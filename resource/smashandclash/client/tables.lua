-- The tables in the world: their props, the board drawn on each, sitting down, the camera while
-- you play, and what is under the cursor.

Tables = {}

local list = {}        -- id -> { def, props, board, blip }
local me = { id = nil, chair = nil }
local cam = nil
local camMode = 'seat' -- seat | top | first
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
  local obj = CreateObjectNoOffset(tableModel, d.coords.x, d.coords.y, z, false, false, false)
  SetEntityHeading(obj, d.heading)
  FreezeEntityPosition(obj, true)
  SetEntityInvincible(obj, true)
  local mn, mx = GetModelDimensions(tableModel)
  local w, depth = mx.x - mn.x, mx.y - mn.y
  t.base = vector3(d.coords.x, d.coords.y, z)
  t.depth = depth
  t.props = { obj }
  -- the board fills the top: 5 cards and gaps across, 3 rows and both hands deep
  local cardH = math.min(w * 0.9 / (5 * 0.7333 + 0.5), depth * 0.92 / 4.9)
  t.board = Board.new({ x = d.coords.x, y = d.coords.y, z = z + mx.z + 0.004 }, d.heading, cardH)
  if t.view then t.board:setView(t.view) end
  if chairModel then
    for _, chair in ipairs({ 'A', 'B' }) do
      local pos, facing = chairSpot(t, chair)
      local c = CreateObjectNoOffset(chairModel, pos.x, pos.y, pos.z, false, false, false)
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
  t.props, t.board = nil, nil
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
  if t and t.board then t.board:animate(steps, GetGameTimer()) end
end

-------------------------------------------------------------------------------------------
-- sitting down

function Tables.seated()
  return me.id ~= nil
end

function Tables.mine()
  return me.id and list[me.id]
end

local function camLookAt(pos, at)
  if not cam then cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true) end
  SetCamCoord(cam, pos.x, pos.y, pos.z)
  PointCamAtCoord(cam, at.x, at.y, at.z)
  SetCamFov(cam, camMode == 'first' and 62.0 or 50.0)
  SetCamActive(cam, true)
  RenderScriptCams(true, true, 600, true, true)
end

--- Point the camera for the chosen view: over your shoulder, from above, or your own eyes.
function Tables.camera(mode)
  if mode then camMode = mode end
  local t = Tables.mine()
  if not t or not t.board then return end
  local b = t.board
  -- offsets are written from chair A: negative y is towards your own chair
  local side = me.chair == 'A' and 1 or -1
  local _, ey = b:extents()
  local function at(x, y, z) local wx, wy, wz = b:world(x * side, y * side, z) return vector3(wx, wy, wz) end
  if camMode == 'top' then
    camLookAt(at(0, -0.12, b.H * 7.5), at(0, -0.02, 0))
  elseif camMode == 'first' then
    local head = GetPedBoneCoords(PlayerPedId(), 31086, 0.0, 0.0, 0.0)
    local eye = at(0, -(ey + b.H * 1.6), 0)
    camLookAt(vector3(eye.x, eye.y, head.z + 0.05), at(0, -b.H * 0.4, 0))
  else
    camLookAt(at(0, -(ey + b.H * 3.6), b.H * 4.6), at(0, -b.H * 0.35, 0))
  end
end

function Tables.cameraMode()
  return camMode
end

function Tables.cycleCamera()
  local nextMode = { seat = 'first', first = 'top', top = 'seat' }
  Tables.camera(nextMode[camMode])
  return camMode
end

local function cameraOff()
  if cam then
    RenderScriptCams(false, true, 600, true, true)
    DestroyCam(cam, false)
    cam = nil
  end
end

--- The server sat us down.
function Tables.onSeated(id, chair)
  local t = list[id]
  me.id, me.chair = id, chair
  if not t then return end
  CreateThread(function()
    local wait = GetGameTimer()
    while not t.board and GetGameTimer() - wait < 5000 do Wait(50) end
    local ped = PlayerPedId()
    local pos, facing = chairSpot(t, chair)
    ClearPedTasksImmediately(ped)
    TaskStartScenarioAtPosition(ped, Config.SitScenario, pos.x, pos.y, pos.z + Config.SeatHeight, facing, 0, true, true)
    Wait(400)
    Tables.camera()
    Nui.open(Tables.context())
  end)
end

function Tables.onStood(id)
  if me.id ~= id and id then return end
  me.id, me.chair = nil, nil
  cameraOff()
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

-- build and clear props by distance, and tell the page which games to follow
CreateThread(function()
  while true do
    local p = GetEntityCoords(PlayerPedId())
    local nearby = {}
    for id, t in pairs(list) do
      local d = #(p - vector3(t.def.coords.x, t.def.coords.y, t.def.coords.z))
      if d < Config.SpawnDistance and not t.props then build(t)
      elseif d > Config.SpawnDistance + 15.0 and t.props then unbuild(t) end
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
