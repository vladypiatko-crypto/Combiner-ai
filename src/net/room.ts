import type { DataConnection, Peer as PeerType, PeerOptions } from 'peerjs';
import { getSettings } from '../data/store';

// Peer-to-peer rooms over WebRTC. The free public PeerJS server is only used
// to introduce players; game data flows directly between devices. The host
// relays messages so everyone can talk to everyone (a simple star).

export interface PeerInfo {
  id: string;
  name: string;
  color: string;
}

/** What the host sends a guest so they can load the same game. */
export type GameSource =
  | { kind: 'engine'; hero: string; world: string; seed: number; aspect: number }
  | { kind: 'html'; title: string; html: string; games?: [string, string] };

export interface RoomMessage {
  k: string;
  from?: string;
  [key: string]: unknown;
}

type Handler = (msg: RoomMessage) => void;

const RELAY = new Set(['st', 'g', 'emote']);

function iceServers(): RTCIceServer[] {
  const s = getSettings();
  const list: RTCIceServer[] = [{ urls: 'stun:stun.l.google.com:19302' }, { urls: 'stun:stun.cloudflare.com:3478' }];
  if (s.turnUrl) list.push({ urls: s.turnUrl, username: s.turnUser, credential: s.turnPass });
  return list;
}

function makeId(): string {
  const a = new Uint8Array(6);
  crypto.getRandomValues(a);
  return 'cmb-' + Array.from(a, (b) => (b % 36).toString(36)).join('');
}

async function newPeer(id?: string): Promise<PeerType> {
  const { Peer } = await import('peerjs');
  const opts: PeerOptions = { config: { iceServers: iceServers() }, debug: 0 };
  const peer = id ? new Peer(id, opts) : new Peer(opts);
  await new Promise<void>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('Could not reach the matchmaking server. Check your connection.')), 12000);
    peer.once('open', () => {
      clearTimeout(t);
      resolve();
    });
    peer.once('error', (e) => {
      clearTimeout(t);
      reject(e);
    });
  });
  return peer;
}

export class Room {
  readonly me: PeerInfo;
  readonly isHost: boolean;
  readonly hostId: string;
  peers = new Map<string, PeerInfo>();
  private conns = new Map<string, DataConnection>();
  private handlers = new Map<string, Set<Handler>>();
  private closed = false;

  private constructor(
    private peer: PeerType,
    isHost: boolean,
    hostId: string,
    private source: () => GameSource,
  ) {
    const s = getSettings();
    this.me = { id: peer.id, name: s.name, color: s.color };
    this.isHost = isHost;
    this.hostId = hostId;
    this.peers.set(this.me.id, this.me);
    peer.on('error', (e) => this.emit({ k: 'error', message: friendlyError(e) }));
    peer.on('disconnected', () => {
      if (!this.closed) peer.reconnect();
    });
  }

  /** Host a room for the given game. */
  static async host(source: () => GameSource): Promise<Room> {
    const peer = await newPeer(makeId());
    const room = new Room(peer, true, peer.id, source);
    peer.on('connection', (conn) => room.acceptGuest(conn));
    return room;
  }

  /** Join a room by the host's id. Resolves once the host sent the game. */
  static async join(hostId: string): Promise<{ room: Room; source: GameSource }> {
    const peer = await newPeer();
    let resolveSource: (s: GameSource) => void = () => {};
    const sourceReady = new Promise<GameSource>((r) => (resolveSource = r));
    const room = new Room(peer, false, hostId, () => {
      throw new Error('guest has no source');
    });
    const conn = peer.connect(hostId, { reliable: true });
    const opened = new Promise<void>((resolve, reject) => {
      const t = setTimeout(() => reject(new Error('The host did not answer. The room may be closed.')), 15000);
      conn.once('open', () => {
        clearTimeout(t);
        resolve();
      });
      peer.once('error', (e) => {
        clearTimeout(t);
        reject(new Error(friendlyError(e)));
      });
    });
    await opened;
    room.conns.set(hostId, conn);
    conn.on('data', (d) => {
      const msg = d as RoomMessage;
      if (msg.k === 'welcome') resolveSource(msg.source as GameSource);
      room.handle(msg, hostId);
    });
    conn.on('close', () => room.emit({ k: 'closed' }));
    conn.send({ k: 'hello', name: room.me.name, color: room.me.color });
    const source = await Promise.race([
      sourceReady,
      new Promise<GameSource>((_, rej) => setTimeout(() => rej(new Error('The host never sent the game.')), 15000)),
    ]);
    return { room, source };
  }

  private acceptGuest(conn: DataConnection): void {
    conn.on('data', (d) => {
      const msg = d as RoomMessage;
      if (msg.k === 'hello') {
        this.conns.set(conn.peer, conn);
        this.peers.set(conn.peer, { id: conn.peer, name: String(msg.name || 'Guest').slice(0, 20), color: String(msg.color || '#fff') });
        conn.send({ k: 'welcome', source: this.source(), roster: [...this.peers.values()] });
        this.broadcastRoster();
        this.emit({ k: 'join', from: conn.peer });
        return;
      }
      this.handle(msg, conn.peer);
    });
    conn.on('close', () => {
      this.conns.delete(conn.peer);
      this.peers.delete(conn.peer);
      this.broadcastRoster();
      this.emit({ k: 'leave', from: conn.peer });
    });
  }

  private broadcastRoster(): void {
    const roster = [...this.peers.values()];
    for (const c of this.conns.values()) if (c.open) c.send({ k: 'roster', roster });
    this.emit({ k: 'roster', roster });
  }

  private handle(msg: RoomMessage, via: string): void {
    if (!msg || typeof msg.k !== 'string') return;
    if (this.isHost) {
      msg.from = via;
      if (RELAY.has(msg.k)) for (const [id, c] of this.conns) if (id !== via && c.open) c.send(msg);
    } else if (msg.k === 'roster') {
      this.peers = new Map((msg.roster as PeerInfo[]).map((p) => [p.id, p]));
    } else if (msg.k === 'welcome') {
      this.peers = new Map((msg.roster as PeerInfo[]).map((p) => [p.id, p]));
      this.emit({ k: 'roster', roster: msg.roster });
      return;
    }
    if (!msg.from) msg.from = via;
    this.emit(msg);
  }

  /** Send to everyone else in the room. */
  send(msg: RoomMessage): void {
    msg.from = this.me.id;
    for (const c of this.conns.values()) if (c.open) c.send(msg);
  }

  on(k: string, fn: Handler): () => void {
    let set = this.handlers.get(k);
    if (!set) this.handlers.set(k, (set = new Set()));
    set.add(fn);
    return () => set!.delete(fn);
  }

  private emit(msg: RoomMessage): void {
    this.handlers.get(msg.k)?.forEach((fn) => fn(msg));
    this.handlers.get('*')?.forEach((fn) => fn(msg));
  }

  close(): void {
    this.closed = true;
    for (const c of this.conns.values()) c.close();
    this.peer.destroy();
  }
}

function friendlyError(e: unknown): string {
  const type = (e as { type?: string }).type;
  if (type === 'peer-unavailable') return 'Room not found — the host may have left.';
  if (type === 'network' || type === 'server-error' || type === 'socket-error') return 'Network problem talking to the matchmaking server.';
  if (type === 'browser-incompatible') return 'This browser does not support peer-to-peer games.';
  return (e as Error).message || 'Connection error';
}
