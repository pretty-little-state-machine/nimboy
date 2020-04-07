import os
import parseutils
import strutils
import terminal
import bitops
import types
import cartridge
import gameboy
import nimboyutils
import cpu

type
  Debugger* = object
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
  stdout.write "│  Break: " & ($tohex(cpu.breakpoint))
  setCursorPos(90,15)
  stdout.write("╰────────────────┤")

proc drawTitle(cartridge: Cartridge) =
  setCursorPos(1,1)
  stdout.write(cartridge.getRomDetailStr())

proc draw(gameboy: Gameboy; debugger: Debugger) =
  drawCliTables()
  drawCpu(gameboy.cpu)
  drawTitle(gameboy.cartridge)
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

proc parseCommand(gameboy: var Gameboy; input: string; debugger: var Debugger) = 
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
        if "BREAK" == r:
          debugger.history.add("!--BREAKPOINT--!")
          break
        else:
          debugger.history.add(r)
    else:
      debugger.history.add(gameboy.step())
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

proc launchDebugger*(gameboy: var Gameboy) = 
  var debugger: Debugger
  draw(gameboy, debugger)
  while true:
    var input: string = readLine(stdin)
    parseCommand(gameboy, input, debugger)
    draw(gameboy, debugger)
