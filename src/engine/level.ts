import { BREAK, EMPTY, TILE, View, WALL, isSolid } from './core';

export type TilePattern =
  | 'plain'
  | 'grass'
  | 'dirt'
  | 'stone'
  | 'ore'
  | 'wood'
  | 'leaves'
  | 'plank'
  | 'brick'
  | 'question'
  | 'pipe'
  | 'tree'
  | 'rock'
  | 'water'
  | 'ruin'
  | 'maze'
  | 'steel'
  | 'hedge';

export interface TileStyle {
  /** [base, highlight, shadow] */
  c: [string, string, string];
  p?: TilePattern;
}

export interface Theme {
  /** Top and bottom colours of the sky / floor gradient. */
  bg: [string, string];
  /** Default style per tile id. */
  tiles: Record<number, TileStyle>;
  /** Styles selected by a tile's art byte (index 0 means "use the default"). */
  variants?: TileStyle[];
  /** Ground colour for top-down worlds (drawn under everything). */
  ground?: string;
  /** Decorative background style. */
  decor: 'clouds' | 'stars' | 'snow' | 'hills' | 'none' | 'grid';
}

export type CameraMode = 'follow' | 'fixed' | 'autoscroll';

export class Level {
  tiles: Uint8Array;
  /** Per-tile variant byte used for art (grass vs dirt, ore colour, brick row…). */
  art: Uint8Array;
  spawn = { x: 2 * TILE, y: 2 * TILE };
  camera: CameraMode = 'follow';
  scrollSpeed = 0;
  wrap = false;
  /** Side-view worlds: falling out of the bottom is a pit. */
  pitBottom = true;
  /** Maze graph for Ghost Maze: per-cell open-side bitmask (N=1, E=2, S=4, W=8). */
  maze: { cols: number; rows: number; open: Uint8Array; houseX: number; houseY: number } | null = null;

  constructor(
    public w: number,
    public h: number,
    public view: View,
    public theme: Theme,
  ) {
    this.tiles = new Uint8Array(w * h);
    this.art = new Uint8Array(w * h);
  }

  get pxW() {
    return this.w * TILE;
  }
  get pxH() {
    return this.h * TILE;
  }

  inside(tx: number, ty: number): boolean {
    return tx >= 0 && ty >= 0 && tx < this.w && ty < this.h;
  }

  get(tx: number, ty: number): number {
    if (this.wrap) {
      tx = ((tx % this.w) + this.w) % this.w;
      ty = ((ty % this.h) + this.h) % this.h;
      return this.tiles[ty * this.w + tx];
    }
    if (tx < 0 || tx >= this.w || ty < 0) return WALL;
    if (ty >= this.h) return this.view === 'side' && this.pitBottom ? EMPTY : WALL;
    return this.tiles[ty * this.w + tx];
  }

  set(tx: number, ty: number, v: number, art = 0): void {
    if (!this.inside(tx, ty)) return;
    this.tiles[ty * this.w + tx] = v;
    this.art[ty * this.w + tx] = art;
  }

  getArt(tx: number, ty: number): number {
    if (!this.inside(tx, ty)) return 0;
    return this.art[ty * this.w + tx];
  }

  fill(x0: number, y0: number, x1: number, y1: number, v: number, art = 0): void {
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) this.set(x, y, v, art);
  }

  solidAt(px: number, py: number): boolean {
    return isSolid(this.get(Math.floor(px / TILE), Math.floor(py / TILE)));
  }

  /** True when an axis-aligned box touches no solid tile. */
  boxFree(x: number, y: number, w: number, h: number): boolean {
    const x0 = Math.floor(x / TILE);
    const x1 = Math.floor((x + w - 0.01) / TILE);
    const y0 = Math.floor(y / TILE);
    const y1 = Math.floor((y + h - 0.01) / TILE);
    for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) if (isSolid(this.get(tx, ty))) return false;
    return true;
  }

  countTiles(id: number): number {
    let n = 0;
    for (let i = 0; i < this.tiles.length; i++) if (this.tiles[i] === id) n++;
    return n;
  }

  /** Surface row of column tx for side worlds: first solid tile from the top. */
  surface(tx: number): number {
    for (let ty = 0; ty < this.h; ty++) if (isSolid(this.get(tx, ty))) return ty;
    return this.h;
  }

  breakableCount(): number {
    return this.countTiles(BREAK);
  }
}

export interface Body {
  x: number;
  y: number;
  w: number;
  h: number;
  vx: number;
  vy: number;
  onGround: boolean;
}

export interface MoveResult {
  hitX: boolean;
  hitY: boolean;
  /** Tile that stopped horizontal / vertical movement (for bricks, mining…). */
  tileX: [number, number] | null;
  tileY: [number, number] | null;
}

function sweepX(level: Level, b: Body, d: number, res: MoveResult): void {
  b.x += d;
  const y0 = Math.floor(b.y / TILE);
  const y1 = Math.floor((b.y + b.h - 0.01) / TILE);
  if (d > 0) {
    const tx = Math.floor((b.x + b.w - 0.01) / TILE);
    for (let ty = y0; ty <= y1; ty++) {
      if (isSolid(level.get(tx, ty))) {
        b.x = tx * TILE - b.w;
        res.hitX = true;
        res.tileX = [tx, ty];
        return;
      }
    }
  } else if (d < 0) {
    const tx = Math.floor(b.x / TILE);
    for (let ty = y0; ty <= y1; ty++) {
      if (isSolid(level.get(tx, ty))) {
        b.x = (tx + 1) * TILE;
        res.hitX = true;
        res.tileX = [tx, ty];
        return;
      }
    }
  }
}

function sweepY(level: Level, b: Body, d: number, res: MoveResult): void {
  b.y += d;
  const x0 = Math.floor(b.x / TILE);
  const x1 = Math.floor((b.x + b.w - 0.01) / TILE);
  if (d > 0) {
    const ty = Math.floor((b.y + b.h - 0.01) / TILE);
    for (let tx = x0; tx <= x1; tx++) {
      if (isSolid(level.get(tx, ty))) {
        b.y = ty * TILE - b.h;
        res.hitY = true;
        res.tileY = [tx, ty];
        return;
      }
    }
  } else if (d < 0) {
    const ty = Math.floor(b.y / TILE);
    for (let tx = x0; tx <= x1; tx++) {
      if (isSolid(level.get(tx, ty))) {
        b.y = (ty + 1) * TILE;
        res.hitY = true;
        res.tileY = [tx, ty];
        return;
      }
    }
  }
}

/** Move a body by its velocity, resolving collisions against solid tiles. */
export function moveBody(level: Level, b: Body, dt: number, ghost = false): MoveResult {
  const res: MoveResult = { hitX: false, hitY: false, tileX: null, tileY: null };
  const dx = b.vx * dt;
  const dy = b.vy * dt;
  if (ghost) {
    b.x += dx;
    b.y += dy;
  } else {
    const steps = Math.max(1, Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / (TILE * 0.4)));
    for (let i = 0; i < steps; i++) {
      if (!res.hitX) sweepX(level, b, dx / steps, res);
      if (!res.hitY) sweepY(level, b, dy / steps, res);
    }
  }
  if (res.hitX) b.vx = 0;
  b.onGround = res.hitY && dy > 0;
  if (res.hitY) b.vy = 0;
  if (level.wrap) {
    const W = level.pxW;
    const H = level.pxH;
    b.x = ((b.x % W) + W) % W;
    b.y = ((b.y % H) + H) % H;
  }
  return res;
}

/** Find an empty spot of the given size, preferring positions near (px, py). */
export function findFreeSpot(level: Level, w: number, h: number, px: number, py: number, maxR = 20): { x: number; y: number } {
  const cx = Math.floor(px / TILE);
  const cy = Math.floor(py / TILE);
  for (let r = 0; r <= maxR; r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        const x = (cx + dx) * TILE + (TILE - w) / 2;
        const y = (cy + dy) * TILE + (TILE - h) / 2;
        if (level.inside(cx + dx, cy + dy) && level.boxFree(x, y, w, h)) return { x, y };
      }
    }
  }
  return { x: px, y: py };
}
