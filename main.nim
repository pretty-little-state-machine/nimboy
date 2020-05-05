import sdl2
# Nimboy imports
import debugger
import gameboy
import cartridge
import sdl2
import os
import strutils
import renderer
import types
import joypad
import apu

const tileDebuggerScale:cint = 1 # Output Scaling

type
  Game = ref object
    inputs: array[Input, bool]
    renderer: RendererPtr
    gameboy: Gameboy

proc newGame(renderer: RendererPtr; gameboy: Gameboy): Game = 
  new result
  result.renderer = renderer
  result.gameboy = gameboy

proc limitFrameRate() =
  if (getTicks() < 30):
    delay(30 - getTicks())

proc render(game: Game): void =
  game.renderer.clear()
  game.renderer.step(game.gameboy.ppu)
  game.renderer.present()

proc main =
  let tileMapRenderer = getRenderer("Tile Data", 256 * tileDebuggerScale, 256 * tileDebuggerScale)

  # Game loop, draws each frame
  var 
    evt = sdl2.defaultEvent
    game = newGame(getRenderer("Nimboy", 160, 144), newGameboy())
    debugger = newDebugger()
    refresh: bool
    running: bool = true

  # Preload tetris
  game.gameboy.cartridge.loadRomFile("roms/tetris.gb")
  
  #sleep (3000)
  #gb.ppu.fillTestTiles()
  while running:
    while pollEvent(evt):
      echo repr(evt.kind)
      case evt.kind:
      of QuitEvent:
        quit("")
      of KeyDown:
        let input = evt.key.keysym.scancode.toInput
        if Input.quit == input:
          quit("")
        game.gameboy.joypad = input.keyDown(game.gameboy.joypad)
      of KeyUp:
        let input = evt.key.keysym.scancode.toInput
        game.gameboy.joypad = input.keyUp(game.gameboy.joypad)
      else:
        discard

    # Only render when shifting from vSync to OAMMode
    if oamSearch == game.gameboy.ppu.mode and true == refresh:
      refresh = false
      tileMapRenderer.clear()
      tileMapRenderer.renderTilemap(game.gameboy.ppu)
      tileMapRenderer.present()
      game.render()

    # Set next OAM to fire off a redraw
    if vBlank == game.gameboy.ppu.mode:
      refresh = true

    let str = game.gameboy.step().debugStr
    if str.contains("UNKNOWN OPCODE"): #or 
      #str.contains("BREAK!"):
      #echo str
      quit("")
    else:
      discard
      echo str
    #debug(game.gameboy, debugger)
    limitFrameRate()
main()
#testSound()
