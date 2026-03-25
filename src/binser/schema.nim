## schema.nim -- Schema-driven encode/decode for msgpack and cbor.

{.experimental: "strict_funcs".}

import std/[strutils, tables]
import basis/code/choice, msgpack

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  FieldType* = enum
    ftInt, ftUint, ftFloat, ftStr, ftBool, ftBin

  FieldDef* = object
    name*: string
    field_type*: FieldType

  Schema* = object
    name*: string
    fields*: seq[FieldDef]

# =====================================================================================================================
# Schema construction
# =====================================================================================================================

proc field*(name: string, ft: FieldType): FieldDef =
  FieldDef(name: name, field_type: ft)

proc schema*(name: string, fields: varargs[FieldDef]): Schema =
  Schema(name: name, fields: @fields)

# =====================================================================================================================
# MsgPack schema encode/decode
# =====================================================================================================================

proc encode_msgpack*(s: Schema, values: Table[string, string]
                    ): Choice[string] =
  ## Encode a record as a msgpack map using schema field ordering.
  var pairs: seq[(MsgPackValue, MsgPackValue)]
  for f in s.fields:
    let key = mp_str(f.name)
    if f.name notin values:
      pairs.add((key, mp_nil()))
      continue
    let raw = values[f.name]
    let val = case f.field_type
      of ftStr: mp_str(raw)
      of ftInt:
        try: mp_int(int64(strutils.parseInt(raw)))
        except ValueError:
          return bad[string]("binser", "invalid int: " & raw)
      of ftUint:
        try: mp_uint(uint64(strutils.parseInt(raw)))
        except ValueError:
          return bad[string]("binser", "invalid uint: " & raw)
      of ftFloat:
        try: mp_float64(strutils.parseFloat(raw))
        except ValueError:
          return bad[string]("binser", "invalid float: " & raw)
      of ftBool: mp_bool(raw == "true")
      of ftBin: mp_bin(raw)
    pairs.add((key, val))
  good(encode(mp_map(pairs)))
