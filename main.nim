# Nimboy imports
import debugger
import gameboy
import sdl2
import os
import ppu
import sdl

proc main =
  #let gbRenderer = getRenderer("Nimboy", 160,144)
  let tileMapRenderer = getRenderer("Tile Data", 256, 256) # 192 for all sprites

  # Game loop, draws each frame
  var gb = newGameboy()
  var debugger = newDebugger()
  while true:
    #sleep(100)
    #gbRenderer.clear()
    #gbRenderer.step(gb.ppu)
    #gbRenderer.present()

    tileMapRenderer.clear()
    #tileMapRenderer.renderMgbTileMap(gb.ppu)
    tileMapRenderer.drawTestTile(gb.ppu)
    tileMapRenderer.present()
    debug(gb, debugger)

main()
