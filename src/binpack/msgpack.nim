## msgpack.nim -- MessagePack encoder/decoder. Pure Nim.
##
## All types: nil, bool, int (pos/neg fixint, uint8-64, int8-64),
## float32/64, str (fixstr, str8-32), bin (bin8-32), array (fixarray, array16/32),
## map (fixmap, map16/32), ext.

{.experimental: "strict_funcs".}

import basis/code/choice
import cbor

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  MsgPackKind* {.pure.} = enum
    Nil, Bool, Int, Uint, Float32, Float64,
    Str, Bin, Array, Map, Ext

  MsgPackValue* = ref object
    case kind*: MsgPackKind
    of MsgPackKind.Nil: discard
    of MsgPackKind.Bool: bool_val*: bool
    of MsgPackKind.Int: int_val*: int64
    of MsgPackKind.Uint: uint_val*: uint64
    of MsgPackKind.Float32: f32_val*: float32
    of MsgPackKind.Float64: f64_val*: float64
    of MsgPackKind.Str: str_val*: string
    of MsgPackKind.Bin: bin_val*: string
    of MsgPackKind.Array: arr_val*: seq[MsgPackValue]
    of MsgPackKind.Map: map_val*: seq[(MsgPackValue, MsgPackValue)]
    of MsgPackKind.Ext:
      ext_type*: int8
      ext_data*: string

# =====================================================================================================================
# Constructors
# =====================================================================================================================

proc mp_nil*(): MsgPackValue = MsgPackValue(kind: MsgPackKind.Nil)
proc mp_bool*(v: bool): MsgPackValue = MsgPackValue(kind: MsgPackKind.Bool, bool_val: v)
proc mp_int*(v: int64): MsgPackValue = MsgPackValue(kind: MsgPackKind.Int, int_val: v)
proc mp_uint*(v: uint64): MsgPackValue = MsgPackValue(kind: MsgPackKind.Uint, uint_val: v)
proc mp_float32*(v: float32): MsgPackValue = MsgPackValue(kind: MsgPackKind.Float32, f32_val: v)
proc mp_float64*(v: float64): MsgPackValue = MsgPackValue(kind: MsgPackKind.Float64, f64_val: v)
proc mp_str*(v: string): MsgPackValue = MsgPackValue(kind: MsgPackKind.Str, str_val: v)
proc mp_bin*(v: string): MsgPackValue = MsgPackValue(kind: MsgPackKind.Bin, bin_val: v)
proc mp_array*(v: seq[MsgPackValue]): MsgPackValue = MsgPackValue(kind: MsgPackKind.Array, arr_val: v)
proc mp_map*(v: seq[(MsgPackValue, MsgPackValue)]): MsgPackValue = MsgPackValue(kind: MsgPackKind.Map, map_val: v)

# =====================================================================================================================
# Encode
# =====================================================================================================================

proc encode_uint16_be(v: uint16): string =
  result = newString(2)
  result[0] = char(v shr 8); result[1] = char(v and 0xFF)

proc encode_uint32_be(v: uint32): string =
  result = newString(4)
  result[0] = char((v shr 24) and 0xFF); result[1] = char((v shr 16) and 0xFF)
  result[2] = char((v shr 8) and 0xFF); result[3] = char(v and 0xFF)

proc encode*(v: MsgPackValue): string {.raises: [BinserError].}

proc encode*(v: MsgPackValue): string =
  case v.kind
  of MsgPackKind.Nil:
    result = "\xc0"
  of MsgPackKind.Bool:
    result = if v.bool_val: "\xc3" else: "\xc2"
  of MsgPackKind.Int:
    let i = v.int_val
    if i >= 0 and i <= 127:
      result = $char(i)
    elif i >= -32 and i < 0:
      result = $char(uint8(i) and 0xFF)
    elif i >= -128 and i <= 127:
      result = "\xd0" & $char(uint8(i) and 0xFF)
    elif i >= -32768 and i <= 32767:
      result = "\xd1" & encode_uint16_be(uint16(i) and 0xFFFF)
    elif i >= -2147483648'i64 and i <= 2147483647'i64:
      result = "\xd2" & encode_uint32_be(uint32(i) and 0xFFFFFFFF'u32)
    else:
      result = newString(9)
      result[0] = '\xd3'
      let u = cast[uint64](i)
      for j in 0 ..< 8:
        result[8 - j] = char((u shr (j * 8)) and 0xFF)
  of MsgPackKind.Uint:
    let u = v.uint_val
    if u <= 127:
      result = $char(u)
    elif u <= 255:
      result = "\xcc" & $char(u)
    elif u <= 65535:
      result = "\xcd" & encode_uint16_be(uint16(u))
    elif u <= 4294967295'u64:
      result = "\xce" & encode_uint32_be(uint32(u))
    else:
      result = newString(9)
      result[0] = '\xcf'
      for j in 0 ..< 8:
        result[8 - j] = char((u shr (j * 8)) and 0xFF)
  of MsgPackKind.Float32:
    result = newString(5)
    result[0] = '\xca'
    let bits = cast[uint32](v.f32_val)
    result[1] = char((bits shr 24) and 0xFF); result[2] = char((bits shr 16) and 0xFF)
    result[3] = char((bits shr 8) and 0xFF); result[4] = char(bits and 0xFF)
  of MsgPackKind.Float64:
    result = newString(9)
    result[0] = '\xcb'
    let bits = cast[uint64](v.f64_val)
    for j in 0 ..< 8:
      result[8 - j] = char((bits shr (j * 8)) and 0xFF)
  of MsgPackKind.Str:
    let n = v.str_val.len
    if n <= 31:
      result = $char(0xa0'u8 or uint8(n)) & v.str_val
    elif n <= 255:
      result = "\xd9" & $char(n) & v.str_val
    elif n <= 65535:
      result = "\xda" & encode_uint16_be(uint16(n)) & v.str_val
    else:
      result = "\xdb" & encode_uint32_be(uint32(n)) & v.str_val
  of MsgPackKind.Bin:
    let n = v.bin_val.len
    if n <= 255:
      result = "\xc4" & $char(n) & v.bin_val
    elif n <= 65535:
      result = "\xc5" & encode_uint16_be(uint16(n)) & v.bin_val
    else:
      result = "\xc6" & encode_uint32_be(uint32(n)) & v.bin_val
  of MsgPackKind.Array:
    let n = v.arr_val.len
    if n <= 15:
      result = $char(0x90'u8 or uint8(n))
    elif n <= 65535:
      result = "\xdc" & encode_uint16_be(uint16(n))
    else:
      result = "\xdd" & encode_uint32_be(uint32(n))
    for item in v.arr_val:
      result.add(encode(item))
  of MsgPackKind.Map:
    let n = v.map_val.len
    if n <= 15:
      result = $char(0x80'u8 or uint8(n))
    elif n <= 65535:
      result = "\xde" & encode_uint16_be(uint16(n))
    else:
      result = "\xdf" & encode_uint32_be(uint32(n))
    for (k, val) in v.map_val:
      result.add(encode(k))
      result.add(encode(val))
  of MsgPackKind.Ext:
    raise newException(BinserError, "ext encoding not implemented")

# =====================================================================================================================
# Decode
# =====================================================================================================================

proc read_u8(buf: string, pos: var int): uint8 {.raises: [BinserError].} =
  if pos >= buf.len: raise newException(BinserError, "msgpack: unexpected end")
  result = uint8(buf[pos]); inc pos

proc read_u16(buf: string, pos: var int): uint16 {.raises: [BinserError].} =
  if pos + 2 > buf.len: raise newException(BinserError, "msgpack: unexpected end")
  result = uint16(uint8(buf[pos])) shl 8 or uint16(uint8(buf[pos+1])); pos += 2

proc read_u32(buf: string, pos: var int): uint32 {.raises: [BinserError].} =
  if pos + 4 > buf.len: raise newException(BinserError, "msgpack: unexpected end")
  result = uint32(uint8(buf[pos])) shl 24 or uint32(uint8(buf[pos+1])) shl 16 or
           uint32(uint8(buf[pos+2])) shl 8 or uint32(uint8(buf[pos+3])); pos += 4

proc read_u64(buf: string, pos: var int): uint64 {.raises: [BinserError].} =
  if pos + 8 > buf.len: raise newException(BinserError, "msgpack: unexpected end")
  for i in 0 ..< 8:
    result = (result shl 8) or uint64(uint8(buf[pos + i]))
  pos += 8

proc read_bytes(buf: string, pos: var int, n: int): string {.raises: [BinserError].} =
  if pos + n > buf.len: raise newException(BinserError, "msgpack: unexpected end")
  result = buf[pos ..< pos + n]; pos += n

proc decode*(buf: string, pos: var int): MsgPackValue {.raises: [BinserError].}

proc decode*(buf: string, pos: var int): MsgPackValue =
  let b = read_u8(buf, pos)
  if b <= 0x7f:               # positive fixint
    return mp_int(int64(b))
  if (b and 0xe0) == 0xe0:    # negative fixint
    return mp_int(int64(cast[int8](b)))
  if (b and 0xf0) == 0x80:    # fixmap
    let n = int(b and 0x0f)
    var pairs: seq[(MsgPackValue, MsgPackValue)]
    for i in 0 ..< n:
      let k = decode(buf, pos); let v = decode(buf, pos)
      pairs.add((k, v))
    return mp_map(pairs)
  if (b and 0xf0) == 0x90:    # fixarray
    let n = int(b and 0x0f)
    var arr: seq[MsgPackValue]
    for i in 0 ..< n: arr.add(decode(buf, pos))
    return mp_array(arr)
  if (b and 0xe0) == 0xa0:    # fixstr
    let n = int(b and 0x1f)
    return mp_str(read_bytes(buf, pos, n))
  case b
  of 0xc0: mp_nil()
  of 0xc2: mp_bool(false)
  of 0xc3: mp_bool(true)
  of 0xc4:
    let n = int(read_u8(buf, pos))
    mp_bin(read_bytes(buf, pos, n))
  of 0xc5:
    let n = int(read_u16(buf, pos))
    mp_bin(read_bytes(buf, pos, n))
  of 0xc6:
    let n = int(read_u32(buf, pos))
    mp_bin(read_bytes(buf, pos, n))
  of 0xca:
    let bits = read_u32(buf, pos)
    mp_float32(cast[float32](bits))
  of 0xcb:
    let bits = read_u64(buf, pos)
    mp_float64(cast[float64](bits))
  of 0xcc: mp_uint(uint64(read_u8(buf, pos)))
  of 0xcd: mp_uint(uint64(read_u16(buf, pos)))
  of 0xce: mp_uint(uint64(read_u32(buf, pos)))
  of 0xcf: mp_uint(read_u64(buf, pos))
  of 0xd0: mp_int(int64(cast[int8](read_u8(buf, pos))))
  of 0xd1: mp_int(int64(cast[int16](read_u16(buf, pos))))
  of 0xd2: mp_int(int64(cast[int32](read_u32(buf, pos))))
  of 0xd3: mp_int(cast[int64](read_u64(buf, pos)))
  of 0xd9:
    let n = int(read_u8(buf, pos))
    mp_str(read_bytes(buf, pos, n))
  of 0xda:
    let n = int(read_u16(buf, pos))
    mp_str(read_bytes(buf, pos, n))
  of 0xdb:
    let n = int(read_u32(buf, pos))
    mp_str(read_bytes(buf, pos, n))
  of 0xdc:
    let n = int(read_u16(buf, pos))
    var arr: seq[MsgPackValue]
    for i in 0 ..< n: arr.add(decode(buf, pos))
    mp_array(arr)
  of 0xdd:
    let n = int(read_u32(buf, pos))
    var arr: seq[MsgPackValue]
    for i in 0 ..< n: arr.add(decode(buf, pos))
    mp_array(arr)
  of 0xde:
    let n = int(read_u16(buf, pos))
    var pairs: seq[(MsgPackValue, MsgPackValue)]
    for i in 0 ..< n:
      let k = decode(buf, pos); let v = decode(buf, pos)
      pairs.add((k, v))
    mp_map(pairs)
  of 0xdf:
    let n = int(read_u32(buf, pos))
    var pairs: seq[(MsgPackValue, MsgPackValue)]
    for i in 0 ..< n:
      let k = decode(buf, pos); let v = decode(buf, pos)
      pairs.add((k, v))
    mp_map(pairs)
  else:
    let digits = "0123456789abcdef"
    raise newException(BinserError, "msgpack: unknown type byte: 0x" & digits[int(b shr 4)] & digits[int(b and 0xf)])
