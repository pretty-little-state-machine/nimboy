import algorithm
import streams
import strutils
import bitops
import os
import types
import nimboyutils



proc isMBC1(cartridge: Cartridge): bool =
  case (cartridge.fixedROM[0x0147]):
  of 0x01: true
  of 0x02: true
  of 0x03: true
  else:
    false

proc isMBC2(cartridge: Cartridge): bool =
  case (cartridge.fixedROM[0x0147]):
  of 0x05: true
  of 0x06: true
  else:
    false

proc isMBC3(cartridge: Cartridge): bool =
  case (cartridge.fixedROM[0x0147]):
  of 0x0F: true
  of 0x10: true
  of 0x11: true
  of 0x12: true
  of 0x13: true  
  else:
    false

proc isMBC5(cartridge: Cartridge): bool =
  case (cartridge.fixedROM[0x0147]):
  of 0x19: true
  of 0x1A: true
  of 0x1B: true
  of 0x1C: true
  of 0x1D: true
  of 0x1E: true      
  else:
    false

proc writeByteMBC1(cartridge: var Cartridge; address: uint16; value: uint8): void =
  # Handles MBC 1 paging behavior
  # Valid write locations range from 0x0000 -> 0xBFFF 
  # RAM Enable
  if address < 0x2000:
    # Pretty much any value with the lower four bits set to 0x0A will enable RAM
    if 0x0A00 == (value shl 4):
      cartridge.ramEnabled = true
    else:
      cartridge.ramEnabled = false
  # This register stores the lower 5 bits of what ROM page to use.
  elif address < 0x4000:
    let lower5bits = bitand(value, 0b0001_1111)
    case (lower5bits):
    of 0x00:
      cartridge.mbc1RomBankSelect = 0x01
    of 0x20:
      cartridge.mbc1RomBankSelect = 0x21
    of 0x40:
      cartridge.mbc1RomBankSelect = 0x41
    of 0x60:
      cartridge.mbc1RomBankSelect = 0x61
    else:
      cartridge.mbc1RomBankSelect = lower5bits
  # This register stores the RAM bank number OR the ROM bank upper 2 bits
  elif address < 0x6000:
    cartridge.mbc1RamRomBankSelect = bitand(value, 0b0000_0011)
  # This register stores the _behavior_ of the register above this one (RAM or ROM mode)
  elif address < 0x8000:
    cartridge.mbc1RomRamModeRegister = bitand(value, 0b0000_0001)
  # Not a valid ROM write register
  elif address < 0xA000:
    discard
  # RAM Page
  elif address < 0xC000:
    # RAM paging mode must be set to write to _any_ RAM page
    if 0x01 == cartridge.mbc1RomRamModeRegister:
      cartridge.internalRAM[uint16(cartridge.mbc1RamRomBankSelect * 16384) + (address - 0xA000)] = value
    else:
      discard
  else:
    discard

proc writeByteMBC2(cartridge: var Cartridge; address: uint16; value: uint8): void =
  # TODO: Handles MBC 2 paging behavior
  discard

proc writeByteMBC3(cartridge: var Cartridge; address: uint16; value: uint8): void =
  # TODO: Handles MBC 3 paging behavior
  discard

proc writeByteMBC5(cartridge: var Cartridge; address: uint16; value: uint8): void =
  # TODO: Handles MBC 5 paging behavior
  discard

proc writeByte*(cartridge: var Cartridge; address: uint16; value: uint8): void =
  # Writes a byte from to cartridge with paging depending on the MBC (if present)
  if isMBC1(cartridge):
    writeByteMBC1(cartridge, address, value)
  elif isMBC2(cartridge):
    writeByteMBC2(cartridge, address, value)    
  elif isMBC3(cartridge):
    writeByteMBC3(cartridge, address, value)
  elif isMBC5(cartridge):
    writeByteMBC5(cartridge, address, value)   
  else:
    # No MBC? No problem! Only RAM address range writes are allowed
    if address > 0x7FFF:
      cartridge.internalRAM[address - 0xA000] = value

proc readByteMBC1*(cartridge: Cartridge; address: uint16): uint8 {.noSideEffect.} =
  # ROM Page 0 - Always present
  if address < 0x4000:
    return cartridge.fixedROM[address]
  # Paged ROM
  elif address < 0x8000 and 0x00 == cartridge.mbc1RomRamModeRegister:
    # Bank number is deprecated since since ROM reading stream starts at index 0
    let 
      bankNumber = bitor((cartridge.mbc1RamRomBankSelect shl 4), cartridge.mbc1RomBankSelect) - 1 
      offset = uint16(bankNumber * 16384 + (address - 0x4000))
    return cartridge.internalROM[offset]
  # RAM Pages
  elif address < 0xC000 and 0x01 == cartridge.mbc1RomRamModeRegister:
    let 
      bankNumber = cartridge.mbc1RamRomBankSelect
      offset = uint16(bankNumber * 16384 + (address - 0xA000))
    return cartridge.internalRAM[offset]
  # Inavlid read attempts. Return 0
  else:
    return 0

proc readByteMBC2*(cartridge: Cartridge; address: uint16): uint8 {.noSideEffect.} =
  # TODO: Returns a read from an MBC5 cartridge
  return 0
proc readByteMBC3*(cartridge: Cartridge; address: uint16): uint8 {.noSideEffect.} =
  # TODO: Returns a read from an MBC5 cartridge
  return 0
proc readByteMBC5*(cartridge: Cartridge; address: uint16): uint8 {.noSideEffect.} =
  # TODO: Returns a read from an MBC5 cartridge
  return 0

proc readByte*(cartridge: Cartridge; address: uint16): uint8 {.noSideEffect.} =
  # Reads a byte from the cartridge with paging on the appropriate MBC (if present)
  if address < 0x4000:
    return cartridge.fixedROM[address]
  # Writes a byte from to cartridge with paging depending on the MBC
  if isMBC1(cartridge):
     return readByteMBC1(cartridge, address)
  elif isMBC2(cartridge):
    return readByteMBC2(cartridge, address)    
  elif isMBC3(cartridge):
    return readByteMBC3(cartridge, address)
  elif isMBC5(cartridge):
    return readByteMBC5(cartridge, address)   
  else:
    # No MBC? No problem! Have the built-in RAM and ROM (if it's even there)
    if address < 0x8000:
      return cartridge.internalROM[address - 0x4000]
    else:
      return cartridge.internalRAM[address - 0xA000]

proc loadRomFile*(cartridge: var Cartridge; path: string) = 
  # Loads a ROM file into the internal ROM.
  if existsFile(path):
    var stream = newFileStream(path)
    discard stream.readData(addr(cartridge.fixedROM), cartridge.fixedROM.len)
    discard stream.readData(addr(cartridge.internalROM), cartridge.internalROM.len)
    cartridge.loaded = true
    stream.close()
  else:
    discard

proc unloadRom*(cartridge: var Cartridge) = 
  # Zeros the cartridge internal ROMs and zeroes cartridge RAM.
  cartridge.fixedROM.fill(0)
  cartridge.internalROM.fill(0)
  cartridge.internalRAM.fill(0)
  cartridge.loaded = false

proc getRomDetailStr*(cartridge: Cartridge): string =
  # Returns a string with all the ROM details decoded in human format
  if not cartridge.loaded: return "No ROM Loaded"
  var s: string
  # Title
  s &= byteSeqToString(cartridge.fixedROM[0x0134..0x142])
  # Cartridge Type
  s &= " - "
  case (cartridge.fixedROM[0x0147]):
  of 0x00: s &= "ROM ONLY"
  of 0x01: s &= "ROM + MBC1"
  of 0x02: s &= "ROM + MBC1 + RAM"
  of 0x03: s &= "ROM + MBC1 + Battery"
  of 0x05: s &= "ROM + MBC2"
  of 0x06: s &= "ROM + MBC2 + Battery"
  of 0x08: s &= "ROM + RAM"
  of 0x09: s &= "ROM + RAM + Battery"
  of 0x0B: s &= "ROM + MMM01"
  of 0x0C: s &= "ROM + MMM01 + SRAM"
  of 0x0D: s &= "ROM + MMM01 + SRAM + Battery"
  of 0x0F: s &= "ROM + MBC3 + Timer + Battery"
  of 0x10: s &= "ROM + MBC3 + RAM + Timer + Battery"
  of 0x11: s &= "ROM + MBC3"
  of 0x12: s &= "ROM + MBC3 + RAM"
  of 0x13: s &= "ROM + MBC3 + RAM + Battery"
  of 0x19: s &= "ROM + MBC5"
  of 0x1A: s &= "ROM + MBC5 + RAM"
  of 0x1B: s &= "ROM + MBC5 + RAM + Battery"
  of 0x1C: s &= "ROM + MBC5 + Rumble"
  of 0x1D: s &= "ROM + MBC5 + Rumble + SRAM"
  of 0x1E: s &= "ROM + MBC5 + Rumble + SRAM + Battery"
  of 0x1F: s &= "Pocket Camera"
  of 0xFD: s &= "Bandai TAMA5"
  of 0xFE: s &= "Hudson HuC-3"
  of 0xFF: s &= "Hudson HuC-1"
  else:    s &= "Unknown Cartridge Type"
  #ROM
  s &= " - "
  case (cartridge.fixedROM[0x0148]):
  of 0x00: s &= "256 Kbit ROM (2 Banks)"
  of 0x01: s &= "512 Kbit ROM (4 Banks)"
  of 0x02: s &= "1 Mbit ROM (8 Banks)"
  of 0x03: s &= "2 Mbit ROM (16 Banks)"
  of 0x04: s &= "4 Mbit ROM (32 Banks)"
  of 0x05: s &= "8 Mbit ROM (64 Banks)"
  of 0x06: s &= "16 Mbit ROM (128 Banks)"
  of 0x52: s &= "9 Mbit ROM (72 Banks)"
  of 0x53: s &= "10 Mbit ROM (80 Banks)"
  of 0x54: s &= "12 Mbit ROM (96 Banks)"
  else:    s &= "Unknown ROM Configuration"
  # RAM
  s &= " - "
  case (cartridge.fixedROM[0x0149]):
  of 0x00: s &= "No RAM"
  of 0x01: s &= "16 Kbit RAM (1 Bank)"
  of 0x02: s &= "64 Kbit RAM (1 Bank)"
  of 0x03: s &= "256 Kbit RAM (4 Banks)"
  of 0x04: s &= "1 Mbit RAM (16 Banks)"
  else:    s &= "Unknown RAM Configuration"
  return s