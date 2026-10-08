// Shared engine primitives: tiles, RNG, math helpers and the entity shape.

export const TILE = 16;

// Tile ids. Solid tiles block movement; BREAK and BLOCK can be destroyed.
export const EMPTY = 0;
export const WALL = 1;
export const BREAK = 2;
export const BLOCK = 3;
export const HAZARD = 4;

export type View = 'side' | 'top';

export function isSolid(t: number): boolean {
  return t === WALL || t === BREAK || t === BLOCK;
}

export function isBreakable(t: number): boolean {
  return t === BREAK || t === BLOCK;
}

/** Small, fast, seedable PRNG (mulberry32). Same seed => same level everywhere. */
export class Rng {
  private s: number;
  constructor(seed: number) {
    this.s = seed >>> 0 || 0x9e3779b9;
  }
  next(): number {
    let t = (this.s = (this.s + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  range(a: number, b: number): number {
    return a + (b - a) * this.next();
  }
  int(a: number, b: number): number {
    return Math.floor(this.range(a, b + 1));
  }
  chance(p: number): boolean {
    return this.next() < p;
  }
  pick<T>(arr: readonly T[]): T {
    return arr[Math.floor(this.next() * arr.length)];
  }
}

export function hashString(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

export const clamp = (v: number, a: number, b: number) => (v < a ? a : v > b ? b : v);
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const approach = (v: number, target: number, step: number) => (v < target ? Math.min(v + step, target) : Math.max(v - step, target));

export function len(x: number, y: number): number {
  return Math.sqrt(x * x + y * y);
}

export function norm(x: number, y: number): [number, number] {
  const l = Math.sqrt(x * x + y * y);
  return l > 1e-6 ? [x / l, y / l] : [0, 0];
}

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export function overlap(a: Rect, b: Rect): boolean {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

export type EntKind = 'enemy' | 'pickup' | 'proj' | 'ball' | 'flag';

/**
 * One struct for every non-hero object. `type` selects behaviour and art;
 * `data` holds per-type state so the core stays small.
 */
export interface Ent extends Rect {
  id: number;
  kind: EntKind;
  type: string;
  vx: number;
  vy: number;
  hp: number;
  maxHp: number;
  dir: number;
  t: number;
  hurt: number;
  dead: boolean;
  onGround: boolean;
  friendly: boolean;
  dmg: number;
  data: Record<string, number>;
}

let nextId = 1;
export function makeEnt(kind: EntKind, type: string, x: number, y: number, w: number, h: number, extra: Partial<Ent> = {}): Ent {
  return {
    id: nextId++,
    kind,
    type,
    x,
    y,
    w,
    h,
    vx: 0,
    vy: 0,
    hp: 1,
    maxHp: 1,
    dir: 1,
    t: 0,
    hurt: 0,
    dead: false,
    onGround: false,
    friendly: false,
    dmg: 1,
    data: {},
    ...extra,
  };
}

export interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  max: number;
  color: string;
  size: number;
  grav: number;
  text?: string;
}
