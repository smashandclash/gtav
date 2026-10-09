// What the player sees on screen while seated at a table: the panel (lobby, waiting room,
// sheets) beside the 3D board, and in a match the HUD over it, plus each move's sound. The
// board itself is in the world: this page sends it what to show (postView, move).

import type { HandCard, Seat, SeatMove, SeatState } from '@smashandclash/sdk';
import { Sound } from './audio';
import { openInBrowser, post } from './bridge';
import { Controller, type Animator } from './controller';
import { completed, handKey, movesFor, nextTargets, parseMove, type ParsedMove } from './moves';
import { Nav } from './nav';
import { stepsFor, tableView, type Step } from './view';

const SITE = 'https://www.smashandclash.in';

type Sheet = null | 'friend' | 'rules' | 'settings' | 'resign';

/* ------------------------------- tiny DOM -------------------------------- */

type Child = Node | string | null | undefined | false;
function h<K extends keyof HTMLElementTagNameMap>(tag: K, props: Record<string, unknown> = {}, ...children: Child[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = String(v);
    else if (k === 'text') el.textContent = String(v);
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v as EventListener);
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const c of children) if (c != null && c !== false) el.append(c);
  return el;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const cellOf = (c: unknown): string | null => {
  if (typeof c === 'string') return c;
  const o = c as { r?: number; c?: number } | null;
  return o && typeof o.r === 'number' && typeof o.c === 'number' ? `${'ABCDE'[o.c]}${o.r + 1}` : null;
};

/* ---------------------------------- UI ----------------------------------- */

export class UI implements Animator {
  readonly sound: Sound;
  readonly nav: Nav;
  ctl!: Controller;

  private app = document.getElementById('app')!;
  private screenEl = document.getElementById('screen')!;
  private toastEl = document.getElementById('toast')!;
  private bannerEl = document.getElementById('banner')!;
  private sheetHost = document.getElementById('sheet')!;

  private built: string | null = null;
  private sheet: Sheet = null;
  private selected: number | null = null;
  private path: string[] = [];
  private joinText = '';

  // match HUD
  private camMode = 'seat';
  private lastView = '';
  private handEl: HTMLElement | null = null;
  private handIds: number[] = [];
  private refs: Record<string, HTMLElement> = {};

  constructor() {
    this.sound = new Sound(() => ({ music: this.ctl.profile.music, effects: this.ctl.profile.effects, voices: this.ctl.profile.voices }));
    this.nav = new Nav({
      layer: () => (this.sheetHost.firstElementChild as HTMLElement | null) ?? this.app,
      back: () => this.back(),
      hand: (key) => this.handKey(key),
    });
    // --u: 1% of a 16:10 frame that fits the screen, so 1080p, 1440p and 4K read the same
    const resize = () => document.documentElement.style.setProperty('--u', `${Math.min(innerWidth, innerHeight * 1.6) / 100}px`);
    window.addEventListener('resize', resize);
    resize();
  }

  attach(ctl: Controller): void {
    this.ctl = ctl;
    ctl.onChange(() => this.render());
  }

  /* ------------------------------ visibility ----------------------------- */

  show(): void {
    this.app.hidden = false;
    this.app.classList.remove('closing');
    this.ctl.visible = true;
    this.sound.setMuted(false);
    this.render();
    if (!this.nav.active) this.nav.focus(this.firstButton());
  }

  hide(): void {
    if (this.app.hidden) return;
    this.ctl.visible = false;
    this.sound.setMuted(true);
    this.sheet = null;
    this.app.classList.add('closing');
    setTimeout(() => {
      this.app.hidden = true;
      this.app.classList.remove('closing');
    }, 200);
  }

  /** Hide the panel and stay seated: the game keeps going, GTA's feed says when it is your turn, and F7 brings it back. */
  putAway(): void {
    this.hide();
    void post('close');
  }

  private back(): void {
    if (this.sheet) return this.closeSheet();
    if (this.selected != null || this.path.length) {
      this.selected = null;
      this.path = [];
      return this.render();
    }
    if (this.ctl.offer) return this.ctl.declineOffer();
    this.putAway();
  }

  private firstButton(): HTMLElement | null {
    const layer = (this.sheetHost.firstElementChild as HTMLElement | null) ?? this.app;
    return layer.querySelector<HTMLElement>('[data-first]') ?? layer.querySelector<HTMLElement>('button:not(:disabled)');
  }

  /* -------------------------------- render ------------------------------- */

  render(): void {
    const ctl = this.ctl;
    document.body.classList.toggle('reduce-motion', ctl.profile.reduceMotion);
    const key = ctl.screen === 'waiting' ? `waiting:${ctl.mode}` : ctl.screen === 'match' ? `match:${ctl.game?.id}` : ctl.screen;
    if (key !== this.built) {
      this.built = key;
      this.selected = null;
      this.path = [];
      this.screenEl.replaceChildren(this.build(ctl.screen));
      this.music();
      if (ctl.visible) this.nav.focus(this.firstButton());
    }
    if (ctl.screen === 'lobby') this.updateLobby();
    if (ctl.screen === 'match') this.updateMatch();
    if (ctl.screen === 'waiting') this.updateWaiting();
    this.updateToast();
    this.updateBanner();
    this.renderSheet();
    this.nav.settle();
  }

  private music(): void {
    const ctl = this.ctl;
    if (ctl.screen === 'lobby') this.sound.play('menu');
    else if (ctl.screen === 'waiting') this.sound.play('matchmaking');
    else if (ctl.screen === 'match' && !ctl.finish) this.sound.play('battle');
  }

  private build(screen: string): HTMLElement {
    if (screen === 'lobby') return this.buildLobby();
    if (screen === 'waiting') return this.buildWaiting();
    if (screen === 'match') return this.buildMatch();
    return h(
      'div',
      { class: 'panel waiting' },
      h('img', { class: 'logo', src: `${SITE}/logo.svg`, alt: 'Smash&Clash', style: { width: '46%' } }),
      h('p', {}, h('span', { class: 'dots', text: 'Shuffling the deck' })),
    );
  }

  /* -------------------------------- lobby -------------------------------- */

  private buildLobby(): HTMLElement {
    const ctl = this.ctl;
    this.refs = {};
    const plate = this.plate('you', ctl.name, '');
    this.refs.youMeta = plate.querySelector('.meta')!;
    this.refs.tableStrip = h('div', { class: 'table-strip', hidden: true });
    const mut = h('button', { class: 'mutators', 'aria-pressed': 'true', onclick: () => this.setRuleset('mutators') }, 'Mutators');
    const cls = h('button', { class: 'classic', 'aria-pressed': 'false', onclick: () => this.setRuleset('classic') }, 'Classic');
    this.refs.mut = mut;
    this.refs.cls = cls;
    const busy = (fn: () => Promise<void>) => () => {
      this.sound.sfx('click');
      void fn();
    };
    this.refs.play = h('button', { class: 'candy sun hero', 'data-first': true, onclick: busy(() => ctl.playNow()) }, h('span', {}, 'PLAY', h('small', { text: 'A game now, against a player at your level' })));
    // a panel beside the table: the board itself stays in view
    return h(
      'div',
      { class: 'panel lobby' },
      h('img', { class: 'logo', src: ctl.kit?.brand.logo ?? `${SITE}/logo.svg`, alt: 'Smash&Clash' }),
      plate,
      this.refs.tableStrip,
      this.refs.play,
      h('button', { class: 'candy sky', onclick: busy(() => ctl.quickMatch()) }, h('span', {}, 'Quick match', h('small', { text: 'Players on every Smash&Clash app, right now' }))),
      h('button', { class: 'candy grape', onclick: () => this.openSheet('friend') }, h('span', {}, 'Play a friend', h('small', { text: 'Make a room, or join one with its code' }))),
      h('div', { class: 'segmented', role: 'group', 'aria-label': 'Rules' }, mut, cls),
      h(
        'div',
        { class: 'lobby-row' },
        h('button', { class: 'candy small', onclick: () => this.openSheet('rules') }, h('span', { text: 'How to play' })),
        h('button', { class: 'candy small', onclick: () => this.openSheet('settings') }, h('span', { text: 'Settings' })),
        h('button', { class: 'candy small', onclick: () => this.putAway() }, h('span', { text: 'Hide' })),
      ),
    );
  }

  private updateLobby(): void {
    const ctl = this.ctl;
    const p = ctl.profile;
    this.refs.youMeta.textContent = p.played ? `Rating ${Math.round(p.rating)} · ${p.won} won of ${p.played}` : `Rating ${Math.round(p.rating)}`;
    this.refs.mut.setAttribute('aria-pressed', String(p.ruleset === 'mutators'));
    this.refs.cls.setAttribute('aria-pressed', String(p.ruleset === 'classic'));
    for (const b of this.screenEl.querySelectorAll<HTMLButtonElement>('.lobby-right .candy')) b.disabled = !!ctl.busy;
    const strip = this.refs.tableStrip;
    const t = ctl.table;
    strip.hidden = !t;
    if (t) {
      const across = t.opposite;
      const key = `${t.id}:${across?.name ?? ''}:${ctl.busy ?? ''}`;
      if (strip.dataset.key !== key) {
        strip.dataset.key = key;
        const parts: HTMLElement[] = [
          h('div', { class: 'what' }, h('b', { text: across ? `${across.name} is across the table` : 'The other chair is empty' }), across ? 'Play them face to face.' : `Table at ${t.label}. Anyone who sits down can play you.`),
        ];
        if (across) parts.push(h('button', { class: 'candy gum small', disabled: !!ctl.busy, onclick: () => void ctl.challengeAcross() }, h('span', { text: `Play ${across.name}` })));
        parts.push(h('button', { class: 'candy small', onclick: () => void post('leaveTable') }, h('span', { text: 'Get up' })));
        strip.replaceChildren(...parts);
      }
    }
  }

  private setRuleset(r: 'mutators' | 'classic'): void {
    this.sound.sfx('click');
    this.ctl.saveProfile({ ruleset: r });
  }

  /* ------------------------------- waiting ------------------------------- */

  private buildWaiting(): HTMLElement {
    const ctl = this.ctl;
    const back = ctl.kit?.card.back ?? `${SITE}/Card_Back_v2.png`;
    const cancel = h('button', { class: 'candy', 'data-first': true, onclick: () => void ctl.resign() }, h('span', { text: 'Cancel' }));
    if (ctl.mode === 'room') {
      const code = ctl.game?.code ?? '';
      return h(
        'div',
        { class: 'panel waiting' },
        h('h1', { text: 'Your room' }),
        h('div', { class: 'code', 'aria-label': `Room code ${code.split('').join(' ')}` }, ...code.split('').map((ch) => h('span', { text: ch }))),
        h('p', { text: 'Anyone joins with this code: here in Los Santos, on smashandclash.in, in Telegram or the terminal.' }),
        h('p', {}, h('span', { class: 'dots', text: 'Waiting for a player' })),
        cancel,
      );
    }
    const across = ctl.table?.opposite?.name ?? 'your friend';
    const table = ctl.mode === 'table';
    return h(
      'div',
      { class: 'panel waiting' },
      h('div', { class: 'spinner-cards' }, h('img', { src: back, alt: '' }), h('img', { src: back, alt: '' }), h('img', { src: back, alt: '' })),
      h('h1', {}, h('span', { class: 'dots', text: table ? `Waiting for ${across}` : 'Finding a player' })),
      h('p', { text: table ? `${across} gets your invite across the table.` : 'The queue is shared by every Smash&Clash app: the website, Telegram, the terminal, a Nintendo DS, and GTA V.' }),
      cancel,
    );
  }

  private updateWaiting(): void {
    for (const b of this.screenEl.querySelectorAll<HTMLButtonElement>('button')) b.disabled = !!this.ctl.busy;
  }

  /* -------------------------------- match -------------------------------- */

  /* --------------------------------- match --------------------------------- */

  // The board is in the world (client/board.lua draws it from postView); the page lays a HUD
  // over it: both players, whose turn it is, your hand (in the third-person views), the buttons,
  // and the cursor, whose clicks the game turns into a tile or a card on the table.
  private buildMatch(): HTMLElement {
    const ctl = this.ctl;
    this.refs = {};
    this.handIds = [];
    this.lastView = '';
    const them = this.plate('them', ctl.opponentName, '');
    const you = this.plate('you', ctl.name, '');
    this.refs.themMeta = them.querySelector('.meta')!;
    this.refs.youMeta = you.querySelector('.meta')!;
    this.refs.themScore = them.appendChild(h('div', { class: 'score', text: '0' }));
    this.refs.youScore = you.appendChild(h('div', { class: 'score', text: '0' }));
    this.refs.turn = h('div', { class: 'turn', role: 'status', 'aria-live': 'polite' });
    this.refs.deckCount = h('span');
    this.refs.mode = h('div', { class: `mode-tag ${ctl.game?.state.ruleset ?? 'mutators'}`, text: ctl.game?.state.ruleset === 'classic' ? 'Classic' : 'Mutators' });
    this.handEl = h('div', { class: 'hand', 'aria-label': 'Your hand' });
    this.refs.tileRow = h('div', { class: 'tile-row', 'aria-label': 'Tiles' });
    this.refs.stay = h('button', { class: 'candy mint', hidden: true, onclick: () => this.playHopStay() }, h('span', { text: 'Stay here' }));
    this.refs.camera = h('button', { class: 'candy small sky', onclick: () => void this.cycleCamera() }, h('span', { text: 'View' }));
    this.refs.resign = h('button', { class: 'candy small cherry', onclick: () => this.openSheet('resign') }, h('span', { text: 'Resign' }));
    this.refs.does = h('div', { class: 'does', hidden: true });
    this.refs.result = h('div', { class: 'result', hidden: true });
    const hud = h(
      'div',
      { class: 'hud' },
      h(
        'div',
        { class: 'hud-top' },
        them,
        h('div', { class: 'hud-right' }, this.refs.turn, h('div', { class: 'deck' }, h('img', { src: ctl.kit?.card.back ?? `${SITE}/Card_Back_v2.png`, alt: '' }), this.refs.deckCount), this.refs.mode),
      ),
      h('div', { class: 'hud-bottom' }, you, h('div', { class: 'hand-wrap' }, this.refs.tileRow, this.handEl), h('div', { class: 'actions-col' }, this.refs.stay, this.refs.camera, this.refs.resign)),
      this.refs.does,
      this.refs.result,
    );
    // the cursor on the table: hover lights what it is over, a click picks it
    let last = 0;
    const onTable = (e: Event) => e.target === hud || (e.target as HTMLElement).classList?.contains('hud-top') || (e.target as HTMLElement).classList?.contains('hud-bottom');
    hud.addEventListener('pointermove', (e) => {
      if (!onTable(e) || performance.now() - last < 45) return;
      last = performance.now();
      void this.pointer(e, false);
    });
    hud.addEventListener('click', (e) => {
      if (onTable(e)) void this.pointer(e, true);
    });
    return hud;
  }

  private async pointer(e: MouseEvent, click: boolean): Promise<void> {
    const r = await post<{ hit?: { kind: 'tile' | 'hand'; cell?: string; index?: number } | false }>('pointer', { x: e.clientX / innerWidth, y: e.clientY / innerHeight }).catch(() => null);
    const hit = r?.hit || null;
    const hud = this.screenEl.querySelector<HTMLElement>('.hud');
    const live = !!hit && this.ctl.canPlay && ((hit.kind === 'tile' && this.targets().has(hit.cell!)) || hit.kind === 'hand');
    hud?.classList.toggle('pointing', live);
    if (!click) return;
    if (hit?.kind === 'tile') this.clickTile(hit.cell!);
    else if (hit?.kind === 'hand') this.clickHand(hit.index!);
    else if (this.selected != null || this.path.length) {
      this.selected = null;
      this.path = [];
      this.render();
    }
  }

  private async cycleCamera(): Promise<void> {
    this.sound.sfx('click');
    const r = await post<{ mode?: string }>('camera').catch(() => null);
    this.camMode = r?.mode ?? (this.camMode === 'seat' ? 'first' : this.camMode === 'first' ? 'top' : 'seat');
    this.render();
  }

  private updateMatch(): void {
    const ctl = this.ctl;
    const g = ctl.game;
    const s = ctl.shown;
    if (!g || !s) return;
    const seat = ctl.seat;
    const view = g.view;
    const myTurn = ctl.canPlay;

    const score = scoreOf(s, seat);
    this.refs.youScore.textContent = String(score.you);
    this.refs.themScore.textContent = String(score.them);
    this.refs.youMeta.textContent = `Rating ${Math.round(ctl.profile.rating)}`;
    const from = ctl.opponentFrom;
    const r = ctl.opponentRating;
    this.refs.themMeta.textContent = [from ? `on ${from}` : null, r != null ? `Rating ${Math.round(r)}` : null].filter(Boolean).join(' · ');
    this.refs.deckCount.textContent = `${s.deck} left`;
    const camLabel: Record<string, string> = { seat: 'View: seat', first: 'View: eyes', top: 'View: above' };
    this.refs.camera.querySelector('span')!.textContent = camLabel[this.camMode] ?? 'View';

    // your hand on screen in the third-person views; in first person you look at the table
    this.handEl!.hidden = this.camMode === 'first';
    this.paintHand(s.hand, view?.hand ?? [], myTurn);
    this.paintTileButtons(myTurn);

    const turn = this.refs.turn;
    const hop = myTurn && !!view?.pendingHop;
    this.refs.stay.hidden = !hop;
    if (g.over) {
      turn.className = 'turn';
      turn.replaceChildren('Game over');
    } else if (myTurn) {
      turn.className = 'turn mine';
      turn.replaceChildren('Your turn', h('small', { text: hop ? 'Hop to a glowing tile, or stay' : this.selected == null ? 'Pick a card' : 'Now pick a glowing tile' }));
    } else {
      turn.className = 'turn';
      const label = ctl.busy ?? (ctl.animating ? `${ctl.opponentName} played` : `${ctl.opponentName}'s turn`);
      turn.replaceChildren(h('span', { class: ctl.animating ? '' : 'dots', text: label }));
    }
    this.refs.resign.toggleAttribute('disabled', g.over || !!ctl.busy);

    const picked = this.selected != null ? view?.hand[this.selected] : undefined;
    const does = this.refs.does;
    if (myTurn && picked?.kind === 'effect') {
      const now = this.pickMoves().find((m) => m.cells.length === 0);
      const key = `${picked.card}:${now?.name ?? ''}`;
      if (does.dataset.key !== key) {
        does.dataset.key = key;
        does.replaceChildren(
          h('div', { text: picked.does }),
          now
            ? h('button', { class: 'candy sun small', style: { marginTop: 'calc(var(--u) * 0.8)' }, onclick: () => this.play(now.name) }, h('span', { text: `Play ${picked.card.replace(/!$/, '')}` }))
            : h('div', { style: { marginTop: 'calc(var(--u) * 0.4)', opacity: '0.75' }, text: 'Now pick a glowing tile on the table.' }),
        );
      }
      does.hidden = false;
    } else {
      does.hidden = true;
      does.dataset.key = '';
    }

    this.postView();
    this.updateResult();
  }

  /** The table as this player sees it, for the board in the world. Sent only when it changes. */
  private postView(): void {
    const ctl = this.ctl;
    const g = ctl.game;
    const s = ctl.shown;
    const t = ctl.table;
    if (!g || !s || !t || ctl.animating) return;
    const view = g.view;
    const myTurn = ctl.canPlay;
    const legal = myTurn ? view?.legalMoves ?? [] : [];
    const v = tableView({
      game: g.id,
      state: s,
      players: g.state.players,
      kinds: g.state.playerKinds,
      viewer: ctl.seat,
      flip: t.seat !== ctl.seat,
      colors: ctl.kit?.colors ?? {},
      over: g.over,
      ui: {
        myTurn,
        targets: myTurn ? [...this.targets()] : [],
        picked: this.path,
        selected: this.selected,
        dead: (view?.hand ?? []).map((c) => myTurn && !legal.some((n) => parseMove(n).key === handKey(c))),
      },
    });
    const text = JSON.stringify(v);
    if (text === this.lastView) return;
    this.lastView = text;
    void post('view', { table: t.id, view: v });
  }

  private plate(side: 'you' | 'them', name: string, meta: string): HTMLElement {
    return h(
      'div',
      { class: `plate ${side}` },
      h('div', { class: 'badge', 'aria-hidden': 'true', text: (name.trim()[0] ?? '?').toUpperCase() }),
      h('div', { class: 'who' }, h('div', { class: 'name', text: name }), h('div', { class: 'meta', text: meta })),
    );
  }

  private paintHand(ids: number[], hand: HandCard[], myTurn: boolean): void {
    const el = this.handEl!;
    el.classList.toggle('idle', !myTurn);
    const same = ids.length === this.handIds.length && ids.every((id, i) => id === this.handIds[i]);
    if (!same) {
      const before = new Set(this.handIds);
      const fresh = this.handIds.length > 0;
      el.replaceChildren(
        ...ids.map((id, i) => {
          const info = this.ctl.cards.get(id);
          return h(
            'button',
            { class: `hand-card${fresh && !before.has(id) ? ' drawn' : ''}`, 'data-key': `hand:${id}`, 'aria-label': info?.name ?? 'card', onclick: () => this.clickHand(i) },
            h('img', { src: info?.image ?? '', alt: '' }),
            h('span', { class: 'key', text: String(i + 1) }),
          );
        }),
      );
      this.handIds = [...ids];
    }
    const legal = myTurn ? this.ctl.game?.view?.legalMoves ?? [] : [];
    el.querySelectorAll<HTMLButtonElement>('.hand-card').forEach((b, i) => {
      const card = hand[i];
      const playable = !!card && legal.some((n) => parseMove(n).key === handKey(card));
      b.classList.toggle('selected', this.selected === i);
      b.classList.toggle('dead', myTurn && !playable);
      if (card?.kind === 'character') b.setAttribute('aria-label', `${card.card}, ${card.top} ${card.right} ${card.bottom} ${card.left}${playable ? '' : ', nothing to do'}`);
    });
  }

  /** A button for each tile the picked card can go to, so keys and a controller can play too. */
  private paintTileButtons(myTurn: boolean): void {
    const row = this.refs.tileRow;
    const cells = myTurn && this.selected != null ? [...this.targets()].sort() : myTurn && this.ctl.game?.view?.pendingHop ? [...this.targets()].sort() : [];
    const key = `${cells.join(',')}|${this.path.join(',')}`;
    if (row.dataset.key === key) return;
    row.dataset.key = key;
    row.replaceChildren(...cells.map((c) => h('button', { class: 'candy small mint', 'data-key': `tile:${c}`, onclick: () => this.clickTile(c) }, h('span', { text: c }))));
  }

  /* ------------------------------ picking moves ----------------------------- */

  private pickMoves(): ParsedMove[] {
    const view = this.ctl.game?.view;
    if (!view) return [];
    if (view.pendingHop) return movesFor(view.legalMoves, 'hop', this.path);
    const card = this.selected != null ? view.hand[this.selected] : undefined;
    return card ? movesFor(view.legalMoves, handKey(card), this.path) : [];
  }

  private targets(): Set<string> {
    return nextTargets(this.pickMoves(), this.path);
  }

  private clickHand(i: number): void {
    const ctl = this.ctl;
    const view = ctl.game?.view;
    if (!ctl.canPlay || !view || view.pendingHop) return;
    const card = view.hand[i];
    if (!card) return;
    const playable = view.legalMoves.some((n) => parseMove(n).key === handKey(card));
    if (!playable) {
      this.sound.sfx('deny');
      ctl.say(`${card.card.replace(/!$/, '')} has nothing to do right now.`);
      return;
    }
    if (this.selected === i) {
      // a second press plays a card that needs no tile (Flip!, Swap!), or puts it back
      const now = this.pickMoves().find((m) => m.cells.length === 0);
      if (now) return this.play(now.name);
      this.selected = null;
    } else {
      this.selected = i;
      this.sound.sfx('cardPick');
    }
    this.path = [];
    this.render();
    // send the ring to the first tile the card can go to
    if (this.selected != null && this.nav.active) {
      const first = this.refs.tileRow?.querySelector<HTMLElement>('button');
      if (first) this.nav.focus(first);
    }
  }

  private clickTile(cell: string): void {
    if (!this.ctl.canPlay) return;
    if (!this.targets().has(cell)) {
      if (this.path.length) {
        this.path = [];
        this.render();
      }
      return;
    }
    this.path = [...this.path, cell];
    const done = completed(this.pickMoves(), this.path);
    if (done) return this.play(done.name);
    this.sound.sfx('click');
    this.render();
  }

  private playHopStay(): void {
    const stay = this.ctl.game?.view?.legalMoves.find((n) => n.startsWith('hop') && !n.includes('→'));
    if (stay) this.play(stay);
  }

  private play(name: string): void {
    this.selected = null;
    this.path = [];
    void this.ctl.play(name);
  }

  /** 1–5 pick a hand card; LB / RB step through the playable ones. */
  private handKey(key: string): boolean {
    if (this.ctl.screen !== 'match' || this.sheet) return false;
    const n = this.handIds.length;
    if (!n) return false;
    let i: number;
    if (key === 'lb' || key === 'rb') i = ((this.selected ?? (key === 'rb' ? -1 : n)) + (key === 'rb' ? 1 : -1) + n) % n;
    else i = Number(key) - 1;
    if (i < 0 || i >= n) return false;
    const btn = this.handEl?.querySelectorAll<HTMLElement>('.hand-card')[i];
    if (this.selected !== i) this.clickHand(i);
    if (btn && this.selected == null) this.nav.focus(btn);
    return true;
  }

  /* -------------------------------- result -------------------------------- */

  private updateResult(): void {
    const ctl = this.ctl;
    const f = ctl.finish;
    const el = this.refs.result;
    if (!f || ctl.animating) {
      el.hidden = true;
      return;
    }
    const key = `${f.result}:${f.ratingAfter}:${f.review ? 'r' : ''}:${ctl.busy ?? ''}`;
    if (el.dataset.key === key) return;
    const first = !el.dataset.key;
    el.dataset.key = key;
    el.hidden = false;
    if (first) {
      this.sound.play(f.result === 'win' ? 'victory' : 'defeat');
      this.sound.announcer(f.result === 'win' ? 'victory' : 'defeat');
      this.sound.sfx(f.result === 'win' ? 'win' : 'lose');
      if (f.ratingAfter != null && f.ratingAfter !== f.ratingBefore) setTimeout(() => this.sound.sfx(f.ratingAfter! > f.ratingBefore ? 'eloUp' : 'eloDown'), 900);
    }
    const delta = f.ratingAfter != null ? f.ratingAfter - f.ratingBefore : null;
    const seat = ctl.seat;
    const other = ctl.other;
    const rv = f.review;
    const again = this.againAction();
    el.replaceChildren(
      h(
        'div',
        { class: 'result-card', role: 'dialog', 'aria-label': 'Game over' },
        h('div', { class: `ribbon ${f.result === 'win' ? '' : 'loss'}`, text: f.result === 'win' ? 'YOU WIN!' : f.result === 'draw' ? 'DRAW' : 'YOU LOSE' }),
        h('div', { class: 'final-score' }, h('span', { class: 'you', text: String(f.score.you) }), h('span', { class: 'vs', text: 'to' }), h('span', { class: 'them', text: String(f.score.them) })),
        h('div', { class: 'result-line' }, f.resigned ? 'You resigned. ' : '', delta != null ? h('span', {}, `Rating ${f.ratingBefore} → ${f.ratingAfter} `, h('span', { class: delta >= 0 ? 'up' : 'down', text: `(${delta >= 0 ? '+' : ''}${delta})` })) : `vs ${ctl.opponentName}`),
        rv
          ? h(
              'div',
              { class: 'review' },
              h('div', {}, h('b', { text: `${Math.round(rv.accuracy[seat])}%` }), 'Your accuracy'),
              h('div', {}, h('b', { text: `${Math.round(rv.accuracy[other])}%` }), `${ctl.opponentName}'s accuracy`),
            )
          : null,
        h(
          'div',
          { class: 'actions' },
          again ? h('button', { class: 'candy sun', 'data-first': true, disabled: !!ctl.busy, onclick: again.run }, h('span', { text: again.label })) : null,
          h('button', { class: 'candy', 'data-first': !again, onclick: () => ctl.toLobby() }, h('span', { text: 'Lobby' })),
          f.replayUrl ? h('button', { class: 'candy sky', onclick: () => this.openReplay(f.replayUrl!) }, h('span', { text: 'Replay' })) : null,
        ),
      ),
    );
    if (first && ctl.visible) this.nav.focus(this.firstButton());
  }

  private againAction(): { label: string; run: () => void } | null {
    const ctl = this.ctl;
    if (ctl.mode === 'house') return { label: 'Play again', run: () => void ctl.playNow() };
    if (ctl.mode === 'quick') return { label: 'Find another', run: () => void ctl.quickMatch() };
    if (ctl.mode === 'table' && ctl.table?.opposite) return { label: `Rematch ${ctl.table.opposite.name}`, run: () => void ctl.challengeAcross() };
    return null;
  }

  private openReplay(url: string): void {
    if (openInBrowser(url)) this.ctl.say('The replay opened in your browser.');
    else this.ctl.say(`Replay: ${url}`, 'info', 9000);
  }

  /* -------------------------------- notes -------------------------------- */

  private updateToast(): void {
    const n = this.ctl.notice;
    const show = n && n.until > Date.now();
    if (!show) {
      this.toastEl.hidden = true;
      this.toastEl.dataset.key = '';
      return;
    }
    const key = `${n.text}:${n.until}`;
    if (this.toastEl.dataset.key === key) return;
    this.toastEl.dataset.key = key;
    this.toastEl.hidden = false;
    this.toastEl.className = `toast ${n.tone === 'error' ? 'error' : ''}`;
    this.toastEl.textContent = n.text;
  }

  private updateBanner(): void {
    const o = this.ctl.offer;
    const el = this.bannerEl;
    if (!o) {
      el.hidden = true;
      el.dataset.key = '';
      return;
    }
    const key = `${o.from}:${o.code}:${this.ctl.busy ?? ''}`;
    if (el.dataset.key === key) return;
    const first = !el.dataset.key;
    el.dataset.key = key;
    el.hidden = false;
    el.replaceChildren(
      h('span', { text: `${o.from} wants to play you` }),
      h('button', { class: 'candy mint small', disabled: !!this.ctl.busy, onclick: () => void this.ctl.acceptOffer() }, h('span', { text: 'Join' })),
      h('button', { class: 'candy small', onclick: () => this.ctl.declineOffer() }, h('span', { text: 'Not now' })),
    );
    if (first) {
      this.sound.sfx('matchFound');
      if (this.ctl.visible) this.nav.focus(el.querySelector('button'));
    }
  }

  /* -------------------------------- sheets -------------------------------- */

  private openSheet(s: Sheet): void {
    this.sound.sfx('click');
    this.sheet = s;
    if (s === 'rules') void this.ctl.loadRules();
    this.sheetHost.dataset.key = '';
    this.render();
    this.nav.focus(this.firstButton());
  }

  private closeSheet(): void {
    this.sheet = null;
    this.render();
    this.nav.focus(this.firstButton());
  }

  private renderSheet(): void {
    const host = this.sheetHost;
    if (!this.sheet) {
      host.replaceChildren();
      host.dataset.key = '';
      return;
    }
    const ctl = this.ctl;
    const key = `${this.sheet}:${ctl.busy ?? ''}:${this.sheet === 'rules' ? ctl.rulesText.length : ''}:${this.sheet === 'settings' ? JSON.stringify([ctl.profile.voices, ctl.profile.reduceMotion]) : ''}`;
    if (host.dataset.key === key) return;
    host.dataset.key = key;
    const done = h('button', { class: 'candy', onclick: () => this.closeSheet() }, h('span', { text: 'Done' }));
    let body: HTMLElement[];
    if (this.sheet === 'friend') {
      const input = h('input', {
        type: 'text',
        value: this.joinText,
        maxlength: '200',
        placeholder: 'Room code, like K7QF2M',
        'aria-label': 'Room code or link',
        autocomplete: 'off',
        spellcheck: 'false',
        oninput: (e: Event) => (this.joinText = (e.target as HTMLInputElement).value),
      });
      const form = h(
        'form',
        {
          class: 'field',
          onsubmit: (e: Event) => {
            e.preventDefault();
            this.sheet = null;
            void ctl.join(this.joinText).then(() => (this.joinText = ''));
          },
        },
        input,
        h('button', { class: 'candy sky', type: 'submit', disabled: !!ctl.busy }, h('span', { text: 'Join' })),
      );
      body = [
        h('h2', { text: 'Play a friend' }),
        h('p', { text: "Make a room and tell your friend its code. They can join from here, smashandclash.in, Telegram or the terminal. Or join theirs with the code they sent you." }),
        h('button', { class: 'candy mint', 'data-first': true, disabled: !!ctl.busy, onclick: () => ((this.sheet = null), void ctl.createRoom()) }, h('span', { text: 'Make a room' })),
        form,
        h('div', { class: 'actions' }, h('button', { class: 'candy', onclick: () => this.closeSheet() }, h('span', { text: 'Cancel' }))),
      ];
    } else if (this.sheet === 'rules') {
      body = [h('h2', { text: 'How to play' }), h('div', { class: 'scroll rules' }, ...rulesBody(ctl.rulesText)), h('div', { class: 'actions' }, done)];
    } else if (this.sheet === 'settings') {
      const p = ctl.profile;
      const slider = (label: string, value: number, set: (v: number) => void) =>
        h(
          'label',
          { class: 'setting' },
          label,
          h('input', { type: 'range', min: '0', max: '100', step: '5', value: String(Math.round(value * 100)), 'aria-label': label, oninput: (e: Event) => set(Number((e.target as HTMLInputElement).value) / 100) }),
        );
      const toggle = (label: string, on: boolean, set: (v: boolean) => void) =>
        h('div', { class: 'setting' }, label, h('button', { class: 'switch', role: 'switch', 'aria-checked': String(on), 'aria-label': label, onclick: () => set(!on) }));
      body = [
        h('h2', { text: 'Settings' }),
        slider('Music', p.music, (v) => {
          ctl.profile.music = v;
          this.sound.refresh();
          ctl.saveProfile({ music: v });
        }),
        slider('Effects', p.effects, (v) => ctl.saveProfile({ effects: v })),
        toggle('Character voices', p.voices, (v) => ctl.saveProfile({ voices: v })),
        toggle('Reduce motion', p.reduceMotion, (v) => ctl.saveProfile({ reduceMotion: v })),
        h('div', { class: 'actions' }, done),
      ];
    } else {
      body = [
        h('h2', { text: 'Resign?' }),
        h('p', { text: `${ctl.opponentName} wins this game, and it counts as a loss.` }),
        h(
          'div',
          { class: 'actions' },
          h('button', { class: 'candy', 'data-first': true, onclick: () => this.closeSheet() }, h('span', { text: 'Keep playing' })),
          h('button', { class: 'candy cherry', onclick: () => ((this.sheet = null), void ctl.resign()) }, h('span', { text: 'Resign' })),
        ),
      ];
    }
    host.replaceChildren(
      h(
        'div',
        { class: 'sheet-scrim', onclick: (e: Event) => e.target === e.currentTarget && this.closeSheet() },
        h('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true' }, ...body),
      ),
    );
  }

  /* ------------------------------ animations ------------------------------ */

  /** One move: the table in the world plays it out (client/board.lua); the page plays its sound. */
  async move(m: SeatMove, before: SeatState, seat: Seat): Promise<void> {
    const ctl = this.ctl;
    const after = m.state;
    const events = m.events as Array<Record<string, unknown> & { type: string }>;
    const { steps, total } = stepsFor(before, after, events, ctl.cards);
    const t = ctl.table;
    if (t && ctl.game) {
      const v = tableView({
        game: ctl.game.id,
        state: after,
        players: ctl.game.state.players,
        kinds: ctl.game.state.playerKinds,
        viewer: seat,
        flip: t.seat !== seat,
        colors: ctl.kit?.colors ?? {},
      });
      this.lastView = JSON.stringify(v);
      void post('move', { table: t.id, steps, view: v });
    }
    if (ctl.visible) this.voice(m, before, steps);
    await sleep(t ? total : 60);
    if (events.some((e) => e.type === 'turnStarted' && e.player === seat) && !after.gameOver) this.sound.sfx('turnChime');
  }

  private voice(m: SeatMove, before: SeatState, steps: Step[]): void {
    const events = m.events as Array<Record<string, unknown> & { type: string }>;
    for (const s of steps) if (s.sfx) setTimeout(() => this.sound.sfx(s.sfx!), s.at);
    const callout = steps.find((s) => s.kind === 'callout');
    if (callout?.sfx) this.sound.announcer(`fx${callout.sfx[0].toUpperCase()}${callout.sfx.slice(1)}`);
    const placed = events.find((e) => e.type === 'cardPlaced' || e.type === 'cardOverrun' || e.type === 'cardRecruited');
    const attacker = Number(placed?.cardId ?? placed?.newCardId ?? NaN);
    if (!Number.isFinite(attacker)) return;
    const flips = steps.filter((s) => s.kind === 'flip');
    if (flips.length) setTimeout(() => this.sound.line(attacker, 'capture', flips.length), flips[0].at);
    else if (blocked(before, m.state, m.seat, cellOf(placed?.cell ?? placed?.to))) {
      this.sound.sfx('blockThud');
      this.sound.line(attacker, 'blocked');
    } else this.sound.line(attacker, 'place');
  }
}

/* -------------------------------- helpers -------------------------------- */

function scoreOf(s: SeatState, seat: Seat): { you: number; them: number } {
  let you = 0;
  let them = 0;
  for (const row of s.board) for (const t of row) if (t) t.owner === seat ? you++ : them++;
  return { you, them };
}

/** A placement that attacked an enemy neighbour and took nothing. */
function blocked(before: SeatState, after: SeatState, mover: Seat, cell: string | null): boolean {
  if (!cell) return false;
  const r = Number(cell[1]) - 1;
  const c = 'ABCDE'.indexOf(cell[0]);
  for (const [dr, dc] of [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1],
  ]) {
    const n = before.board[r + dr]?.[c + dc];
    const m = after.board[r + dr]?.[c + dc];
    if (n && m && n.owner !== mover && !n.frozen && m.owner !== mover) return true;
  }
  return false;
}

/** The rules text from the API, as headings, paragraphs and lists, plus how to play here. */
function rulesBody(text: string): HTMLElement[] {
  if (!text) return [h('p', {}, h('span', { class: 'dots', text: 'Fetching the rules' }))];
  const out: HTMLElement[] = [];
  for (const block of text.split(/\n\s*\n/)) {
    const lines = block.split('\n').filter(Boolean);
    const items = lines.filter((l) => l.startsWith('- ')).map((l) => h('li', { text: l.slice(2) }));
    const head = lines.filter((l) => !l.startsWith('- ')).join(' ');
    if (items.length && head.endsWith(':')) out.push(h('h3', { text: head.replace(/:$/, '').replace(/\s*\(.*\)$/, '') }), h('ul', {}, ...items));
    else {
      const m = /^([A-Z][A-Za-z ]+):\s(.*)$/.exec(head);
      if (m && m[1].length < 24) out.push(h('h3', { text: m[1] }), h('p', { text: m[2] }));
      else out.push(h('p', { text: head }));
      if (items.length) out.push(h('ul', {}, ...items));
    }
  }
  out.push(
    h('h3', { text: 'Playing here' }),
    h(
      'ul',
      {},
      h('li', { text: 'Mouse: pick a card in your hand, then a glowing tile. Press an effect card again to play one that needs no tile.' }),
      h('li', { text: 'Keyboard: arrows or WASD move, Enter plays, 1 to 5 pick a card, Esc backs out or hides the panel.' }),
      h('li', { text: 'Controller: the D-pad moves, A plays, B backs out, LB and RB step through your hand.' }),
      h('li', { text: 'View switches between your seat, your own eyes and the view from above. Hide the panel with Esc and bring it back with F7: the game waits, and a note tells you when it is your turn.' }),
    ),
  );
  return out;
}
