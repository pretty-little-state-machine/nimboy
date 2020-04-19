import random
import types
import cpu
import memory
import timer
import vpu

proc powerOn(gameboy:var Gameboy) =
    gameboy.intEnable = 0xFF'u8
    gameboy.cpu.mem = newCPUMemory(gameboy)
    gameboy.timer.gb = newTimerGb(gameboy)
    gameboy.vpu.gb = newVPUGb(gameboy)
    gameboy.gameboyMode = mgb
    # CPU Initialization
    gameboy.cpu.a = 0x01'u8
    gameboy.cpu.f = 0xb0'u8    # Flags only
    gameboy.cpu.bc = 0x0013'u16
    gameboy.cpu.de = 0x00d8'u16
    gameboy.cpu.hl = 0x014d'u16
    gameboy.cpu.sp = 0xfffe'u16
    gameboy.cpu.pc = 0x0100'u16 # Cheating to avoid bootloader
    gameboy.cpu.ime = false     # CPU always must boot with interrupts disabled
    # Timer Initilzation
    gameboy.timer.timaCounter = 0x00'u8
    gameboy.timer.timaModulo = 0x00'u8
    gameboy.timer.tac = 0x00'u8
    # VPU Initialization
    gameboy.vpu.lcdc = 0x91'u8
    gameboy.vpu.scx = 0x00'u8
    gameboy.vpu.scy = 0x00'u8
    gameboy.vpu.lyc = 0x00'u8
    gameboy.vpu.bgp = 0xFC'u8  # The real one - blank and white by default
    #gameboy.vpu.bgp = 0x1B'u8 # Fake testing one - 4 colours
    gameboy.vpu.obp1 = 0xFF'u8
    gameboy.vpu.obp2 = 0xFF'u8
    gameboy.vpu.wx = 0x00'u8
    gameboy.vpu.wy = 0x00'u8
    # A real gameboy has noise in the ram on boot
    randomize()
    for x in gameboy.vpu.vRAMTileDataBank0.mitems: x = uint8(rand(1))
    for x in gameboy.vpu.vRAMTileDataBank1.mitems: x = uint8(rand(1))
    
proc newGameboy*(): Gameboy =
    new result
    result.powerOn

proc step*(gameboy: var Gameboy): TickResult = 
    result = gameboy.cpu.step()
    for t in countup(1, result.tClock):
      gameboy.timer.tick()
 
