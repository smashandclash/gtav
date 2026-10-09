-- The tables, kept by the server: who sits in which chair and which game is on, so every
-- player sees the same table. The game itself never passes through here: each player's own
-- client plays it on the Smash&Clash game network. The server only hands a room code from one
-- chair to the other.

local tables = {}     -- id -> table
local seatOf = {}     -- player -> { id, chair }
local KVP = 'smashandclash:tables'

local function other(chair) return chair == 'A' and 'B' or 'A' end

local function playerName(src)
  local n = GetPlayerName(src)
  return (n and n ~= '') and n:sub(1, 24) or ('Player ' .. tostring(src))
end

--- What clients get: never a player's server id beyond the chairs, never a game token.
local function public(t)
  local seats = {}
  for _, chair in ipairs({ 'A', 'B' }) do
    local src = t.seats[chair]
    seats[chair] = src and { name = playerName(src), id = src } or false
  end
  return {
    id = t.id,
    label = t.label,
    coords = { x = t.coords.x, y = t.coords.y, z = t.coords.z },
    heading = t.heading,
    temp = t.temp or false,
    seats = seats,
    game = t.game or false,
    flip = t.flip or false,
  }
end

local function broadcast(t)
  TriggerClientEvent('smashandclash:table', -1, public(t))
end

local function addTable(def)
  local t = {
    id = def.id,
    label = def.label or 'Smash&Clash table',
    coords = vector3(def.coords.x, def.coords.y, def.coords.z),
    heading = def.heading or 0.0,
    temp = def.temp,
    owner = def.owner,
    seats = {},
    emptySince = os.time(),
  }
  tables[t.id] = t
  broadcast(t)
  return t
end

local function removeTable(id)
  local t = tables[id]
  if not t then return end
  for _, chair in ipairs({ 'A', 'B' }) do
    local src = t.seats[chair]
    if src then
      seatOf[src] = nil
      TriggerClientEvent('smashandclash:stood', src, id)
    end
  end
  tables[id] = nil
  TriggerClientEvent('smashandclash:tableGone', -1, id)
end

local function saved()
  local text = GetResourceKvpString(KVP)
  local ok, list = pcall(json.decode, text or '[]')
  return (ok and type(list) == 'table') and list or {}
end

CreateThread(function()
  for _, def in ipairs(Config.Tables) do addTable(def) end
  for _, def in ipairs(saved()) do
    if def.id and def.coords then addTable({ id = def.id, label = def.label, coords = def.coords, heading = def.heading }) end
  end
end)

local function stand(src)
  local s = seatOf[src]
  if not s then return end
  seatOf[src] = nil
  local t = tables[s.id]
  if not t then return end
  t.seats[s.chair] = nil
  if not t.seats.A and not t.seats.B then
    t.game, t.flip = nil, nil
    t.emptySince = os.time()
  end
  broadcast(t)
end

local function near(src, t, metres)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return true end -- without OneSync the server cannot see peds
  local p = GetEntityCoords(ped)
  if p.x == 0.0 and p.y == 0.0 then return true end
  return #(p - t.coords) <= metres
end

local function sit(src, id, chair)
  local t = tables[id]
  if not t or (chair ~= 'A' and chair ~= 'B') then return false end
  if t.seats[chair] and t.seats[chair] ~= src then return false end
  if not near(src, t, 6.0) then return false end
  stand(src)
  t.seats[chair] = src
  seatOf[src] = { id = id, chair = chair }
  TriggerClientEvent('smashandclash:seated', src, id, chair)
  broadcast(t)
  return true
end

RegisterNetEvent('smashandclash:hello', function()
  local src = source
  local list = {}
  for _, t in pairs(tables) do list[#list + 1] = public(t) end
  TriggerClientEvent('smashandclash:tables', src, list)
end)

RegisterNetEvent('smashandclash:sit', function(id, chair)
  local src = source
  if not sit(src, id, chair) then TriggerClientEvent('smashandclash:sitRefused', src, id) end
end)

RegisterNetEvent('smashandclash:stand', function()
  stand(source)
end)

-- /smash: a table of your own, where you stand. One per player.
RegisterNetEvent('smashandclash:ownTable', function(x, y, z, heading)
  local src = source
  if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
  local id = 'own-' .. tostring(src)
  if tables[id] then removeTable(id) end
  local t = addTable({ id = id, label = ("%s's table"):format(playerName(src)), coords = vector3(x, y, z), heading = (heading or 0.0) + 0.0, temp = true, owner = src })
  if not near(src, t, 8.0) then return removeTable(id) end
  sit(src, id, 'A')
end)

-- The game a seated player has on: the table follows it for everyone around. `seat` is the
-- player's seat in that game, so the board turns to put their side at their chair.
RegisterNetEvent('smashandclash:tableGame', function(gameId, seat)
  local src = source
  local s = seatOf[src]
  if not s then return end
  local t = tables[s.id]
  if type(gameId) ~= 'string' or not gameId:match('^g_[%w_%-]+$') then gameId = nil end
  t.game = gameId
  t.flip = gameId and ((seat == 'A') ~= (s.chair == 'A')) or nil
  broadcast(t)
end)

-- A room for the player across the table: the code goes to them, and only to them.
RegisterNetEvent('smashandclash:tableRoom', function(code)
  local src = source
  local s = seatOf[src]
  if not s or type(code) ~= 'string' or not code:match('^%w%w%w%w%w%w$') then return end
  local across = tables[s.id].seats[other(s.chair)]
  if across then TriggerClientEvent('smashandclash:tableRoom', across, code:upper(), playerName(src)) end
end)

RegisterNetEvent('smashandclash:tableDecline', function()
  local src = source
  local s = seatOf[src]
  if not s then return end
  local across = tables[s.id].seats[other(s.chair)]
  if across then TriggerClientEvent('smashandclash:tableDeclined', across, playerName(src)) end
end)

-- /smashtable [label]: a permanent table where you stand (saved across restarts).
RegisterCommand('smashtable', function(src, args)
  if src == 0 then return print('Run /smashtable in game, where the table should go.') end
  local ped = GetPlayerPed(src)
  local p = GetEntityCoords(ped)
  local id = ('t%d'):format(os.time())
  local label = #args > 0 and table.concat(args, ' ') or 'Smash&Clash table'
  local def = { id = id, label = label, coords = { x = p.x, y = p.y, z = p.z - 1.0 }, heading = GetEntityHeading(ped) }
  local list = saved()
  list[#list + 1] = def
  SetResourceKvp(KVP, json.encode(list))
  addTable({ id = id, label = label, coords = vector3(def.coords.x, def.coords.y, def.coords.z), heading = def.heading })
  TriggerClientEvent('smashandclash:notify', src, ('Table "%s" placed.'):format(label))
end, true)

-- /smashtable_remove: take away the saved table nearest you.
RegisterCommand('smashtable_remove', function(src)
  if src == 0 then return end
  local p = GetEntityCoords(GetPlayerPed(src))
  local list, best, bestD = saved(), nil, 6.0
  for i, def in ipairs(list) do
    local d = #(p - vector3(def.coords.x, def.coords.y, def.coords.z))
    if d < bestD then best, bestD = i, d end
  end
  if not best then return TriggerClientEvent('smashandclash:notify', src, 'No saved table within 6 m.') end
  local id = list[best].id
  table.remove(list, best)
  SetResourceKvp(KVP, json.encode(list))
  removeTable(id)
end, true)

AddEventHandler('playerDropped', function()
  local src = source
  stand(src)
  local own = tables['own-' .. tostring(src)]
  if own then removeTable(own.id) end
end)

-- tables of one's own go away once nobody has sat at them for a while
CreateThread(function()
  while true do
    Wait(15000)
    local now = os.time()
    for id, t in pairs(tables) do
      if t.temp and not t.seats.A and not t.seats.B and now - (t.emptySince or now) > Config.TempTableSeconds then removeTable(id) end
    end
  end
end)
