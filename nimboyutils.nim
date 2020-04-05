proc byteSeqToString*(bytes: seq): string =
  var s = newString(bytes.len)
  for idx, i in bytes:
    s[idx] = chr(i)
  return s
