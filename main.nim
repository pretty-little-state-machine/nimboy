# Nimboy imports
import debugger
import gameboy
import cartridge
import sdl2
import os
import ppu
import sdl

proc main =
  #let gbRenderer = getRenderer("Nimboy", 160,144)
  let tileMapRenderer = getRenderer("Tile Data", 256, 256) # 192 for all sprites

  # Game loop, draws each frame
  var 
    gb = newGameboy()
    debugger = newDebugger()
    running = true
    evt = sdl2.defaultEvent
    tmp: uint64
  # Preload tetris
  gb.cartridge.loadRomFile("roms/tetris.gb")

  while running:
    #sleep(100)
    #gbRenderer.clear()
    #gbRenderer.step(gb.ppu)
    #gbRenderer.present()

    while pollEvent(evt):
      if evt.kind == QuitEvent:
        running = false
        break
    sdl2.delay(1)
    #debug(gb, debugger)
    if 0 == tmp mod 512:
      echo gb.step().debugStr
      tileMapRenderer.clear()
      tileMapRenderer.renderMgbTileMap(gb.ppu)
      #tileMapRenderer.drawTestTile(gb.ppu)
      tileMapRenderer.present()
    else:
      discard gb.step().debugStr
    tmp += 1
main()
