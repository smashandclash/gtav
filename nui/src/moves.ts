// Pure game helpers for the GTA V client: move names, opponent names, ratings. No DOM, no network.

import type { HandCard, Seat, SeatKind } from '@smashandclash/sdk';

export const COLS = 'ABCDE';

/** A move name split into what it plays and the tiles it needs, in the order a player picks them. */
export interface ParsedMove {
  name: string;
  /** The hand card's key ("Pengu", "BOULDER"), or "hop". */
  key: string;
  cells: string[];
}

// Move names: "Pengu@C2" places, "Teddy!C2" overruns, "hop→E3" / "hop: stay" resolve a hop,
// "BOULDER(D2)", "FREEZE(C1)", "RECRUIT(D3→B1)", "FLIP" and "SWAP" play an effect.
export function parseMove(name: string): ParsedMove {
  let m: RegExpExecArray | null;
  if ((m = /^(.+)[@!]([A-E][1-3])$/.exec(name))) return { name, key: m[1], cells: [m[2]] };
  if ((m = /^hop→([A-E][1-3])$/.exec(name))) return { name, key: 'hop', cells: [m[1]] };
  if (name.startsWith('hop')) return { name, key: 'hop', cells: [] };
  if ((m = /^([A-Z]+)\((.*)\)$/.exec(name))) return { name, key: m[1], cells: m[2].split('→') };
  return { name, key: name, cells: [] };
}

/** The key a hand card's moves start with: its name, or an effect's keyword ("Boulder!" → BOULDER). */
export const handKey = (card: HandCard): string => (card.kind === 'effect' ? card.card.replace(/!$/, '').toUpperCase() : card.card);

/** The moves the picked card can make, narrowed by the tiles picked so far. */
export function movesFor(legal: string[], key: string | null, path: string[]): ParsedMove[] {
  if (key == null) return [];
  return legal.map(parseMove).filter((m) => m.key === key && path.every((c, i) => m.cells[i] === c));
}

/** The tiles that continue a pick: the next cell of every move still possible. */
export function nextTargets(moves: ParsedMove[], path: string[]): Set<string> {
  return new Set(moves.filter((m) => m.cells.length > path.length).map((m) => m.cells[path.length]));
}

/** The move a pick completes, if it is complete. */
export function completed(moves: ParsedMove[], path: string[]): ParsedMove | undefined {
  return moves.find((m) => m.cells.length === path.length && m.cells.every((c, i) => c === path[i]));
}

/* --------------------------------- names ---------------------------------- */

// An opponent at your level wears a player's handle, never a label for what it is: the same
// shapes the lobby uses (a guest's Adjective+Noun+digits, or a first name).
const ADJECTIVES = ['Brave', 'Swift', 'Sneaky', 'Mighty', 'Wobbly', 'Spicy', 'Turbo', 'Cosmic', 'Jolly', 'Rapid', 'Zesty', 'Lucky', 'Cheeky', 'Bouncy', 'Fuzzy', 'Nifty', 'Bold', 'Snappy', 'Plucky', 'Stormy', 'Frosty', 'Toasty'];
const NOUNS = ['Otter', 'Tiger', 'Pengu', 'Yeti', 'Falcon', 'Walrus', 'Comet', 'Ninja', 'Badger', 'Phoenix', 'Koala', 'Bison', 'Hawk', 'Panda', 'Wombat', 'Moose', 'Lynx', 'Heron', 'Gecko', 'Puffin', 'Quokka', 'Ibex'];
const FIRST_NAMES = ['arjun', 'priya', 'rohan', 'aisha', 'kabir', 'meera', 'ishan', 'tara', 'zoya', 'sana', 'kenji', 'yuki', 'mei', 'jisoo', 'hana', 'sora', 'leo', 'maya', 'nina', 'omar', 'theo', 'aria', 'finn', 'luca', 'noor', 'ivy'];

export function rngFrom(text: string): () => number {
  let a = 2166136261;
  for (const ch of text) a = Math.imul(a ^ ch.charCodeAt(0), 16777619);
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** The handle an opponent at your level plays under in game `gameId`: stable for the game. */
export function personaName(gameId: string): string {
  const rng = rngFrom(gameId);
  const pick = <T>(xs: T[]): T => xs[Math.min(xs.length - 1, Math.floor(rng() * xs.length))];
  const roll = rng();
  if (roll < 0.45) return `${pick(ADJECTIVES)}${pick(NOUNS)}${Math.floor(rng() * 1000)}`;
  const first = pick(FIRST_NAMES);
  if (roll < 0.7) return first;
  if (roll < 0.85) return `${first}${String(Math.floor(rng() * 90) + 10)}`;
  return `${first}_${String.fromCharCode(97 + Math.floor(rng() * 26))}`;
}

/** A seat's name as a player should see it: an opponent at your level is never labelled as one. */
export function seatName(gameId: string, seat: Seat, players: { A: string; B: string | null }, kinds: { A: SeatKind; B: SeatKind | null }): string {
  if (kinds[seat] === 'house') return personaName(gameId);
  return players[seat] ?? 'Opponent';
}

/** Where a seat plays from, in words; null when there is nothing worth saying. */
export function clientLabel(client: string | null | undefined): string | null {
  if (!client) return null;
  const c = client.toLowerCase();
  if (c === 'mcp') return null;
  const known: Record<string, string> = {
    'smashandclash.in': 'smashandclash.in',
    android: 'Android',
    windows: 'Windows',
    discord: 'Discord',
    whop: 'Whop',
    glasses: 'smart glasses',
    'smashandclash-cli': 'the terminal',
    'smashandclash-telegram': 'Telegram',
    tldraw: 'a whiteboard',
    'smashandclash-ds': 'a Nintendo DS',
    'smashandclash-psp': 'a PSP',
    fivem: 'GTA V',
  };
  return known[c] ?? null;
}

/* -------------------------------- ratings --------------------------------- */

export const START_RATING = 1200;

/** The opponent at your level plays at your rating, inside the house's range. */
export const houseStrength = (rating: number): number => Math.max(800, Math.min(1600, Math.round(rating)));

/** Your new rating after a game against `opponent` (Elo, K = 32). */
export function nextRating(rating: number, opponent: number, result: 'win' | 'loss' | 'draw'): number {
  const score = result === 'win' ? 1 : result === 'draw' ? 0.5 : 0;
  const expected = 1 / (1 + 10 ** ((opponent - rating) / 400));
  return Math.round(rating + 32 * (score - expected));
}

/* --------------------------------- board ---------------------------------- */

/** "C2" → { r: 1, c: 2 }. */
export function rc(cell: string): { r: number; c: number } {
  return { r: Number(cell[1]) - 1, c: COLS.indexOf(cell[0]) };
}

export const cellName = (r: number, c: number): string => `${COLS[c]}${r + 1}`;

/** Every cell, laid out for a seat: your row 1 (seat A) or row 3 (seat B) at the bottom. */
export function layout(seat: Seat): string[][] {
  const rows: string[][] = [];
  for (let r = 2; r >= 0; r--) rows.push([0, 1, 2, 3, 4].map((c) => cellName(r, c)));
  if (seat === 'B') return rows.reverse().map((row) => row.reverse());
  return rows;
}

