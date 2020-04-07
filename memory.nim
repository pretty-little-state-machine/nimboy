import strutils
import types
import cartridge

export types.CPUMemory

proc readByte*(gameboy: Gameboy, address: uint16): uint8 =
    if address < 0x8000:
        return gameboy.cartridge.readByte(address)
    if address < 0xA000:
        #debugEcho("MEMREAD: ", $toHex(address), " : Video RAM")
        return 1
    if address < 0xC000:
        return gameboy.cartridge.readByte(address)
    else:
        #debugEcho("MEMREAD: ", $toHex(address), " : NOT IMPLEMENTED")
        return 1

proc writeByte*(gameboy: Gameboy, address: uint16, value: uint8): uint8 =
    if address < 0x8000:
        return gameboy.cartridge.writeByte(address, value)
    if address < 0xA000:
        #debugEcho("MEMWRITE: ", $toHex(address), " : Video RAM")
        return 1
    if address < 0xC000:
        return gameboy.cartridge.writeByte(address, value)
    else:
        #debugEcho("MEMWRITE: ", $toHex(address), " : NOT IMPLEMENTED")
        return 1

proc newCPUMemory*(gameboy: Gameboy): CPUMemory =
  CPUMemory(gameboy: gameboy)