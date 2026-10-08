import { HERO_DEFS } from './heroes';
import type { HeroDef, WorldDef } from './types';
import { WORLD_DEFS } from './worlds';

export const HEROES: Record<string, HeroDef> = Object.fromEntries(HERO_DEFS.map((h) => [h.id, h]));
export const WORLDS: Record<string, WorldDef> = Object.fromEntries(WORLD_DEFS.map((w) => [w.id, w]));

export interface BaseGame {
  id: string;
  name: string;
  /** The famous game this archetype is a loving nod to. */
  inspiredBy: string;
  emoji: string;
  color: string;
  /** Name parts used to build mashup titles: hero prefix + world suffix. */
  pre: string;
  suf: string;
  blurb: string;
}

export const BASE_GAMES: BaseGame[] = [
  {
    id: 'blockcraft',
    name: 'Blockcraft',
    inspiredBy: 'Minecraft',
    emoji: '⛏️',
    color: '#5fa83a',
    pre: 'Block',
    suf: 'craft',
    blurb: 'Mine, build and survive in a blocky world.',
  },
  {
    id: 'dragonrealm',
    name: 'Dragon Realm',
    inspiredBy: 'Skyrim',
    emoji: '🐉',
    color: '#8aa2b8',
    pre: 'Dragon',
    suf: 'rim',
    blurb: 'Explore ruins, learn shouts and slay a dragon.',
  },
  {
    id: 'flappy',
    name: 'Flappy Wings',
    inspiredBy: 'Flappy Bird',
    emoji: '🐤',
    color: '#f5c542',
    pre: 'Flappy',
    suf: 'flap',
    blurb: 'Tap to flap through an endless pipe gauntlet.',
  },
  {
    id: 'jumper',
    name: 'Super Jumper',
    inspiredBy: 'Super Mario Bros.',
    emoji: '🍄',
    color: '#e5423a',
    pre: 'Super',
    suf: 'jump',
    blurb: 'Run, jump and stomp across a side-scrolling kingdom.',
  },
  {
    id: 'snake',
    name: 'Snake',
    inspiredBy: 'Snake',
    emoji: '🐍',
    color: '#40c057',
    pre: 'Snake',
    suf: 'snake',
    blurb: 'Eat, grow and never bite your own tail.',
  },
  {
    id: 'rocks',
    name: 'Space Rocks',
    inspiredBy: 'Asteroids',
    emoji: '🚀',
    color: '#9b8cff',
    pre: 'Rocket',
    suf: 'roids',
    blurb: 'Thrust, drift and blast rocks into smaller rocks.',
  },
  {
    id: 'bricks',
    name: 'Brick Breaker',
    inspiredBy: 'Breakout',
    emoji: '🧱',
    color: '#ff8a3d',
    pre: 'Paddle',
    suf: 'breaker',
    blurb: 'Bounce the ball and smash the wall.',
  },
  {
    id: 'maze',
    name: 'Ghost Maze',
    inspiredBy: 'Pac-Man',
    emoji: '👻',
    color: '#ffd43b',
    pre: 'Chomp',
    suf: 'maze',
    blurb: 'Gobble every dot and turn the tables on ghosts.',
  },
];

export const BASE: Record<string, BaseGame> = Object.fromEntries(BASE_GAMES.map((g) => [g.id, g]));
