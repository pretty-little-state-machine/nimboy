# Pixel Processing Unit
# 
# This chip is responsible for displaying graphics on the screen. This program
# implements the PPU using a simple rendering pipeline as shown:
#
# WATCH THIS: https://www.youtube.com/watch?v=HyzD8pNlpwI&t=29m12s
# 
# And read this: http://blog.kevtris.org/blogfiles/Nitty%20Gritty%20Gameboy%20VRAM%20Timing.txt
#
# The PPU will populate an array of palette lookups as pixels along with the data
# for the palette to use. The PPU will handle priority, the SDL rendering engine
# will not any "PPU logic" other than decoding the color space from the palettes.
# 
# See the PixelFIFOEntry type defintion to see what goes to the SDL rendering 
# (or whatever else) that is used.
#
import math
import system
import strutils
import bitops
import deques
import types
import interrupts

proc newPPUGb*(gameboy: Gameboy): PPUGb =
  PPUGb(gameboy: gameboy)

template toSigned(x: uint16): int16 = cast[int16](x)

proc getWindowTileNibble(ppu: PPU; tileNumber: uint16; row: uint8; byte: uint8): uint8 =
  # Returns the specific 2bb encoded byte of a sprite (4 dots)
  # This automatically determines the map and offset based 
  # on the LCDC settings
  
  # The tile number can either be calculated via signed or unsigned
  var tmpTileNum: int
  if testBit(ppu.lcdc, 4): 
    tmpTileNum = toSigned(tileNumber)
  else:
    tmpTileNum = int(tileNumber)
  let address = (tmpTileNum * 16) + int(row * 2) + int(byte)
  #echo $tmpTileNum & ":" & $toHex(address) & ":" & $row & ":" & $byte
  # Load in the result data  TODO: This might need multiplcate on tilenumber by 16?
  result = ppu.vRAMTileDataBank0[address]

proc decode2bbTileRow*(lByte: uint8; hByte: uint8): array[8, uint8] =
  # Decodes a sprite row encoded with the 2BB format
  # See https://www.huderlem.com/demos/gameboy2bpp.html for how this works.
  var offset = 0'u8
  for i in countdown(7, 0):
    if lByte.testBit(i): result[offset] += 2
    if hByte.testBit(i): result[offset] += 1
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
  fetch.idle = false
  fetch.mode = fmsReadTile

proc tickFetch(ppu: var PPU; row: uint8): void =
  # Executes a fetch operation.
  # TODO: Background scrolling support
  case ppu.fetch.mode
  of fmsReadTile:
   # let 
   #   x = floorDiv(ppu.lx, 8)
   #   y = floorDiv(ppu.ly, 8)
   #   offset = (y * 32) + x 
   # echo "READ TILE - " & $offset & " : " & $x & " , " & $y
    let offset:uint = floorDiv(ppu.fetch.tmpTileOffsetY, 8).uint * 32 + ppu.fetch.tmpTileoffsetX.uint
    if (ppu.lcdc.testBit(3)):
      ppu.fetch.tmpTileNum = ppu.vRAMBgMap2[offset]
    else:
      ppu.fetch.tmpTileNum = ppu.vRAMBgMap1[offset]
    ppu.fetch.mode = fmsReadData0
  of fmsReadData0:
    ppu.fetch.tmpByte0 = ppu.getWindowTileNibble(ppu.fetch.tmpTileNum, row, 0)
    ppu.fetch.mode = fmsReadData1
  of fmsReadData1:
    let byte1 = ppu.getWindowTileNibble(ppu.fetch.tmpTileNum, row, 1)
    let tmpData = decode2bbTileRow(ppu.fetch.tmpByte0, byte1)
    # Build up the 7 PixelFIFOEntry objects from the decoding
    for x in countup(0, 7):
      ppu.fetch.result[x].data = tmpData[x] 
      ppu.fetch.result[x].entity = ppu.fetch.entity
      ppu.fetch.mode = fmsIdle
    # Move the tile data up
    ppu.fetch.tmpTileOffsetX += 1
  of fmsIdle:
    discard

proc pixelTransferComplete(ppu: var PPU): void =
    ppu.ly += 1
    ppu.mode = hBlank
    ppu.lx = 0
    ppu.fifo.clear()
    ppu.fetch.tmpTileOffsetX = 0

proc tickPixelTransfer(ppu: var PPU): void = 
  # Handles the Pixel Transfer mode of the PPU
  # TODO Add sprite detection
  if ppu.fifo.len > 8:
    # Mix Pixels - Up to 10 cycles based on OAM Buffer
    #for i in countup(1'u8, ppu.oamBuffer.idx):
      # Determine which entry wins and replace values in FIFO
      # Decode Palette
      #break
    # Push Pixel to LCD Display - This MUST be 32 bit integer!
    let offset = (ppu.ly.uint32 * 160) + ppu.lx.uint32
    ppu.outputBuffer[offset] = ppu.fifo.popFirst()
    ppu.lx += 1

  # Only run the fetcher every other tick.
  if false == ppu.fetch.canRun:
    ppu.fetch.canRun = true
  else:
    ppu.tickFetch(ppu.ly mod 8)
    ppu.fetch.canRun = false

  # Pull the data out of the fetch when FIFO has room
  if fmsIdle == ppu.fetch.mode and ppu.fifo.len() <= 8:
    for x in countup(0x0, 0x7):
      ppu.fifo.addLast(ppu.fetch.result[x])
    ppu.fetch.resetFetch()

  # Pixel transfer complete - Switch to HBlank
  if 160 == ppu.lx:
    ppu.pixelTransferComplete()
    ppu.fetch.tmpTileOffsetY += 1
 
proc hBlankUpdates(ppu: var PPU): void =
  # Writes in any requested memory settings for the PPU during the H-Blank
  ppu.scy = ppu.requestedScy
  ppu.scx = ppu.requestedScx
  ppu.lyc = ppu.requestedLyc
  ppu.wy = ppu.requestedWy
  ppu.wx = ppu.requestedWx

proc isRefreshed(ppu: PPU): bool =
  17556 == ppu.clock

proc tick*(ppu: var PPU) =
  # Processes a tick based on the system clock.
  # 
  # This runs through four modes in a state machine:
  # (oamSearch -> pixelTransfer -> hBlank) x 144 -> VLBLANK -> Repeat....
  # This takes exactly 17556 machine cycles (ticks) to go through one rotation.
  # Rollover per Video Cycle - End of VBLANK
  if ppu.isRefreshed:
    ppu.ly = 0
    ppu.clock = 0
    for x in ppu.oamBuffer.data.mitems: x = 0 # Flush OAM Buffer
    ppu.mode = oamSearch
    ppu.fetch.canRun = true
    ppu.fetch.tmpTileOffsetY = 0
    #ppu.vBlankPrimed = true
  
  if oamSearch == ppu.mode:
    ppu.vBlankPrimed = true
    ppu.tickOamSearch()
  
  if pixelTransfer == ppu.mode:
    for f in countup(1, 4): # 4 times faster than CPU
      ppu.tickPixelTransfer()

  # End H-BLank every 114 cycles - This is the difference between 144 - (OAM + Pixel Transfer)
  if (0 == ppu.clock mod 114 and ppu.mode == hBlank):
    ppu.hBlankUpdates()
    ppu.mode = oamSearch # Set the state machine
    
  # Override OAM Search if we hit VBlank
  if (144 == ppu.ly):
    ppu.mode = vBlank
    #quit("")

  # Update vBlank interrupt and set primed to false so it doesn't keep
  # triggering continually during vBlank
  if vBlank == ppu.mode and ppu.vBlankPrimed:
    ppu.gb.gameboy.triggerVSyncInterrupt()
    ppu.vBlankPrimed = false

  # LY keeps counting up every 114 clocks during vBlank (up to 153)
  if vBlank == ppu.mode and 0 == ppu.clock mod 114:
    ppu.ly += 1

  ppu.clock += 1

proc writeByte*(ppu: var PPU; address: uint16; value: uint8): void =
  # Writes a byte from the cartridge with paging. 
  # Valid address requests directed to this proc:
  #
  # MAPPED locations
  # $8000 - $9FFF
  #
  # TODO: Handle the various paging models
  if address < 0x9800:
    ppu.vRAMTileDataBank0[address - 0x8000] = value
  elif address < 0x9C00:
    ppu.vRAMBgMap1[address - 0x9800] = value
  elif address < 0xA000:
    ppu.vRAMBgMap2[address - 0x9C00] = value


