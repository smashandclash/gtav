// The tables around the player that someone else is playing at: this page follows each game as
// a spectator (games.watchSync: the board, and the hands only as counts) and hands every move
// to the table in the world, so a passer-by sees the cards land and flip.

import type { Card, SmashAndClash, WatchSync } from '@smashandclash/sdk';
import { post } from './bridge';
import { stepsFor, tableView, type TableState } from './view';

export interface NearbyTable {
  id: string;
  game: string | null;
  flip: boolean;
}

interface Following {
  game: string | null;
  flip: boolean;
  gen: number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class Spectator {
  private following = new Map<string, Following>();
  private gen = 0;

  constructor(
    private sc: SmashAndClash,
    private cards: () => Map<number, Card>,
    private colors: () => Record<string, string>,
  ) {}

  /** The tables near the player now, from the game. */
  update(tables: NearbyTable[]): void {
    const seen = new Set<string>();
    for (const t of tables) {
      seen.add(t.id);
      const f = this.following.get(t.id);
      if (f && f.game === t.game && f.flip === t.flip) continue;
      const next = { game: t.game, flip: t.flip, gen: ++this.gen };
      this.following.set(t.id, next);
      if (t.game) void this.follow(t.id, next);
      else void post('view', { table: t.id, view: null });
    }
    for (const id of [...this.following.keys()]) if (!seen.has(id)) this.following.delete(id);
  }

  private live(table: string, f: Following): boolean {
    return this.following.get(table)?.gen === f.gen;
  }

  private view(f: Following, s: WatchSync, state: TableState) {
    return tableView({ game: f.game, state, players: s.players, kinds: s.playerKinds, viewer: null, flip: f.flip, colors: this.colors(), over: s.status !== 'active' });
  }

  private async follow(table: string, f: Following): Promise<void> {
    const id = f.game!;
    let s: WatchSync | null = null;
    while (!s) {
      try {
        s = await this.sc.games.watchSync(id, { since: 0 });
      } catch {
        if (!this.live(table, f)) return;
        await sleep(5000);
      }
    }
    if (!this.live(table, f)) return;
    let shown: TableState = s.state;
    let since = s.moveCount;
    void post('view', { table, view: this.view(f, s, shown) });
    while (this.live(table, f) && s.status !== 'finished' && s.status !== 'abandoned') {
      try {
        s = await this.sc.games.watchSync(id, { since, status: s.status, wait: 20 });
      } catch {
        await sleep(4000);
        continue;
      }
      if (!this.live(table, f)) return;
      for (const m of s.moves) {
        if (m.index < since) continue;
        const { steps, total } = stepsFor(shown, m.state, m.events, this.cards());
        shown = m.state;
        since = m.index + 1;
        void post('move', { table, steps, view: this.view(f, s, shown) });
        await sleep(total);
        if (!this.live(table, f)) return;
      }
      if (s.moveCount === since) {
        shown = s.state;
        void post('view', { table, view: this.view(f, s, shown) });
      }
    }
  }
}
