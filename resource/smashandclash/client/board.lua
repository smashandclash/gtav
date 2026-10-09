-- The Smash&Clash board as a real object on a table: tiles, cards, both hands and every
-- animation, drawn each frame as textured polygons in the world (cards are quads that drop,
-- flip, hop and crumble), so anyone nearby sees the game from wherever they stand.
--
-- Nothing here calls a native directly: the renderer `R` (client/render.lua in the game, a
-- recorder in tools/sim) draws and projects, so the board can be checked outside GTA.

Board = {}
Board.__index = Board

local COLS = 'ABCDE'
local PI = math.pi
local PIECE = { KNIGHT = 'knight', BISHOP = 'bishop', ROOK = 'rook', QUEEN = 'queen', knight = 'knight', bishop = 'bishop', rook = 'rook', queen = 'queen' }
local OVERRUN = { B2 = true, C2 = true, D2 = true }

-- Arena Pop: you are blue, them orange; at a table seen by everyone, chair A blue, chair B orange.
local BLUE = { 33, 115, 232 }
local ORANGE = { 244, 88, 31 }
local MINT = { 139, 247, 207 }
local SUN = { 255, 194, 26 }
local NAVY = { 13, 26, 74 }

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function easeOut(p) return 1 - (1 - p) ^ 3 end
local function easeInOut(p) return p < 0.5 and 4 * p * p * p or 1 - (-2 * p + 2) ^ 3 / 2 end
local function backOut(p)
  local c1, c3 = 1.70158, 2.70158
  return 1 + c3 * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
end

function Board.cellRC(cell)
  return tonumber(cell:sub(2, 2)) - 1, COLS:find(cell:sub(1, 1), 1, true) - 1
end

function Board.cellName(r, c)
  return COLS:sub(c + 1, c + 1) .. tostring(r + 1)
end

--- A board on the table whose top centre is `origin` ({x, y, z}), turned to `heading` degrees
--- (chair A at the table's back edge, chair B at its front), with cards `cardH` metres tall.
function Board.new(origin, heading, cardH)
  local self = setmetatable({}, Board)
  self.origin = origin
  self.heading = heading
  self.H = cardH
  self.W = cardH * 0.7333
  self.G = cardH * 0.08
  self.view = nil
  self.anims = {}
  self.hover = nil
  local h = math.rad(heading)
  -- local x runs to chair A's right, local y from chair A towards chair B
  self.ax = { math.cos(h), math.sin(h) }
  self.ay = { -math.sin(h), math.cos(h) }
  return self
end

--- The table now (see nui/src/view.ts). Animations already running keep playing over it.
function Board:setView(view)
  self.view = view
end

--- A move's animation steps, starting now (`now` in ms). Steps: { at, dur, kind, ... }.
function Board:animate(steps, now)
  for _, s in ipairs(steps or {}) do
    s.start = now + (s.at or 0)
    self.anims[#self.anims + 1] = s
  end
end

function Board:busy(now)
  for _, a in ipairs(self.anims) do
    if now < a.start + a.dur then return true end
  end
  return false
end

--- Local table coordinates (metres; z up from the table top) to the world.
function Board:world(x, y, z)
  local o = self.origin
  return o.x + self.ax[1] * x + self.ay[1] * y, o.y + self.ax[2] * x + self.ay[2] * y, o.z + z
end

--- Where a cell sits, in table coordinates, for the current orientation.
function Board:cellXY(cell, spin)
  local r, c = Board.cellRC(cell)
  local x = (c - 2) * (self.W + self.G)
  local y = (r - 1) * (self.H + self.G)
  if self.view and self.view.flip then x, y = -x, -y end
  if spin and spin ~= 0 then
    local cs, sn = math.cos(spin), math.sin(spin)
    x, y = x * cs - y * sn, x * sn + y * cs
  end
  return x, y
end

--- The half extents of the board's mat.
function Board:extents()
  return 2.5 * self.W + 2 * self.G + self.G * 1.5, 1.5 * self.H + self.G + self.G * 1.5
end

-------------------------------------------------------------------------------------------
-- drawing

-- A flat or standing quad: centre (x, y, z) in table coordinates, half sizes hw, hh, turned
-- `yaw` in the table plane, rolled `roll` about its own up axis (a flip), pitched `pitch` up
-- from the table (a card standing in a hand). Returns its four world corners: top-left,
-- top-right, bottom-right, bottom-left, and its normal.
function Board:quad(x, y, z, hw, hh, yaw, roll, pitch)
  yaw, roll, pitch = yaw or 0, roll or 0, pitch or 0
  local cr, sr = math.cos(roll), math.sin(roll)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local function corner(lx, ly)
    -- roll about the card's vertical axis, then pitch about its horizontal one
    local px, pz = lx * cr, lx * sr
    local py = ly
    local qy, qz = py * cp - pz * sp, py * sp + pz * cp
    local wx, wy = px * cy - qy * sy, px * sy + qy * cy
    return { self:world(x + wx, y + wy, z + qz) }
  end
  -- the normal: the quad's local +z, through the same turns
  local nx, nz = -sr, cr
  local ny = 0
  local my, mz = ny * cp - nz * sp, ny * sp + nz * cp
  local wnx, wny = nx * cy - my * sy, nx * sy + my * cy
  local h = math.rad(self.heading)
  local n = { wnx * math.cos(h) - wny * math.sin(h), wnx * math.sin(h) + wny * math.cos(h), mz }
  return { corner(-hw, hh), corner(hw, hh), corner(hw, -hh), corner(-hw, -hh) }, n
end

local function faces(R, corners, n)
  local cx, cy, cz = R.camera()
  local c = corners[1]
  return (cx - c[1]) * n[1] + (cy - c[2]) * n[2] + (cz - c[3]) * n[3] >= 0
end

-- One sprite on a quad, both windings (so it shows whichever way the engine culls).
local function sprite(R, corners, uv, rgb, a, mirror)
  local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
  if mirror then u0, u1 = u1, u0 end
  local p1, p2, p3, p4 = corners[1], corners[2], corners[3], corners[4]
  local r, g, b = rgb[1], rgb[2], rgb[3]
  R.poly(p1, p2, p3, r, g, b, a, u0, v0, u1, v0, u1, v1)
  R.poly(p1, p3, p4, r, g, b, a, u0, v0, u1, v1, u0, v1)
  R.poly(p3, p2, p1, r, g, b, a, u1, v1, u1, v0, u0, v0)
  R.poly(p4, p3, p1, r, g, b, a, u0, v1, u1, v1, u0, v0)
end

local WHITE = { 255, 255, 255 }

--- A card: its face (or `back` = true for a hidden card) on the side the camera sees.
function Board:card(R, id, x, y, z, yaw, opts)
  opts = opts or {}
  local s = opts.scale or 1
  local hw, hh = self.W / 2 * s, self.H / 2 * s
  local corners, n = self:quad(x, y, z, hw, hh, yaw, opts.roll, opts.pitch)
  local front = faces(R, corners, n)
  local alpha = opts.alpha or 255
  local tint = opts.frozen and { 200, 235, 255 } or WHITE
  if opts.rim and not opts.pitch then
    -- the owner's colour around the card, and a soft shadow under it
    local sc = self:quad(x + self.H * 0.03, y - self.H * 0.04, math.max(0.001, z - 0.004 - (opts.lift or 0)), hw * 1.18, hh * 1.14, yaw)
    sprite(R, sc, R.glyph('shadow'), WHITE, math.floor(150 * alpha / 255))
    local rc = self:quad(x, y, z - 0.0015, hw * 1.12, hh * 1.09, yaw, opts.roll, opts.pitch)
    sprite(R, rc, R.glyph('tile'), opts.rim, alpha)
  end
  if opts.back or not front then
    sprite(R, corners, R.card('back'), WHITE, alpha, not front)
  else
    sprite(R, corners, R.card(id), tint, alpha)
  end
  if opts.frozen and front and not opts.back then
    sprite(R, self:quad(x, y, z + 0.0008, hw, hh, yaw, opts.roll, opts.pitch), R.glyph('ice'), WHITE, math.floor(170 * alpha / 255))
  end
  return corners
end

local function ownerColour(owner)
  return owner == 'A' and BLUE or ORANGE
end

-- The yaw that turns a card to face its owner: chair A's cards read from chair A's side.
function Board:ownerYaw(owner)
  local yaw = owner == 'A' and 0 or PI
  if self.view and self.view.flip then yaw = yaw + PI end
  return yaw
end

local function find(list, pred)
  for _, v in ipairs(list or {}) do
    if pred(v) then return v end
  end
end

--- Draw the whole table. `now` is the game timer (ms).
function Board:draw(R, now)
  local v = self.view
  -- drop finished animations
  local live = {}
  for _, a in ipairs(self.anims) do
    if now < a.start + a.dur + 50 then live[#live + 1] = a end
  end
  self.anims = live
  local spin = 0
  local bf = find(self.anims, function(a) return a.kind == 'boardflip' and now >= a.start end)
  if bf then spin = PI * (1 - easeInOut(clamp((now - bf.start) / bf.dur, 0, 1))) end
  local pending = find(self.anims, function(a) return a.kind == 'boardflip' and now < a.start end)
  if pending then spin = PI end

  -- the mat and the tiles
  local ex, ey = self:extents()
  sprite(R, self:quad(0, 0, 0.0015, ex, ey, spin), R.glyph('tile'), NAVY, 150)
  local power, chess = {}, {}
  for _, p in ipairs(v and v.power or {}) do power[p.cell] = p end
  for _, c in ipairs(v and v.chess or {}) do chess[c.cell] = PIECE[c.piece] end
  local targets, picked = {}, {}
  local ui = v and v.ui
  if ui and ui.myTurn then
    for _, c in ipairs(ui.targets or {}) do targets[c] = true end
    for _, c in ipairs(ui.picked or {}) do picked[c] = true end
  end
  local pulse = 0.5 + 0.5 * math.sin(now / 180)
  for r = 0, 2 do
    for c = 0, 4 do
      local cell = Board.cellName(r, c)
      local x, y = self:cellXY(cell, spin)
      local tw, th = self.W / 2 * 1.04, self.H / 2 * 1.03
      sprite(R, self:quad(x, y, 0.003, tw, th, spin), R.glyph('tile'), WHITE, 46)
      local p = power[cell]
      if p then
        sprite(R, self:quad(x, y, 0.0035, tw, th, spin), R.glyph('tile'), p.rgb or WHITE, 120)
        local bx, by = x + tw * 0.75, y + th * 0.82
        sprite(R, self:quad(bx, by, 0.02, self.W * 0.2, self.W * 0.2, spin), R.glyph(p.boost >= 2 and 'plus2' or 'plus1'), p.rgb or WHITE, 255)
      end
      if v and v.ruleset == 'mutators' and OVERRUN[cell] then sprite(R, self:quad(x, y, 0.004, tw * 0.92, th * 0.92, spin), R.glyph('zone'), WHITE, 90) end
      if chess[cell] then sprite(R, self:quad(x, y, 0.0045, self.W * 0.42, self.W * 0.42, spin + (v and v.flip and PI or 0)), R.glyph(chess[cell]), WHITE, 200) end
      if targets[cell] then
        local col = picked[cell] and SUN or MINT
        local a = picked[cell] and 230 or math.floor(130 + 110 * pulse)
        if self.hover and self.hover.kind == 'tile' and self.hover.cell == cell then a = 255 end
        sprite(R, self:quad(x, y, 0.005, tw * 1.08, th * 1.06, spin), R.glyph('rim'), col, a)
        sprite(R, self:quad(x, y, 0.0048, tw * 1.25, th * 1.2, spin), R.glyph('glow'), col, math.floor(a * 0.45))
      end
    end
  end

  -- the cards on the board
  local hidden = {}
  for _, a in ipairs(self.anims) do
    if (a.kind == 'drop' or a.kind == 'hop') and now < a.start + a.dur then hidden[a.cell] = a end
  end
  for _, t in ipairs(v and v.board or {}) do
    local x, y = self:cellXY(t.cell, spin)
    local a = hidden[t.cell]
    local flip = find(self.anims, function(f) return f.kind == 'flip' and f.cell == t.cell and now < f.start + f.dur end)
    if a and a.kind == 'drop' then
      if now >= a.start then
        local p = clamp((now - a.start) / a.dur, 0, 1)
        local z = 0.008 + self.H * 0.9 * (1 - easeOut(p))
        self:card(R, t.id, x, y, z, self:ownerYaw(t.owner) + spin, { rim = ownerColour(t.owner), frozen = t.frozen, scale = 1 + 0.18 * (1 - backOut(p)), lift = z - 0.008 })
      end
    elseif a and a.kind == 'hop' then
      if now >= a.start then
        local p = easeInOut(clamp((now - a.start) / a.dur, 0, 1))
        local fx, fy = self:cellXY(a.from, spin)
        local hx, hy = fx + (x - fx) * p, fy + (y - fy) * p
        local z = 0.008 + math.sin(p * PI) * self.H * 0.8
        self:card(R, t.id, hx, hy, z, self:ownerYaw(t.owner) + spin, { rim = ownerColour(t.owner), lift = z - 0.008 })
      else
        local fx, fy = self:cellXY(a.from, spin)
        self:card(R, t.id, fx, fy, 0.008, self:ownerYaw(t.owner) + spin, { rim = ownerColour(t.owner) })
      end
    elseif flip and now >= flip.start then
      local p = clamp((now - flip.start) / flip.dur, 0, 1)
      local owner = p < 0.5 and flip.from or t.owner
      local roll = p < 0.5 and p * PI or (p - 1) * PI
      local z = 0.008 + math.sin(p * PI) * self.H * 0.45
      self:card(R, t.id, x, y, z, self:ownerYaw(owner) + spin, { rim = ownerColour(owner), roll = roll, frozen = t.frozen, lift = z - 0.008 })
    else
      local owner = flip and flip.from or t.owner
      self:card(R, t.id, x, y, 0.008, self:ownerYaw(owner) + spin, { rim = ownerColour(owner), frozen = t.frozen })
    end
  end

  -- cards leaving the board: a boulder, a recruit, an overrun
  for _, a in ipairs(self.anims) do
    if a.kind == 'vanish' and now >= a.start and now < a.start + a.dur then
      local p = clamp((now - a.start) / a.dur, 0, 1)
      local x, y = self:cellXY(a.cell, spin)
      local shake = math.sin(p * 40) * self.H * 0.03 * (1 - p)
      self:card(R, a.id, x + shake, y, 0.008 + p * self.H * 0.25, self:ownerYaw(a.owner) + spin + p * 1.2, { rim = ownerColour(a.owner), scale = 1 - 0.7 * p, alpha = math.floor(255 * (1 - p)) })
    end
  end

  self:drawHands(R, now, spin)

  -- an effect card shown over the board
  for _, a in ipairs(self.anims) do
    if a.kind == 'callout' and now >= a.start and now < a.start + a.dur then
      local p = clamp((now - a.start) / a.dur, 0, 1)
      local rise = easeOut(math.min(1, p * 2.5))
      local fade = p > 0.8 and (1 - (p - 0.8) / 0.2) or 1
      local yaw = (self.view and self.view.viewer == 'B') and PI or 0
      if self.view and self.view.flip then yaw = yaw + PI end
      self:card(R, a.id, 0, 0, self.H * (0.35 + 0.9 * rise), yaw, { scale = 1.6 * (0.6 + 0.4 * rise), pitch = math.rad(70), alpha = math.floor(255 * fade), roll = (1 - rise) * PI * 2 })
    end
  end

  -- a character's strike drawing, standing over the tile it attacks from
  for _, a in ipairs(self.anims) do
    if a.kind == 'strike' and now >= a.start and now < a.start + a.dur then
      local p = clamp((now - a.start) / a.dur, 0, 1)
      local x, y = self:cellXY(a.cell, spin)
      local cx, cy = R.camera()
      local wx, wy = self:world(x, y, 0)
      local yaw = math.atan(cx - wx, -(cy - wy)) - math.rad(self.heading)
      local pop = p < 0.3 and backOut(p / 0.3) or 1
      local fade = p > 0.75 and (1 - (p - 0.75) / 0.25) or 1
      local size = self.H * 1.1 * pop
      local corners = self:quad(x, y, 0.01 + size * 0.95, size, size, yaw, 0, PI / 2)
      sprite(R, corners, R.fx(a), WHITE, math.floor(255 * fade), a.mirror)
    end
  end
end

--- Both hands: the viewer's own cards face up, standing at their edge; every other hand is
--- its count of card backs.
function Board:handSlots(chair, n)
  local ex, ey = self:extents()
  local out = {}
  local step = self.W * 0.95 + self.G
  for i = 1, n do
    local x = (i - (n + 1) / 2) * step
    local y = -(ey + self.H * 0.42)
    if chair == 'B' then x, y = -x, -y end
    out[i] = { x = x, y = y }
  end
  return out
end

-- The chair each game seat sits at.
function Board:chairOf(seat)
  if self.view and self.view.flip then return seat == 'A' and 'B' or 'A' end
  return seat
end

function Board:drawHands(R, now, spin)
  local v = self.view
  if not v or not v.hands then return end
  self.handCorners = {}
  local pitch = math.rad(62)
  for _, seat in ipairs({ 'A', 'B' }) do
    local mine = v.viewer == seat and v.myHand
    local n = mine and #v.myHand or (v.hands[seat] or 0)
    local chair = self:chairOf(seat)
    local yaw = chair == 'A' and 0 or PI
    for i, slot in ipairs(self:handSlots(chair, n)) do
      if mine then
        local id = v.myHand[i]
        local ui = v.ui or {}
        local sel = ui.selected == i - 1
        local dead = ui.myTurn and ui.dead and ui.dead[i]
        local hov = self.hover and self.hover.kind == 'hand' and self.hover.index == i - 1
        local lift = (sel and self.H * 0.3 or 0) + (hov and self.H * 0.08 or 0)
        local inward = sel and self.H * 0.15 or 0
        local sy = chair == 'A' and inward or -inward
        local fresh = find(self.anims, function(a) return a.kind == 'draw' and a.index == i - 1 and now < a.start + a.dur end)
        local alpha = dead and 150 or 255
        local dz = 0
        if fresh then
          local p = clamp((now - fresh.start) / fresh.dur, 0, 1)
          if now < fresh.start then alpha = 0 else dz = (1 - backOut(p)) * self.H * 0.6 end
        end
        if alpha > 0 then
          self.handCorners[i] = self:card(R, id, slot.x, slot.y + sy, 0.006 + lift + dz, yaw, { pitch = sel and math.rad(74) or pitch, alpha = alpha })
        end
      else
        self:card(R, 0, slot.x, slot.y, 0.006, yaw, { pitch = pitch, back = true })
      end
    end
  end
end

-------------------------------------------------------------------------------------------
-- picking

local function inside(px, py, poly)
  local hit = false
  local j = #poly
  for i = 1, #poly do
    local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
    if (yi > py) ~= (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi then hit = not hit end
    j = i
  end
  return hit
end

local function screenPoly(R, corners)
  local out = {}
  for i, c in ipairs(corners) do
    local ok, sx, sy = R.project(c[1], c[2], c[3])
    if not ok then return nil end
    out[i] = { sx, sy }
  end
  return out
end

--- What is under the screen point (0..1): one of the viewer's hand cards, or a tile.
function Board:pick(R, sx, sy)
  for i = #(self.handCorners or {}), 1, -1 do
    local c = self.handCorners[i]
    local poly = c and screenPoly(R, c)
    if poly and inside(sx, sy, poly) then return { kind = 'hand', index = i - 1 } end
  end
  for r = 0, 2 do
    for c = 0, 4 do
      local cell = Board.cellName(r, c)
      local x, y = self:cellXY(cell)
      local poly = screenPoly(R, (self:quad(x, y, 0.008, self.W / 2 * 1.04, self.H / 2 * 1.03, 0)))
      if poly and inside(sx, sy, poly) then return { kind = 'tile', cell = cell } end
    end
  end
  return nil
end

--- The point above a chair's edge where its player's name is shown.
function Board:namePoint(chair)
  local _, ey = self:extents()
  local y = -(ey + self.H * 1.05)
  if chair == 'B' then y = -y end
  return self:world(0, y, self.H * 0.9)
end

return Board
