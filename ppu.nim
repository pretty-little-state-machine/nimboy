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
import bitops
import strutils
import deques
import types
import interrupts

proc newPPUGb*(gameboy: Gameboy): PPUGb =
  PPUGb(gameboy: gameboy)

template toSigned(x: uint16): int16 = cast[int16](x)

proc getTileNibble(ppu: PPU; tileNumber: uint16; row: uint8; byte: uint8): uint8 =
  # Returns the specific 2bb encoded byte of a sprite (4 dots)
  # This automatically determines the map and offset based 
  # on the LCDC settings
  
  # The tile number can either be calculated via signed or unsigned
  # but only for backgrounds and windows. Sprites are always unsigned.
  var tmpTileNum: int
  if testBit(ppu.lcdc, 4) and (ftBackground == ppu.fetch.entity or ftWindow == ppu.fetch.entity):
    tmpTileNum = toSigned(tileNumber)
  else:
    tmpTileNum = int(tileNumber)

  let address = (tmpTileNum * 16) + int(row * 2) + int(byte)
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
    return ppu.vRAMTileDataBank0[address - 0x8000]
  if address < 0x9C00:
    return ppu.vRAMBgMap1[address - 0x9800]
  if address < 0xA000:
    return ppu.vRAMBgMap1[address - 0x9C00]

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
  if 80 == ppu.oamBuffer.clock:
    ppu.oamBUffer.clock = 0
    ppu.mode = pixelTransfer
    return

  # Read two sprites per tick
  for offset in countup(0'u8, 1'u8):
    let entry = uint8((ppu.oamBuffer.clock) div 2)
    if (0 != ppu.readOamXCoord(entry)) and
      (ppu.ly + 16 >= ppu.readOamYCoord(entry)) and
      (ppu.ly + 16 < ppu.readOamYCoord(entry) + 8): # TODO: Pixel Height here.
      # Valid - Add to the allowed sprites on this scanline if we haven't seen it yet
      var oamEntry: OamEntry
      oamEntry.yCoord = ppu.readOamYCoord(entry)
      oamEntry.xCoord = ppu.readOamXCoord(entry) - 8
      oamEntry.tileNum = ppu.readOamTileNumber(entry)
      oamEntry.attr = ppu.readOamAttributes(entry)
      if not ppu.oamBuffer.data.contains(oamEntry):
        ppu.oamBuffer.data.addLast(oamEntry)
    ppu.oamBuffer.clock += 1

proc resetFetch(fetch: var Fetch): void =
  # Resets the fetch operation. Hit on window changes or sprite loads
  fetch.idle = false
  fetch.mode = fmsReadTile

proc tickFetch(ppu: var PPU; row: uint8;): void =
  # TODO: Background scrolling support
  case ppu.fetch.mode
  of fmsReadTile:
    ppu.fetch.mode = fmsReadData0
  of fmsReadData0:
    ppu.fetch.tmpByte0 = ppu.getTileNibble(ppu.fetch.targetTile, row, 0)
    ppu.fetch.mode = fmsReadData1
  of fmsReadData1:
    let byte1 = ppu.getTileNibble(ppu.fetch.targetTile, row, 1)
    let tmpData = decode2bbTileRow(ppu.fetch.tmpByte0, byte1)
    # Build up the 7 PixelFIFOEntry objects from the decoding
    for x in countup(0, 7):
      ppu.fetch.result[x].data = tmpData[x] 
      ppu.fetch.result[x].entity = ppu.fetch.entity
      ppu.fetch.mode = fmsIdle
    # Move the tile data up
    if ftSprite0 != ppu.fetch.entity and ftSprite1 != ppu.fetch.entity:
      ppu.fetch.tmpTileOffsetX += 1
  of fmsIdle:
    discard

proc pixelTransferComplete(ppu: var PPU): void =
    ppu.ly += 1
    ppu.mode = hBlank
    ppu.lx = 0
    ppu.fifo.clear()
    ppu.fetch.tmpTileOffsetX = 0
    ppu.fetch.willFetch = fWillFetchBackground

proc getCurrentTileNumber(ppu: var PPU): uint16 = 
  # Returns the current tile number to fetch based on type and LCDC
  var bitToRead = 3 # Default to Background
  if fWillFetchWindow == ppu.fetch.willFetch:
    bitToRead = 6
  let offset:uint = floorDiv(ppu.fetch.tmpTileOffsetY, 8).uint * 32 + ppu.fetch.tmpTileoffsetX.uint
  # Window and background may use either map
  if (ppu.lcdc.testBit(bitToRead)):
    return ppu.vRAMBgMap2[offset]
  else:
    return ppu.vRAMBgMap1[offset]

proc tickPixelTransfer(ppu: var PPU): void = 
  # Handles the Pixel Transfer mode of the PPU
  # Assume fetch will grab the BG. This may be overidden later
  if false == ppu.fifoPaused:
    ppu.fetch.targetTile = ppu.getCurrentTileNumber()
  var rowNumber = ppu.ly mod 8

  # Window enabled and xCoord hit? Reset fetch and start reading the window if we aren't already
  if ppu.lcdc.testBit(5) and ppu.wx == ppu.lx and fWillFetchWindow != ppu.fetch.willFetch:
    ppu.fetch.willFetch = fWillFetchWindow
    ppu.fetch.entity = ftWindow
    ppu.fifo.clear()
    ppu.fetch.resetFetch()

  # Attempt to puish the FIFO the LCD Output buffer. If a sprite is detected
  # the FIFO will be paused and fetch reset to grab a sprite. This will be 
  # overlayed on the existing FIFO data (first 8) before this is allowed to 
  # finish executing.
  block fifoOutput:
    if ppu.fifo.len >= 8 and false == ppu.fifoPaused:
      # Object Check!
      for entry in mitems(ppu.oamBuffer.data):
        if ppu.lx == entry.xCoord and false == ppu.fifoPaused and false == entry.drawn:
          #echo "lx: " & $ppu.lx & " ly: " & $ppu.ly & " object: " & $entry.tileNum
          entry.drawn = true # We're pulling it, scrub it from OAM
          ppu.fifoPaused = true
          ppu.fetch.willFetch = fWillFetchSprite
          ppu.fetch.targetTile = entry.tileNum
          rowNumber = ppu.ly - (entry.yCoord)
          ppu.fetch.entity = ftSprite0
          ppu.fetch.resetFetch()
          break fifoOutput # Break out until we resume FIFO post pixel fetch/mix
      # Push Pixel to LCD Display - This MUST be 32 bit integer!
      let offset = (ppu.ly.uint32 * 160) + ppu.lx.uint32
      let val = ppu.fifo.popFirst()
      ppu.outputBuffer[offset] = val
      ppu.lx += 1

  # If the FIFO is paused that means the fetcher is pulling pixels
  # These will be mixed here into the existing FIFO data (first 8)
  if fmsIdle == ppu.fetch.mode and true == ppu.fifoPaused:
    for x in countup(0x0, 0x7):
      # TODO MIX HERE - Right now it repclaces.
      ppu.fifo[x] = ppu.fetch.result[x]
    ppu.fetch.entity = ftBackground # Flip back to background fetches
    ppu.fifoPaused = false
    ppu.fetch.resetFetch()

  # Only run the fetcher every other tick - 2 Mhz equivalent clock
  if false == ppu.fetch.canRun:
    ppu.fetch.canRun = true
  else:
    ppu.tickFetch(rowNumber)
    ppu.fetch.canRun = false

  # Pull the data out of the fetch when FIFO has room
  # This is for window / background operations, not for Sprites!
  if fmsIdle == ppu.fetch.mode and ppu.fifo.len() <= 8 and false == ppu.fifoPaused:
    for x in countup(0x0, 0x7):
      ppu.fifo.addLast(ppu.fetch.result[x])
    ppu.fetch.resetFetch()

  # Pixel transfer complete - Switch to HBlank
  if 160 == ppu.lx:
    ppu.oamBuffer.data.clear()
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
    echo "------------------"
    ppu.ly = 0
    ppu.clock = 0
    ppu.mode = oamSearch
    ppu.fetch.canRun = true
    ppu.fetch.tmpTileOffsetY = 0
  
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
  elif address < 0xFEA0:
    ppu.oam[address - 0xFE00] = value
