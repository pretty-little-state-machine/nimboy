import sdl2
import times
import os
import strutils
import parseopt
# Nimboy imports
import debugger
import gameboy
import cartridge
import renderer
import types
import joypad
import apu

const tileDebuggerScale:cint = 1 # Output Scaling

type
  Game = ref object
    inputs: array[Input, bool]
    window: WindowPtr
    renderer: RendererPtr
    gameboy: Gameboy
    scale: cint

proc newGame(renderer: RendererPtr; window: WindowPtr; gameboy: Gameboy): Game = 
  new result
  result.scale = 1
  result.window = window
  result.renderer = renderer
  result.gameboy = gameboy

proc limitFrameRate() =
  if (getTicks() < 30):
    delay(30 - getTicks())

proc render(game: Game): void =
  game.renderer.clear()
  game.renderer.step(game.gameboy.ppu, game.scale)
  game.renderer.present()

proc main(file: string = ""): void =
  let 
    (tileMapRenderer, _) = getRenderer("Tile Data", 256 * tileDebuggerScale, 256 * tileDebuggerScale)
    (renderer, window) = getRenderer("Nimboy", 160, 144)
    
  # Game loop, draws each frame
  var 
    evt = sdl2.defaultEvent
    game = newGame(renderer, window, newGameboy())
    debugger = newDebugger()
    refresh: bool
    running: bool = true
    vSyncTime: float

  if "" == file:
    # Preload tetris
    game.gameboy.cartridge.loadRomFile("roms/tetris.gb")
    # Blargg's CPU Roms
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/01-special.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/02-interrupts.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/03-op sp,hl.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/04-op r,imm.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/05-op rp.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/06-ld r,r.gb") 
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/07-jr,jp,call,ret,rst.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/08-misc instrs.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/09-op r,r.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/10-bit ops.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/individual/11-op a,(hl).gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/cpu_instrs/cpu_instrs.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/instr_timing/instr_timing.gb")
  else:
    game.gameboy.cartridge.loadRomFile(file)
  #sleep (3000)
  # game.gameboy.ppu.fillTestTiles()
  while running:
    while pollEvent(evt):
      case evt.kind:
      of QuitEvent:
        quit("")
      of KeyDown:
        let input = evt.key.keysym.scancode.toInput
        if Input.quit == input:
          quit("")
        elif Input.scale1x == input:
          game.window.setSize(160, 144)
          game.scale = 1       
        elif Input.scale2x == input:
          game.window.setSize(160 * 2, 144 * 2)
          game.scale = 2
        elif Input.scale3x == input:
          game.window.setSize(160 * 3, 144 * 3)
          game.scale = 3
        elif Input.scale4x == input:
          game.window.setSize(160 * 4, 144 * 4)
          game.scale = 4         
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
      #echo "vBlank: ", (cpuTime() - vSyncTime) * 1000
      vSyncTime = cpuTime()

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
      #echo str
    #debug(game.gameboy, debugger)
    #limitFrameRate()

for kind, key, value in getOpt():
  case kind
  of cmdLongOption, cmdShortOption:
    case key
    of "rom":
      main(value)
    else:
      main("")
  else:
    main("")
main("")
#testSound()
