// Smash&Clash at a table in GTA V: this page (NUI) runs the game through the Smash&Clash SDK,
// shows the panel and HUD, and tells the resource what each table's 3D board shows.

import './tokens.css';
import './styles.css';
import { inGame, onGameMessage, post, setStandIn, standInTable, type Hello } from './bridge';
import { Controller } from './controller';
import { readProfile } from './profile';
import { Spectator } from './spectate';
import { UI } from './ui';

async function start(): Promise<void> {
  const ui = new UI();
  const hello = await post<Hello>('ready').catch(() => ({ name: 'Player', profile: null }) as Hello);
  const ctl = new Controller(readProfile(hello.profile), ui);
  ui.attach(ctl);
  const spectator = new Spectator(ctl.sc, () => ctl.cards, () => ctl.kit?.colors ?? {});
  // the dev page's test handle (never in the build)
  if (import.meta.env.DEV) (window as unknown as { __snc: unknown }).__snc = { ui, ctl };

  onGameMessage((m) => {
    switch (m.type) {
      case 'open':
        ctl.setTable(m.table);
        ui.show();
        break;
      case 'hide':
        ui.hide();
        break;
      case 'table':
        ctl.setTable(m.table);
        break;
      case 'tableRoom':
        ctl.receiveOffer({ code: m.code, from: m.from });
        break;
      case 'tableDeclined':
        ctl.offerDeclined(m.from);
        break;
      case 'nearby':
        spectator.update(m.tables.map((t) => ({ id: t.id, game: t.game || null, flip: !!t.flip })));
        break;
      case 'pad':
        if (ctl.visible) ui.nav.pad(m.button);
        break;
    }
  });

  // In a browser (npm run dev) there is no game: sit at a preview table now, and bring the panel
  // back when it is hidden.
  if (!inGame || hello.standalone) {
    document.body.classList.add('standalone');
    // the table in a browser: the resource's board.lua, run in a Lua VM and drawn on a canvas
    const canvas = document.createElement('canvas');
    canvas.className = 'sim';
    document.body.prepend(canvas);
    const sim = import.meta.env.DEV ? await (await import('./sim/sim')).createSim(canvas) : null;
    if (sim) (window as unknown as { __snc: Record<string, unknown> }).__snc.sim = sim;
    if (sim) setStandIn((event, d) => {
      if (event === 'view') return sim.view(String(d.table), d.view), { ok: true };
      if (event === 'move') return sim.move(String(d.table), d.steps as unknown[], d.view), { ok: true };
      if (event === 'pointer') return { hit: sim.pick(Number(d.x), Number(d.y)) };
      if (event === 'camera') return { mode: sim.camera(d.mode as string | undefined) };
      if (event === 'cards') return sim.cards(d.ids as number[]), { ok: true };
      return undefined;
    });
    ctl.setTable(standInTable());
    const reopen = document.createElement('button');
    reopen.className = 'candy sun dev-reopen';
    reopen.innerHTML = '<span>Show the panel</span>';
    reopen.hidden = true;
    reopen.onclick = () => {
      reopen.hidden = true;
      ui.show();
    };
    document.body.append(reopen);
    document.addEventListener('snc:standin-closed', () => setTimeout(() => (reopen.hidden = false), 220));
    ui.show();
  }

  try {
    await ctl.boot(hello.name);
  } catch (e) {
    console.error(e);
    ctl.screen = 'lobby';
    ctl.say('Could not reach smashandclash.in. Check your connection, then try again.', 'error', 8000);
  }
  ui.sound.setKit(ctl.kit?.audio ?? null);
  // the atlas lays the cards out by id; the table in the world needs the same order
  void post('cards', { ids: [...ctl.cards.keys()] });
  void post('booted');
}

void start();
