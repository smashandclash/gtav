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
  /** The card on its way while the move is sent: it leaves the hand at once and waits over its tile. */
  playing?: { cell: string; id: number } | null;
  /** The hand card scrolled to: it comes to the front of the fan, all four values in view. */
  focus?: number | null;
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
  kind: 'drop' | 'flip' | 'vanish' | 'hop' | 'recruit' | 'boardflip' | 'callout' | 'strike' | 'draw' | 'compare' | 'freeze' | 'swap' | 'quake';
  cell?: string;
  from?: string | Seat;
  /** compare: the tile attacked. */
  toward?: string;
  id?: number;
  owner?: Seat;
  /** The seat whose hands make this step: they play a card, or draw one. */
  seat?: Seat;
  art?: string;
  mirror?: boolean;
  index?: number;
  /** A card played from the hand: it flies from the player's fan, not from above. */
  fromHand?: boolean;
  /** vanish: a Boulder breaks the card up. */
  crumble?: boolean;
  /** compare: "6 >= 5", and whether it took the card. */
  text?: string;
  win?: boolean;
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

type Ev = { type: string } & Record<string, unknown>;
type Side = 'north' | 'east' | 'south' | 'west';
const OPPOSITE: Record<Side, Side> = { north: 'south', south: 'north', east: 'west', west: 'east' };
const NEIGHBOURS: Array<[number, number, Side]> = [
  [1, 0, 'north'],
  [-1, 0, 'south'],
  [0, 1, 'east'],
  [0, -1, 'west'],
];

/** A card's side in board terms (north faces row 3); seat B's cards are turned round. */
function sideOf(card: Card | undefined, owner: Seat, side: Side): number | null {
  if (!card || card.kind !== 'character' || card.top == null) return null;
  const printed = { top: card.top, right: card.right!, bottom: card.bottom!, left: card.left! };
  const a: Record<Side, number> = { north: printed.top, east: printed.right, south: printed.bottom, west: printed.left };
  const b: Record<Side, number> = { north: printed.bottom, east: printed.left, south: printed.top, west: printed.right };
  return (owner === 'A' ? a : b)[side];
}

/**
 * What a card placed on `cell` compared with each enemy neighbour: "6 >= 5" when it took the
 * card (ties go to the attacker), "4 < 6" when it held. A card of a power tile's colour on that
 * tile attacks with every side boosted.
 */
export function compares(cell: string, before: TableState, after: TableState, flipped: Set<string>, cards: Map<number, Card>): Array<{ toward: string; text: string; win: boolean }> {
  const r = Number(cell[1]) - 1;
  const c = COLS.indexOf(cell[0]);
  const me = after.board[r]?.[c];
  if (!me) return [];
  const card = cards.get(me.cardId);
  const power = (after.powerTiles ?? before.powerTiles ?? []).find((t) => t.cell.r === r && t.cell.c === c);
  const boost = power && card?.color && power.color === card.color ? power.boost : 0;
  const out: Array<{ toward: string; text: string; win: boolean }> = [];
  for (const [dr, dc, side] of NEIGHBOURS) {
    const nr = r + dr;
    const nc = c + dc;
    const them = before.board[nr]?.[nc];
    if (!them || them.owner === me.owner || them.frozen) continue;
    const mine = sideOf(card, me.owner, side);
    const theirs = sideOf(cards.get(them.cardId), them.owner, OPPOSITE[side]);
    if (mine == null || theirs == null) continue;
    const a = mine + boost;
    const toward = cellName(nr, nc);
    const win = flipped.has(toward) || a >= theirs;
    // plain ASCII: the game's fonts have no ≥
    out.push({ toward, win, text: win ? `${a} >= ${theirs}` : `${a} < ${theirs}` });
  }
  return out;
}

/** How a move plays out on the table, step by step, and how long it takes (ms). */
export function stepsFor(before: TableState, after: TableState, events: Ev[], cards: Map<number, Card>, viewer?: Seat | null): { steps: Step[]; total: number } {
  const steps: Step[] = [];
  let t = 0;
  // the seat that moved: its hands play the card
  const who = events.find((e) => e.type === 'cardPlaced' || e.type === 'cardOverrun' || e.type === 'effectPlayed')?.player as Seat | undefined;

  const effect = events.find((e) => e.type === 'effectPlayed');
  if (effect) {
    const name = String(effect.effect);
    steps.push({ at: 0, dur: 1200, kind: 'callout', id: Number(effect.cardId), sfx: name.toLowerCase(), seat: effect.player as Seat });
    t = 750;
  }
  if (events.some((e) => e.type === 'boardFlipped')) {
    steps.push({ at: t, dur: 1300, kind: 'boardflip' });
    return { steps, total: t + 1350 };
  }
  if (events.some((e) => e.type === 'handsSwapped')) {
    steps.push({ at: t, dur: 1300, kind: 'swap', sfx: 'shuffle' });
    return { steps, total: t + 1350 };
  }

  const recruit = events.find((e) => e.type === 'cardRecruited');
  const recruitFrom = recruit ? cellOf(recruit.from) : null;
  const recruitTo = recruit ? cellOf(recruit.to) : null;
  const boulder = events.some((e) => e.type === 'boulderRemoved');
  if (boulder) steps.push({ at: t, dur: 700, kind: 'quake' });

  const drops: string[] = [];
  const flips: Array<{ cell: string; from: Seat }> = [];
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 5; c++) {
      const cell = cellName(r, c);
      const a = before.board[r]?.[c] ?? null;
      const b = after.board[r]?.[c] ?? null;
      if (a && (!b || a.cardId !== b.cardId) && cell !== recruitFrom) {
        steps.push({ at: t, dur: boulder ? 900 : 520, kind: 'vanish', cell, id: a.cardId, owner: a.owner, crumble: boulder && !b, sfx: b ? undefined : boulder ? undefined : 'clashMiss' });
      }
      if (b && (!a || a.cardId !== b.cardId)) drops.push(cell);
      else if (a && b && a.owner !== b.owner) flips.push({ cell, from: a.owner });
    }
  }
  // the cards that left a hand this move: placed, or played over a surrounded card
  const played = new Set(events.filter((e) => e.type === 'cardPlaced' || e.type === 'cardOverrun').map((e) => cellOf(e.cell)).filter(Boolean) as string[]);
  const hop = events.find((e) => e.type === 'cardHopped');
  const hopTo = hop ? cellOf(hop.to) : null;
  for (const cell of drops) {
    if (hopTo && cell === hopTo) steps.push({ at: t, dur: 560, kind: 'hop', cell, from: cellOf(hop!.from) ?? cell, sfx: 'chessHop' });
    else if (recruitTo && cell === recruitTo) steps.push({ at: t, dur: 900, kind: 'recruit', cell, from: recruitFrom ?? cell, owner: before.board[Number(recruitFrom?.[1]) - 1]?.[COLS.indexOf(recruitFrom?.[0] ?? 'A')]?.owner });
    else if (played.has(cell)) steps.push({ at: t, dur: 680, kind: 'drop', cell, fromHand: true, seat: who, sfx: 'cardPlace' });
    else steps.push({ at: t, dur: 420, kind: 'drop', cell, sfx: 'cardPlace' });
  }
  for (const e of events.filter((e) => e.type === 'cardFrozen')) {
    const cell = cellOf(e.cell);
    if (cell) steps.push({ at: t, dur: 700, kind: 'freeze', cell, sfx: 'freeze' });
  }
  if (drops.length || steps.some((s) => s.kind === 'vanish' || s.kind === 'freeze')) t += hop ? 600 : recruitTo ? 940 : played.size ? 720 : boulder ? 950 : 460;

  // the attack: what it compared with each neighbour, the strike, and what it took
  const attackFrom = hopTo ?? recruitTo ?? [...played][0] ?? null;
  const flipped = new Set(flips.map((f) => f.cell));
  const sums = attackFrom ? compares(attackFrom, before, after, flipped, cards) : [];
  for (const s of sums) steps.push({ at: t, dur: 1300, kind: 'compare', cell: attackFrom!, toward: s.toward, text: s.text, win: s.win });
  if (flips.length) {
    const placed = events.find((e) => e.type === 'cardPlaced' || e.type === 'cardOverrun' || e.type === 'cardRecruited' || e.type === 'cardHopped');
    const attacker = Number(placed?.cardId ?? placed?.newCardId ?? NaN);
    const art = cards.get(attacker)?.animation?.strike;
    if (attackFrom && art) {
      // the drawing faces right: mirror it to strike to the left (seen from chair A)
      const toward = flips[0].cell;
      steps.push({ at: t, dur: 760, kind: 'strike', cell: attackFrom, art, mirror: COLS.indexOf(toward[0]) < COLS.indexOf(attackFrom[0]), sfx: 'clashHit' });
    }
    t += art ? 320 : 120;
    for (const f of flips) steps.push({ at: t, dur: 760, kind: 'flip', cell: f.cell, from: f.from, sfx: flips.length >= 3 ? 'captureCrit' : 'captureHit' });
    t += 800;
  } else if (sums.length) {
    t += 700;
  }

  // drawing back up: the card comes from the deck into the hand that drew it
  const handNow = after.hand;
  const handBefore = before.hand;
  for (const e of events.filter((e) => e.type === 'cardsDrawn')) {
    const seat = e.player as Seat;
    const n = Number(e.count ?? 1);
    if (handNow && handBefore && viewer && seat === viewer) {
      const had = new Set(handBefore);
      handNow.forEach((id, i) => {
        if (!had.has(id) && steps.filter((s) => s.kind === 'draw' && s.index === i).length === 0) steps.push({ at: t, dur: 460, kind: 'draw', index: i, seat });
      });
    } else {
      const count = after.hands?.[seat] ?? after.opponentHand ?? 5;
      for (let k = 0; k < n; k++) steps.push({ at: t + k * 120, dur: 460, kind: 'draw', index: Math.max(0, count - n + k), seat });
    }
  }
  return { steps, total: Math.max(t, 140) };
}
