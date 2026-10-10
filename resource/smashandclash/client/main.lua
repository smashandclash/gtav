-- The page (NUI) and the game, joined: the page runs Smash&Clash through the SDK and says what
-- each table shows; this script draws it in the world, seats the player, and passes the
-- cursor, controller and table events back and forth.

Nui = {}

local RES = GetCurrentResourceName()
local KVP = 'smashandclash:profile'
local focused = false
-- the panel is up (the lobby, or the game's HUD); while a game is in play the page gives the mouse
-- back to the game (focus off) and the game sends it what the player does
local panelOpen = false

local function send(msg)
  SendNUIMessage(msg)
end

-- The page's menus have the mouse, but the game keeps its input: hold the right mouse button to
-- look around (and V changes your view) with a menu open. While you type, the game hears nothing.
local typing = false
local looking, lookFrom = false, 0
local function setFocus(on)
  focused = on
  SetNuiFocus(on, on)
  SetNuiFocusKeepInput(on)
end

function Nui.open(ctx)
  panelOpen = true
  setFocus(true)
  send({ type = 'open', table = ctx })
end

function Nui.close()
  panelOpen = false
  setFocus(false)
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
  -- the players' hands play their part: a card played, a card drawn
  for _, act in ipairs(Tables.animate(d.table, d.steps) or {}) do Tables.act(d.table, act) end
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
  panelOpen = false
  setFocus(false)
end)

-- the page asks for the mouse for its menus, and gives it back while a game is in play
cb('focus', function(d)
  setFocus(d.on and true or false)
end)

cb('typing', function(d)
  typing = d.on and true or false
end)

cb('leaveTable', function()
  Tables.stand()
end)

cb('notify', function(d)
  if type(d.text) == 'string' then notify(d.text) end
end)

cb('tableGame', function(d)
  if d.gameId then Tables.lookAtBoard() end
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

-------------------------------------------------------------------------------------------
-- while a game is on: the mouse turns your head, the dot in the middle of your view points, a
-- click acts on what it points at (a card in front of you, a tile on the board)

local PLAY_KEYS = {
  { 14, 'scroll', 1 }, { 15, 'scroll', -1 }, { 24, 'select' }, { 25, 'cancel' }, { 22, 'stay' },
  { 200, 'menu' }, { 199, 'menu' }, { 177, 'menu' },
  { 157, 'key', '1' }, { 158, 'key', '2' }, { 160, 'key', '3' }, { 164, 'key', '4' }, { 165, 'key', '5' },
}
local lastAim = ''
local BLOCK = { 14, 15, 16, 17, 22, 24, 25, 37, 140, 141, 142, 143, 157, 158, 160, 164, 165, 177, 199, 200, 257, 263, 264 }

CreateThread(function()
  while true do
    if Tables.seated() and panelOpen and not focused then
      for _, c in ipairs(BLOCK) do DisableControlAction(0, c, true) end
      local hit = Tables.pick(0.5, 0.5)
      -- tell the page what the dot is on, when it changes, so the dot can show it
      local aim = hit and (hit.kind == 'tile' and ('tile:' .. hit.cell) or ('hand:' .. hit.index)) or ''
      if aim ~= lastAim then
        lastAim = aim
        send({ type = 'aim', kind = hit and hit.kind or nil, cell = hit and hit.cell or nil, index = hit and hit.index or nil })
      end
      for _, k in ipairs(PLAY_KEYS) do
        if IsDisabledControlJustPressed(0, k[1]) then
          local action, arg = k[2], k[3]
          if action == 'select' and hit then
            if hit.kind == 'tile' then action, arg = 'tile', hit.cell else action, arg = 'hand', hit.index end
          end
          send({ type = 'input', action = action, arg = arg })
        end
      end
      Wait(0)
    else
      Wait(150)
    end
  end
end)

-- /smash (F7): back to your table's panel, or a table of your own right here.
RegisterCommand(Config.Command, function()
  if Tables.seated() then
    panelOpen = true
    setFocus(true)
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

-- /smashlook: GTA's own camera for a moment while seated (to see yourself at the table), and back
RegisterCommand('smashlook', function()
  if not Tables.seated() then return end
  Tables.lookAround()
end, false)

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
      DisableControlAction(0, 30, true) -- move
      DisableControlAction(0, 31, true)
      DisableControlAction(0, 24, true) -- attack
      DisableControlAction(0, 25, true)
      DisableControlAction(0, 37, true) -- weapon wheel
      DisableControlAction(0, 44, true) -- cover
      DisableControlAction(0, 140, true) -- melee
      DisableControlAction(0, 141, true)
      DisableControlAction(0, 142, true)
      -- V: through your eyes, or GTA's camera behind you
      DisableControlAction(0, 0, true)
      if IsDisabledControlJustPressed(0, 0) and not typing then Tables.toggleView() end
      -- the mouse turns your head: always with the panel away, with it open while right-click is held
      Tables.freeLook = (not focused or looking) and not typing
      if focused or looking then
        if typing then
          DisableAllControlActions(0)
        else
          -- the panel's keys are its own: Esc is its menu, not GTA's pause menu
          for _, c in ipairs({ 199, 200, 245, 246, 249, 288, 289, 170, 166, 167, 168, 22, 23, 75 }) do DisableControlAction(0, c, true) end
          if not looking then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
          end
          -- hold the right mouse button to turn your head: the cursor goes until you let go; a
          -- quick click instead puts a picked card back
          if not looking and IsDisabledControlJustPressed(0, 25) then
            looking, lookFrom = true, GetGameTimer()
            SetNuiFocus(false, false)
          elseif looking and not IsDisabledControlPressed(0, 25) then
            looking = false
            if panelOpen then SetNuiFocus(true, true) end
            if GetGameTimer() - lookFrom < 250 then send({ type = 'input', action = 'cancel' }) end
          end
        end
      end
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
  if focused then SetNuiFocus(false, false) SetNuiFocusKeepInput(false) end
  Render.stop()
end)
