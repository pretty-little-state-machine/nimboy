import types
import bitops

proc newVPUGb*(gameboy: Gameboy): VPUGb =
  VPUGb(gameboy: gameboy)

proc getWindowTileMapStartingAddress(vpu: VPU): uint16 = 
  if testBit(vpu.lcdc, 6):
    return 0x9800'u16
  else:
    return 0x9c00'u16


