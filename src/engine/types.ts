import type { Rng, View } from './core';
import type { Game } from './game';
import type { Level } from './level';

export interface Input {
  /** Analog stick, -1..1 on each axis (keyboard gives -1/0/1). */
  x: number;
  y: number;
  a: boolean;
  b: boolean;
  c: boolean;
  /** Keyboard "up" key; lets desktop players jump with ↑ as well as Space. */
  up: boolean;
}

export const NO_INPUT: Input = { x: 0, y: 0, a: false, b: false, c: false, up: false };

export type Ability =
  | 'jump'
  | 'flap'
  | 'dash'
  | 'hop'
  | 'mine'
  | 'place'
  | 'sword'
  | 'shout'
  | 'peck'
  | 'fireball'
  | 'shoot'
  | 'warp'
  | 'boost'
  | 'ball'
  | 'power';

export type MoveMode = 'platform' | 'flap' | 'thrust' | 'free' | 'grid';

export const ABILITY_LABEL: Record<Ability, string> = {
  jump: 'Jump',
  flap: 'Flap',
  dash: 'Dash',
  hop: 'Hop',
  mine: 'Mine',
  place: 'Place',
  sword: 'Sword',
  shout: 'Shout',
  peck: 'Peck',
  fireball: 'Fire',
  shoot: 'Shoot',
  warp: 'Warp',
  boost: 'Boost',
  ball: 'Ball',
  power: 'Power',
};

export type ButtonSet = [Ability?, Ability?, Ability?];

export interface HeroDef {
  /** Same id as the base game it comes from. */
  id: string;
  name: string;
  w: number;
  h: number;
  hp: number;
  /** Top running / flying speed in px per second. */
  speed: number;
  jumpV?: number;
  move: Record<View, MoveMode>;
  buttons: Record<View, ButtonSet>;
  /** Short line shown on mashup pages, e.g. "mine and build blocks". */
  verbs: string;
}

export interface GoalState {
  text: string;
  progress: number;
  done: boolean;
}

export interface WorldDef {
  id: string;
  name: string;
  view: View;
  /** One-line description of the objective. */
  objective: string;
  build(game: Game, rng: Rng, aspect: number): Level;
  update?(game: Game, dt: number): void;
  goal(game: Game): GoalState;
  onPickup?(game: Game, type: string): void;
}

export interface Ghost {
  name: string;
  color: string;
  x: number;
  y: number;
  face: number;
  progress: number;
  hp: number;
  done: boolean;
  seen: number;
}

export type GameEvent =
  | { type: 'won'; time: number; score: number }
  | { type: 'lost'; time: number; score: number }
  | { type: 'sfx'; name: SfxName }
  | { type: 'banner'; text: string };

export type SfxName =
  | 'jump'
  | 'hit'
  | 'hurt'
  | 'pickup'
  | 'break'
  | 'shoot'
  | 'power'
  | 'boom'
  | 'win'
  | 'lose'
  | 'place'
  | 'shout';
