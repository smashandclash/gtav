// The server script, run in Lua 5.4 with FiveM's functions stood in: seating, the room code that
// goes only to the player across the table, the game a table shows, and tables of one's own.

import { readFileSync } from 'node:fs';
import { LuaFactory, type LuaEngine } from 'wasmoon';
import { beforeEach, describe, expect, it } from 'vitest';

const read = (p: string) => readFileSync(new URL(`../resource/smashandclash/${p}`, import.meta.url), 'utf8');

const STUBS = `
SENT = {}
HANDLERS = {}
THREADS = {}
COMMANDS = {}
KVP = {}
POS = {}
NAMES = {}
local vmeta = {}
vmeta.__index = vmeta
vmeta.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
json = { encode = function() return '[]' end, decode = function() return {} end }
function CreateThread(fn) THREADS[#THREADS + 1] = fn end
function Wait() end
function TriggerClientEvent(name, target, ...) SENT[#SENT + 1] = { name = name, target = target, args = { ... } } end
function RegisterNetEvent(name, fn) HANDLERS[name] = fn end
function AddEventHandler(name, fn) HANDLERS[name] = fn end
function RegisterCommand(name, fn) COMMANDS[name] = fn end
function GetPlayerName(src) return NAMES[src] or ('p' .. src) end
function GetPlayerPed(src) return src end
function GetEntityCoords(ped) return POS[ped] or vector3(0, 0, 0) end
function GetEntityHeading() return 0.0 end
function GetResourceKvpString(k) return KVP[k] end
function SetResourceKvp(k, v) KVP[k] = v end
function fire(name, src, ...) source = src HANDLERS[name](...) end
function sent(name, target)
  local out = {}
  for _, s in ipairs(SENT) do if s.name == name and (target == nil or s.target == target) then out[#out + 1] = s end end
  return out
end
`;

let lua: LuaEngine;
const run = (code: string) => lua.doString(code);

beforeEach(async () => {
  lua = await new LuaFactory().createEngine();
  await run(STUBS);
  await run(read('shared/config.lua'));
  await run(`Config.Tables = { { id = 't1', label = 'Test', coords = vector3(10, 10, 0), heading = 0.0 } }`);
  await run(read('server/main.lua'));
  await run(`for _, t in ipairs(THREADS) do if t ~= THREADS[#THREADS] then t() end end`);
  await run(`POS[1] = vector3(10, 11, 0) POS[2] = vector3(10, 9, 0) POS[3] = vector3(500, 500, 0) NAMES[1] = 'Franklin' NAMES[2] = 'Lamar'`);
});

describe('tables on the server', () => {
  it('seats a player who is near, and refuses one far away or a taken chair', async () => {
    await run(`fire('smashandclash:sit', 1, 't1', 'A')`);
    expect(await run(`return #sent('smashandclash:seated', 1)`)).toBe(1);
    await run(`fire('smashandclash:sit', 2, 't1', 'A')`);
    expect(await run(`return #sent('smashandclash:sitRefused', 2)`)).toBe(1);
    await run(`fire('smashandclash:sit', 3, 't1', 'B')`);
    expect(await run(`return #sent('smashandclash:sitRefused', 3)`)).toBe(1);
  });

  it('hands a room code to the player across, and only to them', async () => {
    await run(`fire('smashandclash:sit', 1, 't1', 'A') fire('smashandclash:sit', 2, 't1', 'B')`);
    await run(`fire('smashandclash:tableRoom', 1, 'k7qf2m')`);
    const got = await run(`local s = sent('smashandclash:tableRoom') return s[1].target .. ':' .. s[1].args[1] .. ':' .. s[1].args[2] .. ':' .. #s`);
    expect(got).toBe('2:K7QF2M:Franklin:1');
    await run(`fire('smashandclash:tableRoom', 1, 'nope!!')`);
    expect(await run(`return #sent('smashandclash:tableRoom')`)).toBe(1);
  });

  it('turns the board when the player at chair A holds game seat B', async () => {
    await run(`fire('smashandclash:sit', 1, 't1', 'A') fire('smashandclash:tableGame', 1, 'g_abc-1', 'B')`);
    const t = await run(`local s = sent('smashandclash:table') local t = s[#s].args[1] return tostring(t.game) .. ':' .. tostring(t.flip)`);
    expect(t).toBe('g_abc-1:true');
    await run(`fire('smashandclash:tableGame', 1, 'not a game', 'A')`);
    expect(await run(`local s = sent('smashandclash:table') return tostring(s[#s].args[1].game)`)).toBe('false');
  });

  it('frees the chair and the game when everyone gets up', async () => {
    await run(`fire('smashandclash:sit', 1, 't1', 'A') fire('smashandclash:tableGame', 1, 'g_x', 'A') fire('smashandclash:stand', 1)`);
    const t = await run(`local s = sent('smashandclash:table') local t = s[#s].args[1] return tostring(t.seats.A) .. ':' .. tostring(t.game)`);
    expect(t).toBe('false:false');
  });

  it('puts down a table of your own and sits you at it', async () => {
    await run(`fire('smashandclash:ownTable', 3, 500, 501, 0, 90.0)`);
    expect(await run(`local s = sent('smashandclash:seated', 3) return s[1].args[1] .. ':' .. s[1].args[2]`)).toBe('own-3:A');
    await run(`fire('playerDropped', 3)`);
    expect(await run(`return sent('smashandclash:tableGone')[1].args[1]`)).toBe('own-3');
  });
});
