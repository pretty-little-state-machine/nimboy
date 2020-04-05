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


proc execute (cpu: var CPU; opcode: uint8): string =
  var decode: string
  case opcode
  of 0x00:
    cpu.tClock += 4
    cpu.mClock += 1
    cpu.pc += 1
    decode = "NOP"
  else:
    decode = "UNKNOWN OPCODE: " & $toHex(opcode)
  return decode

proc step*(cpu: var CPU): string =   
    return cpu.execute(cpu.mem.gameboy.readByte(cpu.pc))


