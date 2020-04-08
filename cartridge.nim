import algorithm
import streams
import os
import types
import nimboyutils

proc readByte*(cartridge: Cartridge; address: uint16): uint8 {.noSideEffect.} =
  # Reads a byte from the cartridge with paging. 
  # Valid address requests directed to this proc:
  #
  # $0000 - $3FFF - 16K Fixed ROM
  # $4000 - $7FFF - 16K Paged ROM
  # $A000 - $BFFF -  8K Paged RAM 
  if address < 0x4000:
    return cartridge.fixedROM[address]
  elif address < 0x8000:
    let offset = (cartridge.romPage * 8192) + address - 0x4000
    return cartridge.internalROM[offset]
  else:
    let offset = (cartridge.ramPage * 8192) + address - 0xA000
    return cartridge.internalRAM[offset]

proc writeByte*(cartridge: var Cartridge; address: uint16; value: uint8): void =
  # Reads a byte from the cartridge with paging. 
  # Valid address requests directed to this proc:
  #
  # $0000 - $3FFF - 16K Fixed ROM
  # $4000 - $7FFF - 16K Paged ROM
  # $A000 - $BFFF -  8K Paged RAM
  #
  # TODO: Handle the million MBC models and pagination and all sorts of stuff!
  if address < 0x4000:
    cartridge.fixedROM[address] = value
  if address < 0x8000:
    let offset = (cartridge.romPage * 8192) + address - 0x4000
    cartridge.internalROM[offset] = value
  else:
    let offset = (cartridge.ramPage * 8192) + address - 0xA000
    cartridge.internalRAM[offset] = value

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