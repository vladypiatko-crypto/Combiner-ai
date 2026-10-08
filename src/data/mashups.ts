import { BASE, BASE_GAMES, HEROES, WORLDS } from '../engine/registry';

export interface MashupInfo {
  id: string;
  hero: string;
  world: string;
  title: string;
  subtitle: string;
  pitch: string;
}

export function mashupId(hero: string, world: string): string {
  return `${hero}-x-${world}`;
}

export function parseMashupId(id: string): { hero: string; world: string } | null {
  const m = /^([a-z]+)-x-([a-z]+)$/.exec(id);
  if (!m || !BASE[m[1]] || !BASE[m[2]]) return null;
  return { hero: m[1], world: m[2] };
}

const TITLES: Record<string, string> = {
  'blockcraft-x-dragonrealm': 'Blockrim',
  'dragonrealm-x-blockcraft': 'Dragoncraft',
  'flappy-x-rocks': 'Flappyroids',
  'snake-x-jumper': 'Snakejump',
  'jumper-x-maze': 'Super Maze',
  'maze-x-dragonrealm': 'Chomprim',
  'rocks-x-bricks': 'Rocket Breaker',
  'bricks-x-blockcraft': 'Paddlecraft',
  'blockcraft-x-flappy': 'Blockflap',
  'dragonrealm-x-maze': 'Dungeon Maze',
  'snake-x-rocks': 'Snakeroids',
  'jumper-x-dragonrealm': 'Super Dragon Realm',
};

const PITCHES: Record<string, string> = {
  'blockcraft-x-dragonrealm':
    'Our take on the famous "SkyCraft" idea: a blocky miner in a dragon-haunted tundra. Mine through cracked ruins, wall yourself in with blocks and take down the dragon with a pickaxe.',
  'dragonrealm-x-blockcraft': 'A horned knight drops into a blocky overworld. Sword through zombies, shout creepers off cliffs and dig for diamonds.',
  'flappy-x-rocks': 'Gravity is gone and the pipes became asteroids. Flap and peck-dash your way through a rock storm.',
  'snake-x-jumper': 'A snake in a side-scrolling kingdom. Slither over pits, bite the mushrooms and eat every coin on the way to the flag.',
  'jumper-x-maze': 'The plumber is lost in the ghost maze. Hop over ghosts, throw fireballs and clear every dot.',
  'maze-x-dragonrealm': 'A hungry chomper vs a dragon. Gobble runes in the ruins, then power up and eat the dragon whole.',
  'rocks-x-bricks': 'A tiny spaceship keeps the ball alive and blasts bricks with its laser.',
  'bricks-x-blockcraft': 'A hover-paddle hunting diamonds in a blocky world, smashing caves open with its ball.',
  'blockcraft-x-flappy': 'No wings? No problem. Run, jump and build bridges of blocks through the scrolling pipe gauntlet.',
  'dragonrealm-x-maze': 'A knight in the ghost maze: swing your sword and shout ghosts back into their house.',
  'snake-x-rocks': 'A wrap-around snake in an asteroid field. Bite rocks into pebbles without biting yourself.',
  'jumper-x-dragonrealm': 'The plumber goes north: hop on wolves, fireball the draugr and stomp a dragon.',
};

export function mashupTitle(hero: string, world: string): string {
  const id = mashupId(hero, world);
  if (TITLES[id]) return TITLES[id];
  if (hero === world) return `${BASE[hero].name} Classic`;
  const t = BASE[hero].pre + BASE[world].suf;
  return t[0].toUpperCase() + t.slice(1);
}

export function mashupInfo(hero: string, world: string): MashupInfo {
  const id = mashupId(hero, world);
  const h = HEROES[hero];
  const w = WORLDS[world];
  const subtitle = hero === world ? `The original ${BASE[world].name}` : `Play ${w.name} as the ${BASE[hero].name} ${h.name.toLowerCase()}`;
  const pitch =
    PITCHES[id] ??
    (hero === world
      ? `${BASE[world].blurb} The base game every mashup is built from.`
      : `The ${h.name.toLowerCase()} from ${BASE[hero].name} brings its moves into ${w.name}: ${h.verbs}. Goal: ${w.objective.toLowerCase()}.`);
  return { id, hero, world, title: mashupTitle(hero, world), subtitle, pitch };
}

export const FEATURED: string[] = [
  'blockcraft-x-dragonrealm',
  'dragonrealm-x-blockcraft',
  'snake-x-jumper',
  'flappy-x-rocks',
  'jumper-x-maze',
  'maze-x-dragonrealm',
  'blockcraft-x-flappy',
  'rocks-x-bricks',
  'bricks-x-blockcraft',
  'dragonrealm-x-maze',
  'snake-x-rocks',
  'jumper-x-dragonrealm',
];

export function allMashups(): MashupInfo[] {
  const out: MashupInfo[] = [];
  for (const a of BASE_GAMES) for (const b of BASE_GAMES) out.push(mashupInfo(a.id, b.id));
  return out;
}

export function randomMashup(): { hero: string; world: string } {
  const ids = BASE_GAMES.map((g) => g.id);
  const hero = ids[Math.floor(Math.random() * ids.length)];
  let world = ids[Math.floor(Math.random() * ids.length)];
  if (world === hero) world = ids[(ids.indexOf(hero) + 1 + Math.floor(Math.random() * (ids.length - 1))) % ids.length];
  return { hero, world };
}
