// What the page tells the 3D table: the view of a table, and the animation steps for a move.

import type { Card } from '@smashandclash/sdk';
import { describe, expect, it } from 'vitest';
import { completed, houseStrength, movesFor, nextRating, nextTargets, parseMove, personaName, seatName } from '../nui/src/moves';
import { hexRGB, stepsFor, tableView, type TableState } from '../nui/src/view';

const empty = (): TableState['board'] => [0, 1, 2].map(() => [null, null, null, null, null]);

function state(cells: Record<string, { id: number; owner: 'A' | 'B' }>, extra: Partial<TableState> = {}): TableState {
  const board = empty();
  for (const [cell, t] of Object.entries(cells)) board[Number(cell[1]) - 1]['ABCDE'.indexOf(cell[0])] = { cardId: t.id, owner: t.owner, frozen: false };
  return { ruleset: 'mutators', board, current: 'A', gameOver: false, ...extra };
}

const cards = new Map<number, Card>([[1, { id: 1, name: 'Pengu', kind: 'character', image: 'p.webp', animation: { windup: 'w', strike: 's.webp', pivot: { x: 0, y: 0 }, artScale: 1 } } as Card]]);

describe('the table view', () => {
  it('lists the board, the score and the names, an opponent at your level under a handle', () => {
    const v = tableView({
      game: 'g_1',
      state: state({ A1: { id: 1, owner: 'A' }, B1: { id: 2, owner: 'B' }, C1: { id: 3, owner: 'B' } }, { hand: [4, 5], opponentHand: 5, deck: 30, powerTiles: [{ cell: { r: 1, c: 3 }, color: 'pink', boost: 2 }] }),
      players: { A: 'Franklin', B: 'Smash&Clash House' },
      kinds: { A: 'person', B: 'house' },
      viewer: 'A',
      flip: false,
      colors: { pink: '#fc41a3' },
    });
    expect(v.score).toEqual({ A: 1, B: 2 });
    expect(v.hands).toEqual({ A: 2, B: 5 });
    expect(v.myHand).toEqual([4, 5]);
    expect(v.deck).toBe(30);
    expect(v.names.A).toBe('Franklin');
    expect(v.names.B).toBe(personaName('g_1'));
    expect(v.names.B).not.toMatch(/house|cpu/i);
    expect(v.power[0]).toMatchObject({ cell: 'D2', boost: 2, rgb: [252, 65, 163] });
  });

  it('never gives a spectator a hand', () => {
    const v = tableView({ game: 'g_1', state: state({}, { hands: { A: 5, B: 4 } }), players: { A: 'a', B: 'b' }, kinds: { A: 'person', B: 'person' }, viewer: null, flip: true, colors: {} });
    expect(v.myHand).toBeUndefined();
    expect(v.hands).toEqual({ A: 5, B: 4 });
    expect(v.flip).toBe(true);
  });
});

describe('a move on the table', () => {
  it('drops the card, strikes, then flips what it beat', () => {
    const before = state({ C3: { id: 2, owner: 'B' } });
    const after = state({ C2: { id: 1, owner: 'A' }, C3: { id: 2, owner: 'A' } });
    const { steps, total } = stepsFor(before, after, [{ type: 'cardPlaced', cardId: 1, cell: { r: 1, c: 2 } }, { type: 'cardsCaptured', cells: [{ r: 2, c: 2 }] }], cards);
    const kinds = steps.map((s) => s.kind);
    expect(kinds).toEqual(['drop', 'strike', 'flip']);
    const flip = steps.find((s) => s.kind === 'flip')!;
    expect(flip).toMatchObject({ cell: 'C3', from: 'B' });
    expect(flip.at).toBeGreaterThan(steps[0].at);
    expect(total).toBeGreaterThanOrEqual(flip.at);
  });

  it('turns the whole board for a Flip', () => {
    const { steps } = stepsFor(state({ A1: { id: 1, owner: 'A' } }), state({ E3: { id: 1, owner: 'B' } }), [{ type: 'effectPlayed', effect: 'FLIP', cardId: 102 }, { type: 'boardFlipped' }], cards);
    expect(steps.map((s) => s.kind)).toEqual(['callout', 'boardflip']);
  });

  it('crumbles what a Boulder takes, and slides a hop', () => {
    const b = stepsFor(state({ B2: { id: 1, owner: 'A' }, B3: { id: 2, owner: 'B' } }), state({}), [{ type: 'effectPlayed', effect: 'BOULDER', cardId: 101 }], cards);
    expect(b.steps.filter((s) => s.kind === 'vanish').map((s) => s.cell).sort()).toEqual(['B2', 'B3']);
    const h = stepsFor(state({ B1: { id: 1, owner: 'A' } }), state({ D2: { id: 1, owner: 'A' } }), [{ type: 'cardHopped', from: { r: 0, c: 1 }, to: { r: 1, c: 3 }, cardId: 1 }], cards);
    expect(h.steps.find((s) => s.kind === 'hop')).toMatchObject({ cell: 'D2', from: 'B1' });
  });

  it('brings the card you draw into your hand', () => {
    const { steps } = stepsFor(state({}, { hand: [1, 2, 3] }), state({ A1: { id: 1, owner: 'A' } }, { hand: [2, 3, 9] }), [{ type: 'cardsDrawn', player: 'A', count: 1 }], cards, 'A');
    expect(steps.find((s) => s.kind === 'draw')).toMatchObject({ index: 2, seat: 'A' });
  });

  it('shows what each attack compared: "5 >= 5" takes the card, "4 < 6" holds', () => {
    // Pengu 5/4/3/2 placed by A on C2: north 5 against C3's south, east 4 against D2's west
    const deck = new Map<number, Card>([
      [1, { id: 1, name: 'Pengu', kind: 'character', top: 5, right: 4, bottom: 3, left: 2, color: 'pink', image: '' } as Card],
      [2, { id: 2, name: 'X', kind: 'character', top: 1, right: 1, bottom: 5, left: 1, color: 'blue', image: '' } as Card],
      [3, { id: 3, name: 'Y', kind: 'character', top: 1, right: 6, bottom: 1, left: 1, color: 'blue', image: '' } as Card],
    ]);
    // seat B's cards are turned round: C3's south is its printed top (5); D2's west is its printed right (6)
    deck.set(2, { ...deck.get(2)!, top: 5, bottom: 1 } as Card);
    const before = state({ C3: { id: 2, owner: 'B' }, D2: { id: 3, owner: 'B' } });
    const after = state({ C2: { id: 1, owner: 'A' }, C3: { id: 2, owner: 'A' }, D2: { id: 3, owner: 'B' } });
    const { steps } = stepsFor(before, after, [{ type: 'cardPlaced', player: 'A', cardId: 1, cell: { r: 1, c: 2 } }], deck, 'A');
    const sums = steps.filter((s) => s.kind === 'compare').map((s) => `${s.toward} ${s.text} ${s.win}`).sort();
    expect(sums).toEqual(['C3 5 >= 5 true', 'D2 4 < 6 false']);
    expect(steps.find((s) => s.kind === 'drop')).toMatchObject({ fromHand: true, seat: 'A' });
  });

  it('breaks up what a Boulder takes, flies a recruit across, and swaps the hands', () => {
    const b = stepsFor(state({ B2: { id: 1, owner: 'A' } }), state({}), [{ type: 'effectPlayed', effect: 'BOULDER', cardId: 101, player: 'B' }, { type: 'boulderRemoved', cells: [{ r: 1, c: 1 }] }], cards);
    expect(b.steps.find((s) => s.kind === 'vanish')).toMatchObject({ crumble: true });
    expect(b.steps.some((s) => s.kind === 'quake')).toBe(true);
    const r = stepsFor(state({ A3: { id: 1, owner: 'B' } }), state({ B1: { id: 1, owner: 'A' } }), [{ type: 'cardRecruited', from: { r: 2, c: 0 }, to: { r: 0, c: 1 }, cardId: 1, newOwner: 'A' }], cards);
    expect(r.steps.find((s) => s.kind === 'recruit')).toMatchObject({ cell: 'B1', from: 'A3', owner: 'B' });
    expect(r.steps.some((s) => s.kind === 'vanish')).toBe(false);
    const w = stepsFor(state({}), state({}), [{ type: 'effectPlayed', effect: 'SWAP', cardId: 105, player: 'A' }, { type: 'handsSwapped' }], cards);
    expect(w.steps.map((s) => s.kind)).toEqual(['callout', 'swap']);
  });
});

describe('picking a move', () => {
  const legal = ['Pengu@C2', 'Pengu@D2', 'RECRUIT(A3→B1)', 'RECRUIT(A3→C1)', 'FLIP', 'hop→E3', 'hop: stay'];
  it('narrows tile by tile', () => {
    expect([...nextTargets(movesFor(legal, 'Pengu', []), [])].sort()).toEqual(['C2', 'D2']);
    expect([...nextTargets(movesFor(legal, 'RECRUIT', ['A3']), ['A3'])].sort()).toEqual(['B1', 'C1']);
    expect(completed(movesFor(legal, 'RECRUIT', ['A3', 'C1']), ['A3', 'C1'])?.name).toBe('RECRUIT(A3→C1)');
    expect(completed(movesFor(legal, 'FLIP', []), [])?.name).toBe('FLIP');
    expect(parseMove('hop: stay')).toMatchObject({ key: 'hop', cells: [] });
  });
});

describe('ratings and names', () => {
  it('moves your rating, and keeps the house at your level inside its range', () => {
    expect(nextRating(1200, 1200, 'win')).toBe(1216);
    expect(nextRating(1200, 1200, 'loss')).toBe(1184);
    expect(houseStrength(2000)).toBe(1600);
    expect(houseStrength(500)).toBe(800);
  });
  it('names a house seat with a handle, stable for the game', () => {
    expect(seatName('g_9', 'B', { A: 'x', B: 'Smash&Clash House' }, { A: 'person', B: 'house' })).toBe(personaName('g_9'));
    expect(hexRGB('#3493da')).toEqual([52, 147, 218]);
  });
});
