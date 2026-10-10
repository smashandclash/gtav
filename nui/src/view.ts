// What the 3D table draws, as the page hands it to client/board.lua: the board, the special
// tiles, both hands (the viewer's own cards face up, every other hand as a count), names and
// score; and, for each move, the animation steps that play it out. Pure: no DOM, no network.

import type { Card, Seat, SeatKind } from '@smashandclash/sdk';
import { seatName } from './moves';

/** A table's state, from a seat (SeatState) or from the rail (PublicState). */
export interface TableState {
  ruleset: 'mutators' | 'classic';
  board: Array<Array<{ cardId: number; owner: Seat; frozen: boolean } | null>>;
  operatorTiles?: Array<{ cell: { r: number; c: number }; piece: string }>;
  powerTiles?: Array<{ cell: { r: number; c: number }; color: string; boost: number }>;
  current: Seat;
  gameOver: boolean;
  deck?: number;
  /** The seat's own hand (card ids) and the other's count, or both counts for a spectator. */
  hand?: number[];
  opponentHand?: number;
  hands?: { A: number; B: number };
}

export interface ViewUI {
  myTurn: boolean;
  targets: string[];
  picked: string[];
  selected: number | null;
  /** By hand position: nothing to do with this card now. */
  dead: boolean[];
  /** First person: your cards stand at your edge of the table instead of on screen. */
  hand3d?: boolean;
}

export interface TableView {
  game: string | null;
  ruleset: 'mutators' | 'classic';
  /** The game's seat A sits at chair B: the board turns round. */
  flip: boolean;
  /** The seat this client plays, when it plays at this table. */
  viewer: Seat | null;
  board: Array<{ cell: string; id: number; owner: Seat; frozen: boolean }>;
  chess: Array<{ cell: string; piece: string }>;
  power: Array<{ cell: string; color: string; boost: number; rgb: [number, number, number] }>;
  hands: { A: number; B: number };
  /** Cards left to draw: the stack on the stand beside the board. */
  deck: number;
  myHand?: number[];
  current: Seat | null;
  names: { A: string; B: string };
  score: { A: number; B: number };
  ui?: ViewUI;
}

export interface Step {
  at: number;
  dur: number;
  kind: 'drop' | 'flip' | 'vanish' | 'hop' | 'boardflip' | 'callout' | 'strike' | 'draw';
  cell?: string;
  from?: string | Seat;
  id?: number;
  owner?: Seat;
  art?: string;
  mirror?: boolean;
  index?: number;
  /** The sound this step makes, played by the page as it starts. */
  sfx?: string;
}

const COLS = 'ABCDE';
const cellName = (r: number, c: number) => `${COLS[c]}${r + 1}`;
const cellOf = (c: unknown): string | null => {
  if (typeof c === 'string') return c;
  const o = c as { r?: number; c?: number } | null;
  return o && typeof o.r === 'number' && typeof o.c === 'number' ? cellName(o.r, o.c) : null;
};

export function hexRGB(hex: string): [number, number, number] {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return [255, 255, 255];
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export interface ViewInput {
  game: string | null;
  state: TableState;
  players: { A: string; B: string | null };
  kinds: { A: SeatKind; B: SeatKind | null };
  viewer: Seat | null;
  flip: boolean;
  colors: Record<string, string>;
  over?: boolean;
  ui?: ViewUI;
}

export function tableView(i: ViewInput): TableView {
  const s = i.state;
  const board: TableView['board'] = [];
  const score = { A: 0, B: 0 };
  s.board.forEach((row, r) =>
    row.forEach((t, c) => {
      if (!t) return;
      board.push({ cell: cellName(r, c), id: t.cardId, owner: t.owner, frozen: t.frozen });
      score[t.owner]++;
    }),
  );
  let hands = s.hands ?? { A: 0, B: 0 };
  if (!s.hands && i.viewer) {
    const other: Seat = i.viewer === 'A' ? 'B' : 'A';
    hands = { [i.viewer]: s.hand?.length ?? 0, [other]: s.opponentHand ?? 0 } as { A: number; B: number };
  }
  const id = i.game ?? '';
  return {
    game: i.game,
    ruleset: s.ruleset,
    flip: i.flip,
    viewer: i.viewer,
    board,
    chess: (s.operatorTiles ?? []).map((t) => ({ cell: cellOf(t.cell)!, piece: t.piece.toLowerCase() })),
    power: (s.powerTiles ?? []).map((t) => ({ cell: cellOf(t.cell)!, color: t.color, boost: t.boost, rgb: hexRGB(i.colors[t.color] ?? '#ffffff') })),
    hands,
    deck: s.deck ?? 0,
    myHand: i.viewer ? s.hand : undefined,
    current: s.gameOver || i.over ? null : s.current,
    names: { A: seatName(id, 'A', i.players, i.kinds), B: seatName(id, 'B', i.players, i.kinds) },
    score,
    ui: i.ui,
  };
}

/** How a move plays out on the table, step by step, and how long it takes (ms). */
export function stepsFor(
  before: TableState,
  after: TableState,
  events: Array<{ type: string } & Record<string, unknown>>,
  cards: Map<number, Card>,
): { steps: Step[]; total: number } {
  const steps: Step[] = [];
  let t = 0;
  const effect = events.find((e) => e.type === 'effectPlayed');
  if (effect) {
    const name = String(effect.effect);
    steps.push({ at: 0, dur: 1100, kind: 'callout', id: Number(effect.cardId), sfx: name.toLowerCase() });
    t = 700;
  }
  if (events.some((e) => e.type === 'boardFlipped')) {
    steps.push({ at: t, dur: 900, kind: 'boardflip' });
    return { steps, total: t + 950 };
  }

  const drops: string[] = [];
  const flips: Array<{ cell: string; from: Seat }> = [];
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 5; c++) {
      const cell = cellName(r, c);
      const a = before.board[r]?.[c] ?? null;
      const b = after.board[r]?.[c] ?? null;
      if (a && (!b || a.cardId !== b.cardId)) steps.push({ at: t, dur: 520, kind: 'vanish', cell, id: a.cardId, owner: a.owner, sfx: b ? undefined : 'boulder' });
      if (b && (!a || a.cardId !== b.cardId)) drops.push(cell);
      else if (a && b && a.owner !== b.owner) flips.push({ cell, from: a.owner });
    }
  }
  const hop = events.find((e) => e.type === 'cardHopped');
  const hopTo = hop ? cellOf(hop.to) : null;
  for (const cell of drops) {
    if (hopTo && cell === hopTo) steps.push({ at: t, dur: 520, kind: 'hop', cell, from: cellOf(hop!.from) ?? cell, sfx: 'chessHop' });
    else steps.push({ at: t, dur: 420, kind: 'drop', cell, sfx: 'cardPlace' });
  }
  if (drops.length || steps.some((s) => s.kind === 'vanish')) t += hop ? 560 : 440;

  if (flips.length) {
    const placed = events.find((e) => e.type === 'cardPlaced' || e.type === 'cardOverrun' || e.type === 'cardRecruited' || e.type === 'cardHopped');
    const attacker = Number(placed?.cardId ?? placed?.newCardId ?? NaN);
    const from = hopTo ?? drops[0] ?? null;
    const art = cards.get(attacker)?.animation?.strike;
    if (from && art) {
      // the drawing faces right: mirror it to strike to the left (seen from chair A)
      const toward = flips[0].cell;
      steps.push({ at: t, dur: 700, kind: 'strike', cell: from, art, mirror: COLS.indexOf(toward[0]) < COLS.indexOf(from[0]), sfx: 'clashHit' });
    }
    t += art ? 260 : 0;
    for (const f of flips) steps.push({ at: t, dur: 620, kind: 'flip', cell: f.cell, from: f.from, sfx: flips.length >= 3 ? 'captureCrit' : 'captureHit' });
    t += 660;
  }

  // the card you draw back up comes into your hand
  if (before.hand && after.hand) {
    const had = new Set(before.hand);
    after.hand.forEach((id, i) => {
      if (!had.has(id)) steps.push({ at: t, dur: 380, kind: 'draw', index: i });
    });
  }
  return { steps, total: Math.max(t, 120) };
}
