import random
import types
import cpu
import memory
import timer
import ppu

proc powerOn(gameboy:var Gameboy) =
    gameboy.intEnable = 0xFF'u8
    gameboy.cpu.mem = newCPUMemory(gameboy)
    gameboy.timer.gb = newTimerGb(gameboy)
    gameboy.ppu.gb = newPPUGb(gameboy)
    gameboy.gameboyMode = mgb
    # CPU Initialization
    gameboy.cpu.a = 0x01'u8
    gameboy.cpu.f = 0xb0'u8    # Flags only
    gameboy.cpu.bc = 0x0013'u16
    gameboy.cpu.de = 0x00d8'u16
    gameboy.cpu.hl = 0x014d'u16
    gameboy.cpu.sp = 0xfffe'u16
    #gameboy.cpu.pc = 0x0100'u16 # Cheating to avoid bootloader
    gameboy.cpu.pc = 0x0000'u16 
    gameboy.cpu.ime = false     # CPU always must boot with interrupts disabled
    # Timer Initilzation
    gameboy.timer.timaCounter = 0x00'u8
    gameboy.timer.timaModulo = 0x00'u8
    gameboy.timer.tac = 0x00'u8
    # PPU Initialization
    gameboy.ppu.lcdc = 0x91'u8
    gameboy.ppu.scx = 0x00'u8
    gameboy.ppu.scy = 0x00'u8
    gameboy.ppu.lyc = 0x00'u8
    gameboy.ppu.bgp = 0xFC'u8  # The real one - blank and white by default
    #gameboy.ppu.bgp = 0x1B'u8 # Fake testing one - 4 colours
    gameboy.ppu.obp0 = 0xFF'u8
    gameboy.ppu.obp1 = 0xFF'u8
    gameboy.ppu.wx = 0x00'u8
    gameboy.ppu.wy = 0x00'u8
    gameboy.ppu.mode = oamSearch
    # A real gameboy has noise in the ram on boot
    randomize()
    for x in gameboy.ppu.vRAMTileDataBank0.mitems: x = uint8(rand(1))
    for x in gameboy.ppu.vRAMTileDataBank1.mitems: x = uint8(rand(1))
    # Breakpoint 
    gameboy.cpu.breakpoint = 0xFFFF # So we don't accidentally trigger it.
    
proc newGameboy*(): Gameboy =
    new result
    result.powerOn

proc step*(gameboy: var Gameboy): TickResult = 
    result = gameboy.cpu.step()
    for t in countup(1, result.tClock):
      gameboy.timer.tick()
      gameboy.ppu.tick()
