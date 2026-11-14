# roc-cbor

CBOR (RFC 8949) for Roc, as a format of the Roc codec protocol.

You give a Roc type. The compiler derives the reader and the writer. You do not write a codec.
`Cbor` is for CBOR what the builtin `Json` is for JSON.

Features:

- **Typed read and write.** Records, tag unions, lists, `Dict`, `Str`, integers up to 128 bits, floats and `Dec`, derived from the Roc type alone.
- **A strict reader.** One walk checks each byte before the typed parse: well-formed items, valid UTF-8, shortest heads, no duplicate keys, exact numbers, a depth limit. An error gives its byte position.
- **Opt-in leniency.** Each lenient read is one entry of `allow`, such as `Cbor.sql_rows` for the rows of SQLite or Cloudflare D1, or `IndefiniteLength`.
- **A safe writer.** The output is always well-formed, in preferred serialization, and deterministic with `key_order: Sorted` (for bytes to hash or sign).
- **Tag unions** in the external form of `Json`, and on read also with an internal tag key (`unions: Internal`).
- **Dynamic and exact data.** `Cbor.Value` for any item, `Cbor.Raw` for the exact bytes of a signed item (COSE, WebAuthn), CBOR tags with your own `parser_for` and `encoder_for`, `parse_prefix`, and CBOR sequences (RFC 8742).
- **Streams.** Read and write data larger than memory: the items of an array or a sequence, the entries of a map, the chunks of a byte string or a text. A pure `push` core, and `from_stream` for the builtin `Stream` of a platform. A 5 GB byte string reads in about 1 MB of memory.
- **No dependencies.**
- **Tested.**
  - About 1,200 expects, including the vectors of RFC 8949 Appendix A.
  - Fuzz property tests: round trips, no crash on any bytes, the same stream result for each split into chunks, and agreement with a slow reference model.
  - A differential test against Python `cbor2`.
  - Complexity and memory checks for each reader, writer and stream.
  - A regression test for each fix, checked against the code with the fix removed.

  (Section "Tests".)

| Item | Value |
| --- | --- |
| Version | 0.6.1 (section "Changes"; 0.6.0 has a migration table from 0.5) |
| Module | `Cbor` (public), with nested types such as `Cbor.Value`, `Cbor.Raw`, `Cbor.Bytes`, `Cbor.Reader`, `Cbor.Writer`, and the stream types `Cbor.Items`, `Cbor.Entries`, `Cbor.ByteChunks`, `Cbor.TextChunks` and `Cbor.StreamWriter` |
| Dependencies | none |
| Compiler | the Zig compiler (nightlies of 2026-11-08 or later: the codec contract with format-owned errors). CI uses the nightly in `.roc-version` (`nightly-2026-11-13-03dce41`). The tests also pass on `nightly-2026-11-11-7679cc5`. |
| Reader | Strict by default. Each lenient read is a `Cbor.Leniency` in the option `allow`. |
| Writer | Always well-formed, preferred serialization (shortest heads and floats). Deterministic with `key_order: Sorted`. |
| Streams | Read and write data larger than memory, one item, entry or chunk at a time (section "Streams") |
| Tests | `scripts/all_tests.sh`, fuzz, scale, differential and bench scripts (section "Tests") |
| License | UPL-1.0 (`LICENSE`) |

## Use

Add the package to the header with its release URL. The release notes of each
[release](https://github.com/Karakatiza666/roc-cbor/releases) give the URL. The latest release is 0.5.0.

```roc
app [main!] { pf: platform "...", cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst" }

import cbor.Cbor
```

```roc
Pkg : { name : Str, size : U64, tags : List(Str) }

bytes = Cbor.encode({ name: "x", size: 3, tags: ["a"] })

parsed : Try(Pkg, _)
parsed = Cbor.parse(bytes)
```

`Cbor.parse` takes its type from the context. Write the type in an annotation.
`parse` gives `Err(InvalidCbor(pos))` when the bytes are not valid, not in the profile, or do not fit the type. `pos` is the byte position of the problem.
It gives `Err(MissingRequiredField(name))` when a record field is absent. `name` is the Roc name of the field.
A type that you define (`:=` or `::`) must opt in with `parser_for : _` and `encoder_for : _` (Roc langref, "Parsers").

### Read and write

| Item | Type | Use |
| --- | --- | --- |
| `Cbor.parse` | `List(U8) -> Try(a, Cbor.Error)` | Read one item from all of the bytes, strict. The same as `parse_with(bytes, {})`. |
| `Cbor.parse_with` | `List(U8), Cbor.Options -> Try(a, Cbor.Error)` | Read with options (section "Options") |
| `Cbor.parse_prefix` | `List(U8) -> Try({ value : a, rest : List(U8) }, Cbor.Error)` | Read one item at the start of the bytes. `rest` is the bytes after it (a slice, no copy). For WebAuthn authenticator data. |
| `Cbor.parse_prefix_with` | `List(U8), Cbor.Options -> Try({ value : a, rest : List(U8) }, Cbor.Error)` | The same, with options |
| `Cbor.parse_sequence` | `List(U8) -> Try(List(a), Cbor.Error)` | Read a CBOR sequence (RFC 8742): zero or more items. Empty bytes give `[]`. |
| `Cbor.parse_sequence_with` | `List(U8), Cbor.Options -> Try(List(a), Cbor.Error)` | The same, with options. `max_items` counts for each item. |
| `Cbor.encode` | `a -> List(U8)` | Write one item. A derived encoder cannot fail. An `encoder_for` of your own with a wrong item count crashes here. |
| `Cbor.encode_try` | `a -> Try(List(U8), [CountMismatch, ..err])` | Write one item. `Err(CountMismatch)` when an `encoder_for` of your own writes a wrong item count. |
| `Cbor.encode_with` | `a, Cbor.WriteOptions -> Try(List(U8), [CountMismatch, DuplicateMapKey, ..err])` | Write with options (section "Write options") |
| `Cbor.Options` | `{ fields ?: [Snake, Camel], allow ?: List(Cbor.Leniency), duplicate_keys ?: [Reject, First, Last], key_order ?: [Any, Sorted], unknown_fields ?: [Skip, Reject], max_depth ?: U64, max_items ?: U64, ignore_tags ?: List(U64), unions ?: Cbor.Unions, max_buffer ?: U64 }` | The options of the readers and of the stream decoders |
| `Cbor.Leniency` | `[BoolFromInt, FloatToInt, IntFromText, DecFromText, NullAsAbsent, UndefinedAsNull, PaddedNumbers, BytesFromArray, BytesFromBase64, IndefiniteLength]` | One lenient read, for the option `allow` |
| `Cbor.sql_rows` | `List(Cbor.Leniency)` | `[BoolFromInt, FloatToInt, NullAsAbsent, UndefinedAsNull, BytesFromArray]`: rows of a SQL database (section "SQL rows") |
| `Cbor.WriteOptions` | `{ fields ?: [Snake, Camel], key_order ?: [Given, Sorted] }` | The options of `encode_with` |
| `Cbor.Unions` | `[External, Internal({ tag : Str, content : Str })]` | The layout of a tag union on read (section "Tag unions") |
| `Cbor.path_at` | `List(U8), U64 -> Try(List(Cbor.Step), [NotFound])` | The path to the item that starts at a position, for example the position of `InvalidCbor(pos)` |
| `Cbor.Step` | `[Index(U64), Key(Str)]` | One step of a path: an array index or a map key |

The tables leave out the `where` clauses: an `a` that is read has `where [a.Parseable(Cbor.Error)]`, and an `a` that is written has `where [a.Encodable(err)]` with the error row of the function (section "`where` aliases").

### Types

| Item | Type | Use |
| --- | --- | --- |
| `Cbor.Bytes` | `Cbor.Bytes := List(U8)` | Binary data as a byte string. The fast type: one append on write, a slice of the input on read. `Cbor.Bytes.from_list(list)`, `bytes.to_list()`. |
| `Cbor.U8Array` | `Cbor.U8Array := List(U8)` | Bytes as an array of integers 0 to 255, for a peer that needs that form. Reads an array only. `Cbor.U8Array.(list)`, `array.to_list()`. |
| `Cbor.Raw` | `Cbor.Raw :: List(U8)` | One item kept as its exact bytes, to check a signature (COSE, WebAuthn) or to pass it on. `Cbor.Raw.from_bytes(bytes)` (strict), `raw.to_bytes()`. |
| `Cbor.Value` | `Cbor.Value := [Int(Cbor.IntValue), Float(F64), Bytes(List(U8)), Text(Str), Array(List(Cbor.Value)), Map(Cbor.ValueMap), Tag(U64, Cbor.Value), Bool(Bool), Null, Undefined, Simple(Cbor.SimpleValue)]` | Any item, with its tags (section "Dynamic values") |
| `Cbor.IntValue` | `Cbor.IntValue :: I128` | -2^64 to 2^64 - 1. A literal works (`Int(5)`). `from_i128` (`Err(OutOfRange)`), `from_i64`, `from_u64`, `to_i128`. |
| `Cbor.SimpleValue` | `Cbor.SimpleValue :: U8` | 0 to 19 or 32 to 255. A literal works (`Simple(16)`). `from_u8` (`Err(InvalidSimple)`), `to_u8`. |
| `Cbor.ValueMap` | `Cbor.ValueMap :: List((Cbor.Value, Cbor.Value))` | The entries of a map, in order, no duplicate key. `from_list` (`Err(DuplicateKey(key))`), `empty`, `insert`, `get`, `len`, `to_list`. |

### Building blocks for a `parser_for` or an `encoder_for` of your own

| Item | Type | Use |
| --- | --- | --- |
| `Cbor.Reader` | opaque | The checked token reader of a parse: bytes, position, checks. A `parser_for` gets it and gives back the reader after its item. |
| `Cbor.Writer` | opaque | The output of an encode. Each item goes through an `encode_*` function, which counts it. |
| `Cbor.Container` | opaque | The writer inside a list, a tuple, a record or a tag. Only the `add` callback writes to it, one item for each call. |
| `Cbor.parse_item` | `Cbor, Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, Cbor.Error)` | Read one item of the type `a` |
| `Cbor.encode_item` | `a, Cbor.Writer -> Try(Cbor.Writer, err)` | Write one item of the type `a` |
| `Cbor.parse_cbor_tag` | `Cbor, Cbor.Reader -> Try({ value : U64, rest : Cbor.Reader }, Cbor.Error)` | Read the head of a tag. `value` is the tag number, `rest` is at the tagged item. |
| `Cbor.encode_tagged` | `U64, a, Cbor.Writer -> Try(Cbor.Writer, err)` | Write a tag and its one tagged item |
| `Cbor.peek` | `Cbor, Cbor.Reader -> Try(Cbor.Kind, Cbor.Error)` | The kind of the next item, with no read |
| `Cbor.Kind` | `[Int, Bytes, Text, Array, Map, Tag(U64), Bool, Null, Undefined, Simple(U8), Float]` | The result of `peek` |
| `Cbor.parse_union` | `Cbor, Cbor.UnionOptions, Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, Cbor.Error)` | Read one tag union with its own layout and tag name case |
| `Cbor.UnionOptions` | `{ unions ?: Cbor.Unions, tags ?: [Exact, Upper, Lower] }` | The options of `parse_union` |
| `Cbor.parse_bytes` | `Cbor, Cbor.Reader -> Try({ value : List(U8), rest : Cbor.Reader }, Cbor.Error)` | Read a byte string (major type 2) only |
| `Cbor.encode_bytes` | `List(U8), Cbor.Writer -> Try(Cbor.Writer, err)` | Write a byte string in one append |
| `Cbor.invalid_value` | `Cbor, Cbor.Reader -> Cbor.Error` | The error of your own reader at a position: `Err(Cbor.invalid_value(encoding, state))` |
| `Cbor.encode_list` | `Cbor.Writer, U64, (Cbor.Container, (Cbor.Container, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Writer, err)` | Write an array of a declared count. Each call of `add` writes exactly one item. `encode_tuple` is the same. `encode_tag` also takes the tag name after the writer. `encode_record` gives `add` a field name too, and `encode_dict` a key writer and a value writer. |
| `Cbor.parse_str`, `Cbor.encode_str` and the like (`parse_u64`, `encode_f64`, ...) | `Cbor, Cbor.Reader -> Try({ value : Str, rest : Cbor.Reader }, Cbor.Error)`, `Str, Cbor.Writer -> Try(Cbor.Writer, err)` | The codec protocol. The derived `parser_for` and `encoder_for` call them. Your own code can call them too. |

### `where` aliases

| Alias | Is the same as | Use |
| --- | --- | --- |
| `a.Cbor.Parseable(err)` | `a.parser_for : Cbor -> (Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, err))` | A function that calls `Cbor.parse` with a type variable: `where [a.Cbor.Parseable(Cbor.Error)]` |
| `a.Cbor.Encodable(err)` | `a.encoder_for : Cbor -> (a, Cbor.Writer -> Try(Cbor.Writer, err))` | A function that calls `Cbor.encode` with a type variable: `where [a.Cbor.Encodable([])]` |
| `a.Cbor.Readable` | `a.Cbor.Parseable(Cbor.Error)` | The short form. The function can `match` on both errors. |
| `a.Cbor.Writable` | `a.Cbor.Encodable([])` | The short form |

`Cbor.Error` is `[InvalidCbor(U64), MissingRequiredField(Str)]`: the one error of every read. The codec protocol of the compiler requires each operation of a derived parser to have the format's error, so a custom `parser_for` gives `Cbor.Error` too (it can give only `InvalidCbor`).

```roc
read : List(U8) -> Try(a, Str) where [a.Cbor.Readable]
read = |bytes|
	match Cbor.parse(bytes) {
		Ok(v) => Ok(v)
		Err(MissingRequiredField(field)) => Err("missing ${field}")
		Err(InvalidCbor(pos)) => Err("invalid at ${pos.to_str()}")
	}
```

`examples/round_trip.roc` uses each public item, except the stream types: `examples/stream.roc` uses those. `tests/aliases.roc` has generic helpers with `Readable` and `Writable`.

### Options

Each field of `Cbor.Options` is optional: `{}` is the same as `parse`.
A record in a `let` that is not the full record needs the annotation `opts : Cbor.Options`. A record literal in the call does not.

| Field | Default | Value |
| --- | --- | --- |
| `fields` | `Snake` | `Snake`: the field `user_id` reads the key `user_id`. `Camel`: it reads the key `userId`. A key of two fields (`a_1` and `a1`) is an error at the key. |
| `allow` | `[]` | The lenient reads (table "Leniencies"). `[]` is strict. |
| `duplicate_keys` | `Reject` | A key that is two times in one map. `Reject`: an error at the second key. `First`, `Last`: that instance is read, the others are skipped. One rule for each map: record, `Dict`, internal tag, `Cbor.Value`, skipped item. |
| `key_order` | `Any` | `Any`: the keys of a map can be in any order. `Sorted`: the keys of each map must be in the order of RFC 8949 4.2.1, the order that `encode_with(value, { key_order: Sorted })` writes. A key before the key in front of it is an error at the key. Equal keys are next to each other, and `duplicate_keys` applies to them. The check is O(1) for each key: only the key before is kept. |
| `unknown_fields` | `Skip` | A key of a map read as a record that is not a field. `Skip`: the entry is skipped (and checked). `Reject`: an error at the key. |
| `max_depth` | 512 | The most nested arrays, maps and tags. Empty ones count. More is an error at the head that goes too deep. |
| `max_items` | no limit | The most data items in the root item. Each key, value, array item, tag and tagged item counts. More is an error at the first item over the limit. |
| `ignore_tags` | `[]` | The tag numbers that the readers of the types skip before an item. With `[6]`, `c6 f6` reads as `null`. A map key does not skip tags. `peek`, `parse_cbor_tag`, `Cbor.Value` and `Cbor.Raw` see each tag. |
| `unions` | `External` | The layout of each tag union of the parse (section "Tag unions") |
| `max_buffer` | 16,777,216 (16 MiB) | Streams only (`Cbor.Items`, `Cbor.Entries`): the most bytes that a decoder keeps for one item, with the keys of a streamed map (section "Streams"). More is `Err(TooLarge(pos))`. `parse_with`, `parse_prefix`, `parse_sequence`, `ByteChunks` and `TextChunks` ignore it. |

#### Leniencies

| Tag | Strict (default) | With the tag |
| --- | --- | --- |
| `BoolFromInt` | A `Bool` reads only `false` and `true` | Also the integers 0 and 1. Another integer is an error. A float 0.0 or 1.0 needs `FloatToInt` too. |
| `FloatToInt` | An integer type reads only major types 0 and 1 | Also a float with no fraction of size 2^53 - 1 or less (a JS Number). A larger float is an error: it can be the rounded value of many integers. |
| `IntFromText` | Text is an error for an integer type | An integer type also reads canonical decimal text in its range: `0`, or `-?[1-9][0-9]*`. `-0`, `01`, `+1`, `1.0` and spaces are errors. |
| `DecFromText` | Text is an error for a `Dec` | A `Dec` also reads the number form of JSON, `-?(0\|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, exactly: `"4E+1"` is 40. More than 18 fraction digits, or out of range, is an error. |
| `NullAsAbsent` | A `null` value in a map read as a record goes to the reader of the field | The entry is skipped: the same as no key. The keys are counted first: `{a: null, a: 5}` is still a duplicate. |
| `UndefinedAsNull` | `undefined` is an error, except for `Cbor.Value` | `undefined` reads as `null`, also for `NullAsAbsent` |
| `PaddedNumbers` | A number that uses more bytes than it needs is an error, also in a skipped item: an integer, the length of a text or byte string, the count of an array or map, a tag number (RFC 8949 4.2.1). A bignum with a leading zero byte, or with a value that fits 64 bits, is an error (RFC 8949 4.2.2, preferred serialization). | These numbers also read. roc-cbor 0.4 and some other encoders write them. Float widths are not changed by this leniency: each float width reads in all modes. |
| `BytesFromArray` | A `List(U8)` and `Cbor.Bytes` read a byte string or an empty array | Also an array of integers 0 to 255 (for example a D1 BLOB). An array with another item (`[1, null]` for a `List(Try(U8, [Null]))`) reads with no tag. |
| `BytesFromBase64` | A `List(U8)` and `Cbor.Bytes` do not read text | Also text that is base64 (RFC 4648 4) with `=` padding. White space, base64url (`-` `_`), missing padding, and unused bits that are not zero are errors. `Str` and `Cbor.Value` do not change. |
| `IndefiniteLength` | An indefinite length is an error, also in a skipped item | Arrays, maps, byte strings and text of indefinite length read, each with its break. The chunks are joined. Each chunk of text is valid UTF-8. |

`Cbor.Value` reads each item as it is: `allow` does not change it, except `PaddedNumbers` and `IndefiniteLength`. `duplicate_keys` applies to it.
A leniency does not apply to a `Dict` key: a key reads only in the form that the writer writes, so two different keys never give one Roc key.

```roc
Row : { name : Str, id : I64 }

# [{"name": "a", "id": 1.5}]
bytes = [0x81, 0xa2, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61, 0x62, 0x69, 0x64, 0xf9, 0x3e, 0x00]

rows : Try(List(Row), _)
rows = Cbor.parse_with(bytes, { allow: [FloatToInt, IntFromText] })

# 1.5 has a fraction: the error is at the value of "id" (position 12)
expect rows == Err(InvalidCbor(12))
expect Cbor.path_at(bytes, 12) == Ok([Index(0), Key("id")])
```

`path_at` gives `Err(NotFound)` when no item starts at the position (a map key, or a position in the middle of an item), when the path goes through a map key that is not text, or when the bytes are not one well-formed item.
It checks only well-formedness (any head width, indefinite lengths, duplicate keys, any depth), so it finds the position of an error of each `parse_with`. The path of the root item is `[]`.

### Write options

Each field of `Cbor.WriteOptions` is optional: `{}` is the same as `encode_try`.

| Field | Default | Value |
| --- | --- | --- |
| `fields` | `Snake` | `Snake`: the field `user_id` writes the key `user_id`. `Camel`: it writes the key `userId`. Two fields with one camelCase key (`a_1` and `a1`) give `Err(DuplicateMapKey)`. |
| `key_order` | `Given` | `Given`: the order of the encoder (a record: the order of its fields, a `Dict`: its order). `Sorted`: the deterministic encoding of RFC 8949 4.2.1. |

| `key_order: Sorted` | Detail |
| --- | --- |
| Order | The entries of each map are sorted by the bytes of their keys, bytewise: `"b"` (`61 62`) before `"aa"` (`62 61 61`), `24` (`18 18`) before `-1` (`20`) |
| Scope | Each map: a record, a `Dict`, a `Cbor.Value` map, a map of your own `encoder_for`, a map inside a `Cbor.Raw` (so its bytes change) |
| Duplicates | Two entries with the same key bytes in one map: `Err(DuplicateMapKey)`. With `Given`, a map of your own `encoder_for` is not checked. |
| Cost | O(k log k) for a map of k entries |
| Effect | Two equal values write the same bytes. With the shortest heads and floats that each encode writes, this is the core deterministic encoding. |
| Read back | A `Cbor.Value` map keeps the order of its entries, and is equal only to a map with the same order. So it reads back with its entries in the sorted order: not equal to the value written when its entries were in another order, but it writes the same sorted bytes. |

```roc
user = { user_id: 7.U64, display_name: "Ann" }

camel = Cbor.encode_with(user, { fields: Camel, key_order: Sorted })

# {"userId": 7, "displayName": "Ann"}: "userId" (66 ..) is before "displayName" (6b ..)
expect camel.map_ok(|b| b.take_first(8)) == Ok([0xa2, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64])
```

### SQL rows

A SQL database (SQLite, Cloudflare D1, and many others) has no boolean type, and a nullable column gives NULL.
A peer that sends a row as a CBOR map gives the integers 0 and 1 for a boolean column, `null` for a NULL, and sometimes an array for a BLOB.
`allow: Cbor.sql_rows` reads such a row into a natural Roc record:

```roc
Row : { name : Str, note ?: Str, active : Bool }

# {"name": "a", "note": null, "active": 1}
bytes = [0xa3, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61, 0x64, 0x6e, 0x6f, 0x74, 0x65, 0xf6, 0x66, 0x61, 0x63, 0x74, 0x69, 0x76, 0x65, 0x01]

row : Try(Row, _)
row = Cbor.parse_with(bytes, { allow: Cbor.sql_rows })

# note is absent, active is true. The strict reader gives an error at the null (position 13).
strict : Try(Row, _)
strict = Cbor.parse(bytes)

expect row.map_ok(|r| (r.?note.is_ok(), r.active)) == Ok((Bool.False, Bool.True))
expect strict == Err(InvalidCbor(13))
```

| Field or item | Strict | With `Cbor.sql_rows` | Write |
| --- | --- | --- | --- |
| `Bool` | `false`, `true` | Also 0 and 1, and the floats 0.0 and 1.0. Another integer is an error. Text is an error. | `false`, `true` |
| Optional field (`x ?: a`) | No key: absent. `null`: an error at the `null`. | No key or `null`: absent | Absent: no key |
| `Try(a, [Missing])` field | No key: `Err(Missing)`. `null`: an error. | No key or `null`: `Err(Missing)` | `Err(Missing)`: no key |
| `Try(a, [Null])` field | `null`: `Err(Null)`. No key: `MissingRequiredField`. | No key or `null`: `MissingRequiredField` | `Err(Null)`: `null` |
| `Cbor.Value` field | `null`: `Null` | No key or `null`: `MissingRequiredField` | `Null`: `null` |
| Required field of another type | No key: `MissingRequiredField`. `null`: an error at the `null`. | No key or `null`: `MissingRequiredField` | |
| `null` outside a map read as a record (list item, tuple item, root, `Dict` value, tag payload) | `Err(Null)` of a `Try(a, [Null])`, `Null` of a `Cbor.Value`, else an error | The same | `null` |
| `undefined` | An error, except `Cbor.Value` | The same as `null` | |
| `List(U8)`, `Cbor.Bytes` | Byte string or empty array | Also an array of integers 0 to 255 (D1 gives a BLOB back as an array) | Byte string |

The writer writes `Err(Null)` as `null` everywhere, so each value reads back with the strict reader.
`Cbor.sql_rows` reads as 0.4 did, except for duplicate keys and padded numbers. Data written by 0.4 also needs `PaddedNumbers`: `{ allow: Cbor.sql_rows.append(PaddedNumbers) }`.

### Dynamic values

| Need | Building block | Example |
| --- | --- | --- |
| A Roc type for one tag (a UUID, a time, a point, a link of a database) | A `parser_for` of your own with `Cbor.parse_cbor_tag`, then `Cbor.parse_item` for the tagged item. An `encoder_for` with `Cbor.encode_tagged`. | `Uuid` below, and `Instant`, `Point`, `Link` in `tests/tags.roc` |
| A value that can be one of several kinds | `Cbor.peek`, then the reader of that kind | `Cell` in `tests/tags.roc`, `Key` in `examples/round_trip.roc` |
| A value with no fixed type | `Cbor.Value` | `Link.key` in `tests/tags.roc` |
| The exact bytes of an item (to check a signature, to pass it on) | `Cbor.Raw` | `Signed` below |
| An item at the start of the bytes, then more data | `Cbor.parse_prefix` | WebAuthn authenticator data |
| Items one after the other with no array | `Cbor.parse_sequence` (RFC 8742) | A log of records |
| Data larger than memory, or items as their bytes come | The stream types (section "Streams") | A large upload, an export of a table |
| A tag before `null` that means "no value" | `ignore_tags: [n]` | `c6 f6` with `[6]` |
| A decimal number as text in a tag | `ignore_tags: [n]` and `allow: [DecFromText]` | `ca 64 34 45 2b 31` (tag 10, `"4E+1"`) with `[10]` is 40 |

The package gives no tag a meaning of its own, except the tags of RFC 8949 for a `Dec` (4, and 2 and 3 for its mantissa) and for a `U128` or an `I128` (2 and 3).
Tag numbers are in the [IANA registry](https://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml).

```roc
## A UUID (RFC 9562): the IANA tag 37 and a byte string of 16 bytes.
Uuid := List(U8).{
	is_eq : _

	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Uuid, rest : Cbor.Reader }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		bytes = Cbor.parse_bytes(encoding, tag.rest)?
		if tag.value == 37 and bytes.value.len() == 16 {
			Ok({ value: Uuid.(bytes.value), rest: bytes.rest })
		} else {
			Err(Cbor.invalid_value(encoding, state))
		}
	}

	encoder_for : Cbor -> (Uuid, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Uuid.(bytes), w| Cbor.encode_tagged(37, Cbor.Bytes.from_list(bytes), w)
}

## A point that a peer writes as an array of two numbers. The writer checks the count: 2.
Point := { x : F64, y : F64 }.{
	encoder_for : Cbor -> (Point, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Point.({ x, y }), w|
		Cbor.encode_list(w, 2, |c, add| add(add(c, |v| Cbor.encode_f64(x, v))?, |v| Cbor.encode_f64(y, v)))
}

## The signature is over the exact bytes of `body`, as the peer sent them.
Signed : { body : Cbor.Raw, sig : Cbor.Bytes }
```

`Cbor.Value`:

| Variant | CBOR | Note |
| --- | --- | --- |
| `Int(Cbor.IntValue)` | Major type 0 or 1 | -2^64 to 2^64 - 1. A bignum (tag 2 or 3) reads as `Tag(2, Bytes(_))` and writes back the same. |
| `Float(F64)` | f16, f32, f64 | Writes the shortest of f16, f32 and f64 with the same value. Each NaN writes `f9 7e00`. |
| `Bytes(List(U8))`, `Text(Str)` | Byte string, text | The reader checks UTF-8 |
| `Array(List(Cbor.Value))` | Array | |
| `Map(Cbor.ValueMap)` | Map | Any key type, no duplicate key. The entries keep their order. |
| `Tag(U64, Cbor.Value)` | A tag and its item | Each tag stays, also a tag of `ignore_tags` |
| `Bool(Bool)`, `Null`, `Undefined` | `f4`, `f5`, `f6`, `f7` | |
| `Simple(Cbor.SimpleValue)` | Another simple value: 0 to 19, 32 to 255 | 20 to 31 cannot be made |

| Rule | Value |
| --- | --- |
| Read back | Each value that the types let you make writes bytes that `Cbor.parse` reads back as an equal value, with 512 nested arrays, maps and tags or less |
| Equality and hash | Two values are equal when their bytes (`Cbor.encode`) are equal: `Float(0.0)` and `Float(-0.0)` are not equal, each NaN equals each NaN, `Int(1)` and `Float(1.0)` are not equal, two maps are equal only with the same entries in the same order. `is_eq` and `to_hash` are loops (500,000 levels: no stack overflow). |
| Map keys | Two keys are the same when they are the same `Cbor.Value`: f16 `1.0` and f64 `1.0` are one key. `ValueMap.from_list` and the reader compare the key bytes after a sort, never with a hash. |
| Cost | `ValueMap.from_list`: O(n log n). `get` and `insert`: linear, so n `insert` calls are O(n^2). |
| In a record | A `Cbor.Value` field reads `null` as `Null`. With `NullAsAbsent`, the key is absent. |

```roc
entries : Try(Cbor.ValueMap, [DuplicateKey(Cbor.Value)])
entries = Cbor.ValueMap.from_list([(Text("id"), Int(7)), (Int(-1), Bytes([0xab]))])

expect entries.map_ok(|m| Cbor.encode(Cbor.Value.Map(m))) == Ok([0xa2, 0x62, 0x69, 0x64, 0x07, 0x20, 0x41, 0xab])
expect Cbor.ValueMap.from_list([(Text("a"), Null), (Text("a"), Int(1))]) == Err(DuplicateKey(Text("a")))

# An item at the start of the bytes, and the bytes after it.
key : Try({ value : Cbor.Value, rest : List(U8) }, _)
key = Cbor.parse_prefix([0xa1, 0x01, 0x02, 0xff, 0xfe])

expect key.map_ok(|k| k.rest) == Ok([0xff, 0xfe])
```

| `Cbor.Raw` | Effect |
| --- | --- |
| `Cbor.Raw.from_bytes(bytes)` | A `Raw` when `bytes` are exactly one item that `Cbor.parse` reads, else `Err(InvalidCbor(pos))` |
| `Cbor.parse_with(bytes, options)` as a `Cbor.Raw` | The same with options. A lenient option keeps bytes that the strict reader rejects (a long head, a duplicate key). |
| As a record field or a list item | The bytes of that item, with the checks of the parse. `ignore_tags` does not apply: the bytes keep each tag. |
| `raw.to_bytes()`, `Cbor.parse(raw.to_bytes())` | The bytes, and the item as a type |
| Write | The bytes as they are, as one item. With `key_order: Sorted`, its maps are sorted. |

### Tag unions

The writer and the default reader use the external form of `Json`: `{ "Card": { "last4": "4242" } }`.
Many peers write a tag union with an internal tag: the tag name is the value of a key of the map, `{ "kind": "Card", "last4": "4242" }`.
The option `unions` reads this form. It is read only.

```roc
Pay : [Cash, Card({ last4 : Str }), Check(U64), Wire(Str, U64)]

Row : { id : Str, pay : Pay }

rows : List(U8) -> Try(List(Row), _)
rows = |bytes| Cbor.parse_with(bytes, { unions: Internal({ tag: "kind", content: "value" }) })
```

| Payloads | `External` (default) | `Internal({ tag: "kind", content: "value" })` |
| --- | --- | --- |
| 0 | `"Cash"` | `"Cash"`, or `{ "kind": "Cash" }` |
| 1, a record | `{ "Card": { "last4": "4242" } }` | `{ "kind": "Card", "last4": "4242" }`: the map itself |
| 1, another type | `{ "Check": 7 }` | `{ "kind": "Check", "value": 7 }`: the item at the content key |
| 2 or more | `{ "Wire": ["eu", 9] }` | `{ "kind": "Wire", "value": ["eu", 9] }`: an array at the content key |

| Rule | Value |
| --- | --- |
| U1. The type of the payload decides | The same bytes `{ "kind": "Check", "value": 7 }` read as `Check({ value: 7 })` and as `Check(7)`. A record (also a type of your own with a derived record reader) reads the map itself. Each other type reads the item at the content key: a `Dict`, a list, a tuple, a union, `Cbor.Value`, `Cbor.Raw`, and a type of your own that starts with `Cbor.peek` or `Cbor.parse_cbor_tag`. |
| U2. One layout for each parse | `Internal` does not read the external form `{ "Card": .. }` of a tag with payloads |
| U3. Keys | The keys can be in any order. Other keys are skipped (with `unknown_fields: Reject` in a record payload, an error). A tag key or content key that is two times follows `duplicate_keys`: the tag and the record fields come from the same instance. |
| U4. A record payload and the tag key | The tag key is not an unknown field of the record. A field with the name of the tag key reads the tag name: do not use that name for a field. |
| U5. Errors | No tag key, a key that is not text (before or after the tag key), or a tag name that the type does not have: an error at the map. A tag value that is not text: an error at the value. No content key for one payload that is not a record: an error at the map. Content of 2 or more payloads that is not an array of that length: an error at the content. |
| U6. The other options | `fields`, `allow`, `duplicate_keys` and `ignore_tags` apply in the payloads too |
| U7. Nested unions | Each union of the parse has the layout. One scan of each map: deep nesting is linear. |

`Cbor.parse_union` reads one tag union with the options of `Cbor.UnionOptions`, in the `parser_for` of a type of your own.
The payloads of the union, and the other unions of the parse, keep the options of the parse. An omitted `unions` keeps the layout of the parse. An omitted `tags` is `Exact`.

```roc
## The actions of a peer: "CREATE", "UPDATE", "NOT_FOUND".
Action := [Create, Update, NotFound].{
	is_eq : _

	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Action, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { tags: Upper }, state)?
		Ok({ value: Action.(parsed.value), rest: parsed.rest })
	}
}

## The operations of a patch: { "op": "add", "path": "/a", "value": 1 }.
Op := [Add({ path : Str, value : I64 }), Remove({ path : Str })].{
	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Op, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { unions: Internal({ tag: "op", content: "value" }), tags: Lower }, state)?
		Ok({ value: Op.(parsed.value), rest: parsed.rest })
	}
}
```

| `tags` | Wire name | Example | Error |
| --- | --- | --- | --- |
| `Exact` (default) | The Roc tag name | `NotFound` is `NotFound` | |
| `Upper` | Words of `A` to `Z` and `0` to `9`, one `_` between two words | `NOT_FOUND` is `NotFound`, `V2` is `V2` | A small letter, `__`, a `_` at the start or the end, another character, empty text |
| `Lower` | Words of `a` to `z` and `0` to `9`, one `_` between two words | `not_found` is `NotFound`, `add` is `Add` | The same, with a capital letter in place of a small letter |

A structural union (`Pay` above) has no `parser_for` of its own: give it a nominal type to give it options.
When the type of `parse_union` is not a tag union, the options have no effect.

| Limit of tag unions | Reason | Path |
| --- | --- | --- |
| The writer writes the external form and the Roc tag names only | The protocol gives `encode_tag` the Roc tag name and no encoding value, so the format cannot rename a tag or change its layout | An `encoder_for` of your own, for example with `Cbor.encode_record` or a `Cbor.Value` |
| An exact name for one tag (serde `rename`) | Roc has no attributes on tags | A `parser_for` of your own that reads a `Str` and matches it |
| A union with no tag (serde `untagged`) | The protocol gives the format no list of the tags, and a parse cannot go back | A `parser_for` of your own with `Cbor.peek` or `Cbor.Value` |
| A type of your own as the one payload: `peek` and `parse_cbor_tag` see the item at the content key, `parse_record_start` sees the map itself | The format sees the reader that the payload calls, not the type (rule U1) | Put such a type in a record field |

### Streams

The stream types read and write data that is larger than memory: a request body, a file, an object of a store.
A decoder reads the items of one top-level array, map or sequence, or the data of one byte string or text, from bytes that come in chunks.
Each item has the checks and options of `parse_with`. A decoder gives each item or part as soon as its bytes are there, and keeps only the open item.

| Type | Reads or writes | `values` of each `push` |
| --- | --- | --- |
| `Cbor.Items` | `Items.array(options)`: the items of one top-level array. `Items.sequence(options)`: the root items of an RFC 8742 sequence. | `List(a)`, typed as `Cbor.parse` |
| `Cbor.Entries` | `Entries.map(options)`: the entries of one top-level map, read as `parse_with` reads a `Dict(k, v)` | `List((k, v))` |
| `Cbor.ByteChunks` | `ByteChunks.new(options)`: the data of one top-level byte string | `List(List(U8))`, parts of the chunk, none empty |
| `Cbor.TextChunks` | `TextChunks.new(options)`: the data of one top-level text | `List(Str)`, none empty, each at a code point boundary |
| `Cbor.StreamWriter` | `StreamWriter.new(options)`: one item, level by level. `StreamWriter.sequence(options)`: an RFC 8742 sequence. | (a writer: each step gives `{ bytes, writer }`) |

There are two ways to use a decoder: the push loop (pure, the core), and `from_stream` on the builtin `Stream` (for a platform).

| Function of each decoder | Type (`Cbor.Items`; the others are the same with their own type) | Use |
| --- | --- | --- |
| `push` | `Cbor.Items, List(U8) -> { values : List(a), rest : Try(Cbor.Items, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64)]) }` | Give the next chunk. `values`: each item that the chunk completes, in order. `rest`: the decoder of the bytes after them, or the error. A `push` of `[]` changes nothing. |
| `finish` | `Cbor.Items -> Try({}, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64)])` | The end of the input: `Ok({})` when the root (or the sequence) is complete, else the error of the cut item. It gives no value: each item is self-delimiting, so `push` already gave each whole item. |
| `position` | `Cbor.Items -> U64` | The position in the whole stream of the first byte after the items and heads that `push` gave |
| `from_stream` | `Cbor.Items, Stream(Try(List(U8), e)) -> Stream(Try(a, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), Input(e)]))` | A `Stream` of the items, from a `Stream` of chunks. A source error `e` is `Err(Input(e))`. |

An error ends the stream: `rest` is `Err`, and each error position is a position in the whole stream.
Each item before an error is a valid item, and comes in `values` of the `push` that found the error. The stream as a whole is rejected: an app that needs all or nothing holds its effects until `finish` gives `Ok`.
Each item is read with `a.Cbor.Parseable(Cbor.Error)`, so a stream decoder's error is `Cbor.Error` and `TooLarge`; `push` and `finish` give the same union. `Entries` adds the error `NotStreamable` (below). `ByteChunks` and `TextChunks` give only `InvalidCbor(U64)` (and `Input(e)` in `from_stream`).

#### The push loop

```roc
Row : { id : U64, name : Str }

## The rows of one array that comes in `chunks`, with the push loop.
read_rows : List(List(U8)) -> Try(List(Row), _)
read_rows = |chunks| {
	var $items = Cbor.Items.array({})
	var $rows = []
	for chunk in chunks {
		r : { values : List(Row), rest : Try(Cbor.Items, _) }
		r = $items.push(chunk)
		for row in r.values {
			$rows = $rows.append(row)
		}
		$items = r.rest?
	}
	$items.finish()?
	Ok($rows)
}

encoded = Cbor.encode([{ id: 1.U64, name: "ada" }, { id: 2, name: "grace" }])

expect read_rows(encoded.chunks_of(3)) == Ok([{ id: 1, name: "ada" }, { id: 2, name: "grace" }])
# The bytes end in the text "name" (its head is at 6): the error of parse_with.
expect read_rows(encoded.take_first(9).chunks_of(3)) == Err(InvalidCbor(6))
```

`push` takes the decoder and gives the next one in `rest`, and `$items = r.rest?` sets the variable to it. So the decoder has one reference, and each chunk is appended in place: an item of n bytes in many chunks costs O(n).
A decoder that is kept and given to `push` again is copied first, as a `List` that is kept and appended to in any Roc loop. Two forms keep it without a second variable:
a `match` on `r.rest` whose `Err` branch does not set `$items` (with `break`) when `$items` is used after the loop (by `finish`), and a loop that keeps the whole result `r` and pushes into the decoder of `r.rest`.
Then each chunk of an open item copies the item: O(n^2) for one large item. Leave on an error with `?` or `return`, or set `$items` in the `Err` branch too (`$items = Cbor.Items.sequence({})`). `scripts/scale.sh` checks the loop above, the `match` form, and a function that gives the decoder back after its loop.

| Bound | Detail |
| --- | --- |
| Values of one `push` | A chunk of C bytes gives at most C items (each item has 1 byte or more; `Entries`: C / 2 entries). Their memory is the size of the decoded items, the same as `parse_with` of those bytes (the worst case: a record with many optional fields from `a0`). `max_buffer` does not count them: the chunk size sets the bound. `from_stream` gives them one at a time. |
| Open item | At most `max_buffer` bytes (below) |

#### `for!` over a `Stream`

`from_stream` turns a `Stream` of chunks from the platform into a `Stream` of items, and `for!` loops over it.
The writer helpers of `Cbor.StreamWriter` do the reverse: one call turns a `Stream` of values into a `Stream` of bytes.

```roc
ReadErr : [ReadFailed(Str)]

## Reads the rows of an array from a stream of chunks (a request body, a file), one row at a time.
import_rows! : Stream(Try(List(U8), ReadErr)) => Try(U64, _)
import_rows! = |body| {
	rows : Stream(Try(Row, _))
	rows = Cbor.Items.array({ allow: [IndefiniteLength] }).from_stream(body)
	var $count = 0
	for! row in rows {
		r = row?
		echo!("${r.name}\n")
		$count = $count + 1
	}
	Ok($count)
}

## Writes the rows as one array of indefinite length, then a byte string of 7 bytes from 2 chunks.
export! : Stream(Try(Row, ReadErr)), Stream(Try(List(U8), ReadErr)) => Try(List(U8), _)
export! = |rows, blob| {
	var $out = []
	for! piece in Cbor.StreamWriter.array_stream(rows, Indefinite, {}) {
		$out = $out.concat(piece?)
	}
	for! piece in Cbor.StreamWriter.bytes_stream(blob, Length(7)) {
		$out = $out.concat(piece?)
	}
	Ok($out)
}
```

A platform with a read function and no `Stream` gives the function to `Cbor.chunk_source`, which makes the `Stream` of chunks: each pull calls the function once, and an empty chunk (`Ok([])`) ends it.
The length argument of `Stream.custom` has another type in each nightly (`[Known(U64), Unknown]` before 2026-11, `Try(U64, [Unknown])` after), so the helper is in the package and the same code builds on both.

```roc
## Reads the rows from a read function of the platform, such as `|| File.read!(file, 65_536)`.
rows_of_read! : (() => Try(List(U8), e)) => Try(U64, _)
rows_of_read! = |read!| {
	rows : Stream(Try(Row, _))
	rows = Cbor.Items.array({}).from_stream(Cbor.chunk_source(read!))
	var $count = 0
	for! row in rows {
		_ = row?
		$count = $count + 1
	}
	Ok($count)
}
```

`chunk_source : (() => Try(List(U8), e)) -> Stream(Try(List(U8), e))`. An error of the function is the last item of the stream. A function that gives an error at the end, as `Stdin.bytes!` of basic-cli with `Err(EndOfFile)`, maps that error to `Ok([])` first, in a lambda with a `match`.

| Writer helper | Type | Writes |
| --- | --- | --- |
| `StreamWriter.array_stream` | `Stream(Try(a, e)), [Count(U64), Indefinite], Cbor.WriteOptions -> Stream(Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err]))` | One top-level array of the values |
| `StreamWriter.map_stream` | `Stream(Try((k, v), e)), [Count(U64), Indefinite], Cbor.WriteOptions -> Stream(Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err]))` | One top-level map. `Count(n)` is n entries. |
| `StreamWriter.sequence_stream` | `Stream(Try(a, e)), Cbor.WriteOptions -> Stream(Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err]))` | An RFC 8742 sequence |
| `StreamWriter.bytes_stream` | `Stream(Try(List(U8), e)), [Length(U64), Indefinite] -> Stream(Try(List(U8), [CountMismatch, Input(e)]))` | One byte string. `Length(n)`: the head, then each chunk itself (no copy). `Indefinite`: `5f`, a definite chunk for each chunk, `ff`. |
| `StreamWriter.text_stream` | `Stream(Try(Str, e)), [Length(U64), Indefinite] -> Stream(Try(List(U8), [CountMismatch, Input(e)]))` | One text, as `bytes_stream`. `Length(n)` is in bytes of UTF-8. |

`Count(n)` with more or fewer values than `n`, and `Length(n)` with more or fewer bytes, give `Err(CountMismatch)`. A source error `e` gives `Err(Input(e))`. Either error ends the stream, and the bytes so far are not a whole item. No piece is empty.

| Adapter rule | Detail |
| --- | --- |
| Lazy | A `Stream` does nothing until a `for!` (or `Stream.next!`) pulls it. `from_stream` gives the values of the last `push` one at a time, pulls the next chunk of the source only when none is left, and calls `finish` at the end of the source. A writer helper pulls a value of the source only after it gave the bytes before it. So the memory stays one chunk, its values and one open item. |
| Source errors | Wrapped as `Input(e)`, so a platform stream with a closed error union works |
| Cost | About 3% over the push loop (scale: `stream_adapter_items` against `stream_items`) |

`examples/stream.roc` uses each adapter. The writer also has steps, for the push style: `open_array`, `open_map` (`Count(n)` or `Indefinite`), `open_bytes`, `open_text` (`Length(n)` or `Indefinite`), `item`, `entry`, `bytes_chunk`, `text_chunk`, `close` and `finish`.
A step that is not valid gives `Err(CountMismatch)` and no bytes, and the writer before it is not changed. Each level needs its `close`, also a definite one. A definite `bytes_chunk` gives its input list back, with no copy, so a byte string of 5 GB streams with its 9-byte head.

```roc
## An array of two items, one step at a time.
two_items : {} -> Try(List(U8), _)
two_items = |{}| {
	open = Cbor.StreamWriter.new({}).open_array(Count(2))?
	first = open.writer.item("a")?
	second = first.writer.item(5.U64)?
	end = second.writer.close()?
	end.writer.finish()?
	Ok([open.bytes, first.bytes, second.bytes, end.bytes].join())
}

expect two_items({}) == Ok([0x82, 0x61, 0x61, 0x05])
```

#### `max_buffer` and `TooLarge`

`max_buffer` (default 16 MiB) is the most bytes that `Items` and `Entries` keep. An item that is not whole in its first `max_buffer` bytes, with more bytes after them, is `Err(TooLarge(pos))` at the start of the item.
The result is the same for each split of the input, also when all the bytes come in one chunk. A cut item of `max_buffer` bytes or less is the error of a cut item.

```roc
# One byte string of 100 bytes in a sequence, with max_buffer 64
big = Cbor.encode(Cbor.Bytes.from_list(List.repeat(7, 100)))

expect {
	r : { values : List(Cbor.Bytes), rest : Try(Cbor.Items, _) }
	r = Cbor.Items.sequence({ max_buffer: 64 }).push(big)
	r.values == [] and r.rest.map_ok(|_| {}) == Err(TooLarge(0))
}
```

| Decoder | Memory | `max_buffer` counts |
| --- | --- | --- |
| `Items` | The bytes of the open item, and the bytes of the last chunk after it | The open item |
| `Entries` | The open entry, the held entry (`key_order: Sorted` with `duplicate_keys: Last`), and the keys for duplicate keys: with `key_order: Any` the canonical bytes of each distinct key and 8 bytes for each key, with `Sorted` only the key before | All of it: an item over the bytes left is `TooLarge` at the item, keys over the limit are `TooLarge` at the key |
| `ByteChunks`, `TextChunks` | A cut head (8 bytes or less) or a cut code point (3 bytes or less), and the last chunk | Nothing: it does not apply |

A large map with `key_order: Any` keeps each key, so it needs a larger `max_buffer`, or keys in order with `key_order: Sorted`.

#### Duplicate keys in a streamed map

`Entries` reads the keys as `parse_with` reads the keys of a `Dict`: only the form that `Cbor.encode` writes for the key type, and two keys are the same when they are the same `Cbor.Value`.
`duplicate_keys: Last` needs the last entry of a key, and with keys in any order it is known only at the end of the map. So it streams only with `key_order: Sorted`, where equal keys are next to each other.

| `key_order` | `Reject` (default) | `First` | `Last` |
| --- | --- | --- | --- |
| `Any` (default) | An error at the second key | A later entry with the key is checked and not given | `Err(NotStreamable)` at the first `push` (and at `finish`) |
| `Sorted` | An error at the second key | The same as `Any` | Each entry waits until the next key is greater, or the map ends. Then the last entry of each key is given. |

```roc
# {"a": 1, "a": 2, "b": 3}
dup = [0xa3, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02, 0x61, 0x62, 0x03]

## The entries of one push of `bytes`, then the error of `push` or of `finish`.
entries : List(U8), Cbor.Options -> List(Try((Str, U64), _))
entries = |bytes, options| {
	r : { values : List((Str, U64)), rest : Try(Cbor.Entries, _) }
	r = Cbor.Entries.map(options).push(bytes)
	last =
		match r.rest {
			Ok(d) => d.finish()
			Err(e) => Err(e)
		}
	oks = r.values.map(|e| Ok(e))
	match last {
		Ok(_) => oks
		Err(e) => oks.append(Err(e))
	}
}

expect entries(dup, {}) == [Ok(("a", 1)), Err(InvalidCbor(4))]
expect entries(dup, { duplicate_keys: First }) == [Ok(("a", 1)), Ok(("b", 3))]
expect entries(dup, { duplicate_keys: Last }) == [Err(NotStreamable)]
expect entries(dup, { duplicate_keys: Last, key_order: Sorted }) == [Ok(("a", 2)), Ok(("b", 3))]
```

#### Chunks of bytes and text

`ByteChunks` and `TextChunks` give the data of one byte string or text, in parts. Only the concatenation of the parts is defined, not where each one ends.
A string of indefinite length needs `IndefiniteLength`: then the heads of its CBOR chunks are not given.

| Rule | Detail |
| --- | --- |
| No copy | Each part is a part of the chunk of its `push` (a sublist; for `TextChunks`, a `Str` over the same bytes). It keeps that whole input chunk alive. Copy a part that you keep long (append it to a list of your own), or the memory of each whole input chunk stays. |
| UTF-8 hold back | When an input chunk ends inside a code point, `TextChunks` keeps its 1 to 3 bytes, and the next output starts with the whole code point. So each `Str` is valid. These bytes are copied once, with the next chunk. |
| UTF-8 errors | The text must be valid UTF-8, as in `parse_with`. The error is at the head of the text (for an indefinite length, its first head), after the chunks before the bad bytes. |
| Root | Only a byte string (`ByteChunks`) or a text (`TextChunks`), after the tags of `ignore_tags` |

```roc
expect {
	# "€" is e2 82 ac. The first chunk cuts it: no text yet.
	r0 = Cbor.TextChunks.new({}).push([0x63, 0xe2])
	match r0.rest {
		Ok(d1) => {
			r1 = d1.push([0x82, 0xac])
			r0.values == [] and r1.values == ["€"]
		}
		Err(_) => Bool.False
	}
}
```

#### Differences from `parse_with`

A stream decoder reads the bytes that `parse_with` reads, with the same values and the same error positions (fuzz properties P1 to P3, section "Tests"), except in these cases.

| Input | `parse_with` | Stream decoder | Reason |
| --- | --- | --- | --- |
| An empty byte string (`40`) as the root of `Items.array` | `parse_with : List(a)` gives `[]` | An error at the head (0) | Only an array is a root of `Items.array` |
| An array of bytes (`80`, or an array of integers with `BytesFromArray`), or base64 text with `BytesFromBase64`, as the root of `ByteChunks` | `parse_with : List(U8)` reads it | An error at its head | Only a byte string is a root of `ByteChunks` |
| A root of another type, or a root tag that is not in `ignore_tags` | One walk of the whole root comes first, so an ill-formed byte later in the root is the error | The error is at that head. `TextChunks` on `d8 f5 ff` gives `InvalidCbor(0)`, `parse_with : Str` gives `InvalidCbor(2)`. | The decoder checks the root head before more bytes come |
| An indefinite root (`9f`, `bf`, `5f`, `7f`) | Needs `IndefiniteLength` | The same: an error at the root head without it | |
| A cut map with a whole duplicate key, under `key_order: Any` and `duplicate_keys: Reject` | The truncation error | The error at the duplicate key. Both reject. | `Entries` checks each key when it is whole |
| A key type that is composite (`Cbor.Value`, a record, a tuple) | `Dict(k, v)` with such a key does not compile | `Entries` compiles and reads it | The exact-key check of `Entries` compares the key bytes, so two different keys never give one Roc key |

`parse_sequence_with` runs on the `Items.sequence` decoder, with no `max_buffer`, so a sequence reads the same in both.

## Guarantees

What the package checks, the option that changes it, and what the app must check itself.

| Property | The package | Option | The app |
| --- | --- | --- | --- |
| Well-formed input | One walk checks each byte of the root item before the typed parse: heads, lengths, reserved info 28 to 30, breaks, `f8` below 32. Also in skipped fields and in the map of an internal tag. | `IndefiniteLength` | Nothing |
| Valid UTF-8 | Each text, also map keys, skipped items and each chunk. Overlong forms, surrogates and values above U+10FFFF are errors. | none | Noncharacters, NUL and a BOM are valid UTF-8 (RFC 8949): reject them if the protocol does |
| Shortest heads | A longer head is an error (RFC 8949 4.2.1). A bignum must be the preferred form (RFC 8949 4.2.2). | `PaddedNumbers` | Nothing |
| Duplicate keys | One rule for each reader: record, `Dict`, internal tag, `Cbor.Value`, skipped item. Keys are the same when they are the same `Cbor.Value`. The check compares key bytes after a sort, never with a hash. A `null` value counts as a key. | `duplicate_keys` (default `Reject`) | Nothing |
| Unknown keys | Skipped, with the full checks | `unknown_fields: Reject` | Set `Reject` when the protocol forbids other keys |
| Required fields | No key: `MissingRequiredField(name)` with the Roc name. A Camel key of two fields: an error at the key. | `NullAsAbsent` (null is no key) | Nothing |
| Null and absent | Strict: a `null` goes to the reader of the field (`Err(Null)`, `Null`, or an error). No key is absent. | `NullAsAbsent`, `UndefinedAsNull` | With `NullAsAbsent`, a field cannot tell `null` from no key |
| Numeric exactness | An integer out of the range of its type is an error, never cut. A float reads as an integer only with `FloatToInt` and when it is 2^53 - 1 or less. An integer reads as a float only when the float is exact. An `F32` that is not 0 and rounds to 0, or a finite value out of range, is an error. A `Dec` from an integer or a decimal fraction is exact. | `FloatToInt`, `IntFromText`, `DecFromText` | An `F32` from an f64 is rounded. A `Dec` from a float has the precision of the float (15 to 17 digits). |
| Depth and items | 512 nested arrays, maps and tags or less. 1,000,000 levels give an error, no crash. | `max_depth`, `max_items` (no default) | Set `max_items` for input from a peer, and limit the size of the input |
| Typed Ok is valid | A typed parse that gives `Ok` also gives `Ok` as a `Cbor.Value` with the same options: the one walk of the root item comes first. A fuzz property checks it. | none | Nothing |
| Output well-formed | The writer is opaque. It counts the items of each level, and each slot and container has a level id. A wrong count, or a writer of another level, gives `Err(CountMismatch)` (`encode_try`, `encode_with`), or a crash in `encode`. | none | Use `encode_try` with an `encoder_for` of your own |
| No duplicate keys written | A derived record has distinct keys. A Camel collision gives `Err(DuplicateMapKey)`. A `Cbor.ValueMap` has no duplicate key. Each derived `Dict` key form is distinct for distinct keys. | `key_order: Sorted` checks each map | A map of your own `encoder_for` is checked only with `Sorted` |
| Preferred serialization | Shortest heads (also the 9-byte form), the shortest float with the same value, each NaN as `f9 7e00`, a bignum only above 64 bits, definite lengths | none | Nothing |
| Deterministic order | Only with `key_order: Sorted` (RFC 8949 4.2.1, bytewise order of the key bytes): `encode_with` sorts each map. `Cbor.StreamWriter` with `Sorted` checks each key of a streamed map against the key before it: `Err(KeyOutOfOrder)`, or `Err(DuplicateMapKey)` for an equal key, before any byte of the key. | `key_order` (`WriteOptions`) | Use `Sorted` for bytes to hash or sign. Give a streamed map its keys in order. |
| Key order on read | With the read option `key_order: Sorted`, the keys of each map must be in the order of RFC 8949 4.2.1, in each reader: a key before the key in front of it is an error at the key. O(1) memory for each map. | `key_order` (`Options`, default `Any`) | Set `Sorted` when the protocol needs deterministic input |
| Streams | Each item, entry or chunk of a stream decoder has the checks of `parse_with` with the same options, and each split of the input into chunks gives the same items and the same error (fuzz). The differences from `parse_with` are in the table of section "Streams". The stream writer gives `Err` and no bytes for a step that is not valid, so its bytes so far are always a prefix of a valid item. | `max_buffer` | Items before an error are valid, but the stream as a whole is rejected: hold the effects until `End` when you need all or nothing. A writer error ends the output: drop what was sent. |
| Stream memory | `Items`: the open item. `Entries`: the open entry, plus the held entry (`Sorted` with `Last`), plus the key memory (each distinct key with `Any`, the key before with `Sorted`). This is at most `max_buffer` (16 MiB), else `Err(TooLarge(pos))`. Plus the last chunk, and the values of one `push` (at most one for each byte of the chunk). `ByteChunks` and `TextChunks`: 8 bytes or less, plus the last chunk. A 5 GB byte string reads in about 1 MB of RSS. | `max_buffer`, the chunk size | Set the decoder from `rest` (section "Streams"), and copy an output part that you keep long |

Known limits:

| Limit | Reason | What to do |
| --- | --- | --- |
| Hash flooding. A `Dict(k, v)` from a peer, or a `Set` or `Dict` of `Cbor.Value` from a peer, can take O(n^2) time: 100,000 crafted keys take 13 s, random keys 0.1 s. | The Roc `Dict` hash has a fixed seed for each binary (the address of a static value) | Set `max_items`. Use a `Cbor.Value` map or a list of pairs for keys from a peer. The duplicate-key checks of the package do not hash. |
| A value about 200,000 levels deep, built by app code, can overflow the stack when the program drops it. The depth depends on the platform: in `roc test`, nested arrays and tags overflow at 225,000 to 250,000 levels on Linux x86-64, and at less than 200,000 on arm64 (Linux and macOS). | The drop of Roc is recursive. The reader stops at `max_depth`. | Do not build such values, and keep `max_depth` small |
| `ValueMap.insert` and `get` are linear | A `ValueMap` is a list in order | Build a large map with `from_list` (O(n log n)) |
| `Cbor.Value` does not keep NaN payloads: each NaN reads as the default NaN and writes `f9 7e00` | `F64.from_bits` gives the default NaN | Use `Cbor.Raw` to keep the exact bytes |
| A `Cbor.Raw` read with lenient options keeps bytes that the strict reader rejects | It keeps the bytes as the peer sent them | Use `Cbor.Raw.from_bytes` or the strict options |
| A map of your own `encoder_for` with a repeated key is checked only with `key_order: Sorted` | A check with `Given` costs a sort for each map | Use `Sorted`, or `Cbor.ValueMap` |
| A `Dict` key of a composite type (`Cbor.Value`, a record, a tuple, a type of your own) does not compile | A composite key reader can read two different keys as one Roc key. The compiler also crashes on `encode_key_start`. | Use a `Cbor.ValueMap`, a list of pairs, or `Cbor.Entries`, which reads such keys with an exact check |
| A decoder that is kept and given to `push` again is copied | As a `List` that is kept and appended to: then each chunk of an open item copies the item, O(n^2) for one large item. The `?` loop has no second reference. A `match` on `rest` whose `Err` branch keeps the old decoder while `finish` follows the loop, or a loop that keeps the whole result of `push`, has one. The compiler gives no warning. | Set the decoder from `r.rest?`, or in each branch (section "Streams"), or use `from_stream` |
| `duplicate_keys: Last` on a streamed map with `key_order: Any` is `Err(NotStreamable)` | The last entry of a key is known only at the end of the map | Use `key_order: Sorted`, or `First`, or `parse_with` |
| A Camel collision on read is found only when a key that matches two fields is in the input | The check is for each key | Do not give a record two fields with one camelCase key |

## Data model

The model is the same as the model of `Json`. A peer that reads JSON sees the same objects, except bytes and tags.

| Roc | CBOR |
| --- | --- |
| Record | Map with text keys (major type 5). `encode_with({ fields: Camel })` writes camelCase keys. |
| Optional field, absent | No key. The head of the map has the real count. |
| `Try(a, [Missing])` field, `Err(Missing)` | No key |
| `Try(a, [Null])` | `Ok(x)` is `x`. `Err(Null)` is `null` (`f6`), also in a record field. With no type annotation, `Err(Null)` is a tag union to the compiler: it writes `{"Err": "Null"}`. |
| Tag with no payload | Text (major type 3) |
| Tag with one payload | Map of one entry: the tag name, then the payload. Read with `unions: Internal`: section "Tag unions". |
| Tag with more payloads | Map of one entry: the tag name, then an array of the payloads |
| List, tuple | Array (major type 4). A tuple must have the exact length. |
| `List(U8)` | Byte string (major type 2). An empty list is an empty array (`80`). Read: byte string or empty array, an array with `BytesFromArray`, base64 text with `BytesFromBase64`. One protocol call for each byte. |
| `Cbor.Bytes` | Byte string, written in one append and read as a slice. Read: as `List(U8)`. |
| `Cbor.U8Array` | Array of integers 0 to 255. Read: an array only. |
| `Str` | Text (major type 3). The reader checks UTF-8. |
| `Bool` | `f4`, `f5`. Read: also 0 and 1 with `BoolFromInt`. |
| `U8` to `U64`, `I8` to `I64` | Integer (major types 0 and 1) |
| `U128`, `I128` | Integer when it fits -2^64 to 2^64 - 1, else a bignum (tag 2, or tag 3 for -1 - n) with no leading zero byte |
| `F32`, `F64` | Float (major type 7): the shortest of f16, f32 and f64 with the same value |
| `Dec` | Integer when it has no fraction and fits 64 bits, else a decimal fraction (tag 4, exact). Read: integer, decimal fraction or float. |
| `Dict(k, v)` | Map. A key writes as its type writes: `Str` and a tag union with no payloads as text, `Bool`, integers, `U128`, `I128`, `Dec`, `F32`, `F64` as those items. A key reads only in that form. |
| `Cbor.Value` | Any item, with its tags |
| `Cbor.Raw` | One item, as its exact bytes |

## Profile

| Item | Read | Write |
| --- | --- | --- |
| Length | Definite. Indefinite with `IndefiniteLength`. | Definite |
| Head | Shortest argument. Any width with `PaddedNumbers`. | Shortest, for each argument. The 9-byte form for 2^32 or more. |
| Integer | Major types 0 and 1. A float with `FloatToInt`, text with `IntFromText`. `U128` and `I128` also read a bignum (tags 2, 3). | Major types 0 and 1, a bignum above 64 bits |
| Float | f16, f32, f64. An integer when the float is exact. `F32`: rounded, an error when out of range or when it rounds to 0. | The shortest of f16, f32, f64 with the same value. NaN, the infinities and -0.0 as f16 (each NaN `f9 7e00`). |
| `null`, `undefined` | Not the same. `null`: `Err(Null)`, `Null` of a `Cbor.Value`, else an error. `undefined`: an error except into `Cbor.Value`, or `null` with `UndefinedAsNull`. In a record: the value goes to the field, or no key with `NullAsAbsent`. | `null` for `Err(Null)` and `Null`. `undefined` only from `Cbor.Value`. |
| `Bool` from an integer | With `BoolFromInt`: 0 and 1. A float 0.0 or 1.0 needs `FloatToInt` too. | Not written |
| Tag (major type 6) | An error as a value, except a `Dec` (tag 4, and 2 and 3 in its mantissa), `U128` and `I128` (2 and 3), a tag of `ignore_tags`, `parse_cbor_tag`, `Cbor.Value` and `Cbor.Raw`. Any tag in a skipped item. | A `Dec`, a bignum, `encode_tagged`, `Tag` of a `Cbor.Value` |
| Simple values other than `false`, `true`, `null`, `undefined` | An error, except into `Cbor.Value` and `Cbor.Raw`. `f8` below 32 is not well-formed. | Only `Cbor.Value` |
| Map key | Record: text. `Dict`: the form of its key type. `Cbor.Value`: any key. A skipped item: any key. | Record: text. `Dict`: its key type. `Cbor.Value`: any. |
| Duplicate key | `duplicate_keys`: `Reject` (default), `First`, `Last` | Never from derived types. Checked for each map with `Sorted`. |
| Unknown record field | Skipped with the full checks, or an error with `unknown_fields: Reject` | |
| Order of map keys | Any, or the order of RFC 8949 4.2.1 with `key_order: Sorted` | The order of the encoder, or bytewise with `key_order: Sorted` |
| Bytes after the value | An error at the first extra byte. `parse_prefix` gives them back, `parse_sequence` reads them as items. | |
| Bytes that end in an item | An error at the head of the innermost item that is not whole: a cut head, a cut string, an open string of indefinite length, or else the innermost open array, map or tag. The same rule in each reader and stream decoder. A count far larger than the input fails with no allocation: the typed readers run only after the walk saw each item. | The real count |
| Depth and items | `max_depth` (512), `max_items` | No limit |
| `List(U8)` and `Cbor.Bytes` | Byte string, empty array, or an array of integers 0 to 255 with `BytesFromArray` (a float item also needs `FloatToInt`, text is never an item), base64 text with `BytesFromBase64` | Byte string (an empty `List(U8)`: `80`) |
| `Dec`, integer | Major types 0 and 1: exact | A `Dec` with no fraction from -2^64 to 2^64 - 1 |
| `Dec`, decimal fraction | Tag 4 and `[exponent, mantissa]`: exact. The mantissa is an integer or a bignum of 127 bits or less. More than 18 fraction digits, out of range, another tag or length, or a text mantissa is an error at the tag. | Any other `Dec`: tag 4, `[exponent, mantissa]`, exact, the smallest exponent form. `3.14159` is `c4 82 24 1a 00 04 cb 2f`. |
| `Dec`, float | f16, f32, f64: the whole part plus the fraction rounded to a whole attos (10^-18). NaN, an infinity, out of range: an error. | Not written |
| `Dec`, text | With `DecFromText` | Not written |

| Limit | Reason |
| --- | --- |
| A `Dec` with a fraction writes tag 4. A peer that does not read tag 4 (a plain JS CBOR decoder) cannot use it. A whole `Dec` is a plain integer, so a SQL parameter list such as `[1]` works. | The exact `Dec` round trip. A float is not exact for a `Dec`. |
| A `List(U8)` costs one protocol call for each byte (about 39 ns) | The derived encoder has no hook for bytes (roc-lang/roc#11660). Use `Cbor.Bytes` for large data. |
| A `List(U8)` writes a byte string. A peer that needs an array of numbers needs `Cbor.U8Array`. | One form for bytes on write |

## Changes

### 0.6.1

Faster writes and skips. The API and the bytes that are read and written do not change. Built and tested with `nightly-2026-11-13-03dce41`.

| Change | Detail |
| --- | --- |
| Writer | No early return of an error in the writer (workaround for [roc-lang/roc#13035](https://github.com/roc-lang/roc/issues/13035): an early return, from `?` or `return Err(e)`, makes the compiler lose the inlining of the writer). 10k records: `encode` 1.29 to 0.61 ms, `encode_try` and `encode_with` 2.93 to 0.62 ms |
| Skip | An unknown record field or a skipped entry, with no early return (same issue): 10k records with 12 unknown fields each, 12.6 to 11.4 ms |

### 0.6.0

The codec contract of the Roc compiler of 2026-11-08 and later: each format owns one error type, and each operation of a derived parser gives it. 0.5.0 does not compile with that contract (`Encoding.ParseTagUnionSpec` takes four type parameters, and a format with required record fields needs `missing_field`). The bytes that are read and written do not change.

| Change | Detail |
| --- | --- |
| `Cbor.Error` | `[InvalidCbor(U64), MissingRequiredField(Str)]`, the one error of every read. `MissingRequiredField(name)` still names the Roc field |
| `missing_field` | The codec protocol's method for an absent required field |
| `parse_tag_union` | Takes `Encoding.ParseTagUnionSpec(a, Cbor, Cbor.Reader, Cbor.Error)` |
| Reads | `parse`, `parse_with`, `parse_prefix`, `parse_prefix_with`, `parse_sequence`, `parse_sequence_with`, `parse_item` and `parse_union` give `Cbor.Error`, not an open union |
| Streams | The item readers of `Cbor.Items` and `Cbor.Entries` are `Parseable(Cbor.Error)`. `push`, `finish` and `from_stream` give one closed union each: `Cbor.Error` with `TooLarge` (and `NotStreamable` for `Entries`, `Input(e)` from `from_stream`) |
| `Readable` | `a.Cbor.Readable`, with no type parameter |
| Fuzz | The targets use roc-fuzz 0.6.1, with examples |
| Speed | Same API and bytes. `python3 bench/compare/run.py` (`--opt=speed`, `nightly-2026-11-13-03dce41`), time of 0.6.0 against the start of the 0.6 work: 10k records read 9.2 to 3.5 ms and write 2.7 to 1.3 ms; 100k map keys into a `Dict` 16 to 8.0 ms and into a `Cbor.Value` 19 to 10.6 ms; 10k records with unknown fields 29 to 12.5 ms; 10k texts 1.5 to 0.74 ms. A fast walk of the root item, fast paths of the readers at a plain position (each other case goes to the general reader, with the same values and error positions), and a writer that checks each place when the next one opens. The peak RSS of a `Cbor.Value` of 100k map keys: 25 to 18 MB |
| `fuzz.sh` | A build with warnings only (exit code 2) is a build: roc-fuzz 0.6.1 has a warning in its platform |
| CI nightly | `.roc-version` is `nightly-2026-11-13-03dce41`. The tests also pass on `nightly-2026-11-11-7679cc5` |

#### Migration from 0.5

| 0.5.0 | 0.6.0 |
| --- | --- |
| `where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]` | `where [a.Cbor.Parseable(Cbor.Error)]` |
| `where [a.Cbor.Readable(errs)]` | `where [a.Cbor.Readable]` |
| A custom `parser_for` gives `[InvalidCbor(U64)]` | It gives `Cbor.Error` |
| A `match` on the result of a read with `Err(_)` for other errors | A `match` on `InvalidCbor` and `MissingRequiredField` is complete |
| A `match` on `finish` of `Cbor.Items` or `Cbor.Entries` | It also gives `MissingRequiredField` (from an item, as `push` does) |

### 0.5.0

A strict reader, a checked writer and the fixes of an audit of 0.4.1.
Code and data of 0.4 can need a change: see the table "Migration from 0.4".

| Change | Detail |
| --- | --- |
| Strict reader | Each lenient read of 0.4 is now a `Cbor.Leniency` in `allow`. `Cbor.sql_rows` gives the SQL rules of 0.4. Shortest heads, no duplicate keys, `undefined` is not `null`. (G1, F8) |
| One notion of valid | One walk of the root item checks each byte before the typed parse. `path_at`, skipped fields, internal tags and `Cbor.Value` have the same checks. (F1, F2, F6) |
| Duplicate keys | One rule for each reader, the option `duplicate_keys`. No hash of keys from a peer. (F3, F4, F5) |
| Limits | `max_depth` (512) and `max_items`. 1,000,000 levels give an error, no crash. Internal unions: one scan of each map, linear in depth. (D1, D2, D3) |
| Options | `unknown_fields`, `NullAsAbsent`, `UndefinedAsNull`, `IndefiniteLength`. A Camel key of two fields is an error. `MissingRequiredField` names the Roc field. (G6, F7) |
| Checked writer | `Cbor.Writer` is opaque and counts items at each level. `encode_try` and `encode_with` give `Err(CountMismatch)`. `encode_tagged` writes a tag and its one item. (W1 to W6, W15) |
| Preferred serialization | Shortest heads (also the 9-byte form). Floats in the shortest of f16, f32, f64. (W7, W8) |
| Write options | `encode_with`: `fields: Camel`, `key_order: Sorted` (RFC 8949 4.2.1) (G8, W8, C3) |
| Null | `Err(Null)` writes `null`, also in a record field. A strict reader gives the `null` to the field. (W10, W11) |
| Bytes | `List(U8)` writes a byte string. `Cbor.U8Array` writes an array. `Cbor.Bytes` is the fast byte string type. (W13, C1) |
| `Cbor.Value` | `Int(Cbor.IntValue)`, `Map(Cbor.ValueMap)` with no duplicate key, `Simple(Cbor.SimpleValue)`. `is_eq` and `to_hash` are loops. (W9, W14, D5) |
| New | `parse_prefix`, `parse_sequence` (RFC 8742), `Cbor.Raw` (G3, G4). `Dict` write and keys that are not text, `U128`, `I128` (G5). Indefinite lengths on read (G7). |
| Streams | Data larger than memory (section "Streams"). Decoders `Cbor.Items` (array, sequence), `Cbor.Entries` (map), `Cbor.ByteChunks`, `Cbor.TextChunks`, each with `push` (the values that a chunk completes, and the next decoder or the error), `finish`, `position` and `from_stream` (the builtin `Stream`). `Cbor.chunk_source` makes a `Stream` of chunks from a read function. `Cbor.StreamWriter` with steps, and the helpers `array_stream`, `map_stream`, `sequence_stream`, `bytes_stream`, `text_stream`. New errors `TooLarge(pos)`, `NotStreamable`, `Input(e)` and, on write, `KeyOutOfOrder`. |
| Read options | `max_buffer` (16 MiB, streams only) and `key_order: [Any, Sorted]` (each reader: the keys of each map in the order of RFC 8949 4.2.1) |
| `parse_sequence_with` | Now runs on the `Items.sequence` decoder, with no `max_buffer`. Same signature, same results. |
| One truncation rule | When the bytes end in an item, the error is at the head of the innermost item that is not whole, in each reader and stream decoder. The count of an array or a map is not checked against the bytes left, so a stream and `parse_with` give the same position for the same bytes: `84 00 61` gives 2 (the cut text). A huge count still fails with no allocation. |
| Speed | The checks cost time. Against 0.4.1 (`scripts/bench.sh`, `--opt=speed`, `nightly-2026-11-07-ad3a5d2`): most reads are 1.9x to 3.2x slower, record encode is 4x slower. Large `List(U8)` and deep trees read faster (0.3x to 0.4x). The encode of a `List(U8)` is 4.4x slower: use `Cbor.Bytes` for large blobs (no change from 0.4.1). Most of the cost comes from the code that the compiler makes, not from the checks, so there is no option to turn checks off. A later version can get faster with no API change. |
| CI nightly | `.roc-version` is `nightly-2026-11-07-ad3a5d2`. The tests also pass on `nightly-2026-10-19-601b54c`. |
| Tests | New `tests/reader.roc`, `writer.roc`, `options.roc`, `dict.roc`, `indefinite.roc`, `value.roc`, `deterministic.roc`, `truncation.roc`, `key_order.roc`, `stream.roc`, `stream_entries.roc`, `stream_chunks.roc`, `stream_writer.roc`, and the app `stream_adapters.roc`. New fuzz properties and the targets `fuzz/stream.roc`, `fuzz/stream_writer.roc`. `scripts/scale.sh` (with stream and memory cases), `bench.sh`, `differential.sh` and their CI jobs. `scripts/wasm_dev.sh` (in `all_tests.sh`). `examples/stream.roc`. |

Migration from 0.4:

| 0.4 | 0.5.0 |
| --- | --- |
| `Cbor.State` | `Cbor.Reader` |
| `encoder_for : Cbor -> (T, List(U8) -> Try(List(U8), []))` | `encoder_for : Cbor -> (T, Cbor.Writer -> Try(Cbor.Writer, err))`. Write each item with `Cbor.encode_item`, `encode_*` or `encode_tagged`. |
| `Cbor.encode_cbor_tag(n, out)?`, then `Cbor.encode_item(v, ..)` | `Cbor.encode_tagged(n, v, w)` |
| `Cbor.parse_camel(bytes)` | `Cbor.parse_with(bytes, { fields: Camel })` |
| `{ int_from_text: Bool.True }`, `{ dec_from_text: Bool.True }` | `{ allow: [IntFromText] }`, `{ allow: [DecFromText] }` |
| `Cbor.parse` read 0 and 1 as a `Bool`, `null` as no key, a float as an integer, `undefined` as `null`, an array as bytes | Strict. For rows of SQL: `{ allow: Cbor.sql_rows }`. Or each leniency alone. |
| Data written by 0.4: padded numbers, heads not shortest (`99 00 18`, `b9 00 00`) | Add `PaddedNumbers`: `{ allow: [PaddedNumbers] }`, or `Cbor.sql_rows.append(PaddedNumbers)` |
| A key two times in one map: the last value (a record), no error | `Err(InvalidCbor(pos))`. `duplicate_keys: Last` reads as 0.4 did for a record. |
| A recursive type of any depth | 512 levels or less. Set `max_depth` for more. |
| `Err(Null)` in a record field wrote no key | It writes `null`. A reader of 0.4, or `NullAsAbsent`, reads it as no key. |
| `List(U8)` wrote an array of integers | A byte string. For a peer that needs an array: `Cbor.U8Array`. |
| `List(U8)` and `Cbor.Bytes` read an array of integers | With `BytesFromArray` (in `Cbor.sql_rows`) |
| `F64` wrote 9 bytes (f64) | The shortest float. The value read back is the same, the bytes are not: a hash or a signature over bytes of 0.4 does not match bytes of 0.5.0. |
| `Value.Int(n)` with an `I128` | `Int(Cbor.IntValue)`. A literal works: `Int(5)`. From a variable: `Cbor.IntValue.from_i128(n)` (`Err(OutOfRange)`), `from_i64`, `from_u64`. Read with `v.to_i128()`. |
| `Value.Map(pairs)` | `Map(Cbor.ValueMap)`: `Cbor.ValueMap.from_list(pairs)` (`Err(DuplicateKey(key))`). Read with `map.to_list()`. |
| `Value.Simple(n)` with a `U8` | `Simple(Cbor.SimpleValue)`. A literal works: `Simple(16)`. From a variable: `Cbor.SimpleValue.from_u8(n)` (`Err(InvalidSimple)` for 20 to 31). |
| `where [a.Cbor.Encodable([])]`, `Readable`, `Writable`, `Parseable` | No change in the form. The aliases now name `Cbor.Reader` and `Cbor.Writer`. |
| A `Cbor.Options` record in a `let` with no annotation | Still needs `opts : Cbor.Options`: the full record now has 10 fields |

### 0.4.1

A fix for a compiler fault. The read of a small integer type goes through an `I64`. No API change.

| Change | Detail |
| --- | --- |
| Cause | The wasm32 dev backend of the Roc compiler (`roc build --target=wasm32 --opt=dev`; seen on `nightly-2026-10-31-f7bef6b` and `nightly-2026-11-01-48d3369`) gives `Err(OutOfRange)` for `I128.to_u8_try`, `to_u16_try`, `to_i8_try` and `to_i16_try` of a value in range. The reader keeps a CBOR integer as an `I128`. |
| Effect before | In such a build, a `U8`, `U16`, `I8` or `I16` did not read: `Err(InvalidCbor(pos))` at the integer. So a `List(U8)` (it is written as an array) did not read back from its own bytes, and `Cbor.Bytes` did not read an array (a D1 BLOB). The other backends (`--opt=speed`, `--opt=size`, the native dev backend, the interpreter of `roc test`) were correct. |
| Fix | The reader converts the `I128` to an `I64` first, then to `U8`, `U16`, `U32`, `I8`, `I16` or `I32`. The range and the error position do not change. |
| Tests | `tests/ints.roc` (12 expects): the bounds of each small type, and `List(U8)` in a record and a tag payload. `roc test` runs the interpreter, which does not have the fault. The check in a wasm32 dev build is in the `cloudflare-workers` platform (the conformance checks of `Memo`). |

### 0.4.0

This release adds the internal tag of a tag union on read (section "Tag unions"). The readers of 0.3.0 do not change when the option `unions` is not set.

| Change | Detail |
| --- | --- |
| Option `unions` | `Internal({ tag, content })` reads `{ tag: "Card", ..payload }`. `External` (default) is the form of 0.3.0. Read only. |
| `Cbor.Unions` | The type of the option `unions` |
| `Cbor.parse_union`, `Cbor.UnionOptions` | In a `parser_for` of your own: one union type with its own layout, and tag names in upper or lower snake case (`tags: Upper`, `tags: Lower`) |
| `Cbor.peek`, `Cbor.parse_cbor_tag`, `Cbor.Value` | In the map of an internal tag with one payload, they see the item at the content key (rule U1). 0.3.0 had no internal tag, so no read of 0.3.0 changes. |
| Migration | A `Cbor.Options` record in a `let` with no annotation that has the 4 fields of 0.3.0 (`opts = { fields: Camel, int_from_text: Bool.True, dec_from_text: Bool.False, ignore_tags: [] }`), or a function with no annotation that gives one, does not compile now: the compiler gives "missing method" at the call of `parse_with`. Add the annotation `opts : Cbor.Options`. The cause is the same as in 0.3.0: the full record now has 5 fields. A record literal in the call, and an annotated record, do not change. |
| Version | 0.4.0, not 0.3.1, because of the migration row: code that compiles with 0.3.0 can fail to compile |
| Writer | No change: `Cbor.encode` writes the external form (table "Limits of tag unions") |
| Tests | `tests/unions.roc` (41 expects). The new fuzz target `fuzz/unions.roc`. `fuzz/parse_never_crashes.roc` has a recursive union with a record, a `Dict` and a `Cbor.Value` payload, and a type with `Cbor.parse_union`, with `unions: Internal`. `fuzz/cbor.dict` has the keys and the tag names of the targets. |

### 0.3.0

This release adds tags and dynamic values (section "Tags and dynamic values"). The readers of 0.2.2 do not change when the new options are not set.

| Change | Detail |
| --- | --- |
| `Cbor.parse_cbor_tag`, `Cbor.encode_cbor_tag` | Read and write the head of a tag in a `parser_for` or an `encoder_for` of your own. Before: `Cbor.State` is opaque, so a type of an app could not read a tag. |
| `Cbor.parse_item`, `Cbor.encode_item` | Read and write one item of a type, for example the tagged item |
| `Cbor.peek`, `Cbor.Kind` | The kind of the next item, with no read |
| `Cbor.Value` | Any CBOR item, with its tags, maps with any keys, and simple values. `parser_for`, `encoder_for`, `is_eq` and `to_hash`. |
| Option `ignore_tags` | The readers of the types skip a tag of the list before an item |
| Option `dec_from_text` | A `Dec` also reads decimal text, with an exponent (`"4E+1"`) |
| Migration | A `Cbor.Options` record in a `let` that is not the full record (for example `opts = { fields: Camel, int_from_text: Bool.True }`) needs the annotation `opts : Cbor.Options`. The compiler checks a record literal in a `let` with no annotation as a closed record, and the full record now has 4 fields. A record literal in the call (`Cbor.parse_with(bytes, { fields: Camel })`) does not change. |
| Tests | `tests/tags.roc` (92 expects). `fuzz/round_trip.roc` has a field `List(Cbor.Value)` and the property that a tag 6 before each value reads the same item with `ignore_tags: [6]`. `fuzz/parse_never_crashes.roc` has `Cbor.Value` (it reads back from its own bytes) and the two new options. |

### 0.2.2

This release changes two behaviors. There is no option for the old behavior (section "SQL rows" gives the reasons).

| Change | Before (0.2.1) | Now | Reason |
| --- | --- | --- | --- |
| A `Bool` reads the integers 0 and 1 | Only `false` and `true`. `{"a": 0}` into `{ a : Bool }` was `InvalidCbor(3)`. | `false`, `true`, 0 and 1. Another integer is an error. The writer does not change. | A SQL database (SQLite, D1) has no boolean and gives 0 and 1, so a typed row could not have a `Bool` field. |
| A `null` (or `undefined`) value in a map is no key, when the map is read as a record | A `null` read only into a `Try(a, [Null])` field. Into an optional field or a `Try(a, [Missing])` field it was `InvalidCbor(pos)`. | An optional field is absent and a `Try(a, [Missing])` field is `Err(Missing)`. A required field, also a `Try(a, [Null])` field, is `MissingRequiredField(name)`. | A nullable column is naturally an optional field. The format cannot see the field type when it reads a `null`, so one rule for each `null` in a record is the only consistent rule. |
| `Err(Null)` in a record field writes no key | `Err(Null)` wrote `null` | No key, and the head has the real count | The writer and the reader have the same model. A record with `Err(Null)` reads back into an optional field or a `Try(a, [Missing])` field. |
| Migration | | A `Try(a, [Null])` record field: change it to `x ?: a` or `x : Try(a, [Missing])`. A `Try(a, [Null])` item of a list or a tuple, a `Dict` value and the root do not change. | |
| Tests | | `tests/rows.roc` (45 expects). The fuzz targets have a `Bool` field, a list of `Try(I64, [Null])`, and a property for `Err(Null)` in a record field. | |

### 0.2.1

| Change | Detail |
| --- | --- |
| CI nightly | `.roc-version` is `nightly-2026-10-19-601b54c`. The code of the package does not change. |
| Format | `roc fmt` of this nightly writes `if (cond) a else b` with brackets. The files of `src`, `tests`, `examples` and `fuzz` have them, so that `roc fmt --check` passes. |
| Known issues | #12309 and #12310 do not reproduce on this nightly (the repros are in `research/roc-bugs/` of the `cloudflare-workers` repository). The rows in "Known compiler issues" say so. The workarounds stay, as an older nightly needs them. |
| Fuzz target | `fuzz/parse_never_crashes.roc` has the optional field `extra ?: Bool` again: this nightly builds a parse into it. |

### 0.2.0

| Change | Detail |
| --- | --- |
| `Cbor.Bytes` reads an array | A byte string or an array of integers 0 to 255. A JS peer that sends bytes as a plain array (for example a D1 BLOB, which D1 gives back as a JS array) writes a CBOR array. Before: an array was an error. Writing is the same (a byte string). |
| `List(U8)` reads a byte string | No change: 0.1.0 already read a byte string as a `List(U8)`, and only that type (the list reader checks the major type, and `parse_u8` is the only item reader that takes a byte). A test now covers a byte string in a record field. |
| `encode_dec` | A `Dec` writes as an integer when it has no fraction (-2^64 to 2^64 - 1), so an untyped literal such as `[1]` (a `List(Dec)`) is an array of CBOR integers, which a SQL parameter list of the platform needs. Any other `Dec` writes as a decimal fraction (RFC 8949 3.4.4, tag 4, `[exponent, mantissa]`), exact: `3.14159` is `c4 82 24 1a 00 04 cb 2f`. |
| `parse_dec` | A `Dec` reads an integer and a decimal fraction (exact), and also a float (rounded to the nearest attos) for input from JS. |
| `Options` fields are optional | `Cbor.Options` is `{ fields ?: [Snake, Camel], int_from_text ?: Bool }`. `{}` is the same as `parse`. `{ int_from_text: Bool.True }` and the full record still compile. |
| `Cbor.Readable`, `Cbor.Writable` | Short `where` aliases next to `Parseable` and `Encodable` (section "Readable and Writable"). |
| `Cbor.Bytes.from_list` | `List(U8) -> Cbor.Bytes`, the pair of `to_list`, for code that sees `Bytes` through an alias. |

### 0.1.0

First release: the codec protocol, `Cbor.Bytes`, `parse_camel`, `parse_with`, `path_at`.

## Tests

`scripts/all_tests.sh` runs these steps with the compiler in `ROC` (default: `roc` from the path). The roc cache is in `.cache/roc`.

| Step | Command |
| --- | --- |
| Format | `roc fmt --check src tests examples fuzz` |
| Check | `roc check src/main.roc` |
| Expects of the module (189) | `roc test src/main.roc` |
| RFC 8949 Appendix A (187 expects) | `roc test tests/rfc8949.roc` |
| `Readable` and `Writable` (5) | `roc test tests/aliases.roc` |
| SQL rows with `Cbor.sql_rows` (46) | `roc test tests/rows.roc` |
| Tags, `peek`, `Cbor.Value`, `ignore_tags`, `DecFromText` (93) | `roc test tests/tags.roc` |
| Tag unions: `unions: Internal`, `parse_union` (43) | `roc test tests/unions.roc` |
| Small integer types (12) | `roc test tests/ints.roc` |
| The checked reader: one notion of valid, the depth limit, internal tags in depth (62) | `roc test tests/reader.roc` |
| One truncation rule: the error position when the bytes end in an item, a count far larger than the input (36) | `roc test tests/truncation.roc` |
| The writer: counts, level ids, shortest heads, null, bytes, `encode_tagged`, `Cbor.Bytes` (49) | `roc test tests/writer.roc` |
| The reader options: each leniency, null, `duplicate_keys`, `unknown_fields`, `max_items`, Camel keys, exact floats (101) | `roc test tests/options.roc` |
| The read option `key_order: Sorted` in each reader, with `duplicate_keys` (27) | `roc test tests/key_order.roc` |
| `Cbor.StreamWriter`: each kind of level, counts and lengths, the 9-byte head, `key_order: Sorted` on a streamed map (38) | `roc test tests/stream_writer.roc` |
| `Cbor.Items`: each split of the input into chunks gives the items and the error of `parse_with`, `max_buffer`, `push` and `finish` (values before an error, a cut item, an empty chunk, N items from one chunk) (37) | `roc test tests/stream.roc` |
| `Cbor.Entries`: each split gives the entries and the error of `parse_with` of a `Dict`, duplicate keys (`Any`, `Sorted`), `max_buffer`, `push` and `finish` (38) | `roc test tests/stream_entries.roc` |
| `Cbor.ByteChunks`, `Cbor.TextChunks`: each split gives the data and the error of `parse_with`, the UTF-8 hold back, `push` and `finish` (32) | `roc test tests/stream_chunks.roc` |
| The adapters to the builtin `Stream`: `from_stream` of each decoder, `Cbor.chunk_source` and the writer helpers (75 checks). An app, not `roc test`: a `Stream` is effectful, and an `expect` cannot run an effect. It prints each failed check and exits with 1. | `roc check tests/stream_adapters.roc`, `roc tests/stream_adapters.roc` |
| `Dict`: `encode_dict`, keys that are not text, the form of a key, `U128`, `I128` (56) | `roc test tests/dict.roc` |
| Indefinite lengths with `IndefiniteLength` (32) | `roc test tests/indefinite.roc` |
| `ValueMap`, `IntValue`, `SimpleValue`, `is_eq`, `to_hash`, `parse_prefix`, `parse_sequence`, `Cbor.Raw` (65) | `roc test tests/value.roc` |
| Preferred floats, `key_order: Sorted` (52) | `roc test tests/deterministic.roc` |
| The wasm32 dev backend: the shapes that overflowed the stack, built with `--target=wasm32 --opt=dev` and run in node (SKIP with no node). Two apps: `tests/wasm_dev/app.roc` (the encode shapes, `Items`, `ByteChunks`, `StreamWriter`, the adapters) and `tests/wasm_dev/entries.roc` (`Entries`). The second app exists because the code of `Entries` in the first app made its case `deep` trap on `nightly-2026-10-19-601b54c` (roc-lang/roc#12922: the frames of an app grow with its code; on `nightly-2026-11-07-ad3a5d2` the stack of `deep` does not change). | `scripts/wasm_dev.sh` |
| Examples | `roc check` and run each `examples/*.roc` |
| Docs | `roc docs src/main.roc` |

Each fix of 0.5.0 has a regression test, and each test was checked against the code with the fix removed.

| Script | Checks |
| --- | --- |
| `scripts/fuzz.sh [runs]` | The property tests with [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) 0.6.1 (each target reads its input bytes as the entropy of its generators, as 0.4.3 did; the generated values hold `Cbor` encoders, so they have no derived roc-fuzz input format): a fixed count of inputs for each target in `fuzz/` (default 1,000,000, seed 1, inputs of 4,096 bytes or less, the tokens of `fuzz/cbor.dict`). Linux x86-64 and macOS arm64 only. A failure is saved in `.cache/fuzz/art-<target>/`. |
| `scripts/scale.sh [runs]` | Complexity. Each case of `bench/scale.roc` (writer), `bench/scale_read.roc` (reader) and `bench/scale_stream.roc` (the `Stream` adapters) is its own app (`--opt=speed`), at 5k, 10k, 20k and 40k items. The time for each item must not grow more than 2.5x (n log n for a key sort, depth for the depth cases). It fails on 0.4.1 (internal unions), on a quadratic duplicate check, on a decoder that is kept and pushed again, on a walk of the open item from its start at each chunk, and on a linear scan of the keys of a streamed map. Table "Stream scale cases". |
| `scripts/bench.sh [--check \| --update] [runs]` | Speed of `bench/bench.roc`: 0.4.1 against HEAD, or HEAD against `bench/baseline.txt` (each time divided by the time of a `calib` case; a case fails above 1.5x) |
| `python3 bench/compare/run.py [--refresh]` | A diagnostic for development (`bench/compare/README.md`): the same fixtures read and written by roc-cbor and by CBOR libraries of other languages as reference points, to find slow paths and compiler issues. A local report: its results are not committed. |
| `scripts/differential.sh [count] [seed]` | `Cbor.Value` against Python `cbor2` 6.2.1 on the fuzz corpus, the RFC vectors and random items with mutations. A difference that is not in the table of `differential/differential.py` fails. `DIFF_STRICT=1`: padded numbers (no `PaddedNumbers`) are an expected difference. |
| `scripts/bundle.sh` | Makes `dist/<hash>.tar.zst` and prints its release URL |
| `scripts/test_bundle.sh` | Runs the examples against that file (served on `127.0.0.1`), or against a release URL, with `--replace-dep` |

| Fuzz target | Property |
| --- | --- |
| `fuzz/parse_never_crashes.roc` | Any bytes give a value or an error, never a crash: `parse`, `parse_with` (each option and leniency, `Cbor.sql_rows`), `path_at`, into records, lists, `Dict` with integer keys, `U128`, `I128`, `Cbor.Value`, recursive internal unions and `parse_union`. A typed `Ok` is `Ok` as a `Cbor.Value`. `path_at` gives `Ok` for one well-formed item. A `Cbor.Value` that reads writes bytes that read back. `Cbor.Raw` keeps the bytes that `Cbor.Value` reads. `parse_prefix` and `parse_sequence` agree with `parse`. |
| `fuzz/round_trip.roc` | `Cbor.parse(Cbor.encode(v)) == Ok(v)` with the strict reader, for a record with each kind of field. The lenient reads, `duplicate_keys`, `unknown_fields: Reject` and an exact `max_items` give the same value. `Err(Null)` reads back. A tag 6 before each value reads the same with `ignore_tags: [6]`. Each `Cbor.Value` made through the public constructors reads back equal, with the same hash. `key_order: Sorted` reads back (each `Cbor.Value` map with its entries in the sorted order) and is stable. |
| `fuzz/unions.roc` | Random tag union values in the internal form read back with `unions: Internal`, and in the external form with the defaults. A decoy tag key is an error with `Reject`, and the real tag with `Last`. |
| `fuzz/stream.roc` | The stream decoders, for any bytes and splits from the input, with 10 option sets (also `key_order: Sorted`). P1 split independence: 4 random splits (with empty chunks) and 1-byte chunks give the same items and the same end as one chunk, also `TooLarge` with a small `max_buffer`. P2 agreement with `parse_with` and `parse_sequence_with` (Ok with the same values, or both Err), except the differences of section "Streams". P3 a slow reference model (the root head, then `parse_prefix_with` for each item; for `Entries` the order and the duplicates of each key, the held `Last` entry, `NotStreamable`): the same items and the same error position. Roots built from the input (text with 2, 3 and 4-byte code points, maps with repeated keys), because random bytes rarely reach them. |
| `fuzz/stream_writer.roc` | P4 round trip: random `Cbor.Value` items written through `Cbor.StreamWriter` (random `Count` or `Indefinite`, chunk sizes, entry forms, also with `key_order: Sorted`) read back with `parse_with` as the same values, also as a sequence. P5 the writer refuses: a random run of steps; when `finish` gives `Ok`, the bytes of the `Ok` steps are one valid item. |

| Stream scale cases (`scripts/scale.sh`) | Checks |
| --- | --- |
| `stream_items`, `stream_entries`, `stream_bytes`, `stream_text` | The push loops of `Items`, `Entries`, `ByteChunks`, `TextChunks`: linear in the item count or the size |
| `stream_big_item` | One item of n records in 1 KiB chunks, with the `?` loop of section "Streams": linear (each byte of the open item is walked one time and appended in place) |
| `stream_trap_reset`, `stream_trap_return` | The same item with the loop forms of the old single-use traps: a `match` on `rest` with `break` in its `Err` branch (which sets a new decoder) and `finish` after the loop; a function that gives the decoder back after its loop. Linear. |
| `stream_keys`, `stream_keys_dup` | A streamed map with n distinct keys, and with n distinct then n repeated keys (`First`): n log n |
| `sorted_keys` | `key_order: Sorted` on read: linear, fewer instructions than `Any` |
| `stream_array`, `stream_sorted` | `StreamWriter` steps, also with `key_order: Sorted`: linear |
| `stream_adapter`, `stream_adapter_items`, `stream_adapter_write` | `from_stream` (one open item in 256-byte chunks, and many items) and `array_stream`: linear |
| `stream_memory` | Memory, not time: `Items.from_stream` of 250,000 and 1,000,000 items of 100 bytes from a lazy source. The maximum RSS must not grow (about 400 KiB at both). |
| `stream_5gb` (opt in: `SCALE_BIG=1`) | A byte string of 5,000,000,000 bytes from `bytes_stream` into `ByteChunks.from_stream` in 1 MiB chunks, each byte checked against a counter: a few seconds, about 1 MB of RSS, linear time |

The memory cases run under `ulimit -v` (512 MiB), so a memory bug is a FAIL row.

`tests/rfc8949.roc` uses the public API with the hex text of the RFC.

| Appendix A group | Result |
| --- | --- |
| Integers up to 64 bits, positive and negative | Read and written. A longer head is an error, and reads with `PaddedNumbers`. |
| `18446744073709551616`, `-18446744073709551617` (bignums, tags 2 and 3) | An error as `U64` or `I64`. A `U128` or an `I128` reads them (`tests/dict.roc`). |
| Floats: f16, f32, f64, with zero, infinity and NaN | Read. Each vector of the RFC is written in its shortest form. |
| `false`, `true`, `null`, `undefined` | In the profile. `undefined` reads as `null` with `UndefinedAsNull`. |
| `simple(16)`, `simple(255)` | An error for a typed value. `Cbor.Value` reads them. |
| Tags 0, 1, 23, 24, 32 | An error as a value. Skipped in an unknown field. |
| Byte strings, text (also non-ASCII) | Read and written |
| Arrays, maps (text keys) | Read and written. The array of 25 items has the 1-byte argument (`98 19`). |
| Indefinite byte string, text, array, map | An error at the start of the indefinite item. Read with `IndefiniteLength` (`tests/indefinite.roc`). |
| Map with integer keys, `{1: 2, 3: 4}` | An error for a record at the first key (position 1). A `Dict(U64, U64)` and a `Cbor.Value` read it. |

## CI and releases

| Workflow | Job | Does |
| --- | --- | --- |
| `.github/workflows/tests.yaml` (push to `main`, pull request, by hand) | `bundle` | Makes the bundle once on Linux |
| | `test` | `scripts/all_tests.sh` and `scripts/test_bundle.sh` on Linux x64, Linux arm64 and macOS arm64 |
| | `fuzz` | `scripts/fuzz.sh` on Linux x64. A failure uploads the inputs. |
| | `scale` | `scripts/scale.sh 3` with 200,000 items. Blocks. |
| | `differential` | `scripts/differential.sh` with `DIFF_STRICT=1` and `cbor2` 6.2.1. Blocks. |
| | `bench` | `scripts/bench.sh --check 5`. Report only: a shared runner is not the baseline machine. |
| `.github/workflows/release.yml` (push of a tag `X.Y.Z` or `X.Y.Z-pre`) | | Runs the tests, makes the bundle and the docs, and publishes the GitHub Release with `<hash>.tar.zst` and `package-docs.tar.gz`. Then runs the examples against the published URL. |

`.github/actions/setup-roc` downloads the nightly of `.roc-version` from `roc-lang/nightlies` with `gh release download`.
A tag has no `v`: roc reads the version from the URL, and the tag is a segment of the URL.

## Known compiler issues

| Issue | Effect | Workaround |
| --- | --- | --- |
| [roc-lang/roc#12917](https://github.com/roc-lang/roc/issues/12917) (`nightly-2026-10-19-601b54c` to `nightly-2026-11-07-ad3a5d2`) | The drop of a value is recursive: dropping a `Cbor.Value` (or another recursive value) about 200,000 levels deep overflows the stack (fewer on arm64), also on an error path | The reader stops at `max_depth` (512). Do not build such values in app code. |
| [roc-lang/roc#12919](https://github.com/roc-lang/roc/issues/12919) (`nightly-2026-10-19-601b54c` to `nightly-2026-11-07-ad3a5d2`) | A format with `encode_key_start` crashes the compiler (SIGSEGV) with a `Dict` key of a composite type. A tag union key then also needs `encode_key_str`. | The package has no `encode_key_start` and no `parse_key_start`: a composite key is a compile error |
| [roc-lang/roc#13032](https://github.com/roc-lang/roc/issues/13032) (`nightly-2026-10-19-601b54c` to `nightly-2026-11-13-03dce41`) | A record that holds the output list, read after a callback, keeps a second reference to the list, so the next append copies it (an encode of n items is O(n^2)). On the dev backend, `match d.list { Pending(n) => .., _ => o }` on a destructured writer also copied the list. | The writer reads no field after a callback, and uses `if` there. `scripts/scale.sh` checks each writer shape. |
| [roc-lang/roc#13025](https://github.com/roc-lang/roc/issues/13025) (`nightly-2026-11-13-03dce41`) | `Str.from_utf8` out of line decodes each code point and checks the last bytes again: 4.6x the time of Rust on short multi-byte text | `valid_utf8` checks UTF-8 in one pass in Roc in the walk (`TODO(roc#13025)` says how to go back). A test compares it with `Str.from_utf8`. |
| [roc-lang/roc#13035](https://github.com/roc-lang/roc/issues/13035) (`nightly-2026-11-13-03dce41`) | An early return (from `?` or `return Err(e)`) in closure-heavy code makes LLVM lose its inlining: the writer was up to 2x slower, and 4.7x with a non-empty error type (`encode_try`) | The writer and `skip` give an error with a match and no return (`TODO(roc#13035)` says how to go back) |
| [roc-lang/roc#12922](https://github.com/roc-lang/roc/issues/12922) (`nightly-2026-10-19-601b54c` to `nightly-2026-11-07-ad3a5d2`) | The wasm32 dev backend (`--target=wasm32 --opt=dev`) gives each member of the lambda set of a closure call its own stack slots. The writer calls each item encoder at one place, so that frame grows with the number of encoders in the app, and each nesting level of a value uses it once. In a large app (336 KB for each level) `Cbor.encode` of `{ r : { x : List(U8) } }` overflowed a 1 MB stack: `RuntimeError: memory access out of bounds`. | The argument of the call has a name, and the call is alone in `run_slot`: the stack for each level is 3.5x smaller. It still grows with the number of encoders. `scripts/wasm_dev.sh` checks it. On `nightly-2026-10-19-601b54c`, the code of `Cbor.Entries` in the same app made a deep encode trap, so `scripts/wasm_dev.sh` builds `Entries` in a second app. For deep values in a large app, use a larger stack (`--wasm-stack-size`) or `--opt=speed`. |
| [roc-lang/roc#12918](https://github.com/roc-lang/roc/issues/12918) (all nightlies seen) | The `Dict` hash has a fixed seed for each binary, so crafted keys make a `Dict` or a `Set` quadratic (hash flooding) | Section "Guarantees", known limits |
| No issue yet (seen once) | `roc test` hung when the `encoder_for` of a recursive nominal tag union called `encode_item` on a record | No small repro yet |
| [roc-lang/roc#12309](https://github.com/roc-lang/roc/issues/12309) (does not reproduce on `nightly-2026-10-19-601b54c`; it reproduces on 10-09, 10-12 and 10-14) | A nominal or opaque type over a builtin (`Secret :: Str`) has no opt in, but the encoder still writes its value when it is in a record, a tuple or a tag. So `Cbor.encode` can write hidden data. | Back the type with a record: `Secret :: { text : Str }` |
| [roc-lang/roc#12310](https://github.com/roc-lang/roc/issues/12310) (does not reproduce on `nightly-2026-10-19-601b54c`; it reproduces on 10-09, 10-12 and 10-14) | A function with no annotation gives a value that `Json` parsed. Another function takes that value with a `Cbor.Parseable` constraint. The compiler gives "type mismatch" and "type not determined". | Annotate the first function with the full result type |
| No issue yet (seen on `nightly-2026-10-31-f7bef6b` and `nightly-2026-11-01-48d3369`) | The wasm32 dev backend (`--target=wasm32 --opt=dev`) gives `Err(OutOfRange)` for `I128.to_u8_try`, `to_u16_try`, `to_i8_try` and `to_i16_try` of a value in range | The reader goes through `I64` (section "Changes", 0.4.1) |
| No issue (seen on `nightly-2026-10-12-2664a27`, not on `nightly-2026-10-14-38a3029` or later) | Some programs that parse into a record with an optional field (`extra ?: Bool`) crash the compiler (SIGSEGV), with `Json.parse` too | Use a `Try(a, [Missing])` field, or a later nightly |

Issue drafts for the rows with no issue wait for the maintainer. The repros of #12309 and #12310 are in `research/roc-bugs/` of the `cloudflare-workers` repository.

## Layout

| Path | Content |
| --- | --- |
| `src/main.roc` | Header of the package: exposes `Cbor` |
| `src/Cbor.roc` | The format, its `expect`s and the doc comments |
| `tests/rfc8949.roc` | The RFC 8949 Appendix A vectors |
| `tests/aliases.roc` | Generic helpers with `Cbor.Readable` and `Cbor.Writable` |
| `tests/rows.roc` | SQL rows with `Cbor.sql_rows`: `Bool` from 0 and 1, `null` in a map, in a list and in a tuple, the writer |
| `tests/tags.roc` | Types of an app over tags, `Cbor.peek`, `Cbor.Value`, `ignore_tags`, `DecFromText` |
| `tests/unions.roc` | Tag unions: the option `unions`, each payload form, the errors, `Cbor.parse_union` and the tag name cases |
| `tests/ints.roc` | Small integer types: the bounds of `U8` to `I32` |
| `tests/reader.roc` | The checked reader: skipped fields, internal tags and `path_at` with the checks of `Cbor.Value`, the depth limit |
| `tests/writer.roc` | The writer: item counts, level ids, shortest heads, null in a record, `List(U8)`, `Cbor.U8Array`, `Cbor.Bytes`, `encode_with` |
| `tests/options.roc` | The reader options and each leniency |
| `tests/dict.roc` | `Dict` read and write, key types, `U128` and `I128` |
| `tests/indefinite.roc` | `IndefiniteLength` in each reader |
| `tests/value.roc` | `ValueMap`, `IntValue`, `SimpleValue`, `is_eq`, `to_hash`, `parse_prefix`, `parse_sequence`, `Cbor.Raw` |
| `tests/deterministic.roc` | Preferred floats and `key_order: Sorted` |
| `tests/truncation.roc` | One truncation rule in each reader |
| `tests/key_order.roc` | The read option `key_order: Sorted` |
| `tests/stream.roc`, `tests/stream_entries.roc`, `tests/stream_chunks.roc`, `tests/stream_writer.roc` | The stream decoders `Items`, `Entries`, `ByteChunks`, `TextChunks`, and `StreamWriter` |
| `tests/stream_adapters.roc` | An app: the adapters to the builtin `Stream` |
| `tests/wasm_dev/` | The apps (`app.roc`, `entries.roc`), the expected checksums and the small platform of `scripts/wasm_dev.sh` |
| `examples/round_trip.roc` | An app that uses each public item, reads a SQL row, reads a type over a tag, and reads tag unions of a peer. It runs on the echo host of roc, with no platform. |
| `examples/stream.roc` | An app that writes and reads with each `Stream` adapter, with a source error. The same echo host. |
| `fuzz/` | The roc-fuzz targets and the dictionary of CBOR tokens |
| `bench/` | `bench.roc` (its `dump` mode writes the fixtures of `bench/compare/`) and `baseline.txt` (`scripts/bench.sh`), `scale.roc`, `scale_read.roc` and `scale_stream.roc` (`scripts/scale.sh`) |
| `bench/compare/` | `run.py` (the runner), `rusage.c` (peak RSS of each run), `roc/compare.roc`, and the Rust, Go, Python and Zig programs |
| `differential/` | `value_dump.roc` (the Roc side) and `differential.py` (the `cbor2` side and the table of expected differences) |
| `scripts/` | `all_tests.sh`, `fuzz.sh`, `scale.sh`, `bench.sh`, `differential.sh`, `wasm_dev.sh`, `bundle.sh`, `test_bundle.sh` |
| `.roc-version` | The nightly of CI and of the releases |

The bundle has the files of `src/` that `main.roc` imports: `main.roc` and `Cbor.roc`.
Each of the two files starts with the copyright line and a reference to the UPL, because the bundle has no `LICENSE` file.
