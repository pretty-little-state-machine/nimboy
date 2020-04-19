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

proc readWord(cpu: CPU; address: uint16): uint16 =
  var word: uint16
  word = cpu.mem.gameboy.readByte(address + 1)
  word = word shl 8 
  word = bitor(word, cpu.mem.gameboy.readByte(address))
  return word

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

proc isAddCarry(a: uint8; b: uint8): bool = 
  let x = int(a) + int(b) # Cast, otherwise it will overflow
  result = x > 0xFF

proc isSubCarry(a: uint8; b: uint8): bool = 
  let x = int(a) + int(b) # Cast, otherwise it will be unsigned
  result = x < 0

proc isAddHalfCarry(a: uint8; b: uint8): bool =
  # Deterimines if bit4 was carried during addition
  result = bitand(a.bitand(0xF) + b.bitand(0xF), 0x10) == 0x10

proc isSubHalfCarry(a: uint8; b: uint8): bool =
  # Deterimines if bit4 was carried during subtraction
  result = bitand(a.bitand(0xF) - b.bitand(0xF), 0x10) < 0

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

proc opAdd(cpu: var CPU; value: uint8): void = 
  # Executes add on the A Register
  cpu.setFlagN(false)
  cpu.setFlagH(isAddHalfCarry(cpu.a, value))
  cpu.setFlagC(isAddCarry(cpu.a, value))
  cpu.a = cpu.a + value;
  cpu.setFlagZ(0 == cpu.a)

proc opAdc(cpu: var CPU; value: uint8): void = 
  var tmp = value
  # Executes add on the A Register + Carry if set
  if cpu.cFlag: tmp += 1
  cpu.setFlagN(false)
  cpu.setFlagH(isAddHalfCarry(cpu.a, tmp))
  cpu.setFlagC(isAddCarry(cpu.a, tmp))
  cpu.a = cpu.a + tmp;
  cpu.setFlagZ(0 == cpu.a)

proc opSub(cpu: var CPU; value: uint8): void = 
  # Executes substration on the A Register
  cpu.setFlagN(true)
  cpu.setFlagH(isSubHalfCarry(cpu.a, value))
  cpu.setFlagC(isSubCarry(cpu.a, value))
  cpu.a = cpu.a - value;
  cpu.setFlagZ(0 == cpu.a)

proc opSbc(cpu: var CPU; value: uint8): void = 
  var tmp = value
  # Executes substration on the A Register - Carry Flag
  if cpu.cFlag: tmp += 1 # Carry is an additional decrement later
  cpu.setFlagN(true)
  cpu.setFlagH(isSubHalfCarry(cpu.a, tmp))
  cpu.setFlagC(isSubCarry(cpu.a, tmp))
  cpu.a = cpu.a - tmp;
  cpu.setFlagZ(0 == cpu.a)

proc opCp(cpu: var CPU; value: uint8): void = 
  # Compares A to value, this is essentially subtract with ignored results
  let tmpA = cpu.a
  cpu.setFlagN(true)
  cpu.setFlagH(isSubHalfCarry(tmpA, value))
  cpu.setFlagC(isSubCarry(tmpA, value))
  cpu.setFlagZ(0 == tmpA - value)

template toSigned(x: uint8): int8 = cast[int8](x)

proc execute (cpu: var CPU; opcode: uint8): TickResult =
  # Executes a single CPU Opcode
  case opcode
  of 0x00:
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "NOP"
  of 0x05:
    # TODO: Investigate the half-carry here.
    cpu.pc += 1
    cpu.setFlagN(true)
    # Rollover
    if 0 == cpu.bc.readMsb():
      cpu.bc = setMsb(cpu.bc, 0xFF)
      cpu.setFlagH(true)
    else:
      cpu.bc = setMsb(cpu.bc, cpu.bc.readMsb() - 1)
    cpu.setFlagZ( 0 == readMsb(cpu.bc))
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
  of 0x0D:
    # TODO: Investigate the half-carry here
    cpu.pc += 1
    cpu.setFlagN(true)
    # Rollover
    if 0 == cpu.bc.readLsb():
      cpu.bc = setLsb(cpu.bc, 0xFF)
      cpu.setFlagH(true)
    else:
      cpu.bc = setLsb(cpu.bc, cpu.bc.readLsb() - 1)
    if 0 == readLsb(cpu.bc):
       cpu.setFlagZ(true)
    else:
        cpu.setFlagZ(false)
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
  of 0x20:
    let signed = toSigned(cpu.mem.gameboy.readbyte(cpu.pc + 1))
    cpu.pc += 2 # The program counter always increments first!
    if cpu.zFlag:
      result.tClock = 8
      result.mClock = 2
      result.debugStr = "JR NZ " & $toHex(cpu.pc)
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
    result.debugStr = "LD HL " & $toHex(word)
  of 0x32:
    cpu.mem.gameboy.writeByte(cpu.hl, cpu.a)
    cpu.hl -= 1
    cpu.pc += 1
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LDD " & $toHex(cpu.hl) & " " & $toHex(cpu.a)
  of 0x3E:
    cpu.a = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "LD A " & $toHex(cpu.a)
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opAdd(value)
    cpu.pc += 2
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
    cpu.opAdc(readMsb(cpu.hl))
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opAdc(value)
    cpu.pc += 2
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opSub(value)
    cpu.pc += 2
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
    cpu.opSbc(readMsb(cpu.hl))
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opSbc(value)
    cpu.pc += 2
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opAnd(value)
    cpu.pc += 2
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
    cpu.opXor(readMsb(cpu.hl))
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opXor(value)
    cpu.pc += 2
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opOr(value)
    cpu.pc += 2
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
    cpu.opCp(readMsb(cpu.hl))
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
    let value = cpu.mem.gameboy.readbyte(cpu.pc + 1)
    cpu.opCp(value)
    cpu.pc += 2
    result.tClock = 8
    result.mClock = 2
    result.debugStr = "CP (HL)"  & $toHex(value)
  of 0xBF:
    cpu.pc += 1
    cpu.opCp(cpu.a)
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "CP A"
  of 0xC3:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc = word
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "JP " & $toHex(word)
  of 0xC5:
    cpu.pc += 1
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, readMsb(cpu.bc))
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, readLsb(cpu.bc))
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH BC " & $toHex(cpu.sp) & " (" & $toHex(cpu.bc) & ")"
  of 0xD5:
    cpu.pc += 1
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, readMsb(cpu.de))
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, readLsb(cpu.de))
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH DE " & $toHex(cpu.sp) & " (" & $toHex(cpu.de) & ")"
  of 0xE0:
    var word = 0xFF00'u16
    word = bitOr(word, uint16(cpu.mem.gameboy.readbyte(cpu.pc + 1)))
    cpu.mem.gameboy.writeByte(word, cpu.a)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD " & $toHex(word) & " A (" & $toHex(cpu.a) & ")"
  of 0xE5:
    cpu.pc += 1
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, readMsb(cpu.hl))
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, readLsb(cpu.hl))
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH HL " & $toHex(cpu.sp) & " (" & $toHex(cpu.hl) & ")"
  of 0xF0:
    var word = 0xFF00'u16
    word = bitOr(word, uint16(cpu.mem.gameboy.readbyte(cpu.pc + 1)))
    let byte = cpu.mem.gameboy.readByte(word)
    cpu.a = byte
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD A " & $toHex(word) & " (" & $toHex(cpu.a) & ")"
  of 0xF3:
    cpu.pc += 1
    cpu.ime = false # Interrupts are immediately disabled!
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "DI"
  of 0xF5:
    cpu.pc += 1
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, cpu.a)
    cpu.sp -= 1
    cpu.mem.gameboy.writeByte(cpu.sp, cpu.f)
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "PUSH AF " & $toHex(cpu.sp) & " (" & $toHex(cpu.a) & $toHex(cpu.f) & ")"
  of 0xFE:
    cpu.pc += 1
    cpu.eiPending = true # Interrupts are NOT immediately enabled!
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "EI"
  else:
    result.tClock = 0
    result.mClock = 0
    result.debugStr = "UNKNOWN OPCODE: " & $toHex(opcode)

proc push(cpu: var CPU; address: uint16; value: uint8): void =
  # Push onto the stack. This does NOT calculate any cycles for this.
  cpu.mem.gameboy.writeByte(address, readLsb(cpu.pc))
  cpu.sp -= 1
  cpu.mem.gameboy.writeByte(address, readMsb(cpu.pc))

proc call(cpu: var CPU; address: uint16): void =
  # Push onto the stack. This does NOT calculate any cycles for this.
  cpu.mem.gameboy.writeByte(address, readLsb(cpu.pc))
  cpu.sp -= 1
  cpu.mem.gameboy.writeByte(address, readMsb(cpu.pc))

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
    cpu.call(cpu.sp)
    cpu.pc = address
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
