import deques
import sdl2/audio

type
  Gameboy* = ref GameboyObj
  GameboyObj* = object
    cpu*: CPU
    gameboyMode*: GameboyMode
    cartridge*: Cartridge
    ppu*: PPU
    timer*: Timer
    internalRamBank0*: array[8*4096'u16, uint8] # Internal RAM ($C000-$CFFF)
    internalRamBank1*: array[8*4096'u16, uint8] # Internal RAM ($D000-$DFFF)
    highRam*: array[8*128'u16, uint8] # High RAM ($FF80-FFFE)
    joypad*: uint8      # $FF00 - Joypad register
    osc*: uint32        # Internal Oscillator - Master Clock - It's ok to overflow this
    intFlag*: uint8     # Interrupt Flags - 0xFF0F
    intEnable*: uint8   # Interrupt Enable Register - 0xFFFF
    stopped*: bool      # STOP command affects other modules from CPU
    message*: string

  GameboyMode* = enum
    mgb, # Monochrome Gameboy - Original
    sgb, # Super Gameboy - Not Used at this time
    cgb  # Color Gameboy

  # Timer subsystem
  Timer* = object
    gb*: TimerGb         # Ref back to Gameboy object
    divReg*: DivReg      # Divider Register - At memory location 0xFF04 - Only MSB accessible
    timaCounter*: uint8  # Timer Counter - At memory locaton 0xFF05
    timaModulo*: uint8   # Timer Modulo - When TimaCounter overflows this value is loaded into Tima Counter
    tac*: uint8          # Timer Control - Enables timer and sets frequency
    timaPending*: bool   # Pending load of timaModulo into TimaCounter on next tick

  DivReg* = object
    counter*: uint16    # Only the MSB is accessible

  TimerGb* = ref object
    gameboy*: Gameboy

  # CPU Subsystem
  CPU* = object
    mem*: CPUMemory       # Ref back to gameboy - Avoids ciruclar references in NIM
    mClock*: uint8        # Machine Cycles (probably not used, but we have it anyway)
    tClock*: uint8        # Ticks
    pc*, sp*: uint16      # 16-bit Program Counter and Stack Pointer
    a*: uint8             # 8-Bit accumulator
    bc*, de*, hl*: uint16 # General purpose registers - Also operate as 8-bit combos
    f*: uint8             # "Flags" Register [Z N H C 0 0 0 0]
    halted*: bool         # Halted state for CPU power savings
    breakpoint*: uint16   # Single breakpoint for now
    eiPending*: bool      # Set when the EI Opcode is issued - Used for delaying the flip
    ime*: bool            # Global Interrupts Enabled (INTERNAL - NOT VISIBLE TO OPCODES)

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

  PPU* = object
    gb*: PPUGb
    vRAMTileDataBank0*: array[0x1800, uint8] # Stored in 0x8000 - 0x97FF - 384 Tiles
    vRAMTileDataBank1*: array[0x1800, uint8] # Stored in 0x8000 - 0x97FF - 384 More Tiles - Color Gameboy Only
    vRAMBgMap1*: array[0x400, uint8] # Stored in 0x9800 - 0x9BFF VG Background TileMaps 1 - 32x32 Tile Background Map
    vRAMBgMap2*: array[0x400, uint8] # Stored in 0x9C00 - 0x9FFF VG Background TileMaps 2 - 32x32 Tile Background Map
    oam*: array[0xA0, uint8] # Sprite Attribute Table - Object Attribute Memory - 40 Sprites
    # LCD Stuff
    lcdc*: uint8  # 0xFF40 - LCD Control Reigster
    stat*: uint8  # 0xFF41 - LCD Interrupt Handling
    scy*: uint8   # 0xFF42 - BG Scroll Y (R/W)
    scx*: uint8   # 0xFF43 - BG Scroll X (R/W)
    ly*: uint8    # 0xFF44 - Current LCD Scanline
    lyc*: uint8   # 0xFF45 - LCD Scanline Compare - Used to trigger LCDStat intterupt
    wy*: uint8    # 0xFF4A - Window Y Position (R/W)
    wx*: uint8    # 0xFF4B - Window X Position (R/W) - Minus 7?
    # Monochrome Gameboy Palettes
    bgp*: uint8   # 0xFF47 - BG Pallete Data (R/W) 
    obp0*: uint8  # 0xFF48 - Object Palette 0 Data (R/W)
    obp1*: uint8  # 0xFF49 - Object Palette 1 Data (R/W)
    # Color Gameboy Palettes
    bgpi*: uint8  # 0xFF68 - Background Palette Index
    bgpd*: uint8  # 0xFF69 - Background Palette Data
    ocps*: uint8  # 0xFF6A - Sprite Palette Index
    ocpd*: uint8  # 0xFF6B - Sprite Palette Data
    vbk*: uint8   # 0xFF4F - VRAM Bank
    # DMA Request
    dma*: uint8   # 0xFF46 - DMA Transfer and Start Address
    # LCD VRAM DMA - Color Gameboy Only
    hdma1*: uint8 # 0xFF51 - New DMA Source, High
    hdma2*: uint8 # 0xFF52 - New DMA Source, Low
    hdma3*: uint8 # 0xFF53 - New DMA Destination, High
    hdma4*: uint8 # 0xFF54 - New DMA Destination, Low
    hdma5*: uint8 # 0xFF55 - New DMA Length / Mode / Start
    # INTERNAL USE
    outputBuffer*: array[0x5A00, PixelFIFOEntry] # 23,040 Output "Pixels"
    requestedScy*: uint8  # This can be written to at any time but ONLY takes effect until HBLANK
    requestedScx*: uint8  # This can be written to at any time but ONLY takes effect until HBLANK
    requestedLyc*: uint8  # This can be written to at any time but ONLY takes effect until HBLANK
    requestedWy*: uint8   # This can be written to at any time but ONLY takes effect until HBLANK
    requestedWx*: uint8   # This can be written to at any time but ONLY takes effect until HBLANK
    mode*: PPUMode
    clock*: uint32 # Internal Clock
    oamBuffer*: OamBuffer # Used for OAM Detection on eac horizontal line
    fetch*: Fetch     # OAM Data and sprite data fetcher - Populates the FIFO
    fifo*: Deque[PixelFIFOEntry]  # Internals used for pixel rendering
    lx*: uint8        # Internal lx state
    vBlankPrimed*: bool # Used to one-shot fire vBlank interrupt when mode flips

  PPUGb* = ref object
    gameboy*: Gameboy

  PPUMode* = enum
    oamSearch, pixelTransfer, hBlank, vBlank
 
  OamBuffer* = object
    data*: array[0x09, uint8] # Up to 10 visible sprites
    idx*: uint8 # OAM Buffer Index - Keeps track of found sprites
    clock*: uint32 # Internal OAM Buffer Clock - Counts up to 40 ticks then resets

  Fetch* = object
    willFetch*: fWillFetch # What should be fetched
    tmpTileNum*: uint16    # Tmp placeholder for what tile will be read
    tmpTileOffsetX*: uint8 # The current tile that should be read
    tmpTileOffsetY*: uint8 # The current tile that should be read
    tmpByte0*: uint8       # Tmp placeholder for first byte read 
    result*: array[8, PixelFIFOEntry] # Block of data destined for the FIFO queue
    mode*: fModeState      # Mode of the fetcher
    canRun*: bool          # Fetch runs at 2Mhz so every OTHER call will be allowed.
    entity*: FetchEntity   # Type of data to be fetched
    idle*: bool            # The Fetcher goes idle when the data is waiting to be put into FIFO

  fWillFetch* = enum
    fWillFetchWindow, fWillFetchBackground, fWillFetchSprite

  fModeState* = enum
    fmsReadTile, fmsReadData0, fmsReadData1, fmsIdle

  FetchEntity* = enum
    ftBackground, ftWindow, ftSprite0, ftSprite1 # Used to determine the pixel mixing

  PixelFIFOEntry* = object
    data*: uint8          # Will only contain pallete references - 0b00 -> 0b11
    entity*: FetchEntity  # Used to determine rules for mixing and palette lookups

  # AUDIO!
  AudioSettings* = object
    sampleRate*: uint
    numChannels*: uint
    samples*: uint
  
  AudioHardware* = object
    hardwareSpec*: AudioSpec
    audioDeviceID*: AudioDeviceID





