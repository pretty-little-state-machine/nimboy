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

proc newVPUGb*(gameboy: Gameboy): VPUGb =
  VPUGb(gameboy: gameboy)

proc getWindowTileMapStartingAddress(vpu: VPU): uint16 = 
  if testBit(vpu.lcdc, 6):
    return 0x9800'u16
  else:
    return 0x9c00'u16


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

proc drawTile(buffer: var VpuBuffer; tile: Tile; palette: Palette; x: cint; y: cint) =
  # Draws a tile with the top-left corner at x,y with a given palette.
  let memOffset = (x * 8) + (y * buffer.height * 8)
  for yCoord in countup(0, 7):
    for xCoord in countup(0, 7):
      var color = palette[tile.data[(8 * yCoord) + xCoord]]
      buffer.data[(memOffset + yCoord * buffer.height) + xCoord] = color


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

proc readOamYCoord(vpu: VPU; spriteIdx: uint8): uint8 =
  return vpu.oam[0x04 * spriteIdx]

proc readOamXCoord(vpu: VPU; spriteIdx: uint8): uint8 =
  return vpu.oam[0x04 * spriteIdx + 1]

proc readOamTileNumber(vpu: VPU; spriteIdx: uint8): uint8 =
  return vpu.oam[0x04 * spriteIdx + 2]

proc readOamAttributes(vpu: VPU; spriteIdx: uint8): uint8 =
  return vpu.oam[0x04 * spriteIdx + 3]

proc tickOamSearch(vpu: var VPU): void =
  # Executes the appropriate OAM Search based on cycle
  # There are 40 sprites and the OAM may have up to 10 at a time.
  # 
  # The rules are:
  #    - The sprite OAM.x coordinate can not be 0
  #    - The current line we're drawing must be between the first 
  #      and last line of the sprite (LY + 16 >= oam.y || LY + 16 < oam.y + h)
  #
  # Each cycle this is called is only capable of reading two of the 40 OAM entries

  # CIRCUIT BREAKER - Flip the state machine if we're already done on previous tick
  if 40 == vpu.oamClock:
    vpu.oamClock = 0
    vpu.mode = pixelTransfer
    return
  
  let oamIdx = uint8(vpu.oamClock div 2) # Entry offset
  for offset in countup(0'u8, 1'u8):
    vpu.oamClock += 1
    if (0 != vpu.readOamXCoord(oamIdx + offset) and
      (vpu.ly + 16 >= vpu.readOamYCoord(oamIdx + offset)) and
      (vpu.ly + 16) < vpu.readOamYCoord(oamIdx + offset)):
      # Valid - Add to the allowed sprites on this scanline
      vpu.oamBuffer[vpu.oamBufferIdx] = oamIdx + offset
      vpu.oamBufferIdx += 1

proc tickPixelTransfer(vpu: var VPU): void = 
  if 160 == vpu.pixelTransferX:
    vpu.ly += 1
    vpu.mode = hBlank
    vpu.pixelTransferX = 0
  # TODO: Actually implement the FIFO register
  vpu.pixelTransferX += 4

proc tick*(vpu: var VPU) =
  # Rollover per Video Cycle - End of VBLANK
  if 17556 == vpu.clock: 
    vpu.ly = 0
    vpu.clock = 0
    vpu.oamBufferIdx = 0
    for x in vpu.oamBuffer.mitems: x = 0
    vpu.mode = oamSearch
  
  if oamSearch == vpu.mode:
    vpu.tickOamSearch()
  
  if pixelTransfer == vpu.mode:
    vpu.tickPixelTransfer()

  # End H-BLank every 114 cycles - This is the difference between 144 - (OAM + Pixel Transfer)
  if (0 == vpu.clock mod 114 and vpu.mode == hBlank):
    vpu.mode = oamSearch

  # Override OAM Search if we hit VBlank
  if (144 == vpu.ly):
    vpu.mode = vBlank

  vpu.clock += 1

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
#      |----------------------------114 Clocks-----------------------------|
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
