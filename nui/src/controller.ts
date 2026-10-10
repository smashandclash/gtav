// The game, run through the Smash&Clash SDK: start and join games, play moves, wait for the other
// side, finish (rating, Game Review) and resume. The UI draws what this holds and calls its
// actions; nothing here touches the DOM.

import {
  SmashAndClash,
  isNetworkError,
  type Assets,
  type Card,
  type Game,
  type Review,
  type Seat,
  type SeatMove,
  type SeatState,
} from '@smashandclash/sdk';
import { post, type TableContext } from './bridge';
import { houseStrength, nextRating, seatName, clientLabel } from './moves';
import { saveProfile, type GameMode, type Profile } from './profile';

export type Screen = 'boot' | 'lobby' | 'waiting' | 'match';

export interface Animator {
  /** Show one move landing: `before` is the table it changes. Resolves when it has played out. */
  move(m: SeatMove, before: SeatState, seat: Seat): Promise<void>;
}

export interface Finish {
  result: 'win' | 'loss' | 'draw';
  resigned: boolean;
  score: { you: number; them: number };
  ratingBefore: number;
  ratingAfter: number | null;
  review: Review | null;
  replayUrl: string | null;
}

/** A room the player across the table opened for them. */
export interface TableOffer {
  code: string;
  from: string;
}

const CLIENT = 'fivem';

export class Controller {
  readonly sc = new SmashAndClash({ client: CLIENT });
  name = 'Player';
  profile: Profile;
  cards = new Map<number, Card>();
  kit: Assets | null = null;
  rulesText = '';

  screen: Screen = 'boot';
  game: Game | null = null;
  mode: GameMode | null = null;
  strength = 1200;
  /** The table as drawn: the latest move that has played out. */
  shown: SeatState | null = null;
  since = 0;
  animating = false;
  busy: string | null = null;
  notice: { text: string; tone: 'info' | 'error'; until: number } | null = null;
  finish: Finish | null = null;
  table: TableContext | null = null;
  offer: TableOffer | null = null;
  visible = false;
  /** The card on its way to a tile while a move is sent. */
  pending: { cell: string; cardId: number } | null = null;

  private pumpGen = 0;
  private resigned = false;
  private finishedId: string | null = null;
  private listeners = new Set<() => void>();

  constructor(
    profile: Profile,
    private animator: Animator,
  ) {
    this.profile = profile;
  }

  /* ------------------------------ plumbing ------------------------------- */

  onChange(fn: () => void): void {
    this.listeners.add(fn);
  }

  emit(): void {
    for (const fn of this.listeners) fn();
  }

  say(text: string, tone: 'info' | 'error' = 'info', ms = 4000): void {
    this.notice = { text, tone, until: Date.now() + ms };
    this.emit();
    setTimeout(() => this.emit(), ms + 50);
  }

  saveProfile(patch: Partial<Profile>): void {
    this.profile = { ...this.profile, ...patch };
    saveProfile(this.profile);
    this.emit();
  }

  get seat(): Seat {
    return this.game?.state.seat ?? 'A';
  }

  get other(): Seat {
    return this.seat === 'A' ? 'B' : 'A';
  }

  get opponentName(): string {
    const s = this.game?.state;
    if (!s) return '';
    return seatName(s.id, this.other, s.players, s.playerKinds);
  }

  /** Where the opponent plays from, when it says something ("on Telegram"). */
  get opponentFrom(): string | null {
    const s = this.game?.state;
    if (!s || s.playerKinds[this.other] === 'house') return null;
    return clientLabel(s.clients?.[this.other]);
  }

  get opponentRating(): number | null {
    const s = this.game?.state;
    if (!s) return null;
    if (s.playerKinds[this.other] === 'house') return this.strength;
    return s.ratings?.[this.other] ?? null;
  }

  /** The player may pick a move now. */
  get canPlay(): boolean {
    return !!this.game && !this.game.over && this.game.yourTurn && !this.busy && !this.animating;
  }

  private seatOptions() {
    return { name: this.name, as: 'person' as const, ruleset: this.profile.ruleset, rating: Math.round(this.profile.rating) };
  }

  private async task(label: string, fn: () => Promise<void>): Promise<void> {
    if (this.busy) return;
    this.busy = label;
    this.emit();
    try {
      await fn();
    } catch (e) {
      const quiet = (e as { quiet?: boolean })?.quiet;
      this.say(quiet ? (e as Error).message : errorText(e), quiet ? 'info' : 'error', 6000);
    } finally {
      this.busy = null;
      this.emit();
    }
  }

  /* -------------------------------- boot --------------------------------- */

  async boot(name: string): Promise<void> {
    this.name = name.trim().slice(0, 24) || 'Player';
    const [cards, kit] = await Promise.all([this.sc.cards(), this.sc.assets().catch(() => null)]);
    this.cards = new Map(cards.map((c) => [c.id, c]));
    this.kit = kit;
    const active = this.profile.active;
    if (active) {
      try {
        const g = await this.sc.games.resume(active.id, active.token);
        if (!g.over) {
          this.strength = active.strength ?? this.strength;
          await this.adopt(g, active.mode, { resume: true });
          return;
        }
      } catch {}
      this.saveProfile({ active: null });
    }
    this.screen = 'lobby';
    this.emit();
  }

  async loadRules(): Promise<void> {
    if (!this.rulesText) this.rulesText = await this.sc.rules();
    this.emit();
  }

  /* ------------------------------- starting ------------------------------ */

  /** A game now, against an opponent at your level. */
  playNow(): Promise<void> {
    return this.task('Dealing…', async () => {
      await this.leaveCurrent();
      this.strength = houseStrength(this.profile.rating);
      const g = await this.sc.games.startHouse({ ...this.seatOptions(), strength: this.strength });
      await this.adopt(g, 'house');
    });
  }

  /** The queue every client shares: smashandclash.in, Telegram, the terminal, a DS… */
  quickMatch(): Promise<void> {
    return this.task('Joining the queue…', async () => {
      await this.leaveCurrent();
      const g = await this.sc.games.quickMatch({ ...this.seatOptions(), opponent: 'person' });
      await this.adopt(g, 'quick');
    });
  }

  /** A room by code: anyone joins it from any client. */
  createRoom(): Promise<void> {
    return this.task('Opening a room…', async () => {
      await this.leaveCurrent();
      const g = await this.sc.games.createDuel(this.seatOptions());
      await this.adopt(g, 'room');
    });
  }

  /** Whatever a friend shared from any client: a code, a join or invite link. */
  join(text: string): Promise<void> {
    return this.task('Joining…', async () => {
      if (!text.trim()) return this.say('Type the room code your friend sent, like K7QF2M.');
      await this.leaveCurrent();
      const o = await this.sc.games.open(text, this.seatOptions());
      if (o.kind === 'game') await this.adopt(o.game, 'friend');
      else if (o.kind === 'watch') this.say('That game is already full. You can watch it on smashandclash.in.', 'info', 6000);
      else this.say('That link opens in a browser, not a game seat.', 'info', 6000);
    });
  }

  /** At a table: open a room and hand its code to the player across. */
  challengeAcross(): Promise<void> {
    const across = this.table?.opposite;
    if (!this.table || !across) return Promise.resolve();
    return this.task(`Inviting ${across.name}…`, async () => {
      await this.leaveCurrent();
      const g = await this.sc.games.createDuel(this.seatOptions());
      await this.adopt(g, 'table');
      if (g.code) await post('tableRoom', { code: g.code });
    });
  }

  /** At a table: take the seat the player across opened. */
  acceptOffer(): Promise<void> {
    const offer = this.offer;
    if (!offer) return Promise.resolve();
    this.offer = null;
    return this.task(`Joining ${offer.from}…`, async () => {
      await this.leaveCurrent();
      const g = await this.sc.games.joinDuel(offer.code, this.seatOptions());
      await this.adopt(g, 'table');
    });
  }

  declineOffer(): void {
    if (!this.offer) return;
    this.offer = null;
    void post('tableDecline');
    this.emit();
  }

  private async adopt(g: Game, mode: GameMode, o: { resume?: boolean } = {}): Promise<void> {
    this.pumpGen++;
    this.game = g;
    this.mode = mode;
    this.finish = null;
    this.resigned = false;
    this.finishedId = null;
    this.saveProfile({ active: { id: g.id, token: g.playerToken, mode, strength: mode === 'house' ? this.strength : undefined } });
    if (this.table) void post('tableGame', { gameId: g.id, seat: g.state.seat });
    if (g.waiting) {
      this.screen = 'waiting';
      this.shown = null;
      this.since = 0;
      this.emit();
      void this.pump();
      return;
    }
    await this.enterMatch(o.resume ? g.state.moveCount : 0);
  }

  private async enterMatch(since: number): Promise<void> {
    const g = this.game!;
    const s = await g.sync({ since: 0 });
    this.screen = 'match';
    this.since = since;
    // a fresh game shows the opening table, then plays out any move made before you looked
    this.shown = since === 0 ? (s.moves[0] ? previousState(s) : s.state) : s.state;
    this.emit();
    if (since === 0) await this.animateMoves(s.moves);
    this.afterChange();
  }

  /* -------------------------------- playing ------------------------------- */

  play(name: string): Promise<void> {
    const g = this.game;
    if (!g || !this.canPlay) return Promise.resolve();
    const detail = g.view?.moves?.find((m) => m.name === name);
    if (detail && (detail.type === 'place' || detail.type === 'overrun') && detail.cell && detail.cardId != null) this.pending = { cell: detail.cell, cardId: detail.cardId };
    return this.task(this.mode === 'house' ? `${this.opponentName} is thinking…` : 'Playing…', async () => {
      try {
        await g.play(name);
      } finally {
        this.pending = null;
      }
      await this.catchUp();
      this.afterChange();
    });
  }

  resign(): Promise<void> {
    const g = this.game;
    if (!g) return Promise.resolve();
    return this.task(g.waiting ? 'Calling it off…' : 'Resigning…', async () => {
      if (g.waiting) {
        await this.leaveCurrent();
        this.toLobby();
        return;
      }
      this.resigned = true;
      await g.resign();
      await this.catchUp();
      this.afterChange();
    });
  }

  /** Back to the lobby once a game is over (or was called off). */
  toLobby(): void {
    this.pumpGen++;
    this.game = null;
    this.mode = null;
    this.shown = null;
    this.finish = null;
    this.screen = 'lobby';
    this.emit();
  }

  /** Resign a game in play, or call off one nobody joined. Never resigns a game someone just joined. */
  private async leaveCurrent(): Promise<void> {
    const g = this.game;
    if (!g || g.over) return;
    this.pumpGen++;
    if (g.waiting) {
      const left = await g.leave().then(
        () => true,
        (e: { status?: number }) => e?.status !== 409,
      );
      if (!left) {
        await g.refresh();
        await this.enterMatch(0);
        throw Object.assign(new Error('Someone joined just now: your game is on.'), { quiet: true });
      }
    } else await g.resign();
    this.game = null;
    this.saveProfile({ active: null });
  }

  /** Play out every move the table has not shown yet. */
  private async catchUp(): Promise<void> {
    const g = this.game;
    if (!g) return;
    const s = await g.sync({ since: this.since });
    await this.animateMoves(s.moves.filter((m) => m.index >= this.since));
    if (!this.shown || s.moveCount === this.since) this.shown = s.state;
  }

  private async animateMoves(moves: SeatMove[]): Promise<void> {
    if (!moves.length) return;
    this.animating = true;
    this.emit();
    try {
      for (const m of moves) {
        const before = this.shown ?? m.state;
        await this.animator.move(m, before, this.seat);
        this.shown = m.state;
        this.since = m.index + 1;
        this.emit();
      }
    } finally {
      this.animating = false;
      this.emit();
    }
  }

  private afterChange(): void {
    const g = this.game;
    if (!g) return;
    if (g.over) void this.finishGame();
    else void this.pump();
    this.emit();
  }

  /** Wait (long-poll) until it is your turn, someone joins, or the game ends. One at a time. */
  private async pump(): Promise<void> {
    const gen = ++this.pumpGen;
    const g = this.game;
    while (g && gen === this.pumpGen && !g.over && (g.waiting || !g.yourTurn)) {
      const wasWaiting = g.waiting;
      const before = g.state.moveCount;
      try {
        await g.waitForTurn(20);
      } catch (e) {
        if (gen !== this.pumpGen) return;
        if (!isNetworkError(e)) this.say(errorText(e), 'error', 5000);
        await sleep(4000);
        continue;
      }
      if (gen !== this.pumpGen) return;
      if (wasWaiting && !g.waiting) {
        this.notify(`${this.opponentName} joined. Your game is on!`);
        await this.enterMatch(0);
        return;
      }
      if (g.state.moveCount !== before || g.over || g.yourTurn) {
        await this.catchUp();
        if (g.yourTurn && !g.over) this.notify(`Your turn against ${this.opponentName}.`);
        this.afterChange();
        return;
      }
    }
  }

  private async finishGame(): Promise<void> {
    const g = this.game;
    if (!g || this.finishedId === g.id) return;
    this.finishedId = g.id;
    const result = g.winner === 'you' ? 'win' : g.winner === 'draw' ? 'draw' : 'loss';
    const score = { you: g.state.score[this.seat], them: g.state.score[this.other] };
    const ratingBefore = this.profile.rating;
    let ratingAfter: number | null = null;
    if (g.state.status === 'finished') {
      // a game counts against the house at your level, or against a person who brought a rating
      const against = this.opponentRating;
      if (against != null) ratingAfter = nextRating(ratingBefore, against, result);
      this.saveProfile({
        played: this.profile.played + 1,
        won: this.profile.won + (result === 'win' ? 1 : 0),
        rating: ratingAfter ?? ratingBefore,
        active: null,
      });
    } else this.saveProfile({ active: null });
    this.finish = { result, resigned: this.resigned, score, ratingBefore, ratingAfter, review: null, replayUrl: g.replayUrl ?? null };
    this.notify(result === 'win' ? `You beat ${this.opponentName} ${score.you}–${score.them}!` : `${this.opponentName} won ${score.them}–${score.you}.`);
    this.emit();
    if (g.state.moveCount > 0) {
      try {
        const review = await g.review();
        if (this.game?.id === g.id && this.finish) this.finish = { ...this.finish, review, replayUrl: g.replayUrl ?? null };
      } catch {}
      this.emit();
    }
  }

  /** A note in GTA's own feed, when the tablet is put away. */
  private notify(text: string): void {
    if (!this.visible) void post('notify', { text });
  }

  /* -------------------------------- table -------------------------------- */

  setTable(t: TableContext | null): void {
    const was = this.table;
    this.table = t;
    if (!t || !t.opposite) this.offer = null;
    if (t && !was && this.game && !this.game.over) void post('tableGame', { gameId: this.game.id, seat: this.game.state.seat });
    // the player you invited got up before joining: call the room off
    if (this.mode === 'table' && this.game?.waiting && !t?.opposite) {
      this.say(was?.opposite ? `${was.opposite.name} left the table.` : 'The other chair is empty now.');
      void this.resign();
    }
    this.emit();
  }

  /** The player across said no to the room you opened for them. */
  offerDeclined(from: string): void {
    if (this.mode !== 'table' || !this.game?.waiting) return;
    this.say(`${from} doesn't want to play right now.`);
    void this.resign();
  }

  receiveOffer(o: TableOffer): void {
    this.offer = o;
    if (!this.visible) void post('notify', { text: `${o.from} wants to play you. Open Smash&Clash to join.` });
    this.emit();
  }
}

/** The table before the first move a sync carries: the state the move after it started from. */
function previousState(s: { state: SeatState; moves: SeatMove[] }): SeatState {
  const first = s.moves[0];
  // the opening table is empty, with both hands dealt and the Mutators tiles set
  return { ...first.state, board: first.state.board.map((row) => row.map(() => null)), turn: 1, current: first.seat };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function errorText(e: unknown): string {
  const err = e as { message?: string; hint?: string; quiet?: boolean; status?: number };
  const msg = err?.message || String(e);
  // the site's firewall is asking this connection to slow down: it lifts by itself in minutes
  if (/challenge|security checkpoint/i.test(msg) || (err?.status === 403 && /vercel/i.test(msg))) return 'smashandclash.in asked this connection to slow down for a few minutes. Try again shortly.';
  if (/failed to fetch|networkerror|load failed/i.test(msg) || isNetworkError(e)) return 'Could not reach smashandclash.in. Check your connection and try again.';
  return err?.hint ? `${msg} ${err.hint}` : msg;
}
