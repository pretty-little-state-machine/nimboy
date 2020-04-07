import types
import bitops

proc timaEnabled(timer: Timer): bool =
  return testBit(timer.timaCounter, 2)

proc tick*(gameboy: var Gameboy; osc: uint32) =
  # Increments the timer based on the system osscilator
  if 0 == osc mod 0x04:
    gameboy.timer.divReg.counter += 1
    if gameboy.timer.timaEnabled():






