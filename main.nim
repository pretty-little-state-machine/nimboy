# Nimboy imports
import debugger
import gameboy

import sdl2
import os
import sdl

type SDLException = object of Exception

template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

proc getRenderer(title: string; width: cint; height: cint): RendererPtr =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  #defer: sdl2.quit()
  #
  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "2")):
    "Linear texture filtering could not be enabled"
  #
  let window = createWindow(title = title,
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = width, h = height, flags = SDL_WINDOW_SHOWN)
  sdlFailIf window.isNil: "Window could not be created"
  #defer: window.destroy()
  #
  let renderer = window.createRenderer(index = -1,
    flags = Renderer_Accelerated or Renderer_PresentVsync)
  sdlFailIf renderer.isNil: "Renderer could not be created"
  #defer: renderer.destroy()
  #
  renderer.setDrawColor(r = 255, g = 255, b = 255)
  return renderer

proc main =
  let gbRenderer = getRenderer("Nimboy", 160,144)
  let tileMapRenderer = getRenderer("Tile Data", 256, 256) # 192 for all sprites

  # Game loop, draws each frame
  var gb = newGameboy()
  var debugger = newDebugger()
  while true:
    #sleep(100)
    gbRenderer.clear()
    gbRenderer.renderVpu(gb.vpu)
    gbRenderer.present()

    tileMapRenderer.clear()
    tileMapRenderer.renderTileMap(gb.vpu)
    tileMapRenderer.present()

    debug(gb, debugger)

#main()

let r = decode2bbTile([0xFF'u8, 0x00'u8, 0x7E'u8, 0xFF'u8, 0x85'u8, 0x81'u8, 0x89'u8, 0x83'u8, 
                       0x93'u8, 0x85'u8, 0xA5'u8, 0x8B'u8, 0xC9'u8, 0x97'u8, 0x7E'u8, 0xFF'u8])
echo repr(r)
