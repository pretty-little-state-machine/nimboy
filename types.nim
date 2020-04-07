type
  Gameboy* = ref GameboyObj
  GameboyObj* = object
    cpu*: CPU
    cartridge*: Cartridge
    timer*: Timer
    internalRam: array[8*1024'u16, uint8] # Internal RAM ($C000-$DFFF, read-only echo at $E000 - $FE00)
    osc*: uint32  # Internal Oscillator

  # Timer subsystem
  Timer = object
    divReg*: DivReg     # Divider Register - At memory location 0xFF04 - Only MSB accessible
    timaCounter*: uint8  # Timer Counter - At memory locaton 0xFF05
    timaModulo*: uint8   # Timer Modulo - When TimaCounter overflows this value is loaded into Tima Counter
    tac*: uint8

  DivReg = object
    counter*: uint16    # Only the MSB is accessible

  # CPU Subsystem
  CPU* = object
    mem*: CPUMemory       # Ref back to gameboy - Avoids ciruclar references in NIM
    mClock*: uint8        # Machine Cycles
    tClock*: uint8        # Ticks
    pc*, sp*: uint16      # 16-bit Program Counter and Stack Pointer
    a*: uint8             # 8-Bit accumulator
    bc*, de*, hl*: uint16 # General purpose registers - Also operate as 8-bit combos
    f*: uint8             # "Flags" Register [Z N H C 0 0 0 0]
    halted*: bool         # Halted state for CPU power savings
    breakpoint*: uint16   # Single breakpoint for now
    diPending*: bool      # Set when the DI opcode is issued 
    eiPending*: bool      # Set when the EI Opcode is issued
    interuptStatus*: bool # Interupt Status

  CPUMemory* = ref object
      gameboy*: Gameboy

  Cartridge* = object
    loaded*: bool
    fixedROM*: array[16*1024'u16, uint8]        # 16KB of Fixed ROM Bank 0 ($0000-$3FFF)
    internalROM*: array[128*16*1024'u32, uint8] # 2MB Max rom size - MBC3 (128 Banks of 16K)
    internalRAM*: array[4*8*1024'u16, uint8]    # 32KB Max RAM size - MBC3 (4 banks of 8K)
    romPage*: uint16
    ramPage*: uint16
    writeEnabeld*: bool

  Pixel* = object
    r: uint8
    g: uint8
    b: uint8

  VPU* = object
    buffer*: array[256*256, Pixel]
