import bitops
import types
import cpu
import memory
import timer

proc powerOn(gameboy:var Gameboy) =
    gameboy.intEnable = 0xFA'u8 # TODO IS THIS RIGHT
    gameboy.cpu.mem = newCPUMemory(gameboy)
    # CPU Initialization
    gameboy.cpu.a = 0x01'u8
    gameboy.cpu.f = 0xb0'u8    # Flags only
    gameboy.cpu.bc = 0x0013'u16
    gameboy.cpu.de = 0x00d8'u16
    gameboy.cpu.hl = 0x014d'u16
    gameboy.cpu.sp = 0xfffe'u16
    gameboy.cpu.pc = 0x0100'u16
    gameboy.cpu.intStatus = true


proc newGameboy*(): Gameboy =
    new result
    result.powerOn

proc step*(gameboy: var Gameboy): string = 
    gameboy.timer.tick()
    return gameboy.cpu.step()
