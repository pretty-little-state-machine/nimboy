#
# Interrupt handling
#
# NOTE: This uses DIRECT array access since NIM doesn't support
# Circular dependencies and we can't rely on memory due to a 
# dependency loop (ppu-> interrupts->memory->ppu->etc...).
#
import bitops
import types

proc clearAllInterrupts*(gameboy: Gameboy): void =
  gameboy.intFlag = 0x0000

proc testVSyncInterrupt*(gameboy: Gameboy): bool =
  return gameboy.intFlag.testBit(0)

proc testLCDStatInterrupt*(gameboy: Gameboy): bool =
  return gameboy.intFlag.testBit(1)

proc testTimerInterrupt*(gameboy: Gameboy): bool =
  return gameboy.intFlag.testBit(2)

proc testSerialInterrupt*(gameboy: Gameboy): bool =
  return gameboy.intFlag.testBit(3)

proc testJoypadInterrupt*(gameboy: Gameboy): bool =
  return gameboy.intFlag.testBit(4)

proc testVSyncIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.intEnable.testBit(0)

proc testLCDStatIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.intEnable.testBit(1)

proc testTimerIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.intEnable.testBit(2)

proc testSerialIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.intEnable.testBit(3)

proc testJoypadIntEnabled*(gameboy: Gameboy): bool =
  return gameboy.intEnable.testBit(4)

proc triggerVSyncInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.setBit(0)

proc triggerLCDStatInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.setBit(1)

proc triggerTimerInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.setBit(2)

proc triggerSerialInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.setBit(3)

proc triggerJoypadInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.setBit(4)

proc clearVSyncInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.clearBit(0)

proc clearLCDStatInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.clearBit(1)

proc clearTimerInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.clearBit(2)

proc clearSerialInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.clearBit(3)

proc clearJoypadInterrupt*(gameboy: var Gameboy): void =
  gameboy.intFlag.clearBit(4)