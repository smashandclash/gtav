# Smash&Clash in GTA V

Smash&Clash at tables in Los Santos. Sit down, and the board lies on the table in front of you as a real object: the cream wooden board from [smashandclash.in](https://www.smashandclash.in), its tiles, chess and power tiles, every card in its owner's colour, your hand standing at your edge. Cards drop onto the board, flip when they're captured, hop off chess tiles and crumble under a Boulder. Anyone walking past sees the game play out.

It's a [FiveM](https://fivem.net) resource. Every game goes through the [Smash&Clash SDK](https://docs.smashandclash.in), so a player at a table in GTA plays the same game network as everyone else: the website, Telegram, the terminal, a Nintendo DS. Rooms, codes and quick match work across all of them.

## What you can do

- **Sit at a table** (E at a free chair) and press **PLAY** for a game now, against a player at your level.
- **Quick match**: the queue every Smash&Clash app shares.
- **Play a friend**: make a room and give its code to anyone, on any app, or join theirs.
- **Play the person across the table**: when someone sits opposite, a button opens a game for them; they accept on their screen.
- **`/smash`** (F7) puts down a table of your own where you stand. F7 also brings your panel back when you're seated.
- **Views**: over your shoulder with your hand on screen, through your own eyes with your cards standing in front of you, or from above.
- Mutators and Classic, your rating (kept per server), the Game Review after each game, the game's music, effects, announcer and character voices.
- Mouse, keyboard (arrows / WASD, Enter, 1 to 5, Esc) and controller (D-pad, A, B, LB / RB).

## Install (server owners)

Works on FiveM for GTA V Legacy and the FiveM for GTAV Enhanced early access. It uses no streamed assets, so nothing needs converting.

1. Copy `resource/smashandclash` into your server's `resources` folder.
2. Add `ensure smashandclash` to `server.cfg`.
3. Optional: give admins `add_ace group.admin command.smashtable allow` so they can place permanent tables with `/smashtable [name]` (and take one away with `/smashtable_remove`).

The tables, their models, the key and the map blips are set in [`shared/config.lua`](resource/smashandclash/shared/config.lua).

Players need an internet connection: the game runs on www.smashandclash.in.

## Try it on your own PC

1. Install **FiveM for GTAV Enhanced** from [fivem.net](https://fivem.net) (the "Download FiveM for GTAV Enhanced" button). You need GTA V Enhanced on PC.
2. Get a free server licence key at [portal.cfx.re](https://portal.cfx.re).
3. Download the **Cfx Server** for Windows from the official server download page, platform "FiveM for GTAV Enhanced".
4. Put this resource in the server's `resources` folder, `ensure smashandclash` and your key (`sv_licenseKey`) in `server.cfg`, and start `cfx-server.exe`.
5. In FiveM, connect to `localhost`. Walk to the blip at Legion Square, or press F7 anywhere.

## Develop

```bash
npm install
```

```bash
npm run dev
```

The dev page (http://localhost:5394) runs the client in a browser and previews the table: the resource's own `client/board.lua` runs in a Lua 5.4 VM and draws on a canvas. That lets you check the board and animations without starting GTA. `?name=` gives each tab its own player.

```bash
npm run check
```

Type-checks, runs the tests (the server script runs in Lua with FiveM's functions stubbed) and compiles every Lua file. `npm run build` writes the page into `resource/smashandclash/html`.

## How it fits together

| Part | Does |
| --- | --- |
| `nui/` (the page) | Runs the game through `@smashandclash/sdk`, shows the panel and HUD, follows nearby tables' games as a spectator, and tells the resource what each board shows (`view.ts`) and how each move plays out |
| `client/board.lua` | Draws a board: tiles, cards, hands and every animation, as textured polygons in the world. Picks what the cursor points at |
| `client/render.lua` | GTA's side of drawing: the atlas (one DUI page with every card face and sprite) and the strike drawings |
| `client/tables.lua` | Tables, chairs, sitting down, the cameras |
| `server/main.lua` | Who sits where, which game each table shows, and the room code from one chair to the other. The game itself never passes through it |

Each player plays from their own client: their seat's token stays in their game. Spectators get only what anyone at the table could see: the board, and hands as counts.

## Licence

The code is MIT. The characters, art, audio and the Smash&Clash name stay Smash&Clash's: they're free to use in clients built for Smash&Clash, never to present as your own ([terms](https://www.smashandclash.in/terms#developers)).

GTA V and FiveM belong to Rockstar Games and Cfx.re. This resource follows Rockstar's mod guidelines: it's free and non-commercial.
