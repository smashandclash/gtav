-- The page (NUI) and the game, joined: the page runs Smash&Clash through the SDK and says what
-- each table shows; this script draws it in the world, seats the player, and passes the
-- cursor, controller and table events back and forth.

Nui = {}

local RES = GetCurrentResourceName()
local KVP = 'smashandclash:profile'
local focused = false

local function send(msg)
  SendNUIMessage(msg)
end

function Nui.open(ctx)
  focused = true
  SetNuiFocus(true, true)
  send({ type = 'open', table = ctx })
end

function Nui.close()
  focused = false
  SetNuiFocus(false, false)
  send({ type = 'hide' })
end

function Nui.table(ctx)
  send({ type = 'table', table = ctx })
end

local lastNearby = ''
function Nui.nearby(list)
  local text = json.encode(list)
  if text == lastNearby then return end
  lastNearby = text
  send({ type = 'nearby', tables = list })
end

local function notify(text)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName('~b~Smash&Clash~s~  ' .. text)
  EndTextCommandThefeedPostTicker(false, true)
end

-------------------------------------------------------------------------------------------
-- the page's calls

local function cb(name, fn)
  RegisterNUICallback(name, function(data, reply)
    local ok, out = pcall(fn, data or {})
    if not ok then print(('^1[smashandclash] %s: %s^0'):format(name, out)) end
    reply(out or { ok = ok })
  end)
end

-- The SDK's calls to smashandclash.in, through the server (see server/http.lua): answered later.
local pending, nextId = {}, 0
RegisterNUICallback('http', function(data, reply)
  nextId = nextId + 1
  pending[nextId] = reply
  TriggerServerEvent('smashandclash:http', nextId, data.url, data.method, data.headers, data.body)
  local id = nextId
  SetTimeout(30000, function()
    local r = pending[id]
    if r then pending[id] = nil r({ status = 0, error = 'timeout' }) end
  end)
end)
RegisterNetEvent('smashandclash:httpResult', function(id, res)
  local r = pending[id]
  if not r then return end
  pending[id] = nil
  r(res)
end)

cb('ready', function()
  return { name = GetPlayerName(PlayerId()), profile = GetResourceKvpString(KVP) }
end)

cb('saveProfile', function(d)
  if type(d.profile) == 'string' and #d.profile < 8000 then SetResourceKvp(KVP, d.profile) end
end)

cb('cards', function(d)
  if type(d.ids) == 'table' then Render.setCards(d.ids) end
end)

cb('view', function(d)
  if type(d.table) == 'string' then Tables.view(d.table, d.view) end
end)

cb('move', function(d)
  if type(d.table) ~= 'string' then return end
  if d.view then Tables.view(d.table, d.view) end
  Tables.animate(d.table, d.steps)
end)

cb('pointer', function(d)
  local hit = Tables.pick(tonumber(d.x) or -1, tonumber(d.y) or -1)
  return { hit = hit or false }
end)

cb('camera', function(d)
  if d.mode then Tables.camera(d.mode) else Tables.cycleCamera() end
  return { mode = Tables.cameraMode() }
end)

cb('close', function()
  -- the panel goes away, the player stays seated; F7 (or /smash) brings it back
  focused = false
  SetNuiFocus(false, false)
end)

cb('leaveTable', function()
  Tables.stand()
end)

cb('notify', function(d)
  if type(d.text) == 'string' then notify(d.text) end
end)

cb('tableGame', function(d)
  TriggerServerEvent('smashandclash:tableGame', d.gameId, d.seat)
end)

cb('tableRoom', function(d)
  TriggerServerEvent('smashandclash:tableRoom', d.code)
end)

cb('tableDecline', function()
  TriggerServerEvent('smashandclash:tableDecline')
end)

-------------------------------------------------------------------------------------------
-- the server's news

RegisterNetEvent('smashandclash:tables', function(defs)
  for _, def in ipairs(defs) do Tables.update(def) end
end)
RegisterNetEvent('smashandclash:table', function(def) Tables.update(def) end)
RegisterNetEvent('smashandclash:tableGone', function(id)
  if Tables.mine() and Tables.mine().def.id == id then Tables.onStood(id) end
  Tables.remove(id)
end)
RegisterNetEvent('smashandclash:seated', function(id, chair) Tables.onSeated(id, chair) end)
RegisterNetEvent('smashandclash:stood', function(id) Tables.onStood(id) end)
RegisterNetEvent('smashandclash:sitRefused', function() notify('That chair is taken.') end)
RegisterNetEvent('smashandclash:tableRoom', function(code, from) send({ type = 'tableRoom', code = code, from = from }) end)
RegisterNetEvent('smashandclash:tableDeclined', function(from) send({ type = 'tableDeclined', from = from }) end)
RegisterNetEvent('smashandclash:notify', function(text) notify(text) end)

-------------------------------------------------------------------------------------------
-- playing

-- /smash (F7): back to your table's panel, or a table of your own right here.
RegisterCommand(Config.Command, function()
  if Tables.seated() then
    focused = true
    SetNuiFocus(true, true)
    send({ type = 'open', table = Tables.context() })
    return
  end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsEntityDead(ped) then return notify('Find a spot on foot first.') end
  local p = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, 0.0)
  local ok, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)
  -- chair A faces the table: put it where you stand
  TriggerServerEvent('smashandclash:ownTable', p.x, p.y, ok and gz or p.z - 1.0, GetEntityHeading(ped))
end, false)
RegisterKeyMapping(Config.Command, 'Play Smash&Clash', 'keyboard', Config.Key)

-- a controller drives the panel with the D-pad, A and B, and LB / RB through the hand
local PAD = { { 172, 'up' }, { 173, 'down' }, { 174, 'left' }, { 175, 'right' }, { 201, 'accept' }, { 202, 'back' }, { 205, 'lb' }, { 206, 'rb' } }
CreateThread(function()
  while true do
    if focused and not IsUsingKeyboard(2) then
      for _, p in ipairs(PAD) do
        if IsDisabledControlJustPressed(2, p[1]) then send({ type = 'pad', button = p[2] }) end
      end
      Wait(0)
    else
      Wait(250)
    end
  end
end)

-- while seated, keep the player in the chair and the game's own HUD out of the way
CreateThread(function()
  while true do
    if Tables.seated() then
      HideHudAndRadarThisFrame()
      -- your own body would sit between your eyes and the table: on your screen it is hidden (everyone
      -- else still sees you sitting there, holding your cards)
      SetEntityLocallyInvisible(PlayerPedId())
      DisableControlAction(0, 30, true) -- move
      DisableControlAction(0, 31, true)
      DisableControlAction(0, 24, true) -- attack
      DisableControlAction(0, 25, true)
      DisableControlAction(0, 37, true) -- weapon wheel
      Wait(0)
    else
      Wait(400)
    end
  end
end)

CreateThread(function()
  Render.start(RES)
  TriggerServerEvent('smashandclash:hello')
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= RES then return end
  if focused then SetNuiFocus(false, false) end
  Render.stop()
end)
