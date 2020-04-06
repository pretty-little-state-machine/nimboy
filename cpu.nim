import strutils
import bitops
import types
# See here for an amazing resource https://gbdev.io/gb-opcodes/optables/
import memory

type
  AddressingMode = enum
    imp, # Implied
    imm, # Immediate
    exi, # Extended Immediate
    rga, # Register Addressing
    ria, # Register Indirect Addressing
    ext, # Extended
    mpz, # Modified page Zero 
    rel, # Relative
    idx, # Indexed
    bta  # Bit Addressing

proc readWord(cpu: CPU; address: uint16): uint16 =
  var word: uint16
  word = cpu.mem.gameboy.readByte(address + 1)
  word = word shl 8 
  word = bitor(word, cpu.mem.gameboy.readByte(address))
  return word

proc readHL(cpu: CPU): uint16 =
  var word: uint16
  word = cpu.h
  word = word shl 8 
  word = bitor(word, cpu.l)
  return word

proc decHL(cpu: var CPU): uint16 =
  var word: uint16
  word = cpu.h
  word = word shl 8 
  word = bitor(word, cpu.l)
  word -= 1
  cpu.h = word shl 8
  cpu.l = word shr 8
  return word

proc execute (cpu: var CPU; opcode: uint8): string =
  var decode: string
  case opcode
  of 0x00:
    cpu.tClock += 4
    cpu.mClock += 1
    cpu.pc += 1
    decode = "NOP"
  of 0x06:
    let byte =  cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.b = byte
    cpu.tClock += 8
    cpu.mClock += 2
    cpu.pc += 2
    decode = "LD B " & $toHex(byte)
  of 0x0E:
    let byte =  cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.c = byte
    cpu.tClock += 8
    cpu.mClock += 2
    cpu.pc += 2
    decode = "LD C " & $toHex(byte)
  of 0x21:
    let word = cpu.readWord(cpu.pc + 1) # Decode only
    cpu.l = cpu.mem.gameboy.readByte(cpu.pc + 1)
    cpu.h = cpu.mem.gameboy.readByte(cpu.pc + 2)
    cpu.tClock += 12
    cpu.mClock += 3
    cpu.pc += 3
    decode = "LD HL " & $toHex(word)
  of 0x32:
    discard cpu.mem.gameboy.writeByte(cpu.readHL, cpu.a)
    cpu.tClock += 8
    cpu.mClock += 2
    cpu.pc += 1
    decode = "LDD " & $toHex(cpu.readHL) & " " & $toHex(cpu.a)
  of 0xAF:
    cpu.f.clearMask(0b0111_0000'u8) # Clear N H C
    cpu.a = bitxor(cpu.a, cpu.a)
    if 0 == cpu.a: 
      cpu.f.setMask(0b1000_0000'u8)
    else:
      cpu.f.clearMask(0b1000_0000'u8)
    cpu.tClock += 4
    cpu.mClock += 1
    cpu.pc += 1
    decode = "XOR A A"
  of 0xC3:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.tClock += 16
    cpu.mClock += 4
    cpu.pc = word
    decode = "JP " & $toHex(word)
  else:
    decode = "UNKNOWN OPCODE: " & $toHex(opcode)
  return decode

proc step*(cpu: var CPU): string =   
    return $toHex(cpu.pc) & " : " & cpu.execute(cpu.mem.gameboy.readByte(cpu.pc))


