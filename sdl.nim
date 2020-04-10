import sdl2
import system
import bitops
import strutils
import types

type
  TwoBB = array[16, uint8] # 2bb Encoded Sprite Data
  Sprite = object  # Decoded Sprite Data - 8x8 Pixels
    data: array[64, uint8]
  
  Palette = array[4, VpuColor] # Palette - 4 Colours (0 is transparent for sprites)
  
  VpuColor = object
    r: uint8
    g: uint8
    b: uint8

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

proc decode2bbTile(data: TwoBB): Sprite =
  # Decodes a sprite encoded wiht the 2BB format. 
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
  # This is essentially 2bb encoding.
  var offset = 0'u8
  for idx in countup(0, 7, 2):
    var tmp = 0'u8
    if byte.testBit(idx + 1): tmp += 2
    if byte.testBit(idx): tmp += 1
    result[offset] = decodeMgbColor(tmp)
    offset += 1

proc renderSprite(renderer: RendererPtr; sprite: Sprite; palette: Palette; x: cint; y: cint; scale: int = 1) =
  # Draws a sprite with the top-left corner at x,y with a given palette and scale.
  # Note that the calling proc must also consider what scale is being used.
  for i in countup(0, 7):
    for j in countup(0, 7):
      var color = palette[sprite.data[(8 * i) + j]]
      renderer.setDrawColor(r = color.r, g = color.g, b = color.b)
      renderer.drawPoint(cint(x + i), cint(y + j))

proc renderMgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  # Renders the Monochrome Gameboy Tile Map

  # Read the Palette Data
  let palette = byteToMgbPalette(vpu.bgp)
  renderer.drawSwatch(0, 0, 64, 64, palette[0])
  renderer.drawSwatch(64, 0, 64, 64, palette[1])
  renderer.drawSwatch(128, 0, 64, 64, palette[2])
  renderer.drawSwatch(192, 0, 64, 64, palette[3])
  # Tilemap data - 384 Tiles
 #for s in countup(0'u16, 0x1800, 0xF):
 #   var twoBB: TwoBB
 #   var tmp = [0xFF'u8, 0x00, 0x7E, 0xFF, 0x85, 0x81, 0x89, 0x83, 0x93, 0x85, 0xA5, 0x8B, 0xC9, 0x97, 0x7E, 0xFF]
 #   for b in countup(0'u16, 0xF):
 #     #twoBB[b] = vpu.vRAMTileDataBank0[s + b] # Load the 2bb encoding of a sprite (16 bytes)
 #     twoBB[b] = tmp[s + b] # Load the 2bb encoding of a sprite (16 bytes)
 #     var sprite = twoBB.decode2bbTile()
 #     renderer.renderSprite(sprite,  palette, cint(s), cint(64), 4)
 # return
 
  var twoBB: TwoBB
  var tmp = [0xFF'u8, 0x00, 0x7E, 0xFF, 0x85, 0x81, 0x89, 0x83, 0x93, 0x85, 0xA5, 0x8B, 0xC9, 0x97, 0x7E, 0xFF]
  for b in countup(0'u16, 0xF):
    #twoBB[b] = vpu.vRAMTileDataBank0[s + b] # Load the 2bb encoding of a sprite (16 bytes)
    twoBB[b] = tmp[b] # Load the 2bb encoding of a sprite (16 bytes)
    var sprite = twoBB.decode2bbTile()
    renderer.renderSprite(sprite,  palette, cint(0), cint(64), 4)


#proc renderCgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  # TODO

proc renderTileMap*(renderer: RendererPtr; vpu: VPU) =
  case vpu.gb.gameboy.gameboyMode:
  of mgb: renderer.renderMgbTileMap(vpu)
  #of cgb: renderer.renderCgbTileMap(vpu)
  else: discard

proc renderVpu*(renderer: RendererPtr; vpu: VPU) =
  renderer.setDrawColor(r = 255, g = 00, b = 00)
  for x in countup(50, 100):
    for y in countup(50, 100):
      renderer.drawPoint(cint(x), cint(y))
