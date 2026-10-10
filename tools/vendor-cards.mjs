// Copies the card art the table and the panel draw into the resource (nui/public/cards), so a
// player joining a server loads the cards from the server, not 50-odd images from
// smashandclash.in at once (which looks like a bot to the site's firewall).
// The art is free to use in clients built for Smash&Clash, never to present as your own.
//   node tools/vendor-cards.mjs

import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { SmashAndClash } from '@smashandclash/sdk';

const out = fileURLToPath(new URL('../nui/public/cards/', import.meta.url));
mkdirSync(out, { recursive: true });

const sc = new SmashAndClash({ client: 'fivem-build' });
const [cards, kit] = await Promise.all([sc.cards(), sc.assets()]);

async function save(url, name) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${url}`);
  writeFileSync(out + name, Buffer.from(await res.arrayBuffer()));
}

const jobs = [...cards.map((c) => [c.image, `${c.id}.webp`]), [kit.card.back, 'back.png'], [kit.brand.logo, 'logo.svg']];
// a few at a time: this script is a polite client too
for (let i = 0; i < jobs.length; i += 4) await Promise.all(jobs.slice(i, i + 4).map(([u, n]) => save(u, n)));
console.log(`saved ${jobs.length} files to nui/public/cards`);
