import types
import cpu
import memory
proc powerOn(gameboy:var Gameboy) =
    gameboy.cpu.mem = newCPUMemory(gameboy)
    # CPU Initialization
    gameboy.cpu.a = 0x01'u8
    gameboy.cpu.f = 0xb0'u8    # Flags only
    gameboy.cpu.bc = 0x0013'u16
    gameboy.cpu.de = 0x00d8'u16
    gameboy.cpu.hl = 0x014d'u16
    gameboy.cpu.sp = 0xfffe'u16
    gameboy.cpu.pc = 0x0100'u16


proc newGameboy*(): Gameboy =
    new result
    result.powerOn

proc step*(gameboy: var Gameboy): string = 
    return gameboy.cpu.step()
