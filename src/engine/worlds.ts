import { BLOCK, BREAK, EMPTY, Rng, TILE, WALL, clamp, isSolid, len, makeEnt } from './core';
import type { Game } from './game';
import { Level, Theme, TileStyle } from './level';
import type { WorldDef } from './types';

// Art ids index into VARIANTS (0 = tile default).
export const ART = {
  GRASS: 1,
  DIRT: 2,
  STONE: 3,
  ORE: 4,
  WOOD: 5,
  LEAVES: 6,
  BEDROCK: 7,
  GROUND: 8,
  BRICK: 9,
  QUESTION: 10,
  PIPE: 11,
  TREE: 12,
  ROCK: 13,
  WATER: 14,
  RUIN: 15,
  CRACK: 16,
  MAZE: 17,
  STEEL: 18,
  HEDGE: 19,
  STAIR: 20,
  TURF: 21,
  ROW0: 22,
} as const;

const ROW_COLORS: [string, string, string][] = [
  ['#ff5d73', '#ff8fa0', '#c23a4f'],
  ['#ff9f43', '#ffc078', '#c97520'],
  ['#ffd43b', '#ffe580', '#c9a514'],
  ['#51cf66', '#8ce99a', '#2f9e44'],
  ['#339af0', '#74c0fc', '#1c6fb8'],
  ['#845ef7', '#b197fc', '#5f3dc4'],
  ['#f06595', '#faa2c1', '#c2255c'],
  ['#22b8cf', '#66d9e8', '#0c8599'],
];

export const VARIANTS: TileStyle[] = [];
VARIANTS[ART.GRASS] = { c: ['#8a5a35', '#7cc855', '#6b4428'], p: 'grass' };
VARIANTS[ART.DIRT] = { c: ['#8a5a35', '#a8744a', '#6b4428'], p: 'dirt' };
VARIANTS[ART.STONE] = { c: ['#7d7f86', '#9a9ca3', '#5c5e64'], p: 'stone' };
VARIANTS[ART.ORE] = { c: ['#7d7f86', '#9a9ca3', '#5c5e64'], p: 'ore' };
VARIANTS[ART.WOOD] = { c: ['#8b6235', '#a97b47', '#674623'], p: 'wood' };
VARIANTS[ART.LEAVES] = { c: ['#3f8f3a', '#5cb356', '#2c6b28'], p: 'leaves' };
VARIANTS[ART.BEDROCK] = { c: ['#3b3b40', '#55555c', '#232327'], p: 'stone' };
VARIANTS[ART.GROUND] = { c: ['#c8763c', '#e89a5c', '#8f4f22'], p: 'brick' };
VARIANTS[ART.BRICK] = { c: ['#b8562b', '#d9774a', '#7f3615'], p: 'brick' };
VARIANTS[ART.QUESTION] = { c: ['#f2b81f', '#ffd966', '#b5820b'], p: 'question' };
VARIANTS[ART.PIPE] = { c: ['#3fae3a', '#86e07f', '#1f6e1c'], p: 'pipe' };
VARIANTS[ART.TREE] = { c: ['#2f6b3a', '#4d9457', '#1d4524'], p: 'tree' };
VARIANTS[ART.ROCK] = { c: ['#8d8f94', '#b4b6ba', '#606266'], p: 'rock' };
VARIANTS[ART.WATER] = { c: ['#3b6ea8', '#6a9bd4', '#24507f'], p: 'water' };
VARIANTS[ART.RUIN] = { c: ['#9e9581', '#bfb6a0', '#6f6857'], p: 'ruin' };
VARIANTS[ART.CRACK] = { c: ['#8f8673', '#ada48e', '#5e5848'], p: 'ruin' };
VARIANTS[ART.MAZE] = { c: ['#14185c', '#4d6bff', '#0b0d33'], p: 'maze' };
VARIANTS[ART.STEEL] = { c: ['#59607a', '#8b93ad', '#363b4d'], p: 'steel' };
VARIANTS[ART.HEDGE] = { c: ['#2f7a2a', '#4fa847', '#1d5219'], p: 'hedge' };
VARIANTS[ART.STAIR] = { c: ['#9c6b3c', '#c08b58', '#6b4522'], p: 'stone' };
VARIANTS[ART.TURF] = { c: ['#d9b26f', '#79c35a', '#a8823f'], p: 'grass' };
ROW_COLORS.forEach((c, i) => (VARIANTS[ART.ROW0 + i] = { c, p: 'plain' }));

const PLANK: TileStyle = { c: ['#c9a26b', '#e0bd87', '#9c7a48'], p: 'plank' };

function theme(bg: [string, string], decor: Theme['decor'], wall: number, brk: number, ground?: string): Theme {
  return {
    bg,
    decor,
    ground,
    tiles: { [WALL]: VARIANTS[wall], [BREAK]: VARIANTS[brk], [BLOCK]: PLANK },
    variants: VARIANTS,
  };
}

/** Pick level dimensions that fill the player's screen shape. */
function dims(aspect: number, short: number, min: number, max: number): [number, number] {
  return aspect < 1 ? [short, clamp(Math.round(short / aspect), min, max)] : [clamp(Math.round(short * aspect), min, max), short];
}

/** Carve L-shaped corridors so every target is reachable from the start (top-down worlds). */
function ensureReachable(L: Level, sx: number, sy: number, targets: [number, number][]): void {
  const seen = new Uint8Array(L.w * L.h);
  const q: number[] = [sx, sy];
  seen[sy * L.w + sx] = 1;
  while (q.length) {
    const y = q.pop()!;
    const x = q.pop()!;
    for (const [dx, dy] of [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ]) {
      const nx = x + dx;
      const ny = y + dy;
      if (!L.inside(nx, ny) || seen[ny * L.w + nx] || isSolid(L.get(nx, ny))) continue;
      seen[ny * L.w + nx] = 1;
      q.push(nx, ny);
    }
  }
  for (const [tx, ty] of targets) {
    if (seen[ty * L.w + tx]) continue;
    let x = sx;
    let y = sy;
    while (x !== tx) {
      if (L.get(x, y) !== EMPTY && x > 0 && x < L.w - 1) L.set(x, y, EMPTY);
      x += Math.sign(tx - x);
    }
    while (y !== ty) {
      if (L.get(x, y) !== EMPTY && y > 0 && y < L.h - 1) L.set(x, y, EMPTY);
      y += Math.sign(ty - y);
    }
  }
}

function randomFreeTile(game: Game, rng: Rng, minDistTiles: number, margin = 1): [number, number] {
  const L = game.level;
  const [hx, hy] = game.heroCenter();
  for (let i = 0; i < 200; i++) {
    const tx = rng.int(margin, L.w - 1 - margin);
    const ty = rng.int(margin, L.h - 1 - margin);
    if (L.get(tx, ty) !== EMPTY) continue;
    if (len(tx * TILE + 8 - hx, ty * TILE + 8 - hy) < minDistTiles * TILE) continue;
    if (game.hero.segs.some((s) => s.x === tx && s.y === ty)) continue;
    if (game.ents.some((e) => !e.dead && Math.floor((e.x + e.w / 2) / TILE) === tx && Math.floor((e.y + e.h / 2) / TILE) === ty)) continue;
    return [tx, ty];
  }
  return [Math.floor(L.w / 2), 1];
}

// ======================================================================
// Blockcraft — blocky overworld with caves, trees, zombies and creepers.
// ======================================================================

const blockcraft: WorldDef = {
  id: 'blockcraft',
  name: 'Blockcraft',
  view: 'side',
  objective: 'Find 8 diamonds — watch out for creepers!',
  build(game, rng) {
    const W = 150;
    const H = 44;
    const L = new Level(W, H, 'side', theme(['#6fb4ff', '#cfe9ff'], 'clouds', ART.BEDROCK, ART.DIRT));
    const surf: number[] = [];
    let s = 22;
    for (let x = 0; x < W; x++) {
      if (x > 8 && rng.chance(0.38)) s += rng.pick([-1, 1]);
      s = clamp(s, 15, 27);
      surf[x] = s;
    }
    for (let x = 0; x < W; x++) {
      for (let y = surf[x]; y < H; y++) {
        if (y === H - 1) L.set(x, y, WALL, ART.BEDROCK);
        else if (y === surf[x]) L.set(x, y, BREAK, ART.GRASS);
        else if (y <= surf[x] + 3) L.set(x, y, BREAK, ART.DIRT);
        else L.set(x, y, BREAK, rng.chance(0.05) ? ART.ORE : ART.STONE);
      }
    }
    // Caves.
    for (let i = 0; i < 8; i++) {
      let x = rng.int(14, W - 10);
      let y = rng.int(surf[x] + 6, H - 6);
      let a = rng.range(0, Math.PI * 2);
      for (let step = 0; step < 55; step++) {
        const r = rng.chance(0.3) ? 2 : 1;
        for (let dy = -r; dy <= r; dy++)
          for (let dx = -r; dx <= r; dx++) {
            const tx = Math.round(x) + dx;
            const ty = Math.round(y) + dy;
            if (tx > 0 && tx < W - 1 && ty > surf[clamp(tx, 0, W - 1)] + 3 && ty < H - 2) L.set(tx, ty, EMPTY);
          }
        a += rng.range(-0.6, 0.6);
        x = clamp(x + Math.cos(a), 2, W - 3);
        y = clamp(y + Math.sin(a) * 0.6, 4, H - 3);
      }
    }
    // Trees.
    const treeCols = new Set<number>();
    for (let x = 12; x < W - 4; x += rng.int(8, 14)) {
      if (surf[x - 1] !== surf[x] || surf[x + 1] !== surf[x]) continue;
      const g = surf[x];
      for (let y = g - 3; y < g; y++) L.set(x, y, BREAK, ART.WOOD);
      for (let y = g - 5; y <= g - 4; y++) for (let dx = -1; dx <= 1; dx++) L.set(x + dx, y, BREAK, ART.LEAVES);
      L.set(x, g - 6, BREAK, ART.LEAVES);
      treeCols.add(x);
    }
    L.spawn = { x: 3 * TILE, y: (surf[3] - 1) * TILE - 2 };
    // Diamonds on the surface (enough to win without digging: not every hero can mine)…
    for (let i = 0; i < 9; i++) {
      let x = 18 + i * 14 + rng.int(-3, 3);
      while (treeCols.has(x)) x++;
      game.pickup('diamond', x * TILE + 8, (surf[x] - 1) * TILE + 8);
    }
    // …and in caves.
    const cave: [number, number][] = [];
    for (let x = 10; x < W - 2; x++)
      for (let y = surf[x] + 5; y < H - 2; y++) if (L.get(x, y) === EMPTY && L.get(x, y - 1) === EMPTY && isSolid(L.get(x, y + 1))) cave.push([x, y]);
    for (let i = 0; i < 4 && cave.length; i++) {
      const [x, y] = cave.splice(rng.int(0, cave.length - 1), 1)[0];
      game.pickup('diamond', x * TILE + 8, y * TILE + 8);
    }
    for (let i = 0; i < 12; i++) {
      const x = 24 + i * 10 + rng.int(0, 4);
      if (x >= W - 2) break;
      const creeper = i % 3 === 2;
      game.spawn(
        makeEnt('enemy', creeper ? 'creeper' : 'zombie', x * TILE + 2, surf[x] * TILE - 20, 12, 20, {
          hp: creeper ? 2 : 3,
          maxHp: creeper ? 2 : 3,
          dir: rng.chance(0.5) ? 1 : -1,
        }),
      );
    }
    return L;
  },
  goal(game) {
    const n = game.counts.diamond ?? 0;
    return { text: `💎 ${Math.min(n, 8)}/8 diamonds`, progress: Math.min(1, n / 8), done: n >= 8 };
  },
};

// ======================================================================
// Dragon Realm — top-down tundra with ruins, word walls and a dragon.
// ======================================================================

const dragonrealm: WorldDef = {
  id: 'dragonrealm',
  name: 'Dragon Realm',
  view: 'top',
  objective: 'Read 3 word walls in the ruins, then slay the dragon',
  build(game, rng) {
    const W = 64;
    const H = 64;
    const L = new Level(W, H, 'top', theme(['#3d4651', '#3d4651'], 'snow', ART.ROCK, ART.CRACK, '#8fa47a'));
    for (let y = 0; y < H; y++)
      for (let x = 0; x < W; x++) {
        if (x === 0 || y === 0 || x === W - 1 || y === H - 1) L.set(x, y, WALL, ART.TREE);
        else {
          const r = rng.next();
          if (r < 0.055) L.set(x, y, WALL, ART.TREE);
          else if (r < 0.075) L.set(x, y, WALL, ART.ROCK);
        }
      }
    for (let i = 0; i < 3; i++) {
      const cx = rng.int(8, W - 9);
      const cy = rng.int(8, H - 9);
      const r = rng.int(2, 4);
      for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) if (x * x + y * y <= r * r + 1) L.set(cx + x, cy + y, WALL, ART.WATER);
    }
    const sx = W >> 1;
    const sy = H >> 1;
    L.fill(sx - 4, sy - 4, sx + 4, sy + 4, EMPTY);
    L.spawn = { x: sx * TILE, y: sy * TILE };
    const runes: [number, number][] = [];
    const base = rng.range(0, Math.PI * 2);
    for (let i = 0; i < 3; i++) {
      const a = base + (i * Math.PI * 2) / 3 + rng.range(-0.3, 0.3);
      const cx = clamp(Math.round(sx + Math.cos(a) * 20), 8, W - 9);
      const cy = clamp(Math.round(sy + Math.sin(a) * 20), 8, H - 9);
      L.fill(cx - 5, cy - 5, cx + 5, cy + 5, EMPTY);
      for (let d = -4; d <= 4; d++) {
        L.set(cx + d, cy - 4, WALL, ART.RUIN);
        L.set(cx + d, cy + 4, WALL, ART.RUIN);
        L.set(cx - 4, cy + d, WALL, ART.RUIN);
        L.set(cx + 4, cy + d, WALL, ART.RUIN);
      }
      const sides = [0, 1, 2, 3].sort(() => rng.next() - 0.5).slice(0, 2);
      for (const side of sides) {
        for (const o of [0, 1]) {
          if (side === 0) L.set(cx + o, cy - 4, EMPTY);
          if (side === 1) L.set(cx + 4, cy + o, EMPTY);
          if (side === 2) L.set(cx + o, cy + 4, EMPTY);
          if (side === 3) L.set(cx - 4, cy + o, EMPTY);
        }
      }
      for (let k = 0; k < 3; k++) {
        const d = rng.int(-3, 3);
        const side = rng.int(0, 3);
        const [tx, ty] = side === 0 ? [cx + d, cy - 4] : side === 1 ? [cx + 4, cy + d] : side === 2 ? [cx + d, cy + 4] : [cx - 4, cy + d];
        if (L.get(tx, ty) === WALL) L.set(tx, ty, BREAK, ART.CRACK);
      }
      for (let d = -1; d <= 1; d++) L.set(cx + d, cy - 2, WALL, ART.RUIN);
      game.pickup('rune', cx * TILE + 8, cy * TILE + 8);
      runes.push([cx, cy]);
      for (const ox of [-2, 2]) {
        game.spawn(makeEnt('enemy', 'draugr', (cx + ox) * TILE + 1, (cy + 2) * TILE + 1, 13, 13, { hp: 3, maxHp: 3 }));
      }
    }
    ensureReachable(L, sx, sy, runes);
    const place = (type: string, n: number, hp: number, size: number) => {
      for (let i = 0; i < n; i++) {
        for (let tries = 0; tries < 50; tries++) {
          const tx = rng.int(2, W - 3);
          const ty = rng.int(2, H - 3);
          if (L.get(tx, ty) !== EMPTY || len(tx - sx, ty - sy) < 12) continue;
          game.spawn(makeEnt('enemy', type, tx * TILE + 1, ty * TILE + 1, size, size, { hp, maxHp: hp }));
          break;
        }
      }
    };
    place('wolf', 7, 1, 12);
    place('draugr', 4, 3, 13);
    return L;
  },
  update(game) {
    if ((game.counts.rune ?? 0) >= 3 && !game.vars.dragon) {
      game.vars.dragon = 1;
      const [hx, hy] = game.heroCenter();
      game.spawn(
        makeEnt('enemy', 'dragon', clamp(hx - 20, 0, game.level.pxW - 40), clamp(hy - 150, 0, game.level.pxH - 28), 40, 28, {
          hp: 24,
          maxHp: 24,
          data: { heavy: 1, noDrop: 1, score: 2000 },
        }),
      );
      game.banner('A DRAGON APPROACHES!', 2.5);
      game.sfx('shout');
    }
  },
  goal(game) {
    const n = game.counts.rune ?? 0;
    if (!game.vars.dragon) return { text: `ᚱ Word walls ${n}/3`, progress: (n / 3) * 0.5, done: false };
    const d = game.ents.find((e) => e.type === 'dragon' && !e.dead);
    if (!d) return { text: '🐉 Dragon slain!', progress: 1, done: true };
    return { text: `🐉 Dragon ${Math.max(0, d.hp)}/${d.maxHp}`, progress: 0.5 + 0.5 * (1 - d.hp / d.maxHp), done: false };
  },
};

// ======================================================================
// Flappy Wings — autoscrolling pipe gauntlet.
// ======================================================================

const PIPES = 30;
const PERIOD = 5;
const PIPE_X0 = 14;

const flappy: WorldDef = {
  id: 'flappy',
  name: 'Flappy Wings',
  view: 'side',
  objective: 'Make it through 30 pipes — the screen keeps moving!',
  build(game, rng) {
    const H = 18;
    const W = PIPE_X0 + PIPES * PERIOD + 16;
    const L = new Level(W, H, 'side', theme(['#4ec0ca', '#c9f2f4'], 'hills', ART.PIPE, ART.BRICK));
    L.camera = 'autoscroll';
    L.scrollSpeed = 50;
    L.fill(0, H - 3, PIPE_X0 - 3, H - 1, WALL, ART.TURF);
    let bt = H - 5;
    for (let i = 0; i < PIPES; i++) {
      const px = PIPE_X0 + i * PERIOD;
      bt = clamp(bt + rng.int(-1, 2), 7, H - 3);
      const gs = i < 10 ? 6 : 5;
      let gy = bt - gs;
      if (gy < 2) {
        gy = 2;
        bt = gy + gs;
      }
      L.fill(px, 0, px + 1, gy - 1, WALL, ART.PIPE);
      L.fill(px, bt, px + 1, H - 1, WALL, ART.PIPE);
      game.pickup('coin', (px + 3) * TILE + 8, (bt - 3) * TILE + 8);
      if (i >= 8 && i % 3 === 0) {
        game.spawn(makeEnt('enemy', 'bat', (px + 3) * TILE, (gy + 2) * TILE, 12, 10, { hp: 1, maxHp: 1, vx: -14 }));
      }
    }
    const fx = PIPE_X0 + PIPES * PERIOD;
    L.fill(fx, H - 3, W - 1, H - 1, WALL, ART.TURF);
    game.spawn(makeEnt('flag', 'flag', (W - 6) * TILE + 6, (H - 10) * TILE, 6, 7 * TILE));
    L.spawn = { x: 4 * TILE, y: (H - 4) * TILE };
    return L;
  },
  update(game) {
    const passed = Math.floor((game.hero.x / TILE - PIPE_X0 - 2) / PERIOD) + 1;
    game.vars.passed = clamp(Math.max(game.vars.passed ?? 0, passed), 0, PIPES);
  },
  goal(game) {
    const n = game.vars.passed ?? 0;
    return { text: `🟩 Pipes ${n}/${PIPES}`, progress: n / PIPES, done: !!game.vars.flag };
  },
};

// ======================================================================
// Super Jumper — classic side-scroller to the flag.
// ======================================================================

const jumper: WorldDef = {
  id: 'jumper',
  name: 'Super Jumper',
  view: 'side',
  objective: 'Run, jump and stomp your way to the flag',
  build(game, rng) {
    const W = 190;
    const H = 16;
    const L = new Level(W, H, 'side', theme(['#5c94fc', '#a9c8ff'], 'clouds', ART.GROUND, ART.BRICK));
    L.fill(0, H - 2, W - 1, H - 1, WALL, ART.GROUND);
    const pit = new Set<number>();
    for (let x = 22; x < W - 32; ) {
      x += rng.int(14, 24);
      const w = rng.int(2, 3);
      for (let i = 0; i < w; i++) {
        L.set(x + i, H - 2, EMPTY);
        L.set(x + i, H - 1, EMPTY);
        pit.add(x + i);
      }
      x += w;
    }
    for (let x = 10; x < W - 30; x += rng.int(6, 10)) {
      if (pit.has(x) || pit.has(x + 1)) continue;
      const r = rng.next();
      if (r < 0.38) {
        const n = rng.int(3, 5);
        for (let i = 0; i < n; i++) L.set(x + i, H - 5, BREAK, rng.chance(0.3) ? ART.QUESTION : ART.BRICK);
        if (rng.chance(0.5)) for (let i = 0; i < n; i += 2) game.pickup('coin', (x + i) * TILE + 8, (H - 6) * TILE + 8);
      } else if (r < 0.55) {
        const h = rng.int(2, 3);
        L.fill(x, H - 2 - h, x + 1, H - 3, WALL, ART.PIPE);
      } else if (r < 0.72) {
        for (let i = 0; i < 3; i++) L.set(x + i, H - 5, BREAK, ART.BRICK);
        for (let i = 0; i < 3; i++) L.set(x + 3 + i, H - 8, BREAK, i === 1 ? ART.QUESTION : ART.BRICK);
        for (let i = 0; i < 3; i++) game.pickup('coin', (x + 3 + i) * TILE + 8, (H - 9) * TILE + 8);
      } else {
        for (let i = 0; i < 4; i++) game.pickup('coin', (x + i) * TILE + 8, (H - 4 - (i === 1 || i === 2 ? 1 : 0)) * TILE + 8);
      }
    }
    const sx = W - 22;
    for (let i = 0; i < 5; i++) L.fill(sx + i, H - 3 - i, sx + i, H - 3, WALL, ART.STAIR);
    game.spawn(makeEnt('flag', 'flag', (W - 10) * TILE + 6, (H - 9) * TILE, 6, 7 * TILE));
    for (let i = 0; i < 18; i++) {
      const x = rng.int(25, W - 26);
      if (pit.has(x) || pit.has(x + 1) || L.get(x, H - 3) !== EMPTY) continue;
      const koopa = rng.chance(0.25);
      game.spawn(
        makeEnt('enemy', koopa ? 'koopa' : 'goomba', x * TILE + 2, (H - 2) * TILE - (koopa ? 15 : 12), 12, koopa ? 15 : 12, {
          hp: koopa ? 3 : 2,
          maxHp: koopa ? 3 : 2,
          dir: -1,
        }),
      );
    }
    game.onTileBroken = (_tx, _ty, art) => {
      if (art === ART.QUESTION) {
        game.counts.coin = (game.counts.coin ?? 0) + 1;
        game.score += 50;
        game.floatText(_tx * TILE, _ty * TILE - 8, '+50', '#ffe066');
        game.sfx('pickup');
      }
    };
    L.spawn = { x: 3 * TILE, y: (H - 3) * TILE - 2 };
    return L;
  },
  goal(game) {
    const end = (game.level.w - 10) * TILE;
    const p = clamp(game.hero.x / end, 0, 1);
    return { text: `🚩 ${Math.round(p * 100)}% to the flag`, progress: p, done: !!game.vars.flag };
  },
};

// ======================================================================
// Snake — fixed arena, apples, growing obstacles.
// ======================================================================

function placeApple(game: Game): void {
  const [tx, ty] = randomFreeTile(game, game.rng, 4);
  game.pickup('apple', tx * TILE + 8, ty * TILE + 8);
}

const snake: WorldDef = {
  id: 'snake',
  name: 'Snake',
  view: 'top',
  objective: 'Eat 15 apples — every apple makes the garden meaner',
  build(game, rng, aspect) {
    const [w, h] = dims(aspect, 18, 18, 32);
    const L = new Level(w, h, 'top', theme(['#2d6a22', '#2d6a22'], 'grid', ART.HEDGE, ART.CRACK, '#7ec850'));
    L.camera = 'fixed';
    for (let x = 0; x < w; x++) {
      L.set(x, 0, WALL, ART.HEDGE);
      L.set(x, h - 1, WALL, ART.HEDGE);
    }
    for (let y = 0; y < h; y++) {
      L.set(0, y, WALL, ART.HEDGE);
      L.set(w - 1, y, WALL, ART.HEDGE);
    }
    L.spawn = { x: (w >> 1) * TILE, y: (h >> 1) * TILE };
    // Obstacles and the first apple keep their distance from the spawn point.
    game.level = L;
    game.hero.x = L.spawn.x;
    game.hero.y = L.spawn.y;
    for (let i = 0; i < 2; i++) {
      const [tx, ty] = randomFreeTile(game, rng, 4, 2);
      L.set(tx, ty, WALL, ART.ROCK);
    }
    placeApple(game);
    return L;
  },
  onPickup(game, type) {
    if (type !== 'apple') return;
    const n = game.counts.apple ?? 0;
    if (n >= 15) return;
    if (n % 2 === 0) {
      const [tx, ty] = randomFreeTile(game, game.rng, 3, 2);
      game.level.set(tx, ty, WALL, ART.ROCK);
    }
    if (n % 3 === 0) {
      const [tx, ty] = randomFreeTile(game, game.rng, 6, 2);
      const sp = 50 + n * 2;
      game.spawn(
        makeEnt('enemy', 'spiky', tx * TILE + 2, ty * TILE + 2, 12, 12, {
          hp: 2,
          maxHp: 2,
          vx: game.rng.chance(0.5) ? sp : -sp,
          vy: game.rng.chance(0.5) ? sp : -sp,
          data: { spiky: 1, speed: sp, noDrop: 1 },
        }),
      );
    }
    placeApple(game);
  },
  goal(game) {
    const n = game.counts.apple ?? 0;
    return { text: `🍎 ${Math.min(n, 15)}/15 apples`, progress: Math.min(1, n / 15), done: n >= 15 };
  },
};

// ======================================================================
// Space Rocks — wrap-around asteroid field.
// ======================================================================

const ROCK_TOTAL = 4 * 7;

const rocks: WorldDef = {
  id: 'rocks',
  name: 'Space Rocks',
  view: 'top',
  objective: 'Smash every space rock — big ones split!',
  build(game, rng, aspect) {
    const [w, h] = dims(aspect, 20, 20, 36);
    const L = new Level(w, h, 'top', theme(['#05040f', '#161038'], 'stars', ART.STEEL, ART.STEEL));
    L.camera = 'fixed';
    L.wrap = true;
    L.spawn = { x: (w / 2) * TILE - 6, y: (h / 2) * TILE - 6 };
    const R = Math.min(L.pxW, L.pxH) * 0.38;
    for (let i = 0; i < 4; i++) {
      const a = (i * Math.PI) / 2 + rng.range(0.2, 1.2);
      const x = L.pxW / 2 + Math.cos(a) * R - 16;
      const y = L.pxH / 2 + Math.sin(a) * R - 16;
      const va = rng.range(0, Math.PI * 2);
      const sp = rng.range(22, 38);
      game.spawn(
        makeEnt('enemy', 'rock', x, y, 32, 32, {
          hp: 3,
          maxHp: 3,
          vx: Math.cos(va) * sp,
          vy: Math.sin(va) * sp,
          data: { size: 3, seed: rng.int(1, 1e6), spin: rng.range(-1.5, 1.5), noDrop: 1, score: 50 },
        }),
      );
    }
    return L;
  },
  goal(game) {
    const left = game.ents.filter((e) => e.type === 'rock' && !e.dead).length;
    const destroyed = game.counts['kill:rock'] ?? 0;
    return { text: `🪨 ${left} rocks left`, progress: Math.min(1, destroyed / ROCK_TOTAL), done: left === 0 && game.time > 0.5 };
  },
};

// ======================================================================
// Brick Breaker — keep the ball alive and clear the wall.
// ======================================================================

const bricks: WorldDef = {
  id: 'bricks',
  name: 'Brick Breaker',
  view: 'side',
  objective: 'Keep the ball bouncing and break every brick',
  build(game, rng, aspect) {
    const [w, h] = aspect < 1 ? [18, clamp(Math.round(18 / aspect), 22, 32)] : [clamp(Math.round(20 * aspect), 22, 34), 20];
    const L = new Level(w, h, 'side', theme(['#0f0c29', '#2b1a55'], 'none', ART.STEEL, ART.ROW0));
    L.camera = 'fixed';
    L.pitBottom = false;
    for (let x = 0; x < w; x++) {
      L.set(x, 0, WALL, ART.STEEL);
      L.set(x, h - 1, WALL, ART.STEEL);
    }
    for (let y = 0; y < h; y++) {
      L.set(0, y, WALL, ART.STEEL);
      L.set(w - 1, y, WALL, ART.STEEL);
    }
    const rows = Math.min(6, Math.floor(h * 0.28));
    for (let r = 0; r < rows; r++) for (let x = 2; x <= w - 3; x++) L.set(x, 3 + r, BREAK, ART.ROW0 + r);
    game.vars.total = rows * (w - 4);
    L.spawn = { x: (w / 2) * TILE - 6, y: (h - 2) * TILE - 2 };
    game.spawn(makeEnt('ball', 'ball', L.spawn.x, L.spawn.y - 40, 8, 8, { data: { speed: 165, wait: 1.5, floor: h - 1 } }));
    game.onTileBroken = (tx, ty) => {
      if (rng.chance(0.1)) game.spawn(makeEnt('proj', 'bomb', tx * TILE + 4, ty * TILE + 8, 8, 8, { dmg: 1 }));
    };
    return L;
  },
  update(game) {
    for (const b of game.ents) {
      if (b.type !== 'ball' || b.data.owner || b.data.wait) continue;
      if (b.y + b.h >= b.data.floor * TILE - 1.5) {
        b.data.wait = 1.2;
        game.banner('Missed the ball!', 1);
        game.damageHero(1, b.x, b.y);
      }
    }
  },
  goal(game) {
    const left = game.level.countTiles(BREAK);
    const total = game.vars.total || 1;
    return { text: `🧱 ${left} bricks left`, progress: 1 - left / total, done: left === 0 };
  },
};

// ======================================================================
// Ghost Maze — eat every dot while ghosts hunt you.
// ======================================================================

const maze: WorldDef = {
  id: 'maze',
  name: 'Ghost Maze',
  view: 'top',
  objective: 'Eat every dot. Big dots let you eat the ghosts!',
  build(game, rng, aspect) {
    let cols: number;
    let rows: number;
    if (aspect < 1) {
      cols = 7;
      rows = clamp(Math.round((cols * 3 + 1) / aspect / 3), 9, 13);
    } else {
      rows = 7;
      cols = clamp(Math.round(((rows * 3 + 1) * aspect) / 3), 9, 13);
    }
    const w = cols * 3 + 1;
    const h = rows * 3 + 1;
    const L = new Level(w, h, 'top', theme(['#000000', '#05051a'], 'none', ART.MAZE, ART.MAZE, '#000000'));
    L.camera = 'fixed';
    L.fill(0, 0, w - 1, h - 1, WALL, ART.MAZE);
    const open = new Uint8Array(cols * rows);
    for (let cy = 0; cy < rows; cy++) for (let cx = 0; cx < cols; cx++) L.fill(1 + 3 * cx, 1 + 3 * cy, 2 + 3 * cx, 2 + 3 * cy, EMPTY);
    const connect = (cx: number, cy: number, dir: 'E' | 'S') => {
      if (dir === 'E') {
        open[cy * cols + cx] |= 2;
        open[cy * cols + cx + 1] |= 8;
        L.fill(3 + 3 * cx, 1 + 3 * cy, 3 + 3 * cx, 2 + 3 * cy, EMPTY);
      } else {
        open[cy * cols + cx] |= 4;
        open[(cy + 1) * cols + cx] |= 1;
        L.fill(1 + 3 * cx, 3 + 3 * cy, 2 + 3 * cx, 3 + 3 * cy, EMPTY);
      }
    };
    const seen = new Uint8Array(cols * rows);
    const stack: [number, number][] = [[0, 0]];
    seen[0] = 1;
    while (stack.length) {
      const [cx, cy] = stack[stack.length - 1];
      const n = (
        [
          [cx + 1, cy],
          [cx - 1, cy],
          [cx, cy + 1],
          [cx, cy - 1],
        ] as [number, number][]
      ).filter(([x, y]) => x >= 0 && y >= 0 && x < cols && y < rows && !seen[y * cols + x]);
      if (!n.length) {
        stack.pop();
        continue;
      }
      const [nx, ny] = rng.pick(n);
      if (nx > cx) connect(cx, cy, 'E');
      else if (nx < cx) connect(nx, ny, 'E');
      else if (ny > cy) connect(cx, cy, 'S');
      else connect(nx, ny, 'S');
      seen[ny * cols + nx] = 1;
      stack.push([nx, ny]);
    }
    for (let cy = 0; cy < rows; cy++)
      for (let cx = 0; cx < cols; cx++) {
        if (cx < cols - 1 && !(open[cy * cols + cx] & 2) && rng.chance(0.24)) connect(cx, cy, 'E');
        if (cy < rows - 1 && !(open[cy * cols + cx] & 4) && rng.chance(0.24)) connect(cx, cy, 'S');
      }
    const hx = cols >> 1;
    const hy = rows >> 1;
    const spx = cols >> 1;
    const spy = rows - 1;
    L.maze = { cols, rows, open, houseX: hx, houseY: hy };
    L.spawn = { x: (1 + 3 * spx) * TILE + 10, y: (1 + 3 * spy) * TILE + 10 };
    let total = 0;
    const corners = new Set([0, cols - 1, (rows - 1) * cols, rows * cols - 1]);
    for (let cy = 0; cy < rows; cy++)
      for (let cx = 0; cx < cols; cx++) {
        const px = (1 + 3 * cx) * TILE + TILE;
        const py = (1 + 3 * cy) * TILE + TILE;
        const isHouse = cx === hx && cy === hy;
        const isSpawn = cx === spx && cy === spy;
        if (!isHouse && !isSpawn) {
          game.pickup(corners.has(cy * cols + cx) ? 'power' : 'pellet', px, py);
          total++;
        }
        if (open[cy * cols + cx] & 2) {
          game.pickup('pellet', (3 + 3 * cx) * TILE + 8, py);
          total++;
        }
        if (open[cy * cols + cx] & 4) {
          game.pickup('pellet', px, (3 + 3 * cy) * TILE + 8);
          total++;
        }
      }
    game.vars.total = total;
    const colors = 4;
    for (let i = 0; i < colors; i++) {
      const px = (1 + 3 * hx) * TILE + TILE - 7;
      const py = (1 + 3 * hy) * TILE + TILE - 7;
      game.spawn(
        makeEnt('enemy', 'ghost', px + (i - 1.5) * 3, py, 14, 14, {
          hp: 2,
          maxHp: 2,
          data: { cx: hx, cy: hy, tx: hx, ty: hy, dx: 0, dy: 0, kind: i, release: 1.5 + i * 3, noDrop: 1, score: 200 },
        }),
      );
    }
    return L;
  },
  goal(game) {
    const eaten = (game.counts.pellet ?? 0) + (game.counts.power ?? 0);
    const total = game.vars.total || 1;
    return { text: `● ${Math.max(0, total - eaten)} dots left`, progress: eaten / total, done: eaten >= total };
  },
};

export const WORLD_DEFS: WorldDef[] = [blockcraft, dragonrealm, flappy, jumper, snake, rocks, bricks, maze];
