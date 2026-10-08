import { describe, expect, it } from 'vitest';
import { Rng, isSolid } from '../src/engine/core';
import { Game } from '../src/engine/game';
import { BASE_GAMES } from '../src/engine/registry';
import type { Input } from '../src/engine/types';

const ids = BASE_GAMES.map((g) => g.id);

function randomInput(r: Rng, prev: Input): Input {
  // Hold inputs for a while like a person would, with occasional changes.
  if (r.chance(0.9)) return prev;
  return { x: r.pick([-1, 0, 1]), y: r.pick([-1, 0, 0, 1]), a: r.chance(0.4), b: r.chance(0.4), c: r.chance(0.2), up: false };
}

describe('every mashup runs', () => {
  for (const hero of ids) {
    for (const world of ids) {
      it(`${hero} x ${world}`, () => {
        for (const aspect of [0.55, 1.78]) {
          const game = new Game({ heroId: hero, worldId: world, aspect });
          game.setView(aspect < 1 ? 192 : 426, aspect < 1 ? 340 : 240);
          const r = new Rng(42);
          let input: Input = { x: 0, y: 0, a: false, b: false, c: false, up: false };
          for (let i = 0; i < 60 * 25; i++) {
            input = randomInput(r, input);
            game.setInput(input);
            game.step(1 / 60);
            if (game.state !== 'play') game.reset();
          }
          const h = game.hero;
          expect(Number.isFinite(h.x) && Number.isFinite(h.y)).toBe(true);
          expect(game.goal().text.length).toBeGreaterThan(0);
          for (const e of game.ents) expect(Number.isFinite(e.x) && Number.isFinite(e.y)).toBe(true);
        }
      });
    }
  }
});

describe('levels are deterministic per seed', () => {
  it('same seed builds the same level', () => {
    for (const world of ids) {
      const a = new Game({ heroId: 'blockcraft', worldId: world, seed: 1234, aspect: 1 });
      const b = new Game({ heroId: 'blockcraft', worldId: world, seed: 1234, aspect: 1 });
      expect(Array.from(a.level.tiles)).toEqual(Array.from(b.level.tiles));
      expect(a.ents.length).toBe(b.ents.length);
    }
  });
});

describe('goals', () => {
  it('collecting 8 diamonds wins Blockcraft', () => {
    const g = new Game({ heroId: 'blockcraft', worldId: 'blockcraft' });
    const diamonds = g.ents.filter((e) => e.type === 'diamond');
    expect(diamonds.length).toBeGreaterThanOrEqual(8);
    for (const d of diamonds.slice(0, 8)) g.collect(d);
    g.step(1 / 60);
    expect(g.state).toBe('won');
  });

  it('eating every dot wins Ghost Maze', () => {
    const g = new Game({ heroId: 'maze', worldId: 'maze' });
    for (const d of g.ents.filter((e) => e.type === 'pellet' || e.type === 'power')) g.collect(d);
    g.step(1 / 60);
    expect(g.state).toBe('won');
  });

  it('dragon spawns after three runes', () => {
    const g = new Game({ heroId: 'dragonrealm', worldId: 'dragonrealm' });
    for (const r of g.ents.filter((e) => e.type === 'rune')) g.collect(r);
    g.step(1 / 60);
    expect(g.ents.some((e) => e.type === 'dragon')).toBe(true);
    expect(g.state).toBe('play');
  });

  it('runes are reachable from spawn in Dragon Realm', () => {
    for (let seed = 1; seed < 30; seed++) {
      const g = new Game({ heroId: 'blockcraft', worldId: 'dragonrealm', seed });
      const L = g.level;
      const seen = new Set<number>();
      const sx = Math.floor((g.hero.x + 6) / 16);
      const sy = Math.floor((g.hero.y + 6) / 16);
      const q = [[sx, sy]];
      seen.add(sy * L.w + sx);
      while (q.length) {
        const [x, y] = q.pop()!;
        for (const [dx, dy] of [
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1],
        ]) {
          const nx = x + dx;
          const ny = y + dy;
          const k = ny * L.w + nx;
          if (seen.has(k) || isSolid(L.get(nx, ny))) continue;
          seen.add(k);
          q.push([nx, ny]);
        }
      }
      for (const r of g.ents.filter((e) => e.type === 'rune')) {
        const k = Math.floor((r.y + 5) / 16) * L.w + Math.floor((r.x + 5) / 16);
        expect(seen.has(k)).toBe(true);
      }
    }
  });

  it('breaking every brick wins Brick Breaker', () => {
    const g = new Game({ heroId: 'bricks', worldId: 'bricks', aspect: 0.6 });
    for (let y = 0; y < g.level.h; y++) for (let x = 0; x < g.level.w; x++) g.breakTile(x, y);
    g.step(1 / 60);
    expect(g.state).toBe('won');
  });
});
