 # Picture Processing Unit Notes

These notes are taken from [The _ultimate_ Gameboy Talk](https://www.youtube.com/watch?v=HyzD8pNlpwI])
and attempt to document how the PPU works as implemented in NimBoy.

## FIFO Queuing
The FIFO queue runs on a 4Mhz clock while the fetcher runs on a 2 Mhz clock.

#### FIFO
* Each 4Mhz tick results in 1 pixel being output to the screen.
* Pauses unless it contains more than 8 pixels

#### Fetch
* 3 Clocks to fetch 8 pixels
* Pauses in 4th clock unless space in FIFO

#### Timing Comparison
```
| FIFO |     FETCH   |  FIFO Visulization
===============================================
| Push |             | [########|#######_]
|------| Read Tile # | 
| Push |             | [########|######__] 
|------|-------------|
| Push |             | [########|#####___] 
|------| Read Data 0 |
| Push |             | [########|####____] 
|------|-------------|
| Push |             | [########|###_____] 
|------| Read Data 1 |
| Push |             | [########|##______] 
|------|-------------| <Waiting for FIFO to clear>
| Push |             | [########|#_______]
|------| Idle        | 
| Push |             | [########|________] 
|------|-------------| < PUSH INTO FIFO QUEUE >
| Push |             | [########|########]
|------| Read Tile # | 
| Push |             | [########|#######_] 
|------|-------------|
...
```
### Scrolling
If scrolling `Scx` then the pixels are just discarded from the FIFO queue
instead of going to the screen.

### End of Line

Once we get to the end of the line (x = 160) the FIFO queue may contain data:
```
[########|###_____] (5 bits free)
```

That means that the FIFO queue did extra work (it had 3 ticks worth of pushes) so the best
possible case is 43 clock cycles. This extra work is discarded. 

**TODO** Explain this better.


### Windowing
When the window hits the FIFO is cleared. This means we have to do a fresh 
fetch before the pixel FIFO can write to the screen for a total of 6 ticks.

Detail of FIFO Queue Timing during windows
```
 [------------------------------------------------------------------>] 43 OR MORE Clocks
 First Pixel          Piple Cleared    Fetcher reads 
 |                      FIFO Paused    window tiles   FIFO Resumed
 |                            |            |          |
 [][][][][][][][][][][][][][][]-----------------------[][][][][][]//[] 
                              |
                         Start of Window (Wy)
```

### Sprites

Each Sprite ("Object" for Nintendo) are triggered on X Position.  The following happens:
1. Pause FIFO queue
2. Clear the Fetch Cycle
3. Read in the Sprite Data
4. Overlay it on the first 8 pixels of FIFO
5. Mix them together with the existing pixel data


### Pixel Mixing (What's actually in the FIFO queue)
The FIFO queue actually conatins the bit combinations, not the colors 
the sprite. This is represented in the NimBoy as the "PixelFIFOEntry".

```
  PixelFIFOEntry = object
    data: uint8
    fifoType: PixelFIFOType
```

Shown another way (only the first 8 bits of the FIFO are shown)

```
    data [ 10 | 01 | 01 | 10 | 11 | 10 | 10 | 10 |...]
fifoType [ BG | BG | BG | BG | BG | BG | BG | BG |...]
```

When mixing pixels the FIFO is overlayed on itself and the sprite data is 
compared agains the existing background / window data:

```
    data [ 00 | 11 | 11 | 01 | 11 | 01 | 11 | 00 |...] <-- Sprite Priority 0
fifoType [ S1 | S1 | S1 | S1 | S1 | S1 | S1 | S1 |...] <-- from OAM Data (not shown)
    data [ 10 | 01 | 01 | 10 | 10 | 11 | 01 | 10 |...]
fifoType [ BG | BG | BG | BG | BG | BG | BG | BG |...]
```

During the overlay operation the sprite priority is provided alongside
the `PixelFIFOEntry`. This determines the mixing behavior. Here is the 
result of the above operation.

```
    data [ 00 | 11 | 11 | 01 | 11 | 01 | 11 | 00 |...] <-- Sprite Priority 0
fifoType [ S1 | S1 | S1 | S1 | S1 | S1 | S1 | S1 |...] <-- from OAM Data (not shown)
    data [ 10 | 01 | 01 | 10 | 10 | 11 | 01 | 10 |...]
fifoType [ BG | BG | BG | BG | BG | BG | BG | BG |...]
----------------------------------------------------------------
    data [ 10 | 11 | 11 | 01 | 11 | 01 | 11 | 10 |...]
fifoType [ BG | S1 | S1 | S1 | S1 | S1 | S1 | BG |...]
```

What if we have another sprite at the exact same location?

```
    data [ 01 | 01 | 01 | 01 | 01 | 01 | 01 | 01 |...] <-- Sprite Priority 0
fifoType [ S0 | S0 | S0 | S0 | S0 | S0 | S0 | S0 |...] <-- from OAM Data (not shown)
    data [ 10 | 11 | 11 | 01 | 11 | 01 | 11 | 10 |...] <-- Output from previous result
fifoType [ BG | S1 | S1 | S1 | S1 | S1 | S1 | BG |...] <-- Output from previous result
----------------------------------------------------------------
    data [ 01 | 11 | 11 | 01 | 11 | 01 | 11 | 10 |...]
fifoType [ S0 | S1 | S1 | S1 | S1 | S1 | S1 | S0 |...]
```

This is why sprites that are farther to the right do not draw on top of 
existing sprites and why sprites with higher numbers don't draw on top 
of existing sprites.

### Summary
Thus this is how the modes work where the pixel transfer operation can take 
at a minimum 43 clocks but more if there are windows or extra sprites.

These extra cycles are removed from the H-Blank clock as the total cycle 
count per horizontal line is 114 clocks.
 ```
      |----------------------------114 Clocks-----------------------------|
      |----20 Clocks----|<-----43+ Clocks----->|<-------51- Clocks------->|
 ___  +===================================================================+
  |   |                 |                      |                          |
  |   |                 |                         |                       |
  |   |       OAM       |    Pixel Transfer    |        H-BLANK           |
  |   |                 |                      |                          |
  |   |                 |                      |                          |
 144  |                 |                       |                         |
 Lines|                 |                             |                   |
  |   |                 |                      |                          |
  |   |                 |                        |                        |
  |   |                 |                      |                          |
 ---  |-------------------------------------------------------------------|
  10  |                           VBLANK                                  |
 ---  +===================================================================+
```