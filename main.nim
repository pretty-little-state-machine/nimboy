import sdl2
import sdl2/ttf
import strutils
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

type
  Game = ref object
    inputs: array[Input, bool]
    font: FontPtr
    window: WindowPtr
    renderer: RendererPtr
    gameboy: Gameboy
    scale: cint
    showFrameTime: bool
    showOpcodeDebug: bool
    showBGDebug: bool

proc newGame(renderer: RendererPtr; window: WindowPtr; font: FontPtr; gameboy: Gameboy): Game = 
  new result
  result.scale = 1
  result.window = window
  result.renderer = renderer
  result.font = font
  result.gameboy = gameboy
  result.showFrameTime = true
  result.showOpcodeDebug = true

proc limitFrameRate() =
  if (getTicks() < 30):
    delay(30 - getTicks())

proc render(game: Game; frameTime: float): void =
  game.renderer.clear()
  game.renderer.step(game.gameboy.ppu, game.scale)
  if game.showFrameTime:
    if frameTime > 30:
      game.renderer.renderText(game.font, frameTime.formatFloat(ffDecimal, 2), 0, 0, color(255, 128, 128, 255))
    elif frameTime > 16.67:
      game.renderer.renderText(game.font, frameTime.formatFloat(ffDecimal, 2), 0, 0, color(255, 255, 0, 255))
    else:
      game.renderer.renderText(game.font, frameTime.formatFloat(ffDecimal, 2), 0, 0, color(0, 255, 0, 255))
  game.renderer.present()

proc handleKeyDown(game: Game, input: Input): void =
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
  else:
    game.gameboy.joypad = input.keyDown(game.gameboy.joypad)

proc main(file: string = ""): void =
  let (renderer, window, font) = getRenderer("Nimboy", 160, 144)
  #let (tileMapRenderer, _, _) = getRenderer("Tile Data", 256, 256)

  # Game loop, draws each frame
  var 
    evt = sdl2.defaultEvent
    game = newGame(renderer, window, font, newGameboy())
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
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/mem_timing/mem_timing.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/mem_timing/individual/01-read_timing.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/mem_timing/individual/02-write_timing.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/mem_timing/individual/03-modify_timing.gb")
    # game.gameboy.cartridge.loadRomFile("roms/gb-test-roms/interrupt_time/interrupt_time.gb")
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
        game.handleKeyDown(evt.key.keysym.scancode.toInput)
      of KeyUp:
        let input = evt.key.keysym.scancode.toInput
        game.gameboy.joypad = input.keyUp(game.gameboy.joypad)
      else:
        discard

    # Only render when shifting from vSync to OAMMode
    if oamSearch == game.gameboy.ppu.mode and true == refresh:
      refresh = false
      #tileMapRenderer.renderTilemap(game.gameboy.ppu)
      game.render((epochTime() - vSyncTime) * 1000)
      vSyncTime = epochTime()

    # Set next OAM to fire off a redraw
    if vBlank == game.gameboy.ppu.mode:
      refresh = true

    if game.showOpcodeDebug:
      let str = game.gameboy.step().debugStr
      if str.contains("UNKNOWN OPCODE") or str.contains("BREAK!"):
        echo str
        quit("")
      else:
        echo str
    else:
      discard game.gameboy.step()

    #debug(game.gameboy, debugger)
    #limitFrameRate()

#
# CODE START
#####################################
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
