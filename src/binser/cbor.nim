## cbor.nim -- CBOR (RFC 8949) encoder/decoder. Pure Nim.
##
## Major types 0-7: unsigned int, negative int, byte string, text string,
## array, map, tag, simple/float.

{.experimental: "strict_funcs".}

import basis/code/choice

type
  BinserError* = object of CatchableError


# =====================================================================================================================
# Types
# =====================================================================================================================

type
  CborKind* = enum
    ckUint, ckNegint, ckBytes, ckText, ckArray, ckMap, ckTag,
    ckSimple, ckFloat16, ckFloat32, ckFloat64, ckBool, ckNull, ckUndef

  CborValue* = ref object
    case kind*: CborKind
    of ckUint: uint_val*: uint64
    of ckNegint: negint_val*: uint64  ## actual value is -1 - negint_val
    of ckBytes: bytes_val*: string
    of ckText: text_val*: string
    of ckArray: arr_val*: seq[CborValue]
    of ckMap: map_val*: seq[(CborValue, CborValue)]
    of ckTag:
      tag_num*: uint64
      tag_content*: CborValue
    of ckSimple: simple_val*: uint8
    of ckFloat16: f16_val*: uint16  # raw bits
    of ckFloat32: f32_val*: float32
    of ckFloat64: f64_val*: float64
    of ckBool: bool_val*: bool
    of ckNull, ckUndef: discard

# =====================================================================================================================
# Constructors
# =====================================================================================================================

proc cbor_uint*(v: uint64): CborValue = CborValue(kind: ckUint, uint_val: v)
proc cbor_negint*(v: uint64): CborValue = CborValue(kind: ckNegint, negint_val: v)
proc cbor_int*(v: int64): CborValue =
  if v >= 0: cbor_uint(uint64(v))
  else: cbor_negint(uint64(-1 - v))
proc cbor_bytes*(v: string): CborValue = CborValue(kind: ckBytes, bytes_val: v)
proc cbor_text*(v: string): CborValue = CborValue(kind: ckText, text_val: v)
proc cbor_array*(v: seq[CborValue]): CborValue = CborValue(kind: ckArray, arr_val: v)
proc cbor_map*(v: seq[(CborValue, CborValue)]): CborValue = CborValue(kind: ckMap, map_val: v)
proc cbor_bool*(v: bool): CborValue = CborValue(kind: ckBool, bool_val: v)
proc cbor_null*(): CborValue = CborValue(kind: ckNull)
proc cbor_float32*(v: float32): CborValue = CborValue(kind: ckFloat32, f32_val: v)
proc cbor_float64*(v: float64): CborValue = CborValue(kind: ckFloat64, f64_val: v)

# =====================================================================================================================
# Encode
# =====================================================================================================================

proc encode_head(major: uint8, val: uint64): string =
  let mt = major shl 5
  if val <= 23:
    result = $char(mt or uint8(val))
  elif val <= 255:
    result = $char(mt or 24) & $char(val)
  elif val <= 65535:
    result = $char(mt or 25)
    result.add(char(val shr 8)); result.add(char(val and 0xFF))
  elif val <= 4294967295'u64:
    result = $char(mt or 26)
    for i in countdown(3, 0): result.add(char((val shr (i * 8)) and 0xFF))
  else:
    result = $char(mt or 27)
    for i in countdown(7, 0): result.add(char((val shr (i * 8)) and 0xFF))

proc encode*(v: CborValue): string {.raises: [BinserError].}

proc encode*(v: CborValue): string =
  case v.kind
  of ckUint: result = encode_head(0, v.uint_val)
  of ckNegint: result = encode_head(1, v.negint_val)
  of ckBytes: result = encode_head(2, uint64(v.bytes_val.len)) & v.bytes_val
  of ckText: result = encode_head(3, uint64(v.text_val.len)) & v.text_val
  of ckArray:
    result = encode_head(4, uint64(v.arr_val.len))
    for item in v.arr_val: result.add(encode(item))
  of ckMap:
    result = encode_head(5, uint64(v.map_val.len))
    for (k, val) in v.map_val:
      result.add(encode(k)); result.add(encode(val))
  of ckTag:
    result = encode_head(6, v.tag_num) & encode(v.tag_content)
  of ckBool:
    result = if v.bool_val: "\xf5" else: "\xf4"
  of ckNull: result = "\xf6"
  of ckUndef: result = "\xf7"
  of ckSimple:
    if v.simple_val <= 23: result = $char(0xe0'u8 or v.simple_val)
    else: result = "\xf8" & $char(v.simple_val)
  of ckFloat16:
    result = "\xf9"
    result.add(char(v.f16_val shr 8)); result.add(char(v.f16_val and 0xFF))
  of ckFloat32:
    result = "\xfa"
    let bits = cast[uint32](v.f32_val)
    for i in countdown(3, 0): result.add(char((bits shr (i * 8)) and 0xFF))
  of ckFloat64:
    result = "\xfb"
    let bits = cast[uint64](v.f64_val)
    for i in countdown(7, 0): result.add(char((bits shr (i * 8)) and 0xFF))

# =====================================================================================================================
# Decode
# =====================================================================================================================

proc read_u8(buf: string, pos: var int): uint8 {.raises: [BinserError].} =
  if pos >= buf.len: raise newException(BinserError, "cbor: unexpected end")
  result = uint8(buf[pos]); inc pos

proc read_bytes(buf: string, pos: var int, n: int): string {.raises: [BinserError].} =
  if pos + n > buf.len: raise newException(BinserError, "cbor: unexpected end")
  result = buf[pos ..< pos + n]; pos += n

proc decode_arg(buf: string, pos: var int, additional: uint8): uint64 {.raises: [BinserError].} =
  if additional <= 23: uint64(additional)
  elif additional == 24: uint64(read_u8(buf, pos))
  elif additional == 25:
    let a = uint64(read_u8(buf, pos)); let b = uint64(read_u8(buf, pos))
    (a shl 8) or b
  elif additional == 26:
    var r: uint64 = 0
    for i in 0 ..< 4: r = (r shl 8) or uint64(read_u8(buf, pos))
    r
  elif additional == 27:
    var r: uint64 = 0
    for i in 0 ..< 8: r = (r shl 8) or uint64(read_u8(buf, pos))
    r
  else:
    raise newException(BinserError, "cbor: invalid additional info: " & $additional)

proc decode*(buf: string, pos: var int): CborValue {.raises: [BinserError].}

proc decode*(buf: string, pos: var int): CborValue =
  let ib = read_u8(buf, pos)
  let major = ib shr 5
  let additional = ib and 0x1f
  case major
  of 0: cbor_uint(decode_arg(buf, pos, additional))
  of 1: cbor_negint(decode_arg(buf, pos, additional))
  of 2:
    let n = int(decode_arg(buf, pos, additional))
    cbor_bytes(read_bytes(buf, pos, n))
  of 3:
    let n = int(decode_arg(buf, pos, additional))
    cbor_text(read_bytes(buf, pos, n))
  of 4:
    let n = int(decode_arg(buf, pos, additional))
    var arr: seq[CborValue]
    for i in 0 ..< n: arr.add(decode(buf, pos))
    cbor_array(arr)
  of 5:
    let n = int(decode_arg(buf, pos, additional))
    var pairs: seq[(CborValue, CborValue)]
    for i in 0 ..< n:
      let k = decode(buf, pos); let v = decode(buf, pos)
      pairs.add((k, v))
    cbor_map(pairs)
  of 6:
    let tag = decode_arg(buf, pos, additional)
    let content = decode(buf, pos)
    CborValue(kind: ckTag, tag_num: tag, tag_content: content)
  of 7:
    case additional
    of 20: cbor_bool(false)
    of 21: cbor_bool(true)
    of 22: cbor_null()
    of 23: CborValue(kind: ckUndef)
    of 25:
      let a = uint16(read_u8(buf, pos)); let b = uint16(read_u8(buf, pos))
      CborValue(kind: ckFloat16, f16_val: (a shl 8) or b)
    of 26:
      var bits: uint32 = 0
      for i in 0 ..< 4: bits = (bits shl 8) or uint32(read_u8(buf, pos))
      cbor_float32(cast[float32](bits))
    of 27:
      var bits: uint64 = 0
      for i in 0 ..< 8: bits = (bits shl 8) or uint64(read_u8(buf, pos))
      cbor_float64(cast[float64](bits))
    else:
      CborValue(kind: ckSimple, simple_val: additional)
  else:
    raise newException(BinserError, "cbor: unknown major type: " & $major)
