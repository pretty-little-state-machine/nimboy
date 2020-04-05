type
  Gameboy* = ref GameboyObj
  GameboyObj* = object
    cpu*: CPU
    cartridge*: Cartridge
    internalRam: array[8*1024'u16, uint8] # Internal RAM ($C000-$DFFF, read-only echo at $E000 - $FE00)

  CPU* = object
    mem*: CPUMemory
    mClock*: uint64     # Machine Cycles
    tClock*: uint64     # Ticks
    pc*, sp*: uint16    # 16-bit Program Counter and Stack Pointer
    a*, b*, c*, d*, e*, h*, l*: uint8 # General purpose registers
    f*: uint8           # "Flags" Register [Z N H C 0 0 0 0]
    halted*: bool

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
