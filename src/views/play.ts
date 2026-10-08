import qrcode from 'qrcode-generator';
import { mashupInfo, parseMashupId, randomMashup } from '../data/mashups';
import { appUrl, decodeShare } from '../data/share';
import { getCreation, getSettings, noteWin, notePlayed, saveSettings } from '../data/store';
import { HEROES, WORLDS } from '../engine/registry';
import { ABILITY_LABEL, type GameEvent } from '../engine/types';
import { GameSource, Room, RoomMessage } from '../net/room';
import { PadState, TouchPad, wantsTouchControls } from '../player/controls';
import { EngineRunner } from '../player/engineRunner';
import { Keyboard } from '../player/input';
import { SandboxRunner, parseControls } from '../player/sandbox';
import { unlockAudio } from '../player/sfx';
import { go } from '../router';
import type { Route, View } from '../router';
import { btn, icon } from '../ui/components';
import { clear, copyText, formatTime, h, modal, shareLink, svg, toast } from '../ui/dom';

interface PlayContext {
  source: GameSource;
  title: string;
  /** Library id when the game is one of the player's own creations. */
  libId?: string;
  /** Mashup id for built-in games. */
  mashupId?: string;
  room?: Room;
  host?: boolean;
}

/** Resolve a #/play/... route into something playable. */
async function resolve(route: Route): Promise<PlayContext> {
  const [, a, b] = route.path;
  if (a === 'lib' && b) {
    const c = await getCreation(b);
    if (!c) throw new Error('That game is not in your library on this device.');
    return { source: { kind: 'html', title: c.title, html: c.html, games: c.games }, title: c.title, libId: c.id };
  }
  if (a === 's' && b) {
    const s = await decodeShare(b);
    return { source: { kind: 'html', title: s.title, html: s.html, games: s.games }, title: s.title };
  }
  const p = parseMashupId(a ?? '');
  if (!p) throw new Error('Unknown mashup.');
  const seed = Number(route.query.get('seed')) || undefined;
  return {
    source: { kind: 'engine', hero: p.hero, world: p.world, seed: seed ?? 0, aspect: 0 },
    title: mashupInfo(p.hero, p.world).title,
    mashupId: `${p.hero}-x-${p.world}`,
    host: route.query.get('host') === '1',
  };
}

export const playView: View = async (root, route) => {
  const loading = h('div', { class: 'player' }, h('div', { class: 'overlay' }, h('div', { class: 'spinner' })));
  root.appendChild(loading);
  let ctx: PlayContext;
  try {
    ctx = await resolve(route);
  } catch (err) {
    loading.replaceWith(errorScreen((err as Error).message));
    return;
  }
  loading.remove();
  return startPlayer(root, ctx);
};

export const joinView: View = async (root, route) => {
  const hostId = route.path[1] ?? '';
  const status = h('p', { style: 'color:var(--muted)' }, 'Connecting to the room…');
  const screen = h(
    'div',
    { class: 'player' },
    h('div', { class: 'overlay' }, h('div', { class: 'card' }, h('div', { class: 'big' }, '👥'), h('h2', null, 'Joining game'), status, h('div', { class: 'spinner', style: 'margin:10px auto' }))),
  );
  root.appendChild(screen);
  let joined: Awaited<ReturnType<typeof Room.join>>;
  try {
    joined = await Room.join(hostId);
  } catch (err) {
    screen.replaceWith(errorScreen((err as Error).message || 'Could not join the room.'));
    return;
  }
  screen.remove();
  const { room, source } = joined;
  const title = source.kind === 'engine' ? mashupInfo(source.hero, source.world).title : source.title;
  return startPlayer(root, { source, title, room, mashupId: source.kind === 'engine' ? `${source.hero}-x-${source.world}` : undefined });
};

function errorScreen(message: string): HTMLElement {
  return h(
    'div',
    { class: 'player' },
    h(
      'div',
      { class: 'overlay' },
      h('div', { class: 'card' }, h('div', { class: 'big' }, '😵'), h('p', null, message), h('div', { class: 'btn-row', style: 'justify-content:center' }, btn('Home', { href: '#/', class: 'primary' }))),
    ),
  );
}

function startPlayer(root: HTMLElement, ctx: PlayContext): () => void {
  const settings = getSettings();
  const stage = h('div', { class: 'stage' });
  const banner = h('div', { class: 'banner', style: 'opacity:0' });
  const race = h('div', { class: 'race', style: 'display:none' });
  stage.append(banner, race);

  const hearts = h('span', { class: 'hearts' });
  const goalText = h('div', { class: 'gt' });
  const goalBar = h('i', { style: 'width:0%' });
  const stat = h('span', { class: 'stat' });
  const extra = h('span', { class: 'stat' });
  const hud = h('div', { class: 'hud' }, hearts, h('div', { class: 'goal' }, goalText, h('div', { class: 'bar' }, goalBar)), extra, stat);

  const soundBtn = h('button', { class: 'btn icon ghost', type: 'button', title: 'Sound', 'aria-label': 'Toggle sound' });
  const setSoundIcon = () => soundBtn.replaceChildren(icon(getSettings().sound ? 'sound' : 'mute'));
  setSoundIcon();
  soundBtn.addEventListener('click', () => {
    saveSettings({ sound: !getSettings().sound });
    setSoundIcon();
  });

  const player = h('div', { class: 'player' });
  const touch = wantsTouchControls();
  player.classList.toggle('touch', touch);

  const top = h(
    'div',
    { class: 'ptop' },
    h(
      'button',
      {
        class: 'btn icon ghost',
        type: 'button',
        title: 'Back',
        'aria-label': 'Back',
        onClick: () => (history.length > 1 ? history.back() : go('#/')),
      },
      icon('back'),
    ),
    h('div', { class: 'ptitle' }, ctx.title),
    hud,
    h(
      'div',
      { class: 'pbtns' },
    h('button', { class: 'btn icon ghost', type: 'button', title: 'Play with friends', 'aria-label': 'Play with friends', onClick: () => void openInvite() }, icon('users')),
    soundBtn,
    h(
      'button',
      {
        class: 'btn icon ghost',
        type: 'button',
        title: 'Touch controls',
        'aria-label': 'Toggle touch controls',
        onClick: () => player.classList.toggle('touch'),
      },
      icon('gamepad'),
    ),
    document.fullscreenEnabled
      ? h(
          'button',
          {
            class: 'btn icon ghost',
            type: 'button',
            title: 'Fullscreen',
            'aria-label': 'Fullscreen',
            onClick: () => (document.fullscreenElement ? document.exitFullscreen() : player.requestFullscreen().catch(() => {})),
          },
          icon('expand'),
        )
      : null,
    ),
  );

  player.append(top, stage);
  root.appendChild(player);
  const unlock = () => unlockAudio();
  player.addEventListener('pointerdown', unlock);
  window.addEventListener('keydown', unlock);

  const cleanups: (() => void)[] = [
    () => player.removeEventListener('pointerdown', unlock),
    () => window.removeEventListener('keydown', unlock),
  ];
  let room = ctx.room;
  let overlay: HTMLElement | null = null;

  const showOverlay = (...content: (Node | string | null)[]) => {
    overlay?.remove();
    overlay = h('div', { class: 'overlay' }, h('div', { class: 'card' }, ...content));
    stage.appendChild(overlay);
  };
  const hideOverlay = () => {
    overlay?.remove();
    overlay = null;
  };

  // ------------------------------------------------------------------ engine games
  let engine: EngineRunner | null = null;
  let sandbox: SandboxRunner | null = null;
  let pad: TouchPad | null = null;
  const src = ctx.source;

  if (src.kind === 'engine') {
    const onEvent = (e: GameEvent) => {
      if (e.type === 'won' || e.type === 'lost') setTimeout(() => endScreen(e.type === 'won', e.score, e.time), 600);
    };
    // Add the pad first so the game measures the space that is really left.
    const set = HEROES[src.hero].buttons[WORLDS[src.world].view];
    pad = new TouchPad(
      { a: set[0] && ABILITY_LABEL[set[0]], b: set[1] && ABILITY_LABEL[set[1]], c: set[2] && ABILITY_LABEL[set[2]] },
      (s) => engine?.setPad(s),
    );
    player.appendChild(pad.el);
    engine = new EngineRunner(stage, {
      heroId: src.hero,
      worldId: src.world,
      seed: src.seed || undefined,
      aspect: src.aspect || undefined,
      onEvent,
    });
    stage.prepend(engine.canvas);
    engine.start();
    if (ctx.mashupId) notePlayed(ctx.mashupId);

    const hudTimer = setInterval(() => {
      if (!engine) return;
      const g = engine.game;
      const hp = Math.max(0, g.hero.hp);
      hearts.textContent = '♥'.repeat(hp) + '♡'.repeat(Math.max(0, g.hero.maxHp - hp));
      const goal = g.goal();
      goalText.textContent = goal.text;
      goalBar.style.width = `${Math.round(goal.progress * 100)}%`;
      stat.textContent = `${formatTime(g.time)} · ${g.score}`;
      extra.textContent = g.heroDef.buttons[g.view].includes('place') ? `🧱${g.hero.blocks}` : '';
      if (g.bannerT > 0) {
        banner.textContent = g.bannerText;
        banner.style.opacity = '1';
      } else banner.style.opacity = '0';
    }, 100);
    cleanups.push(() => clearInterval(hudTimer));

    const endScreen = (won: boolean, score: number, time: number) => {
      if (!engine) return;
      const best = won && ctx.mashupId ? noteWin(ctx.mashupId, score, time) : false;
      const next = randomMashup();
      showOverlay(
        h('div', { class: 'big' }, won ? '🏆' : '💀'),
        h('h2', null, won ? 'Mashup cleared!' : 'Game over'),
        h('p', { style: 'color:var(--muted)' }, `Time ${formatTime(time)} · Score ${score}`),
        best ? h('p', { class: 'pill ok' }, 'New personal best!') : null,
        h(
          'div',
          { class: 'btn-row', style: 'justify-content:center;margin-top:12px' },
          btn(won ? 'Play again' : 'Try again', {
            class: 'primary',
            icon: 'refresh',
            onClick: () => {
              hideOverlay();
              engine?.restart();
            },
          }),
          btn('Next mashup', { icon: 'dice', href: `#/play/${next.hero}-x-${next.world}` }),
          won && ctx.mashupId
            ? btn('Share', {
                icon: 'share',
                onClick: () => void shareLink(appUrl(`/m/${ctx.mashupId}`), ctx.title, `I cleared ${ctx.title} in ${formatTime(time)} with ${score} points on Combiner. Beat that!`),
              })
            : null,
        ),
      );
    };
  } else {
    // ------------------------------------------------------------------ AI games
    const meta = parseControls(src.html);
    let lastError = '';
    const errBar = h('div', { class: 'banner', style: 'opacity:0;top:auto;bottom:12px;pointer-events:auto;display:flex;gap:8px;align-items:center' });
    stage.appendChild(errBar);
    sandbox = new SandboxRunner(stage, src.html, {
      onError: (message, line) => {
        if (message === lastError) return;
        lastError = message;
        errBar.replaceChildren(
          ...[
          h('span', { class: 'err' }, `⚠️ ${message}${line ? ` (line ${line})` : ''}`),
          ctx.libId
            ? btn('Fix with AI', {
                class: 'small primary',
                icon: 'wand',
                href: `#/create?edit=${ctx.libId}&fix=${encodeURIComponent(`${message}${line ? ` (line ${line})` : ''}`)}`,
              })
            : null,
          btn('', { class: 'small icon ghost', icon: 'close', title: 'Dismiss', onClick: () => (errBar.style.opacity = '0') }),
          ].filter((x): x is HTMLElement => !!x),
        );
        errBar.style.opacity = '1';
      },
      onScore: (score) => {
        stat.textContent = `Score ${score}`;
      },
      onOver: (won, score) => {
        stat.textContent = `${won ? '🏆' : '💀'} ${score}`;
      },
      onNetSend: (data) => room?.send({ k: 'g', d: data }),
      onReady: () => {
        if (room) sandbox?.setPlayers([...room.peers.values()], room.me.id, room.isHost);
      },
    });
    goalText.textContent = src.games ? src.games.join(' × ') : 'AI mashup';
    hearts.textContent = '✨';
    if (!meta.touch) {
      let padState: PadState = { x: 0, y: 0, a: false, b: false, c: false };
      const kb = new Keyboard();
      const sync = () => {
        const k = kb.read();
        sandbox?.sendInput({ x: Math.max(-1, Math.min(1, padState.x + k.x)), y: Math.max(-1, Math.min(1, padState.y + k.y)), a: padState.a || k.a, b: padState.b || k.b, c: padState.c || k.c });
      };
      pad = new TouchPad(meta.labels, (s) => {
        padState = s;
        sync();
      });
      player.appendChild(pad.el);
      // When the parent page has focus (e.g. after tapping the HUD), forward
      // arrow keys / Space / X / C into the game.
      kb.attach();
      const t = setInterval(sync, 50);
      cleanups.push(() => {
        clearInterval(t);
        kb.detach();
      });
    } else {
      player.classList.remove('touch');
    }
    stage.addEventListener('pointerdown', () => sandbox?.focus());
  }

  // ------------------------------------------------------------------ multiplayer

  const raceRows = () => {
    if (!room) return;
    race.style.display = 'block';
    const rows: HTMLElement[] = [];
    for (const p of room.peers.values()) {
      const isMe = p.id === room.me.id;
      const ghost = engine?.game.ghosts.get(p.id);
      const prog = isMe ? (engine?.game.goal().progress ?? 0) : (ghost?.progress ?? 0);
      const done = isMe ? engine?.game.state === 'won' : ghost?.done;
      rows.push(
        h(
          'div',
          { class: 'row' },
          h('span', { class: 'dot', style: `background:${p.color}` }),
          h('span', { style: 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:80px' }, `${p.name}${isMe ? ' (you)' : ''}`),
          src.kind === 'engine' ? h('div', { class: 'bar' }, h('i', { style: `width:${Math.round(prog * 100)}%` })) : null,
          done ? '🏁' : null,
        ),
      );
    }
    race.replaceChildren(h('div', { style: 'margin-bottom:4px;color:var(--muted)' }, `👥 ${room.peers.size} playing`), ...rows);
  };

  const attachRoom = (r: Room) => {
    room = r;
    const offs = [
      r.on('roster', () => {
        if (engine) for (const id of [...engine.game.ghosts.keys()]) if (!r.peers.has(id)) engine.game.ghosts.delete(id);
        if (sandbox) sandbox.setPlayers([...r.peers.values()], r.me.id, r.isHost);
        raceRows();
      }),
      r.on('join', (m) => toast(`${r.peers.get(m.from!)?.name ?? 'Someone'} joined!`)),
      r.on('leave', () => raceRows()),
      r.on('closed', () => toast('The host left the room.')),
      r.on('error', (m) => toast(String(m.message))),
      r.on('st', (m: RoomMessage) => {
        if (!engine || !m.from) return;
        const p = r.peers.get(m.from);
        const prev = engine.game.ghosts.get(m.from);
        engine.game.ghosts.set(m.from, {
          name: p?.name ?? 'Player',
          color: p?.color ?? '#fff',
          x: Number(m.x),
          y: Number(m.y),
          face: Number(m.f) || 1,
          progress: Number(m.p) || 0,
          hp: Number(m.hp) || 0,
          done: !!m.d,
          seen: performance.now(),
        });
        if (m.d && !prev?.done) toast(`🏁 ${p?.name ?? 'Someone'} finished!`);
      }),
      r.on('g', (m) => sandbox?.deliverNet(String(m.from), m.d)),
      r.on('restart', (m) => {
        hideOverlay();
        engine?.restart(Number(m.seed));
        engine?.game.ghosts.clear();
        toast('New race started!');
      }),
    ];
    if (engine) {
      const t = setInterval(() => {
        if (!engine) return;
        r.send({ k: 'st', ...engine.game.snapshot() });
        raceRows();
      }, 100);
      offs.push(() => clearInterval(t));
    }
    raceRows();
    cleanups.push(() => {
      offs.forEach((f) => f());
      r.close();
    });
  };

  const openInvite = async () => {
    if (!room) {
      toast('Opening a room…');
      try {
        const r = await Room.host(() => {
          if (src.kind === 'engine' && engine) return { kind: 'engine', hero: src.hero, world: src.world, seed: engine.game.seed, aspect: engine.aspect };
          return src;
        });
        attachRoom(r);
      } catch (err) {
        toast((err as Error).message || 'Could not open a room');
        return;
      }
    }
    if (!room) return;
    const link = appUrl(`/join/${room.hostId}`);
    const qr = qrcode(0, 'M');
    qr.addData(link);
    qr.make();
    const input = h('input', { class: 'input', readonly: true, value: link, onFocus: (e: Event) => (e.target as HTMLInputElement).select() });
    const m = modal(
      h('h2', null, '👥 Play together'),
      h(
        'p',
        { class: 'hint' },
        room.isHost
          ? 'Send this link to friends. They open it on any phone or computer and join instantly — no install, no account.'
          : 'Share this link to invite more people to the host’s room.',
      ),
      h('div', { class: 'qr' }, svg(qr.createSvgTag({ cellSize: 4, margin: 1, scalable: true }))),
      h(
        'div',
        { class: 'linkbox' },
        input,
        btn('', { class: 'icon', icon: 'copy', title: 'Copy link', onClick: async () => toast((await copyText(link)) ? 'Invite link copied!' : 'Copy failed') }),
      ),
      h(
        'div',
        { class: 'btn-row' },
        btn('Share invite', { class: 'primary', icon: 'share', onClick: () => void shareLink(link, `Play ${ctx.title} with me`, `Join my ${ctx.title} game on Combiner!`) }),
        room.isHost && engine
          ? btn('Restart race for everyone', {
              icon: 'refresh',
              onClick: () => {
                const seed = (Math.random() * 1e9) >>> 0;
                room!.send({ k: 'restart', seed });
                engine?.restart(seed);
                engine?.game.ghosts.clear();
                hideOverlay();
                m.close();
              },
            })
          : null,
        btn('Close', { class: 'ghost', onClick: () => m.close() }),
      ),
      h('p', { class: 'hint', style: 'margin-top:12px' }, `You appear as “${settings.name}”. Change your name in Settings.`),
    );
  };

  if (ctx.room) attachRoom(ctx.room);
  if (ctx.host) void openInvite();

  return () => {
    cleanups.forEach((f) => f());
    engine?.destroy();
    sandbox?.destroy();
    if (document.fullscreenElement) void document.exitFullscreen().catch(() => {});
    clear(root);
  };
}

