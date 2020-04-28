# Nimboy imports
import debugger
import gameboy
import cartridge
import sdl2
import os
import strutils
import renderer
import types

const tileDebuggerScale:cint = 1 # Output Scaling

proc limitFrameRate() =
  if (getTicks() < 30):
    delay(30 - getTicks())

proc main =
  let gbRenderer = getRenderer("Nimboy", 160, 144)
  let tileMapRenderer = getRenderer("Tile Data", 256 * tileDebuggerScale, 256 * tileDebuggerScale)

  # Game loop, draws each frame
  var 
    gb = newGameboy()
    debugger = newDebugger()
    running = true
    evt = sdl2.defaultEvent
    refresh: bool
  # Preload tetris
  gb.cartridge.loadRomFile("roms/tetris.gb")
  tileMapRenderer.clear()
  #sleep (3000)
  gb.ppu.fillTestTiles()
  while running:
    while pollEvent(evt):
      if evt.kind == QuitEvent:
        running = false
        break
    
    # Only render when shifting from vSync to OAMMode
    if oamSearch == gb.ppu.mode and true == refresh:
      refresh = false
      tileMapRenderer.renderTilemap(gb.ppu)
      tileMapRenderer.present()
      gbRenderer.step(gb.ppu)
      gbRenderer.present()

    # Set next OAM to fire off a redraw
    if vBlank == gb.ppu.mode:
      refresh = true

    let str = gb.step().debugStr
    if str.contains("UNKNOWN OPCODE"):
      echo str
      quit("")
    else:
      echo str
    #debug(gb, debugger)
    limitFrameRate()
main()
