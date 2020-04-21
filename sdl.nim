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
import vpu

proc drawSwatch(renderer: RendererPtr; x: cint; y: cint; 
                width: cint; height: cint; color: VpuColor): void =
  # Draws a coloured rectangle swatch for palette inspection
  for i in countup(x, x + width - 1):
    for j in countup(y, y + height - 1):
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(i), cint(j))

proc render(renderer: RendererPtr; buffer: VpuBuffer; scale: int = 1): void =
  # TODO - Post Procesesing / Scaling
  for yCoord in countup(0, buffer.height):
    for xCoord in countup(0, buffer.width - 1):
      let color = buffer.data[(yCoord * buffer.width) + xCoord]
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(xCoord), cint(yCoord))


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
