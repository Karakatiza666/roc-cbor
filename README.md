# roc-cbor

CBOR (RFC 8949) for Roc, as a format of the Roc codec protocol.

You give a Roc type. The compiler derives the reader and the writer. You do not write a codec.
`Cbor` is for CBOR what the builtin `Json` is for JSON.

| Item | Value |
| --- | --- |
| Module | `Cbor` (public), with the nested type `Cbor.Bytes` |
| Dependencies | none |
| Compiler | the Zig compiler (nightlies of 2026). CI uses the nightly in `.roc-version` (`nightly-2026-10-12-2664a27`). Also tested on `nightly-2026-10-14-38a3029`. |
| Tests | `scripts/all_tests.sh` (section "Tests") |
| License | UPL-1.0 (`LICENSE`) |

## Use

Add the package to the header with its release URL. The release notes of each
[release](https://github.com/Karakatiza666/roc-cbor/releases) give the URL. There is no release yet.

```roc
app [main!] { pf: platform "...", cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/<version>/<hash>.tar.zst" }

import cbor.Cbor
```

| Item | Type | Use |
| --- | --- | --- |
| `Cbor.encode` | `a -> List(U8)` | Write a value as CBOR. It cannot fail. |
| `Cbor.parse` | `List(U8) -> Try(a, [InvalidCbor(U64), ..errs])` | Read a value. The number in `InvalidCbor` is the byte position of the error. |
| `Cbor.parse_camel` | the same as `parse` | Read record fields in camelCase: the field `user_id` is read from the key `userId`. |
| `Cbor.Bytes` | `Cbor.Bytes := List(U8)` | A field that crosses as a CBOR byte string. `Cbor.Bytes.(list)` makes one. `bytes.to_list()` gives the list. |
| `Cbor.Parseable` | `where` alias | A function that calls `Cbor.parse` with a type variable has `where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]` |
| `Cbor.Encodable` | `where` alias | A function that calls `Cbor.encode` with a type variable has `where [a.Cbor.Encodable([])]` |

The other functions of `Cbor` (`parse_str`, `encode_record` and the like) are the codec protocol.
The derived `parser_for` and `encoder_for` call them. An app does not call them. `Cbor.State` is opaque.

`examples/round_trip.roc` uses each item of the table.

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

## Data model

The model is the same as the model of `Json`. A peer that reads JSON sees the same objects.

| Roc | CBOR |
| --- | --- |
| Record | Map with text keys (major type 5) |
| Optional field, absent | The key is not in the map. The head of the map has the real count. |
| `Try(a, [Missing])` field, absent | The key is not in the map |
| `Try(a, [Null])` | `Ok(x)` is `x`. `Err(Null)` is `null` (`0xf6`). |
| Tag with no payload | Text (major type 3) |
| Tag with one payload | Map of one entry: the tag name, then the payload |
| Tag with more payloads | Map of one entry: the tag name, then an array of the payloads |
| List, tuple | Array (major type 4). A tuple must have the exact length. |
| `Str` | Text (major type 3). The reader checks UTF-8. |
| `Cbor.Bytes` | Byte string (major type 2) |
| `List(U8)` | Write: array of numbers. Read: byte string or array. |
| `Bool` | `0xf4`, `0xf5` |
| `U8` to `U64`, `I8` to `I64` | Integer (major types 0 and 1) |
| `F32`, `F64` | Float (major type 7) |
| `Dict(Str, v)` | Map with text keys. Read only. |

## Profile

| Item | Read | Write |
| --- | --- | --- |
| Length | Definite only. An indefinite length (`0x5f`, `0x7f`, `0x9f`, `0xbf`) is an error. | Definite |
| Argument width | Any (1, 2, 4 or 8 bytes), also longer than needed | Shortest, for integers and for text and byte string lengths |
| Container head | 1, 2, 4 or 8 bytes | 1 byte for 23 items or less, else 3 bytes (65,535 or less), else 5 bytes. So an array of 24 items has a 3 byte head. |
| Integer | Major types 0 and 1, up to 64 bits. A float with no fraction is also read as an integer, so JS can send 2^53 and more as a float. | Major types 0 and 1 |
| Float | f16, f32, f64. An integer is also read as a float. | `F64` as f64 (9 bytes, never shortened). `F32` as f32 (5 bytes). |
| `null`, `undefined` | Both read as `Err(Null)` of a `Try(a, [Null])` | `null` |
| Tag (major type 6) | An error, as a value. It is skipped in the value of an unknown record field. | Not written |
| Simple values other than `false`, `true`, `null`, `undefined` | An error | Not written |
| Map key | Text only | Text only (record field names) |
| Unknown record field | Skipped (the whole item) | |
| Order of map keys | Any | The order of the derived encoder. It is not the deterministic order of RFC 8949 4.2. |
| Bytes after the value | An error at the position of the first extra byte | |
| Count of an array or a map | More items than bytes after the head is an error at the head. So a bad count never makes a large list. | |
| Unknown record field, nested | Skipped with a loop, not a recursion. Deep nesting does not overflow the stack. | |
| Byte string read as a `List(U8)` | Each byte is one `U8`. A byte string read as a list of another type is an error. | |

Not supported. The compiler gives "missing method" when the code uses them:

| Type | Missing method |
| --- | --- |
| `U128`, `I128` | `parse_u128`, `encode_u128`, `parse_i128`, `encode_i128` |
| `Dec` | `parse_dec`, `encode_dec` |
| `Dict` with a key that is not `Str` | `parse_key_u64` and the like |
| Any `Dict` as a value to write | `encode_dict` |

## Tests

`scripts/all_tests.sh` runs these steps with the compiler in `ROC` (default: `roc` from the path). The roc cache is in `.cache/roc`.

| Step | Command |
| --- | --- |
| Format | `roc fmt --check src tests examples` |
| Check | `roc check src/main.roc` |
| Expects of the module (45) | `roc test src/main.roc` |
| RFC 8949 Appendix A (169 expects) | `roc test tests/rfc8949.roc` |
| Examples | `roc check` and run each `examples/*.roc` |
| Docs | `roc docs src/main.roc` |

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
| `.github/workflows/tests.yaml` | Push to `main`, pull request, by hand | Makes the bundle once on Linux. Runs `scripts/all_tests.sh` and `scripts/test_bundle.sh` on Linux x64, Linux arm64 and macOS arm64. |
| `.github/workflows/release.yml` | Push of a tag `X.Y.Z` or `X.Y.Z-pre` | Runs the tests, makes the bundle and the docs, and publishes the GitHub Release with `<hash>.tar.zst` and `package-docs.tar.gz`. Then runs the examples against the published URL. |

`.github/actions/setup-roc` downloads the nightly of `.roc-version` from `roc-lang/nightlies` with `gh release download`.
A tag has no `v`: roc reads the version from the URL, and the tag is a segment of the URL.

## Known compiler issues

| Issue | Effect | Workaround |
| --- | --- | --- |
| [roc-lang/roc#12309](https://github.com/roc-lang/roc/issues/12309) | A nominal or opaque type over a builtin (`Secret :: Str`) has no opt in, but the encoder still writes its value when it is in a record, a tuple or a tag. So `Cbor.encode` can write hidden data. | Back the type with a record: `Secret :: { text : Str }` |
| [roc-lang/roc#12310](https://github.com/roc-lang/roc/issues/12310) | A function with no annotation gives a value that `Json` parsed. Another function takes that value with a `Cbor.Parseable` constraint. The compiler gives "type mismatch" and "type not determined". | Annotate the first function with the full result type |

Source of the repros: `research/roc-bugs/` of the `cloudflare-workers` repository. Both issues reproduce on `nightly-2026-10-14-38a3029`.

## Layout

| Path | Content |
| --- | --- |
| `src/main.roc` | Header of the package: exposes `Cbor` |
| `src/Cbor.roc` | The format, its `expect`s and the doc comments |
| `tests/rfc8949.roc` | The RFC 8949 Appendix A vectors |
| `examples/round_trip.roc` | An app that uses each public item. It runs on the echo host of roc, with no platform. |
| `scripts/` | `all_tests.sh`, `bundle.sh`, `test_bundle.sh` |
| `.roc-version` | The nightly of CI and of the releases |

The bundle has the files of `src/` that `main.roc` imports: `main.roc` and `Cbor.roc`.
