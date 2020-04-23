#
# SDL2 Interface
#
# What good is a gameboy if you can't play games?
#
import sdl2
import system
import bitops
import types
import os

type 
  SDLException = object of Exception

  # Color object populated with the Palette data - Represents a pixel
  PpuColor = object
    r: uint8
    g: uint8
    b: uint8
  
  # Palette - 4 Colors (0 is transparent for sprites)
  Palette = array[4, PpuColor] 
  
  # TODO: DO I CARE ABOUT THESE?
  # 2bb Encoded Tile Data - 4:1 Compression ratio
  TwoBB = array[16, uint8]
  
  # Decoded Tile Data - 8x8 Pixels
  Tile = object 
    data: array[64, uint8]

  # Generic buffer that will be passed through rendering pipelines
  DebugBuffer = ref object of RootObj
    width: int   # Number of pixels wide
    height: int  # Number of pixels high
    data: array[(32 * 32)*8*8, PpuColor] # Should be enough to hold the entire tilemap debugger - 1024 possible sprites

template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

proc getRenderer*(title: string; width: cint; height: cint): RendererPtr =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  #
  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "2")):
    "Linear texture filtering could not be enabled"
  #
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
  return renderer

proc step*(renderer: RendererPtr; ppu: PPU): void =
  discard

proc decodeMgbColor(colorNumber: uint8): PpuColor =
  # A nice set of psuedo-green colours for Monochrome Gameboy
  case colorNumber:
  of 0x03: result.r = 232'u8; result.g = 242'u8; result.b = 223'u8
  of 0x02: result.r = 174'u8; result.g = 194'u8; result.b = 157'u8
  of 0x01: result.r =  98'u8; result.g = 110'u8; result.b = 89'u8
  of 0x00: result.r =  30'u8; result.g =  33'u8; result.b = 27'u8
  else: result.r = 30'u8; result.g = 33'u8; result.b = 27'u8

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

proc decode2bbTile(data: TwoBB): Tile =
  # Decodes a sprite encoded with the 2BB format. 
  # See https://www.huderlem.com/demos/gameboy2bpp.html for how this works.
  var offset = 0'u8
  for x in countup(0, 15, 2):
    let lByte = data[x]
    let hByte = data[x+1]
    for i in countdown(7, 0):
      if lByte.testBit(i): result.data[offset] += 2
      if hByte.testBit(i): result.data[offset] += 1
      offset += 1

proc drawSwatch(renderer: RendererPtr; x: cint; y: cint; 
                width: cint; height: cint; color: PpuColor): void =
  # Draws a coloured rectangle swatch for palette inspection
  for i in countup(x, x + width - 1):
    for j in countup(y, y + height - 1):
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(i), cint(j))

proc render(renderer: RendererPtr; buffer: DebugBuffer; scale: int = 1): void =
  # TODO - Post Procesesing / Scaling
  for yCoord in countup(0, buffer.height):
    for xCoord in countup(0, buffer.width - 1):
      let color = buffer.data[(yCoord * buffer.width) + xCoord]
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(xCoord), cint(yCoord))

proc drawTile(buffer: var DebugBuffer; tile: Tile; palette: Palette; x: cint; y: cint) =
  # Draws a tile with the top-left corner at x,y with a given palette.
  let memOffset = (x * 8) + (y * buffer.height * 8)
  for yCoord in countup(0, 7):
    for xCoord in countup(0, 7):
      var color = palette[tile.data[(8 * yCoord) + xCoord]]
      buffer.data[(memOffset + yCoord * buffer.height) + xCoord] = color

proc renderMgbTileMap*(renderer: RendererPtr; ppu: PPU) = 
  # Renders the Monochrome Gameboy Tile Map
  var debugBuffer = new DebugBuffer
  debugBuffer.width = (32 * 8)   # 32 Tiles Wide
  debugBuffer.height = (24 * 8)  # 256x32 Swatch Map + 384 8x8 Tiles
  # Read the Palette Data
  let palette = byteToMgbPalette(ppu.bgp)

  # Bank 0
  var xOffset = 0
  var yOffset = 4 # Leave room for swatch overlay, which is 4 tiles high
  for tileOffset in countup(0, 0x17F0, 0xF):
    var twoBB: TwoBB
    for b in countup(0'u16, 0xF):
      twoBB[b] = ppu.vRAMTileDataBank0[uint16(tileOffset) + b] # Load the 2bb encoding of a sprite (16 bytes)
    debugBuffer.drawTile(twoBB.decode2bbTile(), palette, cint(xOffset), cint(yOffset))
    xOffset += 1
    if xOffset > 32: 
      xOffset = 0
      yOffset += 1
  # Bank 1
  xOffset = 0
  yOffset = 17
  for tileOffset in countup(0, 0x17F0, 0xF):
    var twoBB: TwoBB
    for b in countup(0'u16, 0xF):
      twoBB[b] = ppu.vRAMTileDataBank1[uint16(tileOffset) + b] # Load the 2bb encoding of a sprite (16 bytes)
    debugBuffer.drawTile(twoBB.decode2bbTile(), palette, cint(xOffset), cint(yOffset))
    xOffset += 1
    if xOffset > 32: 
      xOffset = 0
      yOffset += 1

  renderer.render(debugBuffer)

  # Overlay swatches (since the pixel data has been written once)
  renderer.drawSwatch(0, 0, 64, 32, palette[0])
  renderer.drawSwatch(64, 0, 64, 32, palette[1])
  renderer.drawSwatch(128, 0, 64, 32, palette[2])
  renderer.drawSwatch(192, 0, 64, 32, palette[3])
#proc renderCgbTileMap(renderer: RendererPtr; ppu: PPU) = 
  # TODO

proc drawTestTile*(renderer: RendererPtr; ppu: PPU): void =
  # Draws a sample sprite to the renderer. Useful for testing scaler
  # code or just eliminating the GB Video memory.
  var debugBuffer = new DebugBuffer
  debugBuffer.width = 8
  debugBuffer.height = 8 
  let palette = byteToMgbPalette(ppu.bgp)
  var twoBB: TwoBB
  var tmp = [0xFF'u8, 0x00, 0x7E, 0xFF, 0x85, 0x81, 0x89, 0x83, 0x93, 0x85, 0xA5, 0x8B, 0xC9, 0x97, 0x7E, 0xFF]
  for b in countup(0'u16, 0xF): 
    twoBB[b] = tmp[b]
  var tile = twoBB.decode2bbTile()
  debugBuffer.drawTile(tile, palette, 0, 0)
  renderer.render(debugBuffer)
