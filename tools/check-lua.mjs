// Compiles every Lua file in the resource with Lua 5.4 (the version FiveM runs with lua54 'yes'),
// so a syntax error is caught before a server owner starts the resource.
//   node tools/check-lua.mjs

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LuaFactory } from 'wasmoon';

const root = fileURLToPath(new URL('..', import.meta.url));
const dirs = [join(root, 'resource'), join(root, 'nui', 'src', 'sim')];

const files = [];
const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      if (name !== 'html' && name !== 'node_modules') walk(p);
    } else if (name.endsWith('.lua')) files.push(p);
  }
};
dirs.forEach(walk);

const lua = await new LuaFactory().createEngine();
let failed = 0;
for (const file of files) {
  lua.global.set('SRC', readFileSync(file, 'utf8'));
  lua.global.set('NAME', '@' + relative(root, file));
  const err = await lua.doString('local f, err = load(SRC, NAME, "t") return err');
  if (err) {
    failed++;
    console.error(`✗ ${err}`);
  } else console.log(`✓ ${relative(root, file)}`);
}
lua.global.close();
if (failed) process.exit(1);
