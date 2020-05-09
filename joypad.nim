#
# Keyboard Input
#
import bitops
import sdl2

type
  Input* {.pure.} = enum none, scale1x, scale2x, scale3x, scale4x, quit, up, down, left, right, select, start, a, b

proc toInput*(key: Scancode): Input = 
  case key:
  of SDL_SCANCODE_1: Input.scale1x  
  of SDL_SCANCODE_2: Input.scale2x
  of SDL_SCANCODE_3: Input.scale3x
  of SDL_SCANCODE_4: Input.scale4x
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

proc keyDown*(input: Input; currentJoypad: uint8): uint8 = 
  # Returns the byte to be placed in the gameboy register.
  result = currentJoypad
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

proc keyUp*(input: Input; currentJoypad: uint8): uint8 = 
  # Returns the byte to be placed in the gameboy register.
  result = currentJoypad
  case input:
  of Input.down:
    result.setBit(3)
  of Input.start:
    result.setBit(3)
  of Input.up:
    result.setBit(2)
  of Input.select:
    result.setBit(2)
  of Input.left:
    result.setBit(1)
  of Input.b:
    result.setBit(1)
  of Input.right:
    result.setBit(0)
  of Input.a:
    result.setBit(0)
  else:
    discard