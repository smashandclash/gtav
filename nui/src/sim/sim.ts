// The table without GTA (npm run dev): the resource's own client/board.lua runs in a Lua VM
// (wasmoon, Lua 5.4 like FiveM's lua54) and its textured polygons are drawn on a canvas through
// a perspective camera placed where the game's seat camera goes. What you see here is what the
// board draws in the world, so its layout and animations can be checked in a browser.

import { LuaFactory } from 'wasmoon';
import wasmUrl from 'wasmoon/dist/glue.wasm?url';
import boardLua from '../../../resource/smashandclash/client/board.lua?raw';
import { paintAtlas } from '../atlas-paint';
import { ATLAS, GLYPH } from '../atlas-spec';
import shimLua from './shim.lua?raw';

type Vec = [number, number, number];

const sub = (a: Vec, b: Vec): Vec => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (a: Vec, b: Vec): Vec => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a: Vec): Vec => {
  const l = Math.hypot(a[0], a[1], a[2]) || 1;
  return [a[0] / l, a[1] / l, a[2] / l];
};
const dot = (a: Vec, b: Vec) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

export interface Sim {
  view(table: string, view: unknown): void;
  move(table: string, steps: unknown[], view: unknown): void;
  pick(x: number, y: number): unknown;
  camera(mode?: string): string;
  cards(ids: number[]): void;
}

export async function createSim(canvas: HTMLCanvasElement): Promise<Sim> {
  const lua = await new LuaFactory(wasmUrl).createEngine();
  await lua.doString(boardLua.replace(/\nreturn Board\s*$/, '\n'));
  await lua.doString(shimLua);
  const g = canvas.getContext('2d')!;

  // the atlas, and tinted copies of its sprite strip
  const atlas = document.createElement('canvas');
  atlas.width = atlas.height = ATLAS;
  await paintAtlas(atlas);
  const tinted = new Map<string, HTMLCanvasElement>();
  const stripH = ATLAS - GLYPH.y;
  const tint = (r: number, gg: number, b: number) => {
    const key = `${r},${gg},${b}`;
    let c = tinted.get(key);
    if (!c) {
      c = document.createElement('canvas');
      c.width = ATLAS;
      c.height = stripH;
      const x = c.getContext('2d')!;
      x.drawImage(atlas, 0, GLYPH.y, ATLAS, stripH, 0, 0, ATLAS, stripH);
      x.globalCompositeOperation = 'multiply';
      x.fillStyle = `rgb(${r},${gg},${b})`;
      x.fillRect(0, 0, ATLAS, stripH);
      x.globalCompositeOperation = 'destination-in';
      x.drawImage(atlas, 0, GLYPH.y, ATLAS, stripH, 0, 0, ATLAS, stripH);
      tinted.set(key, c);
    }
    return c;
  };
  const fxImg = new Image();
  let fxSrc = '';

  let mode = 'seat';
  const H = (): number => lua.global.get('CARD_H') as number;
  let cam = { pos: [0, -1, 1] as Vec, at: [0, 0, 0] as Vec, fov: 50 };
  const place = () => {
    const h = H();
    const ex = lua.global.get('EY') as number;
    if (mode === 'top') cam = { pos: [0, -0.12, h * 7.5], at: [0, -0.02, 0], fov: 50 };
    else if (mode === 'first') cam = { pos: [0, -(ex + h * 1.6), 0.62], at: [0, -h * 0.4, 0], fov: 62 };
    else cam = { pos: [0, -(ex + h * 3.6), h * 4.6], at: [0, -h * 0.35, 0], fov: 50 };
  };
  place();

  // camera basis, shared with the Lua shim for picking and facing
  const basis = () => {
    const f = norm(sub(cam.at, cam.pos));
    const r = norm(cross(f, [0, 0, 1]));
    const u = cross(r, f);
    return { f, r, u };
  };
  const project = (p: Vec, w: number, h: number): [number, number, number] | null => {
    const { f, r, u } = basis();
    const d = sub(p, cam.pos);
    const z = dot(d, f);
    if (z < 0.02) return null;
    const k = 1 / Math.tan(((cam.fov / 2) * Math.PI) / 180);
    const sx = 0.5 + (dot(d, r) * k) / z / (w / h) / 2;
    const sy = 0.5 - (dot(d, u) * k) / z / 2;
    return [sx, sy, z];
  };

  const frame = lua.global.get('frame') as (now: number, cx: number, cy: number, cz: number) => number[];
  const setCam = lua.global.get('setCamera') as (...a: number[]) => void;

  const draw = () => {
    const w = (canvas.width = canvas.clientWidth * devicePixelRatio);
    const h = (canvas.height = canvas.clientHeight * devicePixelRatio);
    const sky = g.createLinearGradient(0, 0, 0, h);
    sky.addColorStop(0, '#9fc3e0');
    sky.addColorStop(0.45, '#d9c9a8');
    sky.addColorStop(1, '#6b5a45');
    g.fillStyle = sky;
    g.fillRect(0, 0, w, h);
    const { f, r, u } = basis();
    setCam(cam.pos[0], cam.pos[1], cam.pos[2], f[0], f[1], f[2], r[0], r[1], r[2], u[0], u[1], u[2], cam.fov, w / h);
    // the table top
    const ext = (lua.global.get('TABLE_EXT') as number) || 0.6;
    poly([[-ext, -ext, -0.002], [ext, -ext, -0.002], [ext, ext, -0.002]], null, '#7a5232');
    poly([[-ext, -ext, -0.002], [ext, ext, -0.002], [-ext, ext, -0.002]], null, '#7a5232');
    const buf = frame(performance.now(), cam.pos[0], cam.pos[1], cam.pos[2]);
    // each poly: 9 coords, r g b a, 6 uv, texture (0 atlas, 1 fx), fx source index
    for (let i = 0; i + 20 <= buf.length; i += 21) {
      const pts: Vec[] = [
        [buf[i], buf[i + 1], buf[i + 2]],
        [buf[i + 3], buf[i + 4], buf[i + 5]],
        [buf[i + 6], buf[i + 7], buf[i + 8]],
      ];
      const [cr, cg, cb, ca] = [buf[i + 9], buf[i + 10], buf[i + 11], buf[i + 12]];
      const uv = [buf[i + 13], buf[i + 14], buf[i + 15], buf[i + 16], buf[i + 17], buf[i + 18]];
      const tex = buf[i + 19];
      if (tex === 1) {
        const src = lua.global.get('FX_SRC') as string;
        if (src && src !== fxSrc) {
          fxSrc = src;
          fxImg.src = src;
        }
      }
      textured(pts, uv, tex, [cr, cg, cb, ca]);
    }
    requestAnimationFrame(draw);

    function poly(p: Vec[], _uv: null, fill: string) {
      const s = p.map((q) => project(q, w, h));
      if (s.some((q) => !q)) return;
      g.beginPath();
      g.moveTo(s[0]![0] * w, s[0]![1] * h);
      g.lineTo(s[1]![0] * w, s[1]![1] * h);
      g.lineTo(s[2]![0] * w, s[2]![1] * h);
      g.closePath();
      g.fillStyle = fill;
      g.fill();
    }

    function textured(p: Vec[], uv: number[], tex: number, c: number[]) {
      const s = p.map((q) => project(q, w, h));
      if (s.some((q) => !q)) return;
      const [x0, y0, x1, y1, x2, y2] = [s[0]![0] * w, s[0]![1] * h, s[1]![0] * w, s[1]![1] * h, s[2]![0] * w, s[2]![1] * h];
      // the game culls a triangle seen from behind: so does the preview
      if ((x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0) > 0) return;
      let img: CanvasImageSource = atlas;
      let tw = ATLAS;
      let th = ATLAS;
      let vOff = 0;
      if (tex === 1) {
        if (!fxImg.complete || !fxImg.naturalWidth) return;
        img = fxImg;
        tw = fxImg.naturalWidth;
        th = fxImg.naturalHeight;
      } else if (uv[1] * ATLAS >= GLYPH.y - 1 && (c[0] < 250 || c[1] < 250 || c[2] < 250)) {
        img = tint(c[0], c[1], c[2]);
        vOff = GLYPH.y;
      }
      const u0 = uv[0] * tw, v0 = uv[1] * th - vOff, u1 = uv[2] * tw, v1 = uv[3] * th - vOff, u2 = uv[4] * tw, v2 = uv[5] * th - vOff;
      const det = (u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0);
      if (Math.abs(det) < 1e-6) return;
      const a = ((x1 - x0) * (v2 - v0) - (x2 - x0) * (v1 - v0)) / det;
      const b = ((y1 - y0) * (v2 - v0) - (y2 - y0) * (v1 - v0)) / det;
      const cc = ((x2 - x0) * (u1 - u0) - (x1 - x0) * (u2 - u0)) / det;
      const d = ((y2 - y0) * (u1 - u0) - (y1 - y0) * (u2 - u0)) / det;
      const e = x0 - a * u0 - cc * v0;
      const ff = y0 - b * u0 - d * v0;
      g.save();
      g.beginPath();
      // grow the clip a hair so neighbouring triangles meet without a seam
      const mx = (x0 + x1 + x2) / 3, my = (y0 + y1 + y2) / 3;
      const grow = (x: number, y: number): [number, number] => [x + Math.sign(x - mx) * 0.6, y + Math.sign(y - my) * 0.6];
      g.moveTo(...grow(x0, y0));
      g.lineTo(...grow(x1, y1));
      g.lineTo(...grow(x2, y2));
      g.closePath();
      g.clip();
      g.globalAlpha = Math.max(0, Math.min(1, c[3] / 255));
      g.setTransform(a, b, cc, d, e, ff);
      g.drawImage(img, 0, 0);
      g.restore();
    }
  };
  requestAnimationFrame(draw);

  const call = (name: string, ...args: unknown[]) => (lua.global.get(name) as (...a: unknown[]) => unknown)(...args);
  return {
    view: (table, view) => call('setView', table, view ?? null),
    move: (table, steps, view) => call('animate', table, steps, view ?? null, performance.now()),
    pick: (x, y) => call('pick', x, y) ?? false,
    camera: (m) => {
      mode = m ?? (mode === 'seat' ? 'first' : mode === 'first' ? 'top' : 'seat');
      place();
      return mode;
    },
    cards: (ids) => call('setCards', ids),
  };
}
