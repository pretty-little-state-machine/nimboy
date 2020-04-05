import bitops
import types
# See here for an amazing resource https://gbdev.io/gb-opcodes/optables/

type
  StepInfo = object
    address, pc: uint16
    mode: AddressingMode

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


proc execute (cpu:var CPU; opcode: uint8) =
  case opcode
  of 0x00:
    cpu.tClock += 4
    cpu.mClock += 1
    cpu.pc += 1
  else:
    discard

proc step*(cpu: var CPU) = 
    cpu.execute(0x0'u8)

