-- The preview's stand-in for client/render.lua and client/tables.lua: the same atlas numbers,
-- but polygons go into a flat buffer the page draws, and projection uses the preview's camera.

local ATLAS = 2048
local CARD = { w = 224, h = 306, sx = 227, sy = 310, cols = 9 }
local GLYPH = { size = 128, stride = 130, y = 1880 }
local GLYPHS = { tile = 0, rim = 1, knight = 2, bishop = 3, rook = 4, queen = 5, plus1 = 6, plus2 = 7, ice = 8, glow = 9, zone = 10, shadow = 11, dot = 12 }


-- the board's wood and an empty tile sit in two free card slots; the edge labels beside the strip
local BOARD_SLOTS = { slab = 52, empty = 53 }
local LABEL = { size = 64, stride = 70, x = 1700, y = 1880, cols = 5 }
local LABELS = { A = 0, B = 1, C = 2, D = 3, E = 4, ['1'] = 5, ['2'] = 6, ['3'] = 7 }

local slots, backSlot = {}, 51
local current = 0
local buf, n = {}, 0
local camp = { 0, 0, 0 }
local camf, camr, camu = { 0, 1, 0 }, { 1, 0, 0 }, { 0, 0, 1 }
local fov, aspect = 50, 16 / 9
FX_SRC = ''

local function uv(x, y, w, h)
  return { (x + 0.5) / ATLAS, (y + 0.5) / ATLAS, (x + w - 0.5) / ATLAS, (y + h - 0.5) / ATLAS }
end

-- FiveM's json.decode, for the preview: JSON null becomes nil, arrays count from 1.
json = {}
function json.decode(text)
  local i = 1
  local function ws() i = text:find('[^ \t\r\n]', i) or #text + 1 end
  local value
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = text:sub(j, j)
      if c == '"' then break end
      if c == '\\' then
        local e = text:sub(j + 1, j + 1)
        if e == 'u' then
          local code = tonumber(text:sub(j + 2, j + 5), 16)
          out[#out + 1] = utf8.char(code)
          j = j + 6
        else
          local map = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
          out[#out + 1] = map[e] or e
          j = j + 2
        end
      else
        out[#out + 1] = c
        j = j + 1
      end
    end
    i = j + 1
    return table.concat(out)
  end
  function value()
    ws()
    local c = text:sub(i, i)
    if c == '{' then
      local t = {}
      i = i + 1
      ws()
      if text:sub(i, i) == '}' then i = i + 1 return t end
      while true do
        ws()
        local k = str()
        ws()
        i = i + 1 -- :
        t[k] = value()
        ws()
        local d = text:sub(i, i)
        i = i + 1
        if d == '}' then return t end
      end
    elseif c == '[' then
      local t, n = {}, 0
      i = i + 1
      ws()
      if text:sub(i, i) == ']' then i = i + 1 return t end
      while true do
        n = n + 1
        t[n] = value()
        ws()
        local d = text:sub(i, i)
        i = i + 1
        if d == ']' then return t end
      end
    elseif c == '"' then
      return str()
    elseif text:sub(i, i + 3) == 'true' then i = i + 4 return true
    elseif text:sub(i, i + 4) == 'false' then i = i + 5 return false
    elseif text:sub(i, i + 3) == 'null' then i = i + 4 return nil
    else
      local num = text:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
      i = i + #num
      return tonumber(num)
    end
  end
  return value()
end

R = {}

function R.card(id)
  current = 0
  local slot = id == 'back' and backSlot or (slots[id] or backSlot)
  return uv((slot % CARD.cols) * CARD.sx, (slot // CARD.cols) * CARD.sy, CARD.w, CARD.h)
end

function R.board(name)
  current = 0
  local slot = BOARD_SLOTS[name]
  return uv((slot % CARD.cols) * CARD.sx, (slot // CARD.cols) * CARD.sy, CARD.w, CARD.h)
end

function R.label(ch)
  current = 0
  local k = LABELS[ch] or 0
  return uv(LABEL.x + (k % LABEL.cols) * LABEL.stride, LABEL.y + (k // LABEL.cols) * LABEL.stride, LABEL.size, LABEL.size)
end

function R.glyph(name)
  current = 0
  return uv(GLYPHS[name] * GLYPH.stride, GLYPH.y, GLYPH.size, GLYPH.size)
end

function R.fx(step)
  current = 1
  FX_SRC = step.art or FX_SRC
  return { 0, 0, 1, 1 }
end

function R.poly(p1, p2, p3, r, g, b, a, u1, v1, u2, v2, u3, v3)
  local t = { p1[1], p1[2], p1[3], p2[1], p2[2], p2[3], p3[1], p3[2], p3[3], r, g, b, a, u1, v1, u2, v2, u3, v3, current, 0 }
  for i = 1, 21 do buf[n + i] = t[i] end
  n = n + 21
end

TEXTS = {}
function R.text(x, y, z, text, rgb, a, scale)
  TEXTS[#TEXTS + 1] = x .. '|' .. y .. '|' .. z .. '|' .. rgb[1] .. '|' .. rgb[2] .. '|' .. rgb[3] .. '|' .. (a or 255) .. '|' .. (scale or 0.5) .. '|' .. text
end

function R.camera()
  return camp[1], camp[2], camp[3]
end

function R.project(x, y, z)
  local d = { x - camp[1], y - camp[2], z - camp[3] }
  local zz = d[1] * camf[1] + d[2] * camf[2] + d[3] * camf[3]
  if zz < 0.02 then return false end
  local k = 1 / math.tan(math.rad(fov / 2))
  local sx = 0.5 + (d[1] * camr[1] + d[2] * camr[2] + d[3] * camr[3]) * k / zz / aspect / 2
  local sy = 0.5 - (d[1] * camu[1] + d[2] * camu[2] + d[3] * camu[3]) * k / zz / 2
  return true, sx, sy
end

function setCamera(px, py, pz, fx, fy, fz, rx, ry, rz, ux, uy, uz, f, a)
  camp, camf, camr, camu, fov, aspect = { px, py, pz }, { fx, fy, fz }, { rx, ry, rz }, { ux, uy, uz }, f, a
end

-- one table at the origin, chair A towards -y, sized like a 1.1 m table
local TABLE_W, TABLE_D = 1.1, 1.1
CARD_H = math.min(TABLE_W * 0.9 / (5 * 0.7333 + 0.5), TABLE_D * 0.92 / 4.9)
TABLE_EXT = TABLE_W / 2
local board = Board.new({ x = 0, y = 0, z = 0 }, 0, CARD_H)
local _, ey = board:extents()
EY = ey

function setCards(text)
  local ids = json.decode(text)
  local list = {}
  for i = 1, #ids do list[i] = ids[i] end
  table.sort(list)
  slots = {}
  for i, id in ipairs(list) do slots[id] = i - 1 end
  backSlot = #list
end

function setView(_, text)
  board:setView(json.decode(text))
end

function animate(_, steps, view, now)
  steps, view = json.decode(steps), json.decode(view)
  if view then board:setView(view) end
  board:animate(steps, now)
end

function pick(x, y)
  local hit = board:pick(R, x, y)
  board.hover = hit
  return hit
end

-- a seated player at chair A, as tables.lua reads one from a ped: eyes over the edge, the fan
-- held in both hands in front of the chest
HEAD = { 0, -(ey + 0.55), 0.48 }
HEAD_Y, HEAD_Z = HEAD[2], HEAD[3]
local hands = {
  A = { anchor = { 0, -(ey + 0.27), 0.15 }, head = { HEAD[1], HEAD[2], HEAD[3] + 0.04 } },
  -- the character across the table, holding their cards the same way
  B = { anchor = { 0, ey + 0.27, 0.15 }, head = { 0, ey + 0.55, 0.52 } },
}

function frame(now)
  buf, n = {}, 0
  TEXTS = {}
  board:setHands(hands)
  board:draw(R, now)
  TEXT_LINES = table.concat(TEXTS, '\n')
  return buf
end
