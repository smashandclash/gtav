// The card art and logo, shipped inside the resource (tools/vendor-cards.mjs copies them into
// nui/public/cards), so the game loads them from the server, never in a burst from the website.

export const art = {
  card: (id: number): string => `./cards/${id}.webp`,
  back: './cards/back.png',
  logo: './cards/logo.svg',
};
