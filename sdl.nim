import sdl2
import system
import os
import bitops
import types

type
  Sprite = object
    data: array[64, uint8]

proc decodeMgbColor(colorNumber: uint8): array[3, uint8] =
  case colorNumber:
  of 0x03: return [232'u8, 242'u8, 223'u8]
  of 0x02: return [174'u8, 194'u8, 157'u8]
  of 0x01: return [98'u8, 110'u8, 89'u8]
  of 0x00: return [30'u8, 33'u8, 27'u8]
  else: return [30'u8, 33'u8, 27'u8]

proc drawSwatch(renderer: RendererPtr; x: cint; y: cint; 
                width: cint; height: cint; color: array[3, uint8]): void =
  for i in countup(x, x + width):
    for j in countup(y, y + height):
      renderer.setDrawColor(r = color[0], g = color[1], b = color[2])
      renderer.drawPoint(cint(i), cint(j))

proc decode2bbTile*(data: array[16, uint8]): array[64, uint8] =
  var offset = 0'u8
  var sprite = new Sprite
  for x in countup(0, 15, 2):
    let lByte = data[x]
    let hByte = data[x+1]
    for i in countdown(7, 0):
      if lByte.testBit(i) and hByte.testBit(i): sprite.data[offset] = 0x03'u8
      elif lByte.testBit(i) and not hByte.testBit(i): sprite.data[offset] = 0x02'u8
      elif not lByte.testBit(i) and hByte.testBit(i): sprite.data[offset] = 0x01'u8
      else: sprite.data[offset] = 0x00'u8
      offset += 1
      echo $offset
  return sprite.data

proc renderMgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  renderer.drawSwatch(0, 0, 64, 64, decodeMgbColor(3))
  renderer.drawSwatch(64, 0, 64, 64, decodeMgbColor(2))
  renderer.drawSwatch(128, 0, 64, 64, decodeMgbColor(1))
  renderer.drawSwatch(192, 0, 64, 64, decodeMgbColor(0))

proc renderCgbTileMap(renderer: RendererPtr; vpu: VPU) = 
  renderer.drawSwatch(0, 0, 64, 8, [232'u8, 242'u8, 223'u8])
  renderer.drawSwatch(64, 0, 64, 8, [174'u8, 194'u8, 157'u8])
  renderer.drawSwatch(128, 0, 64, 8, [98'u8, 110'u8, 89'u8])
  renderer.drawSwatch(192, 0, 64, 8, [30'u8, 33'u8, 27'u8])
  renderer.drawSwatch(0, 8, 64, 8, [223'u8, 237'u8, 242'u8])
  renderer.drawSwatch(64, 8, 64, 8, [136'u8, 176'u8, 191'u8])
  renderer.drawSwatch(128, 8, 64, 8, [39'u8, 91'u8, 110'u8])
  renderer.drawSwatch(192, 8, 64, 8, [3'u8, 42'u8, 56'u8])
  renderer.drawSwatch(0, 16, 64, 8, [232'u8, 242'u8, 223'u8])
  renderer.drawSwatch(64, 16, 64, 8, [174'u8, 194'u8, 157'u8])
  renderer.drawSwatch(128, 16, 64, 8, [98'u8, 110'u8, 89'u8])
  renderer.drawSwatch(192, 16, 64, 8, [30'u8, 33'u8, 27'u8])
  renderer.drawSwatch(0, 24, 64, 8, [223'u8, 237'u8, 242'u8])
  renderer.drawSwatch(64, 24, 64, 8, [136'u8, 176'u8, 191'u8])
  renderer.drawSwatch(128, 24, 64, 8, [39'u8, 91'u8, 110'u8])
  renderer.drawSwatch(192, 24, 64, 8, [3'u8, 42'u8, 56'u8])
  renderer.drawSwatch(0, 32, 64, 8, [232'u8, 242'u8, 223'u8])
  renderer.drawSwatch(64, 32, 64, 8, [174'u8, 194'u8, 157'u8])
  renderer.drawSwatch(128, 32, 64, 8, [98'u8, 110'u8, 89'u8])
  renderer.drawSwatch(192, 32, 64, 8, [30'u8, 33'u8, 27'u8])
  renderer.drawSwatch(0, 40, 64, 8, [223'u8, 237'u8, 242'u8])
  renderer.drawSwatch(64, 40, 64, 8, [136'u8, 176'u8, 191'u8])
  renderer.drawSwatch(128, 40, 64, 8, [39'u8, 91'u8, 110'u8])
  renderer.drawSwatch(192, 40, 64, 8, [3'u8, 42'u8, 56'u8])
  renderer.drawSwatch(0, 48, 64, 8, [232'u8, 242'u8, 223'u8])
  renderer.drawSwatch(64, 48, 64, 8, [174'u8, 194'u8, 157'u8])
  renderer.drawSwatch(128, 48, 64, 8, [98'u8, 110'u8, 89'u8])
  renderer.drawSwatch(192, 48, 64, 8, [30'u8, 33'u8, 27'u8])
  renderer.drawSwatch(0, 56, 64, 8, [223'u8, 237'u8, 242'u8])
  renderer.drawSwatch(64, 56, 64, 8, [136'u8, 176'u8, 191'u8])
  renderer.drawSwatch(128, 56, 64, 8, [39'u8, 91'u8, 110'u8])
  renderer.drawSwatch(192, 56, 64, 8, [3'u8, 42'u8, 56'u8])

proc renderTileMap*(renderer: RendererPtr; vpu: VPU) =
  case vpu.gb.gameboy.gameboyMode:
  of mgb: renderer.renderMgbTileMap(vpu)
  of cgb: renderer.renderCgbTileMap(vpu)
  else: discard

proc renderVpu*(renderer: RendererPtr; vpu: VPU) =
  renderer.setDrawColor(r = 255, g = 00, b = 00)
  for x in countup(50, 100):
    for y in countup(50, 100):
      renderer.drawPoint(cint(x), cint(y))
