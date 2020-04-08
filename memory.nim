import types
import bitops
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
  if 0xFF0F == address:
    return gameboy.intFlag
  if 0xFFFF == address:
    return gameboy.intEnable
  return 0 # Undefined Address

proc writeByte*(gameboy: Gameboy; address: uint16; value: uint8): void =
  if address < 0x8000:
    gameboy.cartridge.writeByte(address, value)
  if address < 0xA000:
      discard
  if address < 0xC000:
    gameboy.cartridge.writeByte(address, value)
  if 0xFF0F == address:
    gameboy.intFlag = value
  if 0xFFFF == address:
    gameboy.intEnable = value

proc newCPUMemory*(gameboy: Gameboy): CPUMemory =
  CPUMemory(gameboy: gameboy)

proc newTimerGb*(gameboy: Gameboy): TimerGb =
  TimerGb(gameboy: gameboy)

proc clearAllInterrupts*(gameboy: Gameboy): void =
  gameboy.intFlag = 0x0000

proc testVSyncInterrupt*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFF0F).testBit(0)

proc testLCDStatInterrupt*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFF0F).testBit(1)

proc testTimerInterrupt*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFF0F).testBit(2)

proc testSerialInterrupt*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFF0F).testBit(3)

proc testJoypadInterrupt*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFF0F).testBit(4)

proc testVSyncIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFFFF).testBit(0)

proc testLCDStatIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFFFF).testBit(1)

proc testTimerIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFFFF).testBit(2)

proc testSerialIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFFFF).testBit(3)

proc testJoypadIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.readByte(0xFFFF).testBit(4)

proc triggerVSyncInterrupt*(gameboy: var Gameboy): void =
  var ie = gameboy.readByte(0xFF0F)
  ie.setBit(0)
  gameboy.writeByte(0xFF0F, ie)

proc triggerLCDStatInterrupt*(gameboy: var Gameboy): void =
  var ie = gameboy.readByte(0xFF0F)
  ie.setBit(1)
  gameboy.writeByte(0xFF0F, ie)

proc triggerTimerInterrupt*(gameboy: var Gameboy): void =
  var ie = gameboy.readByte(0xFF0F)
  ie.setBit(2)
  gameboy.writeByte(0xFF0F, ie)

proc triggerSerialInterrupt*(gameboy: var Gameboy): void =
  var ie = gameboy.readByte(0xFF0F)
  ie.setBit(3)
  gameboy.writeByte(0xFF0F, ie)

proc triggerJoypadInterrupt*(gameboy: var Gameboy): void =
  var ie = gameboy.readByte(0xFF0F)
  ie.setBit(4)
  gameboy.writeByte(0xFF0F, ie)
