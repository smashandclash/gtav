-- Smash&Clash tables: where they stand, what they are made of, and how players use them.

Config = {}

-- Tables placed on the map. Add your own in game with /smashtable (needs the
-- command.smashtable ace) or here: coords are the ground under the table's centre, heading is
-- the way chair A faces. Anyone can also put down a table of their own with /smash.
Config.Tables = {
  { id = 'legion', label = 'Legion Square', coords = vector3(195.2, -933.9, 30.69), heading = 145.0 },
  { id = 'pier', label = 'Del Perro Pier', coords = vector3(-1631.8, -1012.9, 13.12), heading = 50.0 },
}

-- The first model the game has wins. Tables near 1 m across fit the board best.
Config.TableModels = { 'prop_table_04', 'prop_table_03', 'prop_chateau_table_01', 'prop_table_02' }
Config.ChairModels = { 'prop_table_04_chr', 'prop_table_03_chr', 'prop_chateau_chair_01', 'prop_chair_01a' }
-- Chair props face away from where they point; turn them round so they face the table.
Config.ChairTurn = 180.0
-- How far a chair stands out from the table's edge, and how high its seat is.
Config.ChairGap = 0.42
Config.SeatHeight = 0.5
Config.SitScenario = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER'
-- Who sits across when the other player is not at the table (the opponent at your level, or a
-- player on another app). The first the game has, picked by the game, so everyone sees the same.
Config.CharacterModels = {
  'a_m_y_hipster_01', 'a_f_y_hipster_02', 'a_m_y_business_02', 'a_f_y_business_01',
  'a_m_y_vinewood_01', 'a_f_y_tourist_01', 'a_m_y_stbla_01', 'a_f_y_bevhills_01',
}

-- Tables are built within this distance, and the board is drawn within the second.
Config.SpawnDistance = 90.0
Config.DrawDistance = 28.0

-- A table made with /smash goes away this long after both chairs are empty.
Config.TempTableSeconds = 90

-- The command and default key that sit you at a table of your own (rebind in GTA's settings,
-- Key Bindings > FiveM).
Config.Command = 'smash'
Config.Key = 'F7'

-- Tables of your own (/smash, F7): on for everyone, or only for players with the
-- `smashandclash.own` ace (add_ace group.vip smashandclash.own allow) when OwnTableAce is true.
Config.OwnTables = true
Config.OwnTableAce = false
-- At most this many tables of your own on the server at once (placed tables don't count).
Config.MaxOwnTables = 24

-- Each player's calls to smashandclash.in go through this server: per player, and for the whole
-- server together, per minute. A game uses a few calls a move; the defaults leave plenty of room.
Config.RequestsPerPlayer = 90
Config.RequestsPerServer = 1500

-- Say in the server console when a newer version of this resource is out.
Config.CheckForUpdates = true

-- Diagnostics in the server console (sitting, tables). Off unless you're chasing a problem.
Config.Debug = false

-- Show the tables on the map.
Config.Blips = true
Config.BlipSprite = 680 -- radar_casino_table_games
Config.BlipColour = 38
