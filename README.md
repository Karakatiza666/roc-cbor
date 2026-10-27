# roc-cbor

CBOR (RFC 8949) for Roc, as a format of the Roc codec protocol.

You give a Roc type. The compiler derives the reader and the writer. You do not write a codec.
`Cbor` is for CBOR what the builtin `Json` is for JSON.

| Item | Value |
| --- | --- |
| Module | `Cbor` (public), with the nested type `Cbor.Bytes` |
| Dependencies | none |
| Compiler | the Zig compiler (nightlies of 2026). CI uses the nightly in `.roc-version` (`nightly-2026-10-19-601b54c`). Also tested on `nightly-2026-10-12-2664a27` and `nightly-2026-10-14-38a3029` for 0.2.0 and before. |
| Tests | `scripts/all_tests.sh` (section "Tests") |
| License | UPL-1.0 (`LICENSE`) |

## Use

Add the package to the header with its release URL. The release notes of each
[release](https://github.com/Karakatiza666/roc-cbor/releases) give the URL. The latest release is 0.2.1 (section "Changes").
The next release is 0.2.2: it changes how a `Bool` and a `null` read (section "SQL rows").

```roc
app [main!] { pf: platform "...", cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.2.1/9jD8bxEKhNu6CzBKej1nA1hzymTedJsfhiGgiMPGA1mu.tar.zst" }

import cbor.Cbor
```

| Item | Type | Use |
| --- | --- | --- |
| `Cbor.encode` | `a -> List(U8)` | Write a value as CBOR. It cannot fail. |
| `Cbor.parse` | `List(U8) -> Try(a, [InvalidCbor(U64), ..errs])` | Read a value. The number in `InvalidCbor` is the byte position of the error. |
| `Cbor.parse_camel` | the same as `parse` | Read record fields in camelCase: the field `user_id` is read from the key `userId`. |
| `Cbor.parse_with` | `List(U8), Cbor.Options -> Try(a, [InvalidCbor(U64), ..errs])` | Read a value with options (table "Options") |
| `Cbor.Options` | `{ fields ?: [Snake, Camel], int_from_text ?: Bool }` | The options of `parse_with`. Each field is optional: `{}` is the same as `parse`. |
| `Cbor.path_at` | `List(U8), U64 -> Try(List(Cbor.Step), [NotFound])` | The path to the item that starts at a position, for example the position of `InvalidCbor(pos)` |
| `Cbor.Step` | `[Index(U64), Key(Str)]` | One step of a path: an array index or a map key |
| `Cbor.Bytes` | `Cbor.Bytes := List(U8)` | A field that is written as a CBOR byte string. It reads a byte string or an array of integers 0 to 255. `Cbor.Bytes.(list)` or `Cbor.Bytes.from_list(list)` makes one. `bytes.to_list()` gives the list. |
| `Cbor.Parseable` | `where` alias | A function that calls `Cbor.parse` with a type variable has `where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]` |
| `Cbor.Encodable` | `where` alias | A function that calls `Cbor.encode` with a type variable has `where [a.Cbor.Encodable([])]` |
| `Cbor.Readable` | `where` alias | The short form of `Cbor.Parseable`: `where [a.Cbor.Readable(errs)]` (section "Readable and Writable") |
| `Cbor.Writable` | `where` alias | The short form of `Cbor.Encodable([])`: `where [a.Cbor.Writable]` |

The other functions of `Cbor` (`parse_str`, `encode_record` and the like) are the codec protocol.
The derived `parser_for` and `encoder_for` call them. An app does not call them. `Cbor.State` is opaque.

`examples/round_trip.roc` uses each item of the table, except `Cbor.Readable` and `Cbor.Writable` (`tests/aliases.roc` uses them).

```roc
Pkg : { name : Str, size : U64, tags : List(Str) }

bytes = Cbor.encode({ name: "x", size: 3, tags: ["a"] })

parsed : Try(Pkg, _)
parsed = Cbor.parse(bytes)
```

`Cbor.parse` takes its type from the context. Write the type in an annotation.
`parse` gives `Err(InvalidCbor(pos))` when the bytes are not in the profile or do not fit the type.
It gives `Err(MissingRequiredField(name))` when a record field is absent.
A type that you define (`:=` or `::`) must opt in with `parser_for : _` and `encoder_for : _` (Roc langref, "Parsers").

### Options

Each field of `Cbor.Options` is optional. An omitted field has its default: `fields` is `Snake`, `int_from_text` is `Bool.False`.
So `{}`, `{ fields: Camel }`, `{ int_from_text: Bool.True }` and the full record all compile.

| Field | Value | Effect |
| --- | --- | --- |
| `fields` | `Snake` (default) | A record field `user_id` reads the key `user_id` (as `parse`) |
| | `Camel` | A record field `user_id` reads the key `userId` (as `parse_camel`) |
| `int_from_text` | `Bool.False` (default) | An integer type reads CBOR integers, and floats as the table "Profile" says (as `parse` and `parse_camel`) |
| | `Bool.True` | An integer type (`U8` to `I64`) also reads text that is a canonical decimal integer in the range of the type: `0`, or `-?[1-9][0-9]*`. Other text (`-0`, `01`, `+1`, `1.0`, spaces) is an error. A `Str` field does not change. |

`int_from_text` is for a peer that sends a 64-bit integer as text, for example a SQL `CAST(id AS TEXT)`.

```roc
Row : { name : Str, id : I64 }

rows : Try(List(Row), _)
rows = Cbor.parse_with(bytes, { int_from_text: Bool.True })

# [{"name": "a", "id": 1.5}]: the error is at the value of "id" (position 12)
expect Cbor.path_at(bytes, 12) == Ok([Index(0), Key("id")])
```

`path_at` gives `Err(NotFound)` when no item starts at the position (a map key, or a position in the middle of an item), or when the bytes before it are not valid.
The path of the root item is `[]`.

### SQL rows

A SQL database (SQLite, Cloudflare D1, and many others) has no boolean type, and a nullable column gives NULL.
A peer that sends a row as a CBOR map gives the integers 0 and 1 for a boolean column, and `null` for a NULL.
Since 0.2.2, a row reads into a natural Roc record:

```roc
# {"name": "a", "note": null, "active": 1}
Row : { name : Str, note ?: Str, active : Bool }

row : Try(Row, _)
row = Cbor.parse(bytes)
# Ok: name is "a", note is absent (row.?note is Err(MissingField)), active is Bool.True
```

| Rule | Read | Write | Reason |
| --- | --- | --- | --- |
| B1. `Bool` | `false`, `true`, and the integers 0 and 1. The integer rules of the table "Profile" apply (any argument width; a float 0.0 or 1.0 also reads). Another integer is an error at the item. Text (`"1"`) is an error, also with `int_from_text`. | `false`, `true` | SQLite has no boolean: it gives 0 and 1. Other integers are an error, because 2 or -1 is not a boolean, and a silent `true` hides a bad column. The writer keeps the CBOR booleans: they are the exact form, and a JS peer gets a JS boolean. |
| N1. A `null` or `undefined` value in a map read as a record | The same as no key. The entry is skipped. | | One model: null means no value, and in a map no value is no key. A nullable column is naturally an optional field (`?:`) or a `Try(a, [Missing])` field. |
| N2. An optional field (`x ?: a`) | No key or `null`: absent (`.?x` is `Err(MissingField)`) | Absent: no key | Rule N1 |
| N3. A `Try(a, [Missing])` field | No key or `null`: `Err(Missing)` | `Err(Missing)`: no key | Rule N1 |
| N4. A required field (`x : a`, also `x : Try(a, [Null])`) | No key or `null`: `Err(MissingRequiredField("x"))` | | The error names the field. A `Try(a, [Null])` field is required for the compiler (see "Why `Try(a, [Null])` is not for a record field"). |
| N5. `Err(Null)` in a record field | | No key. The head of the map has the real count. | The writer and the reader have the same model: a record that `Cbor.encode` writes reads back. `Err(Null)` reads back as `Err(Missing)` or an absent optional field. |
| N6. A `null` outside a record: a list item, a tuple item, the root, a `Dict` value, a tag payload | `Err(Null)` of a `Try(a, [Null])`. Another type: an error at the `null` (`InvalidCbor(pos)`, and `Cbor.path_at(bytes, pos)` gives the path). | `Err(Null)`: `null` | An item of an array has a position, so it cannot be absent. A `Dict` keeps each entry. |

Why `Try(a, [Null])` is not for a record field:

| Fact | Effect |
| --- | --- |
| The derived parser of a record reads a key, then gives the value to the parser of the field. The format sees the key, but not the type of the field. | The format decides for each `null` in a map, the same way for each field type. |
| The compiler keeps `Null` and `Missing` apart. `Try(a, [Null, Missing])` does not compile. A `Try(a, [Null])` field is required, and an optional field or a `Try(a, [Missing])` field reads its value with the parser of `a`, which does not see a `null`. | A `null` can be absent (for `?:` and `[Missing]`) or `Err(Null)` (for `[Null]`), not both. |
| A row of a SQL table has the same keys each time, so null and no key tell the same thing. | Rule N1: absent. A record field that must tell `null` from no key is not possible. Use an optional field. |

### Readable and Writable

`Cbor.Readable(errs)` and `Cbor.Writable` are short `where` aliases. `Cbor.Parseable` and `Cbor.Encodable` stay.

| Alias | Is the same as | Use |
| --- | --- | --- |
| `a.Cbor.Writable` | `a.Cbor.Encodable([])` | A function that calls `Cbor.encode` with a type variable |
| `a.Cbor.Readable(errs)` | `a.Cbor.Parseable([InvalidCbor(U64), MissingRequiredField(Str), ..errs])` | A function that calls `Cbor.parse` with a type variable. The function can `match` on `InvalidCbor(pos)` and `MissingRequiredField(field)`. |

```roc
read : List(U8) -> Try(a, Str) where [a.Cbor.Readable(errs)]
read = |bytes|
	match Cbor.parse(bytes) {
		Ok(v) => Ok(v)
		Err(MissingRequiredField(field)) => Err("missing ${field}")
		Err(InvalidCbor(pos)) => Err("invalid at ${pos.to_str()}")
		Err(_) => Err("other")
	}
```

A function with `Readable` can call a function with `Parseable`.
`MissingRequiredField(Str)` can also be in the row of a `Parseable`: `a.Cbor.Parseable([InvalidCbor(U64), MissingRequiredField(Str), ..errs])`.
A form with no `errs` is not possible: the compiler does not allow `..` in an alias.
`tests/aliases.roc` has generic helpers for a record, `List(Row)`, `List(I64)`, `Cbor.Bytes` and a type of your own with a closed reader.

## Changes

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

## Data model

The model is the same as the model of `Json`, with two differences for SQL rows (section "SQL rows"): a `Bool` also reads 0 and 1,
and a `null` value in a map is no key. A peer that reads JSON sees the same objects.

| Roc | CBOR |
| --- | --- |
| Record | Map with text keys (major type 5) |
| Optional field, absent | The key is not in the map. The head of the map has the real count. Read: no key, or a `null` value. |
| `Try(a, [Missing])` field, `Err(Missing)` | The key is not in the map. Read: no key, or a `null` value. |
| `Try(a, [Null])` | `Ok(x)` is `x`. `Err(Null)` is `null` (`0xf6`), except in a record field: there it is no key (rule N5). |
| Tag with no payload | Text (major type 3) |
| Tag with one payload | Map of one entry: the tag name, then the payload |
| Tag with more payloads | Map of one entry: the tag name, then an array of the payloads |
| List, tuple | Array (major type 4). A tuple must have the exact length. |
| `Str` | Text (major type 3). The reader checks UTF-8. |
| `Cbor.Bytes` | Write: byte string (major type 2). Read: byte string or array of integers 0 to 255. |
| `List(U8)` | Write: array of numbers. Read: byte string or array. |
| `Bool` | Write: `0xf4`, `0xf5`. Read: also the integers 0 and 1. |
| `U8` to `U64`, `I8` to `I64` | Integer (major types 0 and 1) |
| `F32`, `F64` | Float (major type 7) |
| `Dec` | Write: integer when it has no fraction (and fits), else decimal fraction (tag 4, exact). Read: integer, decimal fraction or float. |
| `Dict(Str, v)` | Map with text keys. Read only. |

## Profile

| Item | Read | Write |
| --- | --- | --- |
| Length | Definite only. An indefinite length (`0x5f`, `0x7f`, `0x9f`, `0xbf`) is an error. | Definite |
| Argument width | Any (1, 2, 4 or 8 bytes), also longer than needed | Shortest, for integers and for text and byte string lengths |
| Container head | 1, 2, 4 or 8 bytes | 1 byte for 23 items or less, else 3 bytes (65,535 or less), else 5 bytes. So an array of 24 items has a 3 byte head. |
| Integer | Major types 0 and 1, up to 64 bits. A float with no fraction is also read as an integer when its size is 2^53 - 1 or less (a JS Number). A float of 2^53 or more is an error, because one such float is the rounded value of many integers. With `int_from_text`, also canonical decimal text (section "Options"). | Major types 0 and 1 |
| Float | f16, f32, f64. An integer is also read as a float. An `F32` reads a finite value outside the F32 range as an error (not as an infinity). | `F64` as f64 (9 bytes, never shortened). `F32` as f32 (5 bytes). |
| `null`, `undefined` | Both are the same. In a map read as a record: the entry is skipped, as if the key is not there. In another place: `Err(Null)` of a `Try(a, [Null])`, else an error. | `null`, but not as a value in a map: that entry is not written |
| Integer read as a `Bool` | 0 is `false`, 1 is `true`, with the integer rules above (also a float 0.0 or 1.0). Another integer is an error. | Not written: a `Bool` writes `false` or `true` |
| Tag (major type 6) | An error, as a value (a `Dec` reads tag 4, and the tags 2 and 3 of its mantissa). It is skipped in the value of an unknown record field. | Not written |
| Simple values other than `false`, `true`, `null`, `undefined` | An error | Not written |
| Map key | Text only | Text only (record field names) |
| Unknown record field | Skipped (the whole item) | |
| Order of map keys | Any | The order of the derived encoder. It is not the deterministic order of RFC 8949 4.2. |
| Bytes after the value | An error at the position of the first extra byte | |
| Count of an array or a map | More items than bytes after the head is an error at the head. So a bad count never makes a large list. | |
| Unknown record field, nested | Skipped with a loop, not a recursion. Deep nesting does not overflow the stack. | |
| Byte string read as a `List(U8)` | Each byte is one `U8`. A byte string read as a list of another type is an error. | |
| Array read as `Cbor.Bytes` | Each item is an integer 0 to 255 (a float with no fraction of 2^53 - 1 or less also counts, as for any integer). Text is not an item, also with `int_from_text`. Another item is an error at the item. | |
| `Dec`, integer | Major types 0 and 1: exact. | A `Dec` with no fraction from -2^64 to 2^64 - 1: major types 0 and 1. |
| `Dec`, decimal fraction | Tag 4 and an array of 2, `[exponent, mantissa]`: exact, value `mantissa * 10^exponent`. The mantissa is an integer (major types 0 and 1) or a bignum (tag 2 or 3 and a byte string, 127 bits or less, leading zero bytes allowed). More than 18 fraction digits, a value outside the range of a `Dec` (about 1.7e20), another tag, another array length, or a text mantissa is an error at the tag (or at the mantissa for its own error). | Any other `Dec`: tag 4 and `[exponent, mantissa]`, exact. The mantissa is the count of attos (10^-18) with the exponent -18. Each trailing zero digit of the mantissa moves to the exponent (the smallest exponent form). A mantissa outside the 64 bit integers is a bignum (tag 2 for positive, tag 3 for negative with the value -1 - n, a byte string of 1 to 16 bytes, no leading zero). A whole `Dec` outside 2^64 has a positive exponent, for example 10^20 is `[20, 1]`. |
| `Dec`, float | f16, f32, f64, for input from JS: the whole part plus the fraction rounded to the nearest attos (10^-18). NaN, an infinity and a value outside the range of a `Dec` are errors. Text is an error. | Not written |

Not supported. The compiler gives "missing method" when the code uses them:

| Type | Missing method |
| --- | --- |
| `U128`, `I128` | `parse_u128`, `encode_u128`, `parse_i128`, `encode_i128` |
| `Dict` with a key that is not `Str` | `parse_key_u64` and the like |
| Any `Dict` as a value to write | `encode_dict` |

Known limits:

| Limit | Reason |
| --- | --- |
| There is no camelCase writer. `Cbor.encode` writes the Roc field names (`user_id`). Only the reader has a camelCase form (`Cbor.parse_camel`). | The encode methods of the codec protocol (`encode_record` and the like) do not get the encoding value, so they cannot rename a field. |
| A `Dec` with a fraction is written with the tag 4. A peer that does not read tag 4 (a plain JS CBOR decoder) cannot use it. A whole `Dec` is a plain integer, so a SQL parameter list such as `[1]` works. | The change gives an exact `Dec` round trip. A float is not exact for a `Dec`. |
| A `Dec` that a peer sends as a float with more than 15 to 17 digits is rounded, as the float is. | A float has 53 bits. |
| `Cbor.Bytes` writes a byte string, not an array. A peer that needs an array of numbers must write the list as `List(U8)`. A byte string (a `Uint8Array` in JS) is the right input for a D1 binding: D1 stores it as a BLOB, and gives a BLOB back as a plain JS array, which `Cbor.Bytes` reads. | The reader takes both forms. The writer has one form. |
| A recursive type of your own (a tree) can overflow the stack on very deep input. | The derived parser of a recursive type calls itself once for each level of nesting. The package has no depth limit. An unknown record field is not affected: the package skips it with a loop. |

## Tests

`scripts/all_tests.sh` runs these steps with the compiler in `ROC` (default: `roc` from the path). The roc cache is in `.cache/roc`.

| Step | Command |
| --- | --- |
| Format | `roc fmt --check src tests examples fuzz` |
| Check | `roc check src/main.roc` |
| Expects of the module (132) | `roc test src/main.roc` |
| RFC 8949 Appendix A (170 expects) | `roc test tests/rfc8949.roc` |
| `Readable` and `Writable` (5 expects) | `roc test tests/aliases.roc` |
| SQL rows: `Bool` and `null` (45 expects) | `roc test tests/rows.roc` |
| Examples | `roc check` and run each `examples/*.roc` |
| Docs | `roc docs src/main.roc` |

`scripts/fuzz.sh [runs]` runs the property tests (L1) with [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) 0.4.3.
It builds each target in `fuzz/` and runs a fixed count of inputs (default 1,000,000, seed 1, inputs of 4,096 bytes or less, the tokens of `fuzz/cbor.dict`).
roc-fuzz runs on Linux x86-64 and macOS arm64 only. A failure is saved in `.cache/fuzz/art-<target>/`.

| Target | Property |
| --- | --- |
| `fuzz/parse_never_crashes.roc` | Any bytes give a value or an error, never a crash, from `Cbor.parse`, `Cbor.parse_camel`, `Cbor.parse_with` (with `int_from_text`) and `Cbor.path_at`. Target types: a record with nested lists, a `Try(a, [Missing])` field, a `Bool` field and an optional field, `List(U64)`, `Str`, `Try(U64, [Null])`, `List((Bool, Try(I64, [Null])))`, `Cbor.Bytes`, `List(U8)`, `Dec`, `List(Dec)`, `Dict(Str, U64)`. The position in `InvalidCbor` is in the input. |
| `fuzz/round_trip.roc` | `Cbor.parse(Cbor.encode(v)) == Ok(v)`, and `parse_with` with `int_from_text` gives the same, for random values of a record with each supported kind of field (integers, floats with no NaN, text, bytes, `Bool`, lists, tuples, tags, `Try(_, [Missing])`, a list of `Try(_, [Null])`). Also: a record with `Err(Null)` in a field reads back with `Err(Missing)` in that field. |

`scripts/bundle.sh` makes `dist/<hash>.tar.zst` and prints its release URL.
`scripts/test_bundle.sh` runs the examples against that file (served on `127.0.0.1`), or against a release URL, with `--replace-dep`.

`tests/rfc8949.roc` uses the public API of the package, with the hex text of the RFC.
A vector in the profile is read, and also written when the profile writes the same bytes.
A vector outside the profile is an `expect` that the parse is `Err(InvalidCbor(pos))`.

| Appendix A group | Result |
| --- | --- |
| Integers up to 64 bits, positive and negative | In the profile: read and written |
| Integers `18446744073709551616` and `-18446744073709551617` (bignums, tags 2 and 3) | Outside: error at 0 |
| `-18446744073709551616` (`0x3bffffffffffffffff`) | Fits no integer type of Roc here. Error for `I64`. |
| Floats: f16, f32, f64, with zero, infinity and NaN | In the profile: read. f32 and f64 also written. |
| `false`, `true`, `null`, `undefined` | In the profile |
| `simple(16)`, `simple(255)` | Outside: error at 0 |
| Tags 0, 1, 23, 24, 32 | Outside: error at 0 |
| Byte strings, text (also non-ASCII) | In the profile |
| Arrays, maps (text keys) | In the profile. The array of 25 items is read with the 1 byte head of the RFC. It is written with a 3 byte head. |
| Indefinite byte string, text, array, map (all 11 vectors) | Outside: error at the start of the indefinite item |
| Map with integer keys, `{1: 2, 3: 4}` | Outside: error at the first key (position 1) |

## CI and releases

| Workflow | When | Does |
| --- | --- | --- |
| `.github/workflows/tests.yaml` | Push to `main`, pull request, by hand | Makes the bundle once on Linux. Runs `scripts/all_tests.sh` and `scripts/test_bundle.sh` on Linux x64, Linux arm64 and macOS arm64. Runs `scripts/fuzz.sh` on Linux x64. |
| `.github/workflows/release.yml` | Push of a tag `X.Y.Z` or `X.Y.Z-pre` | Runs the tests, makes the bundle and the docs, and publishes the GitHub Release with `<hash>.tar.zst` and `package-docs.tar.gz`. Then runs the examples against the published URL. |

`.github/actions/setup-roc` downloads the nightly of `.roc-version` from `roc-lang/nightlies` with `gh release download`.
A tag has no `v`: roc reads the version from the URL, and the tag is a segment of the URL.

## Known compiler issues

| Issue | Effect | Workaround |
| --- | --- | --- |
| [roc-lang/roc#12309](https://github.com/roc-lang/roc/issues/12309) (does not reproduce on `nightly-2026-10-19-601b54c`; it reproduces on 10-09, 10-12 and 10-14) | A nominal or opaque type over a builtin (`Secret :: Str`) has no opt in, but the encoder still writes its value when it is in a record, a tuple or a tag. So `Cbor.encode` can write hidden data. | Back the type with a record: `Secret :: { text : Str }` |
| [roc-lang/roc#12310](https://github.com/roc-lang/roc/issues/12310) (does not reproduce on `nightly-2026-10-19-601b54c`; it reproduces on 10-09, 10-12 and 10-14) | A function with no annotation gives a value that `Json` parsed. Another function takes that value with a `Cbor.Parseable` constraint. The compiler gives "type mismatch" and "type not determined". | Annotate the first function with the full result type |
| No issue (seen on `nightly-2026-10-12-2664a27`, not on `nightly-2026-10-14-38a3029` or `nightly-2026-10-19-601b54c`) | Some programs that parse into a record with an optional field (`extra ?: Bool`) crash the compiler (SIGSEGV), with `Json.parse` too. A first build of the fuzz target had this crash. | Use a `Try(a, [Missing])` field, or a later nightly |

Source of the repros: `research/roc-bugs/` of the `cloudflare-workers` repository. Both issues reproduce on `nightly-2026-10-14-38a3029`, and neither reproduces on `nightly-2026-10-19-601b54c`.

## Layout

| Path | Content |
| --- | --- |
| `src/main.roc` | Header of the package: exposes `Cbor` |
| `src/Cbor.roc` | The format, its `expect`s and the doc comments |
| `tests/rfc8949.roc` | The RFC 8949 Appendix A vectors |
| `tests/aliases.roc` | Generic helpers with `Cbor.Readable` and `Cbor.Writable` |
| `tests/rows.roc` | SQL rows: `Bool` from 0 and 1, `null` in a map, in a list and in a tuple, the writer |
| `examples/round_trip.roc` | An app that uses each public item, and reads a SQL row. It runs on the echo host of roc, with no platform. |
| `fuzz/` | The roc-fuzz targets and the dictionary of CBOR tokens |
| `scripts/` | `all_tests.sh`, `fuzz.sh`, `bundle.sh`, `test_bundle.sh` |
| `.roc-version` | The nightly of CI and of the releases |

The bundle has the files of `src/` that `main.roc` imports: `main.roc` and `Cbor.roc`.
Each of the two files starts with the copyright line and a reference to the UPL, because the bundle has no `LICENSE` file.
