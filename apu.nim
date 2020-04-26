#
# Audio Processing Unit
#
# Some notes on the math in this module. Times are in milliseconds
#       ____________________      ____________________
# _____|        20         |_____|         20        |_____
#   5                         5                         5
#
# Pw = Pulse Width = 20 ms
# Sw = Space Width = 5 ms
# Tc = Cycle Time  = (Pw + Sw)/1000 = 0.025s
#  f = Frequency   = 1/Tc = 40 hz
# Dc = Duty Cycle  = Pw / Tc * 100 = 80%
# 
# A _square_ wave has a duty cycle of 50%
#
# Some good resources on how to use SDL Audio:
# https://github.com/nim-lang/sdl2/blob/master/examples/sdl_audiostream.nim
# https://github.com/Rust-SDL2/rust-sdl2/blob/master/examples/audio-queue-squarewave.rs
# https://davidgow.net/handmadepenguin/ch8.html
#
import math
import bitops
import sdl2, sdl2/audio
import types

proc setupAudioOutput(settings: AudioSettings): AudioHardware =
  # start up SDL2
  if sdl2.init(INIT_AUDIO) != SdlSuccess:
    quit "failed to init SDL2!"

  # SDL 2.0.7 is the first version with audio streams. If you want
  # to convert audio from one format to another before 2.0.7, you
  # have to use AudioCVT.
  var version: SDL_Version
  getVersion(version)
  if (version.major <= 2'u8) and
    (version.minor <= 0'u8) and
    (version.patch < 7'u8):
    quit "The installed version of SDL2 does not support SDL_AudioStream!"

  let ndevices = getNumAudioDevices(0.cint).cint
  if ndevices == 0:
    quit "No audio devices found!"

  # Initialize the Hardware
  result.hardwareSpec = AudioSpec()
  result.hardwareSpec.freq = settings.sampleRate.cint
  result.hardwareSpec.format = AUDIO_S16
  result.hardwareSpec.channels = settings.numChannels.uint8
  result.hardwareSpec.samples = settings.samples.uint16
  result.hardwareSpec.padding = 0

  # Adjust the first integer to match the audio device you want.
  let deviceName = getAudioDeviceName(1.cint, 0.cint)

  # If the device can't handle one of the specs we've given it, 
  # openAudioDevice will tweak the contents of hardwareSpec to match something
  # the device can do.
  result.audioDeviceID = openAudioDevice(deviceName, 0.cint, addr result.hardwareSpec, nil, 0)

  # Debugging if required. Useful for figuring out the audio device to use.
  echo deviceName
  echo "  frequency: ", result.hardwareSpec.freq
  echo "  format: ", result.hardwareSpec.format
  echo "  channels: ", result.hardwareSpec.channels
  echo "  samples: ", result.hardwareSpec.samples
  echo "  padding: ", result.hardwareSpec.padding

proc registerToHz*(lowReg: uint8; highReg: uint8): uint32 =
  # Converts the gameboy 11-byte encoding to a frequency in hz.
  # Output range of 64hz to 131,072 hz (way out of human range, 18->20khz)
  #
  # Something to note here: The sound conversion is NOT a linear relationship!
  # There are 32 samples of 64 -> 65 hz but in the 800 hz section each increment
  # may result in several hz of jump between values. 
  #
  # See notes/APU_Frequency.ods
  #
  var word: uint16 = lowReg
  # Take the first three bits only of the high register
  if highReg.testBit(0): word.setBit(8)
  if highReg.testBit(1): word.setBit(9)
  if highReg.testBit(2): word.setBit(10)
  # This magic number is the crystal frequency of the gameboy's 4Mhz clock.
  result = 4194304'u32 div uint32(32 * (2048 - word))

proc genRectWave(settings: AudioSettings; bytesToWrite: uint32): seq[int] = 
  let
    toneHz = 2500'u32
    toneVolume = 3_000 # 32767 is loudest
    squareWavePeriod = settings.sampleRate div toneHz

  for x in countup(0.uint, bytesToWrite):
    if 0 == (x div (squareWavePeriod div 2)) mod 2:
      result.add(toneVolume)
    else:
      result.add(-toneVolume)

proc testSound*(): void = 
  var settings: AudioSettings
  settings.sampleRate = 48_000
  settings.numChannels = 2
  settings.samples = 4094

  let audioHardware = setupAudioOutput(settings)
  audioHardware.audioDeviceID.pauseAudioDevice(0.cint) # Play

  let nBytesPerSample = audioHardware.hardwareSpec.channels * (SDL_AUDIO_BITSIZE(audioHardware.hardwareSpec.format.uint32) div 8).uint8
  echo nBytesPerSample
  let wave = genRectWave(settings, uint32(8000 * nBytesPerSample))
  
  if 0 > audioHardware.audioDeviceID.queueAudio(unsafeAddr wave[0], uint32(len(wave) * sizeof(int))):
    echo $sdl2.getError()
    quit "Failed to queue audio!"
  
  while audioHardware.audioDeviceID.getQueuedAudioSize() > 0'u32:
    discard
