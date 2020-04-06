import types
import cpu
import memory
proc powerOn(gameboy:var Gameboy) =
    gameboy.cpu.mem = newCPUMemory(gameboy)
    # CPU Initialization
    gameboy.cpu.a = 0x01'u8
    gameboy.cpu.b = 0x13'u8 shr 8
    gameboy.cpu.c = 0x13'u8 
    gameboy.cpu.d = 0xd8'u8 shr 8
    gameboy.cpu.e = 0xd8'u8
    gameboy.cpu.f = 0xb0'u8
    gameboy.cpu.h = 0x01'u8
    gameboy.cpu.l = 0x4d'u8
    gameboy.cpu.sp = 0xfffe'u16
    gameboy.cpu.pc = 0x0100'u16

proc newGameboy*(): Gameboy =
    new result
    result.powerOn

proc step*(gameboy: var Gameboy): string = 
    return gameboy.cpu.step()
