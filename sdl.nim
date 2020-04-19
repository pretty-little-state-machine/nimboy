#
# VPU Rendering Chip
# 
# This chip is responsible for displaying graphics on the screen. This program
# implements the VPU using a simple rendering pipeline as shown:
#
# WATCH THIS: https://www.youtube.com/watch?v=HyzD8pNlpwI&t=29m12s
# 
# And read this: http://blog.kevtris.org/blogfiles/Nitty%20Gritty%20Gameboy%20VRAM%20Timing.txt
#
# Step - (Public Proc)
#  |> Draw Background (VpuBuffer)
#  |> Overlay Window  (VpuBuffer)
#  |> Draw Sprites    (VpuBuffer)
#  |> Render          (SDL2 RendererPtr Draw Calls)          
#
# This allows us to perform all our scaling or 2x2 SuperEagle interpolation or
# whatever we want to do all at once instead of in the tile drawing routines.
#
# The VpuBuffer itself is very large as it might be holding debugger maps. 
# Since the gameboy screen itself won't be using the entire thing the object
# has a `used` field that will represent the actual consumed lenght for the 
# renderer to function on.
#
import sdl2
import system
import bitops
import strutils
import types
import os

type
  OAMSearch = array[10, uint8]

  PixelFIFO = array[16, PixelFifoEntry]

  PixelFIFOType = enum
    ftBackground, ftWindow, ftSprite0, ftSprite1

  PixelFIFOEntry = object
    data: array[16, uint8]
    fifoType: PixelFIFOType
    priority: uint8

  # 2bb Encoded Tile Data - 4:1 Compression ratio
  TwoBB = array[16, uint8]
  
  # Decoded Tile Data - 8x8 Pixels
  Tile = object 
    data: array[64, uint8]
  
  # Palette - 4 Colors (0 is transparent for sprites)
  Palette = array[4, VpuColor] 
  
  # Color object populated with the Palette data - Represents a pixel
  VpuColor = object
    r: uint8
    g: uint8
    b: uint8

  # Generic buffer that will be passed through rendering pipelines
  VpuBuffer = ref object of RootObj
    width: int   # Number of pixels wide
    height: int  # Number of pixels high
    data: array[(32 * 32)*8*8, VpuColor] # Should be enough to hold the entire tilemap debugger - 1024 possible sprites

proc decodeMgbColor(colorNumber: uint8): VpuColor =
  # A nice set of psuedo-green colours for Monochrome Gameboy
  case colorNumber:
  of 0x03: result.r = 232'u8; result.g = 242'u8; result.b = 223'u8
  of 0x02: result.r = 174'u8; result.g = 194'u8; result.b = 157'u8
  of 0x01: result.r =  98'u8; result.g = 110'u8; result.b = 89'u8
  of 0x00: result.r =  30'u8; result.g =  33'u8; result.b = 27'u8
  else: result.r = 30'u8; result.g = 33'u8; result.b = 27'u8

proc drawSwatch(renderer: RendererPtr; x: cint; y: cint; 
                width: cint; height: cint; color: VpuColor): void =
  # Draws a coloured rectangle swatch for palette inspection
  for i in countup(x, x + width - 1):
    for j in countup(y, y + height - 1):
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(i), cint(j))

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

proc render(renderer: RendererPtr; buffer: VpuBuffer; scale: int = 1): void =
  # TODO - Post Procesesing / Scaling
  for yCoord in countup(0, buffer.height):
    for xCoord in countup(0, buffer.width - 1):
      let color = buffer.data[(yCoord * buffer.width) + xCoord]
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(xCoord), cint(yCoord))

proc drawTile(buffer: var VpuBuffer; tile: Tile; palette: Palette; x: cint; y: cint) =
  # Draws a tile with the top-left corner at x,y with a given palette.
  let memOffset = (x * 8) + (y * buffer.height * 8)
  for yCoord in countup(0, 7):
    for xCoord in countup(0, 7):
      var color = palette[tile.data[(8 * yCoord) + xCoord]]
      buffer.data[(memOffset + yCoord * buffer.height) + xCoord] = color

proc renderMgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  # Renders the Monochrome Gameboy Tile Map
  var vpuBuffer = new VpuBuffer
  vpuBuffer.width = (32 * 8)   # 32 Tiles Wide
  vpuBuffer.height = (24 * 8)  # 256x32 Swatch Map + 384 8x8 Tiles
  # Read the Palette Data
  let palette = byteToMgbPalette(vpu.bgp)

  # Bank 0
  var xOffset = 0
  var yOffset = 6 # Leave room for swatch overlay, which is 4 tiles high
  for tileOffset in countup(0, 0x17FF, 0xF):
    var twoBB: TwoBB
    for b in countup(0'u16, 0xF):
      twoBB[b] = vpu.vRAMTileDataBank0[uint16(tileOffset) + b] # Load the 2bb encoding of a sprite (16 bytes)
    vpuBuffer.drawTile(twoBB.decode2bbTile(), palette, cint(xOffset), cint(yOffset))
    xOffset += 1
    if xOffset > 32: 
      xOffset = 0
      yOffset += 1
  # Bank 1
  xOffset = 0
  yOffset = 17
  for tileOffset in countup(0, 0x17FF, 0xF):
    var twoBB: TwoBB
    for b in countup(0'u16, 0xF):
      twoBB[b] = vpu.vRAMTileDataBank1[uint16(tileOffset) + b] # Load the 2bb encoding of a sprite (16 bytes)
    vpuBuffer.drawTile(twoBB.decode2bbTile(), palette, cint(xOffset), cint(yOffset))
    xOffset += 1
    if xOffset > 32: 
      xOffset = 0
      yOffset += 1

  renderer.render(vpuBuffer)

  # Overlay swatches (since the pixel data has been written once)
  renderer.drawSwatch(0, 0, 64, 32, palette[0])
  renderer.drawSwatch(64, 0, 64, 32, palette[1])
  renderer.drawSwatch(128, 0, 64, 32, palette[2])
  renderer.drawSwatch(192, 0, 64, 32, palette[3])
#proc renderCgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  # TODO

proc drawTestTile*(renderer: RendererPtr; vpu: VPU): void =
  # Draws a sample sprite to the renderer. Useful for testing scaler
  # code or just eliminating the GB Video memory.
  var vpuBuffer = new VpuBuffer
  vpuBuffer.width = 8
  vpuBuffer.height = 8 
  let palette = byteToMgbPalette(vpu.bgp)
  var twoBB: TwoBB
  var tmp = [0xFF'u8, 0x00, 0x7E, 0xFF, 0x85, 0x81, 0x89, 0x83, 0x93, 0x85, 0xA5, 0x8B, 0xC9, 0x97, 0x7E, 0xFF]
  for b in countup(0'u16, 0xF): 
    twoBB[b] = tmp[b]
  var tile = twoBB.decode2bbTile()
  vpuBuffer.drawTile(tile, palette, 0, 0)
  renderer.render(vpuBuffer)

proc readByte*(vpu: Vpu; address: uint16): uint8 {.noSideEffect.} =
  # TODO Addressing based on BIT 4 of the LDCD register
  # TODO Pagination for gameboy color
  if address < 0x9800:
    result = vpu.vRAMTileDataBank0[address - 0x8000]
  if address < 0x9C00:
    result = vpu.vRAMBgMap1[address - 0x9800]
  if address < 0x9FFF:
    result = vpu.vRAMBgMap1[address - 0x9C00]

proc renderTileMap*(renderer: RendererPtr; vpu: VPU) =
  case vpu.gb.gameboy.gameboyMode:
  of mgb: renderer.renderMgbTileMap(vpu)
  #of cgb: renderer.renderCgbTileMap(vpu)
  else: discard


proc stepFifo(): void = 
  # Read tile from background map
  let x = 1
  # Read Data 0 
  
  # Read Data 1

  # Construct 8 pixels of data - but NOT VPU pixels


proc tickOam(vpu: VPU): void =
  let x = 1

proc tick*(renderer: RendererPtr; vpu: VPU) =
  # Processes a tick from the system clock.
  # Note that the VPU is technically always clocking when turned on.
  # This is called Cpu.tCycles numbers of times.
  #
  # A vertical refresh happens every 70224 clocks (140448 in double speed mode)
  # LY Refresh timings vary per scanline but take 456 clocks total usually (912 double speed)


  # OAM Search - 20 Clocks
  # Determine up to 10 pixels that can be drawn.

  

  # Pixel Transfer

  # HBlank

  # VBLANK






#
# FIFO - Pushes one pixel per clock
#  4Mhz  Pauses unless it contains more than 8 pixels
#
# FETCH - 3 Clocks to fetch 8 pixels
#  2Mhz   Pauses on 4th clock unless FIFO has room
#
# Window wipes out the FIFO and fetch restarts
#
# Sprites have 10 comparators 
#
# Horizontal Line drawing:
#
# [--------------------------------------------------------->>>>>>>>>>>] 43 OR MORE Clocks
# First Pixel          Piple Cleared    Fetcher reads 
# |                      FIFO Paused    window tiles    FIFO Resumed
# |                             |            |         |
# [][][][][][][][][][][][][][][]-----------------------[][][][][][]//[] 
#                              |
#                         Start of Window
#
#
# Thus this is how the modes work:
#  
#      |----20 Clocks----|<-----43+ Clocks----->|<-------51- Clocks------->|
# ___  +===================================================================+
#  |   |                 |                      |                          |
#  |   |                 |                         |                       |
#  |   |       OAM       |    Pixel Transfer    |        H-BLANK           |
#  |   |                 |                      |                          |
#  |   |                 |                      |                          |
# 144  |                 |                       |                         |
# Lines|                 |                             |                   |
#  |   |                 |                      |                          |
#  |   |                 |                      |                          |
#  |   |                 |                      |                          |
# ---  |-------------------------------------------------------------------|
#  10  |                           VBLANK                                  |
# ---  +===================================================================+
#
  let x = 1