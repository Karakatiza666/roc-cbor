# roc-cbor

CBOR (RFC 8949) for Roc, as a format of the Roc codec protocol.

You give a Roc type. The compiler derives the reader and the writer. You do not write a codec.
`Cbor` is for CBOR what the builtin `Json` is for JSON.

| Item | Value |
| --- | --- |
| Module | `Cbor` (public), with the nested types `Cbor.Bytes` and `Cbor.Value` |
| Dependencies | none |
| Compiler | the Zig compiler (nightlies of 2026). CI uses the nightly in `.roc-version` (`nightly-2026-10-19-601b54c`). Also tested on `nightly-2026-10-12-2664a27` and `nightly-2026-10-14-38a3029` for 0.2.0 and before. |
| Tests | `scripts/all_tests.sh` (section "Tests") |
| License | UPL-1.0 (`LICENSE`) |

## Use

Add the package to the header with its release URL. The release notes of each
[release](https://github.com/Karakatiza666/roc-cbor/releases) give the URL. The latest release is 0.3.0 (section "Changes"). It adds tags and dynamic values (section "Tags and dynamic values").

```roc
app [main!] { pf: platform "...", cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.3.0/Tnw6MgCr8RziwL6zZCHekkmzk715kfp83i7PxHASz9N.tar.zst" }

import cbor.Cbor
```

| Item | Type | Use |
| --- | --- | --- |
| `Cbor.encode` | `a -> List(U8)` | Write a value as CBOR. It cannot fail. |
| `Cbor.parse` | `List(U8) -> Try(a, [InvalidCbor(U64), ..errs])` | Read a value. The number in `InvalidCbor` is the byte position of the error. |
| `Cbor.parse_camel` | the same as `parse` | Read record fields in camelCase: the field `user_id` is read from the key `userId`. |
| `Cbor.parse_with` | `List(U8), Cbor.Options -> Try(a, [InvalidCbor(U64), ..errs])` | Read a value with options (table "Options") |
| `Cbor.Options` | `{ fields ?: [Snake, Camel], int_from_text ?: Bool, dec_from_text ?: Bool, ignore_tags ?: List(U64), unions ?: Cbor.Unions }` | The options of `parse_with`. Each field is optional: `{}` is the same as `parse`. |
| `Cbor.Unions` | `[External, Internal({ tag : Str, content : Str })]` | The layout of a tag union on read (section "Tag unions") |
| `Cbor.parse_union` | `Cbor, Cbor.UnionOptions, Cbor.State -> Try({ value : a, rest : Cbor.State }, [InvalidCbor(U64), ..errs])` | In a `parser_for` of your own: read one tag union with its own layout and tag name case |
| `Cbor.UnionOptions` | `{ unions ?: Cbor.Unions, tags ?: [Exact, Upper, Lower] }` | The options of `parse_union` |
| `Cbor.path_at` | `List(U8), U64 -> Try(List(Cbor.Step), [NotFound])` | The path to the item that starts at a position, for example the position of `InvalidCbor(pos)` |
| `Cbor.Step` | `[Index(U64), Key(Str)]` | One step of a path: an array index or a map key |
| `Cbor.Bytes` | `Cbor.Bytes := List(U8)` | A field that is written as a CBOR byte string. It reads a byte string or an array of integers 0 to 255. `Cbor.Bytes.(list)` or `Cbor.Bytes.from_list(list)` makes one. `bytes.to_list()` gives the list. |
| `Cbor.Parseable` | `where` alias | A function that calls `Cbor.parse` with a type variable has `where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]` |
| `Cbor.Encodable` | `where` alias | A function that calls `Cbor.encode` with a type variable has `where [a.Cbor.Encodable([])]` |
| `Cbor.Readable` | `where` alias | The short form of `Cbor.Parseable`: `where [a.Cbor.Readable(errs)]` (section "Readable and Writable") |
| `Cbor.Writable` | `where` alias | The short form of `Cbor.Encodable([])`: `where [a.Cbor.Writable]` |
| `Cbor.Value` | `Cbor.Value := [Int(I128), Float(F64), Bytes(List(U8)), Text(Str), Array(List(Cbor.Value)), Map(List((Cbor.Value, Cbor.Value))), Tag(U64, Cbor.Value), Bool(Bool), Null, Undefined, Simple(U8)]` | Any CBOR item, with its tags (section "Tags and dynamic values") |
| `Cbor.parse_cbor_tag` | `Cbor, Cbor.State -> Try({ value : U64, rest : Cbor.State }, [InvalidCbor(U64)])` | In a `parser_for` of your own: read the head of a tag. `value` is the tag number, `rest` is at the tagged item. |
| `Cbor.encode_cbor_tag` | `U64, List(U8) -> Try(List(U8), [])` | In an `encoder_for` of your own: write the head of a tag |
| `Cbor.parse_item` | `Cbor, Cbor.State -> Try({ value : a, rest : Cbor.State }, [InvalidCbor(U64), ..errs])` | In a `parser_for` of your own: read one item of the type `a` (for example the tagged item) |
| `Cbor.encode_item` | `a, List(U8) -> Try(List(U8), err)` | In an `encoder_for` of your own: write one item of the type `a` |
| `Cbor.peek` | `Cbor, Cbor.State -> Try(Cbor.Kind, [InvalidCbor(U64)])` | In a `parser_for` of your own: the kind of the next item, with no read |
| `Cbor.Kind` | `[Int, Bytes, Text, Array, Map, Tag(U64), Bool, Null, Undefined, Simple(U8), Float]` | The result of `peek` |

The other functions of `Cbor` (`parse_str`, `encode_record` and the like) are the codec protocol.
The derived `parser_for` and `encoder_for` call them. `Cbor.State` is opaque.
A `parser_for` of your own can also call them, as `Cbor.parse_str(encoding, state)`, and gives its own errors with `Cbor.invalid_value(encoding, state)`.

`examples/round_trip.roc` uses each item of the table, except `Cbor.Readable` and `Cbor.Writable` (`tests/aliases.roc` uses them).
`tests/tags.roc` uses the items for tags in more types.

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

Each field of `Cbor.Options` is optional. An omitted field has its default: `fields` is `Snake`, `int_from_text` and `dec_from_text` are `Bool.False`, `ignore_tags` is `[]`, `unions` is `External`.
So `{}`, `{ fields: Camel }`, `{ int_from_text: Bool.True }` and the full record all compile.
A record in a `let` that is not the full record needs the annotation `Cbor.Options` (section "Changes", 0.3.0 and 0.4.0).

| Field | Value | Effect |
| --- | --- | --- |
| `fields` | `Snake` (default) | A record field `user_id` reads the key `user_id` (as `parse`) |
| | `Camel` | A record field `user_id` reads the key `userId` (as `parse_camel`) |
| `int_from_text` | `Bool.False` (default) | An integer type reads CBOR integers, and floats as the table "Profile" says (as `parse` and `parse_camel`) |
| | `Bool.True` | An integer type (`U8` to `I64`) also reads text that is a canonical decimal integer in the range of the type: `0`, or `-?[1-9][0-9]*`. Other text (`-0`, `01`, `+1`, `1.0`, spaces) is an error. A `Str` field does not change. |

| `dec_from_text` | `Bool.False` (default) | A `Dec` reads an integer, a decimal fraction (tag 4) or a float (table "Profile") |
| | `Bool.True` | A `Dec` also reads text in the number form of JSON: `-?(0\|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, exact. `"12.50"` is 12.5 and `"4E+1"` is 40. More than 18 fraction digits (after the exponent), a value outside the range of a `Dec`, or other text (`01`, `+1`, `1.`, `.5`, spaces) is an error. Other types do not change. |
| `ignore_tags` | `[]` (default) | A tag is an error, except the tag 4 of a `Dec` and its tags 2 and 3 |
| | A list of tag numbers | The reader of each type skips a tag of the list before an item, and reads the item. One item can have more than one such tag. So with `[6]` the bytes `c6 f6` are `null`: no key in a record, `Err(Null)` of a `Try(a, [Null])`. A map key does not skip tags. `Cbor.peek`, `Cbor.parse_cbor_tag` and `Cbor.Value` see each tag. |
| `unions` | `External` (default) | A tag union is text, or a map of one entry: `{ "Card": payload }` (table "Data model") |
| | `Internal({ tag, content })` | A tag union is text, or a map with the tag name at the key `tag` (section "Tag unions") |

`int_from_text` is for a peer that sends a 64-bit integer as text, for example a SQL `CAST(id AS TEXT)`.
`dec_from_text` is for a peer that sends a decimal number as text, for example a SQL `NUMERIC`, or a decimal in a tag of the peer.
`ignore_tags` is for a peer that puts a tag of its own before an item that a Roc type reads with no tag.
Tag numbers are in the [IANA registry](https://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml). The package gives no tag a meaning of its own, except the tags of RFC 8949 for a `Dec` (2, 3 and 4).

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

### Tags and dynamic values

A peer can send items with tags (RFC 8949 3.4): a standard tag such as 37 (UUID), or a tag of its own from the unassigned numbers.
The package is generic: it has no type for a tag of a peer, and no geometry or time types. It gives the building blocks, and a type of your app reads its tag.

| Need | Building block | Example |
| --- | --- | --- |
| A Roc type for one tag (a UUID, a time, a point, a link of a database) | A `parser_for` of your own with `Cbor.parse_cbor_tag`, then `Cbor.parse_item` for the tagged item. An `encoder_for` with `Cbor.encode_cbor_tag`, then `Cbor.encode_item`. | `Uuid`, `Instant`, `Point`, `Link` in `tests/tags.roc` |
| A value that can be one of several kinds | `Cbor.peek` in a `parser_for` of your own, then the reader of that kind | `Cell` in `tests/tags.roc`, `Key` in `examples/round_trip.roc` |
| A value with no fixed type (a key that is text or a number, the items of a patch, a reply with any result) | `Cbor.Value`: any item, with each tag | `Link.key` in `tests/tags.roc` |
| A tag before `null` that means "no value" | `ignore_tags: [n]` | `c6 f6` with `[6]` |
| A decimal number as text in a tag | `ignore_tags: [n]` and `dec_from_text: Bool.True` | `ca 64 34 45 2b 31` (tag 10, `"4E+1"`) with `[10]` is 40 |

```roc
## A UUID (RFC 9562): the IANA tag 37 and a byte string of 16 bytes.
Uuid := List(U8).{
	parser_for : Cbor -> (Cbor.State -> Try({ value : Uuid, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		bytes = Cbor.parse_bytes(encoding, tag.rest)?
		if tag.value == 37 and bytes.value.len() == 16 {
			Ok({ value: Uuid.(bytes.value), rest: bytes.rest })
		} else {
			Err(Cbor.invalid_value(encoding, state))
		}
	}

	encoder_for : Cbor -> (Uuid, List(U8) -> Try(List(U8), []))
	encoder_for = |_| |Uuid.(bytes), out| {
		tagged = Cbor.encode_cbor_tag(37, out)?
		Cbor.encode_item(Cbor.Bytes.(bytes), tagged)
	}
}
```

`Cbor.Value`:

| Variant | CBOR | Note |
| --- | --- | --- |
| `Int(I128)` | Major type 0 or 1 | -2^64 to 2^64 - 1 reads. The writer writes a value outside that range as a bignum (tag 2 or 3). It reads back as `Tag(2, Bytes(_))` or `Tag(3, Bytes(_))`. |
| `Float(F64)` | f16, f32, f64 | The writer writes f64 |
| `Bytes(List(U8))`, `Text(Str)` | Byte string, text | The reader checks UTF-8 |
| `Array(List(Cbor.Value))` | Array | |
| `Map(List((Cbor.Value, Cbor.Value)))` | Map | Any key type. The entries keep their order, also a key that is there two times. |
| `Tag(U64, Cbor.Value)` | A tag and its item | Each tag stays, also a tag of `ignore_tags` |
| `Bool(Bool)`, `Null`, `Undefined` | `f4`, `f5`, `f6`, `f7` | |
| `Simple(U8)` | Another simple value: 0 to 19, 32 to 255 | The writer writes `Simple(20)` to `Simple(23)` as `f4` to `f7`, and `Simple(24)` to `Simple(31)` (not valid) as `f7` |

| Rule | Value |
| --- | --- |
| Equality and hash | Two values are equal when their bytes (`Cbor.encode`) are equal. `to_hash` hashes the bytes. So a `Cbor.Value` can be a `Dict` key. `Float(0.0)` and `Float(-0.0)` are not equal. `Int(1)` and `Float(1.0)` are not equal. |
| Deep nesting | The reader and the writer use a loop, not a recursion: 100,000 nested arrays do not overflow the stack |
| Profile | The same as for the other types: definite lengths only. An indefinite length, a break (`ff`), a reserved head and `f8` below 32 are errors. |
| In a record | A `null` value in a map is still no key (rule N1): a required `Cbor.Value` field is `MissingRequiredField`. A `List(Cbor.Value)` keeps each `Null`. |

### Tag unions

The writer and the default reader use the external form of `Json`: `{ "Card": { "last4": "4242" } }`.
Many peers write a tag union with an internal tag: the tag name is the value of a key of the map, `{ "kind": "Card", "last4": "4242" }`.
Since 0.4.0, the option `unions` reads this form. It is read only: `Cbor.encode` writes the external form (table "Limits of tag unions").

```roc
Pay : [Cash, Card({ last4 : Str }), Check(U64), Wire(Str, U64)]

Row : { id : Str, pay : Pay }

rows : Try(List(Row), _)
rows = Cbor.parse_with(bytes, { unions: Internal({ tag: "kind", content: "value" }) })
```

| Payloads | `External` (default) | `Internal({ tag: "kind", content: "value" })` |
| --- | --- | --- |
| 0 | `"Cash"` | `"Cash"`, or `{ "kind": "Cash" }` |
| 1, a record | `{ "Card": { "last4": "4242" } }` | `{ "kind": "Card", "last4": "4242" }`: the map itself |
| 1, another type | `{ "Check": 7 }` | `{ "kind": "Check", "value": 7 }`: the item at the content key |
| 2 or more | `{ "Wire": ["eu", 9] }` | `{ "kind": "Wire", "value": ["eu", 9] }`: an array at the content key |

| Rule | Value |
| --- | --- |
| U1. The type of the payload decides | The reader of the payload picks the form, so the same bytes `{ "kind": "Check", "value": 7 }` read as `Check({ value: 7 })` and as `Check(7)`. A record (also a type of your own with a derived record reader) reads the map itself. Each other type reads the item at the content key: also a `Dict`, a list, a tuple, a union, `Cbor.Value`, and a type of your own that starts with `Cbor.peek` or `Cbor.parse_cbor_tag`. |
| U2. One layout for each parse | `Internal` does not read the external form `{ "Card": .. }` of a tag with payloads. A tag with no payload reads as text, or as a map with the tag key. |
| U3. Keys | The keys can be in any order. Other keys are skipped. When a key is in the map two times, the first one counts. Keys are text (table "Profile"). |
| U4. A record payload and the tag key | The record reads the tag key as an unknown key, and skips it. A field of the record with the name of the tag key reads the tag name: do not use that name for a field. |
| U5. Errors | No tag key, a key that is not text, or a tag name that the type does not have: an error at the map. A tag key with a value that is not text: an error at the value. No content key for one payload that is not a record: an error at the map. The content of 2 or more payloads that is not an array of that length: an error at the content. |
| U6. The other options | `fields`, `int_from_text`, `dec_from_text` and `ignore_tags` apply in the payloads too. A tag of `ignore_tags` before the map and before the content is skipped. |
| U7. Nested unions | Each union of the parse has the layout: also a union in a payload, in a list or in a record |

#### One union type with its own options

`Cbor.parse_union` reads one tag union with the options of `Cbor.UnionOptions`, in the `parser_for` of a type of your own.
The payloads of the union, and the other unions of the parse, keep the options of the parse.
An omitted `unions` keeps the layout of the parse. An omitted `tags` is `Exact`.

```roc
## The actions of a peer: "CREATE", "UPDATE", "NOT_FOUND".
Action := [Create, Update, NotFound].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Action, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { tags: Upper }, state)?
		Ok({ value: Action.(parsed.value), rest: parsed.rest })
	}
}

## The operations of a patch: { "op": "add", "path": "/a", "value": 1 }.
Op := [Add({ path : Str, value : I64 }), Remove({ path : Str })].{
	parser_for : Cbor -> (Cbor.State -> Try({ value : Op, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { unions: Internal({ tag: "op", content: "value" }), tags: Lower }, state)?
		Ok({ value: Op.(parsed.value), rest: parsed.rest })
	}
}
```

| `tags` | Wire name | Example | Error |
| --- | --- | --- | --- |
| `Exact` (default) | The Roc tag name | `NotFound` is `NotFound` | |
| `Upper` | Upper snake case: words of `A` to `Z` and `0` to `9`, with one `_` between two words | `NOT_FOUND` is `NotFound`, `V2` is `V2` | A small letter, two `_` together, a `_` at the start or at the end, another character, empty text |
| `Lower` | Lower snake case: words of `a` to `z` and `0` to `9`, with one `_` between two words | `not_found` is `NotFound`, `add` is `Add` | The same, with a capital letter in place of a small letter |

There is no tag name case for all unions of a parse: one case rule for all unions changes each union, also a union with names in another case.
So the case is an option of one type. A structural union (`Pay` above) has no `parser_for` of its own: give it a nominal type to give it options.
When the type of `parse_union` is not a tag union, the options have no effect.

#### Limits of tag unions

| Limit | Reason | Path |
| --- | --- | --- |
| The writer writes the external form and the Roc tag names only. `Cbor.encode` does not write an internal tag or a tag name in another case. | The codec protocol gives `encode_tag` the Roc tag name and no encoding value (the same reason as for "There is no camelCase writer"), so the format cannot rename a tag or change its layout. | A hook of the compiler, `rename_tag : encoding, Str -> Str`, or the encoding value as an argument of `encode_tag`. Until then, an `encoder_for` of your own can write another form, for example with `Cbor.encode_item` of a `Cbor.Value`. |
| An exact name for one tag (serde `rename`) | Roc has no attributes on tags | A `parser_for` of your own that reads a `Str` and matches it |
| A union with no tag (serde `untagged`) | The protocol gives the format no list of the tags, and a parse cannot go back | A `parser_for` of your own with `Cbor.peek` or `Cbor.Value` |
| A type of your own as the one payload: `Cbor.peek` and `Cbor.parse_cbor_tag` see the item at the content key, and `Cbor.parse_record_start` sees the map itself | The format sees the reader that the payload calls, not the type (rule U1) | A type that reads a record after `Cbor.peek` gives `Map`: as one payload of an internal tag, it reads the item at the content key, then the map of the tag. Put such a type in a record field. |

## Changes

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
| Tag with one payload | Map of one entry: the tag name, then the payload. Read with `unions: Internal`: section "Tag unions". |
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
| `Cbor.Value` | Any item, with its tags (section "Tags and dynamic values") |

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
| Tag (major type 6) | An error, as a value (a `Dec` reads tag 4, and the tags 2 and 3 of its mantissa). It is skipped in the value of an unknown record field. A tag of the option `ignore_tags` is skipped before an item. A `parser_for` of your own reads a tag with `Cbor.parse_cbor_tag`. `Cbor.Value` reads each tag. | Not written by the derived encoders (a `Dec` writes tag 4). An `encoder_for` of your own writes one with `Cbor.encode_cbor_tag`. `Cbor.Value` writes `Tag(n, v)`. |
| Simple values other than `false`, `true`, `null`, `undefined` | An error, except into `Cbor.Value` (`Simple(n)`) | Only `Cbor.Value` writes them |
| Map key | Text only, except into `Cbor.Value` (any key) | Text only (record field names), except `Cbor.Value` |
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
| Tags and dynamic values (92 expects) | `roc test tests/tags.roc` |
| Tag unions: internal tags and `parse_union` (41 expects) | `roc test tests/unions.roc` |
| Examples | `roc check` and run each `examples/*.roc` |
| Docs | `roc docs src/main.roc` |

`scripts/fuzz.sh [runs]` runs the property tests (L1) with [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) 0.4.3.
It builds each target in `fuzz/` and runs a fixed count of inputs (default 1,000,000, seed 1, inputs of 4,096 bytes or less, the tokens of `fuzz/cbor.dict`).
roc-fuzz runs on Linux x86-64 and macOS arm64 only. A failure is saved in `.cache/fuzz/art-<target>/`.

| Target | Property |
| --- | --- |
| `fuzz/parse_never_crashes.roc` | Any bytes give a value or an error, never a crash, from `Cbor.parse`, `Cbor.parse_camel`, `Cbor.parse_with` (with `int_from_text`) and `Cbor.path_at`. Target types: a record with nested lists, a `Try(a, [Missing])` field, a `Bool` field and an optional field, `List(U64)`, `Str`, `Try(U64, [Null])`, `List((Bool, Try(I64, [Null])))`, `Cbor.Bytes`, `List(U8)`, `Dec`, `List(Dec)`, `Dict(Str, U64)`, `Cbor.Value`, and a record with `Cbor.Value` fields. Also with `ignore_tags` and `dec_from_text`, and with `unions: Internal` into a recursive union with a record, a `Dict` and a `Cbor.Value` payload, and a type with `Cbor.parse_union`. The position in `InvalidCbor` is in the input. A `Cbor.Value` that reads, reads back from its own bytes. |
| `fuzz/unions.roc` | For random values of tag unions with each kind of payload (none, a record, one item, two items, a union, a list of unions), and a type with `Cbor.parse_union` and `tags: Upper`: the external form (the form of the writer) reads back with `Cbor.parse`, and the internal form reads back with `unions: Internal`. The keys of the internal form are random: 3 names for the tag key, 3 for the content key, the tag key first or last, and another key or not. |
| `fuzz/round_trip.roc` | `Cbor.parse(Cbor.encode(v)) == Ok(v)`, and `parse_with` with `int_from_text` gives the same, for random values of a record with each supported kind of field (integers, floats with no NaN, text, bytes, `Bool`, lists, tuples, tags, `Try(_, [Missing])`, a list of `Try(_, [Null])`, a list of `Cbor.Value` of each kind to a depth of 3). Also: a record with `Err(Null)` in a field reads back with `Err(Missing)` in that field. The bytes with a tag 6 before each value (not a map key, not in a tag, not in a `Cbor.Value`) read the same item with `ignore_tags: [6]`. |

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
| `tests/tags.roc` | Types of an app over tags, `Cbor.peek`, `Cbor.Value`, the options `ignore_tags` and `dec_from_text` |
| `tests/unions.roc` | Tag unions: the option `unions`, each payload form, the errors, `Cbor.parse_union` and the tag name cases |
| `examples/round_trip.roc` | An app that uses each public item, reads a SQL row, reads a type over a tag, and reads tag unions of a peer. It runs on the echo host of roc, with no platform. |
| `fuzz/` | The roc-fuzz targets and the dictionary of CBOR tokens |
| `scripts/` | `all_tests.sh`, `fuzz.sh`, `bundle.sh`, `test_bundle.sh` |
| `.roc-version` | The nightly of CI and of the releases |

The bundle has the files of `src/` that `main.roc` imports: `main.roc` and `Cbor.roc`.
Each of the two files starts with the copyright line and a reference to the UPL, because the bundle has no `LICENSE` file.
