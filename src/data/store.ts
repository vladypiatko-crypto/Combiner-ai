// Everything is stored on the device: no accounts, no servers, no cost.

export type ProviderId = 'openrouter' | 'gemini' | 'anthropic' | 'custom' | 'manual';

export interface Settings {
  name: string;
  color: string;
  provider: ProviderId;
  keys: Partial<Record<ProviderId, string>>;
  models: Partial<Record<ProviderId, string>>;
  customBase: string;
  sound: boolean;
  touch: 'auto' | 'on' | 'off';
  turnUrl: string;
  turnUser: string;
  turnPass: string;
}

const COLORS = ['#ff5c8a', '#43e3c4', '#ffd43b', '#5b8cff', '#ff8a4c', '#b197fc', '#51cf66'];
const NAMES = ['Pixel', 'Turbo', 'Nova', 'Glitch', 'Combo', 'Byte', 'Comet', 'Blaze', 'Echo', 'Fizz'];

export const DEFAULT_MODELS: Record<ProviderId, string> = {
  openrouter: 'openrouter/free',
  gemini: 'gemini-flash-latest',
  anthropic: 'claude-opus-5-5',
  custom: '',
  manual: '',
};

function defaults(): Settings {
  const n = Math.floor(Math.random() * 1000);
  return {
    name: `${NAMES[n % NAMES.length]}${n}`,
    color: COLORS[n % COLORS.length],
    provider: 'manual',
    keys: {},
    models: {},
    customBase: 'https://api.groq.com/openai/v1',
    sound: true,
    touch: 'auto',
    turnUrl: '',
    turnUser: '',
    turnPass: '',
  };
}

const SETTINGS_KEY = 'combiner.settings';
let cached: Settings | null = null;

function lsGet(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function lsSet(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* private mode: settings live for this tab only */
  }
}

export function getSettings(): Settings {
  if (cached) return cached;
  const base = defaults();
  const stored = lsGet(SETTINGS_KEY);
  try {
    cached = stored ? { ...base, ...JSON.parse(stored) } : base;
  } catch {
    cached = base;
  }
  // Persist the generated player name so it stays the same next visit.
  if (!stored) lsSet(SETTINGS_KEY, JSON.stringify(cached));
  return cached!;
}

export function saveSettings(patch: Partial<Settings>): Settings {
  cached = { ...getSettings(), ...patch };
  lsSet(SETTINGS_KEY, JSON.stringify(cached));
  return cached;
}

export function modelFor(p: ProviderId): string {
  return getSettings().models[p] || DEFAULT_MODELS[p];
}

// ------------------------------------------------------------ recently played

const RECENT_KEY = 'combiner.recent';
export function recentPlays(): string[] {
  try {
    return JSON.parse(lsGet(RECENT_KEY) || '[]');
  } catch {
    return [];
  }
}

export function notePlayed(id: string): void {
  const list = [id, ...recentPlays().filter((x) => x !== id)].slice(0, 12);
  lsSet(RECENT_KEY, JSON.stringify(list));
}

const BEST_KEY = 'combiner.best';
export function bestScores(): Record<string, { score: number; time: number }> {
  try {
    return JSON.parse(lsGet(BEST_KEY) || '{}');
  } catch {
    return {};
  }
}

export function noteWin(id: string, score: number, time: number): boolean {
  const all = bestScores();
  const prev = all[id];
  if (prev && prev.score >= score) return false;
  all[id] = { score, time };
  lsSet(BEST_KEY, JSON.stringify(all));
  return true;
}

// ------------------------------------------------------------ creations (IndexedDB)

export interface Creation {
  id: string;
  title: string;
  tagline: string;
  games: [string, string];
  twist: string;
  html: string;
  multiplayer: boolean;
  provider?: string;
  model?: string;
  createdAt: number;
  updatedAt: number;
  /** Previous versions, newest first (kept short). */
  history?: string[];
}

const DB_NAME = 'combiner';
const STORE = 'creations';
const memory = new Map<string, Creation>();
let dbPromise: Promise<IDBDatabase | null> | null = null;

function db(): Promise<IDBDatabase | null> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve) => {
    try {
      const req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: 'id' });
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return dbPromise;
}

function tx<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return db().then(
    (d) =>
      new Promise<T>((resolve, reject) => {
        if (!d) return reject(new Error('no-idb'));
        const req = fn(d.transaction(STORE, mode).objectStore(STORE));
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      }),
  );
}

export async function listCreations(): Promise<Creation[]> {
  let all: Creation[];
  try {
    all = await tx('readonly', (s) => s.getAll() as IDBRequest<Creation[]>);
  } catch {
    all = [...memory.values()];
  }
  return all.sort((a, b) => b.updatedAt - a.updatedAt);
}

export async function getCreation(id: string): Promise<Creation | undefined> {
  try {
    return await tx('readonly', (s) => s.get(id) as IDBRequest<Creation | undefined>);
  } catch {
    return memory.get(id);
  }
}

export async function saveCreation(c: Creation): Promise<void> {
  c.updatedAt = Date.now();
  try {
    await tx('readwrite', (s) => s.put(c));
  } catch {
    memory.set(c.id, c);
  }
}

export async function deleteCreation(id: string): Promise<void> {
  try {
    await tx('readwrite', (s) => s.delete(id));
  } catch {
    memory.delete(id);
  }
}

export function newId(): string {
  const a = new Uint8Array(8);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(36).padStart(2, '0')).join('').slice(0, 12);
}
