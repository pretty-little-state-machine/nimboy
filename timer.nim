import types
import bitops

proc timaEnabled(timer: Timer): bool =
  return testBit(timer.timaCounter, 2)

proc timaRate(timer: Timer): uint16 = 
  # Returns the timer rate based on the first two bits of the TAC
  if testBit(timer.tac, 0):
    if testBit(timer.tac, 1):
      return 262144'u16 #0x01
    else:
      return 4094'u16   #0x00
  else:
    if testBit(timer.tac, 1):
      return 16386'u16  #0x11
    else:
      return 65536'u16  #0x10

proc tick*(gameboy: var Gameboy; osc: uint32) =
  # Increments the timer based on the system osscilator
  if 0 == osc mod 0x04:
    gameboy.timer.divReg.counter += 1
    if gameboy.timer.timaEnabled() and 0 == osc mod gameboy.timer.timaRate():
      gameboy.timer.timaCounter += 1
  
      





