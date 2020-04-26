#
# Keyboard Input
#
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
