import strutils
import bitops
import types
# See here for an amazing resource https://gbdev.io/gb-opcodes/optables/
import memory
import nimboyutils

type
  TickResult* = object
    tClock*: int
    mClock*: int
    debugStr*: string

proc setMsb(word: var uint16; byte: uint8): uint16 = 
  # Sets the MSB to the new byte
  let tmpWord:uint16 = byte
  word.clearMask(0xFF00)
  word.setMask(tmpWord shl 8)
  return word

proc setLsb(word: var uint16; byte: uint8): uint16 = 
  # Sets the LSB to the new byte
  word.clearMask(0x00FF)
  word.setMask(byte)
  return word

proc readWord(cpu: CPU; address: uint16): uint16 =
  var word: uint16
  word = setLsb(word, cpu.mem.gameboy.readByte(address)) #Get LSB
  word = setMsb(word, cpu.mem.gameboy.readByte(address + 1))  # Get MSB
  return word

proc writeWord(cpu: var CPU; address: uint16, word: uint16): void =
  var tempAddress = address
  cpu.mem.gameboy.writeByte(tempAddress, readLsb(word))
  tempAddress += 1
  cpu.mem.gameboy.writeByte(tempAddress, readMsb(word))

proc pushByte(cpu: var CPU; value: uint8): void =
  # Push byte onto the stack. This does NOT calculate any cycles for this.
  cpu.sp -= 1
  cpu.mem.gameboy.writeByte(cpu.sp, value)
  
proc popByte(cpu: var CPU): uint8 =
  # Pop byte from the stack. This does NOT calculate any cycles for this.
  var value = cpu.mem.gameboy.readByte(cpu.sp)
  cpu.sp += 1
  return value
  
proc pushWord(cpu: var CPU; value: uint16): void =
  # Push word onto the stack. This does NOT calculate any cycles for this.
  cpu.pushByte(readMsb(value))
  cpu.pushByte(readLsb(value))
  
proc popWord(cpu: var CPU): uint16 =
  # Pop word from the stack. This does NOT calculate any cycles for this.
  var value: uint16 = 0
  value = setLsb(value, cpu.popByte())
  value = setMsb(value, cpu.popByte())
  return value
  
proc call(cpu: var CPU, address: uint16): void =
  # Push onto the stack. This does NOT calculate any cycles for this.
  cpu.pushWord(cpu.pc)
  cpu.pc = address

proc ret(cpu: var CPU): void =
  # Push onto the stack. This does NOT calculate any cycles for this.
  cpu.pc = cpu.popWord()

proc setFlagZ(cpu: var CPU; bool: bool): void = 
  if bool:
    cpu.f.setMask(0b1000_0000'u8)
  else:
    cpu.f.clearMask(0b1000_0000'u8)

proc setFlagN(cpu: var CPU; bool: bool): void = 
  if bool:
    cpu.f.setMask(0b0100_0000'u8)
  else:
    cpu.f.clearMask(0b0100_0000'u8)

proc setFlagH(cpu: var CPU; bool: bool): void = 
  if bool:
    cpu.f.setMask(0b0010_0000'u8)
  else:
    cpu.f.clearMask(0b0010_0000'u8)

proc setFlagC(cpu: var CPU; bool: bool): void = 
  if bool:
    cpu.f.setMask(0b0001_0000'u8)
  else:
    cpu.f.clearMask(0b0001_0000'u8)

proc zFlag(cpu: var CPU): bool =
  return cpu.f.testBit(7)

proc nFlag(cpu: var CPU): bool =
  return cpu.f.testBit(6)

proc hFlag(cpu: var CPU): bool =
  return cpu.f.testBit(5)

proc cFlag(cpu: var CPU): bool =
  return cpu.f.testBit(4)

proc isAddCarry(a: uint8; b: uint8, usedCarry: uint8): bool = 
  let x = int(a) + int(b) + int(usedCarry) # Cast, otherwise it will overflow
  result = x.bitand(0x100) == 0x100

proc isSubCarry(a: uint8; b: uint8, usedCarry: uint8): bool = 
  let x = int(a) + int(b) + int(usedCarry) # Cast, otherwise it will be unsigned
  result = x.bitand(0x100) == 0x00

proc isAddHalfCarry(a: uint8; b: uint8, usedCarry: uint8): bool =
  # Deterimines if bit4 was carried during addition
  result = bitand(a.bitand(0xF) + b.bitand(0xF) + usedCarry.bitand(0xF), 0x10) == 0x10

proc isSubHalfCarry(a: uint8; b: uint8, usedCarry: uint8): bool =
  # Deterimines if bit4 was carried during subtraction
  result = bitand(a.bitand(0xF) + b.bitand(0xF) + usedCarry.bitand(0xF), 0x10) == 0x00

proc opOr(cpu: var CPU; value: uint8): void = 
  # Executes an OR operation on the A Register
  cpu.setFlagC(false)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  cpu.a = bitor(cpu.a, value)
  cpu.setFlagZ(0 == cpu.a)

proc opAnd(cpu: var CPU; value: uint8): void = 
  # Executes an AND operation on the A Register
  cpu.setFlagC(false)
  cpu.setFlagN(false)
  cpu.setFlagH(true)
  cpu.a = bitand(cpu.a, value)
  cpu.setFlagZ(0 == cpu.a)

proc opXor(cpu: var CPU; value: uint8): void = 
  # Executes a XOR operation on the A Register
  cpu.setFlagC(false)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  cpu.a = bitxor(cpu.a, value)
  cpu.setFlagZ(0 == cpu.a)

proc doAdd(cpu: var CPU, value1: uint8, value2: uint8, throughCarry: bool):uint8 =
  var usedCarry: uint8 = 0
  if cpu.cFlag and throughCarry:
    usedcarry = 1

  cpu.setFlagH(isAddHalfCarry(value1, value2, usedcarry))
  cpu.setFlagC(isAddCarry(value1, value2, usedcarry))
  result = value1 + value2 + usedcarry;

proc opAdd(cpu: var CPU; value: uint8): void = 
  # Executes add on the A Register
  cpu.a = cpu.doAdd(cpu.a, value, false)
  cpu.setFlagZ(0 == cpu.a)
  cpu.setFlagN(false)
  
proc opAdc(cpu: var CPU; value: uint8): void = 
  # Executes add on the A Register + Carry if set
  cpu.a = cpu.doAdd(cpu.a, value, true)
  cpu.setFlagZ(0 == cpu.a)
  cpu.setFlagN(false)

proc doSub(cpu: var CPU, value1: uint8, value2: uint8, throughCarry: bool):uint8 =
  var ones = not(value2)
  var usedCarry: uint8 = 1
  if cpu.cFlag and throughCarry:
    usedcarry = 0

  cpu.setFlagH(isSubHalfCarry(value1, ones, usedcarry))
  cpu.setFlagC(isSubCarry(value1, ones, usedcarry))
  result = value1 + ones + usedcarry;

proc opSub(cpu: var CPU; value: uint8): void = 
  # Executes substraction on the A Register
  cpu.a = cpu.doSub(cpu.a, value, false)
  cpu.setFlagZ(0 == cpu.a)
  cpu.setFlagN(true)

proc opSbc(cpu: var CPU; value: uint8): void = 
  # Executes substraction on the A Register - Carry Flag
  cpu.a = cpu.doSub(cpu.a, value, true)
  cpu.setFlagZ(0 == cpu.a)
  cpu.setFlagN(true)

proc opCp(cpu: var CPU; value: uint8): void = 
  # Compares A to value, this is essentially subtract with ignored results
  let tmpA = cpu.doSub(cpu.a, value, false)
  cpu.setFlagZ(0 == tmpA)
  cpu.setFlagN(true)

proc doRollRight(cpu: var CPU; value: uint8, throughCarry: bool): uint8 =
  var newValue: uint8 = value
  var newCarry: bool = bitand(newValue, 0x01) == 0x01
  var newSevenBit:uint8 = 0

  if throughCarry:
    if cpu.cFlag:
      newSevenBit = 0x80
    else: 
      newSevenBit = 0x00
  else:
    if newCarry:
      newSevenBit = 0x80
    else: 
      newSevenBit = 0x00

  newValue = newValue shr 1
  newValue = bitand(bitor(newValue, newSevenBit), 0xFF)
  cpu.setFlagC(newCarry)
  cpu.setFlagZ(0 == newValue)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  result = newValue

proc doRollLeft(cpu: var CPU; value: uint8, throughCarry: bool): uint8 =
  var newValue: uint8 = value
  var newCarry: bool = bitand(newValue, 0x80) == 0x80
  var newZeroBit:uint8 = 0

  if throughCarry:
    if cpu.cFlag:
      newZeroBit = 0x01
    else: 
      newZeroBit = 0x00
  else:
    if newCarry:
      newZeroBit = 0x01
    else: 
      newZeroBit = 0x00

  newValue = newValue shl 1
  newValue = bitand(bitor(newValue, newZeroBit), 0xFF)
  cpu.setFlagZ(0 == newValue)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  cpu.setFlagC(newCarry)
  result = newValue

proc doArithmeticShiftRigth(cpu: var CPU; value: uint8): uint8 =
  var newValue: uint8 = value
  var newCarry: bool = bitand(newValue, 0x01) == 0x01
  var newSevenBit:uint8 = bitand(newValue, 0x80)

  newValue = newValue shr 1
  newValue = bitand(bitor(newValue, newSevenBit), 0xFF)
  cpu.setFlagC(newCarry)
  cpu.setFlagZ(0 == newValue)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  result = newValue

proc doLogicalShiftRigth(cpu: var CPU; value: uint8): uint8 =
  var newValue: uint8 = value
  var newCarry: bool = bitand(newValue, 0x01) == 0x01
  var newSevenBit:uint8 = 0

  newValue = newValue shr 1
  newValue = bitand(bitor(newValue, newSevenBit), 0xFF)
  cpu.setFlagC(newCarry)
  cpu.setFlagZ(0 == newValue)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  result = newValue

proc doShiftLeft(cpu: var CPU; value: uint8): uint8 =
  var newValue: uint8 = value
  var newCarry: bool = bitand(newValue, 0x80) == 0x80
  var newZeroBit:uint8 = 0

  newValue = newValue shl 1
  newValue = bitand(bitor(newValue, newZeroBit), 0xFF)
  cpu.setFlagZ(0 == newValue)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  cpu.setFlagC(newCarry)
  result = newValue

proc doSwap(cpu: var CPU; value: uint8): uint8 =
  var lowNibble = bitand(value, 0x0F)
  var highNibble = bitand(value, 0xF0)
  var newValue = bitor((lowNibble shl 4), (highNibble shr 4))
  cpu.setFlagZ(0 == newValue)
  cpu.setFlagN(false)
  cpu.setFlagH(false)
  cpu.setFlagC(false)
  result = newValue

proc doBitTest(cpu: var CPU; value: uint8, bit: uint8): void =
  var mask: uint8 = uint8(1) shl bit
  var newValue = bitand(value, mask)
  cpu.setFlagZ(0 == newValue)
  cpu.setFlagN(false)
  cpu.setFlagH(true)

proc doBitSet(cpu:var CPU; value: uint8, bit: uint8): uint8 =
  var mask: uint8 = uint8(1) shl bit
  var newValue = bitor(value, mask)
  result = newValue

proc doBitReset(cpu:var CPU; value: uint8, bit: uint8): uint8 =
  var mask: uint8 = uint8(1) shl bit
  var newValue = bitand(value, not mask)
  result = newValue

template toSigned(x: uint8): int8 = cast[int8](x)

proc execute_cb (cpu: var CPU; opcode: uint8): TickResult =
  # Executes a single CPU Opcode
  case opcode
  of 0x00:
    cpu.bc = setMsb(cpu.bc, cpu.doRollLeft(readMsb(cpu.bc), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RLC B"
  of 0x01:
    cpu.bc = setLsb(cpu.bc, cpu.doRollLeft(readLsb(cpu.bc), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RLC C"
  of 0x02:
    cpu.de = setMsb(cpu.de, cpu.doRollLeft(readMsb(cpu.de), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RLC D"
  of 0x03:
    cpu.de = setLsb(cpu.de, cpu.doRollLeft(readLsb(cpu.de), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RLC E"
  of 0x04:
    cpu.hl = setMsb(cpu.hl, cpu.doRollLeft(readMsb(cpu.hl), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RLC H"
  of 0x05:
    cpu.hl = setLsb(cpu.hl, cpu.doRollLeft(readLsb(cpu.hl), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RLC L"
  of 0x06:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doRollLeft(value, true)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RLC (HL) (" & $toHex(cpu.hl) & ")"
  of 0x07:
    cpu.a = cpu.doRollLeft(cpu.a, true)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RLC A"
  of 0x08:
    cpu.bc = setMsb(cpu.bc, cpu.doRollRight(readMsb(cpu.bc), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RRC B"
  of 0x09:
    cpu.bc = setLsb(cpu.bc, cpu.doRollRight(readLsb(cpu.bc), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RRC C"
  of 0x0A:
    cpu.de = setMsb(cpu.de, cpu.doRollRight(readMsb(cpu.de), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RRC D"
  of 0x0B:
    cpu.de = setLsb(cpu.de, cpu.doRollRight(readLsb(cpu.de), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RRC E"
  of 0x0C:
    cpu.hl = setMsb(cpu.hl, cpu.doRollRight(readMsb(cpu.hl), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RRC H"
  of 0x0D:
    cpu.hl = setLsb(cpu.hl, cpu.doRollRight(readLsb(cpu.hl), true))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RRC L"
  of 0x0E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doRollRight(value, true)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RRC (HL) (" & $toHex(cpu.hl) & ")"
  of 0x0F:
    cpu.a = cpu.doRollRight(cpu.a, true)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RRC A"
  of 0x10:
    cpu.bc = setMsb(cpu.bc, cpu.doRollLeft(readMsb(cpu.bc), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RL B"
  of 0x11:
    cpu.bc = setLsb(cpu.bc, cpu.doRollLeft(readLsb(cpu.bc), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RL C"
  of 0x12:
    cpu.de = setMsb(cpu.de, cpu.doRollLeft(readMsb(cpu.de), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RL D"
  of 0x13:
    cpu.de = setLsb(cpu.de, cpu.doRollLeft(readLsb(cpu.de), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RL E"
  of 0x14:
    cpu.hl = setMsb(cpu.hl, cpu.doRollLeft(readMsb(cpu.hl), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RL H"
  of 0x15:
    cpu.hl = setLsb(cpu.hl, cpu.doRollLeft(readLsb(cpu.hl), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RL L"
  of 0x16:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doRollLeft(value, false)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RL (HL) (" & $toHex(cpu.hl) & ")"
  of 0x17:
    cpu.a = cpu.doRollLeft(cpu.a, false)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RL A"
  of 0x18:
    cpu.bc = setMsb(cpu.bc, cpu.doRollRight(readMsb(cpu.bc), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RR B"
  of 0x19:
    cpu.bc = setLsb(cpu.bc, cpu.doRollRight(readLsb(cpu.bc), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RR C"
  of 0x1A:
    cpu.de = setMsb(cpu.de, cpu.doRollRight(readMsb(cpu.de), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RR D"
  of 0x1B:
    cpu.de = setLsb(cpu.de, cpu.doRollRight(readLsb(cpu.de), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RR E"
  of 0x1C:
    cpu.hl = setMsb(cpu.hl, cpu.doRollRight(readMsb(cpu.hl), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RR H"
  of 0x1D:
    cpu.hl = setLsb(cpu.hl, cpu.doRollRight(readLsb(cpu.hl), false))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RR L"
  of 0x1E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doRollRight(value, false)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RR (HL) (" & $toHex(cpu.hl) & ")"
  of 0x1F:
    cpu.a = cpu.doRollRight(cpu.a, false)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RR A"
  of 0x20:
    cpu.bc = setMsb(cpu.bc, cpu.doShiftLeft(readMsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SLA B"
  of 0x21:
    cpu.bc = setLsb(cpu.bc, cpu.doShiftLeft(readLsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SLA C"
  of 0x22:
    cpu.de = setMsb(cpu.de, cpu.doShiftLeft(readMsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SLA D"
  of 0x23:
    cpu.de = setLsb(cpu.de, cpu.doShiftLeft(readLsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SLA E"
  of 0x24:
    cpu.hl = setMsb(cpu.hl, cpu.doShiftLeft(readMsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SLA H"
  of 0x25:
    cpu.hl = setLsb(cpu.hl, cpu.doShiftLeft(readLsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SLA L"
  of 0x26:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doShiftLeft(value)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SLA (HL) (" & $toHex(cpu.hl) & ")"
  of 0x27:
    cpu.a = cpu.doShiftLeft(cpu.a,)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SLA A"
  of 0x28:
    cpu.bc = setMsb(cpu.bc, cpu.doArithmeticShiftRigth(readMsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRA B"
  of 0x29:
    cpu.bc = setLsb(cpu.bc, cpu.doArithmeticShiftRigth(readLsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRA C"
  of 0x2A:
    cpu.de = setMsb(cpu.de, cpu.doArithmeticShiftRigth(readMsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRA D"
  of 0x2B:
    cpu.de = setLsb(cpu.de, cpu.doArithmeticShiftRigth(readLsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRA E"
  of 0x2C:
    cpu.hl = setMsb(cpu.hl, cpu.doArithmeticShiftRigth(readMsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRA H"
  of 0x2D:
    cpu.hl = setLsb(cpu.hl, cpu.doArithmeticShiftRigth(readLsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRA L"
  of 0x2E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doArithmeticShiftRigth(value)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SRA (HL) (" & $toHex(cpu.hl) & ")"
  of 0x2F:
    cpu.a = cpu.doArithmeticShiftRigth(cpu.a)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRA A"
  of 0x30:
    cpu.bc = setMsb(cpu.bc, cpu.doSwap(readMsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SWAP B"
  of 0x31:
    cpu.bc = setLsb(cpu.bc, cpu.doSwap(readLsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SWAP C"
  of 0x32:
    cpu.bc = setMsb(cpu.de, cpu.doSwap(readMsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SWAP D"
  of 0x33:
    cpu.bc = setLsb(cpu.de, cpu.doSwap(readLsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SWAP E"
  of 0x34:
    cpu.bc = setMsb(cpu.hl, cpu.doSwap(readMsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SWAP H"
  of 0x35:
    cpu.bc = setLsb(cpu.hl, cpu.doSwap(readLsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SWAP L"
  of 0x36:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doSwap(value)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SWAP H"
  of 0x37:
    cpu.a = cpu.doSwap(cpu.a)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SWAP L"
  of 0x38:
    cpu.bc = setMsb(cpu.bc, cpu.doLogicalShiftRigth(readMsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRL B"
  of 0x39:
    cpu.bc = setLsb(cpu.bc, cpu.doLogicalShiftRigth(readLsb(cpu.bc)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRL C"
  of 0x3A:
    cpu.de = setMsb(cpu.de, cpu.doLogicalShiftRigth(readMsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRL D"
  of 0x3B:
    cpu.de = setLsb(cpu.de, cpu.doLogicalShiftRigth(readLsb(cpu.de)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRL E"
  of 0x3C:
    cpu.hl = setMsb(cpu.hl, cpu.doLogicalShiftRigth(readMsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRL H"
  of 0x3D:
    cpu.hl = setLsb(cpu.hl, cpu.doLogicalShiftRigth(readLsb(cpu.hl)))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRL L"
  of 0x3E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doLogicalShiftRigth(value)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SRL (HL) (" & $toHex(cpu.hl) & ")"
  of 0x3F:
    cpu.a = cpu.doLogicalShiftRigth(cpu.a)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SRL A"
  of 0x40:
    cpu.doBitTest(readMsb(cpu.bc), 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 0, B"
  of 0x41:
    cpu.doBitTest(readLsb(cpu.bc), 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 0, C"
  of 0x42:
    cpu.doBitTest(readMsb(cpu.de), 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 0, D"
  of 0x43:
    cpu.doBitTest(readLsb(cpu.de), 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 0, E"
  of 0x44:
    cpu.doBitTest(readMsb(cpu.hl), 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 0, H"
  of 0x45:
    cpu.doBitTest(readLsb(cpu.hl), 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 0, L"
  of 0x46:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 0)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 0, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x47:
    cpu.doBitTest(cpu.a, 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 0, A"
  of 0x48:
    cpu.doBitTest(readMsb(cpu.bc), 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 1, B"
  of 0x49:
    cpu.doBitTest(readLsb(cpu.bc), 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 1, C"
  of 0x4A:
    cpu.doBitTest(readMsb(cpu.de), 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 1, D"
  of 0x4B:
    cpu.doBitTest(readLsb(cpu.de), 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 1, E"
  of 0x4C:
    cpu.doBitTest(readMsb(cpu.hl), 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 1, H"
  of 0x4D:
    cpu.doBitTest(readLsb(cpu.hl), 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 1, L"
  of 0x4E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 1)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 1, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x4F:
    cpu.doBitTest(cpu.a, 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 1, A"
  of 0x50:
    cpu.doBitTest(readMsb(cpu.bc), 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 2, B"
  of 0x51:
    cpu.doBitTest(readLsb(cpu.bc), 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 2, C"
  of 0x52:
    cpu.doBitTest(readMsb(cpu.de), 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 2, D"
  of 0x53:
    cpu.doBitTest(readLsb(cpu.de), 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 2, E"
  of 0x54:
    cpu.doBitTest(readMsb(cpu.hl), 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 2, H"
  of 0x55:
    cpu.doBitTest(readLsb(cpu.hl), 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 2, L"
  of 0x56:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 2)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 2, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x57:
    cpu.doBitTest(cpu.a, 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 2, A"
  of 0x58:
    cpu.doBitTest(readMsb(cpu.bc), 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 3, B"
  of 0x59:
    cpu.doBitTest(readLsb(cpu.bc), 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 3, C"
  of 0x5A:
    cpu.doBitTest(readMsb(cpu.de), 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 3, D"
  of 0x5B:
    cpu.doBitTest(readLsb(cpu.de), 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 3, E"
  of 0x5C:
    cpu.doBitTest(readMsb(cpu.hl), 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 3, H"
  of 0x5D:
    cpu.doBitTest(readLsb(cpu.hl), 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 3, L"
  of 0x5E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 3)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 3, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x5F:
    cpu.doBitTest(cpu.a, 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 3, A"
  of 0x60:
    cpu.doBitTest(readMsb(cpu.bc), 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 4, B"
  of 0x61:
    cpu.doBitTest(readLsb(cpu.bc), 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 4, C"
  of 0x62:
    cpu.doBitTest(readMsb(cpu.de), 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 4, D"
  of 0x63:
    cpu.doBitTest(readLsb(cpu.de), 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 4, E"
  of 0x64:
    cpu.doBitTest(readMsb(cpu.hl), 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 4, H"
  of 0x65:
    cpu.doBitTest(readLsb(cpu.hl), 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 4, L"
  of 0x66:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 4)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 4, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x67:
    cpu.doBitTest(cpu.a, 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 4, A"
  of 0x68:
    cpu.doBitTest(readMsb(cpu.bc), 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 5, B"
  of 0x69:
    cpu.doBitTest(readLsb(cpu.bc), 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 5, C"
  of 0x6A:
    cpu.doBitTest(readMsb(cpu.de), 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 5, D"
  of 0x6B:
    cpu.doBitTest(readLsb(cpu.de), 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 5, E"
  of 0x6C:
    cpu.doBitTest(readMsb(cpu.hl), 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 5, H"
  of 0x6D:
    cpu.doBitTest(readLsb(cpu.hl), 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 5, L"
  of 0x6E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 5)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 5, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x6F:
    cpu.doBitTest(cpu.a, 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 5, A"
  of 0x70:
    cpu.doBitTest(readMsb(cpu.bc), 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 6, B"
  of 0x71:
    cpu.doBitTest(readLsb(cpu.bc), 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 6, C"
  of 0x72:
    cpu.doBitTest(readMsb(cpu.de), 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 6, D"
  of 0x73:
    cpu.doBitTest(readLsb(cpu.de), 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 6, E"
  of 0x74:
    cpu.doBitTest(readMsb(cpu.hl), 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 6, H"
  of 0x75:
    cpu.doBitTest(readLsb(cpu.hl), 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 6, L"
  of 0x76:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 6)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 6, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x77:
    cpu.doBitTest(cpu.a, 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 6, A"
  of 0x78:
    cpu.doBitTest(readMsb(cpu.bc), 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 7, B"
  of 0x79:
    cpu.doBitTest(readLsb(cpu.bc), 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 7, C"
  of 0x7A:
    cpu.doBitTest(readMsb(cpu.de), 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 7, D"
  of 0x7B:
    cpu.doBitTest(readLsb(cpu.de), 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 7, E"
  of 0x7C:
    cpu.doBitTest(readMsb(cpu.hl), 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 7, H"
  of 0x7D:
    cpu.doBitTest(readLsb(cpu.hl), 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 7, L"
  of 0x7E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.doBitTest(value, 7)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "BIT 7, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x7F:
    cpu.doBitTest(cpu.a, 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "BIT 7, A"
  of 0x80:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 0, B"
  of 0x81:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 0, C"
  of 0x82:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 0, D"
  of 0x83:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 0, E"
  of 0x84:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 0, H"
  of 0x85:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 0, L"
  of 0x86:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 0)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 0, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x87:
    cpu.a = cpu.doBitReset(cpu.a, 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 0, A"
  of 0x88:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 1, B"
  of 0x89:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 1, C"
  of 0x8A:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 1, D"
  of 0x8B:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 1, E"
  of 0x8C:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 1, H"
  of 0x8D:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 1, L"
  of 0x8E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 1)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 1, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x8F:
    cpu.a = cpu.doBitReset(cpu.a, 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 1, A"
  of 0x90:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 2, B"
  of 0x91:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 2, C"
  of 0x92:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 2, D"
  of 0x93:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 2, E"
  of 0x94:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 2, H"
  of 0x95:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 2, L"
  of 0x96:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 2)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 2, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x97:
    cpu.a = cpu.doBitReset(cpu.a, 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 2, A"
  of 0x98:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 3, B"
  of 0x99:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 3, C"
  of 0x9A:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 3, D"
  of 0x9B:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 3, E"
  of 0x9C:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 3, H"
  of 0x9D:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 3, L"
  of 0x9E:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 3)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 3, (HL) (" & $toHex(cpu.hl) & ")"
  of 0x9F:
    cpu.a = cpu.doBitReset(cpu.a, 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 3, A"
  of 0xA0:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 4, B"
  of 0xA1:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 4, C"
  of 0xA2:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 4, D"
  of 0xA3:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 4, E"
  of 0xA4:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 4, H"
  of 0xA5:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 4, L"
  of 0xA6:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 4)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 4, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xA7:
    cpu.a = cpu.doBitReset(cpu.a, 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 4, A"
  of 0xA8:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 5, B"
  of 0xA9:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 5, C"
  of 0xAA:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 5, D"
  of 0xAB:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 5, E"
  of 0xAC:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 5, H"
  of 0xAD:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 5, L"
  of 0xAE:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 5)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 5, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xAF:
    cpu.a = cpu.doBitReset(cpu.a, 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 5, A"
  of 0xB0:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 6, B"
  of 0xB1:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 6, C"
  of 0xB2:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 6, D"
  of 0xB3:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 6, E"
  of 0xB4:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 6, H"
  of 0xB5:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 6, L"
  of 0xB6:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 6)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 6, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xB7:
    cpu.a = cpu.doBitReset(cpu.a, 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 6, A"
  of 0xB8:
    cpu.bc = setMsb(cpu.bc, cpu.doBitReset(readMsb(cpu.bc), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 7, B"
  of 0xB9:
    cpu.bc = setLsb(cpu.bc, cpu.doBitReset(readLsb(cpu.bc), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 7, C"
  of 0xBA:
    cpu.de = setMsb(cpu.de, cpu.doBitReset(readMsb(cpu.de), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 7, D"
  of 0xBB:
    cpu.de = setLsb(cpu.de, cpu.doBitReset(readLsb(cpu.de), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 7, E"
  of 0xBC:
    cpu.hl = setMsb(cpu.hl, cpu.doBitReset(readMsb(cpu.hl), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 7, H"
  of 0xBD:
    cpu.hl = setLsb(cpu.hl, cpu.doBitReset(readLsb(cpu.hl), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 7, L"
  of 0xBE:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitReset(value, 7)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RES 7, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xBF:
    cpu.a = cpu.doBitReset(cpu.a, 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "RES 7, A"
  of 0xC0:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 0, B"
  of 0xC1:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 0, C"
  of 0xC2:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 0, D"
  of 0xC3:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 0, E"
  of 0xC4:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 0, H"
  of 0xC5:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 0))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 0, L"
  of 0xC6:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 0)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 0, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xC7:
    cpu.a = cpu.doBitSet(cpu.a, 0)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 0, A"
  of 0xC8:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 1, B"
  of 0xC9:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 1, C"
  of 0xCA:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 1, D"
  of 0xCB:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 1, E"
  of 0xCC:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 1, H"
  of 0xCD:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 1))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 1, L"
  of 0xCE:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 1)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 1, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xCF:
    cpu.a = cpu.doBitSet(cpu.a, 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 1, A"
  of 0xD0:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 2, B"
  of 0xD1:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 2, C"
  of 0xD2:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 2, D"
  of 0xD3:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 2, E"
  of 0xD4:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 2, H"
  of 0xD5:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 2))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 2, L"
  of 0xD6:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 2)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 2, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xD7:
    cpu.a = cpu.doBitSet(cpu.a, 2)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 2, A"
  of 0xD8:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 3, B"
  of 0xD9:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 3, C"
  of 0xDA:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 3, D"
  of 0xDB:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 3, E"
  of 0xDC:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 3, H"
  of 0xDD:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 3))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 3, L"
  of 0xDE:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 3)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 3, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xDF:
    cpu.a = cpu.doBitSet(cpu.a, 3)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 3, A"
  of 0xE0:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 4, B"
  of 0xE1:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 4, C"
  of 0xE2:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 4, D"
  of 0xE3:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 4, E"
  of 0xE4:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 4, H"
  of 0xE5:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 4))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 4, L"
  of 0xE6:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 4)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 4, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xE7:
    cpu.a = cpu.doBitSet(cpu.a, 4)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 4, A"
  of 0xE8:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 5, B"
  of 0xE9:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 5, C"
  of 0xEA:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 5, D"
  of 0xEB:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 5, E"
  of 0xEC:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 5, H"
  of 0xED:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 5))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 5, L"
  of 0xEE:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 5)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 5, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xEF:
    cpu.a = cpu.doBitSet(cpu.a, 5)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 5, A"
  of 0xF0:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 6, B"
  of 0xF1:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 6, C"
  of 0xF2:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 6, D"
  of 0xF3:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 6, E"
  of 0xF4:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 6, H"
  of 0xF5:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 6))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 6, L"
  of 0xF6:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 6)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 6, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xF7:
    cpu.a = cpu.doBitSet(cpu.a, 6)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 6, A"
  of 0xF8:
    cpu.bc = setMsb(cpu.bc, cpu.doBitSet(readMsb(cpu.bc), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 7, B"
  of 0xF9:
    cpu.bc = setLsb(cpu.bc, cpu.doBitSet(readLsb(cpu.bc), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 7, C"
  of 0xFA:
    cpu.de = setMsb(cpu.de, cpu.doBitSet(readMsb(cpu.de), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 7, D"
  of 0xFB:
    cpu.de = setLsb(cpu.de, cpu.doBitSet(readLsb(cpu.de), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 7, E"
  of 0xFC:
    cpu.hl = setMsb(cpu.hl, cpu.doBitSet(readMsb(cpu.hl), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 7, H"
  of 0xFD:
    cpu.hl = setLsb(cpu.hl, cpu.doBitSet(readLsb(cpu.hl), 7))
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 7, L"
  of 0xFE:
    var value = cpu.mem.gameboy.readByte(cpu.hl)
    value =  cpu.doBitSet(value, 7)
    cpu.mem.gameboy.writeByte(cpu.hl, value)
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "SET 7, (HL) (" & $toHex(cpu.hl) & ")"
  of 0xFF:
    cpu.a = cpu.doBitSet(cpu.a, 7)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SET 7, A"

proc execute (cpu: var CPU; opcode: uint8): TickResult =
  # Executes a single CPU Opcode
  case opcode
  of 0x00:
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "NOP"
  of 0x01:
    let word = cpu.readWord(cpu.pc + 1) # Decode only
    cpu.bc = setLsb(cpu.bc, cpu.mem.gameboy.readByte(cpu.pc + 1))
    cpu.bc = setMsb(cpu.bc, cpu.mem.gameboy.readByte(cpu.pc + 2))
    cpu.pc += 3
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD BC (" & $toHex(word) & ")"
  of 0x02:
    cpu.mem.gameboy.writeByte(cpu.bc, cpu.a)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A, BC ( " & $toHex(cpu.bc) & ") " & $toHex(cpu.a)
  of 0x03:
    cpu.bc += 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "INC BC"
  of 0x04:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readMsb(cpu.bc)
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.bc = setMsb(cpu.bc, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "INC B"
  of 0x05:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readMsb(cpu.bc)
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.bc = setMsb(cpu.bc, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DEC B"
  of 0x06:
    let byte =  cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.bc = setMsb(cpu.bc, byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD B " & $toHex(byte)
  of 0x07:
    cpu.a = cpu.doRollLeft(cpu.a, true)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "RLC A"
  of 0x08:
    let address = cpu.readWord(cpu.pc + 1) 
    cpu.writeWord(address, cpu.sp)
    cpu.pc += 3
    result.tClock = 20
    result.mClock = 5
    result.debugStr = "LD  (" & $toHex(address) & ") SP"
  of 0x09:
    var byte: uint8 = cpu.doAdd(readLsb(cpu.hl), readLsb(cpu.bc), false)
    cpu.hl = setLsb(cpu.hl, byte)
    byte = cpu.doAdd(readMsb(cpu.hl), readMsb(cpu.bc), true)
    cpu.hl = setMsb(cpu.hl, byte)
    cpu.setFlagN(false)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADD HL BC"
  of 0x0A:
    cpu.a = cpu.mem.gameboy.readByte(cpu.bc)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A (BC) " & $toHex(cpu.bc)
  of 0x0B:
    cpu.bc -= 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "DEC BC"
  of 0x0C:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readLsb(cpu.bc)
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.bc = setLsb(cpu.bc, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "INC C"
  of 0x0D:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readLsb(cpu.bc)
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.bc = setLsb(cpu.bc, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DEC C"
  of 0x0E:
    let byte = cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.bc = setLsb(cpu.bc, byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD C " & $toHex(byte)
  of 0x0F:
    cpu.a = cpu.doRollRight(cpu.a, true)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "RRC A"
  of 0x10:
    cpu.mem.gameboy.stopped = true
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "STOP"
  of 0x11:
    let word = cpu.readWord(cpu.pc + 1) # Decode only
    cpu.de = setLsb(cpu.de, cpu.mem.gameboy.readByte(cpu.pc + 1))
    cpu.de = setMsb(cpu.de, cpu.mem.gameboy.readByte(cpu.pc + 2))
    cpu.pc += 3
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD DE, (" & $toHex(word) & ")"
  of 0x12:
    cpu.mem.gameboy.writeByte(cpu.de, cpu.a)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD DE (" & $toHex(cpu.de) & "), A " & $toHex(cpu.a)
  of 0x13:
    cpu.de += 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "INC DE"
  of 0x14:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readMsb(cpu.de)
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.de = setMsb(cpu.de, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "INC D"
  of 0x15:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readMsb(cpu.de)
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.de = setMsb(cpu.de, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DEC D"
  of 0x16:
    let byte =  cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.de = setMsb(cpu.de, byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD D " & $toHex(byte)
  of 0x17:
    cpu.a = cpu.doRollLeft(cpu.a, false)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "RL A"
  of 0x18:
    let signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2 # The program counter always increments first!
    cpu.pc += uint16(signed)
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "JR " & $toHex(cpu.pc)   
  of 0x19:
    var byte: uint8 = cpu.doAdd(readLsb(cpu.hl), readLsb(cpu.de), false)
    cpu.hl = setLsb(cpu.hl, byte)
    byte = cpu.doAdd(readMsb(cpu.hl), readMsb(cpu.de), true)
    cpu.hl = setMsb(cpu.hl, byte)
    cpu.setFlagN(false)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADD HL DE"
  of 0x1A:
    cpu.a = cpu.mem.gameboy.readByte(cpu.de)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A (DE) " & $toHex(cpu.de)
  of 0x1B:
    cpu.de -= 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "DEC DE"
  of 0x1C:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readLsb(cpu.de)
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.de = setLsb(cpu.de, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "INC E"
  of 0x1D:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readLsb(cpu.de)
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.de = setLsb(cpu.de, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DEC E"
  of 0x1E:
    let byte = cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.de = setLsb(cpu.de, byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD E " & $toHex(byte)
  of 0x1F:
    cpu.a = cpu.doRollRight(cpu.a, false)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "RR A"
  of 0x20:
    let signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2 # The program counter always increments first!
    if cpu.zFlag:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "JR NZ missed"
    else:
      cpu.pc += uint16(signed)
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "JR NZ " & $toHex(cpu.pc)
  of 0x21:
    let word = cpu.readWord(cpu.pc + 1) # Decode only
    cpu.hl = setLsb(cpu.hl, cpu.mem.gameboy.readByte(cpu.pc + 1))
    cpu.hl = setMsb(cpu.hl, cpu.mem.gameboy.readByte(cpu.pc + 2))
    cpu.pc += 3
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD HL (" & $toHex(word) & ")"
  of 0x22:
    cpu.mem.gameboy.writeByte(cpu.hl, cpu.a)
    cpu.hl += 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LDI HL" & $toHex(cpu.hl) & " " & $toHex(cpu.a)
  of 0x23:
    cpu.hl += 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "INC HL"
  of 0x24:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readMsb(cpu.hl)
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.hl = setMsb(cpu.hl, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "INC H"
  of 0x25:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readMsb(cpu.hl)
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.hl = setMsb(cpu.hl, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DEC H"
  of 0x26:
    let byte =  cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.hl = setMsb(cpu.hl, byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD H " & $toHex(byte)
  of 0x27:
    var oldValue = cpu.a
    var newValue:uint16 = cpu.a
    let oldCarry = cpu.cFlag
    var newCarry = false
    if bitand(oldValue, 0x0F) > 9 or cpu.hFlag:
      newValue += 6
      if bitand(newValue, 0x100) == 0x100:
        newCarry = true
      cpu.setFlagC(oldCarry or newCarry)
      cpu.setFlagH(true)
    else:
      cpu.setFlagH(false)

    if oldValue > 0x99 or oldCarry:
      newValue += 0x80
      cpu.setFlagC(true)
    else:
      cpu.setFlagC(false)
    cpu.a = uint8(newValue)
    cpu.setFlagZ(0 == cpu.a)
    cpu.setFlagH(false)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DAA"
  of 0x28:
    let signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2 # The program counter always increments first!
    if cpu.zFlag:
      cpu.pc += uint16(signed)
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "JR Z " & $toHex(cpu.pc)
    else:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "JR Z missed"
  of 0x29:
    var byte: uint8 = cpu.doAdd(readLsb(cpu.hl), readLsb(cpu.hl), false)
    cpu.hl = setLsb(cpu.hl, byte)
    byte = cpu.doAdd(readMsb(cpu.hl), readMsb(cpu.hl), true)
    cpu.hl = setMsb(cpu.hl, byte)
    cpu.setFlagN(true)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADD HL HL"
  of 0x2A:
    cpu.a = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.hl += 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A (HL+)"
  of 0x2B:
    cpu.hl -= 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "DEC HL"
  of 0x2C:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readLsb(cpu.hl)
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.hl = setLsb(cpu.hl, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "INC L"
  of 0x2D:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = readLsb(cpu.hl)
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.hl = setLsb(cpu.hl, tmp)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DEC L"
  of 0x2E:
    let byte = cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.hl = setLsb(cpu.hl, byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD L " & $toHex(byte)
  of 0x2F:
    cpu.a = not cpu.a
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "CPL"
  of 0x30:
    let signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2 # The program counter always increments first!
    if cpu.cFlag:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "JR NC missed"
    else:
      cpu.pc += uint16(signed)
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "JR NC " & $toHex(cpu.pc)
  of 0x31:
    cpu.sp = setLsb(cpu.sp, cpu.mem.gameboy.readByte(cpu.pc + 1))
    cpu.sp = setMsb(cpu.sp, cpu.mem.gameboy.readByte(cpu.pc + 2))
    cpu.pc += 3
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD SP (" & $toHex(cpu.sp) & ")"
  of 0x32:
    cpu.mem.gameboy.writeByte(cpu.hl, cpu.a)
    cpu.hl -= 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LDD (HL), A (" & $toHex(cpu.hl) & ") " & $toHex(cpu.a)
  of 0x33:
    cpu.sp += 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "INC SP"
  of 0x34:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = cpu.mem.gameboy.readByte(cpu.hl)
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.mem.gameboy.writeByte(cpu.hl, tmp)
    cpu.pc += 1
    result.tClock = 12
    result.mClock = 4
    result.debugStr = "INC (HL) " & $toHex(cpu.hl)
  of 0x35:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = cpu.mem.gameboy.readByte(cpu.hl)
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.mem.gameboy.writeByte(cpu.hl, tmp)
    cpu.pc += 1
    result.tClock = 12
    result.mClock = 4
    result.debugStr = "DEC (HL) " & $toHex(cpu.hl)
  of 0x36:
    let byte =  cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.mem.gameboy.writeByte(cpu.hl, byte)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 4
    result.debugStr = "LD (HL) " & $toHex(byte)
  of 0x37:
    cpu.setFlagC(true)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SCF"
  of 0x38:
    let signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2 # The program counter always increments first!
    if cpu.cFlag:
      cpu.pc += uint16(signed)
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "JR C " & $toHex(cpu.pc)
    else:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "JR C missed"
  of 0x39:
    var byte: uint8 = cpu.doAdd(readLsb(cpu.hl), readLsb(cpu.sp), false)
    cpu.hl = setLsb(cpu.hl, byte)
    byte = cpu.doAdd(readMsb(cpu.hl), readMsb(cpu.sp), true)
    cpu.hl = setMsb(cpu.hl, byte)
    cpu.setFlagN(true)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADD HL SP"
  of 0x3A:
    cpu.a = cpu.mem.gameboy.readByte(cpu.hl)
    cpu.hl -= 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A (HL-)"
  of 0x3B:
    cpu.sp -= 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "DEC SP"
  of 0x3C:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = cpu.a
    tmp = cpu.doAdd(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(false)
    cpu.setFlagZ(0 == tmp)
    cpu.a = tmp
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "INC A"
  of 0x3D:
    # Note that Carry is NOT set on this operation
    var oldcarry = cpu.cFlag()
    var tmp = cpu.a
    tmp = cpu.doSub(tmp,1,false)
    cpu.setFlagC(oldcarry)
    cpu.setFlagN(true)
    cpu.setFlagZ(0 == tmp)
    cpu.a = tmp
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DEC A"
  of 0x3E:
    cpu.a = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A " & $toHex(cpu.a)
  of 0x3F:
    cpu.setFlagC(false)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CCF"
  of 0x40:
    cpu.bc = setMsb(cpu.bc, readMsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD B, B"
  of 0x41:
    cpu.bc = setMsb(cpu.bc, readLsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD B, C"
  of 0x42:
    cpu.bc = setMsb(cpu.bc, readMsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD B, D"
  of 0x43:
    cpu.bc = setMsb(cpu.bc, readLsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD B, E"
  of 0x44:
    cpu.bc = setMsb(cpu.bc, readMsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD B, H"
  of 0x45:
    cpu.bc = setMsb(cpu.bc, readLsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD B, L"
  of 0x46:
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.bc = setMsb(cpu.bc, value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD B, (HL) " & $toHex(value)
  of 0x47:
    cpu.pc += 1
    cpu.bc = setMsb(cpu.bc, cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD B, A"
  of 0x48:
    cpu.bc = setLsb(cpu.bc, readMsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD C, B"
  of 0x49:
    cpu.bc = setLsb(cpu.bc, readLsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD C, C"
  of 0x4A:
    cpu.bc = setLsb(cpu.bc, readMsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD C, D"
  of 0x4B:
    cpu.bc = setLsb(cpu.bc, readLsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD C, E"
  of 0x4C:
    cpu.bc = setLsb(cpu.bc, readMsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD C, H"
  of 0x4D:
    cpu.bc = setLsb(cpu.bc, readLsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD C, L"
  of 0x4E:
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.bc = setLsb(cpu.bc, value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD C, (HL) " & $toHex(value)
  of 0x4F:
    cpu.pc += 1
    cpu.bc = setLsb(cpu.bc, cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD C, A"
  of 0x50:
    cpu.de = setMsb(cpu.de, readMsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD D, B"
  of 0x51:
    cpu.de = setMsb(cpu.de, readLsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD D, C"
  of 0x52:
    cpu.de = setMsb(cpu.de, readMsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD D, D"
  of 0x53:
    cpu.de = setMsb(cpu.de, readLsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD D, E"
  of 0x54:
    cpu.de = setMsb(cpu.de, readMsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD D, H"
  of 0x55:
    cpu.de = setMsb(cpu.de, readLsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD D, L"
  of 0x56:
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.de = setMsb(cpu.de, value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD D, (HL) " & $toHex(value)
  of 0x57:
    cpu.pc += 1
    cpu.de = setMsb(cpu.de, cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD D, A"
  of 0x58:
    cpu.de = setLsb(cpu.de, readMsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD E, B"
  of 0x59:
    cpu.de = setLsb(cpu.de, readLsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD E, C"
  of 0x5A:
    cpu.de = setLsb(cpu.de, readMsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD E, D"
  of 0x5B:
    cpu.de = setLsb(cpu.de, readLsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD E, E"
  of 0x5C:
    cpu.de = setLsb(cpu.de, readMsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD E, H"
  of 0x5D:
    cpu.de = setLsb(cpu.de, readLsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD E, L"
  of 0x5E:
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.de = setLsb(cpu.de, value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD E, (HL) " & $toHex(value)
  of 0x5F:
    cpu.pc += 1
    cpu.de = setLsb(cpu.de, cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD E, A"
  of 0x60:
    cpu.hl = setMsb(cpu.hl, readMsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD H, B"
  of 0x61:
    cpu.hl = setMsb(cpu.hl, readLsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD H, C"
  of 0x62:
    cpu.hl = setMsb(cpu.hl, readMsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD H, D"
  of 0x63:
    cpu.hl = setMsb(cpu.hl, readLsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD H, E"
  of 0x64:
    cpu.hl = setMsb(cpu.hl, readMsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD H, H"
  of 0x65:
    cpu.hl = setMsb(cpu.hl, readLsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD H, L"
  of 0x66:
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.hl = setMsb(cpu.hl, value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD H, (HL) " & $toHex(value)
  of 0x67:
    cpu.pc += 1
    cpu.hl = setMsb(cpu.hl, cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD H, A"
  of 0x68:
    cpu.hl = setLsb(cpu.hl, readMsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD L, B"
  of 0x69:
    cpu.hl = setLsb(cpu.hl, readLsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD L, C"
  of 0x6A:
    cpu.hl = setLsb(cpu.hl, readMsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD L, D"
  of 0x6B:
    cpu.hl = setLsb(cpu.hl, readLsb(cpu.de))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD L, E"
  of 0x6C:
    cpu.hl = setLsb(cpu.hl, readMsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD L, H"
  of 0x6D:
    cpu.hl = setLsb(cpu.hl, readLsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD L, L"
  of 0x6E:
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.hl = setLsb(cpu.hl, value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD L, (HL) " & $toHex(value)
  of 0x6F:
    cpu.pc += 1
    cpu.hl = setLsb(cpu.hl, cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD L, A"
  of 0x70:
    cpu.mem.gameboy.writeByte(cpu.hl, readMsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (HL), B"
  of 0x71:
    cpu.mem.gameboy.writeByte(cpu.hl, readLsb(cpu.bc))
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (HL), C"
  of 0x72:
    cpu.mem.gameboy.writeByte(cpu.hl, readMsb(cpu.de))
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (HL), D"
  of 0x73:
    cpu.mem.gameboy.writeByte(cpu.hl, readLsb(cpu.de))
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (HL), E"
  of 0x74:
    cpu.mem.gameboy.writeByte(cpu.hl, readMsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (HL), H"
  of 0x75:
    cpu.mem.gameboy.writeByte(cpu.hl, readLsb(cpu.hl))
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (HL), L"
  of 0x76:
    cpu.halted = true
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "HALT"
  of 0x77:
    cpu.mem.gameboy.writeByte(cpu.hl, cpu.a)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (HL), A"
  of 0x78:
    cpu.a = readMsb(cpu.bc)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD A, B"
  of 0x79:
    cpu.a = readLsb(cpu.bc)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD A, C"
  of 0x7A:
    cpu.a = readMsb(cpu.de)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD A, D"
  of 0x7B:
    cpu.a = readLsb(cpu.de)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD A, E"
  of 0x7C:
    cpu.a = readMsb(cpu.hl)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD A, H"
  of 0x7D:
    cpu.a = readLsb(cpu.hl)
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD A, L"
  of 0x7E:
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.a =  value
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A, (HL) " & $toHex(value)
  of 0x7F:
    cpu.pc += 1
    cpu.a =  cpu.a
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "LD A, A"
  of 0x80:
    cpu.pc += 1
    cpu.opAdd(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADD B"
  of 0x81:
    cpu.pc += 1
    cpu.opAdd(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADD C"
  of 0x82:
    cpu.pc += 1
    cpu.opAdd(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADD D"
  of 0x83:
    cpu.pc += 1
    cpu.opAdd(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADD E"
  of 0x84:
    cpu.pc += 1
    cpu.opAdd(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADD H"
  of 0x85:
    cpu.pc += 1
    cpu.opAdd(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADD L"
  of 0x86: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opAdd(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADD (HL)"  & $toHex(value)
  of 0x87:
    cpu.pc += 1
    cpu.opAdd(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADD A"
  of 0x88:
    cpu.pc += 1
    cpu.opAdc(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADC B"
  of 0x89:
    cpu.pc += 1
    cpu.opAdc(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADC C"
  of 0x8A:
    cpu.pc += 1
    cpu.opAdc(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADC D"
  of 0x8B:
    cpu.pc += 1
    cpu.opAdc(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADC E"
  of 0x8C:
    cpu.pc += 1
    cpu.opAdc(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADC H"
  of 0x8D:
    cpu.pc += 1
    cpu.opAdc(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADC L"
  of 0x8E: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opAdc(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADC (HL)"  & $toHex(value)
  of 0x8F:
    cpu.pc += 1
    cpu.opAdc(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "ADC A"
  of 0x90:
    cpu.pc += 1
    cpu.opSub(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SUB B"
  of 0x91:
    cpu.pc += 1
    cpu.opSub(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SUB C"
  of 0x92:
    cpu.pc += 1
    cpu.opSub(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SUB D"
  of 0x93:
    cpu.pc += 1
    cpu.opSub(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SUB E"
  of 0x94:
    cpu.pc += 1
    cpu.opSub(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SUB H"
  of 0x95:
    cpu.pc += 1
    cpu.opSub(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SUB L"
  of 0x96: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opSub(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SUB (HL)"  & $toHex(value)
  of 0x97:
    cpu.pc += 1
    cpu.opSub(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SUB A"
  of 0x98:
    cpu.pc += 1
    cpu.opSbc(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SBC B"
  of 0x99:
    cpu.pc += 1
    cpu.opSbc(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SBC C"
  of 0x9A:
    cpu.pc += 1
    cpu.opSbc(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SBC D"
  of 0x9B:
    cpu.pc += 1
    cpu.opSbc(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SBC E"
  of 0x9C:
    cpu.pc += 1
    cpu.opSbc(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SBC H"
  of 0x9D:
    cpu.pc += 1
    cpu.opSbc(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SBC L"
  of 0x9E: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opSbc(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SBC (HL)"  & $toHex(value)
  of 0x9F:
    cpu.pc += 1
    cpu.opSbc(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "SBC A"
  of 0xA0:
    cpu.pc += 1
    cpu.opAnd(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "AND B"
  of 0xA1:
    cpu.pc += 1
    cpu.opAnd(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "AND C"
  of 0xA2:
    cpu.pc += 1
    cpu.opAnd(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "AND D"
  of 0xA3:
    cpu.pc += 1
    cpu.opAnd(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "AND E"
  of 0xA4:
    cpu.pc += 1
    cpu.opAnd(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "AND H"
  of 0xA5:
    cpu.pc += 1
    cpu.opAnd(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "AND L"
  of 0xA6: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opAnd(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "AND (HL)"  & $toHex(value)
  of 0xA7:
    cpu.pc += 1
    cpu.opAnd(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "AND A"
  of 0xA8:
    cpu.pc += 1
    cpu.opXor(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR B"
  of 0xA9:
    cpu.pc += 1
    cpu.opXor(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR C"
  of 0xAA:
    cpu.pc += 1
    cpu.opXor(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR D"
  of 0xAB:
    cpu.pc += 1
    cpu.opXor(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR E"
  of 0xAC:
    cpu.pc += 1
    cpu.opXor(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR H"
  of 0xAD:
    cpu.pc += 1
    cpu.opXor(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR L"
  of 0xAE: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opXor(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "XOR (HL)"  & $toHex(value)
  of 0xAF:
    cpu.pc += 1
    cpu.opXor(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR A"
  of 0xB0:
    cpu.pc += 1
    cpu.opOr(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "OR B"
  of 0xB1:
    cpu.pc += 1
    cpu.opOr(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "OR C"
  of 0xB2:
    cpu.pc += 1
    cpu.opOr(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "OR D"
  of 0xB3:
    cpu.pc += 1
    cpu.opOr(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "OR E"
  of 0xB4:
    cpu.pc += 1
    cpu.opOr(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "OR H"
  of 0xB5:
    cpu.pc += 1
    cpu.opOr(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "OR L"
  of 0xB6: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opOr(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "OR (HL)"  & $toHex(value)
  of 0xB7:
    cpu.pc += 1
    cpu.opOr(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "OR A"
  of 0xB8:
    cpu.pc += 1
    cpu.opCp(readMsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP B"
  of 0xB9:
    cpu.pc += 1
    cpu.opCp(readLsb(cpu.bc))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP C"
  of 0xBA:
    cpu.pc += 1
    cpu.opCp(readMsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP D"
  of 0xBB:
    cpu.pc += 1
    cpu.opCp(readLsb(cpu.de))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP E"
  of 0xBC:
    cpu.pc += 1
    cpu.opCp(readMsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP H"
  of 0xBD:
    cpu.pc += 1
    cpu.opCp(readLsb(cpu.hl))
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP L"
  of 0xBE: 
    let value = cpu.mem.gameboy.readbyte(cpu.hl)
    cpu.opCp(value)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "CP (HL)"  & $toHex(value)
  of 0xBF:
    cpu.pc += 1
    cpu.opCp(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP A"
  of 0xC0:
    cpu.pc += 1
    if cpu.zFlag:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "RET NZ (missed)"
    else:
      cpu.ret()
      result.tClock = 20
      result.mClock = 5
      result.debugStr = "RET NZ"
  of 0XC1:
    cpu.bc = cpu.popWord()
    cpu.pc += 1
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "POP BC " & $toHex(cpu.sp) & " (" & $toHex(cpu.bc) & ")"
  of 0xC2:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3
    if cpu.zFlag:
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "JP NZ (missed)"
    else:
      cpu.pc = word
      result.tClock = 16
      result.mClock = 4
      result.debugStr = "JP NZ, (" & $toHex(word) & ")"
  of 0xC3:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc = word
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "JP " & $toHex(word)
  of 0xC4:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3 # We increment BEFORE we call. The RET should be the instruction AFTER this one.
    if cpu.zFlag:
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "CALL NZ, (missed)"
    else:
      cpu.call(word)
      result.tClock = 24
      result.mClock = 6
      result.debugStr = "CALL NZ, (" & $toHex(word) & ")"
  of 0xC5:
    cpu.pc += 1
    cpu.pushWord(cpu.bc)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH BC " & $toHex(cpu.sp) & " (" & $toHex(cpu.bc) & ")"
  of 0xC6:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opAdd(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADD A " & $toHex(byte)
  of 0xC7:
    cpu.pc += 1
    cpu.call(0x00)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 00"
  of 0xC8:
    cpu.pc += 1
    if cpu.zFlag:
      cpu.ret()
      result.tClock = 20
      result.mClock = 5
      result.debugStr = "RET Z"
    else:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "RET Z (missed)"
  of 0xC9:
    cpu.ret()
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RET"
  of 0xCA:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3
    if cpu.zFlag:
      cpu.pc = word
      result.tClock = 20
      result.mClock = 5
      result.debugStr = "JP Z, (" & $toHex(word) & ")"
    else:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "JP Z (missed)"
  of 0xCB:
    let cb_opcode = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    result = cpu.execute_cb(cb_opcode)
  of 0xCC:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3 # We increment BEFORE we call. The RET should be the instruction AFTER this one.
    if cpu.zFlag:
      cpu.call(word)
      result.tClock = 24
      result.mClock = 6
      result.debugStr = "CALL Z, (" & $toHex(word) & ")"
    else:
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "CALL Z, (missed)"
  of 0xCD:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3 # We increment BEFORE we call. The RET should be the instruction AFTER this one.
    cpu.call(word)
    result.tClock = 24
    result.mClock = 6
    result.debugStr = "CALL (" & $toHex(word) & ")"
  of 0xCE:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opAdc(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "ADC A " & $toHex(byte)
  of 0xCF:
    cpu.pc += 1
    cpu.call(0x08)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 08"
  of 0xD0:
    cpu.pc += 1
    if cpu.cFlag:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "RET NC (missed)"
    else:
      cpu.ret()
      result.tClock = 20
      result.mClock = 5
      result.debugStr = "RET NC"
  of 0XD1:
    cpu.de = cpu.popWord()
    cpu.pc += 1
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "POP DE " & $toHex(cpu.sp) & " (" & $toHex(cpu.de) & ")"
  of 0xD2:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3
    if cpu.cFlag:
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "JP NC (missed)"
    else:
      cpu.pc = word
      result.tClock = 16
      result.mClock = 4
      result.debugStr = "JP NC, (" & $toHex(word) & ")"
  # NO oxD3
  of 0xD4:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3 # We increment BEFORE we call. The RET should be the instruction AFTER this one.
    if cpu.cFlag:
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "CALL NC, (missed)"
    else:
      cpu.call(word)
      result.tClock = 24
      result.mClock = 6
      result.debugStr = "CALL NC, (" & $toHex(word) & ")"
  of 0xD5:
    cpu.pc += 1
    cpu.pushWord(cpu.de)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH DE " & $toHex(cpu.sp) & " (" & $toHex(cpu.de) & ")"
  of 0xD6:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opSub(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SUB A " & $toHex(byte)
  of 0xD7:
    cpu.pc += 1
    cpu.call(0x10)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 10"
  of 0xD8:
    cpu.pc += 1
    if cpu.cFlag:
      cpu.ret()
      result.tClock = 20
      result.mClock = 5
      result.debugStr = "RET C"
    else:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "RET C (missed)"
  of 0xD9:
    cpu.ret()
    cpu.eiPending = true # Will enable interrupts AFTER the next instructino
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RETI"
  of 0xDA:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3
    if cpu.cFlag:
      cpu.pc = word
      result.tClock = 20
      result.mClock = 5
      result.debugStr = "JP C, (" & $toHex(word) & ")"
    else:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "JP C (missed)"
  # NO 0xDB
  of 0xDC:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc += 3 # We increment BEFORE we call. The RET should be the instruction AFTER this one.
    if cpu.cFlag:
      cpu.call(word)
      result.tClock = 24
      result.mClock = 6
      result.debugStr = "CALL C, (" & $toHex(word) & ")"
    else:
      result.tClock = 12
      result.mClock = 3
      result.debugStr = "CALL C, (missed)"
  # NO 0xDD
  of 0xDE:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opSbc(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "SBC A " & $toHex(byte)
  of 0xDF:
    cpu.pc += 1
    cpu.call(0x18)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 18"
  of 0xE0:
    var word = 0xFF00'u16
    word = bitOr(word, uint16(cpu.mem.gameboy.readbyte(cpu.pc + 1)))
    cpu.mem.gameboy.writeByte(word, cpu.a)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LDH " & $toHex(word) & " A (" & $toHex(cpu.a) & ")"
  of 0XE1:
    cpu.hl = cpu.popWord()
    cpu.pc += 1
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "POP HL " & $toHex(cpu.sp) & " (" & $toHex(cpu.hl) & ")"
  of 0xE2:
    var address = 0xFF00'u16
    address = bitOr(address, uint16(readLsb(cpu.bc)))
    cpu.mem.gameboy.writeByte(address, cpu.a)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD (C) A"
  # NO 0xE3
  # NO 0xE4
  of 0xE5:
    cpu.pc += 1
    cpu.pushWord(cpu.hl)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH HL " & $toHex(cpu.sp) & " (" & $toHex(cpu.hl) & ")"
  of 0xE6:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opAnd(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "AND A " & $toHex(byte)
  of 0xE7:
    cpu.pc += 1
    cpu.call(0x20)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 20"
  of 0xE8:
    var byte: uint8 = 0
    var offset: uint8 = 0
    var signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    if signed < 0:
      offset = uint8(abs(signed))
      byte = cpu.doSub(readLsb(cpu.sp), offset, false)
      cpu.sp = setLsb(cpu.sp, byte)
      byte = cpu.doSub(readMsb(cpu.sp), 0, true)
      cpu.sp = setMsb(cpu.sp, byte)
    else:
      offset = uint8(abs(signed))
      byte = cpu.doAdd(readLsb(cpu.sp), offset, false)
      cpu.sp = setLsb(cpu.sp, byte)
      byte = cpu.doAdd(readMsb(cpu.sp), 0, true)
      cpu.sp = setMsb(cpu.sp, byte)
    cpu.setFlagZ(false)
    cpu.setFlagN(false)
    signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "ADD SP, r8 (" & $toHex(signed) & ")"
  of 0xE9:
    cpu.pc = cpu.hl
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "JP HL  (" & $toHex(cpu.hl) & ")"
  of 0xEA:
    var word: uint16
    word = cpu.readWord(cpu.pc+1)
    cpu.mem.gameboy.writeByte(word, cpu.a)
    cpu.pc += 3
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "LD (" & $tohex(word) & ") A"
  # NO 0XEB
  # NO 0XEC
  # NO 0XED
  of 0xEE:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opXor(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "XOR A " & $toHex(byte)
  of 0xEF:
    cpu.pc += 1
    cpu.call(0x28)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 28"
  of 0xF0:
    var word = 0xFF00'u16
    word = bitOr(word, uint16(cpu.mem.gameboy.readbyte(cpu.pc + 1)))
    let byte = cpu.mem.gameboy.readByte(word)
    cpu.a = byte
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD A " & $toHex(word) & " (" & $toHex(cpu.a) & ")"
  of 0XF1:
    cpu.f = cpu.popByte()
    cpu.a = cpu.popByte()
    cpu.pc += 1
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "POP AF " & $toHex(cpu.sp) & " (" & $toHex(cpu.a) & $toHex(cpu.f) & ")"
  of 0xF2:
    var address = 0xFF00'u16
    address = bitOr(address, uint16(readLsb(cpu.bc)))
    cpu.a = cpu.mem.gameboy.readByte(address)
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A (C)"
  of 0xF3:
    cpu.pc += 1
    cpu.ime = false # Interrupts are immediately disabled!
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DI"
  # NO 0xF4
  of 0xF5:
    cpu.pc += 1
    cpu.pushByte(cpu.a)
    cpu.pushByte(cpu.f)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH AF " & $toHex(cpu.sp) & " (" & $toHex(cpu.a) & $toHex(cpu.f) & ")"
  of 0xF6:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opOr(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "OR A " & $toHex(byte)
  of 0xF7:
    cpu.pc += 1
    cpu.call(0x30)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 30"
  of 0xF8:
    var byte: uint8 = 0
    var offset: uint8 = 0
    var signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    var newSp = cpu.sp
    if signed < 0:
      offset = uint8(abs(signed))
      byte = cpu.doSub(readLsb(newSp), offset, false)
      newSp = setLsb(newSp, byte)
      byte = cpu.doSub(readMsb(newSp), 0, true)
      newSp = setMsb(newSp, byte)
    else:
      offset = uint8(abs(signed))
      byte = cpu.doAdd(readLsb(newSp), offset, false)
      newSp = setLsb(newSp, byte)
      byte = cpu.doAdd(readMsb(newSp), 0, true)
      newSp = setMsb(newSp, byte)
    cpu.hl = newSp
    cpu.setFlagZ(false)
    cpu.setFlagN(false)
    signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD HL, SP + r8 (" & $toHex(signed) & ")"
  of 0xF9:
    cpu.sp = cpu.hl
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD SP, HL"
  of 0xFA:
    var word: uint16
    word = cpu.readWord(cpu.pc + 1)
    cpu.a = cpu.mem.gameboy.readByte(word)
    cpu.pc += 3
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "LD A (" & $tohex(word) & ")"
  of 0xFB:
    cpu.pc += 1
    cpu.eiPending = true # Interrupts are NOT immediately enabled!
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "EI"
  # NO 0XFC
  # NO 0Xfe
  of 0xFE:
    let byte = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opCp(byte)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "CP A " & $toHex(byte)
  of 0xFF:
    cpu.pc += 1
    cpu.call(0x38)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "RST 38"
  else:
    result.tClock = 0
    result.mClock = 0
    result.debugStr = "UNKNOWN OPCODE: " & $toHex(opcode)
    
proc callInterrupt(cpu: var CPU; address: uint16; flagBit: uint8;): TickResult =
  # Processes the given interrupt. Note that the halt flag is cleared if it is set.
  #
  # WARNING: 
  # The call is only executed if the global IME (Interrupt Enable) is set
  # The Halt flag is _always_ cleared, regardless of the IME. If the halt
  # flag has to be cleared there is a 4 cycle penalty for the operation.
  if cpu.halted: # Clear halted status in all cases
    result.tClock = 4
    result.mClock = 1
    cpu.halted = false
  if cpu.ime:
    # Clear the interrupt that fired only. Interrupts are DISABLED here.
    cpu.ime = false
    cpu.call(address)
    result.tClock += 20
    result.mClock += 5
    case flagBit:
      of 0x00:
        cpu.mem.gameboy.clearVSyncInterrupt()
        result.debugStr = "INTERRUPT: VSync"
      of 0x01:
        cpu.mem.gameboy.clearLCDStatInterrupt()
        result.debugStr =  "INTERRUPT: LCDStat"
      of 0x02:
        cpu.mem.gameboy.clearTimerInterrupt()
        result.debugStr =  "INTERRUPT: Timer"
      of 0x03:
        cpu.mem.gameboy.clearSerialInterrupt()
        result.debugStr =  "INTERRUPT: Serial"
      of 0x04:
        cpu.mem.gameboy.clearJoypadInterrupt()
        result.debugStr =  "INTERRUPT: Joypad"
      else: discard

proc handleInterrupts(cpu: var CPU): TickResult =
  # Process Interrupts and clears the HALT status.
  # 
  # This dispatches per interrupt. Note that interrupts CAN be chained once the 
  # previous interrupt has set IE (or typically the RETI opcode - Return and Enable Interrupts)
  if cpu.mem.gameboy.testVsyncInterrupt() and cpu.mem.gameboy.testVsyncIntEnabled():
    return cpu.callInterrupt(0x0040, 0)
  elif cpu.mem.gameboy.testLCDStatInterrupt() and cpu.mem.gameboy.testLCDStatIntEnabled():
    return cpu.callInterrupt(0x0048, 1)
  elif cpu.mem.gameboy.testTimerInterrupt() and cpu.mem.gameboy.testTimerIntEnabled():
    return cpu.callInterrupt(0x0050, 2)
  elif cpu.mem.gameboy.testSerialInterrupt() and cpu.mem.gameboy.testSerialIntEnabled():
    return cpu.callInterrupt(0x0058, 3)
  elif cpu.mem.gameboy.testJoypadInterrupt() and cpu.mem.gameboy.testJoypadIntEnabled():
    return cpu.callInterrupt(0x0060, 4)
  else:
    discard

proc step*(cpu: var CPU): TickResult =   
  # Executes a single step for the CPU.
  # Breakpiont Tirgger - Circuit breaker
  if cpu.breakpoint == cpu.pc:
    result.debugStr = "BREAK!"
    return
  
  # A response of 0 cycles indicates nothing happened, no interrupts to process - Circuit breaker
  let intResult = cpu.handleInterrupts()
  if 0 < intResult.tClock:
    return intResult

  # If there's pending interrupt enable, flip it off and queue up the toggle.
  var enableInterrupts = false
  if cpu.eiPending:
    cpu.eiPending = false
    enableInterrupts = true

  # Execute the next instruction and prepend the PC (before execution)
  let tmpPc = cpu.pc
  result = cpu.execute(cpu.mem.gameboy.readByte(cpu.pc))
  result.debugStr = $toHex(tmpPc) & " : " & result.debugStr
  
  # Process the enableInterrupts toggle if it was queued
  if enableInterrupts:
    cpu.ime = true

proc addBreakpoint*(cpu: var CPU; breakpoint: uint16) =
  # Addres a breakpoint to the CPU. This will NOT be cleared when hit.
  cpu.breakpoint = breakpoint
