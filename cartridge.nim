import algorithm
import streams
import strutils
import nimboyutils

type
  Cartridge* = object
    loaded: bool
    fixedROM: array[16*1024'u16, uint8]        # 16KB of Fixed ROM Bank 0 ($0000-$3FFF)
    internalROM: array[128*16*1024'u32, uint8] # 2MB Max rom size - MBC3 (128 Banks of 16K)
    internalRAM: array[4*8*1024'u16, uint8]    # 32KB Max RAM size - MBC3 (4 banks of 8K)
    romPage: uint16
    ramPage: uint16
    writeEnabeld: bool

# Reads a byte from the cartridge with paging. 
# Valid address requests directed to this proc:
#
# $0000 - $3FFF - 16K Fixed ROM
# $4000 - $7FFF - 16K Paged ROM
# $A000 - $BFFF -  8K Paged RAM
proc readByte*(cartridge: Cartridge; address: uint16):uint8 {.noSideEffect.} =    
  if address < 0x4000:
    let value = cartridge.fixedROM[address]
    debugEcho("MEMREAD: ", $toHex(address), " : ", $toHex(address), " : ", $toHex(value), " : ", "Cartridge Fixed ROM")
    return value
  elif address < 0x8000:
    let offset = (cartridge.romPage * 8192) + address - 0x4000
    debugEcho("MEMREAD: ", $toHex(address), " : ", $toHex(offset) , " : Cartridge Paged ROM : Page ", cartridge.romPage)
    return cartridge.internalROM[offset]
  else:
    let offset = (cartridge.ramPage * 8192) + address - 0xA000
    debugEcho("MEMREAD: ", $toHex(address), " : ", $toHex(offset) , " : Cartridge Paged RAM : Page ", cartridge.romPage)
    return cartridge.internalRAM[offset]



# Reads a byte from the cartridge with paging. 
# Valid address requests directed to this proc:
#
# $0000 - $3FFF - 16K Fixed ROM
# $4000 - $7FFF - 16K Paged ROM
# $A000 - $BFFF -  8K Paged RAM
#
# TODO: Handle the million MBC models and pagination and all sorts of stuff!
proc writeByte*(cartridge: var Cartridge; address: uint16; value: uint8):uint8 =
  if address < 0x4000:
    debugEcho("MEMWRITE: ", $toHex(address), " : ", $toHex(address), " : TODO: PAGING")
    return cartridge.fixedROM[address]
  if address < 0x8000:
    let offset = (cartridge.romPage * 8192) + address - 0x4000
    debugEcho("MEMWRITE: ", $toHex(address), " : ", $toHex(address), " : TODO: PAGING")
    return cartridge.internalROM[offset]
  else:
    let offset = (cartridge.ramPage * 8192) + address - 0xA000
    debugEcho("MEMWRITE: ", $toHex(address), " : ", $toHex(offset) , " : Cartridge Paged RAM : Page ", cartridge.romPage)
    cartridge.internalRAM[offset] = value
    return cartridge.internalRAM[offset]

proc loadRomFile*(cartridge: var Cartridge; path: string) = 
  var stream = newFileStream(path)
  discard stream.readData(addr(cartridge.fixedROM), 16384)
  discard stream.readData(addr(cartridge.internalROM), 2097152)
  cartridge.loaded = true
  stream.close()

proc unloadRom*(cartridge: var Cartridge) = 
  cartridge.fixedROM.fill(0)
  cartridge.internalROM.fill(0)
  cartridge.internalRAM.fill(0)
  cartridge.loaded = false

proc getRomTitle*(cartridge: Cartridge): string =
  if cartridge.loaded:
    return byteSeqToString(cartridge.fixedROM[0x0134..0x142])
  else:
    return "No ROM Loaded"

