// Copies everything the client shows and plays into the resource (nui/public), from the game's own
// asset folder (SNC_ASSETS, default C:/PROJECTS/Smash&Clash/fable/assets: the website's root), so in game the
// page only talks to smashandclash.in through the SDK, for the games themselves:
//   kit/cards.json  the deck (values, colours, names), pointing at the local art
//   kit/kit.json    colours and every sound, pointing at the local files
//   kit/rules.txt   the rules
//   cards/          card faces, the card back, the logo
//   strike/         each character's strike drawing
//   audio/          one take of each music track and character line, every effect and call
// The art and audio are free to use in clients built for Smash&Clash, never to present as your own.
// The deck and the kit (which file is which) come from the SDK, once, at build time.
//   node tools/vendor-assets.mjs

import { copyFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SmashAndClash } from '@smashandclash/sdk';

const pub = fileURLToPath(new URL('../nui/public/', import.meta.url));
const SOURCE = process.env.SNC_ASSETS ?? 'C:/PROJECTS/Smash&Clash/fable/assets';
if (!existsSync(SOURCE)) throw new Error(`No asset folder at ${SOURCE}: set SNC_ASSETS to the game's assets folder.`);
for (const d of ['cards', 'strike', 'audio', 'kit']) rmSync(join(pub, d), { recursive: true, force: true });

const sc = new SmashAndClash({ client: 'fivem-build' });
const [cards, kit, rules] = await Promise.all([sc.cards(), sc.assets(), sc.rules()]);

const jobs = [];
/** Queue a file to copy and return the path the page loads it from. */
const local = (url, path) => {
  jobs.push([url, path]);
  return `./${path}`;
};
// one take of a list of takes; a single URL as it is
const one = (v, path) => (Array.isArray(v) ? (v.length ? [local(v[0], path)] : []) : typeof v === 'string' ? local(v, path) : v);
const ext = (u) => (u.match(/\.(\w+)(?:\?|$)/)?.[1] ?? 'mp3');

const deck = cards.map((c) => ({
  ...c,
  image: local(c.image, `cards/${c.id}.webp`),
  art: undefined,
  versus: undefined,
  animation: c.animation ? { ...c.animation, windup: undefined, strike: local(c.animation.strike, `strike/${c.id}.webp`) } : null,
}));

const a = kit.audio;
const audio = {
  music: Object.fromEntries(Object.entries(a.music).map(([k, v]) => [k, one(v, `audio/music/${k}.${ext(v[0])}`)])),
  sfx: Object.fromEntries(Object.entries(a.sfx).map(([k, v]) => [k, (Array.isArray(v) ? v : [v]).map((u, i) => local(u, `audio/sfx/${k}-${i + 1}.${ext(u)}`))])),
  announcer: Object.fromEntries(Object.entries(a.announcer).map(([k, v]) => [k, (Array.isArray(v) ? v : [v]).map((u, i) => local(u, `audio/announcer/${k}-${i + 1}.${ext(u)}`))])),
  howTo: {},
  voices: Object.fromEntries(
    Object.entries(a.voices).map(([id, lines]) => [
      id,
      Object.fromEntries(
        Object.entries(lines).map(([kind, v]) =>
          Array.isArray(v) || typeof v === 'string'
            ? [kind, one(v, `audio/voice/${id}/${kind}.mp3`)]
            : [kind, Object.fromEntries(Object.entries(v).map(([n, takes]) => [n, one(takes, `audio/voice/${id}/${kind}-${n}.mp3`)]))],
        ),
      ),
    ]),
  ),
};

const localKit = {
  version: kit.version,
  terms: kit.terms,
  brand: { logo: local(kit.brand.logo, 'cards/logo.svg') },
  card: { back: local(kit.card.back, 'cards/back.png'), aspect: kit.card.aspect, sides: kit.card.sides },
  colors: kit.colors,
  animation: kit.animation,
  audio,
};

let done = 0;
const missing = [];
for (const [url, path] of jobs) {
  // a site URL is a file in the asset folder: https://www.smashandclash.in/Cards-webp/01_Pengu.webp
  const from = join(SOURCE, decodeURIComponent(new URL(url).pathname));
  if (!existsSync(from)) {
    missing.push(url);
    continue;
  }
  const to = join(pub, path);
  mkdirSync(dirname(to), { recursive: true });
  copyFileSync(from, to);
  done++;
}
if (missing.length) console.warn(`not in the asset folder (${missing.length}):\n  ${missing.slice(0, 10).join('\n  ')}`);

mkdirSync(join(pub, 'kit'), { recursive: true });
writeFileSync(join(pub, 'kit/cards.json'), JSON.stringify(deck));
writeFileSync(join(pub, 'kit/kit.json'), JSON.stringify(localKit));
writeFileSync(join(pub, 'kit/rules.txt'), rules);
console.log(`saved ${done} files and the kit to nui/public`);
