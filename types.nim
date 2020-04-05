import cartridge

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
        f*: uint8           # "Flags" Register
        halted*: bool

    CPUMemory* = ref object
        gameboy*: Gameboy



    Pixel* = object
        r: uint8
        g: uint8
        b: uint8

    VPU* = object
        buffer*: array[256*256, Pixel]

