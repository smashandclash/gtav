fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'smashandclash'
author 'Smash&Clash'
description 'Smash&Clash at tables in Los Santos: sit down and play anyone on any Smash&Clash client, through the Smash&Clash SDK'
version '1.0.0'
repository 'https://github.com/smashandclash/gtav'

shared_script 'shared/config.lua'

client_scripts {
  'client/board.lua',
  'client/render.lua',
  'client/tables.lua',
  'client/main.lua',
}

server_scripts {
  'server/main.lua',
  'server/http.lua',
  'server/version.lua',
}

ui_page 'html/index.html'

-- the page, its scripts, and the art and sound the game ships (nothing loads from the website)
files {
  'html/**/*',
}
