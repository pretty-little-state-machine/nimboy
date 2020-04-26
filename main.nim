# Nimboy imports
import debugger
import gameboy
import cartridge
import sdl2
import renderer
import types
import joypad

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
  if (getTicks() < 17):
    delay(17 - getTicks())

proc handleInput(game: Game) = 
  var event = defaultEvent
  while pollEvent(event):
    case event.kind:
    of QuitEvent:
      game.inputs[Input.quit] = true
    of KeyDown:
      echo "Keydown"
      game.inputs[event.key.keysym.scancode.toInput] = true
    of KeyUp:
      game.inputs[event.key.keysym.scancode.toInput] = false
    else: 
      discard

proc render(game: Game) = 
  game.renderer.clear()
  game.renderer.step(game.gameboy.ppu)
  game.renderer.present()

proc main =
  let tileMapRenderer = getRenderer("Tile Data", 256 * tileDebuggerScale, 256 * tileDebuggerScale)

  var 
    game = newGame(getRenderer("Nimboy", 160, 144), newGameboy())
    debugger = newDebugger()
    refresh: bool
  
  # Preload tetris
  game.gameboy.cartridge.loadRomFile("roms/tetris.gb")
  
  #sleep (3000)
  game.gameboy.ppu.fillTestTiles()

  # Game loop, draws each frame
  while not game.inputs[Input.quit]:
    game.handleInput()

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
    
    # Dump the current opcodes to the screen for now.
    discard game.gameboy.step().debugStr
    # Disable debugger
    # debug(gb, debugger) 
    # Limited to ~60 FPS
    limitFrameRate()
main()
