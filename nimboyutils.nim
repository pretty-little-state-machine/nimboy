proc byteSeqToString*(bytes: seq): string =
  var s = newString(bytes.len)
  for idx, i in bytes:
    s[idx] = chr(i)
  return s

proc readMsb*(word: uint16): uint8 =
  return uint8(word shr 8)

proc readLsb*(word: uint16): uint8 =
  return uint8(word)

