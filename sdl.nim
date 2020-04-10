#
# VPU Rendering Chip
# 
# This chip is responsible for displaying graphics on the screen. This program
# implements the VPU using a simple rendering pipeline as shown:
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
    data: array[768*8*8, VpuColor] # Should be enough to hold the entire tilemap debugger

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
  for i in countup(x, x + width):
    for j in countup(y, y + height):
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

proc render(renderer: RendererPtr; buffer: VpuBuffer): void =
  # TODO - Post Procesesing / Scaling
  for xCoord in countup(0, buffer.width):
    for yCoord in countup(0, buffer.height):
      let color = buffer.data[(xCoord * 8) + yCoord]
      echo "Drawing: " & $yCoord & "," & $xCoord
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(xCoord), cint(yCoord))
      sleep (100)


proc drawTile(buffer: var VpuBuffer; tile: Tile; palette: Palette; x: cint; y: cint) =
  # Draws a tile with the top-left corner at x,y with a given palette.
  for i in countup(0, 7):
    for j in countup(0, 7):
      var color = palette[tile.data[(8 * i) + j]]
      let xCoord = (x*8 + j)
      let yCoord = (y*8 + i)
      buffer.data[(xCoord * 8) + yCoord] = color

proc renderMgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  # TODO: FINISH ME?
  var vpuBuffer = new VpuBuffer
  vpuBuffer.width = 32                 # 32 Tiles Wide
  #vpuBuffer.used = (256*32) + (32*8*8) # 256x32 Swatch Map + 384 8x8 Tiles
  vpuBuffer.height = 32 # 256x32 Swatch Map + 384 8x8 Tiles

  # Renders the Monochrome Gameboy Tile Map

  # Read the Palette Data
  let palette = byteToMgbPalette(vpu.bgp)


  var twoBB: TwoBB
  var tmp = [0xFF'u8, 0x00, 0x7E, 0xFF, 0x85, 0x81, 0x89, 0x83, 0x93, 0x85, 0xA5, 0x8B, 0xC9, 0x97, 0x7E, 0xFF]
  for b in countup(0'u16, 0xF):
    #twoBB[b] = vpu.vRAMTileDataBank0[s + b] # Load the 2bb encoding of a sprite (16 bytes)
    twoBB[b] = tmp[b] # Load the 2bb encoding of a sprite (16 bytes)
    #renderer.renderTile(sprite,  palette, cint(0), cint(64), 4)
  var tile = twoBB.decode2bbTile()
  #vpuBuffer.drawTile(tile, palette, 0, 0)
  vpuBuffer.drawTile(tile, palette, 2, 2)
  renderer.render(vpuBuffer)

  # Overlay swatches (since the pixel data has been written once)
  #renderer.drawSwatch(0, 0, 64, 32, palette[0])
  #renderer.drawSwatch(64, 0, 64, 32, palette[1])
  #renderer.drawSwatch(128, 0, 64, 32, palette[2])
  #renderer.drawSwatch(192, 0, 64, 32, palette[3])
#proc renderCgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  # TODO

proc renderTileMap*(renderer: RendererPtr; vpu: VPU) =
  case vpu.gb.gameboy.gameboyMode:
  of mgb: renderer.renderMgbTileMap(vpu)
  #of cgb: renderer.renderCgbTileMap(vpu)
  else: discard

proc step*(renderer: RendererPtr; vpu: VPU) =
  renderer.setDrawColor(r = 255, g = 00, b = 00)
  for x in countup(50, 100):
    for y in countup(50, 100):
      renderer.drawPoint(cint(x), cint(y))


