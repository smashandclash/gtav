// Paints the atlas the 3D table samples (see atlas-spec.ts): the real card faces from the deck the
// resource ships, the real card back, and white sprites the table tints (tiles, owner rims, chess
// pieces, power badges, ice, glow).

import { loadDeck } from './kit';
import './fonts.css';
import { art } from './art';
import { ATLAS, EMPTY_SLOT, GLYPH, GLYPHS, LABEL, LABELS, SLAB_SLOT, cardSlots, slotRect } from './atlas-spec';

let g: CanvasRenderingContext2D;

function rounded(x: number, y: number, w: number, h: number, r: number): void {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

function load(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = src;
  });
}

async function card(slot: number, src: string): Promise<void> {
  const img = await load(src);
  if (!img) return;
  const r = slotRect(slot);
  g.save();
  rounded(r.x, r.y, r.w, r.h, 16);
  g.clip();
  g.drawImage(img, r.x, r.y, r.w, r.h);
  g.restore();
}

function glyphs(): void {
  const s = GLYPH.size;
  const at = (name: (typeof GLYPHS)[number]) => ({ x: GLYPHS.indexOf(name) * GLYPH.stride, y: GLYPH.y });
  const box = (name: (typeof GLYPHS)[number], paint: (x: number, y: number) => void) => {
    const p = at(name);
    g.save();
    paint(p.x, p.y);
    g.restore();
  };
  box('tile', (x, y) => {
    g.fillStyle = '#fff';
    rounded(x + 4, y + 4, s - 8, s - 8, 18);
    g.fill();
  });
  box('rim', (x, y) => {
    g.strokeStyle = '#fff';
    g.lineWidth = 12;
    rounded(x + 8, y + 8, s - 16, s - 16, 20);
    g.stroke();
  });
  for (const [name, ch] of [
    ['knight', '♞'],
    ['bishop', '♝'],
    ['rook', '♜'],
    ['queen', '♛'],
  ] as const) {
    box(name, (x, y) => {
      g.font = `${s * 0.78}px "Segoe UI Symbol", "DejaVu Sans", serif`;
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillStyle = 'rgba(6,16,47,0.45)';
      g.fillText(ch, x + s / 2 + 3, y + s / 2 + 7);
      g.fillStyle = '#fff';
      g.fillText(ch, x + s / 2, y + s / 2 + 4);
    });
  }
  for (const [name, text] of [
    ['plus1', '+1'],
    ['plus2', '+2'],
  ] as const) {
    box(name, (x, y) => {
      g.fillStyle = '#fff';
      g.beginPath();
      g.arc(x + s / 2, y + s / 2, s / 2 - 6, 0, Math.PI * 2);
      g.fill();
      g.font = `${s * 0.46}px "Luckiest Guy", "Arial Black", sans-serif`;
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillStyle = '#0d1a4a';
      g.fillText(text, x + s / 2, y + s / 2 + 3);
    });
  }
  box('ice', (x, y) => {
    const grad = g.createLinearGradient(x, y, x + s, y + s);
    grad.addColorStop(0, 'rgba(255,255,255,0.75)');
    grad.addColorStop(0.45, 'rgba(170,225,255,0.35)');
    grad.addColorStop(1, 'rgba(255,255,255,0.7)');
    g.fillStyle = grad;
    rounded(x + 2, y + 2, s - 4, s - 4, 14);
    g.fill();
    g.strokeStyle = 'rgba(220,245,255,0.95)';
    g.lineWidth = 6;
    g.stroke();
  });
  box('glow', (x, y) => {
    const grad = g.createRadialGradient(x + s / 2, y + s / 2, 4, x + s / 2, y + s / 2, s / 2);
    grad.addColorStop(0, 'rgba(255,255,255,1)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(x, y, s, s);
  });
  box('zone', (x, y) => {
    g.strokeStyle = '#fff';
    g.lineWidth = 6;
    g.setLineDash([14, 10]);
    rounded(x + 18, y + 18, s - 36, s - 36, 14);
    g.stroke();
  });
  box('shadow', (x, y) => {
    const grad = g.createRadialGradient(x + s / 2, y + s / 2, 8, x + s / 2, y + s / 2, s / 2);
    grad.addColorStop(0, 'rgba(0,0,0,0.6)');
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.fillRect(x, y, s, s);
  });
  box('dot', (x, y) => {
    g.fillStyle = '#fff';
    g.beginPath();
    g.arc(x + s / 2, y + s / 2, s / 2 - 4, 0, Math.PI * 2);
    g.fill();
  });
}

/** The board itself, as the website draws it: cream wood, cream tiles with the logo pressed in. */
async function board(): Promise<void> {
  const slab = slotRect(SLAB_SLOT);
  g.save();
  rounded(slab.x, slab.y, slab.w, slab.h, 18);
  g.clip();
  g.fillStyle = '#eadbbd';
  g.fillRect(slab.x, slab.y, slab.w, slab.h);
  // a soft grain
  for (let i = 0; i < 26; i++) {
    const y = slab.y + (i + 0.5) * (slab.h / 26) + Math.sin(i * 1.7) * 2;
    g.strokeStyle = i % 3 ? 'rgba(160,130,85,0.07)' : 'rgba(255,255,255,0.18)';
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(slab.x, y);
    g.bezierCurveTo(slab.x + slab.w * 0.3, y + 3, slab.x + slab.w * 0.7, y - 3, slab.x + slab.w, y + 1);
    g.stroke();
  }
  g.restore();

  const e = slotRect(EMPTY_SLOT);
  g.save();
  rounded(e.x + 3, e.y + 3, e.w - 6, e.h - 6, 18);
  g.fillStyle = '#efe3c9';
  g.fill();
  g.lineWidth = 5;
  g.strokeStyle = '#d8c59f';
  g.stroke();
  g.clip();
  const shade = g.createLinearGradient(0, e.y, 0, e.y + e.h);
  shade.addColorStop(0, 'rgba(120,95,55,0.16)');
  shade.addColorStop(0.18, 'rgba(120,95,55,0)');
  g.fillStyle = shade;
  g.fillRect(e.x, e.y, e.w, e.h);
  const logo = await load(art.logo);
  if (logo) {
    const w = e.w * 0.66;
    const hgt = (w * logo.naturalHeight) / (logo.naturalWidth || 1);
    g.globalAlpha = 0.22;
    g.filter = 'grayscale(1) sepia(0.7) brightness(0.85)';
    g.drawImage(logo, e.x + (e.w - w) / 2, e.y + (e.h - hgt) / 2, w, hgt);
    g.filter = 'none';
    g.globalAlpha = 1;
  }
  g.restore();

  g.font = `${LABEL.size * 0.82}px "Luckiest Guy", "Arial Black", sans-serif`;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillStyle = '#4a3b26';
  LABELS.forEach((t, k) => {
    const x = LABEL.x + (k % LABEL.cols) * LABEL.stride;
    const y = LABEL.y + Math.floor(k / LABEL.cols) * LABEL.stride;
    g.fillText(t, x + LABEL.size / 2, y + LABEL.size / 2 + 3);
  });
}

/** Paint the whole atlas onto a 2048 x 2048 canvas. */
export async function paintAtlas(canvas: HTMLCanvasElement): Promise<void> {
  g = canvas.getContext('2d')!;
  g.clearRect(0, 0, ATLAS, ATLAS);
  await document.fonts.load(`40px "Luckiest Guy"`).catch(() => {});
  glyphs();
  await board();
  const cards = await loadDeck();
  const slots = cardSlots(cards.map((c) => c.id));
  // the art ships with the resource (tools/vendor-cards.mjs): one join, no burst of image requests
  for (let i = 0; i < cards.length; i += 8) await Promise.all(cards.slice(i, i + 8).map((c) => card(slots.get(c.id)!, art.card(c.id))));
  await card(cards.length, art.back);
}

