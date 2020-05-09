#
# SDL Rendering Module
#
import sdl2
import sdl2/ttf
import system
import bitops
import types
import os
import ppu

type 
  SDLException = object of IOError

  # Color object populated with the Palette data - Represents a pixel
  PpuColor = object
    r: uint8
    g: uint8
    b: uint8
  
  # Palette - 4 Colors (0 is transparent for sprites)
  Palette = array[4, PpuColor] 

template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

proc getRenderer*(title: string; width: cint; height: cint): (RendererPtr, WindowPtr) =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  #
  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "2")):
    "Linear texture filtering could not be enabled"
  #
  sdlFailIf(not ttfInit()):
    "SDL2 TTF Initialization Failed"
  let window = createWindow(title = title,
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = width, h = height, flags = SDL_WINDOW_SHOWN)
  sdlFailIf window.isNil: "Window could not be created"
  #
  let renderer = window.createRenderer(index = -1,
    flags = Renderer_Accelerated or Renderer_PresentVsync)
  sdlFailIf renderer.isNil: "Renderer could not be created"
  #
  renderer.setDrawColor(r = 255, g = 255, b = 255)
  return (renderer, window)

proc decodeMgbColor(colorNumber: uint8): PpuColor =
  # A nice set of psuedo-green colours for Monochrome Gameboy. Any invalid 
  # color palette values are rendered in red.
  case colorNumber:
  of 0x00: result.r = 232'u8; result.g = 242'u8; result.b = 223'u8
  of 0x01: result.r =  98'u8; result.g = 110'u8; result.b = 89'u8
  of 0x02: result.r = 174'u8; result.g = 194'u8; result.b = 157'u8
  of 0x03: result.r =  30'u8; result.g =  33'u8; result.b = 27'u8
  else: result.r = 255'u8; result.g = 0'u8; result.b = 0'u8

proc byteToMgbPalette(byte: uint8): Palette =
  # Reads the palette register into the four colors
  # This is essentially 2bb encoding, just like tiles.
  var offset = 0'u8
  for idx in countup(0, 7, 2):
    var tmp = 0'u8
    if byte.testBit(idx + 1): tmp += 2
    if byte.testBit(idx): tmp += 1
    result[offset] = decodeMgbColor(tmp)
    offset += 1

proc drawSwatch(renderer: RendererPtr; x: cint; y: cint; 
                width: cint; height: cint; color: PpuColor): void =
  # Draws a coloured rectangle swatch for palette inspection
  for i in countup(x, x + width - 1):
    for j in countup(y, y + height - 1):
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(i), cint(j))

proc fillTestTiles*(ppu: var PPU): void = 
  # Fills the PPU Sprite memory with a single test sprite over and over
  ppu.bgp = 0x1B'u8 # Fake testing one - 4 colours
  var tmp = [0xFF'u8, 0x00, 0x7E, 0xFF, 0x85, 0x81, 0x89, 0x83, 0x93, 0x85, 0xA5, 0x8B, 0xC9, 0x97, 0x7E, 0xFF]
  for tileOffset in countup(0, 0x17F0, 0x10):
    for b in countup(0'u16, 0xF): 
       ppu.vRAMTileDataBank0[uint16(tileOffset) + b] = tmp[b]

proc renderText(renderer: RendererPtr, text: string, x, y: cint, color: Color) =
  let font = openFont("resources/DejaVuSans.ttf", 12)

  let surface = font.renderUtf8Blended(text.cstring, color)
  sdlFailIf surface.isNil: "Could not render text surface"
  discard surface.setSurfaceAlphaMod(color.a)

  var source = rect(0, 0, surface.w, surface.h)
  var dest = rect(x, y, surface.w, surface.h)
  let texture = renderer.createTextureFromSurface(surface)

  sdlFailIf texture.isNil:
    "Could not create texture from rendered text"
  surface.freeSurface()
  renderer.copyEx(texture, source, dest, angle = 0.0, center = nil, flip = SDL_FLIP_NONE)
  texture.destroy()

proc drawPixelEntry(renderer: RendererPtr; ppu: PPU; x: cint; y: cint; scale: cint): void = 
  # Draws a pixel with the appropriate color palette to the screen.
  let offset = (y * 160) + x
  let pfe = ppu.outputBuffer[offset]
  var palette: Palette
  case pfe.entity:
  of ftBackground:
    palette = byteToMgbPalette(ppu.bgp)
  of ftWindow:
    palette = byteToMgbPalette(ppu.bgp)
  of ftSprite0:
    palette = byteToMgbPalette(ppu.obp0)
  of ftSprite1:
    palette = byteToMgbPalette(ppu.obp1)

  let color = palette[pfe.data]
  renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
  for sx in countup(1.cint, scale):
    for sy in countup(1.cint, scale):
      renderer.drawPoint(x * scale + sx, y * scale + sy)

proc step*(renderer: RendererPtr; ppu: PPU; scale: cint): void =
  # Processes a step in the "real" gameboy.
  # Supports scaling now!
  for y in countup(0, 143):
    for x in countup(0, 159):
      renderer.drawPixelEntry(ppu, cint(x), cint(y), scale)

proc renderOAM*(renderer: RendererPtr; ppu: PPU): void =
  renderer.setDrawColor(0, 0, 0, 255);
  renderer.clear()
  renderer.renderText("Testing text output", 0, 0, color(255, 255, 255, 255))
  renderer.present()

proc renderTileMap*(renderer: RendererPtr; ppu: PPU): void =
  renderer.clear()
  let palette = byteToMgbPalette(ppu.bgp)
  var
    xOffset = 0
    yOffset = 0
  for sprite in countup(0, 383):
    for row in countup(0, 7):
      let
        lByte = ppu.vRAMTileDataBank0[(sprite * 16) + int(row * 2) + 0]
        hByte = ppu.vRAMTileDataBank0[(sprite * 16) + int(row * 2) + 1]
        tmp = decode2bbTileRow(lbyte, hByte)
      for pixel in countup(0, 7):
        let color = palette[tmp[pixel]]
        renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
        renderer.drawPoint(cint((xOffset*8) + pixel), cint(yOffset + row))
    xOffset += 1
    if 32 == xOffset:
      xOffset = 0
      yOffset += 8
  renderer.present()

  # Overlay swatches (since the pixel data has been written once)
  renderer.drawSwatch(0, 192, 64, 32, palette[0])
  renderer.drawSwatch(64, 192, 64, 32, palette[1])
  renderer.drawSwatch(128, 192, 64, 32, palette[2])
  renderer.drawSwatch(192, 192, 64, 32, palette[3])
