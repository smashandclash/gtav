// smashandclash.zip: the resource as a server owner installs it (resources/smashandclash), with the
// built page in it, so nobody needs Node. Run after `npm run build`.
import { execFileSync } from 'node:child_process';
import { existsSync, rmSync } from 'node:fs';

if (!existsSync('resource/smashandclash/html/index.html')) throw new Error('Build the page first: npm run build');
rmSync('smashandclash.zip', { force: true });
// Windows' own tar (bsdtar) writes a real zip; elsewhere use zip
const win = process.platform === 'win32';
if (win) execFileSync('C:/Windows/System32/tar.exe', ['-a', '-c', '-f', '../smashandclash.zip', 'smashandclash'], { cwd: 'resource', stdio: 'inherit' });
else execFileSync('zip', ['-qr', '../smashandclash.zip', 'smashandclash'], { cwd: 'resource', stdio: 'inherit' });
console.log('smashandclash.zip');
