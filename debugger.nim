import parseutils
import strutils
import terminal
import bitops
import colors
# Nimboy Imports
import types
import cartridge
import gameboy
import nimboyutils
import cpu

type
  Debugger* = ref DebuggerObj
  DebuggerObj* = object
    history: seq[string]

proc drawCliTables() = 
  eraseScreen()
  setForegroundColor(fgWhite, true)
  setCursorPos(0,0)
  # Top
  stdout.write "╭"
  for x in countup(1, 106):
    stdout.write "─"
  stdout.write "╮\n"
  
  # Sides
  for y in countup(1,38):
    stdout.write "│"
    for x in countup(1, 106): stdout.write " "
    stdout.write "│\n"

  # Bottom
  stdout.write "╰"
  for x in countup(1, 106): stdout.write "─"
  stdout.write "╯\n"

  # Top Bar
  setCursorPos(0, 2)
  stdout.write "├"
  for x in countup(1, 106): stdout.write "─"
  stdout.write "┤"
  # Bottom Bar
  setCursorPos(0,37)
  stdout.write "├"
  for x in countup(1, 106): stdout.write "─"
  stdout.write "┤"
  resetAttributes()

proc decodeFlags(cpu: CPU): string =
  var s: string
  if cpu.f.testBit(7):
    s = s & " 1"
  else: 
    s = s & " 0"
  if cpu.f.testBit(6):
    s = s & " 1"
  else: 
    s = s & " 0"
  if cpu.f.testBit(5):
    s = s & " 1"
  else: 
    s = s & " 0"
  if cpu.f.testBit(4):
    s = s & " 1"
  else: 
    s = s & " 0"
  return s

proc drawCpu(cpu: CPU) =
  setCursorPos(90,2)
  stdout.write("┬")
  for y in countup(3,12):
    setCursorPos(90,y)
    stdout.write "│"
  setCursorPos(95,3)
  stdout.write("A ", $toHex(cpu.a), $toHex(cpu.f), " F")
  setCursorPos(95,4)
  stdout.write("B ", $toHex(readMsb(cpu.bc)), $toHex(readLsb(cpu.bc)), " C")
  setCursorPos(95,5)
  stdout.write("D ", $toHex(readMsb(cpu.de)), $toHex(readLsb(cpu.de)), " E")
  setCursorPos(95,6)
  stdout.write("H ", $toHex(readMsb(cpu.hl)), $toHex(readLsb(cpu.hl)), " L")
  setCursorPos(94,8)
  stdout.write("SP ", $tohex(cpu.sp))
  setCursorPos(94,9)
  stdout.write("PC ", $tohex(cpu.pc))
  # Flags!
  setCursorPos(95,11)
  stdout.write (" Z N H C ")
  setCursorPos(95,12)
  stdout.write (decodeFlags(cpu))
  setCursorPos(90,13)
  stdout.write("├────────────────┤")
  # Breakpoint!
  setCursorPos(90,14)
  stdout.write "│   Break: " & ($tohex(cpu.breakpoint))
  # Done with CPU
  setCursorPos(90,15)
  stdout.write("├────────────────┤")

proc drawTitle(cartridge: Cartridge) =
  setCursorPos(1,1)
  stdout.write(cartridge.getRomDetailStr())

proc drawInterrupts(gameboy: Gameboy) = 
  setCursorPos(90,16)
  stdout.write ("│ Joypad: ")
  if (testBit(gameboy.intEnable, 4)):
    setForegroundColor(fgGreen, false)
    setCursorPos(100, 16)
    stdout.write("ENA")
  else:
    setForegroundColor(fgRed, false)
    setCursorPos(100, 16)
    stdout.write("DIS")
  if(testBit(gameboy.intFlag, 4)):
    setForegroundColor(fgRed, true)
    setCursorPos(104, 16)
    stdout.write("TRG")
  else:
    setForegroundColor(fgWhite, false)
    setCursorPos(104, 16)
    stdout.write("---")
  #
  setForegroundColor(fgWhite, true)
  setCursorPos(90,17)
  stdout.write ("│ Serial: ")
  if (testBit(gameboy.intEnable, 3)):
    setForegroundColor(fgGreen, false)
    setCursorPos(100, 17)
    stdout.write("ENA")
  else:
    setForegroundColor(fgRed, false)
    setCursorPos(100, 17)
    stdout.write("DIS")
  if(testBit(gameboy.intFlag, 3)):
    setForegroundColor(fgRed, true)
    setCursorPos(104, 17)
    stdout.write("TRG")
  else:
    setForegroundColor(fgWhite, false)
    setCursorPos(104, 17)
    stdout.write("---")
  #
  setForegroundColor(fgWhite, true)
  setCursorPos(90, 18)
  stdout.write ("│  Timer: ")
  if (testBit(gameboy.intEnable, 2)):
    setForegroundColor(fgGreen, false)
    setCursorPos(100, 18)
    stdout.write("ENA")
  else:
    setForegroundColor(fgRed, false)
    setCursorPos(100, 18)
    stdout.write("DIS")
  if(testBit(gameboy.intFlag, 2)):
    setForegroundColor(fgRed, true)
    setCursorPos(104, 18)
    stdout.write("TRG")
  else:
    setForegroundColor(fgWhite, false)
    setCursorPos(104, 18)
    stdout.write("---")
  #
  setForegroundColor(fgWhite, true)
  setCursorPos(90, 19)
  stdout.write ("│LCDStat: ")
  if (testBit(gameboy.intEnable, 1)):
    setForegroundColor(fgGreen, false)
    setCursorPos(100, 19)
    stdout.write("ENA")
  else:
    setForegroundColor(fgRed, false)
    setCursorPos(100, 19)
    stdout.write("DIS")
  if(testBit(gameboy.intFlag, 1)):
    setForegroundColor(fgRed, true)
    setCursorPos(104, 19)
    stdout.write("TRG")
  else:
    setForegroundColor(fgWhite, false)
    setCursorPos(104, 19)
    stdout.write("---")
  #
  setForegroundColor(fgWhite, true)
  setCursorPos(90, 20)
  stdout.write ("│  VSync:")
  if (testBit(gameboy.intEnable, 0)):
    setForegroundColor(fgGreen, false)
    setCursorPos(100, 20)
    stdout.write("ENA")
  else:
    setForegroundColor(fgRed, false)
    setCursorPos(100, 20)
    stdout.write("DIS")
  if(testBit(gameboy.intFlag, 0)):
    setForegroundColor(fgRed, true)
    setCursorPos(104, 20)
    stdout.write("TRG")
  else:
    setForegroundColor(fgWhite, false)
    setCursorPos(104, 20)
    stdout.write("---")
  # Global Interrupts
  setForegroundColor(fgWhite, true)
  setCursorPos(90, 21)
  stdout.write ("│ GLOBAL:")
  if gameboy.cpu.ime:
    setForegroundColor(fgGreen, false)
    setCursorPos(100, 21)
    stdout.write("ENA")
  else:
    setForegroundColor(fgRed, false)
    setCursorPos(100, 21)
    stdout.write("DIS")
  setForegroundColor(fgWhite, true)
  setCursorPos(90,22)
  stdout.write("╰────────────────┤")

proc drawPpuMode(ppu: PPU) =
  setCursorPos(70, 3)
  stdout.write($ppu.clock)
  setCursorPos(70, 4)
  case ppu.mode
  of oamSearch:
    stdout.write("OAM Search")
  of pixelTransfer:
    stdout.write("Pixel Transfer")
  of hBlank:
    stdout.write("H-Blank")
  of vBlank:
    stdout.write("V-Blank")

  setCursorPos(70,5)
  stdout.write(" LY: " & $ppu.ly)
  setCursorPos(70,6)
  stdout.write("SCX: " & $ppu.scx)
  setCursorPos(70,7)
  stdout.write("SCY: " & $ppu.scy)
  setCursorPos(70,8)
  stdout.write(" WX: " & $ppu.wx)
  setCursorPos(70,9)
  stdout.write(" WY: " & $ppu.wy)
  setCursorPos(70,10)
  stdout.write("FQD: " & $ppu.fifo.queueDepth)
  setCursorPos(70,11)
  stdout.write(" Lx: " & $ppu.fifo.pixelTransferX)
  setCursorPos(60,12)
  stdout.write("FState: ")
  setCursorPos(70,12)
  case ppu.fetch.mode
  of fmsReadTile:
    stdout.write("Read Tile")
  of fmsReadData0:
    stdout.write("Read Data 0")
  of fmsReadData1:
    stdout.write("Read Data 1")
  setCursorPos(60,13)
  stdout.write("F.Idle: ")
  setCursorPos(70,13)
  if ppu.fetch.idle:
    stdout.write("True")
  else:
    stdout.write("False")

proc draw(gameboy: Gameboy; debugger: Debugger) =
  drawCliTables()
  drawCpu(gameboy.cpu)
  drawTitle(gameboy.cartridge)
  drawInterrupts(gameboy)
  drawPpuMode(gameboy.ppu)
  # OPCode Decoder
  var i = 0
  for x in countdown(debugger.history.len, debugger.history.len - 30):
    setCursorPos(1,4 + i)
    if x > 0: 
      stdout.write(debugger.history[x-1])
    i += 1
  
  # Input Block
  setCursorPos(1,38)
  stdout.write "> "
  stdout.setStyle({styleBlink})
  stdout.write "_"
  stdout.resetAttributes()
  setCursorPos(3,38)

proc parseCommand(gameboy: var Gameboy; input: string; debugger: var Debugger): void = 
  let args = input.split(' ')
  if "load" in args[0] and 2 == args.len:
    gameboy.cartridge.loadRomFile(args[1])
  elif "unload" in args[0] and 1 == args.len:
    gameboy.cartridge.unloadRom()
  elif "bp" in args[0] and 2 == args.len:
    var bp = 0
    if parseHex(args[1], bp) > 0:
      gameboy.cpu.addBreakpoint(cast[uint16](bp))
  elif "st" in args[0]:
    if args.len > 1:
      for x in countup(1, parseint(args[1])):
        var r = gameboy.step()
        if "BREAK!" == r.debugStr:
          debugger.history.add("!--BREAKPOINT--!")
          break
        else:
          debugger.history.add(r.debugStr)
    else:
      debugger.history.add(gameboy.step().debugStr)
  elif "tf" in args[0] and 2 == args.len:
    if "z" in args[1] or "Z" in args[1]:
      gameboy.cpu.f.flipBit(7)
    elif "n" in args[1] or "N" in args[1]:
      gameboy.cpu.f.flipBit(6)
    elif "h" in args[1] or "H" in args[1]:
      gameboy.cpu.f.flipBit(5)
    elif "c" in args[1] or "C" in args[1]:
      gameboy.cpu.f.flipBit(4)
    else:
      discard
  else:
    discard

proc debug*(gameboy: var Gameboy; debugger: var Debugger): void = 
  draw(gameboy, debugger)
  var input: string = readLine(stdin)
  parseCommand(gameboy, input, debugger)
  draw(gameboy, debugger)

proc newDebugger*(): Debugger = 
  new result
  result