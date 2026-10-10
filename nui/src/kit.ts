// The deck, the kit (colours and sounds) and the rules, shipped inside the resource
// (tools/vendor-assets.mjs). In game the page reaches smashandclash.in only through the SDK, for
// the games themselves.

import type { Assets, Card } from '@smashandclash/sdk';

async function local<T>(path: string, as: 'json' | 'text'): Promise<T> {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`The resource is missing ${path}: rebuild it (npm run build).`);
  return (as === 'json' ? res.json() : res.text()) as Promise<T>;
}

export const loadDeck = (): Promise<Card[]> => local<Card[]>('./kit/cards.json', 'json');
export const loadKit = (): Promise<Assets> => local<Assets>('./kit/kit.json', 'json');
export const loadRules = (): Promise<string> => local<string>('./kit/rules.txt', 'text');
