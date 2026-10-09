// The line between the page and the game. Inside FiveM the page posts to its resource's Lua
// (https://<resource>/<event>) and hears it through window messages. In a plain browser (npm run
// dev) a small stand-in answers instead, so the client can be built and played without GTA.

export interface TableSeatInfo {
  name: string;
}

/** The table the player sits at, as the server keeps it. */
export interface TableContext {
  id: string;
  label: string;
  seat: 'A' | 'B';
  /** Who sits across; null while the other chair is empty. */
  opposite: TableSeatInfo | null;
}

/** What the game tells the page. */
export type GameMessage =
  | { type: 'open'; table: TableContext | null }
  | { type: 'hide' }
  | { type: 'table'; table: TableContext | null }
  | { type: 'tableRoom'; code: string; from: string }
  | { type: 'tableDeclined'; from: string }
  | { type: 'pad'; button: PadButton }
  | { type: 'nearby'; tables: Array<{ id: string; game: string | null; flip: boolean }> };

export type PadButton = 'up' | 'down' | 'left' | 'right' | 'accept' | 'back' | 'lb' | 'rb';

/** What the page reads from the game when it starts. */
export interface Hello {
  name: string;
  profile: string | null;
  /** Inside a dev server: no tablet animation, the page shows itself. */
  standalone?: boolean;
}

interface NuiWindow {
  GetParentResourceName?: () => string;
  invokeNative?: (native: string, arg: string) => void;
}

const w = window as unknown as NuiWindow;

export const inGame = typeof w.GetParentResourceName === 'function';
const resource = inGame ? w.GetParentResourceName!() : 'smashandclash';

/** Send an event to the resource's client script and read its answer. */
export async function post<T = unknown>(event: string, data: Record<string, unknown> = {}): Promise<T> {
  if (!inGame) return standIn(event, data) as T;
  const res = await fetch(`https://${resource}/${event}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });
  const text = await res.text();
  try {
    return JSON.parse(text) as T;
  } catch {
    return text as T;
  }
}

export function onGameMessage(handler: (m: GameMessage) => void): void {
  window.addEventListener('message', (e: MessageEvent) => {
    const m = e.data as GameMessage | null;
    if (m && typeof m === 'object' && typeof m.type === 'string') handler(m);
  });
}

/** Open a link in the player's own browser (outside the game). False when that is not possible. */
export function openInBrowser(url: string): boolean {
  if (inGame) {
    if (typeof w.invokeNative !== 'function') return false;
    w.invokeNative('openUrl', url);
    return true;
  }
  return !!window.open(url, '_blank', 'noopener');
}

/* ------------------------------- stand-in -------------------------------- */

const params = new URLSearchParams(location.search);
// each ?name= keeps its own record, so two tabs can play each other
const PROFILE_KEY = `snc-fivem-profile:${params.get('name') || 'Franklin'}`;

type StandIn = (event: string, data: Record<string, unknown>) => unknown;
let extra: StandIn | null = null;

/** The dev page's table (a preview of the board in the world) answers the table's events. */
export function setStandIn(fn: StandIn): void {
  extra = fn;
}

function standIn(event: string, data: Record<string, unknown>): unknown {
  if (extra) {
    const out = extra(event, data);
    if (out !== undefined) return out;
  }
  switch (event) {
    case 'ready': {
      let profile: string | null = null;
      try {
        profile = localStorage.getItem(PROFILE_KEY);
      } catch {}
      return { name: params.get('name') || 'Franklin', profile, standalone: true } satisfies Hello;
    }
    case 'saveProfile':
      try {
        localStorage.setItem(PROFILE_KEY, String(data.profile ?? ''));
      } catch {}
      return { ok: true };
    case 'close':
      // a browser has no game to go back to: show the reopen button the dev page carries
      document.dispatchEvent(new CustomEvent('snc:standin-closed'));
      return { ok: true };
    default:
      console.info('[game]', event, data);
      return { ok: true };
  }
}

/** The stand-in's table: the dev page sits you at one (?opposite=Lamar puts someone across). */
export function standInTable(): TableContext | null {
  if (inGame) return null;
  if (!params.get('opposite')) return { id: 'dev', label: 'the dev page', seat: 'A', opposite: null };
  return { id: 'dev', label: 'Legion Square', seat: 'A', opposite: { name: params.get('opposite') || 'Lamar' } };
}
