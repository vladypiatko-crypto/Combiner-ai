// Share links carry the whole game inside the URL fragment (compressed), so
// sharing needs no server and the fragment is never sent to any host.

export interface SharedGame {
  v: 1;
  title: string;
  tagline?: string;
  games?: [string, string];
  twist?: string;
  html: string;
  multiplayer?: boolean;
}

function toB64Url(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromB64Url(s: string): Uint8Array {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function pipe(bytes: Uint8Array, stream: CompressionStream | DecompressionStream): Promise<Uint8Array> {
  const res = new Response(new Blob([bytes as BlobPart]).stream().pipeThrough(stream));
  return new Uint8Array(await res.arrayBuffer());
}

export async function encodeShare(game: SharedGame): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(game));
  if (typeof CompressionStream !== 'undefined') {
    return 'z' + toB64Url(await pipe(bytes, new CompressionStream('deflate-raw')));
  }
  return 'j' + toB64Url(bytes);
}

export async function decodeShare(payload: string): Promise<SharedGame> {
  const kind = payload[0];
  let bytes = fromB64Url(payload.slice(1));
  if (kind === 'z') {
    if (typeof DecompressionStream === 'undefined') throw new Error('This browser is too old to open compressed links.');
    bytes = await pipe(bytes, new DecompressionStream('deflate-raw'));
  } else if (kind !== 'j') {
    throw new Error('Unknown link format');
  }
  const data = JSON.parse(new TextDecoder().decode(bytes));
  if (!data || typeof data.html !== 'string' || typeof data.title !== 'string') throw new Error('Link is damaged');
  return data as SharedGame;
}

export function appUrl(hash: string): string {
  const base = location.href.split('#')[0];
  return `${base}#${hash}`;
}
