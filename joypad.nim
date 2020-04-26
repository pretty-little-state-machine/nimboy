#
# Keyboard Input
#
import bitops
import sdl2

type
  Input* {.pure.} = enum none, quit, up, down, left, right, select, start, a, b

proc toInput*(key: Scancode): Input = 
  case key:
  of SDL_SCANCODE_Q: Input.quit
  of SDL_SCANCODE_W: Input.up
  of SDL_SCANCODE_A: Input.left
  of SDL_SCANCODE_S: Input.down
  of SDL_SCANCODE_D: Input.right
  of SDL_SCANCODE_J: Input.a
  of SDL_SCANCODE_K: Input.b
  of SDL_SCANCODE_RETURN: Input.start
  of SDL_SCANCODE_SPACE: Input.select
  else: Input.none

proc toRegisterByte*(input: Input): uint8 = 
  # Returns the byte to be placed in the gameboy register.
  result = 0b0000_1111 # 1 is "unpressed" on the matrix
  case input:
  of Input.down:
    result.clearBit(3)
  of Input.start:
    result.clearBit(3)
  of Input.up:
    result.clearBit(2)
  of Input.select:
    result.clearBit(2)
  of Input.left:
    result.clearBit(1)
  of Input.b:
    result.clearBit(1)
  of Input.right:
    result.clearBit(0)
  of Input.a:
    result.clearBit(0)
  else:
    discard

    