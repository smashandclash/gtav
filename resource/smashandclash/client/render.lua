-- The renderer the board draws through, on GTA's natives: textured polygons in the world from
-- the atlas (one DUI page with every card face, the back and the board's sprites), the
-- strike drawing (a second DUI page), screen projection and the camera position.

Render = {}

local ATLAS, FX_SIZE = 2048, 512
local CARD = { w = 224, h = 306, sx = 227, sy = 310, cols = 9 }
local GLYPH = { size = 128, stride = 130, y = 1880 }
local GLYPHS = { tile = 0, rim = 1, knight = 2, bishop = 3, rook = 4, queen = 5, plus1 = 6, plus2 = 7, ice = 8, glow = 9, zone = 10, shadow = 11, dot = 12 }


-- the board's wood and an empty tile sit in two free card slots; the edge labels beside the strip
local BOARD_SLOTS = { slab = 52, empty = 53 }
local LABEL = { size = 64, stride = 70, x = 1700, y = 1880, cols = 5 }
local LABELS = { A = 0, B = 1, C = 2, D = 3, E = 4, ['1'] = 5, ['2'] = 6, ['3'] = 7 }

local TXD = 'snc_txd'
local slots = {} -- card id -> atlas slot
local backSlot = 51
local atlasDui, fxDui
local fxSrc = nil
local ready = false

local function uv(x, y, w, h, size)
  size = size or ATLAS
  -- half a texel in, so neighbours never bleed into an edge
  return { (x + 0.5) / size, (y + 0.5) / size, (x + w - 0.5) / size, (y + h - 0.5) / size }
end

local cardUV = {}
local glyphUV = {}
for name, i in pairs(GLYPHS) do
  glyphUV[name] = uv(i * GLYPH.stride, GLYPH.y, GLYPH.size, GLYPH.size)
end

local function slotUV(slot)
  if not cardUV[slot] then
    cardUV[slot] = uv((slot % CARD.cols) * CARD.sx, (slot // CARD.cols) * CARD.sy, CARD.w, CARD.h)
  end
  return cardUV[slot]
end

--- The deck's ids in atlas order (sorted, as the atlas page lays them out).
function Render.setCards(ids)
  table.sort(ids)
  slots = {}
  for i, id in ipairs(ids) do slots[id] = i - 1 end
  backSlot = #ids
end

function Render.start(resource)
  if atlasDui then return end
  local base = ('nui://%s/html/'):format(resource)
  atlasDui = CreateDui(base .. 'atlas.html', ATLAS, ATLAS)
  fxDui = CreateDui(base .. 'fx.html', FX_SIZE, FX_SIZE)
  CreateThread(function()
    local t0 = GetGameTimer()
    while not (IsDuiAvailable(atlasDui) and IsDuiAvailable(fxDui)) do
      if GetGameTimer() - t0 > 20000 then
        print('^1[smashandclash] the table textures did not load (DUI unavailable)^0')
        return
      end
      Wait(100)
    end
    local txd = CreateRuntimeTxd(TXD)
    CreateRuntimeTextureFromDuiHandle(txd, 'atlas', GetDuiHandle(atlasDui))
    CreateRuntimeTextureFromDuiHandle(txd, 'fx', GetDuiHandle(fxDui))
    ready = true
  end)
end

function Render.stop()
  if atlasDui then DestroyDui(atlasDui) end
  if fxDui then DestroyDui(fxDui) end
  atlasDui, fxDui, ready = nil, nil, false
end

function Render.ready()
  return ready
end

-- the texture each draw uses: 'atlas' unless a sprite says otherwise
local current = 'atlas'

function Render.card(id)
  current = 'atlas'
  if id == 'back' then return slotUV(backSlot) end
  return slotUV(slots[id] or backSlot)
end

function Render.board(name)
  current = 'atlas'
  return slotUV(BOARD_SLOTS[name])
end

function Render.label(ch)
  current = 'atlas'
  local k = LABELS[ch] or 0
  return uv(LABEL.x + (k % LABEL.cols) * LABEL.stride, LABEL.y + (k // LABEL.cols) * LABEL.stride, LABEL.size, LABEL.size)
end

function Render.glyph(name)
  current = 'atlas'
  return glyphUV[name]
end

--- The strike drawing for an animation step: points the fx page at its art.
function Render.fx(step)
  if step.art and step.art ~= fxSrc and fxDui then
    fxSrc = step.art
    SendDuiMessage(fxDui, json.encode({ type = 'art', src = step.art }))
  end
  current = 'fx'
  return { 0, 0, 1, 1 }
end

function Render.poly(p1, p2, p3, r, g, b, a, u1, v1, u2, v2, u3, v3)
  if not ready then return end
  DrawTexturedPoly(p1[1], p1[2], p1[3], p2[1], p2[2], p2[3], p3[1], p3[2], p3[3], r, g, b, a, TXD, current, u1, v1, 1.0, u2, v2, 1.0, u3, v3, 1.0)
end

function Render.project(x, y, z)
  local ok, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
  return ok, sx, sy
end

function Render.camera()
  local c = GetFinalRenderedCamCoord()
  return c.x, c.y, c.z
end

return Render
