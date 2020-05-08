# TIMER module
#
# The timer DIV runs at 16384Hz which is 256 times slower than the
# gameboy. We will use a uint8 and overflow it to represnt one cycle
# of the overall system clock.
# 
# This will automatically allow for double-speeding on Gameboy color.
#
import bitops
import types
import interrupts
import nimboyutils

proc timaEnabled*(timer: Timer): bool =
  return testBit(timer.tac, 2)

proc timaRate*(timer: Timer): uint = 
  # Returns the timer rate based on the first two bits of the TAC
  if not testBit(timer.tac, 1) and not testBit(timer.tac, 0): return 1024 # 4096 hz - 0x00
  if not testBit(timer.tac, 1) and testBit(timer.tac, 0): return 16 # 262144 hz - 0x01
  if testBit(timer.tac, 1) and not testBit(timer.tac, 0): return 64 # 65536 hz - 0x10
  if testBit(timer.tac, 1) and testBit(timer.tac, 0): return 256  # 16384 hz - 0x11

proc resetDiv*(timer: var Timer): void =
  timer.divReg.counter = 0

proc readDiv*(timer: Timer): uint8 = 
  return readMsb(timer.divReg.counter)

proc tick*(timer: var Timer): void =
  timer.gb.gameboy.osc += 1
  #echo "OSC: " & $timer.gb.gameboy.osc & "  DIV: " & $timer.divReg.counter & "  TIMA: " & $timer.timaCounter & " RATE: " & $timer.timaRate()
  if timer.timaPending:
    timer.timaPending = false
    timer.timaCounter = timer.timaModulo
  # Increments the timer based on the system osscilator
  if 0 == timer.gb.gameboy.osc mod 256:
    timer.divReg.counter += 1
  if timer.timaEnabled() and 0 == timer.gb.gameboy.osc mod timer.timaRate():
    timer.timaCounter += 1
    if 0 == timer.timaCounter:
      timer.gb.gameboy.triggerTimerInterrupt()