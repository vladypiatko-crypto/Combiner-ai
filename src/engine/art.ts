import { Ent, TILE, WALL } from './core';
import type { Game, Hero } from './game';
import type { Level, TileStyle } from './level';

type Ctx = CanvasRenderingContext2D;

function rect(ctx: Ctx, color: string, x: number, y: number, w: number, h: number): void {
  ctx.fillStyle = color;
  ctx.fillRect(x, y, w, h);
}

function circle(ctx: Ctx, color: string, x: number, y: number, r: number): void {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
}

function hash(x: number, y: number, k = 0): number {
  let h = (x * 374761393 + y * 668265263 + k * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

// ------------------------------------------------------------------ tiles

export function drawTile(ctx: Ctx, s: TileStyle, tx: number, ty: number, L: Level, time: number): void {
  const x = tx * TILE;
  const y = ty * TILE;
  const [base, hi, lo] = s.c;
  const p = s.p ?? 'plain';
  const ground = L.theme.ground;
  switch (p) {
    case 'tree':
      if (ground) rect(ctx, ground, x, y, TILE, TILE);
      circle(ctx, lo, x + 8, y + 9, 8);
      circle(ctx, base, x + 8, y + 8, 7);
      circle(ctx, hi, x + 6, y + 6, 3);
      return;
    case 'rock':
      if (ground) rect(ctx, ground, x, y, TILE, TILE);
      rect(ctx, lo, x + 1, y + 3, 14, 12);
      rect(ctx, base, x + 2, y + 2, 12, 11);
      rect(ctx, hi, x + 3, y + 3, 6, 3);
      return;
    case 'water': {
      rect(ctx, base, x, y, TILE, TILE);
      const o = Math.floor((time * 6 + tx * 3) % 16);
      rect(ctx, hi, x + ((o + 2) % 12), y + 4, 4, 1);
      rect(ctx, hi, x + ((o + 9) % 12), y + 11, 4, 1);
      return;
    }
    case 'maze': {
      rect(ctx, base, x, y, TILE, TILE);
      ctx.fillStyle = hi;
      const open = (dx: number, dy: number) => L.get(tx + dx, ty + dy) !== WALL;
      if (open(0, -1)) ctx.fillRect(x, y + 2, TILE, 2);
      if (open(0, 1)) ctx.fillRect(x, y + 12, TILE, 2);
      if (open(-1, 0)) ctx.fillRect(x + 2, y, 2, TILE);
      if (open(1, 0)) ctx.fillRect(x + 12, y, 2, TILE);
      return;
    }
    default:
      break;
  }
  rect(ctx, base, x, y, TILE, TILE);
  switch (p) {
    case 'grass':
      rect(ctx, hi, x, y, TILE, 4);
      for (let i = 0; i < 4; i++) if (hash(tx, ty, i) > 0.4) rect(ctx, hi, x + i * 4 + 1, y + 4, 2, 2);
      rect(ctx, lo, x + Math.floor(hash(tx, ty) * 12), y + 10, 2, 2);
      break;
    case 'dirt':
    case 'stone':
    case 'ore':
      for (let i = 0; i < 4; i++) {
        const h = hash(tx, ty, i);
        rect(ctx, i % 2 ? hi : lo, x + Math.floor(h * 14), y + Math.floor(hash(ty, tx, i) * 14), 2, 2);
      }
      if (p === 'ore') {
        const kind = hash(tx, ty, 9);
        const c = kind < 0.6 ? '#1f1f22' : kind < 0.85 ? '#d9a679' : '#f2d24b';
        rect(ctx, c, x + 3, y + 4, 3, 3);
        rect(ctx, c, x + 9, y + 8, 3, 3);
        rect(ctx, c, x + 5, y + 11, 2, 2);
      }
      break;
    case 'wood':
      rect(ctx, lo, x + 3, y, 2, TILE);
      rect(ctx, lo, x + 10, y, 1, TILE);
      rect(ctx, hi, x + 6, y, 1, TILE);
      break;
    case 'leaves':
    case 'hedge':
      for (let i = 0; i < 6; i++) {
        rect(ctx, i % 2 ? hi : lo, x + Math.floor(hash(tx, ty, i) * 13), y + Math.floor(hash(ty, tx, i + 3) * 13), 3, 3);
      }
      break;
    case 'plank':
      rect(ctx, lo, x, y + 5, TILE, 1);
      rect(ctx, lo, x, y + 11, TILE, 1);
      rect(ctx, hi, x, y, TILE, 1);
      rect(ctx, lo, x + (ty % 2 ? 4 : 11), y, 1, 5);
      rect(ctx, lo, x + (ty % 2 ? 11 : 4), y + 6, 1, 5);
      break;
    case 'brick':
    case 'ruin': {
      const big = p === 'ruin';
      rect(ctx, hi, x, y, TILE, 1);
      rect(ctx, lo, x, y + (big ? 8 : 7), TILE, 1);
      rect(ctx, lo, x, y + 15, TILE, 1);
      rect(ctx, lo, x + (big ? 10 : 7), y, 1, big ? 8 : 7);
      rect(ctx, lo, x + (big ? 4 : 3), y + (big ? 9 : 8), 1, 7);
      if (big && L.get(tx, ty) !== WALL) {
        rect(ctx, '#3a352b', x + 5, y + 3, 1, 5);
        rect(ctx, '#3a352b', x + 6, y + 7, 3, 1);
      }
      break;
    }
    case 'question': {
      rect(ctx, lo, x, y + 15, TILE, 1);
      rect(ctx, lo, x + 15, y, 1, TILE);
      rect(ctx, hi, x, y, TILE, 1);
      const q = Math.sin(time * 4) > 0 ? '#fff4c2' : '#ffffff';
      rect(ctx, q, x + 5, y + 3, 6, 2);
      rect(ctx, q, x + 10, y + 4, 2, 4);
      rect(ctx, q, x + 7, y + 7, 3, 2);
      rect(ctx, q, x + 7, y + 11, 3, 2);
      break;
    }
    case 'pipe':
      rect(ctx, hi, x + 2, y, 3, TILE);
      rect(ctx, lo, x + 12, y, 3, TILE);
      if (L.get(tx, ty - 1) !== WALL || L.get(tx, ty + 1) !== WALL) {
        rect(ctx, lo, x, y + (L.get(tx, ty - 1) !== WALL ? 0 : 14), TILE, 2);
      }
      break;
    case 'steel':
      rect(ctx, hi, x, y, TILE, 1);
      rect(ctx, hi, x, y, 1, TILE);
      rect(ctx, lo, x, y + 15, TILE, 1);
      rect(ctx, lo, x + 15, y, 1, TILE);
      rect(ctx, lo, x + 3, y + 3, 2, 2);
      rect(ctx, lo, x + 11, y + 11, 2, 2);
      break;
    default:
      rect(ctx, hi, x, y, TILE, 2);
      rect(ctx, lo, x, y + 14, TILE, 2);
      break;
  }
}

// ------------------------------------------------------------------ heroes

export interface HeroPose {
  x: number;
  y: number;
  w: number;
  h: number;
  face: number;
  fx: number;
  fy: number;
  angle: number;
  anim: number;
  moving: boolean;
  thrusting: boolean;
  power: number;
  attack: Hero['attack'];
  hop: number;
  segs?: { x: number; y: number }[];
  prevSegs?: { x: number; y: number }[];
  segT?: number;
  ballHeld?: boolean;
}

export function poseFromHero(h: Hero): HeroPose {
  return {
    x: h.x,
    y: h.y,
    w: h.w,
    h: h.h,
    face: h.face,
    fx: h.fx,
    fy: h.fy,
    angle: h.angle,
    anim: h.anim,
    moving: Math.abs(h.vx) + Math.abs(h.vy) > 10,
    thrusting: h.thrusting,
    power: h.power,
    attack: h.attack,
    hop: h.hop,
    segs: h.segs,
    prevSegs: h.prevSegs,
    segT: Math.min(1, h.gridT / 0.13),
  };
}

/** Draw a hero sprite. Shared by the player and by ghost racers. */
export function drawHero(ctx: Ctx, id: string, p: HeroPose, view: 'side' | 'top'): void {
  const cx = p.x + p.w / 2;
  const bottom = p.y + p.h;
  let lift = 0;
  if (p.hop > 0) {
    lift = Math.sin((1 - p.hop / 0.45) * Math.PI) * 10;
    ctx.globalAlpha *= 1;
    circle(ctx, 'rgba(0,0,0,0.25)', cx, bottom - 1, 5);
  }
  if (p.power > 0) {
    ctx.save();
    ctx.globalAlpha *= 0.35 + 0.2 * Math.sin(p.anim * 20);
    circle(ctx, '#fff3a0', cx, p.y + p.h / 2, 13);
    ctx.restore();
  }
  ctx.save();
  ctx.translate(Math.round(cx), Math.round(bottom - lift));
  const walk = p.moving ? Math.sin(p.anim * 16) : 0;
  switch (id) {
    case 'blockcraft':
      ctx.scale(p.face, 1);
      rect(ctx, '#3240a8', -5, -5, 4, 5 + Math.min(0, walk));
      rect(ctx, '#3240a8', 1, -5, 4, 5 - Math.max(0, walk));
      rect(ctx, '#2fa8c4', -6, -11, 12, 7);
      rect(ctx, '#c99a6e', -7, -10, 2, 5);
      rect(ctx, '#c99a6e', 5, -10, 2, 5);
      rect(ctx, '#c99a6e', -5, -18, 10, 8);
      rect(ctx, '#3b2a1a', -5, -18, 10, 3);
      rect(ctx, '#ffffff', 1, -14, 2, 2);
      rect(ctx, '#4a3cb5', 2, -14, 1, 2);
      rect(ctx, '#ffffff', -3, -14, 2, 2);
      rect(ctx, '#4a3cb5', -2, -14, 1, 2);
      if (p.attack.t > 0 && p.attack.kind === 'mine') {
        ctx.save();
        ctx.rotate(-1.2 + (p.attack.t / 0.18) * 1.6);
        rect(ctx, '#8b6235', 4, -12, 2, 10);
        rect(ctx, '#9aa0a6', 1, -14, 9, 3);
        ctx.restore();
      } else {
        rect(ctx, '#8b6235', 5, -9, 2, 7);
        rect(ctx, '#9aa0a6', 3, -11, 6, 2);
      }
      break;
    case 'dragonrealm':
      ctx.scale(p.face, 1);
      rect(ctx, '#8f1d1d', -7, -12, 4, 11);
      rect(ctx, '#5b5f66', -5, -5, 4, 5 + Math.min(0, walk));
      rect(ctx, '#5b5f66', 1, -5, 4, 5 - Math.max(0, walk));
      rect(ctx, '#b8c0cc', -5, -12, 10, 8);
      rect(ctx, '#8d6e4a', -5, -6, 10, 2);
      rect(ctx, '#8d96a3', -5, -19, 10, 8);
      rect(ctx, '#e8e2d0', -8, -20, 3, 3);
      rect(ctx, '#e8e2d0', 5, -20, 3, 3);
      rect(ctx, '#1b1d22', -1, -16, 6, 2);
      if (!(p.attack.t > 0 && p.attack.kind === 'sword')) {
        rect(ctx, '#d0d5dd', 6, -14, 2, 9);
        rect(ctx, '#8d6e4a', 5, -6, 4, 2);
      }
      break;
    case 'flappy': {
      ctx.scale(p.face, 1);
      ctx.fillStyle = '#e8a200';
      ctx.beginPath();
      ctx.ellipse(0, -6, 7, 6, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#f5c542';
      ctx.beginPath();
      ctx.ellipse(0, -6.5, 6.5, 5.5, 0, 0, Math.PI * 2);
      ctx.fill();
      const flap = Math.sin(p.anim * 22) * 3;
      rect(ctx, '#fff3c4', -6, -6 + flap * 0.5, 6, 3);
      rect(ctx, '#ffffff', 2, -10, 4, 4);
      rect(ctx, '#111111', 4, -9, 2, 2);
      rect(ctx, '#f76707', 5, -6, 5, 2);
      rect(ctx, '#e03131', 5, -4, 4, 1);
      break;
    }
    case 'jumper':
      ctx.scale(p.face, 1);
      rect(ctx, '#6b3a1e', -6, -2, 5, 2);
      rect(ctx, '#6b3a1e', 1, -2, 5, 2);
      rect(ctx, '#2f5bd3', -5, -7 + Math.min(0, walk), 4, 5);
      rect(ctx, '#2f5bd3', 1, -7 - Math.max(0, walk), 4, 5);
      rect(ctx, '#e5423a', -6, -12, 12, 6);
      rect(ctx, '#2f5bd3', -3, -12, 6, 6);
      rect(ctx, '#ffd43b', -3, -10, 1, 1);
      rect(ctx, '#ffd43b', 2, -10, 1, 1);
      rect(ctx, '#f1c27d', -4, -18, 9, 6);
      rect(ctx, '#3b2a1a', 0, -14, 5, 2);
      rect(ctx, '#111111', 2, -17, 1, 2);
      rect(ctx, '#e5423a', -5, -21, 10, 4);
      rect(ctx, '#e5423a', 2, -19, 5, 2);
      break;
    case 'rocks': {
      ctx.translate(0, -p.h / 2);
      ctx.rotate(p.angle);
      if (p.thrusting) {
        ctx.fillStyle = Math.sin(p.anim * 40) > 0 ? '#ffa94d' : '#ffe066';
        ctx.beginPath();
        ctx.moveTo(-6, -3);
        ctx.lineTo(-12 - Math.random() * 3, 0);
        ctx.lineTo(-6, 3);
        ctx.fill();
      }
      ctx.fillStyle = '#2b2f4a';
      ctx.strokeStyle = '#e9ecef';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(9, 0);
      ctx.lineTo(-6, -6);
      ctx.lineTo(-3, 0);
      ctx.lineTo(-6, 6);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      rect(ctx, '#74c0fc', 1, -1, 3, 2);
      break;
    }
    case 'bricks': {
      ctx.translate(0, -p.h / 2);
      ctx.fillStyle = 'rgba(77,171,247,0.25)';
      ctx.fillRect(-p.w / 2 - 2, -p.h / 2 - 2, p.w + 4, p.h + 4);
      const g = ctx.createLinearGradient(0, -p.h / 2, 0, p.h / 2);
      g.addColorStop(0, '#a5d8ff');
      g.addColorStop(1, '#1971c2');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.roundRect(-p.w / 2, -p.h / 2, p.w, p.h, 4);
      ctx.fill();
      rect(ctx, 'rgba(255,255,255,0.7)', -p.w / 2 + 3, -p.h / 2 + 1, p.w - 6, 2);
      break;
    }
    case 'maze': {
      ctx.translate(0, -p.h / 2);
      const dir = Math.atan2(p.fy, p.fx);
      const mouth = 0.08 + 0.32 * Math.abs(Math.sin(p.anim * 12));
      ctx.rotate(dir);
      ctx.fillStyle = p.power > 0 && Math.sin(p.anim * 30) > 0 ? '#ffffff' : '#ffd43b';
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, 7, mouth * Math.PI, (2 - mouth) * Math.PI);
      ctx.closePath();
      ctx.fill();
      rect(ctx, '#111111', 0, -5, 2, 2);
      break;
    }
    default:
      rect(ctx, '#ffffff', -6, -12, 12, 12);
  }
  ctx.restore();
  drawAttack(ctx, p, view);
}

function drawAttack(ctx: Ctx, p: HeroPose, view: 'side' | 'top'): void {
  const a = p.attack;
  if (a.t <= 0) return;
  const cx = p.x + p.w / 2;
  const cy = p.y + p.h / 2;
  if (a.kind === 'sword') {
    const base = Math.atan2(a.dy, a.dx);
    const prog = 1 - a.t / 0.2;
    ctx.save();
    ctx.strokeStyle = 'rgba(255,255,255,0.9)';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(cx, cy, 16, base - 1.2 + prog * 0.6, base + 1.2 * prog);
    ctx.stroke();
    ctx.strokeStyle = '#d0d5dd';
    ctx.lineWidth = 2;
    const sa = base - 1.2 + prog * 2.4;
    ctx.beginPath();
    ctx.moveTo(cx + Math.cos(sa) * 4, cy + Math.sin(sa) * 4);
    ctx.lineTo(cx + Math.cos(sa) * 18, cy + Math.sin(sa) * 18);
    ctx.stroke();
    ctx.restore();
  } else if (a.kind === 'shout') {
    const prog = 1 - a.t / 0.5;
    const base = Math.atan2(a.dy, a.dx);
    ctx.save();
    ctx.strokeStyle = `rgba(191,227,255,${1 - prog})`;
    ctx.lineWidth = 3;
    for (let i = 0; i < 3; i++) {
      const r = 10 + prog * 80 - i * 12;
      if (r <= 4) continue;
      ctx.beginPath();
      ctx.arc(cx, cy, r, base - 0.9, base + 0.9);
      ctx.stroke();
    }
    ctx.restore();
  } else if (a.kind === 'mine' && view === 'top') {
    rect(ctx, 'rgba(255,255,255,0.6)', cx + a.dx * 12 - 3, cy + a.dy * 12 - 3, 6, 6);
  }
}

/** Snake bodies need segment-by-segment drawing. */
export function drawSnake(ctx: Ctx, p: HeroPose, color = '#40c057', dark = '#2b8a3e'): void {
  const segs = p.segs ?? [];
  const prev = p.prevSegs ?? segs;
  const t = p.segT ?? 1;
  for (let i = segs.length - 1; i >= 0; i--) {
    const a = prev[i] ?? segs[i];
    const b = segs[i];
    const jump = Math.abs(a.x - b.x) > 1 || Math.abs(a.y - b.y) > 1;
    const x = (jump ? b.x : a.x + (b.x - a.x) * t) * TILE + 8;
    const y = (jump ? b.y : a.y + (b.y - a.y) * t) * TILE + 8;
    const r = i === 0 ? 7 : 6 - Math.min(2, i / 10);
    circle(ctx, i % 2 ? dark : color, x, y, r);
    if (i === 0) {
      const ex = p.fx * 3;
      const ey = p.fy * 3;
      circle(ctx, '#ffffff', x + ex - p.fy * 3, y + ey + p.fx * 3, 2);
      circle(ctx, '#ffffff', x + ex + p.fy * 3, y + ey - p.fx * 3, 2);
      rect(ctx, '#111', x + ex * 1.2 - p.fy * 3 - 0.5, y + ey * 1.2 + p.fx * 3 - 0.5, 1.5, 1.5);
      rect(ctx, '#111', x + ex * 1.2 + p.fy * 3 - 0.5, y + ey * 1.2 - p.fx * 3 - 0.5, 1.5, 1.5);
      if (Math.sin(p.anim * 8) > 0.6) {
        ctx.strokeStyle = '#e03131';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(x + p.fx * 7, y + p.fy * 7);
        ctx.lineTo(x + p.fx * 11, y + p.fy * 11);
        ctx.stroke();
      }
    }
  }
}

// ------------------------------------------------------------------ entities

const GHOST_COLORS = ['#ff3b3b', '#ffb8ff', '#3bf0ff', '#ffb852'];

export function drawEnt(ctx: Ctx, e: Ent, game: Game): void {
  const t = e.t;
  const cx = e.x + e.w / 2;
  const cy = e.y + e.h / 2;
  if (e.hurt > 0 && e.kind === 'enemy' && Math.floor(e.hurt * 30) % 2 === 0) ctx.globalAlpha = 0.5;
  switch (e.type) {
    case 'coin': {
      const w = Math.max(1, Math.abs(Math.cos(t * 4 + e.id)) * 5);
      ctx.fillStyle = '#c79100';
      ctx.beginPath();
      ctx.ellipse(cx, cy, w + 0.5, 5.5, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#ffd43b';
      ctx.beginPath();
      ctx.ellipse(cx, cy, w, 5, 0, 0, Math.PI * 2);
      ctx.fill();
      break;
    }
    case 'diamond': {
      const by = cy + Math.sin(t * 3 + e.id) * 1.5;
      ctx.fillStyle = '#3bc9db';
      ctx.beginPath();
      ctx.moveTo(cx, by - 6);
      ctx.lineTo(cx + 6, by);
      ctx.lineTo(cx, by + 6);
      ctx.lineTo(cx - 6, by);
      ctx.fill();
      rect(ctx, '#c5f6fa', cx - 2, by - 3, 3, 3);
      if (Math.sin(t * 5 + e.id) > 0.8) rect(ctx, '#ffffff', cx + 3, by - 6, 2, 2);
      break;
    }
    case 'rune': {
      const r = 6 + Math.sin(t * 4) * 1;
      ctx.save();
      ctx.globalAlpha *= 0.35;
      circle(ctx, '#b197fc', cx, cy, r + 4);
      ctx.restore();
      circle(ctx, '#5f3dc4', cx, cy, r);
      ctx.strokeStyle = '#e5dbff';
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(cx - 2, cy - 4);
      ctx.lineTo(cx - 2, cy + 4);
      ctx.moveTo(cx - 2, cy - 4);
      ctx.lineTo(cx + 3, cy - 1);
      ctx.lineTo(cx - 2, cy + 1);
      ctx.lineTo(cx + 3, cy + 4);
      ctx.stroke();
      break;
    }
    case 'apple':
      circle(ctx, '#e03131', cx, cy + 1, 5);
      circle(ctx, '#ff8787', cx - 2, cy - 1, 1.5);
      rect(ctx, '#5c3d1e', cx - 0.5, cy - 6, 1, 3);
      rect(ctx, '#51cf66', cx + 0.5, cy - 6, 3, 2);
      break;
    case 'pellet':
      circle(ctx, '#ffe3c4', cx, cy, 2);
      break;
    case 'power':
      if (Math.sin(t * 8) > -0.4) circle(ctx, '#ffe3c4', cx, cy, 5);
      break;
    case 'heart': {
      const by = cy + Math.sin(t * 3) * 1.5;
      circle(ctx, '#ff4d6d', cx - 2.5, by - 1, 3);
      circle(ctx, '#ff4d6d', cx + 2.5, by - 1, 3);
      ctx.beginPath();
      ctx.moveTo(cx - 5.5, by);
      ctx.lineTo(cx + 5.5, by);
      ctx.lineTo(cx, by + 6);
      ctx.fill();
      break;
    }
    case 'flag': {
      rect(ctx, '#ced4da', e.x + 2, e.y, 2, e.h);
      circle(ctx, '#ffd43b', e.x + 3, e.y, 3);
      const wave = Math.sin(t * 5) * 2;
      ctx.fillStyle = '#40c057';
      ctx.beginPath();
      ctx.moveTo(e.x + 4, e.y + 4);
      ctx.lineTo(e.x + 18, e.y + 9 + wave);
      ctx.lineTo(e.x + 4, e.y + 15);
      ctx.fill();
      break;
    }
    case 'zombie': {
      const f = e.dir;
      const walk = Math.sin(t * 10) * 1.5;
      rect(ctx, '#3b3b8a', e.x + 2, e.y + 14, 3, 6 + walk);
      rect(ctx, '#3b3b8a', e.x + 7, e.y + 14, 3, 6 - walk);
      rect(ctx, '#2f9e9e', e.x + 1, e.y + 7, 10, 8);
      rect(ctx, '#5aa548', f > 0 ? e.x + 8 : e.x - 4, e.y + 8, 8, 3);
      rect(ctx, '#5aa548', e.x + 1, e.y, 10, 8);
      rect(ctx, '#1b1b1b', f > 0 ? e.x + 6 : e.x + 2, e.y + 3, 2, 2);
      rect(ctx, '#1b1b1b', f > 0 ? e.x + 9 : e.x + 5, e.y + 3, 2, 2);
      break;
    }
    case 'creeper': {
      const flash = e.data.fuse && Math.sin(t * 30) > 0;
      rect(ctx, flash ? '#ffffff' : '#4caf50', e.x + 1, e.y, 10, e.h - 4);
      rect(ctx, '#2e7d32', e.x + 1, e.y + e.h - 4, 4, 4);
      rect(ctx, '#2e7d32', e.x + 7, e.y + e.h - 4, 4, 4);
      rect(ctx, '#1b1b1b', e.x + 3, e.y + 2, 2, 2);
      rect(ctx, '#1b1b1b', e.x + 7, e.y + 2, 2, 2);
      rect(ctx, '#1b1b1b', e.x + 5, e.y + 4, 2, 3);
      rect(ctx, '#1b1b1b', e.x + 4, e.y + 6, 4, 2);
      break;
    }
    case 'draugr':
      circle(ctx, '#2f343b', cx, cy + 1, 7);
      circle(ctx, '#4b5563', cx, cy, 6);
      rect(ctx, '#d6cfc0', cx - 7, cy - 6, 2, 3);
      rect(ctx, '#d6cfc0', cx + 5, cy - 6, 2, 3);
      rect(ctx, '#74e0ff', cx - 3, cy - 1, 2, 2);
      rect(ctx, '#74e0ff', cx + 1, cy - 1, 2, 2);
      break;
    case 'wolf': {
      const f = e.dir;
      ctx.fillStyle = '#8d8f94';
      ctx.beginPath();
      ctx.ellipse(cx, cy, 6, 4.5, 0, 0, Math.PI * 2);
      ctx.fill();
      circle(ctx, '#a5a8ad', cx + f * 5, cy - 2, 3.5);
      rect(ctx, '#6c6e73', cx + f * 4 - 2, cy - 7, 2, 3);
      rect(ctx, '#6c6e73', cx + f * 6 - 1, cy - 7, 2, 3);
      rect(ctx, '#ffd43b', cx + f * 6, cy - 3, 1.5, 1.5);
      rect(ctx, '#6c6e73', cx - f * 7, cy - 1, 3, 2);
      break;
    }
    case 'dragon':
      drawDragon(ctx, e, game);
      break;
    case 'bat': {
      const flap = Math.sin(t * 18) * 4;
      ctx.fillStyle = '#5f3dc4';
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx - 8, cy - 3 + flap);
      ctx.lineTo(cx - 3, cy + 2);
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + 8, cy - 3 + flap);
      ctx.lineTo(cx + 3, cy + 2);
      ctx.fill();
      circle(ctx, '#3b2a8a', cx, cy, 3.5);
      rect(ctx, '#ff6b6b', cx - 2, cy - 1, 1, 1);
      rect(ctx, '#ff6b6b', cx + 1, cy - 1, 1, 1);
      break;
    }
    case 'goomba': {
      const step = Math.sin(t * 8) > 0 ? 1 : 0;
      rect(ctx, '#1b1b1b', e.x + 1 - step, e.y + e.h - 3, 4, 3);
      rect(ctx, '#1b1b1b', e.x + 7 + step, e.y + e.h - 3, 4, 3);
      rect(ctx, '#f4c58b', e.x + 3, e.y + 5, 6, 5);
      ctx.fillStyle = '#9c5221';
      ctx.beginPath();
      ctx.ellipse(cx, e.y + 5, 6.5, 5, 0, Math.PI, 0);
      ctx.fill();
      rect(ctx, '#9c5221', e.x, e.y + 4, 12, 3);
      rect(ctx, '#ffffff', e.x + 3, e.y + 3, 2, 3);
      rect(ctx, '#ffffff', e.x + 7, e.y + 3, 2, 3);
      rect(ctx, '#1b1b1b', e.x + 4, e.y + 4, 1, 2);
      rect(ctx, '#1b1b1b', e.x + 7, e.y + 4, 1, 2);
      break;
    }
    case 'koopa': {
      const f = e.dir;
      rect(ctx, '#ffd43b', f > 0 ? e.x + 8 : e.x, e.y, 4, 7);
      rect(ctx, '#1b1b1b', f > 0 ? e.x + 10 : e.x + 1, e.y + 2, 1, 2);
      ctx.fillStyle = '#2f9e44';
      ctx.beginPath();
      ctx.ellipse(cx - f, e.y + 9, 6, 5, 0, Math.PI, 0);
      ctx.fill();
      rect(ctx, '#2f9e44', e.x, e.y + 9, 12, 3);
      rect(ctx, '#ffffff', e.x, e.y + 11, 12, 1);
      rect(ctx, '#8ce99a', cx - 3, e.y + 6, 3, 2);
      rect(ctx, '#ffd43b', e.x + 2, e.y + 12, 3, 3);
      rect(ctx, '#ffd43b', e.x + 7, e.y + 12, 3, 3);
      break;
    }
    case 'spiky': {
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(t * 3);
      ctx.fillStyle = '#868e96';
      for (let i = 0; i < 8; i++) {
        ctx.rotate(Math.PI / 4);
        ctx.beginPath();
        ctx.moveTo(4, -2);
        ctx.lineTo(8, 0);
        ctx.lineTo(4, 2);
        ctx.fill();
      }
      ctx.restore();
      circle(ctx, '#495057', cx, cy, 5);
      rect(ctx, '#ff6b6b', cx - 2, cy - 1, 1.5, 1.5);
      rect(ctx, '#ff6b6b', cx + 1, cy - 1, 1.5, 1.5);
      break;
    }
    case 'rock': {
      const n = 9;
      const r = e.w / 2;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(t * (e.data.spin ?? 1));
      ctx.beginPath();
      for (let i = 0; i < n; i++) {
        const a = (i / n) * Math.PI * 2;
        const rr = r * (0.75 + hash(e.data.seed ?? 1, i) * 0.3);
        if (i === 0) ctx.moveTo(Math.cos(a) * rr, Math.sin(a) * rr);
        else ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
      }
      ctx.closePath();
      ctx.fillStyle = '#5c5348';
      ctx.fill();
      ctx.strokeStyle = '#d8d0c0';
      ctx.lineWidth = 1.5;
      ctx.stroke();
      circle(ctx, '#4a4239', r * 0.25, -r * 0.2, r * 0.18);
      ctx.restore();
      break;
    }
    case 'ghost': {
      const d = e.data;
      const scared = d.frightened;
      const blink = scared && game.hero.power < 1.5 && Math.sin(t * 20) > 0;
      if (!d.eaten) {
        ctx.fillStyle = scared ? (blink ? '#ffffff' : '#2b3cff') : GHOST_COLORS[d.kind ?? 0];
        ctx.beginPath();
        ctx.arc(cx, cy - 1, 7, Math.PI, 0);
        ctx.lineTo(cx + 7, cy + 7);
        const wob = Math.sin(t * 12) > 0 ? 1 : 0;
        for (let i = 0; i < 4; i++) ctx.lineTo(cx + 7 - (i + 0.5) * 3.5, cy + 7 - ((i + wob) % 2 ? 2 : 0));
        ctx.lineTo(cx - 7, cy + 7);
        ctx.closePath();
        ctx.fill();
      }
      if (scared && !d.eaten) {
        rect(ctx, '#ffd6a5', cx - 3, cy - 2, 2, 2);
        rect(ctx, '#ffd6a5', cx + 1, cy - 2, 2, 2);
      } else {
        circle(ctx, '#ffffff', cx - 3, cy - 2, 2.5);
        circle(ctx, '#ffffff', cx + 3, cy - 2, 2.5);
        circle(ctx, '#1c3fff', cx - 3 + (d.dx ?? 0), cy - 2 + (d.dy ?? 0), 1.3);
        circle(ctx, '#1c3fff', cx + 3 + (d.dx ?? 0), cy - 2 + (d.dy ?? 0), 1.3);
      }
      break;
    }
    case 'fire':
      circle(ctx, 'rgba(255,146,43,0.45)', cx, cy, 7);
      circle(ctx, '#ff922b', cx, cy, 4.5);
      circle(ctx, '#ffe066', cx, cy, 2);
      break;
    case 'fireball':
      circle(ctx, '#ff6b00', cx, cy, 4);
      circle(ctx, '#ffd43b', cx + Math.cos(t * 20), cy + Math.sin(t * 20), 2);
      break;
    case 'bullet':
      circle(ctx, 'rgba(255,255,255,0.35)', cx, cy, 3.5);
      rect(ctx, '#ffffff', e.x, e.y, e.w, e.h);
      break;
    case 'bomb':
      circle(ctx, '#212529', cx, cy, 4);
      if (Math.sin(t * 25) > 0) rect(ctx, '#ffd43b', cx + 1, cy - 6, 2, 2);
      break;
    case 'ball':
      circle(ctx, 'rgba(255,255,255,0.25)', cx, cy, 6);
      circle(ctx, e.data.owner ? '#a5d8ff' : '#ffffff', cx, cy, 4);
      rect(ctx, '#ffffff', cx - 2, cy - 2, 1.5, 1.5);
      break;
  }
  ctx.globalAlpha = 1;
  if (e.kind === 'enemy' && e.maxHp >= 3 && e.hp < e.maxHp && e.type !== 'dragon' && e.type !== 'ghost') {
    rect(ctx, 'rgba(0,0,0,0.5)', e.x, e.y - 5, e.w, 2);
    rect(ctx, '#ff6b6b', e.x, e.y - 5, (e.w * Math.max(0, e.hp)) / e.maxHp, 2);
  }
}

function drawDragon(ctx: Ctx, e: Ent, game: Game): void {
  const cx = e.x + e.w / 2;
  const cy = e.y + e.h / 2;
  const f = e.dir || 1;
  const resting = e.data.phase === 2;
  if (game.view === 'top') {
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath();
    ctx.ellipse(cx, cy + (resting ? 10 : 22), 18, 6, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  const flap = resting ? 0.2 : Math.sin(e.t * 9);
  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(f, 1);
  ctx.fillStyle = '#a52a2a';
  for (const s of [-1, 1]) {
    ctx.beginPath();
    ctx.moveTo(-4, 0);
    ctx.lineTo(-10, s * (12 + flap * 8));
    ctx.lineTo(6, s * (14 + flap * 6));
    ctx.lineTo(6, 0);
    ctx.fill();
  }
  ctx.fillStyle = '#7f1d1d';
  ctx.beginPath();
  ctx.ellipse(0, 0, 15, 7, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.moveTo(-14, 0);
  ctx.lineTo(-22, -3);
  ctx.lineTo(-22, 3);
  ctx.fill();
  ctx.fillStyle = '#962d2d';
  ctx.beginPath();
  ctx.ellipse(16, -2, 6, 4.5, 0, 0, Math.PI * 2);
  ctx.fill();
  rect(ctx, '#ffd43b', 18, -4, 2, 2);
  rect(ctx, '#e8e2d0', 13, -8, 2, 3);
  if (e.data.fire !== undefined && e.data.fire < 0.15 && e.data.phase === 0) circle(ctx, '#ff922b', 23, -1, 3);
  ctx.restore();
  if (e.data.phase === 1) {
    ctx.save();
    ctx.globalAlpha = 0.3;
    circle(ctx, '#ffffff', cx, cy, 20);
    ctx.restore();
  }
}
