-- The Smash&Clash board as a real object on a table: tiles, cards, both hands and every
-- animation, drawn each frame as textured polygons in the world (cards are quads that drop,
-- flip, hop and crumble), so anyone nearby sees the game from wherever they stand.
--
-- Nothing here calls a native directly: the renderer `R` (client/render.lua in the game, a
-- recorder in the dev page's sim/shim.lua) draws and projects, so the board can be checked
-- outside GTA.

Board = {}
Board.__index = Board

local COLS = 'ABCDE'
local PI = math.pi
local PIECE = { KNIGHT = 'knight', BISHOP = 'bishop', ROOK = 'rook', QUEEN = 'queen', knight = 'knight', bishop = 'bishop', rook = 'rook', queen = 'queen' }
local OVERRUN = { B2 = true, C2 = true, D2 = true }

-- Arena Pop: chair A blue, chair B orange (the website's you / them, as the table sees it)
local BLUE = { 33, 115, 232 }
local ORANGE = { 244, 88, 31 }
local MINT = { 139, 247, 207 }
local SUN = { 255, 194, 26 }
local RED = { 255, 84, 84 }
local ICE = { 190, 235, 255 }
local WHITE = { 255, 255, 255 }

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function easeOut(p) return 1 - (1 - p) ^ 3 end
local function easeInOut(p) return p < 0.5 and 4 * p * p * p or 1 - (-2 * p + 2) ^ 3 / 2 end
local function backOut(p)
  local c1, c3 = 1.70158, 2.70158
  return 1 + c3 * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
end
local function backInOut(p)
  local c2 = 1.70158 * 1.525
  if p < 0.5 then return ((2 * p) ^ 2 * ((c2 + 1) * 2 * p - c2)) / 2 end
  return ((2 * p - 2) ^ 2 * ((c2 + 1) * (p * 2 - 2) + c2) + 2) / 2
end
-- a landing: down fast, one small bounce
local function bounce(p)
  if p < 0.72 then return (p / 0.72) ^ 2 end
  local q = (p - 0.72) / 0.28
  return 1 - math.sin(q * PI) * 0.08
end

local function find(list, pred)
  for _, v in ipairs(list or {}) do
    if pred(v) then return v end
  end
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
  self.fan = {} -- card id -> how it sits in the hand now (eased every frame)
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
--- Returns what the players' bodies do in it: { { kind = 'play' | 'draw', seat, at } }.
function Board:animate(steps, now)
  local acts = {}
  for _, s in ipairs(steps or {}) do
    s.start = now + (s.at or 0)
    self.anims[#self.anims + 1] = s
    if s.kind == 'drop' and s.fromHand and s.seat then acts[#acts + 1] = { kind = 'play', seat = s.seat, at = s.at or 0 } end
    if s.kind == 'draw' and s.seat then acts[#acts + 1] = { kind = 'draw', seat = s.seat, at = s.at or 0 } end
  end
  return acts
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

--- World to table coordinates (the inverse of Board:world).
function Board:toLocal(x, y, z)
  local o = self.origin
  local dx, dy = x - o.x, y - o.y
  return dx * self.ax[1] + dy * self.ax[2], dx * self.ay[1] + dy * self.ay[2], z - o.z
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

-- The chair each game seat sits at.
function Board:chairOf(seat)
  if self.view and self.view.flip then return seat == 'A' and 'B' or 'A' end
  return seat
end

-------------------------------------------------------------------------------------------
-- drawing primitives

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

local function ownerColour(owner)
  return owner == 'A' and BLUE or ORANGE
end

-- The yaw that turns a card to face its owner: chair A's cards read from chair A's side.
function Board:ownerYaw(owner)
  local yaw = owner == 'A' and 0 or PI
  if self.view and self.view.flip then yaw = yaw + PI end
  return yaw
end

--- A card on (or over) the board: its face, or `back` = true for a hidden card, on the side
--- the camera sees; a slim border in its owner's colour outside the card (never over it, so
--- every value stays readable), and a soft shadow under it.
function Board:card(R, id, x, y, z, yaw, opts)
  opts = opts or {}
  local s = opts.scale or 1
  local hw, hh = self.W / 2 * s, self.H / 2 * s
  local corners, n = self:quad(x, y, z, hw, hh, yaw, opts.roll, opts.pitch)
  local front = faces(R, corners, n)
  local alpha = opts.alpha or 255
  local tint = opts.frozen and { 210, 238, 255 } or opts.dim and { 175, 175, 175 } or WHITE
  if not opts.pitch then
    local lift = opts.lift or 0
    local shadowZ = math.max(0.001, z - 0.004 - lift)
    local spread = 1 + lift / self.H * 0.6
    local sc = self:quad(x + self.H * 0.025 + lift * 0.2, y - self.H * 0.035 - lift * 0.25, shadowZ, hw * 1.12 * spread, hh * 1.1 * spread, yaw)
    sprite(R, sc, R.glyph('shadow'), WHITE, math.floor(150 * alpha / 255 / spread))
  end
  if opts.rim and not opts.pitch then
    sprite(R, self:quad(x, y, z - 0.0012, hw * 1.065, hh * 1.048, yaw, opts.roll, opts.pitch), R.glyph('tile'), opts.rim, alpha)
  end
  if opts.back or not front then
    sprite(R, corners, R.card('back'), WHITE, alpha, not front)
  else
    sprite(R, corners, R.card(id), tint, alpha)
  end
  if opts.frozen and front and not opts.back then
    local k = opts.ice or 1
    sprite(R, self:quad(x, y, z + 0.0008, hw * (1 + 0.3 * (1 - k)), hh * (1 + 0.3 * (1 - k)), yaw, opts.roll, opts.pitch), R.glyph('ice'), WHITE, math.floor(170 * alpha / 255 * k))
  end
  return corners
end

--- A quarter of a card (a crumbling piece): `qx`, `qy` pick the quarter (0 or 1).
function Board:piece(R, id, x, y, z, yaw, qx, qy, roll, alpha)
  local uv = R.card(id)
  local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
  local um, vm = (u0 + u1) / 2, (v0 + v1) / 2
  local pu = { qx == 0 and u0 or um, qy == 0 and v0 or vm, qx == 0 and um or u1, qy == 0 and vm or v1 }
  sprite(R, (self:quad(x, y, z, self.W / 4, self.H / 4, yaw, roll)), pu, WHITE, alpha)
end

-------------------------------------------------------------------------------------------
-- the board

--- Draw the whole table. `now` is the game timer (ms).
function Board:draw(R, now)
  local dt = self.clock and math.min(100, now - self.clock) or 16
  self.clock = now
  local v = self.view
  -- drop finished animations
  local live = {}
  for _, a in ipairs(self.anims) do
    if now < a.start + a.dur + 50 then live[#live + 1] = a end
  end
  self.anims = live

  -- a Flip turns the whole board over: it rises, turns half round and lands
  local spin, liftAll = 0, 0
  local bf = find(self.anims, function(a) return a.kind == 'boardflip' and now >= a.start end)
  if bf then
    local p = clamp((now - bf.start) / bf.dur, 0, 1)
    spin = PI * (1 - backInOut(p))
    liftAll = math.sin(p * PI) * self.H * 0.7
  elseif find(self.anims, function(a) return a.kind == 'boardflip' end) then
    spin = PI
  end
  -- a Boulder shakes the board
  local quake = find(self.anims, function(a) return a.kind == 'quake' and now >= a.start and now < a.start + a.dur end)
  local shakeX = 0
  if quake then
    local p = (now - quake.start) / quake.dur
    shakeX = math.sin(p * 70) * self.H * 0.035 * (1 - p)
  end

  local ex, ey = self:extents()
  local gx, gy = self:grid()
  local T = self.T + liftAll
  local flipYaw = (v and v.flip) and PI or 0
  local function bxy(x, y) local a, b = self:boardXY(x, y, spin) return a + shakeX, b end
  local function cxy(cell) local a, b = self:cellXY(cell, spin) return a + shakeX, b end

  -- the slab: cream wood with a darker edge, as on smashandclash.in
  sprite(R, self:quad(self.H * 0.06, -self.H * 0.08, 0.001, ex * 1.12, ey * 1.14, 0), R.glyph('shadow'), WHITE, math.floor(170 - liftAll / self.H * 120))
  local side = { 196, 176, 136 }
  for _, e in ipairs({ { 0, -ey, ex, 0 }, { 0, ey, ex, PI }, { -ex, 0, ey, -PI / 2 }, { ex, 0, ey, PI / 2 } }) do
    local x, y = bxy(e[1], e[2])
    sprite(R, self:quad(x, y, T - self.T / 2, e[3], self.T / 2, e[4] + spin + flipYaw, 0, PI / 2), R.board('slab'), side, 255)
  end
  local sx, sy = bxy(0, 0)
  sprite(R, self:quad(sx, sy, T, ex, ey, spin), R.board('slab'), WHITE, 255)

  -- A-E along both long edges, 1-3 down both short ones, each reading from the nearer chair
  local lw = self.M * 0.62
  for c = 0, 4 do
    local x0 = (c - 2) * (self.W + self.G)
    for _, e in ipairs({ { -1, 0 }, { 1, PI } }) do
      local x, y = bxy(x0, e[1] * (gy + self.M / 2))
      sprite(R, self:quad(x, y, T + 0.0006, lw / 2, lw / 2, e[2] + spin + flipYaw), R.label(COLS:sub(c + 1, c + 1)), WHITE, 235)
    end
  end
  for r = 0, 2 do
    local y0 = (r - 1) * (self.H + self.G)
    for _, e in ipairs({ { -1, 0 }, { 1, PI } }) do
      local x, y = bxy(e[1] * (gx + self.M / 2), y0)
      sprite(R, self:quad(x, y, T + 0.0006, lw / 2, lw / 2, e[2] + spin + flipYaw), R.label(tostring(r + 1)), WHITE, 235)
    end
  end

  -- the tiles
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
      local x, y = cxy(cell)
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
      local hovered = self.hover and self.hover.kind == 'tile' and self.hover.cell == cell
      if targets[cell] then
        local col = picked[cell] and SUN or MINT
        local a = picked[cell] and 230 or math.floor(130 + 110 * pulse)
        if hovered then
          -- the tile you are on, and the card can go there: a bright, breathing outline in sun
          -- yellow, a second ring just outside it and a strong glow, so it reads at a glance
          local k = 1 + 0.035 * math.sin(now / 120)
          sprite(R, self:quad(x, y, T + 0.0024, tw * 1.45 * k, th * 1.38 * k, yaw), R.glyph('glow'), SUN, 230)
          sprite(R, self:quad(x, y, T + 0.0027, tw * 1.16 * k, th * 1.13 * k, yaw), R.glyph('rim'), SUN, 255)
          sprite(R, self:quad(x, y, T + 0.0028, tw * 1.07, th * 1.05, yaw), R.glyph('rim'), WHITE, 255)
          sprite(R, self:quad(x, y, T + 0.0021, tw, th, yaw), R.glyph('tile'), SUN, 70)
        else
          sprite(R, self:quad(x, y, T + 0.0026, tw * 1.08, th * 1.06, yaw), R.glyph('rim'), col, a)
          sprite(R, self:quad(x, y, T + 0.0024, tw * 1.25, th * 1.2, yaw), R.glyph('glow'), col, math.floor(a * 0.45))
        end
      elseif hovered and ui and ui.myTurn then
        if ui.selected ~= nil then
          -- a card is picked but cannot go here: a red edge says no
          sprite(R, self:quad(x, y, T + 0.0026, tw * 1.06, th * 1.04, yaw), R.glyph('rim'), RED, 200)
        else
          -- nothing picked yet: a soft outline shows what the dot is on
          sprite(R, self:quad(x, y, T + 0.0026, tw * 1.05, th * 1.03, yaw), R.glyph('rim'), WHITE, 120)
        end
      end
      -- the tile you look at with a card picked: the card waits over it, see-through, before you place it
      if targets[cell] and ui and ui.selected ~= nil and v.myHand and self.hover and self.hover.kind == 'tile' and self.hover.cell == cell then
        local id = v.myHand[ui.selected + 1]
        if id then self:card(R, id, x, y, T + 0.03 + math.sin(now / 200) * 0.004, self:ownerYaw(v.viewer or 'A') + spin, { alpha = 160 }) end
      end
    end
  end

  -- the deck, on a little stand at chair A's left, as tall as the cards left in it
  if v and v.deck and v.deck > 0 then
    local dx, dy = self:boardXY(-(ex + self.W * 0.95), 0)
    sprite(R, self:quad(dx, dy, self.T * 0.5, self.W * 0.72, self.H * 0.66, 0), R.board('slab'), side, 255)
    local n = math.max(1, math.ceil(v.deck / 8))
    for i = 1, n do
      self:card(R, 0, dx, dy, self.T * 0.5 + 0.003 + i * 0.004, (i % 2 == 0 and 0.05 or -0.04) + flipYaw, { back = true })
    end
  end

  self:drawBoardCards(R, now, cxy, T, spin)
  self:drawHands(R, now, dt)
  self:drawPlaying(R, now, spin)
  self:drawEffects(R, now, cxy, T, spin)
end

--- The cards on the board, each with whatever is happening to it.
function Board:drawBoardCards(R, now, cxy, T, spin)
  local v = self.view
  local B0 = T + 0.008
  local busy = {}
  for _, a in ipairs(self.anims) do
    if (a.kind == 'drop' or a.kind == 'hop' or a.kind == 'recruit') and now < a.start + a.dur then busy[a.cell] = a end
  end
  for _, t in ipairs(v and v.board or {}) do
    local x, y = cxy(t.cell)
    local a = busy[t.cell]
    local yaw = self:ownerYaw(t.owner) + spin
    local flip = find(self.anims, function(f) return f.kind == 'flip' and f.cell == t.cell and now < f.start + f.dur end)
    local freeze = find(self.anims, function(f) return f.kind == 'freeze' and f.cell == t.cell and now < f.start + f.dur end)
    local ice = 1
    if freeze then ice = now < freeze.start and 0 or easeOut(clamp((now - freeze.start) / freeze.dur, 0, 1)) end
    local frozen = t.frozen and ice > 0
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
          -- played from the hand: an arc from the fan down onto its tile, turning flat as it
          -- lands, with a little spin that settles and a bump on touchdown
          local e = easeInOut(p)
          local cx, cy = lerp(hx, x, e), lerp(hy, y, e)
          local z = lerp(hz, B0, bounce(p)) + math.sin(e * PI) * self.H * 0.5
          local settle = (1 - e) * 0.5
          self:card(R, t.id, cx, cy, z, yaw + settle, { rim = p > 0.85 and ownerColour(t.owner) or nil, frozen = frozen, scale = 0.6 + 0.4 * e, lift = math.max(0, z - B0) })
        else
          local z = B0 + self.H * 0.9 * (1 - bounce(p))
          self:card(R, t.id, x, y, z, yaw, { rim = ownerColour(t.owner), frozen = frozen, scale = 1 + 0.12 * (1 - p), lift = z - B0 })
        end
        if p > 0.85 then self:ring(R, x, y, B0 - 0.002, (p - 0.85) / 0.15, ownerColour(t.owner)) end
      end
    elseif a and (a.kind == 'hop' or a.kind == 'recruit') then
      local fx, fy = cxy(a.from)
      if now >= a.start then
        -- a hop (or a recruited card) lifts, flies along an arc and lands; a recruit turns over
        -- to its new owner in the air
        local p = clamp((now - a.start) / a.dur, 0, 1)
        local e = easeInOut(p)
        local z = B0 + math.sin(e * PI) * self.H * (a.kind == 'recruit' and 1.1 or 0.8)
        local owner, roll = t.owner, 0
        if a.kind == 'recruit' then
          owner = p < 0.5 and (a.owner or t.owner) or t.owner
          roll = p < 0.5 and p * 2 * PI or 0
          if p >= 0.5 then roll = (p - 1) * 2 * PI end
          roll = roll / 2
        end
        self:card(R, t.id, lerp(fx, x, e), lerp(fy, y, e), z, self:ownerYaw(owner) + spin, { rim = ownerColour(owner), roll = roll, lift = z - B0 })
        if p > 0.85 then self:ring(R, x, y, B0 - 0.002, (p - 0.85) / 0.15, ownerColour(t.owner)) end
      else
        local owner = a.kind == 'recruit' and (a.owner or t.owner) or t.owner
        self:card(R, t.id, fx, fy, B0, self:ownerYaw(owner) + spin, { rim = ownerColour(owner) })
      end
    elseif flip and now >= flip.start then
      -- a capture: the card jumps, turns right over to its new owner and lands with a flash
      local p = clamp((now - flip.start) / flip.dur, 0, 1)
      local owner = p < 0.5 and flip.from or t.owner
      local roll = p < 0.5 and backOut(p * 2) * PI / 2 or (1 - backOut((p - 0.5) * 2)) * -PI / 2
      local z = B0 + math.sin(p * PI) * self.H * 0.7
      self:card(R, t.id, x, y, z, self:ownerYaw(owner) + spin, { rim = ownerColour(owner), roll = roll, frozen = frozen, lift = z - B0, scale = 1 + 0.1 * math.sin(p * PI) })
      if p > 0.7 then self:ring(R, x, y, B0 - 0.002, (p - 0.7) / 0.3, ownerColour(t.owner)) end
    else
      local owner = (flip and flip.from) or t.owner
      self:card(R, t.id, x, y, B0, self:ownerYaw(owner) + spin, { rim = ownerColour(owner), frozen = frozen, ice = ice })
      if freeze and now >= freeze.start then
        local p = clamp((now - freeze.start) / freeze.dur, 0, 1)
        sprite(R, self:quad(x, y, B0 + 0.003, self.W * (0.7 + p), self.H * (0.6 + p * 0.8), spin), R.glyph('glow'), ICE, math.floor(220 * (1 - p)))
      end
    end
  end

  -- cards leaving the board: a Boulder crumbles them, an overrun or a recruit lifts them away
  for _, a in ipairs(self.anims) do
    if a.kind == 'vanish' and now >= a.start and now < a.start + a.dur then
      local p = clamp((now - a.start) / a.dur, 0, 1)
      local x, y = cxy(a.cell)
      local yaw = self:ownerYaw(a.owner) + spin
      if a.crumble then
        -- shaken, then broken in four, the pieces flung out and falling
        if p < 0.25 then
          local shake = math.sin(p * 120) * self.H * 0.04
          self:card(R, a.id, x + shake, y, B0, yaw, { rim = ownerColour(a.owner) })
        else
          local q = (p - 0.25) / 0.75
          for qy = 0, 1 do
            for qx = 0, 1 do
              local dx, dy = (qx - 0.5) * 2, (0.5 - qy) * 2
              local ox, oy = self.W / 4 * dx + dx * q * self.H * 0.7, self.H / 4 * dy + dy * q * self.H * 0.5
              local cs, sn = math.cos(yaw), math.sin(yaw)
              local z = B0 + math.sin(math.min(1, q * 1.6) * PI) * self.H * 0.5 - q * q * self.H * 0.3
              self:piece(R, a.id, x + ox * cs - oy * sn, y + ox * sn + oy * cs, math.max(B0, z), yaw + q * 2 * dx, qx, qy, q * 3 * dy, math.floor(255 * (1 - q)))
            end
          end
          sprite(R, self:quad(x, y, B0 + 0.004, self.W * (0.6 + q * 1.4), self.H * (0.5 + q), spin), R.glyph('shadow'), { 120, 100, 80 }, math.floor(160 * (1 - q)))
        end
      else
        self:card(R, a.id, x, y, B0 + easeOut(p) * self.H * 0.5, yaw + p * 1.4, { rim = ownerColour(a.owner), scale = 1 - 0.6 * p, alpha = math.floor(255 * (1 - p)) })
      end
    end
  end
end

--- A ring that opens out from a tile as a card lands on it.
function Board:ring(R, x, y, z, p, rgb)
  local s = 1 + p * 0.5
  sprite(R, self:quad(x, y, z, self.W / 2 * 1.1 * s, self.H / 2 * 1.08 * s, 0), R.glyph('rim'), rgb, math.floor(230 * (1 - p)))
end

--- What plays over the board: an effect card called out, a character's strike drawing, the
--- numbers each attack compares, and the hands swapping across the table.
function Board:drawEffects(R, now, cxy, T, spin)
  local v = self.view
  for _, a in ipairs(self.anims) do
    if now >= a.start and now < a.start + a.dur then
      local p = clamp((now - a.start) / a.dur, 0, 1)
      if a.kind == 'callout' then
        -- the effect card rises over the board, spins to face the players, glows, and goes
        local rise = easeOut(math.min(1, p * 2.2))
        local fade = p > 0.82 and (1 - (p - 0.82) / 0.18) or 1
        local yaw = (v and v.viewer == 'B') and PI or 0
        if v and v.flip then yaw = yaw + PI end
        local z = T + self.H * (0.4 + 0.8 * rise)
        sprite(R, self:quad(0, 0, z - 0.004, self.W * 2.2, self.W * 2.2, yaw, 0, math.rad(70)), R.glyph('glow'), SUN, math.floor(200 * fade * rise))
        self:card(R, a.id, 0, 0, z, yaw, { scale = 1.7 * (0.5 + 0.5 * backOut(math.min(1, p * 2))), pitch = math.rad(70), alpha = math.floor(255 * fade), roll = (1 - rise) * PI * 2 })
      elseif a.kind == 'strike' then
        -- the attacker's strike drawing, standing over its tile, facing the camera
        local x, y = cxy(a.cell)
        local cx, cy = R.camera()
        local wx, wy = self:world(x, y, 0)
        local yaw = math.atan(cx - wx, -(cy - wy)) - math.rad(self.heading)
        local pop = p < 0.3 and backOut(p / 0.3) or 1
        local fade = p > 0.75 and (1 - (p - 0.75) / 0.25) or 1
        local size = self.H * 1.1 * pop
        local corners = self:quad(x, y, T + 0.01 + size * 0.95, size, size, yaw, 0, PI / 2)
        sprite(R, corners, R.fx(a), WHITE, math.floor(255 * fade), a.mirror)
      elseif a.kind == 'compare' and R.text then
        -- "6 ≥ 5": what the attack compared, between the two cards; gold when it takes the card
        local x1, y1 = cxy(a.cell)
        local x2, y2 = cxy(a.toward)
        local x, y = (x1 + x2) / 2, (y1 + y2) / 2
        local pop = p < 0.25 and backOut(p / 0.25) or 1
        local fade = p > 0.8 and (1 - (p - 0.8) / 0.2) or 1
        local wx, wy, wz = self:world(x, y, T + self.H * (0.35 + 0.25 * easeOut(p)))
        R.text(wx, wy, wz, a.text, a.win and SUN or { 255, 120, 120 }, math.floor(255 * fade), 0.55 * pop)
      elseif a.kind == 'swap' then
        -- both hands fly across the table, face down, and change places
        local pa = self:handPoint('A')
        local pb = self:handPoint('B')
        if pa and pb then
          for k = 1, 5 do
            local d = (k - 3) * 0.06
            local e = easeInOut(clamp(p * 1.15 - (k - 1) * 0.03, 0, 1))
            for dir = 0, 1 do
              local s, t2 = dir == 0 and pa or pb, dir == 0 and pb or pa
              local px = lerp(s[1], t2[1], e) + d
              local py = lerp(s[2], t2[2], e)
              local pz = lerp(s[3], t2[3], e) + math.sin(e * PI) * self.H * 1.2
              self:card(R, 0, px, py, pz, e * PI * 2 + k, { back = true, scale = 0.58, lift = pz })
            end
          end
        end
      end
    end
  end
end

-------------------------------------------------------------------------------------------
-- the hands

--- Where a seat's cards stand at its edge of the table.
function Board:handSlots(chair, n)
  local _, ey = self:extents()
  local out = {}
  local step = self.W * 0.66 + self.G * 0.9
  for i = 1, n do
    local x = (i - (n + 1) / 2) * step
    local y = -(ey + self.H * 0.5)
    if chair == 'B' then x, y = -x, -y end
    out[i] = { x = x, y = y }
  end
  return out
end

--- The deck stand's top, in the world: where a drawn card starts.
function Board:deckPoint()
  local ex = self:extents()
  local dx, dy = self:boardXY(-(ex + self.W * 0.95), 0)
  return { self:world(dx, dy, self.T * 0.5 + 0.03) }
end

--- The middle of a chair's cards, in table coordinates: their stand.
function Board:handPoint(chair)
  return { 0, self:handSlots(chair, 1)[1].y, self.T + self.H * 0.4 }
end

-- ease a value towards its target, at the same pace whatever the frame rate
local function toward(cur, target, dt, rate)
  return cur + (target - cur) * (1 - math.exp(-dt / 1000 * (rate or 14)))
end

-- how far a card in the stand leans back from upright: its face looks up at the seated player
local STAND = math.rad(38)
-- cards in the stand are smaller than on the board, so the board stays in view
local RACK = 0.66

--- Each player's cards stand in a row at their edge of the table, leaning back towards their
--- chair like tiles on a rack: nothing floats in front of your eyes, nothing covers the board,
--- and every card shows all four values. The card under the cursor rises and comes towards you;
--- a picked card stays up with a sun-yellow edge. The other player sees the backs.
function Board:drawHands(R, now, dt)
  local v = self.view
  if not v or not v.hands then return end
  self.handCorners = {}
  self.handOrder = {}
  local swapping = find(self.anims, function(a) return a.kind == 'swap' and now >= a.start and now < a.start + a.dur end)
  if swapping then return end
  local seen = {}
  local sp, cp = math.sin(STAND), math.cos(STAND)
  for _, seat in ipairs({ 'A', 'B' }) do
    local mine = v.viewer == seat and v.myHand
    local count = mine and #v.myHand or (v.hands[seat] or 0)
    local chair = self:chairOf(seat)
    local ui = v.ui or {}
    -- the card just played has left the stand; the rest close up
    local shown = {}
    for i = 1, count do
      local id = mine and v.myHand[i] or 0
      if not (mine and self.playing and self.playing.id == id) then shown[#shown + 1] = { i = i, id = id } end
    end
    local n = #shown
    local focus = nil
    if mine then
      if self.hover and self.hover.kind == 'hand' then focus = self.hover.index + 1
      elseif ui.focus ~= nil then focus = ui.focus + 1
      elseif ui.selected ~= nil then focus = ui.selected + 1 end
    end
    local slots = self:handSlots(chair, n)
    local toward_ = chair == 'A' and -1 or 1 -- local y towards this chair
    local yaw = chair == 'A' and 0 or PI
    for k, card in ipairs(shown) do
      local i, id = card.i, card.id
      local sel = mine and ui.selected == i - 1
      local dead = mine and ui.myTurn and ui.dead and ui.dead[i]
      local key = seat .. ':' .. (mine and tostring(id) or tostring(i))
      seen[key] = true
      local st = self.fan[key] or { lift = 0, pull = 0, scale = RACK, glow = 0, x = slots[k].x }
      local isFocus = mine and focus == i
      st.lift = toward(st.lift, isFocus and self.H * (sel and 0.26 or 0.18) or (sel and self.H * 0.12 or 0), dt)
      st.pull = toward(st.pull, isFocus and self.H * 0.12 or 0, dt)
      st.scale = toward(st.scale, isFocus and RACK * 1.22 or RACK, dt)
      st.glow = toward(st.glow, sel and 1 or 0, dt, 18)
      -- the row closes up and opens out smoothly as cards come and go
      st.x = toward(st.x or slots[k].x, slots[k].x, dt, 10)
      self.fan[key] = st
      local hh = self.H / 2 * st.scale
      local x, y = st.x, slots[k].y + toward_ * st.pull
      local z = self.T + hh * sp + 0.004 + st.lift
      local alpha, scale = 255, st.scale
      local fresh = find(self.anims, function(a) return a.kind == 'draw' and a.index == i - 1 and (a.seat == nil or a.seat == seat) and now < a.start + a.dur end)
      if fresh then
        -- a card drawn from the deck flies to its place in the stand
        if now < fresh.start then alpha = 0
        else
          local p = easeOut(clamp((now - fresh.start) / fresh.dur, 0, 1))
          local ex = self:extents()
          local dx, dy = self:boardXY(-(ex + self.W * 0.95), 0)
          x, y = lerp(dx, x, p), lerp(dy, y, p)
          z = lerp(self.T * 0.5 + 0.03, z, p) + math.sin(p * PI) * self.H * 0.9
        end
      end
      if alpha > 0 then
        if st.glow > 0.02 then
          -- the picked card's edge, just behind it
          local g = self:quad(x, y - toward_ * 0.002 * cp, z - 0.002 * sp, self.W / 2 * scale * 1.1, hh * 1.07, yaw, 0, STAND)
          sprite(R, g, R.glyph('tile'), SUN, math.floor(alpha * st.glow))
        end
        local corners = self:card(R, mine and id or 0, x, y, z, yaw, { pitch = STAND, back = not mine, alpha = alpha, scale = scale, dim = dead })
        if mine then
          self.handCorners[i] = corners
          self.handOrder[#self.handOrder + 1] = i
        end
      end
    end
  end
  for key in pairs(self.fan) do
    if not seen[key] then self.fan[key] = nil end
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
  if hx then cx, cy, cz = lerp(hx, x, p), lerp(hy, y, p), lerp(hz, hoverZ, p) + math.sin(p * PI) * self.H * 0.3 end
  self:card(R, pl.id, cx, cy, cz, self:ownerYaw(v.viewer or 'A') + spin + (1 - p) * 0.5, { scale = 0.62 + 0.38 * p, lift = cz - B0 })
end

--- Where a card played from a seat's hand starts its flight: the middle of its stand.
function Board:handStart(seat)
  local p = self:handPoint(self:chairOf(seat))
  return p[1], p[2], p[3]
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

--- What is under the screen point (0..1): one of the viewer's hand cards (the one drawn on
--- top first), or a tile.
function Board:pick(R, sx, sy)
  local order = self.handOrder or {}
  for j = #order, 1, -1 do
    local i = order[j]
    local poly = self.handCorners[i] and screenPoly(R, self.handCorners[i])
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
