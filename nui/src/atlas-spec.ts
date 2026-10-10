// The texture atlas the 3D table draws from: one 2048 x 2048 DUI page holding every card face, the
// card back and the board's sprites. client/render.lua (and the preview's sim/shim.lua) carry the
// same numbers.

export const ATLAS = 2048;
export const CARD = { w: 224, h: 306, strideX: 227, strideY: 310, cols: 9 };
export const GLYPH = { size: 128, stride: 130, y: 1880 };

/** The board's sprites, by slot along the bottom strip. White where the table tints them. */
export const GLYPHS = ['tile', 'rim', 'knight', 'bishop', 'rook', 'queen', 'plus1', 'plus2', 'ice', 'glow', 'zone', 'shadow', 'dot'] as const;

/** Two free card slots hold the board's wood (the slab) and an empty tile, as on smashandclash.in. */
export const SLAB_SLOT = 52;
export const EMPTY_SLOT = 53;

/** The letters and numbers printed round the board's edge, 64 px each beside the sprite strip. */
export const LABELS = ['A', 'B', 'C', 'D', 'E', '1', '2', '3'] as const;
export const LABEL = { size: 64, stride: 70, x: 1700, y: 1880, cols: 5 };

/** A card's slot: its place among the deck sorted by id; the card back follows the deck. */
export function cardSlots(ids: number[]): Map<number, number> {
  return new Map([...ids].sort((a, b) => a - b).map((id, i) => [id, i]));
}

export function slotRect(slot: number): { x: number; y: number; w: number; h: number } {
  return { x: (slot % CARD.cols) * CARD.strideX, y: Math.floor(slot / CARD.cols) * CARD.strideY, w: CARD.w, h: CARD.h };
}
