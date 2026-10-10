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
  -- the board is a slab of wood on the table, its edge printed with A-E and 1-3
  self.T = cardH * 0.1
  self.M = self.W * 0.42
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
  -- a card just played leaves the hand at once and waits over its tile until the move lands
  local p = view and view.ui and view.ui.playing
  if p and not (self.playing and self.playing.cell == p.cell) then
    self.playing = { cell = p.cell, id = p.id, start = self.clock or 0 }
  end
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
  return self:boardXY((c - 2) * (self.W + self.G), (r - 1) * (self.H + self.G), spin)
end

--- A point on the board, written with seat A at chair A, turned the way the board lies now.
function Board:boardXY(x, y, spin)
  if self.view and self.view.flip then x, y = -x, -y end
  if spin and spin ~= 0 then
    local cs, sn = math.cos(spin), math.sin(spin)
    x, y = x * cs - y * sn, x * sn + y * cs
  end
  return x, y
end

--- The half extents of the tiles.
function Board:grid()
  return 2.5 * self.W + 2 * self.G, 1.5 * self.H + self.G
end

--- The half extents of the board's slab, its printed edge included.
function Board:extents()
  local gx, gy = self:grid()
  return gx + self.M, gy + self.M
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
    -- a thick border in the owner's colour, as the website frames every card on the board
    local rc = self:quad(x, y, z - 0.0015, hw * 1.2, hh * 1.15, yaw, opts.roll, opts.pitch)
    sprite(R, rc, R.glyph('tile'), opts.rim, alpha)
  end
  if opts.back or not front then
    sprite(R, corners, R.card('back'), WHITE, alpha, not front)
  else
    sprite(R, corners, R.card(id), tint, alpha)
  end
  if opts.rim and not opts.pitch then
    -- and a ring of it over the card's edge, so the owner reads even on a card of the same colour
    local ring = self:quad(x, y, z + 0.0006, hw * 1.07, hh * 1.05, yaw, opts.roll)
    sprite(R, ring, R.glyph('rim'), opts.rim, alpha)
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
  self.clock = now
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

  -- the board: a slab of cream wood on the table, as on smashandclash.in
  local ex, ey = self:extents()
  local gx, gy = self:grid()
  local T = self.T
  local flipYaw = (v and v.flip) and PI or 0
  sprite(R, self:quad(self.H * 0.06, -self.H * 0.08, 0.001, ex * 1.12, ey * 1.14, spin), R.glyph('shadow'), WHITE, 170)
  local side = { 196, 176, 136 }
  for _, e in ipairs({ { 0, -ey, ex, 0 }, { 0, ey, ex, PI }, { -ex, 0, ey, -PI / 2 }, { ex, 0, ey, PI / 2 } }) do
    local x, y = self:boardXY(e[1], e[2], spin)
    sprite(R, self:quad(x, y, T / 2, e[3], T / 2, e[4] + spin + flipYaw, 0, PI / 2), R.board('slab'), side, 255)
  end
  sprite(R, self:quad(0, 0, T, ex, ey, spin), R.board('slab'), WHITE, 255)

  -- A-E along both long edges, 1-3 down both short ones, each reading from the nearer chair
  local lw = self.M * 0.62
  for c = 0, 4 do
    local x0 = (c - 2) * (self.W + self.G)
    for _, e in ipairs({ { -1, 0 }, { 1, PI } }) do
      local x, y = self:boardXY(x0, e[1] * (gy + self.M / 2), spin)
      sprite(R, self:quad(x, y, T + 0.0006, lw / 2, lw / 2, e[2] + spin + flipYaw), R.label(COLS:sub(c + 1, c + 1)), WHITE, 235)
    end
  end
  for r = 0, 2 do
    local y0 = (r - 1) * (self.H + self.G)
    for _, e in ipairs({ { -1, 0 }, { 1, PI } }) do
      local x, y = self:boardXY(e[1] * (gx + self.M / 2), y0, spin)
      sprite(R, self:quad(x, y, T + 0.0006, lw / 2, lw / 2, e[2] + spin + flipYaw), R.label(tostring(r + 1)), WHITE, 235)
    end
  end

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
  local PURPLE, PURPLE_DEEP = { 150, 110, 245 }, { 96, 52, 206 }
  for r = 0, 2 do
    for c = 0, 4 do
      local cell = Board.cellName(r, c)
      local x, y = self:cellXY(cell, spin)
      local tw, th = self.W / 2 * 1.04, self.H / 2 * 1.03
      local yaw = spin + flipYaw
      local p = power[cell]
      if chess[cell] then
        -- a chess tile: purple, its piece in a circle
        sprite(R, self:quad(x, y, T + 0.001, tw, th, yaw), R.glyph('tile'), PURPLE, 255)
        sprite(R, self:quad(x, y, T + 0.0015, self.W * 0.34, self.W * 0.34, yaw), R.glyph('dot'), PURPLE_DEEP, 255)
        sprite(R, self:quad(x, y, T + 0.002, self.W * 0.3, self.W * 0.3, yaw), R.glyph(chess[cell]), WHITE, 255)
      else
        sprite(R, self:quad(x, y, T + 0.001, tw, th, yaw), R.board('empty'), WHITE, 255)
      end
      if p then
        -- a power tile glows in its colour, with its boost in the corner
        local glow = 0.75 + 0.25 * pulse
        sprite(R, self:quad(x, y, T + 0.0018, tw * 1.02, th * 1.02, yaw), R.glyph('tile'), p.rgb or WHITE, math.floor(95 * glow))
        sprite(R, self:quad(x, y, T + 0.0019, tw * 1.35, th * 1.3, yaw), R.glyph('glow'), p.rgb or WHITE, math.floor(150 * glow))
        local bx, by = x + (tw * 0.6) * math.cos(yaw) - (th * 0.68) * math.sin(yaw), y + (tw * 0.6) * math.sin(yaw) + (th * 0.68) * math.cos(yaw)
        sprite(R, self:quad(bx, by, T + 0.03, self.W * 0.19, self.W * 0.19, yaw), R.glyph(p.boost >= 2 and 'plus2' or 'plus1'), p.rgb or WHITE, 255)
      end
      if v and v.ruleset == 'mutators' and OVERRUN[cell] then sprite(R, self:quad(x, y, T + 0.0022, tw * 0.9, th * 0.9, yaw), R.glyph('zone'), { 190, 160, 110 }, 150) end
      if targets[cell] then
        local col = picked[cell] and SUN or MINT
        local a = picked[cell] and 230 or math.floor(130 + 110 * pulse)
        if self.hover and self.hover.kind == 'tile' and self.hover.cell == cell then a = 255 end
        sprite(R, self:quad(x, y, T + 0.0026, tw * 1.08, th * 1.06, yaw), R.glyph('rim'), col, a)
        sprite(R, self:quad(x, y, T + 0.0024, tw * 1.25, th * 1.2, yaw), R.glyph('glow'), col, math.floor(a * 0.45))
      end
    end
  end

  -- the deck, on a little stand at chair A's left, as tall as the cards left in it
  if v and v.deck and v.deck > 0 then
    local dx, dy = self:boardXY(-(ex + self.W * 0.95), 0)
    sprite(R, self:quad(dx, dy, T * 0.5, self.W * 0.72, self.H * 0.66, 0), R.board('slab'), side, 255)
    local n = math.max(1, math.ceil(v.deck / 8))
    for i = 1, n do
      self:card(R, 0, dx, dy, T * 0.5 + 0.003 + i * 0.004, (i % 2 == 0 and 0.05 or -0.04) + flipYaw, { back = true })
    end
  end

  -- the cards on the board (on the slab, B0 above the table)
  local B0 = self.T + 0.008
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
        local hx, hy, hz = nil, nil, nil
        if a.fromHand then hx, hy, hz = self:handStart(t.owner) end
        if a.fromHand and self.playing and self.playing.cell == t.cell then
          hx, hy, hz = x, y, B0 + self.H * 0.55
          if p >= 1 then self.playing = nil end
        end
        if hx then
          -- played from the hand: an arc from the fan down onto its tile, turning flat as it lands
          local e = easeInOut(p)
          local cx, cy = hx + (x - hx) * e, hy + (y - hy) * e
          local z = hz + (B0 - hz) * e + math.sin(e * PI) * self.H * 0.6
          self:card(R, t.id, cx, cy, z, self:ownerYaw(t.owner) + spin, { rim = p > 0.8 and ownerColour(t.owner) or nil, frozen = t.frozen, scale = 0.62 + 0.38 * e, lift = math.max(0, z - B0) })
        else
          local z = B0 + self.H * 0.9 * (1 - easeOut(p))
          self:card(R, t.id, x, y, z, self:ownerYaw(t.owner) + spin, { rim = ownerColour(t.owner), frozen = t.frozen, scale = 1 + 0.18 * (1 - backOut(p)), lift = z - B0 })
        end
      end
    elseif a and a.kind == 'hop' then
      if now >= a.start then
        local p = easeInOut(clamp((now - a.start) / a.dur, 0, 1))
        local fx, fy = self:cellXY(a.from, spin)
        local hx, hy = fx + (x - fx) * p, fy + (y - fy) * p
        local z = B0 + math.sin(p * PI) * self.H * 0.8
        self:card(R, t.id, hx, hy, z, self:ownerYaw(t.owner) + spin, { rim = ownerColour(t.owner), lift = z - B0 })
      else
        local fx, fy = self:cellXY(a.from, spin)
        self:card(R, t.id, fx, fy, B0, self:ownerYaw(t.owner) + spin, { rim = ownerColour(t.owner) })
      end
    elseif flip and now >= flip.start then
      local p = clamp((now - flip.start) / flip.dur, 0, 1)
      local owner = p < 0.5 and flip.from or t.owner
      local roll = p < 0.5 and p * PI or (p - 1) * PI
      local z = B0 + math.sin(p * PI) * self.H * 0.45
      self:card(R, t.id, x, y, z, self:ownerYaw(owner) + spin, { rim = ownerColour(owner), roll = roll, frozen = t.frozen, lift = z - B0 })
    else
      local owner = flip and flip.from or t.owner
      self:card(R, t.id, x, y, B0, self:ownerYaw(owner) + spin, { rim = ownerColour(owner), frozen = t.frozen })
    end
  end

  -- cards leaving the board: a boulder, a recruit, an overrun
  for _, a in ipairs(self.anims) do
    if a.kind == 'vanish' and now >= a.start and now < a.start + a.dur then
      local p = clamp((now - a.start) / a.dur, 0, 1)
      local x, y = self:cellXY(a.cell, spin)
      local shake = math.sin(p * 40) * self.H * 0.03 * (1 - p)
      self:card(R, a.id, x + shake, y, B0 + p * self.H * 0.25, self:ownerYaw(a.owner) + spin + p * 1.2, { rim = ownerColour(a.owner), scale = 1 - 0.7 * p, alpha = math.floor(255 * (1 - p)) })
    end
  end

  self:drawHands(R, now)
  self:drawPlaying(R, now, spin)

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
      local corners = self:quad(x, y, self.T + 0.01 + size * 0.95, size, size, yaw, 0, PI / 2)
      sprite(R, corners, R.fx(a), WHITE, math.floor(255 * fade), a.mirror)
    end
  end
end

--- Where each chair's player holds their cards, in the world, from their body (client/tables.lua
--- reads it from the ped's hands and head every frame): { A = { anchor = {x,y,z}, head = {x,y,z} } }.
function Board:setHands(hands)
  self.hands = hands
end

--- World to table coordinates (the inverse of Board:world).
function Board:toLocal(x, y, z)
  local o = self.origin
  local dx, dy = x - o.x, y - o.y
  return dx * self.ax[1] + dy * self.ax[2], dx * self.ay[1] + dy * self.ay[2], z - o.z
end

local function v3(a) return { a[1] or a.x, a[2] or a.y, a[3] or a.z } end
local function add(a, b, k) return { a[1] + b[1] * k, a[2] + b[2] * k, a[3] + b[3] * k } end
local function sub3(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function norm3(a)
  local l = math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
  if l < 1e-6 then return { 0, 0, 1 } end
  return { a[1] / l, a[2] / l, a[3] / l }
end
local function cross3(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end

-- the size of a card held in the hand: a real card, a little larger so it reads on screen
local HAND_H = 0.12

--- The fan a player holds: for card i of n, its centre, its up and right axes and its normal
--- (towards the holder's eyes). `lift` raises a picked card out of the fan.
function Board:fanSlot(hand, i, n, lift)
  local anchor, head = v3(hand.anchor), v3(hand.head)
  local f = norm3(sub3(head, anchor))
  local r = norm3(cross3({ 0, 0, 1 }, f))
  local u = cross3(f, r)
  -- spread wide enough that each card's corner, with its values, shows past the next one
  local spread = math.rad(math.min(17, 72 / math.max(1, n - 1)))
  local a = (i - (n + 1) / 2) * spread
  -- card 1 on the left, each next one turned a little further right (seen by the holder)
  local up = add({ 0, 0, 0 }, u, math.cos(a))
  up = add(up, r, math.sin(a))
  local right = add({ 0, 0, 0 }, r, math.cos(a))
  right = add(right, u, -math.sin(a))
  local c = add(anchor, up, HAND_H * 0.5 + (lift or 0))
  c = add(c, f, (i - 1) * 0.0025 + (lift and lift > 0 and 0.012 or 0))
  return c, up, right, f
end

--- A card held in the hand, as a world-space quad; the face shows on the holder's side.
function Board:heldCard(R, id, c, up, right, f, opts)
  opts = opts or {}
  local s = opts.scale or 1
  local hw, hh = HAND_H * 0.7333 / 2 * s, HAND_H / 2 * s
  local function p(kx, ky) return { c[1] + right[1] * hw * kx + up[1] * hh * ky, c[2] + right[2] * hw * kx + up[2] * hh * ky, c[3] + right[3] * hw * kx + up[3] * hh * ky } end
  local corners = { p(-1, 1), p(1, 1), p(1, -1), p(-1, -1) }
  local cx, cy, cz = R.camera()
  local front = (cx - c[1]) * f[1] + (cy - c[2]) * f[2] + (cz - c[3]) * f[3] >= 0
  local alpha = opts.alpha or 255
  if opts.glow and front and not opts.back then
    -- the picked card: a sun-yellow edge behind it
    local g = { p(-1.12, 1.09), p(1.12, 1.09), p(1.12, -1.09), p(-1.12, -1.09) }
    for _, q in ipairs(g) do q[1], q[2], q[3] = q[1] - f[1] * 0.001, q[2] - f[2] * 0.001, q[3] - f[3] * 0.001 end
    sprite(R, g, R.glyph('tile'), SUN, alpha)
  end
  if opts.back or not front then
    sprite(R, corners, R.card('back'), WHITE, alpha, not front)
  else
    sprite(R, corners, R.card(id), WHITE, alpha)
  end
  return corners
end

--- Both hands. A player in a chair holds theirs as a fan; the viewer sees their own faces, everyone
--- else the backs. A seat with nobody in its chair (an opponent on another app) stands its backs
--- at its edge of the table.
function Board:handSlots(chair, n)
  local _, ey = self:extents()
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

--- The deck stand's top, in the world: where a drawn card starts.
function Board:deckPoint()
  local ex = self:extents()
  local dx, dy = self:boardXY(-(ex + self.W * 0.95), 0)
  return { self:world(dx, dy, self.T * 0.5 + 0.03) }
end

function Board:drawHands(R, now)
  local v = self.view
  if not v or not v.hands then return end
  self.handCorners = {}
  local pitch = math.rad(62)
  for _, seat in ipairs({ 'A', 'B' }) do
    local mine = v.viewer == seat and v.myHand
    local count = mine and #v.myHand or (v.hands[seat] or 0)
    local chair = self:chairOf(seat)
    local held = self.hands and self.hands[chair]
    local ui = v.ui or {}
    -- the card just played has left the hand; the rest close up
    local shown = {}
    for i = 1, count do
      local id = mine and v.myHand[i] or 0
      if not (mine and self.playing and self.playing.id == id) then shown[#shown + 1] = { i = i, id = id } end
    end
    local n = #shown
    -- the card the player is looking at (scrolled to, hovered or picked) comes to the front, whole
    local focus = nil
    if mine then
      if self.hover and self.hover.kind == 'hand' then focus = self.hover.index + 1
      elseif ui.focus ~= nil then focus = ui.focus + 1
      elseif ui.selected ~= nil then focus = ui.selected + 1 end
    end
    local front = nil
    for k, card in ipairs(shown) do
      local i, id = card.i, card.id
      local sel = mine and ui.selected == i - 1
      local dead = mine and ui.myTurn and ui.dead and ui.dead[i]
      local fresh = find(self.anims, function(a) return a.kind == 'draw' and a.index == i - 1 and (a.seat == nil or a.seat == seat) and now < a.start + a.dur end)
      if held then
        local c, up, right, f = self:fanSlot(held, k, n, sel and HAND_H * 0.4 or 0)
        local alpha = dead and 160 or 255
        local scale = 1
        if fresh then
          -- a card drawn from the deck flies into its place in the fan
          if now < fresh.start then alpha = 0
          else
            local p = easeOut(clamp((now - fresh.start) / fresh.dur, 0, 1))
            local d = self:deckPoint()
            c = { d[1] + (c[1] - d[1]) * p, d[2] + (c[2] - d[2]) * p, d[3] + (c[3] - d[3]) * p + math.sin(p * PI) * 0.18 }
            scale = 0.7 + 0.3 * p
          end
        end
        if alpha > 0 then
          if mine and focus == i and not fresh then
            front = { i = i, id = id, sel = sel, alpha = alpha }
          elseif mine then
            self.handCorners[i] = self:heldCard(R, id, c, up, right, f, { alpha = alpha, glow = sel, scale = scale })
          else
            self:heldCard(R, 0, c, up, right, f, { back = true, scale = scale })
          end
        end
      else
        -- nobody in that chair: the hand stands at its edge (the viewer's own only in first person)
        if not mine or ui.hand3d then
          local slot = self:handSlots(chair, n)[k]
          local yaw = chair == 'A' and 0 or PI
          local hov = mine and focus == i
          local liftZ = (sel and self.H * 0.3 or 0) + (hov and self.H * 0.08 or 0)
          local corners = self:card(R, mine and id or 0, slot.x, slot.y, 0.006 + liftZ, yaw, { pitch = sel and math.rad(74) or pitch, back = not mine, alpha = dead and 150 or 255 })
          if mine then self.handCorners[i] = corners end
        end
      end
    end
    if front and held then
      -- upright, raised and a little nearer the eyes, over the rest: all four values in view
      local k = 1
      for j, card in ipairs(shown) do if card.i == front.i then k = j end end
      local c, _, _, f = self:fanSlot(held, k, n, HAND_H * (front.sel and 0.62 or 0.5))
      local _, up, right = self:fanSlot(held, (n + 1) / 2, n, 0)
      c = { c[1] + f[1] * 0.035, c[2] + f[2] * 0.035, c[3] + f[3] * 0.035 }
      self.handCorners[front.i] = self:heldCard(R, front.id, c, up, right, f, { alpha = front.alpha, glow = front.sel, scale = 1.18 })
    end
  end
end

--- The card a player just played, while the move is on its way: out of the fan, over its tile.
function Board:drawPlaying(R, now, spin)
  local pl = self.playing
  local v = self.view
  if not pl or not v then return end
  if now - pl.start > 8000 then self.playing = nil return end
  -- the move has landed when its tile holds a card and no drop is waiting to show it
  local landing = find(self.anims, function(a) return a.kind == 'drop' and a.cell == pl.cell end)
  if landing then return end
  if not (v.ui and v.ui.playing) then
    for _, t in ipairs(v.board or {}) do
      if t.cell == pl.cell then self.playing = nil return end
    end
  end
  local x, y = self:cellXY(pl.cell, spin)
  local B0 = self.T + 0.008
  local hoverZ = B0 + self.H * 0.55 + math.sin(now / 220) * self.H * 0.04
  local hx, hy, hz = self:handStart(v.viewer or 'A')
  local p = easeOut(clamp((now - pl.start) / 380, 0, 1))
  local cx, cy, cz = x, y, hoverZ
  if hx then cx, cy, cz = hx + (x - hx) * p, hy + (y - hy) * p, hz + (hoverZ - hz) * p + math.sin(p * PI) * self.H * 0.3 end
  self:card(R, pl.id, cx, cy, cz, self:ownerYaw(v.viewer or 'A') + spin, { scale = 0.62 + 0.38 * p, lift = cz - B0 })
end

--- Where a card played from a seat's hand starts its flight: the middle of the fan, in table
--- coordinates; nil when nobody holds that seat's cards.
function Board:handStart(seat)
  local held = self.hands and self.hands[self:chairOf(seat)]
  if not held then return nil end
  local a = v3(held.anchor)
  local x, y, z = self:toLocal(a[1], a[2], a[3] + HAND_H * 0.45)
  return x, y, z
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
      local poly = screenPoly(R, (self:quad(x, y, self.T + 0.008, self.W / 2 * 1.04, self.H / 2 * 1.03, 0)))
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
