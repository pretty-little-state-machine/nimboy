import strutils
import terminal
import types
import cartridge

type
  Debugger* = object
    history: seq[string]

proc drawCliTables() = 
  eraseScreen()
  setForegroundColor(fgWhite, true)
  setCursorPos(0,0)
  # Top
  stdout.write "╭"
  for x in countup(1, 126):
    stdout.write "─"
  stdout.write "╮\n"
  
  # Sides
  for y in countup(1,38):
    stdout.write "│"
    for x in countup(1, 126):
      stdout.write " "
    stdout.write "│\n"

  # Bottom
  stdout.write "╰"
  for x in countup(1, 126):
    stdout.write "─"
  stdout.write "╯\n"

  # Top Bar
  setCursorPos(0, 2)
  stdout.write "├"
  for x in countup(1, 126):
    stdout.write "─"
  stdout.write "┤"
  # Bottom Bar
  setCursorPos(0,37)
  stdout.write "├"
  for x in countup(1, 126):
    stdout.write "─"
  stdout.write "┤"
  resetAttributes()

proc drawCpu(cpu: CPU) =
  setCursorPos(110,2)
  stdout.write("┬")
  for y in countup(3,9):
    setCursorPos(110,y)
    stdout.write "│"
  setCursorPos(115,3)
  stdout.write("A ", $toHex(cpu.a), $toHex(cpu.f), " F")
  setCursorPos(115,4)
  stdout.write("B ", $toHex(cpu.b), $toHex(cpu.c), " C")
  setCursorPos(115,5)
  stdout.write("D ", $toHex(cpu.d), $toHex(cpu.e), " E")
  setCursorPos(115,6)
  stdout.write("H ", $toHex(cpu.h), $toHex(cpu.l), " L")
  setCursorPos(114,8)
  stdout.write("SP ", $tohex(cpu.sp))
  setCursorPos(114,9)
  stdout.write("PC ", $tohex(cpu.pc))
  setCursorPos(110,10)
  stdout.write("╰────────────────┤")

proc drawTitle(cartridge: Cartridge) =
  setCursorPos(1,1)
  stdout.write(cartridge.getRomTitle())

proc draw(gameboy: Gameboy) =
  drawCliTables()
  drawCpu(gameboy.cpu)
  drawTitle(gameboy.cartridge)
  # Input Block
  setCursorPos(1,38)
  stdout.write "> "
  stdout.setStyle({styleBlink})
  stdout.write "_"
  stdout.resetAttributes()
  setCursorPos(3,38)

proc parseCommand(gameboy: var Gameboy; input: string) = 
  let args = input.split(' ')
  if "load" in args[0] and 2 == args.len:
    gameboy.cartridge.loadRomFile(args[1])
  elif "unload" in args[0] and 1 == args.len:
    gameboy.cartridge.unloadRom()
  else:
    discard

proc launchDebugger*(gameboy: var Gameboy) = 
  var debugger: Debugger
  draw(gameboy)
  while true:
    var input: string = readLine(stdin)
    parseCommand(gameboy, input)
    debugger.history.add(input)
    draw(gameboy)
