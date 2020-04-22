# Pixel Processing Unit
# 
# This chip is responsible for displaying graphics on the screen. This program
# implements the PPU using a simple rendering pipeline as shown:
#
# WATCH THIS: https://www.youtube.com/watch?v=HyzD8pNlpwI&t=29m12s
# 
# And read this: http://blog.kevtris.org/blogfiles/Nitty%20Gritty%20Gameboy%20VRAM%20Timing.txt
#
# Step - (Public Proc)
#  |> Draw Background (PpuBuffer)
#  |> Overlay Window  (PpuBuffer)
#  |> Draw Sprites    (PpuBuffer)
#  |> Render          (SDL2 RendererPtr Draw Calls)          
#
# This allows us to perform all our scaling or 2x2 SuperEagle interpolation or
# whatever we want to do all at once instead of in the tile drawing routines.
#
# The PpuBuffer itself is very large as it might be holding debugger maps. 
# Since the gameboy screen itself won't be using the entire thing the object
# has a `used` field that will represent the actual consumed lenght for the 
# renderer to function on.
#
import system
import bitops
import types

type
  # 2bb Encoded Tile Data - 4:1 Compression ratio
  TwoBB = array[16, uint8]
  
  # Decoded Tile Data - 8x8 Pixels
  Tile = object 
    data: array[64, uint8]
  
  # Palette - 4 Colors (0 is transparent for sprites)
  Palette = array[4, PpuColor] 
  
  # Color object populated with the Palette data - Represents a pixel
  PpuColor = object
    r: uint8
    g: uint8
    b: uint8

  # Generic buffer that will be passed through rendering pipelines
  PpuBuffer = ref object of RootObj
    width: int   # Number of pixels wide
    height: int  # Number of pixels high
    data: array[(32 * 32)*8*8, PpuColor] # Should be enough to hold the entire tilemap debugger - 1024 possible sprites

proc newPPUGb*(gameboy: Gameboy): PPUGb =
  PPUGb(gameboy: gameboy)

proc getWindowTileMapStartingAddress(ppu: PPU): uint16 = 
  if testBit(ppu.lcdc, 6):
    return 0x9800'u16
  else:
    return 0x9c00'u16

proc decodeMgbColor(colorNumber: uint8): PpuColor =
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

proc readByte*(ppu: Ppu; address: uint16): uint8 {.noSideEffect.} =
  # TODO Addressing based on BIT 4 of the LDCD register
  # TODO Pagination for gameboy color
  if address < 0x9800:
    result = ppu.vRAMTileDataBank0[address - 0x8000]
  if address < 0x9C00:
    result = ppu.vRAMBgMap1[address - 0x9800]
  if address < 0x9FFF:
    result = ppu.vRAMBgMap1[address - 0x9C00]

proc stepFifo(): void = 
  # Read tile from background map
  let x = 1
  # Read Data 0 
  
  # Read Data 1

  # Construct 8 pixels of data - but NOT PPU pixels

proc readOamYCoord(ppu: PPU; spriteIdx: uint8): uint8 =
  return ppu.oam[0x04 * spriteIdx]

proc readOamXCoord(ppu: PPU; spriteIdx: uint8): uint8 =
  return ppu.oam[0x04 * spriteIdx + 1]

proc readOamTileNumber(ppu: PPU; spriteIdx: uint8): uint8 =
  return ppu.oam[0x04 * spriteIdx + 2]

proc readOamAttributes(ppu: PPU; spriteIdx: uint8): uint8 =
  return ppu.oam[0x04 * spriteIdx + 3]

proc tickOamSearch(ppu: var PPU): void =
  # Executes the appropriate OAM Search based on cycle
  # There are 40 sprites and the OAM may have up to 10 at a time.
  # 
  # The rules are:
  #    - The sprite OAM.x coordinate can not be 0
  #    - The current line we're drawing must be between the first 
  #      and last line of the sprite (LY + 16 >= oam.y || LY + 16 < oam.y + h)
  #
  # Each cycle this is called is only capable of reading two of the 40 OAM entries

  # CIRCUIT BREAKER - Flip the state machine and reset if we're already done on previous tick
  if 40 == ppu.oamBuffer.clock:
    ppu.oamBUffer.clock = 0
    ppu.mode = pixelTransfer
    return
  
  let oamIdx = uint8(ppu.oamBuffer.clock div 2) # Entry offset
  for offset in countup(0'u8, 1'u8):
    ppu.oamBuffer.clock += 1
    if (0 != ppu.readOamXCoord(oamIdx + offset) and
      (ppu.ly + 16 >= ppu.readOamYCoord(oamIdx + offset)) and
      (ppu.ly + 16) < ppu.readOamYCoord(oamIdx + offset)):
      # Valid - Add to the allowed sprites on this scanline
      ppu.oamBuffer.data[ppu.oamBuffer.idx] = oamIdx + offset
      ppu.oamBuffer.idx += 1

proc resetFetch(fetch: var Fetch): void =
  # Resets the fetch operation. Hit on window changes or sprite loads
  fetch.tick = 1
  fetch.mode = fmsReadTile

proc fetch(fetch: var Fetch): void =
  # Executes a fetch operation.
  # The fetch is running at 2Mhz so it only does something every other tick.
  # This increments and fast returns if we're only on the first tick.
  if 1 == fetch.tick:
    fetch.tick += 1
    return 

  # TODO: Actually make the fetcher DO something.

  # Increment the state machine
  if fmsReadTile == fetch.mode: fetch.mode = fmsReadData0
  if fmsReadData0 == fetch.mode: fetch.mode = fmsReadData1
  if fmsReadData1 == fetch.mode: fetch.mode = fmsIdle
  if fmsIdle == fetch.mode: fetch.resetFetch() # Reset the state machine

proc tickPixelTransfer(ppu: var PPU): void = 
  # Reset the PPU and aport
  if 160 == ppu.fifo.pixelTransferX:
    ppu.ly += 1
    ppu.mode = hBlank
    ppu.fifo.pixelTransferX = 0
    ppu.fifo.queueDepth = 0
    return

  if ppu.fifo.queueDepth >= 8:
    # Mix Pixels - Up to 10 cycles based on OAM Buffer
    for i in countup(1'u8, ppu.oamBuffer.idx):
      # Determine which entry wins and replace values in FIFO
      # Decode Palette
      break
    # Push Pixel to LCD Display
    ppu.fifo.queueDepth -= 1
    ppu.fifo.pixelTransferX += 1

proc tick*(ppu: var PPU) =
  # Processes a tick based on the system clock.

  # Rollover per Video Cycle - End of VBLANK
  if 17556 == ppu.clock: 
    ppu.ly = 0
    ppu.clock = 0
    for x in ppu.oamBuffer.data.mitems: x = 0 # Flush OAM Buffer
    ppu.mode = oamSearch
  
  if oamSearch == ppu.mode:
    ppu.tickOamSearch()
  
  if pixelTransfer == ppu.mode:
    ppu.tickPixelTransfer()

  # End H-BLank every 114 cycles - This is the difference between 144 - (OAM + Pixel Transfer)
  if (0 == ppu.clock mod 114 and ppu.mode == hBlank):
    ppu.mode = oamSearch # Update state machine
    # Update any requested values for window / scroll / Lyc
    ppu.scy = ppu.requestedScy
    ppu.scx = ppu.requestedScx
    ppu.lyc = ppu.requestedLyc
    ppu.wy = ppu.requestedWy
    ppu.wx = ppu.requestedWx
    
  # Override OAM Search if we hit VBlank
  if (144 == ppu.ly):
    ppu.mode = vBlank

  ppu.clock += 1
