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

proc clearFlagZ(cpu: var CPU) = 
  cpu.f.clearMask(0b1000_0000'u8)

proc clearFlagN(cpu: var CPU) = 
  cpu.f.clearMask(0b0100_0000'u8)

proc clearFlagH(cpu: var CPU) = 
  cpu.f.clearMask(0b0010_0000'u8)

proc clearFlagC(cpu: var CPU) = 
  cpu.f.clearMask(0b0001_0000'u8)

proc setFlagZ(cpu: var CPU) = 
  cpu.f.setMask(0b1000_0000'u8)

proc setFlagN(cpu: var CPU) = 
  cpu.f.setMask(0b0100_0000'u8)

proc setFlagH(cpu: var CPU) = 
  cpu.f.setMask(0b0010_0000'u8)

proc setFlagC(cpu: var CPU) = 
  cpu.f.setMask(0b0001_0000'u8)

proc zFlag(cpu: var CPU): bool =
  return cpu.f.testBit(7)

proc nFlag(cpu: var CPU): bool =
  return cpu.f.testBit(6)

proc hFlag(cpu: var CPU): bool =
  return cpu.f.testBit(5)

proc cFlag(cpu: var CPU): bool =
  return cpu.f.testBit(4)

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
    cpu.pc += 1
    cpu.setFlagN()
    # Rollover
    if 0 == cpu.bc.readMsb():
      cpu.bc = setMsb(cpu.bc, 0xFF)
      cpu.setFlagH()
    else:
      cpu.bc = setMsb(cpu.bc, cpu.bc.readMsb() - 1)
    if 0 == readMsb(cpu.bc):
       cpu.setFlagZ()
    else:
        cpu.clearFlagZ()
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
    cpu.pc += 1
    cpu.setFlagN()
    # Rollover
    if 0 == cpu.bc.readLsb():
      cpu.bc = setLsb(cpu.bc, 0xFF)
      cpu.setFlagH()
    else:
      cpu.bc = setLsb(cpu.bc, cpu.bc.readLsb() - 1)
    if 0 == readLsb(cpu.bc):
       cpu.setFlagZ()
    else:
        cpu.clearFlagZ()
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
  of 0xAF:
    cpu.clearFlagC()
    cpu.clearFlagN()
    cpu.clearFlagH()
    cpu.a = bitxor(cpu.a, cpu.a)
    if 0 == cpu.a: 
      cpu.setFlagZ()
    else:
      cpu.clearFlagZ()
    cpu.pc += 1
    result.tClock = 4
    result.mClock = 1
    result.debugStr = "XOR A A"
  of 0xC3:
    let word = cpu.readWord(cpu.pc + 1)
    cpu.pc = word
    result.tClock = 16
    result.mClock = 4
    result.debugStr = "JP " & $toHex(word)
  of 0xE0:
    var word = 0xFF00'u16
    word = bitOr(word, uint16(cpu.mem.gameboy.readbyte(cpu.pc + 1)))
    cpu.mem.gameboy.writeByte(word, cpu.a)
    cpu.pc += 2
    result.tClock = 12
    result.mClock = 3
    result.debugStr = "LD " & $toHex(word) & " A (" & $toHex(cpu.a) & ")"
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
