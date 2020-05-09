import types
import bitops
import cartridge
import ppu
import timer
import strutils

export types.CPUMemory

# Headers so DMA can work on them.
proc readByte*(gameboy: Gameboy, address: uint16): uint8;
proc writeByte*(gameboy: Gameboy; address: uint16; value: uint8);

proc dmaTransfer(gameboy:Gameboy): void =
  # Moves a block of RAM / ROM to Video OAM (0xFE00-0xFE9F)
  # TODO: This does NOT wait for 160 cycles to finish at this time
  let startingAddress = (gameboy.readbyte(0xFF46).uint16 shl 8)
  for address in countup(0'u16, 0x9F):
    gameboy.writeByte(0xFE00'u16 + address, gameboy.readByte(startingAddress))

proc readByte*(gameboy: Gameboy, address: uint16): uint8 =
  # 0x0000 -> 0x3FFF (Cartridge ROM Bank 00)
  # 0x4000 -> 0x7FFF (Cartridge Rom Bank 01 / Switched)
  if address < 0x8000:
    return gameboy.cartridge.readByte(address)
  # 0x8000 -> 0x9FFF (VRAM - Bank 0 & 1 if Color Gameboy)  
  if address < 0xA000:
    return gameboy.ppu.readByte(address)
  # 0xA000 -> 0xBFFF (Cartridge RAM Bank 0)
  if address < 0xC000:
    return gameboy.cartridge.readByte(address)
  # 0xC000 -> 0xDFFF (Work RAM Bank 0)
  if address < 0xE000:
    return gameboy.internalRamBank0[address - 0xC000]
  # 0xE000 -> 0xFDFF (Echo Ram)
  if address < 0xFE00:
    return gameboy.internalRamBank0[address - 0xE000]
  # 0xFE00 -> 0xFE9F (PPU Object Attribute Map - OAM)
  if address < 0xFEA0:
    return gameboy.ppu.readByte(address)
  # 0xFEA0 - 0xFEFF (Unused, always 0)
  if address < 0xFF00:
    return 0
  # Joypad
  if 0xFF00 == address:
    return gameboy.joypad
  # TIMER Registers
  if 0xFF04 == address:
    return gameboy.timer.readDiv()
  if 0xFF05 == address:
    return gameboy.timer.timaCounter
  if 0xFF06 == address:
    return gameboy.timer.timaModulo
  if 0xFF07 == address:
    return gameboy.timer.tac
  # Interrupts
  if 0xFF0F == address:
    return gameboy.intFlag
  # PPU Allocations
  if 0xFF40 == address:
    return gameboy.ppu.lcdc
  if 0xFF41 == address:
    return gameboy.ppu.stat
  if 0xFF42 == address:
    return gameboy.ppu.scy
  if 0xFF43 == address:
    return gameboy.ppu.scx
  if 0xFF44 == address:
    return gameboy.ppu.ly
  if 0xFF45 == address:
    return gameboy.ppu.lyc
  if 0xFF46 == address:
    return gameboy.ppu.dma
  if 0xFF47 == address:
    return gameboy.ppu.bgp
  if 0xFF48 == address:
    return gameboy.ppu.obp0
  if 0xFF49 == address:
    return gameboy.ppu.obp1
  if 0xFF4A == address:
    return gameboy.ppu.wy
  if 0xFF4B == address:
    return gameboy.ppu.wx
  if 0xFF51 == address:     # Gameboy Color Only
    return gameboy.ppu.hdma1
  if 0xFF52 == address:     # Gameboy Color Only
    return gameboy.ppu.hdma2
  if 0xFF53 == address:     # Gameboy Color Only
    return gameboy.ppu.hdma3
  if 0xFF54 == address:     # Gameboy Color Only
    return gameboy.ppu.hdma4
  if 0xFF55 == address:     # Gameboy Color Only
    return gameboy.ppu.hdma5
  if 0xFF68 == address:     # Gameboy Color Only
    return gameboy.ppu.bgpi
  if 0xFF69 == address:     # Gameboy Color Only
    return gameboy.ppu.bgpd
  if 0xFF6A == address:     # Gameboy Color Only
    return gameboy.ppu.ocps
  # TODO THESE REGISTERS
  if address < 0xFF80:
    return 0'u8
  # High RAM
  if address < 0xFFFF:
    #echo "HIGH RAM READ: $" & $toHex(address)
    return gameboy.highRam[address - 0xFF80]
  # Global Interrupts Table
  if 0xFFFF == address:
    return gameboy.intEnable

proc writeByte*(gameboy: Gameboy; address: uint16; value: uint8): void =

  # 0x0000 -> 0x3FFF (Cartridge ROM Bank 00)
  # 0x4000 -> 0x7FFF (Cartridge Rom Bank 01 / Switched)
  if address < 0x8000:
    gameboy.cartridge.writeByte(address, value)
  # 0x8000 -> 0x9FFF (VRAM - Bank 0 & 1 if Color Gameboy)  
  elif address < 0xA000:
    gameboy.ppu.writeByte(address, value)
  # 0xA000 -> 0xBFFF (Cartridge RAM Bank 0)
  elif address < 0xC000:
    gameboy.cartridge.writeByte(address, value)
  # 0xC000 -> 0xDFFF (Work RAM Bank 0)
  elif address < 0xE000:
    gameboy.internalRamBank0[address - 0xC000] = value
  # 0xE000 -> 0xFDFF (Echo Ram)
  elif address < 0xFE00:
    gameboy.internalRamBank0[address - 0xE000] = value
  # 0xFE00 -> 0xFE9F (PPU Object Attribute Map - OAM)
  elif address < 0xFEA0:
    gameboy.ppu.writeByte(address, value)
  # 0xFEA0 - 0xFEFF (Unused, always 0)
  elif address < 0xFF00:
    discard
  else:
    discard
  # Joypad
  if 0xFF00 == address:
    discard  # Joypad will have the proper value either way.
  # Serial IO
  if 0xFF01 == address:
    let c = char(value)
    if value == 10:
      gameboy.message &= " "
      stdout.write(gameboy.message)
      if "Passed" in gameboy.message :
        echo ""
        quit(QuitSuccess)
      if "Failed" in gameboy.message:
        echo ""
        quit(QuitFailure)
      gameboy.message = ""
    else:
      gameboy.message &= c
  if 0xFF02 == address:
    discard
  if 0xFF04 == address:
    gameboy.timer.resetDiv() # Reset the DIV on any writes.
  if 0xFF05 == address:
    gameboy.timer.timaCounter = value
  if 0xFF06 == address:
    gameboy.timer.timaModulo = value
  if 0xFF07 == address:
    gameboy.timer.tac = value
  if 0xFF0F == address:
    gameboy.intFlag = value
  # PPU Allocations
  if 0xFF40 == address:
    gameboy.ppu.lcdc = value
  if 0xFF41 == address:
    gameboy.ppu.stat = value
  if 0xFF42 == address:
    gameboy.ppu.requestedScy = value
  if 0xFF43 == address:
    gameboy.ppu.requestedScx = value
  if 0xFF45 == address:
    gameboy.ppu.requestedLyc = value
  if 0xFF46 == address:
    gameboy.ppu.dma = value
    gameboy.dmaTransfer()   # Dispatch the transfer
  if 0xFF47 == address:
    gameboy.ppu.bgp = value
  if 0xFF48 == address:
    gameboy.ppu.obp0 = value
  if 0xFF49 == address:
    gameboy.ppu.obp1 = value
  if 0xFF4A == address:
    gameboy.ppu.requestedWy = value
  if 0xFF4B == address:
    gameboy.ppu.requestedWx = value
  if 0xFF51 == address:     # Gameboy Color Only
    gameboy.ppu.hdma1 = value
  if 0xFF52 == address:     # Gameboy Color Only
    gameboy.ppu.hdma2 = value
  if 0xFF53 == address:     # Gameboy Color Only
    gameboy.ppu.hdma3 = value
  if 0xFF54 == address:     # Gameboy Color Only
    gameboy.ppu.hdma4 = value
  if 0xFF55 == address:     # Gameboy Color Only
    gameboy.ppu.hdma5 = value
  if 0xFF68 == address:     # Gameboy Color Only
    gameboy.ppu.bgpi = value
  if 0xFF69 == address:     # Gameboy Color Only
    gameboy.ppu.bgpd = value
  if 0xFF6A == address:     # Gameboy Color Only
    gameboy.ppu.ocps = value
  # TODO THESE REGISTERS
  if address < 0xFF80:
    discard
    return
  # High RAM
  if address < 0xFFFF:
    #echo "HIGH RAM WRITE: $" & $toHex(address) & " = " & $toHex(value)
    gameboy.highRam[address - 0xFF80] = value
    return
  if 0xFFFF == address:
    gameboy.intEnable = value

proc newCPUMemory*(gameboy: Gameboy): CPUMemory =
  CPUMemory(gameboy: gameboy)

proc newTimerGb*(gameboy: Gameboy): TimerGb =
  TimerGb(gameboy: gameboy)