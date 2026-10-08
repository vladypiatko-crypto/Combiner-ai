import {
  BLOCK,
  BREAK,
  Ent,
  Particle,
  Rect,
  Rng,
  TILE,
  clamp,
  hashString,
  isBreakable,
  len,
  lerp,
  makeEnt,
  overlap,
} from './core';
import { Body, Level, findFreeSpot } from './level';
import { HEROES, WORLDS } from './registry';
import { updateHero, heroHitsEnemy } from './heroes';
import { updateEnt } from './enemies';
import {
  ABILITY_LABEL,
  Ghost,
  GameEvent,
  GoalState,
  HeroDef,
  Input,
  NO_INPUT,
  SfxName,
  WorldDef,
} from './types';

export class Hero implements Body {
  x = 0;
  y = 0;
  w = 12;
  h = 14;
  vx = 0;
  vy = 0;
  onGround = false;
  hp = 5;
  maxHp = 5;
  /** Invulnerability after being hit. */
  inv = 0;
  face = 1;
  fx = 1;
  fy = 0;
  angle = -Math.PI / 2;
  cd = [0, 0, 0];
  dash = 0;
  dashHurts = false;
  hop = 0;
  power = 0;
  coyote = 0;
  jumpBuf = 0;
  anim = 0;
  attack = { kind: '', t: 0, dx: 1, dy: 0 };
  blocks = 12;
  thrusting = false;
  lastSafe = { x: 0, y: 0 };
  /** Snake body in tile coordinates, head first. */
  segs: { x: number; y: number }[] = [];
  prevSegs: { x: number; y: number }[] = [];
  gridDir = { x: 1, y: 0 };
  want = { x: 1, y: 0 };
  gridT = 0;
  grow = 0;
  ballId = 0;
}

export interface GameOptions {
  heroId: string;
  worldId: string;
  seed?: number;
  aspect?: number;
  onEvent?: (e: GameEvent) => void;
}

export class Game {
  heroDef: HeroDef;
  worldDef: WorldDef;
  seed: number;
  aspect: number;
  rng!: Rng;
  level!: Level;
  hero!: Hero;
  ents: Ent[] = [];
  parts: Particle[] = [];
  counts: Record<string, number> = {};
  vars: Record<string, number> = {};
  time = 0;
  score = 0;
  state: 'play' | 'won' | 'lost' = 'play';
  cam = { x: 0, y: 0 };
  viewW = 320;
  viewH = 240;
  shake = 0;
  bannerText = '';
  bannerT = 0;
  input: Input = { ...NO_INPUT };
  prev: Input = { ...NO_INPUT };
  ghosts = new Map<string, Ghost>();
  onEvent: (e: GameEvent) => void;
  private goalCache: GoalState = { text: '', progress: 0, done: false };

  constructor(opts: GameOptions) {
    const hero = HEROES[opts.heroId];
    const world = WORLDS[opts.worldId];
    if (!hero || !world) throw new Error(`Unknown mashup ${opts.heroId} x ${opts.worldId}`);
    this.heroDef = hero;
    this.worldDef = world;
    this.seed = opts.seed ?? hashString(`${opts.heroId}:${opts.worldId}`);
    this.aspect = clamp(opts.aspect ?? 16 / 9, 0.4, 2.6);
    this.onEvent = opts.onEvent ?? (() => {});
    this.reset();
  }

  get view() {
    return this.level.view;
  }

  /** Rebuild the level from the seed. Used for start, retry and race restarts. */
  reset(seed = this.seed): void {
    this.seed = seed;
    this.rng = new Rng(seed);
    this.ents = [];
    this.parts = [];
    this.counts = {};
    this.vars = {};
    this.time = 0;
    this.score = 0;
    this.state = 'play';
    this.bannerT = 0;
    this.shake = 0;
    const h = new Hero();
    h.w = this.heroDef.w;
    h.h = this.heroDef.h;
    h.hp = h.maxHp = this.heroDef.hp;
    this.hero = h;
    this.onTileBroken = () => {};
    this.level = this.worldDef.build(this, this.rng, this.aspect);
    this.placeHero(this.level.spawn.x, this.level.spawn.y);
    this.cam.x = h.x - this.viewW / 2;
    this.cam.y = h.y - this.viewH / 2;
    this.updateCamera(1);
    this.goalCache = this.worldDef.goal(this);
    this.banner(this.worldDef.objective, 3);
  }

  /** Put the hero at a pixel position, snapping to the tile grid for the snake. */
  placeHero(px: number, py: number): void {
    const h = this.hero;
    if (this.heroDef.move[this.view] === 'grid') {
      const tx = Math.floor((px + h.w / 2) / TILE);
      const ty = Math.floor((py + h.h / 2) / TILE);
      const free = findFreeSpot(this.level, TILE, TILE, tx * TILE, ty * TILE);
      const sx = Math.round(free.x / TILE);
      const sy = Math.round(free.y / TILE);
      h.segs = [];
      for (let i = 0; i < 4; i++) h.segs.push({ x: sx, y: sy });
      h.prevSegs = h.segs.map((s) => ({ ...s }));
      h.x = sx * TILE + (TILE - h.w) / 2;
      h.y = sy * TILE + (TILE - h.h) / 2;
    } else {
      const free = findFreeSpot(this.level, h.w, h.h, px, py);
      h.x = free.x;
      h.y = free.y;
    }
    h.vx = h.vy = 0;
    h.lastSafe = { x: h.x, y: h.y };
  }

  buttons(): { a?: string; b?: string; c?: string } {
    const set = this.heroDef.buttons[this.view];
    return {
      a: set[0] ? ABILITY_LABEL[set[0]] : undefined,
      b: set[1] ? ABILITY_LABEL[set[1]] : undefined,
      c: set[2] ? ABILITY_LABEL[set[2]] : undefined,
    };
  }

  setInput(i: Input): void {
    this.input = i;
  }

  pressed(k: 'a' | 'b' | 'c' | 'up'): boolean {
    return this.input[k] && !this.prev[k];
  }

  emit(e: GameEvent): void {
    this.onEvent(e);
  }

  sfx(name: SfxName): void {
    this.onEvent({ type: 'sfx', name });
  }

  banner(text: string, dur = 2): void {
    this.bannerText = text;
    this.bannerT = dur;
    this.onEvent({ type: 'banner', text });
  }

  spawn(e: Ent): Ent {
    this.ents.push(e);
    return e;
  }

  pickup(type: string, x: number, y: number, extra: Partial<Ent> = {}): Ent {
    // Dots are drawn tiny but get a generous hitbox so they are easy to collect.
    const size = type === 'power' ? 12 : 10;
    return this.spawn(makeEnt('pickup', type, x - size / 2, y - size / 2, size, size, extra));
  }

  goal(): GoalState {
    return this.goalCache;
  }

  heroCenter(): [number, number] {
    return [this.hero.x + this.hero.w / 2, this.hero.y + this.hero.h / 2];
  }

  enemies(): Ent[] {
    return this.ents.filter((e) => e.kind === 'enemy' && !e.dead);
  }

  // ---------------------------------------------------------------- effects

  burst(x: number, y: number, color: string, n = 8, speed = 90, grav = 300): void {
    for (let i = 0; i < n; i++) {
      const a = this.rng.range(0, Math.PI * 2);
      const s = this.rng.range(speed * 0.3, speed);
      this.parts.push({
        x,
        y,
        vx: Math.cos(a) * s,
        vy: Math.sin(a) * s - (grav > 0 ? 40 : 0),
        life: this.rng.range(0.3, 0.7),
        max: 0.7,
        color,
        size: this.rng.range(1.5, 3.5),
        grav,
      });
    }
  }

  floatText(x: number, y: number, text: string, color = '#fff'): void {
    this.parts.push({ x, y, vx: 0, vy: -30, life: 0.9, max: 0.9, color, size: 8, grav: 0, text });
  }

  addShake(n: number): void {
    this.shake = Math.max(this.shake, n);
  }

  // ---------------------------------------------------------------- combat

  /** Break a breakable tile, returning true when something was destroyed. */
  breakTile(tx: number, ty: number): boolean {
    const t = this.level.get(tx, ty);
    if (!isBreakable(t)) return false;
    const art = this.level.getArt(tx, ty);
    this.level.set(tx, ty, 0);
    const style = (art ? this.level.theme.variants?.[art] : undefined) ?? this.level.theme.tiles[t];
    this.burst(tx * TILE + 8, ty * TILE + 8, style ? style.c[0] : '#aaa', 6, 70);
    this.sfx('break');
    this.vars.broken = (this.vars.broken ?? 0) + 1;
    if (t === BREAK) this.score += 10;
    this.onTileBroken(tx, ty, art);
    return true;
  }

  /** Hook used by worlds (e.g. "?" blocks drop coins, bricks drop bombs). */
  onTileBroken: (tx: number, ty: number, art: number) => void = () => {};

  breakTilesInCircle(cx: number, cy: number, r: number): number {
    let n = 0;
    const t0x = Math.floor((cx - r) / TILE);
    const t1x = Math.floor((cx + r) / TILE);
    const t0y = Math.floor((cy - r) / TILE);
    const t1y = Math.floor((cy + r) / TILE);
    for (let ty = t0y; ty <= t1y; ty++)
      for (let tx = t0x; tx <= t1x; tx++) {
        const dx = tx * TILE + 8 - cx;
        const dy = ty * TILE + 8 - cy;
        if (dx * dx + dy * dy <= r * r && this.level.get(tx, ty) !== BLOCK && this.breakTile(tx, ty)) n++;
      }
    return n;
  }

  hurtEnemy(e: Ent, dmg: number, fromX: number, fromY: number, knock = 160): void {
    if (e.dead || e.hurt > 0 || e.data.harmless) return;
    if (e.data.invulnerable) {
      this.burst(e.x + e.w / 2, e.y + e.h / 2, '#fff', 3, 40);
      return;
    }
    e.hp -= dmg;
    e.hurt = 0.18;
    const [cx, cy] = [e.x + e.w / 2, e.y + e.h / 2];
    const d = len(cx - fromX, cy - fromY) || 1;
    if (!e.data.heavy) {
      e.vx += ((cx - fromX) / d) * knock;
      e.vy += ((cy - fromY) / d) * knock * (this.view === 'side' ? 0.5 : 1);
    }
    this.burst(cx, cy, '#ffffff', 4, 60);
    this.sfx('hit');
    if (e.hp <= 0) this.killEnemy(e);
  }

  killEnemy(e: Ent): void {
    if (e.type === 'ghost') {
      // Maze ghosts never die: they turn into eyes and fly home.
      e.data.eaten = 1;
      e.hp = e.maxHp;
      this.score += 200;
      this.floatText(e.x, e.y, '+200', '#7df');
      return;
    }
    e.dead = true;
    const cx = e.x + e.w / 2;
    const cy = e.y + e.h / 2;
    const value = e.data.score ?? 100;
    this.score += value;
    this.floatText(cx, cy - 6, `+${value}`, '#ffe066');
    this.burst(cx, cy, e.type === 'rock' ? '#b9b2a6' : '#ff6b6b', 12, 110);
    this.counts.kills = (this.counts.kills ?? 0) + 1;
    this.counts[`kill:${e.type}`] = (this.counts[`kill:${e.type}`] ?? 0) + 1;
    if (e.type === 'rock') splitRock(this, e);
    else if (!e.data.noDrop && this.rng.chance(0.1)) this.pickup('heart', cx, cy);
  }

  /** Damage every enemy (and optionally tiles) inside a rectangle. */
  hitRect(r: Rect, dmg: number, knock: number, breaks: boolean): number {
    const [hx, hy] = this.heroCenter();
    let hits = 0;
    for (const e of this.ents) {
      if (e.dead) continue;
      if (e.kind === 'enemy' && overlap(r, e)) {
        this.hurtEnemy(e, dmg, hx, hy, knock);
        hits++;
      } else if (e.kind === 'proj' && !e.friendly && overlap(r, e)) {
        e.dead = true;
      }
    }
    if (breaks) {
      const x0 = Math.floor(r.x / TILE);
      const x1 = Math.floor((r.x + r.w) / TILE);
      const y0 = Math.floor(r.y / TILE);
      const y1 = Math.floor((r.y + r.h) / TILE);
      for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) if (this.level.get(tx, ty) === BREAK) this.breakTile(tx, ty);
    }
    return hits;
  }

  damageHero(n: number, fromX: number, fromY: number): void {
    const h = this.hero;
    if (this.state !== 'play' || h.inv > 0 || h.dash > 0 || h.hop > 0 || h.power > 0) return;
    h.hp -= n;
    h.inv = 1.3;
    const [cx, cy] = this.heroCenter();
    const d = len(cx - fromX, cy - fromY) || 1;
    if (this.heroDef.move[this.view] !== 'grid') {
      h.vx = ((cx - fromX) / d) * 190;
      h.vy = ((cy - fromY) / d) * 190 - (this.view === 'side' ? 120 : 0);
    }
    this.addShake(5);
    this.burst(cx, cy, '#ff4d4d', 10, 100);
    this.sfx('hurt');
    if (h.hp <= 0) this.lose();
  }

  heal(n: number): void {
    this.hero.hp = Math.min(this.hero.maxHp, this.hero.hp + n);
  }

  /** Move the hero back into play after a fall or a squish. */
  respawnHero(): void {
    const h = this.hero;
    const L = this.level;
    if (L.camera === 'autoscroll') {
      const cx = this.cam.x + this.viewW * 0.45;
      const tx0 = Math.floor(cx / TILE);
      const mode = this.heroDef.move[this.view];
      for (let r = 0; r < 12; r++) {
        for (const tx of [tx0 + r, tx0 - r]) {
          const row = standRow(L, tx);
          if (row < 0) continue;
          if (mode === 'platform' || mode === 'grid' || mode === 'free') {
            this.placeHero(tx * TILE, row * TILE - h.h + TILE - 1);
            h.inv = 1.5;
            return;
          }
          this.placeHero(tx * TILE, (row - 4) * TILE);
          h.inv = 1.5;
          return;
        }
      }
    }
    this.placeHero(h.lastSafe.x, h.lastSafe.y);
    h.inv = 1.5;
  }

  win(): void {
    if (this.state !== 'play') return;
    this.state = 'won';
    this.score += Math.max(0, Math.round(3000 - this.time * 10));
    this.sfx('win');
    this.emit({ type: 'won', time: this.time, score: this.score });
  }

  lose(): void {
    if (this.state !== 'play') return;
    this.state = 'lost';
    this.sfx('lose');
    this.emit({ type: 'lost', time: this.time, score: this.score });
  }

  // ---------------------------------------------------------------- loop

  step(dt: number): void {
    this.updateParticles(dt);
    if (this.bannerT > 0) this.bannerT -= dt;
    this.shake = Math.max(0, this.shake - dt * 20);
    if (this.state !== 'play') {
      this.prev = { ...this.input };
      return;
    }
    this.time += dt;
    updateHero(this, dt);
    for (let i = 0; i < this.ents.length; i++) {
      const e = this.ents[i];
      if (!e.dead) updateEnt(this, e, dt);
    }
    this.collide();
    this.worldDef.update?.(this, dt);
    this.ents = this.ents.filter((e) => !e.dead);
    this.updateCamera(dt);
    this.goalCache = this.worldDef.goal(this);
    if (this.goalCache.done) this.win();
    this.prev = { ...this.input };
  }

  private collide(): void {
    const h = this.hero;
    const grid = this.heroDef.move[this.view] === 'grid';
    for (const e of this.ents) {
      if (e.dead) continue;
      if (e.kind === 'pickup') {
        if (overlap(h, e)) this.collect(e);
        continue;
      }
      if (e.kind === 'flag') {
        if (overlap(h, e)) this.vars.flag = 1;
        continue;
      }
      if (e.kind === 'proj' && !e.friendly) {
        if (overlap(h, e) || (grid && this.bodyHit(e))) {
          e.dead = true;
          this.damageHero(e.dmg, e.x + e.w / 2, e.y + e.h / 2);
        }
        continue;
      }
      if (e.kind !== 'enemy' || e.data.harmless || e.data.eaten) continue;
      if (overlap(h, e)) heroHitsEnemy(this, e);
      else if (grid && this.bodyHit(e)) this.damageHero(1, e.x + e.w / 2, e.y + e.h / 2);
    }
  }

  /** Snake body (not head) overlapping an entity. */
  private bodyHit(e: Ent): boolean {
    const segs = this.hero.segs;
    for (let i = 2; i < segs.length; i++) {
      const r = { x: segs[i].x * TILE + 3, y: segs[i].y * TILE + 3, w: 10, h: 10 };
      if (overlap(r, e)) return true;
    }
    return false;
  }

  collect(e: Ent): void {
    e.dead = true;
    const type = e.type;
    this.counts[type] = (this.counts[type] ?? 0) + 1;
    const values: Record<string, number> = { coin: 10, diamond: 100, rune: 500, apple: 50, pellet: 10, power: 50, heart: 0 };
    const v = values[type] ?? 10;
    this.score += v;
    const cx = e.x + e.w / 2;
    const cy = e.y + e.h / 2;
    if (type === 'heart') {
      this.heal(1);
      this.floatText(cx, cy, '+1 ♥', '#ff6b8a');
    } else if (type === 'power') {
      this.hero.power = Math.max(this.hero.power, 6);
      this.sfx('power');
    } else if (v >= 50) {
      this.floatText(cx, cy, `+${v}`, '#ffe066');
    }
    if (type !== 'pellet') this.burst(cx, cy, type === 'diamond' ? '#6ff' : '#ffd84d', 6, 60, 0);
    this.sfx('pickup');
    this.hero.grow += 1;
    this.worldDef.onPickup?.(this, type);
  }

  private updateParticles(dt: number): void {
    for (const p of this.parts) {
      p.life -= dt;
      p.vy += p.grav * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
    this.parts = this.parts.filter((p) => p.life > 0);
    if (this.parts.length > 400) this.parts.splice(0, this.parts.length - 400);
  }

  setView(w: number, h: number): void {
    this.viewW = w;
    this.viewH = h;
  }

  updateCamera(dt: number): void {
    const L = this.level;
    const [hx, hy] = this.heroCenter();
    const fit = (v: number, view: number, size: number) => (size <= view ? (size - view) / 2 : clamp(v, 0, size - view));
    if (L.camera === 'fixed') {
      this.cam.x = (L.pxW - this.viewW) / 2;
      this.cam.y = (L.pxH - this.viewH) / 2;
      return;
    }
    if (L.camera === 'autoscroll') {
      if (this.time > 1.5) this.cam.x += L.scrollSpeed * dt;
      // Never fall too far behind a fast hero.
      this.cam.x = Math.max(this.cam.x, hx - this.viewW * 0.7);
      this.cam.x = fit(this.cam.x, this.viewW, L.pxW);
      this.cam.y = fit(lerp(this.cam.y, hy - this.viewH / 2, Math.min(1, dt * 4)), this.viewH, L.pxH);
      return;
    }
    const k = Math.min(1, dt * 6);
    this.cam.x = fit(lerp(this.cam.x, hx - this.viewW / 2, k), this.viewW, L.pxW);
    this.cam.y = fit(lerp(this.cam.y, hy - this.viewH / 2, k), this.viewH, L.pxH);
  }

  /** Data broadcast to other racers: compact and JSON friendly. */
  snapshot() {
    const h = this.hero;
    return {
      x: Math.round(h.x),
      y: Math.round(h.y),
      f: h.face,
      hp: h.hp,
      p: Math.round(this.goalCache.progress * 1000) / 1000,
      d: this.state === 'won',
      s: this.score,
    };
  }
}

/** Highest empty row directly above the bottom-most solid run of column tx. */
export function standRow(L: Level, tx: number): number {
  if (tx < 0 || tx >= L.w) return -1;
  let ty = L.h - 1;
  if (!L.solidAt(tx * TILE + 1, ty * TILE + 1)) return -1;
  while (ty > 0 && L.solidAt(tx * TILE + 1, ty * TILE + 1)) ty--;
  return ty;
}

function splitRock(game: Game, e: Ent): void {
  const size = e.data.size ?? 1;
  if (size <= 1) return;
  for (let i = 0; i < 2; i++) {
    const s = size - 1;
    const px = s === 2 ? 20 : 12;
    const a = game.rng.range(0, Math.PI * 2);
    const sp = game.rng.range(35, 70) * (1 + (3 - s) * 0.25);
    game.spawn(
      makeEnt('enemy', 'rock', e.x + e.w / 2 - px / 2, e.y + e.h / 2 - px / 2, px, px, {
        vx: Math.cos(a) * sp,
        vy: Math.sin(a) * sp,
        hp: s,
        maxHp: s,
        data: { size: s, seed: game.rng.int(1, 1e6), spin: game.rng.range(-2, 2), noDrop: 1, score: 50 * (4 - s) },
      }),
    );
  }
}
