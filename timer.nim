import bitops
import types
import memory

proc timaEnabled(timer: Timer): bool =
  return testBit(timer.timaCounter, 2)

proc timaRate(timer: Timer): uint = 
  # Returns the timer rate based on the first two bits of the TAC
  if testBit(timer.tac, 0):
    if testBit(timer.tac, 1):
      return 262144 #0x01
    else:
      return 4094   #0x00
  else:
    if testBit(timer.tac, 1):
      return 16386  #0x11
    else:
      return 65536  #0x10

proc tick*(timer: var Timer) =
  if timer.timaPending:
    timer.timaPending = false
    timer.timaCounter = timer.timaModulo
  # Increments the timer based on the system osscilator
  if 0 == timer.gb.gameboy.osc mod 0x04:
    timer.divReg.counter += 1
    if timer.timaEnabled() and 0 == timer.gb.gameboy.osc mod timer.timaRate():
      timer.timaCounter += 1
    if 0 == timer.timaCounter:
      timer.gb.gameboy.triggerTimerInterrupt()





