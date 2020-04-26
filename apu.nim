#
# Audio Processing Unit
#
# Some notes on the math in this module. Times are in milliseconds
#       ____________________      ____________________
# _____|        20         |_____|         20        |_____
#   5                         5                         5
#
# Pw = Pulse Width = 20 ms
# Sw = Space Width = 5 ms
# Tc = Cycle Time  = (Pw + Sw)/1000 = 0.025s
#  f = Frequency   = 1/Tc = 40 hz
# Dc = Duty Cycle  = Pw / Tc * 100 = 80%
# 
# A _square_ wave has a duty cycle of 50%
#
import bitops

proc registerToHz*(lowReg: uint8; highReg: uint8): uint32 =
  # Converts the gameboy 11-byte encoding to a frequency in hz.
  # Output range of 64hz to 131,072 hz (way out of human range, 18->20khz)
  #
  # Something to note here: The sound conversion is NOT a linear relationship!
  # There are 32 samples of 64 -> 65 hz but in the 800 hz section each increment
  # may result in several hz of jump between values. 
  #
  # See notes/APU_Frequency.ods
  #
  var word: uint16 = lowReg
  # Take the first three bits only of the high register
  if highReg.testBit(0): word.setBit(8)
  if highReg.testBit(1): word.setBit(9)
  if highReg.testBit(2): word.setBit(10)
  result = 4194304'u32 div uint32(32 * (2048 - word))

#proc genSound1*(): void =
  # The sound 1 register generates a square wave with sweep and 
  # and envelope functions available.



