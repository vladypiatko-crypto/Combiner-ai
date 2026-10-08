import { BLOCK, EMPTY, Ent, TILE, approach, clamp, isSolid, len, makeEnt, norm, overlap } from './core';
import type { Game } from './game';
import { moveBody } from './level';
import type { Ability, HeroDef } from './types';

/**
 * Each base game contributes one hero. A hero brings its movement style and
 * abilities into whatever world it is dropped in; movement adapts to the
 * world's camera ("side" has gravity, "top" is a top-down view).
 */
export const HERO_DEFS: HeroDef[] = [
  {
    id: 'blockcraft',
    name: 'Miner',
    w: 12,
    h: 14,
    hp: 5,
    speed: 95,
    jumpV: 345,
    move: { side: 'platform', top: 'free' },
    buttons: { side: ['jump', 'mine', 'place'], top: ['dash', 'mine', 'place'] },
    verbs: 'mine anything breakable and build with blocks',
  },
  {
    id: 'dragonrealm',
    name: 'Knight',
    w: 12,
    h: 14,
    hp: 6,
    speed: 90,
    jumpV: 340,
    move: { side: 'platform', top: 'free' },
    buttons: { side: ['jump', 'sword', 'shout'], top: ['dash', 'sword', 'shout'] },
    verbs: 'swing a sword and blast enemies away with a dragon shout',
  },
  {
    id: 'flappy',
    name: 'Bird',
    w: 12,
    h: 11,
    hp: 4,
    speed: 105,
    move: { side: 'flap', top: 'free' },
    buttons: { side: ['flap', 'peck'], top: ['dash', 'peck'] },
    verbs: 'flap through the air and peck-dash through enemies',
  },
  {
    id: 'jumper',
    name: 'Plumber',
    w: 12,
    h: 14,
    hp: 4,
    speed: 112,
    jumpV: 372,
    move: { side: 'platform', top: 'free' },
    buttons: { side: ['jump', 'fireball'], top: ['hop', 'fireball'] },
    verbs: 'jump high, stomp enemies and throw bouncing fireballs',
  },
  {
    id: 'snake',
    name: 'Snake',
    w: 12,
    h: 12,
    hp: 5,
    speed: 120,
    move: { side: 'grid', top: 'grid' },
    buttons: { side: ['boost'], top: ['boost'] },
    verbs: 'slither on a grid, bite enemies and grow with every pickup',
  },
  {
    id: 'rocks',
    name: 'Ship',
    w: 12,
    h: 12,
    hp: 4,
    speed: 240,
    move: { side: 'thrust', top: 'thrust' },
    buttons: { side: ['warp', 'shoot'], top: ['warp', 'shoot'] },
    verbs: 'thrust around with momentum, shoot and hyperspace-warp',
  },
  {
    id: 'bricks',
    name: 'Paddle',
    w: 26,
    h: 8,
    hp: 5,
    speed: 120,
    move: { side: 'free', top: 'free' },
    buttons: { side: ['dash', 'ball'], top: ['dash', 'ball'] },
    verbs: 'hover around and launch a bouncing ball that smashes everything',
  },
  {
    id: 'maze',
    name: 'Chomper',
    w: 13,
    h: 13,
    hp: 4,
    speed: 100,
    move: { side: 'free', top: 'free' },
    buttons: { side: ['dash', 'power'], top: ['dash', 'power'] },
    verbs: 'gobble pickups and power up to eat enemies',
  },
];

const DEAD_ZONE = 0.18;

function stick(game: Game): [number, number] {
  let { x, y } = game.input;
  const m = len(x, y);
  if (m < DEAD_ZONE) return [0, 0];
  if (m > 1) {
    x /= m;
    y /= m;
  }
  return [x, y];
}

function slotOf(game: Game, ab: Ability): number {
  return game.heroDef.buttons[game.view].indexOf(ab);
}

function slotPressed(game: Game, slot: number): boolean {
  return slot >= 0 && game.pressed((['a', 'b', 'c'] as const)[slot]);
}

function slotHeld(game: Game, slot: number): boolean {
  return slot >= 0 && game.input[(['a', 'b', 'c'] as const)[slot]];
}

/** Axis-snapped aim (mining, placing). */
function aimAxis(game: Game): [number, number] {
  const h = game.hero;
  const [ix, iy] = stick(game);
  if (game.view === 'side') {
    if (Math.abs(iy) > 0.5 && Math.abs(iy) >= Math.abs(ix)) return [0, Math.sign(iy)];
    return [h.face, 0];
  }
  const vx = ix || iy ? ix : h.fx;
  const vy = ix || iy ? iy : h.fy;
  return Math.abs(vx) >= Math.abs(vy) ? [Math.sign(vx) || 1, 0] : [0, Math.sign(vy)];
}

/** Free aim (sword, shout, dashes, fireballs). */
function aimVec(game: Game): [number, number] {
  const h = game.hero;
  const [ix, iy] = stick(game);
  if (game.view === 'side') {
    if (Math.abs(iy) > 0.55 && Math.abs(iy) > Math.abs(ix)) return [0, Math.sign(iy)];
    return [h.face, 0];
  }
  if (ix || iy) return norm(ix, iy);
  return [h.fx, h.fy];
}

export function updateHero(game: Game, dt: number): void {
  const h = game.hero;
  const def = game.heroDef;
  const L = game.level;
  const mode = def.move[game.view];

  h.anim += dt;
  h.inv = Math.max(0, h.inv - dt);
  h.power = Math.max(0, h.power - dt);
  h.attack.t = Math.max(0, h.attack.t - dt);
  for (let i = 0; i < 3; i++) h.cd[i] = Math.max(0, h.cd[i] - dt);
  if (h.dash > 0) h.dash -= dt;
  if (h.hop > 0) {
    h.hop -= dt;
    if (h.hop <= 0) {
      const [cx, cy] = game.heroCenter();
      game.hitRect({ x: cx - 22, y: cy - 22, w: 44, h: 44 }, 2, 200, false);
      game.burst(cx, cy + 6, '#e9d8a6', 10, 80, 0);
      game.addShake(2);
    }
  }

  const [ix, iy] = stick(game);
  if (mode !== 'grid' && mode !== 'thrust' && (ix || iy)) {
    [h.fx, h.fy] = norm(ix, iy);
    if (Math.abs(ix) > 0.2) h.face = Math.sign(ix);
  }

  // Paddles always carry their ball.
  if (def.buttons[game.view].includes('ball') && !game.ents.some((e) => e.id === h.ballId && !e.dead)) {
    const ball = game.spawn(makeEnt('ball', 'ball', h.x, h.y, 8, 8, { friendly: true, data: { held: 1, owner: 1, speed: 215 } }));
    h.ballId = ball.id;
  }

  const set = def.buttons[game.view];
  for (let i = 0; i < 3; i++) {
    const ab = set[i];
    if (ab) useAbility(game, ab, i);
  }

  switch (mode) {
    case 'platform':
      movePlatform(game, dt, ix);
      break;
    case 'flap':
      moveFlap(game, dt, ix);
      break;
    case 'thrust':
      moveThrust(game, dt, ix, iy);
      break;
    case 'free':
      moveFree(game, dt, ix, iy);
      break;
    case 'grid':
      moveGrid(game, dt, ix, iy);
      break;
  }

  // Autoscrolling worlds push the hero along; getting squished hurts.
  if (L.camera === 'autoscroll') {
    if (h.x < game.cam.x) {
      if (mode === 'grid' || !L.boxFree(game.cam.x, h.y, h.w, h.h)) {
        game.damageHero(1, h.x - 10, h.y + h.h / 2);
        if (game.state === 'play') game.respawnHero();
      } else {
        h.x = game.cam.x;
        h.vx = Math.max(h.vx, 0);
      }
    }
    const right = game.cam.x + game.viewW - h.w;
    if (h.x > right && mode !== 'grid') h.x = right;
  }

  // Falling out of a side-view world.
  if (game.view === 'side' && h.y > L.pxH + 24) {
    game.damageHero(1, h.x + h.w / 2, h.y + 40);
    if (game.state === 'play') game.respawnHero();
  }

  // Remember a safe spot to respawn at.
  const safe = mode === 'platform' ? h.onGround : h.y < L.pxH - 3 * TILE;
  if (safe && Math.floor(h.anim * 4) !== Math.floor((h.anim - dt) * 4) && L.boxFree(h.x, h.y, h.w, h.h)) {
    h.lastSafe = { x: h.x, y: h.y };
  }
}

function useAbility(game: Game, ab: Ability, slot: number): void {
  const h = game.hero;
  if (ab === 'jump' || ab === 'flap' || ab === 'boost') return; // handled by movement
  const pressed = slotPressed(game, slot) || (ab === 'shoot' && slotHeld(game, slot));
  if (!pressed || h.cd[slot] > 0) return;
  switch (ab) {
    case 'dash':
      startDash(game, false);
      h.cd[slot] = 0.6;
      break;
    case 'peck':
      startDash(game, true);
      h.cd[slot] = 0.45;
      break;
    case 'hop':
      if (h.hop <= 0) {
        h.hop = 0.45;
        game.sfx('jump');
      }
      h.cd[slot] = 0.1;
      break;
    case 'mine':
      mine(game);
      h.cd[slot] = 0.18;
      break;
    case 'place':
      place(game);
      h.cd[slot] = 0.15;
      break;
    case 'sword':
      sword(game);
      h.cd[slot] = 0.3;
      break;
    case 'shout':
      shout(game);
      h.cd[slot] = 2.5;
      break;
    case 'fireball':
      if (fireball(game)) h.cd[slot] = 0.22;
      break;
    case 'shoot':
      shoot(game);
      h.cd[slot] = 0.16;
      break;
    case 'warp':
      warp(game);
      h.cd[slot] = 3;
      break;
    case 'ball':
      ball(game);
      h.cd[slot] = 0.2;
      break;
    case 'power':
      h.power = 5;
      game.banner('POWER!', 1);
      game.sfx('power');
      h.cd[slot] = 12;
      break;
  }
}

// ------------------------------------------------------------------ movement

function movePlatform(game: Game, dt: number, ix: number): void {
  const h = game.hero;
  const def = game.heroDef;
  if (h.dash > 0) {
    moveBody(game.level, h, dt);
    return;
  }
  h.vx = approach(h.vx, ix * def.speed, (h.onGround ? 1500 : 1000) * dt);
  h.coyote = h.onGround ? 0.1 : h.coyote - dt;
  const slot = slotOf(game, 'jump');
  if (slotPressed(game, slot) || game.pressed('up')) h.jumpBuf = 0.12;
  else h.jumpBuf -= dt;
  if (h.jumpBuf > 0 && h.coyote > 0) {
    h.vy = -(def.jumpV ?? 340);
    h.coyote = 0;
    h.jumpBuf = 0;
    h.onGround = false;
    game.sfx('jump');
  }
  const held = slotHeld(game, slot) || game.input.up;
  const g = 1000 * (h.vy < 0 && !held ? 2.2 : 1);
  h.vy = Math.min(h.vy + g * dt, 620);
  const rising = h.vy < 0;
  const res = moveBody(game.level, h, dt);
  if (rising && res.hitY && res.tileY) bonk(game, res.tileY[0], res.tileY[1]);
}

/** Head-bonking bricks and "?" blocks breaks them, like a certain plumber. */
function bonk(game: Game, tx: number, ty: number): void {
  const L = game.level;
  const art = L.getArt(tx, ty);
  const style = art ? L.theme.variants?.[art] : undefined;
  if (style && (style.p === 'brick' || style.p === 'question')) game.breakTile(tx, ty);
}

function moveFlap(game: Game, dt: number, ix: number): void {
  const h = game.hero;
  if (h.dash > 0) {
    moveBody(game.level, h, dt);
    return;
  }
  h.vx = approach(h.vx, ix * game.heroDef.speed, 800 * dt);
  if (slotPressed(game, slotOf(game, 'flap')) || game.pressed('up')) {
    h.vy = -265;
    game.sfx('jump');
    game.burst(h.x + h.w / 2, h.y + h.h, '#fff6c8', 3, 40, 200);
  }
  h.vy = Math.min(h.vy + 950 * dt, 520);
  moveBody(game.level, h, dt);
}

function moveThrust(game: Game, dt: number, ix: number, iy: number): void {
  const h = game.hero;
  const mag = Math.min(1, len(ix, iy));
  h.thrusting = mag > 0.25;
  if (h.thrusting) {
    const target = Math.atan2(iy, ix);
    let diff = target - h.angle;
    while (diff > Math.PI) diff -= Math.PI * 2;
    while (diff < -Math.PI) diff += Math.PI * 2;
    h.angle += clamp(diff, -7 * dt, 7 * dt);
    const thrust = 440 * mag;
    h.vx += Math.cos(h.angle) * thrust * dt;
    h.vy += Math.sin(h.angle) * thrust * dt;
  }
  h.fx = Math.cos(h.angle);
  h.fy = Math.sin(h.angle);
  if (Math.abs(h.fx) > 0.1) h.face = Math.sign(h.fx);
  const drag = Math.max(0, 1 - 0.9 * dt);
  h.vx *= drag;
  h.vy *= drag;
  if (game.view === 'side') h.vy += 230 * dt;
  const sp = len(h.vx, h.vy);
  const max = game.heroDef.speed;
  if (sp > max) {
    h.vx *= max / sp;
    h.vy *= max / sp;
  }
  const pvx = h.vx;
  const pvy = h.vy;
  const res = moveBody(game.level, h, dt);
  if (res.hitX) h.vx = -pvx * 0.4;
  if (res.hitY) h.vy = res.hitY && pvy > 0 && game.view === 'side' ? 0 : -pvy * 0.4;
}

function moveFree(game: Game, dt: number, ix: number, iy: number): void {
  const h = game.hero;
  if (h.dash > 0) {
    moveBody(game.level, h, dt);
    return;
  }
  const sp = game.heroDef.speed;
  const acc = game.heroDef.id === 'flappy' ? 650 : 1400;
  h.vx = approach(h.vx, ix * sp, acc * dt);
  h.vy = approach(h.vy, iy * sp, acc * dt);
  moveBody(game.level, h, dt);
}

function moveGrid(game: Game, dt: number, ix: number, iy: number): void {
  const h = game.hero;
  const L = game.level;
  if (Math.abs(ix) > 0.35 || Math.abs(iy) > 0.35) {
    const d = Math.abs(ix) > Math.abs(iy) ? { x: Math.sign(ix), y: 0 } : { x: 0, y: Math.sign(iy) };
    if (!(d.x === -h.gridDir.x && d.y === -h.gridDir.y)) h.want = d;
  }
  const interval = slotHeld(game, slotOf(game, 'boost')) ? 0.075 : 0.13;
  h.gridT += dt;
  if (h.gridT >= interval) {
    h.gridT = Math.min(h.gridT - interval, interval);
    h.gridDir = { ...h.want };
    const head = h.segs[0];
    let nx = head.x + h.gridDir.x;
    let ny = head.y + h.gridDir.y;
    if (L.wrap) {
      nx = ((nx % L.w) + L.w) % L.w;
      ny = ((ny % L.h) + L.h) % L.h;
    }
    h.prevSegs = h.segs.map((s) => ({ ...s }));
    const blocked = (!L.wrap && !L.inside(nx, ny)) || isSolid(L.get(nx, ny));
    if (!blocked) {
      const tailMoves = h.grow <= 0;
      const end = tailMoves ? h.segs.length - 1 : h.segs.length;
      for (let i = 1; i < end; i++) {
        if (h.segs[i].x === nx && h.segs[i].y === ny && !(h.segs[i].x === head.x && h.segs[i].y === head.y)) {
          game.damageHero(1, nx * TILE + 8, ny * TILE + 8);
          break;
        }
      }
      h.segs.unshift({ x: nx, y: ny });
      if (h.grow > 0) h.grow--;
      else h.segs.pop();
      if (h.segs.length > 40) h.segs.length = 40;
    }
  }
  const head = h.segs[0];
  h.x = head.x * TILE + (TILE - h.w) / 2;
  h.y = head.y * TILE + (TILE - h.h) / 2;
  h.fx = h.gridDir.x;
  h.fy = h.gridDir.y;
  if (h.gridDir.x) h.face = h.gridDir.x;
}

// ------------------------------------------------------------------ abilities

function startDash(game: Game, hurts: boolean): void {
  const h = game.hero;
  const [dx, dy] = aimVec(game);
  h.dash = 0.16;
  h.dashHurts = hurts;
  h.vx = dx * 330;
  h.vy = game.view === 'side' && dy === 0 ? -30 : dy * 330;
  game.burst(h.x + h.w / 2, h.y + h.h / 2, '#ffffff', 5, 50, 0);
  game.sfx('jump');
}

function mine(game: Game): void {
  const h = game.hero;
  const [dx, dy] = aimAxis(game);
  const [cx, cy] = game.heroCenter();
  const px = cx + dx * (h.w / 2 + 7);
  const py = cy + dy * (h.h / 2 + 7);
  if (game.breakTile(Math.floor(px / TILE), Math.floor(py / TILE))) h.blocks = Math.min(99, h.blocks + 1);
  game.hitRect({ x: px - 8, y: py - 8, w: 16, h: 16 }, 2, 150, false);
  h.attack = { kind: 'mine', t: 0.18, dx, dy };
}

function place(game: Game): void {
  const h = game.hero;
  const L = game.level;
  if (h.blocks <= 0) {
    game.floatText(h.x, h.y - 6, 'No blocks — mine some!', '#ffd');
    return;
  }
  const [dx, dy] = aimAxis(game);
  const [cx, cy] = game.heroCenter();
  const tx = Math.floor((cx + dx * (h.w / 2 + 8)) / TILE);
  const ty = Math.floor((cy + dy * (h.h / 2 + 8)) / TILE);
  if (!L.inside(tx, ty) || L.get(tx, ty) !== EMPTY) return;
  const r = { x: tx * TILE, y: ty * TILE, w: TILE, h: TILE };
  if (overlap(r, h)) return;
  if (game.ents.some((e) => !e.dead && (e.kind === 'enemy' || e.kind === 'pickup' || e.kind === 'flag') && overlap(r, e))) return;
  L.set(tx, ty, BLOCK);
  h.blocks--;
  h.attack = { kind: 'mine', t: 0.12, dx, dy };
  game.sfx('place');
}

function sword(game: Game): void {
  const h = game.hero;
  const [dx, dy] = aimVec(game);
  const [cx, cy] = game.heroCenter();
  const ax = cx + dx * 12;
  const ay = cy + dy * 12;
  game.hitRect({ x: ax - 18, y: ay - 18, w: 36, h: 36 }, 2, 240, false);
  game.hitRect({ x: ax - 10, y: ay - 10, w: 20, h: 20 }, 0, 0, true);
  h.attack = { kind: 'sword', t: 0.2, dx, dy };
  game.sfx('shoot');
}

function shout(game: Game): void {
  const h = game.hero;
  const [dx, dy] = aimVec(game);
  const [cx, cy] = game.heroCenter();
  for (const e of game.ents) {
    if (e.dead || (e.kind !== 'enemy' && !(e.kind === 'proj' && !e.friendly))) continue;
    const ex = e.x + e.w / 2 - cx;
    const ey = e.y + e.h / 2 - cy;
    const d = len(ex, ey);
    if (d > 95 || (d > 6 && (ex * dx + ey * dy) / d < 0.55)) continue;
    if (e.kind === 'proj') e.dead = true;
    else game.hurtEnemy(e, 1, cx, cy, 520);
  }
  h.attack = { kind: 'shout', t: 0.5, dx, dy };
  game.floatText(cx - 24, h.y - 8, 'FUS RO DAH!', '#bfe3ff');
  game.addShake(4);
  game.sfx('shout');
}

function fireball(game: Game): boolean {
  const h = game.hero;
  const alive = game.ents.filter((e) => e.type === 'fireball' && !e.dead).length;
  if (alive >= 2) return false;
  const [dx, dy] = game.view === 'side' ? [h.face, 0] : aimVec(game);
  const [cx, cy] = game.heroCenter();
  game.spawn(
    makeEnt('proj', 'fireball', cx - 4 + dx * 6, cy - 4 + dy * 6, 8, 8, {
      friendly: true,
      vx: dx * 230,
      vy: game.view === 'side' ? 60 : dy * 230,
      data: { life: 1.6, bounce: game.view === 'side' ? 1 : 0 },
    }),
  );
  h.attack = { kind: 'throw', t: 0.15, dx, dy };
  game.sfx('shoot');
  return true;
}

function shoot(game: Game): void {
  const h = game.hero;
  const [cx, cy] = game.heroCenter();
  const a = h.angle;
  game.spawn(
    makeEnt('proj', 'bullet', cx - 2 + Math.cos(a) * 8, cy - 2 + Math.sin(a) * 8, 4, 4, {
      friendly: true,
      vx: Math.cos(a) * 380 + h.vx * 0.4,
      vy: Math.sin(a) * 380 + h.vy * 0.4,
      data: { life: 0.8 },
    }),
  );
  game.sfx('shoot');
}

function warp(game: Game): void {
  const h = game.hero;
  const L = game.level;
  const enemies = game.enemies();
  const x0 = L.camera === 'fixed' ? 0 : Math.max(0, game.cam.x);
  const y0 = L.camera === 'fixed' ? 0 : Math.max(0, game.cam.y);
  const ww = Math.min(L.pxW, L.camera === 'fixed' ? L.pxW : game.viewW);
  const hh = Math.min(L.pxH, L.camera === 'fixed' ? L.pxH : game.viewH);
  for (let i = 0; i < 40; i++) {
    const x = x0 + game.rng.range(8, ww - 8 - h.w);
    const y = y0 + game.rng.range(8, hh - 8 - h.h);
    if (!L.boxFree(x, y, h.w, h.h)) continue;
    if (enemies.some((e) => len(e.x - x, e.y - y) < 60)) continue;
    game.burst(h.x + h.w / 2, h.y + h.h / 2, '#b197fc', 10, 90, 0);
    h.x = x;
    h.y = y;
    h.vx = h.vy = 0;
    h.inv = Math.max(h.inv, 0.6);
    game.burst(x + h.w / 2, y + h.h / 2, '#b197fc', 10, 90, 0);
    game.sfx('power');
    return;
  }
}

function ball(game: Game): void {
  const h = game.hero;
  const b = game.ents.find((e) => e.id === h.ballId && !e.dead);
  if (!b) return;
  if (b.data.held) {
    const [dx, dy] = game.view === 'side' ? norm(h.face * 0.45, -1) : aimVec(game);
    b.vx = dx * b.data.speed;
    b.vy = dy * b.data.speed;
    b.data.held = 0;
    b.data.out = 0;
    game.sfx('shoot');
  } else {
    b.data.recall = 1;
  }
}

/** Hero body touching an enemy: stomp, bite, eat or get hurt. */
export function heroHitsEnemy(game: Game, e: Ent): void {
  const h = game.hero;
  const [cx, cy] = game.heroCenter();
  const mode = game.heroDef.move[game.view];
  if (h.power > 0) {
    game.hurtEnemy(e, 3, cx, cy, 220);
    return;
  }
  if (h.dash > 0 && h.dashHurts) {
    game.hurtEnemy(e, 2, cx, cy, 220);
    return;
  }
  if (game.view === 'side' && mode === 'platform' && h.vy > 30 && h.y + h.h - e.y < 10 && !e.data.spiky) {
    game.hurtEnemy(e, 2, cx, h.y, 40);
    h.vy = -290;
    game.sfx('jump');
    return;
  }
  if (h.hop > 0 || h.dash > 0) return;
  if (mode === 'grid' && !e.data.spiky) {
    game.hurtEnemy(e, 2, cx, cy, 200);
    return;
  }
  game.damageHero(e.dmg, e.x + e.w / 2, e.y + e.h / 2);
}
