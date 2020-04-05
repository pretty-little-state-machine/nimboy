
import strutils
import bitops
# Nimboy imports
import types
import cpu
import cartridge
import debugger

proc powerOn(gameboy:var Gameboy) =
    # CPU Initialization
    gameboy.cpu.a = 0x01'u8
    gameboy.cpu.b = 0x13'u8 shr 8
    gameboy.cpu.c = 0x13'u8 
    gameboy.cpu.d = 0xd8'u8 shr 8
    gameboy.cpu.e = 0xd8'u8
    gameboy.cpu.sp = 0xfffe'u16
    gameboy.cpu.pc = 0x0100'u16

proc newGameboy(): Gameboy =
    new result
    result.powerOn
 
proc readByte(gameboy: Gameboy, address: uint16): uint8 =
    if address < 0x8000:
        return gameboy.cartridge.readByte(address)
    if address < 0xA000:
        debugEcho("MEMREAD: ", $toHex(address), " : Video RAM")
        return 1
    if address < 0xC000:
        return gameboy.cartridge.readByte(address)
    else:
        debugEcho("MEMREAD: ", $toHex(address), " : NOT IMPLEMENTED")
        return 1

proc writeByte(gameboy: Gameboy, address: uint16, value: uint8): uint8 =
    if address < 0x8000:
        return gameboy.cartridge.writeByte(address, value)
    if address < 0xA000:
        debugEcho("MEMWRITE: ", $toHex(address), " : Video RAM")
        return 1
    if address < 0xC000:
        return gameboy.cartridge.writeByte(address, value)
    else:
        debugEcho("MEMWRITE: ", $toHex(address), " : NOT IMPLEMENTED")
        return 1

# MAIN
var gameboy = newGameboy()
#echo repr(gameboy.cpu)
#echo gameboy.readByte(0xB001)
#echo gameboy.writeByte(0xB001, 0xff)
#echo gameboy.readByte(0xB001)
#echo repr(gameboy.cpu)

#gameboy.cartridge.loadRomFile("./roms/tetris.gb")

#for x in countup(0x100, 0x1FF):
#  discard gameboy.readByte(uint16(x))

#gameboy.cartridge.displayROMData()
launchDebugger(gameboy)
