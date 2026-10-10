-- The tables in the world: their props, the board drawn on each, sitting down, the camera while
-- you play, and what is under the cursor.

Tables = {}

--- A line for the server's console (client prints only reach F8): what happened at a table.
function Tables.log(text)
  if not Config.Debug then return end
  TriggerServerEvent('smashandclash:log', tostring(text):sub(1, 300))
end

local list = {}        -- id -> { def, props, board, blip }
local me = { id = nil, chair = nil }
local myServerId = GetPlayerServerId(PlayerId())

local function loadModel(names)
  for _, name in ipairs(names) do
    local hash = joaat(name)
    if IsModelInCdimage(hash) then
      RequestModel(hash)
      local t0 = GetGameTimer()
      while not HasModelLoaded(hash) and GetGameTimer() - t0 < 5000 do Wait(10) end
      if HasModelLoaded(hash) then return hash end
    end
  end
end

local function ground(x, y, z)
  local ok, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
  if ok and math.abs(gz - z) < 3.0 then return gz end
  return z
end

-- A chair's spot: on the table's local y axis, beyond its edge.
local function chairSpot(t, chair)
  local h = math.rad(t.def.heading)
  local ay = { -math.sin(h), math.cos(h) }
  local d = (t.depth / 2 + Config.ChairGap) * (chair == 'A' and -1 or 1)
  local c = t.base
  return vector3(c.x + ay[1] * d, c.y + ay[2] * d, c.z), (t.def.heading + (chair == 'A' and 0.0 or 180.0)) % 360.0
end

local function build(t)
  local d = t.def
  local tableModel = loadModel(Config.TableModels)
  local chairModel = loadModel(Config.ChairModels)
  if not tableModel then return end
  local z = ground(d.coords.x, d.coords.y, d.coords.z)
  -- a model's origin is often its middle, not its feet: stand it on the floor
  local mn, mx = GetModelDimensions(tableModel)
  local obj = CreateObjectNoOffset(tableModel, d.coords.x, d.coords.y, z - mn.z, false, false, false)
  SetEntityHeading(obj, d.heading)
  FreezeEntityPosition(obj, true)
  SetEntityInvincible(obj, true)
  local w, depth = mx.x - mn.x, mx.y - mn.y
  t.base = vector3(d.coords.x, d.coords.y, z)
  t.depth = depth
  t.props = { obj }
  -- the board fills the top: 5 cards and gaps across, 3 rows and both hands deep
  local cardH = math.min(w * 0.9 / (5 * 0.7333 + 0.5), depth * 0.92 / 4.9)
  t.board = Board.new({ x = d.coords.x, y = d.coords.y, z = z + (mx.z - mn.z) + 0.004 }, d.heading, cardH)
  if t.view then t.board:setView(t.view) end
  if chairModel then
    local cmn = GetModelDimensions(chairModel)
    for _, chair in ipairs({ 'A', 'B' }) do
      local pos, facing = chairSpot(t, chair)
      local c = CreateObjectNoOffset(chairModel, pos.x, pos.y, pos.z - cmn.z, false, false, false)
      SetEntityHeading(c, (facing + Config.ChairTurn) % 360.0)
      FreezeEntityPosition(c, true)
      t.props[#t.props + 1] = c
    end
  end
  SetModelAsNoLongerNeeded(tableModel)
  if chairModel then SetModelAsNoLongerNeeded(chairModel) end
end

local function unbuild(t)
  for _, o in ipairs(t.props or {}) do
    if DoesEntityExist(o) then DeleteObject(o) end
  end
  -- the character across goes with the table
  if t.npc and t.npc.ped and DoesEntityExist(t.npc.ped) then DeleteEntity(t.npc.ped) end
  t.props, t.board, t.npc = nil, nil, nil
end

local function blip(t)
  if not Config.Blips or t.def.temp or t.blip then return end
  local b = AddBlipForCoord(t.def.coords.x, t.def.coords.y, t.def.coords.z)
  SetBlipSprite(b, Config.BlipSprite)
  SetBlipColour(b, Config.BlipColour)
  SetBlipScale(b, 0.8)
  SetBlipAsShortRange(b, true)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName('Smash&Clash')
  EndTextCommandSetBlipName(b)
  t.blip = b
end

--- A table's state from the server.
function Tables.update(def)
  local t = list[def.id]
  if not t then
    t = { def = def }
    list[def.id] = t
  end
  local moved = t.def.coords.x ~= def.coords.x or t.def.coords.y ~= def.coords.y or t.def.heading ~= def.heading
  t.def = def
  if moved and t.props then unbuild(t) end
  blip(t)
  if me.id == def.id then Nui.table(Tables.context()) end
end

function Tables.remove(id)
  local t = list[id]
  if not t then return end
  unbuild(t)
  if t.blip then RemoveBlip(t.blip) end
  list[id] = nil
end

function Tables.get(id)
  return list[id]
end

--- The table as the seated player's tablet needs it.
function Tables.context()
  local t = me.id and list[me.id]
  if not t then return nil end
  local across = t.def.seats[me.chair == 'A' and 'B' or 'A']
  return { id = t.def.id, label = t.def.label, seat = me.chair, opposite = across and { name = across.name } or nil }
end

--- What the page draws for a table (nui/src/view.ts), and a move to animate on it.
function Tables.view(id, view)
  local t = list[id]
  if not t then return end
  t.view = view
  if t.board then t.board:setView(view) end
end

function Tables.animate(id, steps)
  local t = list[id]
  if t and t.board then return t.board:animate(steps, GetGameTimer()) end
  return {}
end

-------------------------------------------------------------------------------------------
-- sitting down

function Tables.seated()
  return me.id ~= nil
end

function Tables.mine()
  return me.id and list[me.id]
end

-- Seated, you see the table through your own eyes: a camera just in front of your face (so your
-- hair never gets in the way), looking down at the board to start with. The mouse turns your
-- head (with a menu open, while the right button is held: Tables.freeLook). V swaps to GTA's own
-- camera behind you and back.
local view = 'eyes'
local cam = nil
local look = { yaw = 0.0, pitch = -30.0, toYaw = nil, toPitch = nil }
local facing = 0.0
Tables.freeLook = false

local function eyePoint(ped)
  local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
  local h = math.rad(facing)
  return vector3(head.x - math.sin(h) * 0.13, head.y + math.cos(h) * 0.13, head.z + 0.03)
end

-- how far down the eyes look to see the board: a little this side of its middle, so the whole
-- board is ahead and your cards are at the bottom of the view
local function boardPitch()
  local t = Tables.mine()
  if not t or not t.board then return -30.0 end
  local eye = eyePoint(PlayerPedId())
  local _, ey = t.board:extents()
  local cx, cy, cz = t.board:world(0, (me.chair == 'A' and -1 or 1) * ey * 0.35, 0)
  local dx, dy, dz = cx - eye.x, cy - eye.y, cz - eye.z
  return math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
end

local function eyesOn()
  if cam then return end
  cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
  SetCamFov(cam, 60.0)
  local p = eyePoint(PlayerPedId())
  SetCamCoord(cam, p.x, p.y, p.z)
  SetCamRot(cam, look.pitch, 0.0, facing + look.yaw, 2)
  RenderScriptCams(true, true, 500, true, false)
end

local function eyesOff(ease)
  if not cam then return end
  RenderScriptCams(false, ease ~= false, ease ~= false and 500 or 0, true, false)
  DestroyCam(cam, false)
  cam = nil
end

--- Sitting down: through your eyes (unless you chose GTA's camera at this table).
function Tables.camera()
  if view == 'eyes' then eyesOn() end
end

--- V: through your eyes, then GTA's camera close behind you, then further back, then your eyes.
function Tables.toggleView()
  if not Tables.seated() then return view end
  if view == 'eyes' then
    view = 'near'
    eyesOff(true)
    SetFollowPedCamViewMode(1)
  elseif view == 'near' then
    view = 'far'
    SetFollowPedCamViewMode(2)
  else
    view = 'eyes'
    eyesOn()
  end
  return view
end
Tables.lookAround = Tables.toggleView

--- Turn your head back to the board, smoothly: when you sit down, and when a game starts.
function Tables.lookAtBoard()
  look.toYaw, look.toPitch = 0.0, boardPitch()
end

function Tables.cameraMode()
  return view == 'eyes' and 'first' or 'third'
end

function Tables.cycleCamera()
  Tables.toggleView()
  return Tables.cameraMode()
end

local function cameraOff()
  eyesOff(true)
  view = 'eyes'
  look.yaw, look.toYaw, look.toPitch = 0.0, nil, nil
end

CreateThread(function()
  while true do
    if cam and Tables.seated() then
      local ped = PlayerPedId()
      local dt = GetFrameTime()
      if Tables.freeLook then
        local mx, my = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
        if math.abs(mx) + math.abs(my) > 0.0005 then look.toYaw, look.toPitch = nil, nil end
        look.yaw = math.max(-110.0, math.min(110.0, look.yaw - mx * 9.0))
        look.pitch = math.max(-75.0, math.min(35.0, look.pitch - my * 9.0))
      end
      if look.toPitch then
        local k = 1 - math.exp(-dt * 6.0)
        look.yaw = look.yaw + (look.toYaw - look.yaw) * k
        look.pitch = look.pitch + (look.toPitch - look.pitch) * k
        if math.abs(look.toPitch - look.pitch) < 0.05 and math.abs(look.toYaw - look.yaw) < 0.05 then look.toYaw, look.toPitch = nil, nil end
      end
      local p = eyePoint(ped)
      SetCamCoord(cam, p.x, p.y, p.z)
      SetCamRot(cam, look.pitch, 0.0, facing + look.yaw, 2)
      Wait(0)
    else
      Wait(250)
    end
  end
end)

--- The server sat us down.
--- Sit a body in a chair: GTA's own sitting, warped into place, tried again if it does not take.
function Tables.sit(ped, t, chair)
  local pos, facing = chairSpot(t, chair)
  for _ = 1, 3 do
    ClearPedTasksImmediately(ped)
    SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z + 1.0, false, false, false)
    SetEntityHeading(ped, facing)
    TaskStartScenarioAtPosition(ped, Config.SitScenario, pos.x, pos.y, pos.z + Config.SeatHeight, facing, 0, true, true)
    local t0 = GetGameTimer()
    while not IsPedUsingScenario(ped, Config.SitScenario) and GetGameTimer() - t0 < 1500 do Wait(50) end
    if IsPedUsingScenario(ped, Config.SitScenario) then return true end
    Tables.log(('sit did not take at %s (%.2f %.2f %.2f)'):format(chair, pos.x, pos.y, pos.z))
  end
  return false
end

function Tables.onSeated(id, chair)
  me.id, me.chair = id, chair
  CreateThread(function()
    -- the seat can come before the table itself: wait for both
    local wait = GetGameTimer()
    while (not list[id] or not list[id].board) and GetGameTimer() - wait < 6000 do Wait(50) end
    local t = list[id]
    Tables.log(('seated at %s %s: table %s, board %s'):format(id, chair, tostring(t ~= nil), tostring(t and t.board ~= nil)))
    if not t or not t.board or me.id ~= id then return end
    local ped = PlayerPedId()
    local _, f = chairSpot(t, chair)
    facing = f
    Tables.sit(ped, t, chair)
    Wait(600)
    -- look down at the board to start with; after that, you look where you like
    look.yaw, look.pitch = 0.0, boardPitch()
    Tables.camera()
    Nui.open(Tables.context())
  end)
end

function Tables.onStood(id)
  if me.id ~= id and id then return end
  Tables.log(("stood up from %s"):format(tostring(id)))
  me.id, me.chair = nil, nil
  cameraOff()
  ClearPedSecondaryTask(PlayerPedId())
  ClearPedTasks(PlayerPedId())
  Nui.close()
end

function Tables.stand()
  if not me.id then return end
  TriggerServerEvent('smashandclash:stand')
  Tables.onStood(me.id)
end

-------------------------------------------------------------------------------------------
-- the cursor

--- What the cursor (0..1 on screen) points at on your table.
function Tables.pick(x, y)
  local t = Tables.mine()
  if not t or not t.board then return nil end
  local hit = t.board:pick(Render, x, y)
  t.board.hover = hit
  return hit
end

-------------------------------------------------------------------------------------------
-- every frame: build what is near, draw the boards, offer the chairs

local function text3d(x, y, z, text, scale)
  SetDrawOrigin(x, y, z, 0)
  SetTextScale(0.0, scale or 0.36)
  SetTextFont(4)
  SetTextCentre(true)
  SetTextOutline()
  SetTextColour(255, 255, 255, 235)
  BeginTextCommandDisplayText('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(0.0, 0.0)
  ClearDrawOrigin()
end

local function help(text)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayHelp(0, false, false, -1)
end

-- a reach takes over the arms for a moment
local reaching = {}

-- Who sits in each chair of a table, as bodies in the world.
-- The body in a chair: a player, or the character who plays for an opponent not at the table.
local function pedAt(t, chair)
  local seat = t.def.seats[chair]
  if seat then
    if seat.id == myServerId then return PlayerPedId() end
    local player = GetPlayerFromServerId(seat.id)
    if player ~= -1 then return GetPlayerPed(player) end
    return nil
  end
  return t.npc and t.npc.chair == chair and t.npc.ped or nil
end

--- A hand reaching out: to lay a card on the board, or to take one from the deck.
local REACH = { 'mp_common', 'givetake1_a' }
function Tables.act(id, act)
  local t = list[id]
  if not t or not t.board or not act.seat then return end
  local ped = pedAt(t, t.board:chairOf(act.seat))
  if not ped or not DoesEntityExist(ped) then return end
  -- only your own body and the characters this client runs are animated here; other players
  -- animate themselves and the game shares it
  if ped ~= PlayerPedId() and not (t.npc and t.npc.ped == ped) then return end
  SetTimeout(math.max(0, (act.at or 0) - 120), function()
    if not DoesEntityExist(ped) then return end
    RequestAnimDict(REACH[1])
    local t0 = GetGameTimer()
    while not HasAnimDictLoaded(REACH[1]) and GetGameTimer() - t0 < 1500 do Wait(10) end
    if not HasAnimDictLoaded(REACH[1]) then return end
    -- 48 = upper body + secondary: the arm reaches, the seat keeps the legs
    reaching[ped] = GetGameTimer() + 1000
    TaskPlayAnim(ped, REACH[1], REACH[2], 6.0, 4.0, 900, 48, act.kind == 'draw' and 0.15 or 0.0, false, false, false)
  end)
end

-------------------------------------------------------------------------------------------
-- the character across the table

-- When the other side of a game is not in the chair across (the opponent at your level, or a
-- player on another app), a local character sits there and plays their cards.
local function wantsCharacter(t)
  local d = t.def
  if not d.game or not t.board then return nil end
  local a, b = d.seats.A, d.seats.B
  if a and not b then return 'B' end
  if b and not a then return 'A' end
  return nil
end

local function removeCharacter(t)
  if t.npc and t.npc.ped and DoesEntityExist(t.npc.ped) then DeleteEntity(t.npc.ped) end
  t.npc = nil
end

local function placeCharacter(t, chair)
  if t.npc and t.npc.chair == chair and DoesEntityExist(t.npc.ped) then return end
  removeCharacter(t)
  -- the same face for the same game, on every client
  local pick = 0
  for i = 1, #(t.def.game or '') do pick = (pick * 31 + t.def.game:byte(i)) % 1000003 end
  local models = Config.CharacterModels
  local model
  for k = 0, #models - 1 do
    local name = models[(pick + k) % #models + 1]
    if IsModelInCdimage(joaat(name)) then model = joaat(name) break end
  end
  if not model then return end
  t.npc = { chair = chair, loading = true }
  CreateThread(function()
    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t0 < 5000 do Wait(20) end
    if not HasModelLoaded(model) or not t.npc or t.npc.chair ~= chair then return end
    local pos, facing = chairSpot(t, chair)
    local ped = CreatePed(4, model, pos.x, pos.y, pos.z, facing, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    t.npc = { chair = chair, ped = ped }
    Tables.sit(ped, t, chair)
  end)
end

local function tendCharacter(t)
  local chair = wantsCharacter(t)
  if not chair then
    if t.npc then removeCharacter(t) end
    return
  end
  if not t.npc or (t.npc.chair ~= chair and not t.npc.loading) then placeCharacter(t, chair) end
end

-- GTA can stand a seated body up (a bump, a key): sit it back down.
CreateThread(function()
  while true do
    Wait(1500)
    local t = Tables.mine()
    local ped = PlayerPedId()
    if t and t.board and (reaching[ped] or 0) < GetGameTimer() and not IsPedUsingScenario(ped, Config.SitScenario) and not IsPedRagdoll(ped) then
      Tables.sit(ped, t, me.chair)
    end
  end
end)

-- build and clear props by distance, and tell the page which games to follow
CreateThread(function()
  while true do
    local p = GetEntityCoords(PlayerPedId())
    local nearby = {}
    for id, t in pairs(list) do
      local d = #(p - vector3(t.def.coords.x, t.def.coords.y, t.def.coords.z))
      if d < Config.SpawnDistance and not t.props then build(t)
      elseif d > Config.SpawnDistance + 15.0 and t.props then unbuild(t) end
      if t.props then tendCharacter(t) elseif t.npc then removeCharacter(t) end
      if d < Config.DrawDistance + 5.0 and id ~= me.id then
        nearby[#nearby + 1] = { id = id, game = t.def.game or nil, flip = t.def.flip or false }
      end
    end
    Nui.nearby(nearby)
    Wait(1000)
  end
end)

CreateThread(function()
  while true do
    local sleep = 500
    if Render.ready() then
      local ped = PlayerPedId()
      local p = GetEntityCoords(ped)
      local now = GetGameTimer()
      for _, t in pairs(list) do
        if t.board then
          local d = #(p - t.base)
          if d < Config.DrawDistance or me.id == t.def.id then
            sleep = 0
            t.board:draw(Render, now)
            -- the names at each chair, for whoever stands around
            if d < 9.0 and me.id ~= t.def.id then
              local v = t.view
              for _, chair in ipairs({ 'A', 'B' }) do
                local seat = (t.def.flip and (chair == 'A' and 'B' or 'A')) or chair
                local name = v and v.names and v.names[seat] or (t.def.seats[chair] and t.def.seats[chair].name)
                if name then
                  local x, y, z = t.board:namePoint(chair)
                  local score = v and v.score and v.score[seat]
                  text3d(x, y, z, score and ('%s  ~y~%d'):format(name, score) or name)
                end
              end
            end
            -- a free chair within reach
            if not me.id and d < 3.0 and not IsPedInAnyVehicle(ped, false) then
              for _, chair in ipairs({ 'A', 'B' }) do
                local pos = chairSpot(t, chair)
                if not t.def.seats[chair] and #(p - pos) < 1.4 then
                  help('~INPUT_CONTEXT~ Sit down and play ~b~Smash&Clash')
                  if IsControlJustPressed(0, 38) then TriggerServerEvent('smashandclash:sit', t.def.id, chair) end
                end
              end
            end
          end
        end
      end
    end
    Wait(sleep)
  end
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for _, t in pairs(list) do
    unbuild(t)
    if t.blip then RemoveBlip(t.blip) end
  end
  cameraOff()
  if me.id then ClearPedTasksImmediately(PlayerPedId()) end
end)

function Tables.isMe(serverId)
  return serverId == myServerId
end

return Tables
