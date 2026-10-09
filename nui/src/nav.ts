// Keyboard and controller navigation: arrows / WASD / D-pad move between whatever can be pressed
// on the top layer (an open sheet, else the screen), Enter / Space / A presses it, Esc / B backs
// out. The game forwards a controller's buttons as 'pad' messages; the mouse works as usual.

import type { PadButton } from './bridge';

type Dir = 'up' | 'down' | 'left' | 'right';

export interface NavHooks {
  /** The layer whose buttons are reachable: an open sheet, or the screen. */
  layer(): HTMLElement | null;
  /** Esc / B: close what is open, or put the tablet away. */
  back(): void;
  /** 1–5 pick a hand card; LB / RB step through the hand. */
  hand?(key: string): boolean;
}

const SELECTOR = 'button:not(:disabled), input, [data-nav]';

export class Nav {
  private current: HTMLElement | null = null;

  constructor(private hooks: NavHooks) {
    window.addEventListener('keydown', (e) => this.onKey(e));
    window.addEventListener('pointerdown', () => this.clear());
  }

  /** The ring is showing: the player is on keys or a controller. */
  get active(): boolean {
    return !!this.current;
  }

  /** Forwarded from the game: a controller button. */
  pad(button: PadButton): void {
    if (button === 'accept') return this.press();
    if (button === 'back') return this.hooks.back();
    if (button === 'lb' || button === 'rb') {
      this.hooks.hand?.(button);
      return;
    }
    this.move(button);
  }

  /** Put the ring on an element (after a screen change, its first button). */
  focus(el: HTMLElement | null): void {
    this.clear();
    if (!el) return;
    this.current = el;
    el.classList.add('nav-focus');
    el.focus({ preventScroll: false });
    el.scrollIntoView({ block: 'nearest' });
  }

  /** Keep the ring on the same element across a re-render, or move it to the first one. */
  settle(): void {
    if (!this.current) return;
    const layer = this.hooks.layer();
    if (this.current.isConnected && layer?.contains(this.current) && visible(this.current)) {
      this.current.classList.add('nav-focus');
      return;
    }
    const key = this.current.dataset.key;
    const same = key ? layer?.querySelector<HTMLElement>(`[data-key="${CSS.escape(key)}"]`) : null;
    this.focus(same ?? this.candidates()[0] ?? null);
  }

  clear(): void {
    this.current?.classList.remove('nav-focus');
    this.current = null;
  }

  private candidates(): HTMLElement[] {
    const layer = this.hooks.layer();
    if (!layer) return [];
    return [...layer.querySelectorAll<HTMLElement>(SELECTOR)].filter(visible);
  }

  private onKey(e: KeyboardEvent): void {
    const typing = e.target instanceof HTMLInputElement && e.target.type !== 'range';
    const dirs: Record<string, Dir> = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };
    const wasd: Record<string, Dir> = { w: 'up', s: 'down', a: 'left', d: 'right' };
    if (e.key === 'Escape' || (e.key === 'Backspace' && !typing)) {
      e.preventDefault();
      this.hooks.back();
      return;
    }
    if (typing) {
      if (e.key === 'Enter') {
        e.preventDefault();
        (e.target as HTMLInputElement).form?.requestSubmit();
      }
      if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
    }
    const dir = dirs[e.key] ?? (!typing ? wasd[e.key.toLowerCase()] : undefined);
    if (dir) {
      e.preventDefault();
      this.move(dir);
      return;
    }
    if ((e.key === 'Enter' || e.key === ' ') && this.current) {
      e.preventDefault();
      this.press();
      return;
    }
    if (!typing && /^[1-5]$/.test(e.key) && this.hooks.hand?.(e.key)) e.preventDefault();
  }

  private press(): void {
    if (!this.current || !this.current.isConnected) return this.settleOrFirst();
    if (this.current instanceof HTMLInputElement && this.current.type !== 'range') {
      this.current.focus();
      return;
    }
    this.current.click();
  }

  private settleOrFirst(): void {
    this.focus(this.candidates()[0] ?? null);
  }

  private move(dir: Dir): void {
    const all = this.candidates();
    if (!all.length) return;
    const from = this.current && all.includes(this.current) ? this.current : null;
    if (!from) return this.focus(all[0]);
    if (from instanceof HTMLInputElement && from.type === 'range' && (dir === 'left' || dir === 'right')) {
      from.stepUp(dir === 'right' ? 5 : -5);
      from.dispatchEvent(new Event('input', { bubbles: true }));
      return;
    }
    const a = from.getBoundingClientRect();
    const ax = a.left + a.width / 2;
    const ay = a.top + a.height / 2;
    let best: HTMLElement | null = null;
    let bestScore = Infinity;
    for (const el of all) {
      if (el === from) continue;
      const b = el.getBoundingClientRect();
      const bx = b.left + b.width / 2;
      const by = b.top + b.height / 2;
      const dx = bx - ax;
      const dy = by - ay;
      const along = dir === 'left' ? -dx : dir === 'right' ? dx : dir === 'up' ? -dy : dy;
      const across = dir === 'left' || dir === 'right' ? Math.abs(dy) : Math.abs(dx);
      if (along <= 4) continue;
      // prefer what lines up: distance along the direction, plus a heavy toll for drifting across
      const score = along + across * 2.2;
      if (score < bestScore) {
        bestScore = score;
        best = el;
      }
    }
    if (best) this.focus(best);
  }
}

function visible(el: HTMLElement): boolean {
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0 && !el.closest('[hidden]');
}
