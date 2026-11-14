# Copyright © 2026 Heorhii Bulakh and subsequent roc-cbor authors <github.com/Karakatiza666/roc-cbor/graphs/contributors>
# Licensed under the Universal Permissive License (UPL), Version 1.0. See LICENSE.

## CBOR (RFC 8949) as a format of the Roc codec protocol. The derived `parser_for` and
## `encoder_for` of a type read and write it, as they do for `Json`.
##
## ```roc
## bytes = Cbor.encode({ name: "x", size: 3.U64 })
## parsed : Try({ name : Str, size : U64 }, _)
## parsed = Cbor.parse(bytes)
## ```
##
## Data model: the same as `Json`. A record is a map with text keys, a tag with no payload is
## text, a tag with payloads is a map of one entry, a list and a tuple are arrays. So a peer
## that reads JSON sees the same objects from this format.
##
## Profile: the writer writes definite lengths only. The reader reads an indefinite length only with `IndefiniteLength`. The reader is strict by default (RFC 8949 4.2.1 heads, no duplicate keys),
## and each lenient read is a `Cbor.Leniency` in the option `allow`. Integers are major types 0 and 1.
## Floats are f16, f32 or f64 when read, and the shortest of the three with the same value when written (RFC 8949 4.1). An integer reads as a float only when the float
## has the same value. `null` and `undefined` are not the same.
##
## Null: `Err(Null)` writes `null`, also in a record field, and reads back. In a map read as a record, the value of each
## key goes to the reader of its field: a `Try(a, [Null])` field reads `null` as `Err(Null)`, a `Cbor.Value` field as `Null`,
## and another field type gives an error at the `null`. An absent optional field and `Err(Missing)` write no key.
## SQL rows: `allow: Cbor.sql_rows` gives the rules of 0.4. A `Bool` also reads 0 and 1, and a `null` value in a map is the same as no key.
##
## A `List(U8)` reads a byte string, or an empty array, and writes a byte string (major type 2).
## `Cbor.Bytes` is the fast type for binary data: one append on write, a part of the input on read.
## `Cbor.U8Array` writes an array of integers 0 to 255, and reads only that.
## A `Dec` writes as an integer when it has no fraction, else as a decimal fraction (tag 4, exact). It reads an integer, a decimal fraction or a float.
##
## Tags: a type of your own reads a tag with `parse_cbor_tag` and `parse_item` in its `parser_for`, and writes one with
## `encode_tagged`. `peek` gives the kind of the next item. `Cbor.Value` is any item, with its tags.
## The option `ignore_tags` skips the tags of a list before an item.
##
## Tag unions: the option `unions` reads an internal tag, `{ "kind": "Card", "last4": "4242" }` (read only).
## `parse_union` in a `parser_for` of your own gives the options of one union type, also a case for its tag names.
Cbor :: {
	# The case of the record keys that `rename_field` gives: on write only. A parse has `Snake`, so that
	# `MissingRequiredField` names the Roc field. The case of a parse is `read.camel`.
	fields : [Snake, Camel],
	# The rules of the typed readers of a parse.
	read : ReadRules,
	ignore_tags : List(U64),
	# The layout of each tag union of the parse.
	unions : [External, Internal({ tag : Str, content : Str })],
	# In the map at `at` of an internal tag: a reader that is not a record reads the item at `to` (one payload).
	# `tag` is the position of the tag key, which is not an unknown field.
	content : { at : U64, to : U64, tag : U64 },
	# The options of the one union at `at`, from `parse_union`.
	next : { at : U64, unions : [External, Internal({ tag : Str, content : Str })], tags : [Exact, Upper, Lower] },
}.{

	## The options of `parse_with`. Each field is optional: `{}` is the same as `parse`.
	##
	## | Field | Default | Value |
	## | --- | --- | --- |
	## | `fields` | `Snake` | `Snake`: a record field `user_id` reads the key `user_id`. `Camel`: it reads the key `userId`. A key that is the key of two fields (`a_1` and `a1`) is an error at the key. |
	## | `allow` | `[]` | The lenient reads (`Cbor.Leniency`). `[]` is strict. `Cbor.sql_rows` gives the rules of 0.4. |
	## | `duplicate_keys` | `Reject` | A key that is two times in one map. `Reject`: an error at the second key. `First`, `Last`: that instance is read, and the other ones are skipped. The same rule for each map: a record, a `Dict`, an internal tag, a `Cbor.Value`. Keys are the same when they are the same `Cbor.Value` (`is_eq`). |
	## | `key_order` | `Any` | `Any`: the keys of a map can come in any order. `Sorted`: the keys of each map must be in the order of RFC 8949 4.2.1, the bytewise order of the deterministic encoding of each key (the order of `encode_with(value, { key_order: Sorted })`). A key that comes before the key in front of it in this order is an error at the key. Equal keys are adjacent, and `duplicate_keys` applies to them. The same rule for each map. |
	## | `unknown_fields` | `Skip` | A key of a map read as a record that is not a field of the record. `Skip`: the entry is skipped. `Reject`: an error at the key. |
	## | `max_depth` | 512 | The most arrays, maps and tags that an item can be in. More is an error at the head that goes too deep. |
	## | `max_items` | no limit | The most data items in the root item: each key, value, array item, tag and tagged item counts. More is an error at the first item over the limit. |
	## | `ignore_tags` | `[]` | The tag numbers that the readers of the types skip: an item with a tag of the list reads as the item with no tag. So with `[6]`, the bytes `c6 f6` read as `null`. `Cbor.peek`, `Cbor.parse_cbor_tag` and `Cbor.Value` see each tag. |
	## | `unions` | `External` | The layout of a tag union (`Cbor.Unions`). `External`: `{ "Card": payload }`. `Internal({ tag, content })`: `{ tag: "Card", ..payload }`. |
	## | `max_buffer` | 16,777,216 | Streams only (`Cbor.Items`, `Cbor.Entries`): the most bytes of one item; for `Cbor.Entries`, of the open item, the held entry and the key memory together. An item that is not whole in its first `max_buffer` bytes, with more bytes after them, is the error `TooLarge(pos)` at the start of the item. `parse_with`, `parse_prefix` and `parse_sequence` ignore it. |
	##
	## The `Cbor.Value` reader reads each item as it is: `allow` does not change it, except `PaddedNumbers` and `IndefiniteLength`.
	## `duplicate_keys` applies to it too.
	Options : {
		fields ?: [Snake, Camel],
		allow ?: List(Cbor.Leniency),
		duplicate_keys ?: [Reject, First, Last],
		key_order ?: [Any, Sorted],
		unknown_fields ?: [Skip, Reject],
		max_depth ?: U64,
		max_items ?: U64,
		ignore_tags ?: List(U64),
		unions ?: Cbor.Unions,
		max_buffer ?: U64,
	}

	## A lenient read: a tag in the option `allow` of `Cbor.Options`. With no tag, the reader is strict.
	##
	## | Tag | Strict | With the tag |
	## | --- | --- | --- |
	## | `BoolFromInt` | A `Bool` reads only `false` and `true` | A `Bool` also reads the integers 0 and 1. A float 0.0 or 1.0 needs `FloatToInt` too. |
	## | `FloatToInt` | An integer type reads only major types 0 and 1 | Also a float with no fraction, of size 2^53 - 1 or less (a JS Number). A larger float can be the rounded value of many integers, so it is an error. |
	## | `IntFromText` | Text is an error for an integer type | An integer type (`U8` to `I128`) also reads text that is a canonical decimal integer in its range: `0`, or `-?[1-9][0-9]*`. Other text is an error. |
	## | `DecFromText` | Text is an error for a `Dec` | A `Dec` also reads text in the number form of JSON, `-?(0\|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, exactly. `4E+1` is 40. More than 18 fraction digits, or a value outside the range of a `Dec`, is an error. |
	## | `NullAsAbsent` | A `null` value in a map read as a record goes to the reader of the field | The entry is skipped: the same as no key. An optional field is absent, a `Try(a, [Missing])` field is `Err(Missing)`, a required field is `MissingRequiredField`. The keys are counted first: `{a: null, a: 5}` is still a duplicate key. |
	## | `UndefinedAsNull` | `undefined` is an error for each type, except `Cbor.Value` | `undefined` reads as `null`, also for `NullAsAbsent` |
	## | `PaddedNumbers` | A number that uses more bytes than it needs is an error, also in a skipped item: an integer, the length of a text or byte string, the count of an array or map, a tag number (RFC 8949 4.2.1). A bignum with a leading zero byte, or with a value that fits 64 bits, is an error (RFC 8949 4.2.2, preferred serialization). | These numbers also read. roc-cbor 0.4 and some other encoders write them. Float widths are not changed by this leniency: each float width reads in all modes. |
	## | `BytesFromArray` | A `List(U8)` reads a byte string or an empty array, not an array of integers 0 to 255 | A `List(U8)` also reads an array of integers 0 to 255. The writer writes a list as a byte string only when each item is a `U8`, so an array with another item (`[1, null]` for a `List(Try(U8, [Null]))`) reads with no option. `Cbor.U8Array` always reads an array. |
	## | `BytesFromBase64` | A `List(U8)` and a `Cbor.Bytes` do not read text | A `List(U8)` and a `Cbor.Bytes` also read text that is base64 (RFC 4648 4): the alphabet `A-Z a-z 0-9 + /`, with `=` padding to a multiple of 4 characters. White space, base64url (`-` `_`), padding that is missing or not at the end, and unused bits before the padding that are not zero (RFC 4648 3.5) are errors at the text. So each byte list has one text. `""` is `[]`. `Str`, `Cbor.Value` and `Cbor.U8Array` do not change. The writer writes a byte string. |
	## | `IndefiniteLength` | An indefinite length (RFC 8949 3.2) is an error, also in a skipped item | Arrays, maps, byte strings and text of indefinite length read, each with its break. Each chunk of a byte string or text is a definite string of the same major type, and the chunks of text are each valid UTF-8. The readers join the chunks. A `Cbor.Value` is the same as from the definite form, so it writes the definite form. |
	##
	## `PaddedNumbers` also reads a bignum (tag 2 or 3) of a `U128`, an `I128` or the mantissa of a `Dec` with leading zero bytes,
	## or with a value that fits major type 0 or 1. Strict, a bignum is the preferred serialization (RFC 8949 4.2.2): more than 8 bytes, no leading zero byte.
	##
	## A key of a `Dict` reads only the form that the writer writes for its value (with any head width and float width that the
	## walk accepts), so two different keys of the map never give one Roc key. A lenient read does not apply to a key: with `BoolFromInt`,
	## the key `0` of a `Dict(Bool, v)` is still an error.
	Leniency : [BoolFromInt, FloatToInt, IntFromText, DecFromText, NullAsAbsent, UndefinedAsNull, PaddedNumbers, BytesFromArray, BytesFromBase64, IndefiniteLength]

	## The lenient reads for rows of a SQL database (SQLite, D1), which has no boolean and gives `NULL` for a nullable column:
	## `BoolFromInt`, `FloatToInt`, `NullAsAbsent`, `UndefinedAsNull`, `BytesFromArray`. With it, the reader reads as 0.4 did,
	## except for duplicate keys and padded numbers (`PaddedNumbers`). Use `{ allow: Cbor.sql_rows }`.
	sql_rows : List(Cbor.Leniency)
	sql_rows = [BoolFromInt, FloatToInt, NullAsAbsent, UndefinedAsNull, BytesFromArray]

	## The layout of a tag union on read. The writer always writes `External`.
	##
	## | Payloads | `External` (default) | `Internal({ tag: "kind", content: "value" })` |
	## | --- | --- | --- |
	## | 0 | `"Cash"` | `"Cash"`, or `{ "kind": "Cash" }` |
	## | 1, a record | `{ "Card": { "last4": "4242" } }` | `{ "kind": "Card", "last4": "4242" }`: the map itself |
	## | 1, another type | `{ "Check": 7 }` | `{ "kind": "Check", "value": 7 }` |
	## | 2 or more | `{ "Wire": ["eu", 9] }` | `{ "kind": "Wire", "value": ["eu", 9] }` |
	##
	## The type of the payload decides between "a record" and "another type", so the same bytes read
	## `Card({ value: 7 })` and `Check(7)`. A `Dict` is another type. The keys of the map can be in any
	## order, and other keys are skipped. `Internal` does not read the `External` form of a tag with payloads.
	Unions : [External, Internal({ tag : Str, content : Str })]

	## The options of one tag union type, for `Cbor.parse_union`. An omitted field keeps the value of
	## the parse (`unions`), or is `Exact` (`tags`).
	##
	## | Field | Value | Effect |
	## | --- | --- | --- |
	## | `unions` | `Cbor.Unions` | The layout of this union |
	## | `tags` | `Exact` | The wire name is the Roc tag name: `NotFound` |
	## | | `Upper` | The wire name is in upper snake case: `NOT_FOUND` reads as `NotFound`. `NotFound` and `NOT__FOUND` are errors. |
	## | | `Lower` | The wire name is in lower snake case: `not_found` reads as `NotFound`, `add` as `Add` |
	UnionOptions : { unions ?: Cbor.Unions, tags ?: [Exact, Upper, Lower] }

	## One step of the path that `path_at` gives: an array index or a map key.
	Step : [Index(U64), Key(Str)]

	## The kind of the next item, from its head (RFC 8949 3). `Cbor.peek` gives it.
	## `Int` is major type 0 or 1. `Tag(number)` is major type 6. `Simple(n)` is a simple value other than
	## `false`, `true`, `null` and `undefined`. `Float` is f16, f32 or f64.
	Kind : [Int, Bytes, Text, Array, Map, Tag(U64), Bool, Null, Undefined, Simple(U8), Float]

	## The checked token reader of a parse: the bytes, the read position and the rules of the checks.
	## The derived parsers pass it from step to step. Its fields are hidden.
	Reader :: {
		bytes : List(U8),
		pos : U64,
		# The bytes left in a byte string read as a `List(U8)`.
		raw : U64,
		# The position of the last array that `parse_list_start` read: a `List(U8)` reads its first item only with `BytesFromArray`.
		array : U64,
		# In a byte string of indefinite length read as a `List(U8)`: `raw` is the bytes left in the current chunk.
		chunks : Bool,
		# The lists that most parses do not use (`ReaderMemo`). `Plain` when each one is empty.
		memo : [Plain, Memo(Box(ReaderMemo))],
	}

	## The output of an encode. The derived `encoder_for` of a type passes it from item to item, and
	## an `encoder_for` of your own gets it. Its fields are hidden: each item goes through an `encode_*`
	## method, which counts it. So each array, map and tag gets exactly the items that its head declares.
	Writer :: {
		out : List(U8),
		st : {
			# The places of the current level that no `add_*` call has opened yet.
			left : U64,
			# The open place has no item yet: the next item takes it (`begin`). A place is opened by `slot`.
			owe : Bool,
			# The current list: its head is still to write (Pending), or it is a byte string (Bytes).
			list : [Plain, Pending(U64), Bytes({ start : U64, count : U64 })],
			# The id of the current level, and the next free id. A callback must give back a writer of its own level.
			level : U64,
			next : U64,
			# A count mismatch, or a writer of another level. The encode gives `Err(CountMismatch)`.
			bad : Bool,
			# Two fields of one record with the same camelCase key (`a_1` and `a1`). `encode_with` gives `Err(DuplicateMapKey)`.
			dup : Bool,
			# The bytes of old record heads, removed at the end of the encode.
			gaps : List({ at : U64, len : U64 }),
			fields : [Snake, Camel],
		},
	}

	## The writer inside a list, a tuple, a record or a tag. Only the `add` callback of
	## `encode_list` (and the like) can write to it, one item for each call.
	Container :: Cbor.Writer

	## The options of `encode_with`. Each field is optional: `{}` is the same as `encode`.
	##
	## | Field | Default | Value |
	## | --- | --- | --- |
	## | `fields` | `Snake` | `Snake`: a record field `user_id` writes the key `user_id`. `Camel`: it writes the key `userId`. |
	## | `key_order` | `Given` | `Given`: the entries of each map in the order of the encoder (a record: the order of the fields, a `Dict`: its order). `Sorted`: the deterministic encoding of RFC 8949 4.2.1, see below. |
	##
	## The writer always writes the shortest heads, definite lengths and the shortest floats. With `key_order: Sorted`, the entries of each map
	## (a record, a `Dict`, a `Cbor.Value` map, a map of an `encoder_for` of your own, also a map in a `Cbor.Raw`) are sorted by the bytes of
	## their keys, in bytewise order: `"b"` (`61 62`) comes before `"aa"` (`62 61 61`). So two values that are equal write the same bytes.
	## Two entries with the same key bytes in one map give `Err(DuplicateMapKey)`: an `encoder_for` of your own, or
	## two NaN keys of a `Dict(F64, v)`. A sort costs O(k log k) for a map of k entries. With `Given`, only the keys of a record
	## are checked, and only with `fields: Camel`: two fields with one camelCase key (`a_1` and `a1`) give `Err(DuplicateMapKey)`.
	## A map that an `encoder_for` of your own writes with `Cbor.encode_dict` is not checked with `Given`.
	WriteOptions : { fields ?: [Snake, Camel], key_order ?: [Given, Sorted] }

	## An encoder of one item (`new`) or of an RFC 8742 sequence (`sequence`), one level at a time, for data that is
	## larger than memory. Each step gives the bytes of that step and the next writer. The writer keeps no output.
	##
	## | Step | Bytes |
	## | --- | --- |
	## | `open_array`, `open_map` | The head: `Count(n)` is the shortest head, `Indefinite` is `9f` or `bf` |
	## | `open_bytes`, `open_text` | The head: `Length(n)` is the shortest head (9 bytes for 2^32 or more), `Indefinite` is `5f` or `7f` |
	## | `item` | One whole item, from `Cbor.encode_with` with the options of the writer |
	## | `entry` | The key and the value of one map entry |
	## | `bytes_chunk`, `text_chunk` | Definite: the data itself (a byte string: the same list, no copy). Indefinite: one definite chunk. |
	## | `close` | `ff` for an indefinite level, else no bytes |
	##
	## A step that is not valid gives `Err(CountMismatch)` and no bytes: a place that has no room (too many items or bytes,
	## or a second root item of `new`), an item or a level in a byte string or a text, a chunk in an array or a map,
	## an `entry` that is not at a key place, a `close` before the count or the length is done, or of an indefinite map
	## with a key and no value. The writer before the error is not changed, so it can do another step.
	## Each level must get its `close`, also a definite level. `finish` checks that each level is closed.
	##
	## With `key_order: Sorted`, each map key of a streamed map must come after the key before it, in the order of `encode_with`
	## (the bytes of the key): a smaller key is `Err(KeyOutOfOrder)`, an equal key is `Err(DuplicateMapKey)`. A level that
	## opens at a key place is `Err(CountMismatch)`, because its key has no bytes to compare. With `Given`, a streamed map is not checked.
	StreamWriter :: StreamState.{

		## A writer of one root item. The options apply in each item (`fields`, `key_order`), and `key_order: Sorted` also checks the keys of a streamed map.
		new : Cbor.WriteOptions -> Cbor.StreamWriter
		new = |options| stream_writer(One, options)

		## A writer of an RFC 8742 sequence: zero or more root items, one after the other.
		sequence : Cbor.WriteOptions -> Cbor.StreamWriter
		sequence = |options| stream_writer(Sequence, options)

		## Opens an array. `Count(n)`: `n` items, then `close`. `Indefinite`: items until `close`.
		open_array : Cbor.StreamWriter, [Count(U64), Indefinite] -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch])
		open_array = |w, size| open_level(w, Array, 4, size)

		## Opens a map. `Count(n)`: `n` entries (2n items), then `close`. `Indefinite`: entries until `close`.
		open_map : Cbor.StreamWriter, [Count(U64), Indefinite] -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch])
		open_map = |w, size| open_level(w, Map, 5, size)

		## Opens a byte string. `Length(n)`: `n` bytes in `bytes_chunk` steps, then `close`. `Indefinite`: chunks until `close`.
		open_bytes : Cbor.StreamWriter, [Length(U64), Indefinite] -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch])
		open_bytes = |w, size| open_level(w, ByteString, 2, string_size(size))

		## Opens a text. `Length(n)`: `n` bytes of UTF-8 in `text_chunk` steps, then `close`. `Indefinite`: chunks until `close`.
		open_text : Cbor.StreamWriter, [Length(U64), Indefinite] -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch])
		open_text = |w, size| open_level(w, TextString, 3, string_size(size))

		## One whole item in the current place. In a streamed map, items alternate: a key, then its value.
		item : Cbor.StreamWriter, a -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch, DuplicateMapKey, KeyOutOfOrder, ..err])
			where [a.Encodable([CountMismatch, DuplicateMapKey, KeyOutOfOrder, ..err])]
		item = |w, value| {
			Cbor.StreamWriter.(s) = w
			place = item_place(s)?
			bytes = Cbor.encode_with(value, { fields: s.fields, key_order: if (s.sorted) Sorted else Given })?
			Ok({ bytes, writer: Cbor.StreamWriter.(put_item(s, place, bytes)?) })
		}

		## One entry of the current streamed map: the key, then the value. Only at a key place.
		entry : Cbor.StreamWriter, k, v -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch, DuplicateMapKey, KeyOutOfOrder, ..err])
			where [k.Encodable([CountMismatch, DuplicateMapKey, KeyOutOfOrder, ..err]), v.Encodable([CountMismatch, DuplicateMapKey, KeyOutOfOrder, ..err])]
		entry = |w, key, value| {
			Cbor.StreamWriter.(s) = w
			place = item_place(s)?
			match place {
				Key(_) => {}
				_ => return Err(CountMismatch)
			}
			options = { fields: s.fields, key_order: if (s.sorted) Sorted else Given }
			key_bytes = Cbor.encode_with(key, options)?
			value_bytes = Cbor.encode_with(value, options)?
			keyed = put_item(s, place, key_bytes)?
			after = put_item(keyed, item_place(keyed)?, [])?
			Ok({ bytes: key_bytes.concat(value_bytes), writer: Cbor.StreamWriter.(after) })
		}

		## Data of the current byte string. Definite: `bytes` is `data` itself, with no copy, and the data must not go past the length.
		## Indefinite: `bytes` is one definite chunk (a head and `data`).
		bytes_chunk : Cbor.StreamWriter, List(U8) -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch])
		bytes_chunk = |w, data| {
			Cbor.StreamWriter.(s) = w
			len = data.len()
			match chunk_place(s, ByteString, len)? {
				Definite(next) => Ok({ bytes: data, writer: Cbor.StreamWriter.(next) })
				Chunk => Ok({ bytes: put_head(List.with_capacity(len + 9), 2, len).concat(data), writer: w })
			}
		}

		## Text of the current text: the same rules as `bytes_chunk`, with the length in bytes of UTF-8. A `Str` is valid UTF-8,
		## so each chunk is too.
		text_chunk : Cbor.StreamWriter, Str -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch])
		text_chunk = |w, text| {
			Cbor.StreamWriter.(s) = w
			len = text.count_utf8_bytes()
			match chunk_place(s, TextString, len)? {
				Definite(next) => Ok({ bytes: text.to_utf8(), writer: Cbor.StreamWriter.(next) })
				Chunk => Ok({ bytes: put_text(List.with_capacity(len + 9), text), writer: w })
			}
		}

		## Closes the current level. A definite level must have all its items or bytes, and gives no bytes.
		## An indefinite level gives `ff`. An indefinite map must not have a key with no value.
		close : Cbor.StreamWriter -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch])
		close = |w| {
			Cbor.StreamWriter.(s) = w
			match s.open.last() {
				Ok(level) if !level.half and level.left == Count(0) => Ok({ bytes: [], writer: Cbor.StreamWriter.({ ..s, open: s.open.drop_last(1) }) })
				Ok(level) if !level.half and level.left == Indefinite => Ok({ bytes: [0xff], writer: Cbor.StreamWriter.({ ..s, open: s.open.drop_last(1) }) })
				_ => Err(CountMismatch)
			}
		}

		## `Ok` when each level is closed, and the root item is written (`new`). A sequence can end after any root item.
		finish : Cbor.StreamWriter -> Try({}, [CountMismatch])
		finish = |Cbor.StreamWriter.(s)| if (s.open.is_empty() and (s.done or s.root == Sequence)) Ok({}) else Err(CountMismatch)

		## A stream of the bytes of one top-level array of the items of `source`: the head, the bytes of each item, and
		## `ff` for `Indefinite`. `Count(n)` with more items than `n` is `Err(CountMismatch)` at the item after the n-th,
		## and with fewer at the end of `source`.
		##
		## Each writer adapter (`array_stream`, `map_stream`, `sequence_stream`, `bytes_stream`, `text_stream`) gives
		## the bytes of each step of a `Cbor.StreamWriter` that has bytes, and pulls a value of `source` only after it
		## gave the bytes before it. A source error `e` is `Err(Input(e))`, then the end. A writer error ends the stream
		## too: then the bytes so far are not a whole item.
		array_stream : Stream(Try(a, e)), [Count(U64), Indefinite], Cbor.WriteOptions -> Stream(Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err])) where [a.Encodable([CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err])]
		array_stream = |source, size, options|
			encode_stream(
				Cbor.StreamWriter.new(options),
				source,
				{
					open: |w| w.open_array(size).map_err(|CountMismatch| CountMismatch),
					put: |w, value| w.item(value),
					close: |w| w.close().map_err(|CountMismatch| CountMismatch),
				},
			)

		## A stream of the bytes of one top-level map of the entries of `source`. `Count(n)` is n entries. With
		## `key_order: Sorted`, each key must come after the key before it: else `Err(KeyOutOfOrder)`, or
		## `Err(DuplicateMapKey)` for an equal key.
		map_stream : Stream(Try((k, v), e)), [Count(U64), Indefinite], Cbor.WriteOptions -> Stream(Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err])) where [k.Encodable([CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err]), v.Encodable([CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err])]
		map_stream = |source, size, options|
			encode_stream(
				Cbor.StreamWriter.new(options),
				source,
				{
					open: |w| w.open_map(size).map_err(|CountMismatch| CountMismatch),
					put: |w, (key, value)| w.entry(key, value),
					close: |w| w.close().map_err(|CountMismatch| CountMismatch),
				},
			)

		## A stream of the bytes of an RFC 8742 sequence of the items of `source`, one item after the other.
		sequence_stream : Stream(Try(a, e)), Cbor.WriteOptions -> Stream(Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err])) where [a.Encodable([CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(e), ..err])]
		sequence_stream = |source, options|
			encode_stream(
				Cbor.StreamWriter.sequence(options),
				source,
				{
					open: |w| Ok({ bytes: [], writer: w }),
					put: |w, value| w.item(value),
					close: |w| Ok({ bytes: [], writer: w }),
				},
			)

		## A stream of the bytes of one top-level byte string of the chunks of `source`. `Length(n)`: the head, then
		## each chunk itself (no copy); more or fewer bytes than `n` is `Err(CountMismatch)`. `Indefinite`: `5f`, a
		## definite chunk for each chunk of `source`, and `ff`.
		bytes_stream : Stream(Try(List(U8), e)), [Length(U64), Indefinite] -> Stream(Try(List(U8), [CountMismatch, Input(e)]))
		bytes_stream = |source, size|
			encode_stream(
				Cbor.StreamWriter.new({}),
				source,
				{
					open: |w| w.open_bytes(size).map_err(|CountMismatch| CountMismatch),
					put: |w, chunk| w.bytes_chunk(chunk).map_err(|CountMismatch| CountMismatch),
					close: |w| w.close().map_err(|CountMismatch| CountMismatch),
				},
			)

		## A stream of the bytes of one top-level text of the chunks of `source`, as `bytes_stream`. `Length(n)` is
		## a count of bytes.
		text_stream : Stream(Try(Str, e)), [Length(U64), Indefinite] -> Stream(Try(List(U8), [CountMismatch, Input(e)]))
		text_stream = |source, size|
			encode_stream(
				Cbor.StreamWriter.new({}),
				source,
				{
					open: |w| w.open_text(size).map_err(|CountMismatch| CountMismatch),
					put: |w, chunk| w.text_chunk(chunk).map_err(|CountMismatch| CountMismatch),
					close: |w| w.close().map_err(|CountMismatch| CountMismatch),
				},
			)
	}

	## The error of every read: the position of the first byte that is not valid, not in the profile, or does not
	## fit the type (`InvalidCbor`), or a required field of a record that is absent, by its Roc name
	## (`MissingRequiredField`). The codec protocol makes it the one error of every operation of a derived parser.
	Error : [InvalidCbor(U64), MissingRequiredField(Str)]

	## A type that `Cbor.parse` can read. Use it in the `where` clause of a function that calls
	## `Cbor.parse` with a type variable: `where [a.Cbor.Parseable(Cbor.Error)]`.
	a.Parseable(errs) :
		where [
			a.parser_for : Cbor -> (Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, errs)),
		]

	## A type that `Cbor.encode` can write. Use it in the `where` clause of a function that calls
	## `Cbor.encode` with a type variable: `where [a.Cbor.Encodable([])]`.
	a.Encodable(err) :
		where [
			a.encoder_for : Cbor -> (a, Cbor.Writer -> Try(Cbor.Writer, err)),
		]

	## The short form of `Cbor.Parseable(Cbor.Error)`: `where [a.Cbor.Readable]`.
	a.Readable :
		where [
			a.parser_for : Cbor -> (Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, Cbor.Error)),
		]

	## The short form of `Cbor.Encodable([])`: a type that `Cbor.encode` can write. Use it as
	## `where [a.Cbor.Writable]`.
	a.Writable :
		where [
			a.encoder_for : Cbor -> (a, Cbor.Writer -> Try(Cbor.Writer, [])),
		]

	## A list of bytes that writes as an array of integers 0 to 255, for a peer that needs that form.
	## A `List(U8)` writes as a byte string. It reads an array of integers 0 to 255.
	## `Cbor.U8Array.(list)` makes one, and `array.to_list()` gives the list back.
	U8Array := List(U8).{

		## Two values are equal when their lists are equal.
		is_eq : _

		## Reads an array (major type 4) of integers 0 to 255, also with no option. Another item is an error at the item.
		## A float item needs `FloatToInt`. Text is never an item.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Cbor.U8Array, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)]))
		parser_for = |encoding| {
			|tagged| {
				state = untag(encoding, tagged)?
				h = head(state)?
				until_end = indefinite_at(h, state.pos)
				if h.major == 4 and (until_end or h.arg <= state.bytes.len() - h.next) {
					strict = no_text(encoding)
					var $s = at(state, h.next)
					var $out = List.with_capacity(if (until_end) 0 else h.arg)
					var $left = h.arg
					while $left > 0 and !(until_end and at_break($s)) {
						$left = $left - 1
						n = int(strict, $s)?
						$out = $out.append(narrow(n.value, $s.pos)?.to_u8_try() ? |_| InvalidCbor($s.pos))
						$s = n.rest
					}
					Ok({ value: Cbor.U8Array.($out), rest: if (until_end) at($s, $s.pos + 1) else $s })
				} else {
					Err(InvalidCbor(state.pos))
				}
			}
		}

		## Writes an array of integers (major type 4).
		encoder_for : Cbor -> (Cbor.U8Array, Cbor.Writer -> Try(Cbor.Writer, err))
		encoder_for = |_| |Cbor.U8Array.(bytes), w| {
			{ out, st } = begin(w)
			Ok({ out: bytes.fold(put_head(out, 4, bytes.len()), |o, b| put_head(o, 0, b.to_u64())), st })
		}

		## The bytes as a list.
		to_list : Cbor.U8Array -> List(U8)
		to_list = |Cbor.U8Array.(bytes)| bytes
	}

	## Binary data as one byte string (major type 2). Use `Cbor.Bytes` for binary data.
	## A `List(U8)` also writes a byte string, but a `List(U8)` field costs a protocol call for each byte:
	## the derived encoder has no hook for bytes (roc-lang/roc#11660). `Cbor.Bytes` writes the head and
	## the list in one append, and reads a byte string as a part of the input, with no copy.
	## It reads a byte string only. `Cbor.Bytes.from_list(list)` makes one, and `bytes.to_list()` gives the list back.
	Bytes := List(U8).{

		## Two values are equal when their lists are equal.
		is_eq : _

		## Reads a byte string (major type 2) as a part of the input. As a `List(U8)`, it also reads an empty array,
		## with `BytesFromArray` an array of integers 0 to 255, and with `BytesFromBase64` base64 text. Another item is an error.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Cbor.Bytes, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)]))
		parser_for = |encoding|
			|tagged| {
				state = untag(encoding, tagged)?
				h = head(state)?
				empty = h.arg == 0 or (indefinite_at(h, state.pos) and state.bytes.get(h.next) == Ok(0xff))
				if h.major == 4 and (empty or encoding.read.bytes_from_array) {
					parse_array = Cbor.U8Array.parser_for(encoding)
					parsed = parse_array(state)?
					Ok({ value: Cbor.Bytes.(parsed.value.to_list()), rest: parsed.rest })
				} else if h.major == 3 and encoding.read.bytes_from_base64 {
					t = text_head(state)?
					value = from_base64(t.name) ? |_| InvalidCbor(state.pos)
					Ok({ value: Cbor.Bytes.(value), rest: t.rest })
				} else {
					parsed = Cbor.parse_bytes(encoding, state)?
					Ok({ value: Cbor.Bytes.(parsed.value), rest: parsed.rest })
				}
			}

		## Writes a byte string (major type 2).
		encoder_for : Cbor -> (Cbor.Bytes, Cbor.Writer -> Try(Cbor.Writer, err))
		encoder_for = |_| |Cbor.Bytes.(bytes), w| Cbor.encode_bytes(bytes, w)

		## The bytes as a list.
		to_list : Cbor.Bytes -> List(U8)
		to_list = |Cbor.Bytes.(bytes)| bytes

		## Makes `Bytes` from a list. The pair of `to_list`.
		from_list : List(U8) -> Cbor.Bytes
		from_list = |list| Cbor.Bytes.(list)
	}

	## Any CBOR data item (RFC 8949 3), with its tags. Use it for a value that has no fixed type:
	## a key that can be text or a number, an item with a tag, the items of a patch.
	##
	## | Variant | CBOR | Note |
	## | --- | --- | --- |
	## | `Int(Cbor.IntValue)` | Major type 0 or 1 | -2^64 to 2^64 - 1. A literal works: `Int(5)`. |
	## | `Float(F64)` | f16, f32, f64 | The writer writes the shortest of f16, f32, f64 with the same value, each NaN as `f9 7e00` |
	## | `Bytes(List(U8))` | Byte string | |
	## | `Text(Str)` | Text | UTF-8 is checked |
	## | `Array(List(Cbor.Value))` | Array | |
	## | `Map(Cbor.ValueMap)` | Map | Any key type, no duplicate key. The entries keep their order. |
	## | `Tag(U64, Cbor.Value)` | Tag and its item | Each tag stays, also a tag of the option `ignore_tags` |
	## | `Bool(Bool)`, `Null`, `Undefined` | `false`, `true`, `null`, `undefined` | |
	## | `Simple(Cbor.SimpleValue)` | Another simple value: 0 to 19, 32 to 255 | A literal works: `Simple(16)` |
	##
	## Each value that the types let you make writes bytes that `Cbor.parse` reads back as the same value,
	## when it has 512 nested arrays, maps and tags or less (the default `max_depth`).
	## A record field of type `Cbor.Value` reads a `null` value as `Null` (with `NullAsAbsent`: the key is absent).
	## A map with a duplicate key is an error, or keeps one instance of the key (the option `duplicate_keys`).
	Value := [
		Int(Cbor.IntValue),
		Float(F64),
		Bytes(List(U8)),
		Text(Str),
		Array(List(Cbor.Value)),
		Map(Cbor.ValueMap),
		Tag(U64, Cbor.Value),
		Bool(Bool),
		Null,
		Undefined,
		Simple(Cbor.SimpleValue),
	].{

		## Two values are equal when their CBOR bytes (`Cbor.encode`) are equal. So `Float(0.0)` and
		## `Float(-0.0)` are not equal, each NaN is equal to each NaN (all write `f9 7e00`), `Int(1)` and `Float(1.0)`
		## are not equal, and two maps are equal only with the same entries in the same order.
		## A loop, not a recursion, and no encode.
		is_eq : Cbor.Value, Cbor.Value -> Bool
		is_eq = |a, b| same_value(a, b)

		## Hashes the value, the same as `is_eq`. So a `Cbor.Value` can be a key of a `Dict` or an item of a `Set`.
		## Do not put values from a peer into a `Dict` or a `Set`: the hash of Roc has a fixed seed (hash flooding).
		to_hash : Cbor.Value, Hasher -> Hasher
		to_hash = |value, hasher| hash_value(hasher, value)

		## Reads any one item. The option `ignore_tags` does not apply: each tag stays. More than 512 nested arrays,
		## maps and tags is an error at the head that goes too deep. As the one payload of an internal tag (`Cbor.Unions`),
		## it reads the item at the content key.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Cbor.Value, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)]))
		parser_for = |encoding| |state| read_value(at_content(encoding, state)?)

		## Writes the item, with the shortest heads (also for the counts of arrays and maps).
		encoder_for : Cbor -> (Cbor.Value, Cbor.Writer -> Try(Cbor.Writer, err))
		encoder_for = |_| |value, w| {
			{ out, st } = begin(w)
			Ok({ out: put_value(out, value), st })
		}
	}

	## The integer of `Cbor.Value.Int`: -2^64 to 2^64 - 1, the range of CBOR major types 0 and 1.
	## A literal in that range makes one (`Cbor.Value.Int(-5)`), and a literal out of the range is a compile error.
	IntValue :: I128.{
		is_eq : _
		to_hash : _

		## A literal of the type: an integer from -2^64 to 2^64 - 1.
		from_numeral : Numeral -> Try(Cbor.IntValue, [InvalidNumeral(Str)])
		from_numeral = |n| {
			# The digits are base 256, the most significant first. 9 digits hold 2^64.
			digits = n.digits_before_pt()
			if n.digits_after_pt_count() > 0 or digits.len() > 9 {
				return Err(InvalidNumeral("A Cbor.IntValue is an integer from -2^64 to 2^64 - 1"))
			}
			size = digits.fold(0.I128, |acc, d| acc * 256 + d.to_i128())
			Cbor.IntValue.from_i128(if (n.is_negative()) 0 - size else size).map_err(|_| InvalidNumeral("A Cbor.IntValue is an integer from -2^64 to 2^64 - 1"))
		}

		## `Err(OutOfRange)` when `n` is not in -2^64 to 2^64 - 1.
		from_i128 : I128 -> Try(Cbor.IntValue, [OutOfRange])
		from_i128 = |n| if (n >= -18446744073709551616 and n <= 18446744073709551615) Ok(Cbor.IntValue.(n)) else Err(OutOfRange)

		from_i64 : I64 -> Cbor.IntValue
		from_i64 = |n| Cbor.IntValue.(n.to_i128())

		from_u64 : U64 -> Cbor.IntValue
		from_u64 = |n| Cbor.IntValue.(n.to_i128())

		to_i128 : Cbor.IntValue -> I128
		to_i128 = |Cbor.IntValue.(n)| n

		to_inspect : Cbor.IntValue -> Str
		to_inspect = |Cbor.IntValue.(n)| n.to_str()
	}

	## The number of `Cbor.Value.Simple`: 0 to 19 or 32 to 255. 20 to 23 are `false`, `true`, `null` and
	## `undefined` (other variants of `Cbor.Value`), and 24 to 31 are not valid (RFC 8949 3.3).
	## A literal makes one (`Cbor.Value.Simple(16)`), and a literal of 20 to 31 is a compile error.
	SimpleValue :: U8.{
		is_eq : _
		to_hash : _

		## A literal of the type: 0 to 19 or 32 to 255.
		from_numeral : Numeral -> Try(Cbor.SimpleValue, [InvalidNumeral(Str)])
		from_numeral = |n| {
			digits = n.digits_before_pt()
			value = digits.first() ?? 0
			if n.digits_after_pt_count() > 0 or n.is_negative() or digits.len() > 1 {
				return Err(InvalidNumeral("A Cbor.SimpleValue is 0 to 19 or 32 to 255"))
			}
			Cbor.SimpleValue.from_u8(value).map_err(|_| InvalidNumeral("A Cbor.SimpleValue is 0 to 19 or 32 to 255"))
		}

		## `Err(InvalidSimple)` for 20 to 31.
		from_u8 : U8 -> Try(Cbor.SimpleValue, [InvalidSimple])
		from_u8 = |n| if (n >= 20 and n < 32) Err(InvalidSimple) else Ok(Cbor.SimpleValue.(n))

		to_u8 : Cbor.SimpleValue -> U8
		to_u8 = |Cbor.SimpleValue.(n)| n

		to_inspect : Cbor.SimpleValue -> Str
		to_inspect = |Cbor.SimpleValue.(n)| n.to_str()
	}

	## The entries of `Cbor.Value.Map`, in order, with no duplicate key. Two keys are the same when they are
	## equal as `Cbor.Value` (`is_eq`). The reader and `from_list` compare the keys by their bytes after a sort,
	## never with a hash, so a map from a peer cannot cause hash flooding.
	##
	## ```roc
	## map = Cbor.ValueMap.from_list([(Text("a"), Int(1)), (Int(2), Null)])?
	## Cbor.encode(Cbor.Value.Map(map))
	## ```
	ValueMap :: List((Cbor.Value, Cbor.Value)).{

		## Equal when the entries are equal, in the same order (the same as `Cbor.Value.is_eq`).
		is_eq : Cbor.ValueMap, Cbor.ValueMap -> Bool
		is_eq = |a, b| same_value(Cbor.Value.Map(a), Cbor.Value.Map(b))

		to_hash : Cbor.ValueMap, Hasher -> Hasher
		to_hash = |map, hasher| hash_value(hasher, Cbor.Value.Map(map))

		## A map with no entries.
		empty : () -> Cbor.ValueMap
		empty = || Cbor.ValueMap.([])

		## The entries in the order of the list. A key that is the same as a key before it is an error,
		## `Err(DuplicateKey(key))` with the second instance. O(n log n) for n keys.
		from_list : List((Cbor.Value, Cbor.Value)) -> Try(Cbor.ValueMap, [DuplicateKey(Cbor.Value)])
		from_list = |pairs|
			match first_duplicate(pairs.map(|(k, _)| put_value([], k))) {
				Ok(i) => Err(DuplicateKey(pairs.get(i).map_ok(|(k, _)| k) ?? Cbor.Value.Null))
				Err(_) => Ok(Cbor.ValueMap.(pairs))
			}

		## The entries, in order.
		to_list : Cbor.ValueMap -> List((Cbor.Value, Cbor.Value))
		to_list = |Cbor.ValueMap.(pairs)| pairs

		## The value of `key`. A linear search.
		get : Cbor.ValueMap, Cbor.Value -> Try(Cbor.Value, [KeyNotFound])
		get = |Cbor.ValueMap.(pairs), key| {
			for (k, v) in pairs {
				if same_value(k, key) {
					return Ok(v)
				}
			}
			Err(KeyNotFound)
		}

		## Sets the value of `key`. A key that is in the map keeps its place, else the entry goes at the end.
		insert : Cbor.ValueMap, Cbor.Value, Cbor.Value -> Cbor.ValueMap
		insert = |Cbor.ValueMap.(pairs), key, value| {
			for i in (0.U64).until(pairs.len()) {
				match pairs.get(i) {
					Ok((k, _)) if same_value(k, key) => {
						return Cbor.ValueMap.(pairs.set(i, (k, value)) ?? pairs)
					}
					_ => {}
				}
			}
			Cbor.ValueMap.(pairs.append((key, value)))
		}

		## The count of entries.
		len : Cbor.ValueMap -> U64
		len = |Cbor.ValueMap.(pairs)| pairs.len()

		to_inspect : Cbor.ValueMap -> Str
		to_inspect = |Cbor.ValueMap.(pairs)| "ValueMap(${Str.inspect(pairs)})"
	}

	## One CBOR item, kept as its exact bytes: to hash or check a signature over the bytes that a peer sent
	## (COSE, WebAuthn), or to pass an item on with no change. A `Raw` always holds exactly one well-formed item.
	##
	## | Function | Effect |
	## | --- | --- |
	## | `Cbor.Raw.from_bytes(bytes)` | A `Raw` when `bytes` are exactly one item that `Cbor.parse` reads, else `Err(InvalidCbor(pos))` |
	## | `Cbor.parse_with(bytes, options)` as a `Cbor.Raw` | The same with options (`PaddedNumbers`, `duplicate_keys`, `max_depth`) |
	## | `raw.to_bytes()` | The bytes |
	## | `Cbor.parse(raw.to_bytes())` | The item as a type |
	##
	## As a field of a record or an item of a list, it reads the bytes of that item, with the checks of the parse.
	## The writer writes the bytes as they are, as one item.
	Raw :: List(U8).{
		is_eq : _
		to_hash : _

		## A `Raw` of `bytes`: they must be one item with the strict checks of `Cbor.parse`.
		from_bytes : List(U8) -> Try(Cbor.Raw, [InvalidCbor(U64), MissingRequiredField(Str)])
		from_bytes = |bytes| Cbor.parse(bytes)

		## The bytes of the item.
		to_bytes : Cbor.Raw -> List(U8)
		to_bytes = |Cbor.Raw.(bytes)| bytes

		## Reads the bytes of one item. The option `ignore_tags` does not apply: the bytes keep each tag.
		## As the one payload of an internal tag (`Cbor.Unions`), it reads the item at the content key.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Cbor.Raw, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)]))
		parser_for = |encoding| |tagged| {
			state = at_content(encoding, tagged)?
			end = skip(state)?
			Ok({ value: Cbor.Raw.(state.bytes.sublist({ start: state.pos, len: end.pos - state.pos })), rest: end })
		}

		## Writes the bytes as one item.
		encoder_for : Cbor -> (Cbor.Raw, Cbor.Writer -> Try(Cbor.Writer, err))
		encoder_for = |_| |Cbor.Raw.(bytes), w| {
			{ out, st } = begin(w)
			Ok({ out: out.concat(bytes), st })
		}

		to_inspect : Cbor.Raw -> Str
		to_inspect = |Cbor.Raw.(bytes)| "Raw(${Str.inspect(bytes)})"
	}

	# Streams: ByteChunks and TextChunks. The helper functions are in the region "Streams: ByteChunks and TextChunks"
	# after the walk.

	## Reads one top-level byte string from bytes that come in chunks, and gives its data as chunks: a byte string
	## larger than memory can be read. The steps are the steps of `Cbor.Items`:
	##
	## | Step | Result |
	## | --- | --- |
	## | `push(chunk)` | `{ values, rest }`: the data in `chunk`, as parts of it (no copy), and the next decoder or the error |
	## | `finish()` | `Ok({})` when the byte string is complete, else the error of a cut byte string |
	##
	## Only the concatenation of the parts is defined, not where each one ends. A part is never empty. The byte string
	## can have a definite or, with `IndefiniteLength`, an indefinite length: then each CBOR chunk must be a byte string
	## of definite length, and its head is not given. The tags of `ignore_tags` before the byte string are skipped.
	## Each tag and the byte string count for `max_items`, and each tag for `max_depth`. Another root is an error at
	## its head (a `List(U8)` of `parse_with` also reads an empty array, and base64 text with `BytesFromBase64`; a
	## `ByteChunks` reads only a byte string). Bytes after the byte string are an error at the first extra byte, as in
	## `parse_with`. Each position is a position in the whole stream.
	##
	## Memory: the decoder keeps at most a cut head (8 bytes), and the last chunk. `max_buffer` does not apply. A part
	## keeps the chunk that it is a part of alive: copy it to keep it long.
	ByteChunks :: ChunkState.{

		## A decoder of one byte string.
		new : Cbor.Options -> Cbor.ByteChunks
		new = |options| Cbor.ByteChunks.(new_chunks(options, 2))

		## The data in the bytes of `chunk` (after the bytes before it), as parts of `chunk`, and the decoder of the bytes
		## after `chunk` in `rest`; or in `rest` the error, after the parts before it. A `push` of `[]` changes nothing.
		push : Cbor.ByteChunks, List(U8) -> { values : List(List(U8)), rest : Try(Cbor.ByteChunks, [InvalidCbor(U64)]) }
		push = |Cbor.ByteChunks.(s), chunk| {
			r = chunks_run(append_chunks(s, chunk))
			match r.rest {
				Ok(next) => { values: r.pieces, rest: Ok(Cbor.ByteChunks.(next)) }
				Err(e) => { values: r.pieces, rest: Err(e) }
			}
		}

		## The end of the input: `Ok({})` when the byte string ended at the last byte, else the error of a cut byte
		## string, at a position in the whole stream.
		finish : Cbor.ByteChunks -> Try({}, [InvalidCbor(U64)])
		finish = |Cbor.ByteChunks.(s)| finish_chunks(s)

		## The position in the stream of the first byte that `push` did not give or read past (a head or data).
		position : Cbor.ByteChunks -> U64
		position = |Cbor.ByteChunks.(s)| s.base + s.off

		## A stream of the parts of the data, with the bytes of the chunks of `source`. Each step pulls a chunk of
		## `source` only when the parts of the chunk before are given, and the end of `source` is `finish`. A source
		## error `e` is `Err(Input(e))`. An error ends the stream.
		from_stream : Cbor.ByteChunks, Stream(Try(List(U8), e)) -> Stream(Try(List(U8), [InvalidCbor(U64), Input(e)]))
		from_stream = |start, source|
			decode_stream(
				start,
				source,
				{
					push_error: |InvalidCbor(p)| InvalidCbor(p),
					finish_error: |InvalidCbor(p)| InvalidCbor(p),
					spent: Cbor.ByteChunks.new({}),
				},
			)
	}

	## Reads one top-level text from bytes that come in chunks, and gives it as `Str` parts: a text larger than memory
	## can be read. The same as `Cbor.ByteChunks`, for text (major type 3). Each part ends at a code point boundary.
	##
	## When a chunk ends inside a code point, the decoder keeps its 1 to 3 bytes, and the part of the next chunk starts
	## with the whole code point. The text must be valid UTF-8, as in `parse_with`: else the error is at the head of the
	## text (for an indefinite length, its first head), after the parts before the bad bytes. With `IndefiniteLength`,
	## each CBOR chunk is a text of definite length that is valid UTF-8 by itself (RFC 8949 3.2.3).
	## A part shares the bytes of its chunk (no copy), and keeps it alive.
	TextChunks :: ChunkState.{

		## A decoder of one text.
		new : Cbor.Options -> Cbor.TextChunks
		new = |options| Cbor.TextChunks.(new_chunks(options, 3))

		## The text in the bytes of `chunk` (after the bytes before it), and the decoder of the bytes after `chunk` in
		## `rest`; or in `rest` the error, after the parts before it. A `push` of `[]` changes nothing.
		push : Cbor.TextChunks, List(U8) -> { values : List(Str), rest : Try(Cbor.TextChunks, [InvalidCbor(U64)]) }
		push = |Cbor.TextChunks.(s), chunk| {
			r = chunks_run(append_chunks(s, chunk))
			var $texts = List.with_capacity(r.pieces.len())
			var $valid = Bool.True
			for piece in r.pieces {
				if $valid {
					match Str.from_utf8(piece) {
						Ok(text) => {
							$texts = $texts.append(text)
						}
						Err(_) => {
							$valid = Bool.False
						}
					}
				}
			}
			if !$valid {
				# Invalid UTF-8: the error is at the head of the text, as in `parse_with`.
				{ values: $texts, rest: Err(InvalidCbor(r.open)) }
			} else {
				match r.rest {
					Ok(next) => { values: $texts, rest: Ok(Cbor.TextChunks.(next)) }
					Err(e) => { values: $texts, rest: Err(e) }
				}
			}
		}

		## The end of the input: `Ok({})` when the text ended at the last byte, else the error of a cut text (also in a
		## code point).
		finish : Cbor.TextChunks -> Try({}, [InvalidCbor(U64)])
		finish = |Cbor.TextChunks.(s)| finish_chunks(s)

		## The position in the stream of the first byte that `push` did not give or read past (a head or text). The bytes
		## of a cut code point are after it.
		position : Cbor.TextChunks -> U64
		position = |Cbor.TextChunks.(s)| s.base + s.off

		## A stream of the parts of the text, with the bytes of the chunks of `source`, as `ByteChunks.from_stream`.
		from_stream : Cbor.TextChunks, Stream(Try(List(U8), e)) -> Stream(Try(Str, [InvalidCbor(U64), Input(e)]))
		from_stream = |start, source|
			decode_stream(
				start,
				source,
				{
					push_error: |InvalidCbor(p)| InvalidCbor(p),
					finish_error: |InvalidCbor(p)| InvalidCbor(p),
					spent: Cbor.TextChunks.new({}),
				},
			)
	}

	# Streams: Cbor.Items. The helper functions are in the region "Streams: Cbor.Items" after the walk.

	## Reads the items of one top-level array (`array`), or the root items of an RFC 8742 sequence (`sequence`),
	## from bytes that come in chunks. Each item is a typed value from the annotation of `push`, as in `Cbor.parse`.
	##
	## | Step | Result |
	## | --- | --- |
	## | `push(chunk)` | `{ values, rest }`: the items that `chunk` completes, and the next decoder or the error |
	## | `finish()` | `Ok({})` when the input can end here, else the error of the cut item (or the open array) |
	##
	## Give each chunk to `push`, and the last decoder to `finish`. `push` takes the decoder and gives back the next one
	## in `rest`, so the loop sets its variable to it:
	##
	## ```roc
	## var $items = Cbor.Items.array({})
	## for chunk in chunks {
	## 	r : { values : List({ id : U64 }), rest : Try(Cbor.Items, _) }
	## 	r = $items.push(chunk)
	## 	for row in r.values {
	## 		$rows = $rows.append(row)
	## 	}
	## 	$items = r.rest?
	## }
	## $items.finish()?
	## ```
	##
	## Each item that comes before an error is a valid item: the items before the error are in `values`, and the error
	## is in `rest`. An error ends the stream. For an array, the array must end at the last byte: bytes after it are an
	## error at the first extra byte, as in `parse_with`. Each position is a position in the whole stream.
	##
	## Each item has the checks of `parse_with` and its options. `Items.array` reads the bytes that `parse_with`
	## reads as a `List(a)`, and `Items.sequence` the bytes of `parse_sequence_with`. `max_items` counts each item
	## of the array and the array itself, or the items of each root item of a sequence. `max_depth` counts the array
	## and its tags. Only an array is a root of `Items.array`: an empty byte string, which `parse_with` reads as an
	## empty `List(a)`, is an error at its head.
	##
	## Memory: the decoder keeps the bytes of the open item, and the bytes of the last chunk that are not read.
	## An item that is not whole in its first `max_buffer` bytes (`Cbor.Options`, default 16 MiB), with more bytes
	## after them, is the error `TooLarge(pos)` at the start of the item. Each byte of an item is walked one time,
	## and copied at most about two times, also when the item comes in many chunks. The `values` of one `push` are not
	## in `max_buffer`: a chunk of C bytes gives at most C items (each item has 1 byte or more), decoded as `parse_with`
	## decodes those bytes, so the chunk size bounds them. A decoder that is kept and given to `push` again is copied
	## first, as a `List` that is kept and appended to.
	Items :: {
		# The bytes that are not read: the open item, and the bytes after it.
		buf : List(U8),
		# The position of buf[0] in the stream.
		base : U64,
		# The start of the next item or head in `buf`.
		off : U64,
		phase : ItemsPhase,
		# The walk of the open item, stopped at the end of `buf` (`Cut`).
		cut : [Idle, Open(WalkState)],
		# Array: the items of the root so far, for `max_items`.
		count : U64,
		# Array: the levels of the root, the array and each tag before it, for `max_depth`.
		depth : U64,
		# Array: the stream position of the innermost head of the root (a tag or the array), or `no_pos`.
		root : U64,
		# Set by `finish`.
		input_done : Bool,
		# The most bytes of one item (`max_buffer`).
		limit : U64,
		rules : Rules,
		cbor : Cbor,
	}.{

		## A decoder of the items of one top-level array, of definite or indefinite length. The tags of
		## `ignore_tags` before the array are skipped. An indefinite length needs `IndefiniteLength`.
		array : Cbor.Options -> Cbor.Items
		array = |options| new_items(options, Head, options.?max_buffer ?? 16_777_216)

		## A decoder of the root items of an RFC 8742 sequence: zero or more items, with no head before them.
		sequence : Cbor.Options -> Cbor.Items
		sequence = |options| new_items(options, Sequence, options.?max_buffer ?? 16_777_216)

		## The items that are whole after the bytes of `chunk`, in order, as the type of the annotation, and the decoder
		## of the bytes after them in `rest`; or in `rest` the error, after the items before it. A `push` of `[]` changes
		## nothing. A chunk of C bytes gives C items or less, and their memory is the memory of `parse_with` of them.
		push : Cbor.Items, List(U8) -> { values : List(a), rest : Try(Cbor.Items, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64)]) } where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
		push = |items, chunk| {
			Shape : a
			parse_shape = Shape.parser_for(items.cbor)
			push_items(items, chunk, parse_shape, |p| TooLarge(p))
		}

		## The end of the input: `Ok({})` when the root array, or the last item of the sequence, ended at the last byte.
		## Else the error of the cut item, or of the open array. Each item is self-delimiting, so `push` already gave
		## each whole item: `finish` gives no value.
		finish : Cbor.Items -> Try({}, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64)])
		finish = |items| finish_items(items)

		## The position in the stream of the first byte that is not part of an item or a head that `push` gave.
		position : Cbor.Items -> U64
		position = |items| items.base + items.off

		## A stream of the items, with the bytes of the chunks of `source`, each item as the type of the use of the stream.
		## Each step gives the next item of the last chunk, and pulls the next chunk of `source` only when no item of
		## the chunk before is left. The end of `source` is `finish`. A source error `e` is `Err(Input(e))`. An error
		## ends the stream. `for!` loops over the stream:
		##
		## ```roc
		## rows : Stream(Try({ id : U64 }, _))
		## rows = Cbor.Items.array({}).from_stream(body)
		## for! row in rows {
		## 	store_row!(row?)
		## }
		## ```
		from_stream : Cbor.Items, Stream(Try(List(U8), e)) -> Stream(Try(a, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), Input(e)])) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
		from_stream = |start, source| {
			decode_stream(
				start,
				source,
				{
					push_error: |e| e,
					finish_error: |e|
						match e {
							InvalidCbor(p) => InvalidCbor(p)
							MissingRequiredField(f) => MissingRequiredField(f)
							TooLarge(p) => TooLarge(p)
						},
					spent: Cbor.Items.sequence({}),
				},
			)
		}
	}

	# Streams: Cbor.Entries. The helper functions are in the region "Streams: Cbor.Entries" after "Streams: Cbor.Items".

	## Reads the entries of one top-level map from bytes that come in chunks. Each entry is a typed key and value from
	## the annotation of `push`, as in `Cbor.parse`. The steps are the steps of `Cbor.Items`: `push` gives the entries
	## that the chunk completes as `(key, value)` in `values`, and the next decoder or the error in `rest`; `finish`
	## gives `Ok({})` or the error of a cut entry (or the open map).
	##
	## The map is read as `parse_with` reads a `Dict(k, v)`, with the same options: `Entries.map` reads the bytes that
	## `parse_with : Dict(k, v)` reads, with the same entries, for each key type that a `Dict` allows. A key reads only
	## in the form that `Cbor.encode` writes for its value (see `Cbor.Leniency`). The tags of `ignore_tags` before the
	## map are skipped. An indefinite length needs `IndefiniteLength`. Bytes after the map are an error at the first
	## extra byte. An error ends the stream, at a position in the whole stream, after the entries before it.
	##
	## Duplicate keys of the map (`duplicate_keys`), with the keys compared as `parse_with` compares them:
	##
	## | `key_order` | `Reject` | `First` | `Last` |
	## | --- | --- | --- | --- |
	## | `Any` | An error at the second key | A later entry with the key is walked, and not given | `Err(NotStreamable)` at each `push` and `finish`: the last entry of a key is known only at the end of the map |
	## | `Sorted` | An error at the second key | The same as `Any` | Each entry is held until the next key is greater, or the map ends: then the last entry of each key is given |
	##
	## Memory: the decoder keeps the bytes of the open entry, and the keys that it needs for duplicate keys: with
	## `key_order: Any` the canonical bytes of each distinct key (and 8 bytes for each key), with `Sorted` only the
	## key before (and the held entry for `Last`). All of it counts in `max_buffer`: an item (a key or a value) that is
	## not whole in the bytes that are left, with more bytes after them, is the error `TooLarge(pos)` at the start of
	## the item, and keys over the limit are `TooLarge(pos)` at the key. So a large map with `key_order: Any` needs a
	## larger `max_buffer`, or keys in order with `key_order: Sorted`. The `values` of one `push` are not in
	## `max_buffer`, as for `Cbor.Items`: a chunk of C bytes gives C/2 entries or less.
	Entries :: {
		# The window, the root head, the count of entries left (in `phase`), the walk of the open item and the limits.
		# `off` is the start of the held entry, or else of the open entry.
		items : Cbor.Items,
		# `Key`: the key of the open entry is not whole. `Value`: the key is whole (`key` bytes at the start of the open
		# entry), and the value is open. `later`: a later instance of a key (`First`), not given. `skips`: the keys that
		# `duplicate_keys` skips inside the key, from the start of the open entry.
		part : [Key, Value({ key : U64, later : Bool, skips : List(U64) })],
		# `Sorted` and `Last`: the bytes (`held`) and the key bytes (`held_key`) of the entry at `off` that waits for the
		# next key. Its skips inside its key and value, from `off`. `held` is 0 when no entry waits.
		held : U64,
		held_key : U64,
		held_skips : List(U64),
		# `Any`: the canonical bytes of each key so far.
		keys : KeySet,
		# `Sorted`: the deterministic bytes of the key before, or `[]` before the first key (`first`).
		prev : List(U8),
		first : Bool,
	}.{

		## A decoder of the entries of one top-level map, of definite or indefinite length.
		map : Cbor.Options -> Cbor.Entries
		map = |options| new_entries(options)

		## The entries that are whole after the bytes of `chunk`, in order, as `(key, value)` of the key and value types
		## of the annotation, and the decoder of the bytes after them in `rest`; or in `rest` the error, after the
		## entries before it. The key reads as a key of a `Dict(k, v)`: only the form that `Cbor.encode` writes for it.
		## A `push` of `[]` changes nothing. A chunk of C bytes gives C/2 entries or less.
		push : Cbor.Entries, List(U8) -> { values : List((k, v)), rest : Try(Cbor.Entries, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable]) } where [k.Parseable([InvalidCbor(U64), MissingRequiredField(Str)]), k.Encodable([]), v.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
		push = |entries, chunk| {
			KeyShape : k
			ValueShape : v
			key_shape = KeyShape.parser_for(entries.items.cbor)
			value_shape = ValueShape.parser_for(entries.items.cbor)
			dups = key_dups(entries.items.rules)
			push_entries(entries, chunk, |state| exact_key_with(state, key_shape, dups), value_shape)
		}

		## The end of the input: `Ok({})` when the map ended at the last byte, else the error of the cut entry or of
		## the open map. `finish` gives no entry: `push` gave each one, also the held entry of `Sorted` and `Last`.
		finish : Cbor.Entries -> Try({}, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable])
		finish = |entries| finish_entries(entries)

		## The position in the stream of the first byte that is not part of an entry or a head that `push` gave
		## (or skipped).
		position : Cbor.Entries -> U64
		position = |entries| entries.items.position()

		## A stream of the entries as `(key, value)`, with the bytes of the chunks of `source`, as `Items.from_stream`.
		## A source error `e` is `Err(Input(e))`. An error ends the stream.
		from_stream : Cbor.Entries, Stream(Try(List(U8), e)) -> Stream(Try((k, v), [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable, Input(e)])) where [k.Parseable([InvalidCbor(U64), MissingRequiredField(Str)]), k.Encodable([]), v.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
		from_stream = |start, source| {
			decode_stream(
				start,
				source,
				{
					push_error: |e| e,
					finish_error: |e|
						match e {
							InvalidCbor(p) => InvalidCbor(p)
							MissingRequiredField(f) => MissingRequiredField(f)
							TooLarge(p) => TooLarge(p)
							NotStreamable => NotStreamable
						},
					spent: Cbor.Entries.map({}),
				},
			)
		}
	}

	## A `Stream` of the chunks that `read!` gives, for `from_stream`: each pull calls `read!` one time, and an empty
	## chunk (`Ok([])`, the end of a file or a socket) ends the stream. An error of `read!` is the last item. For a
	## platform with a read function and no `Stream`:
	##
	## ```roc
	## rows : Stream(Try({ id : U64 }, _))
	## rows = Cbor.Items.array({}).from_stream(Cbor.chunk_source(|| read_body!(65_536)))
	## ```
	chunk_source : (() => Try(List(U8), e)) -> Stream(Try(List(U8), e))
	chunk_source = |read!|
		Stream.custom(
			Bool.True,
			unknown_length,
			|going|
				if going {
					match read!() {
						Ok([]) => Err(NoMore)
						Ok(chunk) => Ok((Ok(chunk), Bool.True))
						Err(e) => Ok((Err(e), Bool.False))
					}
				} else {
					Err(NoMore)
				},
		)

	## Reads one CBOR item of the type `a` from all of `bytes`, with the strict rules. The type comes from the annotation.
	## The error is `InvalidCbor(pos)`, with the byte position of the problem, or
	## `MissingRequiredField(name)` from the derived parser of a record, with the Roc name of the field.
	## First the item must be valid as a `Cbor.Value`, also each part that the type skips: shortest heads,
	## no duplicate key, 512 nested arrays, maps and tags or less. Then it must fit the type.
	## Bytes after the item are an error at the position of the first extra byte.
	## The same as `parse_with(bytes, {})`.
	parse : List(U8) -> Try(a, [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse = |bytes| Cbor.parse_with(bytes, {})

	## Like `parse`, with options (`Cbor.Options`).
	##
	## ```roc
	## row : Try({ id : I64, active : Bool }, _)
	## row = Cbor.parse_with(bytes, { fields: Camel, allow: Cbor.sql_rows })
	## ```
	parse_with : List(U8), Cbor.Options -> Try(a, [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse_with = |bytes, options| {
		setup = parse_setup(options)
		Shape : a
		parse_shape = Shape.parser_for(setup.cbor)
		one = parse_one(bytes, 0, setup.rules, parse_shape)?
		if (one.next == bytes.len()) Ok(one.value) else Err(InvalidCbor(one.next))
	}

	## Reads one CBOR item of the type `a` at the start of `bytes`, with the strict rules, and gives the bytes after it
	## in `rest` (a slice, no copy). The checks of `parse` apply to the item. For data that has more after an item,
	## as the credential public key in the authenticator data of WebAuthn.
	##
	## ```roc
	## key : Try({ value : Cbor.Value, rest : List(U8) }, _)
	## key = Cbor.parse_prefix(bytes)
	## ```
	parse_prefix : List(U8) -> Try({ value : a, rest : List(U8) }, [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse_prefix = |bytes| Cbor.parse_prefix_with(bytes, {})

	## Like `parse_prefix`, with options (`Cbor.Options`).
	parse_prefix_with : List(U8), Cbor.Options -> Try({ value : a, rest : List(U8) }, [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse_prefix_with = |bytes, options| {
		setup = parse_setup(options)
		Shape : a
		parse_shape = Shape.parser_for(setup.cbor)
		one = parse_one(bytes, 0, setup.rules, parse_shape)?
		Ok({ value: one.value, rest: bytes.sublist({ start: one.next, len: bytes.len() - one.next }) })
	}

	## Reads a CBOR sequence (RFC 8742): zero or more items of the type `a`, one after the other, with no
	## head before them. Empty bytes give `[]`. Each item has the checks of `parse` (and `max_items` counts the items of each one).
	## The position of an error is in all of `bytes`.
	parse_sequence : List(U8) -> Try(List(a), [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse_sequence = |bytes| Cbor.parse_sequence_with(bytes, {})

	## Like `parse_sequence`, with options (`Cbor.Options`).
	parse_sequence_with : List(U8), Cbor.Options -> Try(List(a), [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse_sequence_with = |bytes, options| {
		# The stream decoder with no `max_buffer`: all the bytes are in memory.
		start = append_items(new_items(options, Sequence, U64.highest), bytes)
		Shape : a
		parse_shape = Shape.parser_for(start.cbor)
		var $items = end_items(start)
		var $values = []
		var $more = Bool.True
		while $more {
			match items_next($items, parse_shape, |p| InvalidCbor(p))? {
				Item(value, rest) => {
					$values = $values.append(value)
					$items = rest
				}
				_ => {
					$more = Bool.False
				}
			}
		}
		Ok($values)
	}

	## The path from the root to the item that starts at `pos`: the array indexes and the map keys.
	## Use it with the position of `InvalidCbor(pos)` to find the field of the error.
	## The path of the root is `[]`. `Err(NotFound)` when no item starts at `pos` (also a map key,
	## or a position in the middle of an item), when the path has a map key that is not text, or when
	## `bytes` are not one well-formed item. It has the checks of `Cbor.Value` that no option changes, so it finds
	## the position of an error of each `parse_with`: any head width, any length (also indefinite), a duplicate key, any depth.
	##
	## ```roc
	## # [{"name": "a", "id": 1.5}]: the value of "id" starts at 12
	## expect Cbor.path_at(bytes, 12) == Ok([Index(0), Key("id")])
	## ```
	path_at : List(U8), U64 -> Try(List(Cbor.Step), [NotFound])
	path_at = |bytes, pos| {
		start = reader(bytes)
		end = skip(start) ? |_| NotFound
		if (end.pos == bytes.len()) path_to(start, pos) else Err(NotFound)
	}

	## Writes `value` as one CBOR item. The derived encoders always give the right item counts.
	## An `encoder_for` of your own that writes a wrong count crashes the program here: use
	## `Cbor.encode_try` to get the error.
	encode : a -> List(U8) where [a.Encodable([])]
	encode = |value|
		match Cbor.encode_item(value, new_writer(Snake)) {
			Ok(w) if counts_match(w) => finish_output(w)
			_ => crash "Cbor.encode: an encoder_for wrote the wrong count of items (CountMismatch). Cbor.encode_try gives the error."
		}

	## Writes `value` as one CBOR item. `Err(CountMismatch)`: an `encoder_for` of your own wrote 0 or 2
	## items in one place, or a count of items that is not the count it gave (a record can get fewer fields).
	## Another error comes from your own `encoder_for`.
	encode_try : a -> Try(List(U8), [CountMismatch, ..err]) where [a.Encodable([CountMismatch, ..err])]
	encode_try = |value| {
		w = Cbor.encode_item(value, new_writer(Snake))?
		if (counts_match(w)) Ok(finish_output(w)) else Err(CountMismatch)
	}

	## `Cbor.encode_try` with options (`Cbor.WriteOptions`). `Err(DuplicateMapKey)`: two fields of one record have the same
	## camelCase key (`fields: Camel`), or with `key_order: Sorted`, a map has two entries with the same key bytes.
	encode_with : a, Cbor.WriteOptions -> Try(List(U8), [CountMismatch, DuplicateMapKey, ..err]) where [a.Encodable([CountMismatch, DuplicateMapKey, ..err])]
	encode_with = |value, options| {
		w = Cbor.encode_item(value, new_writer(options.?fields ?? Snake))?
		if !counts_match(w) {
			return Err(CountMismatch)
		}
		if w.st.dup {
			return Err(DuplicateMapKey)
		}
		match options.?key_order ?? Given {
			Given => Ok(finish_output(w))
			Sorted => sort_maps(finish_output(w))
		}
	}

	## Codec protocol: the record key to write. `Camel` (`encode_with`) gives the camelCase name.
	## In a parse it gives the Roc name, for `MissingRequiredField`: `parse_record_field` matches the keys.
	rename_field : Cbor, Str -> Str
	rename_field = |encoding, name|
		match encoding {
			{ fields: Snake, .. } => name
			{ fields: Camel, .. } => Json.snake_to_camel(name)
		}

	## Codec protocol: the error for a value that does not fit its type. A `parser_for` of your own
	## uses it for its own errors: `Err(Cbor.invalid_value(encoding, state))` is an error at `state`.
	invalid_value : Cbor, Cbor.Reader -> [InvalidCbor(U64), MissingRequiredField(Str)]
	invalid_value = |_, state| InvalidCbor(error_pos(state))

	# Building blocks for a `parser_for` or an `encoder_for` of your own

	## The kind of the item at `state` (`Cbor.Kind`), with no read: use it to pick the reader.
	## The option `ignore_tags` does not apply: a tag gives `Tag(number)`.
	## As the one payload of an internal tag (`Cbor.Unions`), it gives the kind of the item at the content key.
	## A reserved head, or no more bytes, is an error. An item of indefinite length gives its kind (the walk of a parse
	## without `IndefiniteLength` rejected it before).
	peek : Cbor, Cbor.Reader -> Try(Cbor.Kind, [InvalidCbor(U64), MissingRequiredField(Str)])
	peek = |encoding, tagged| {
		state = at_content(encoding, tagged)?
		h = head(state)?
		match h.major {
			0 => Ok(Int)
			1 => Ok(Int)
			2 => Ok(Bytes)
			3 => Ok(Text)
			4 => Ok(Array)
			5 => Ok(Map)
			6 => Ok(Tag(h.arg))
			_ =>
				match simple(state, h.arg) {
					Ok(SimpleFloat) => Ok(Float)
					Ok(SimpleBool(_)) => Ok(Bool)
					Ok(SimpleNull) => Ok(Null)
					Ok(SimpleUndefined) => Ok(Undefined)
					Ok(SimpleOther(n)) => Ok(Simple(n))
					Err(e) => Err(e)
				}
		}
	}

	## Reads the head of a tag (major type 6): its number. `rest` is at the tagged item, which you read next
	## with its reader (`Cbor.parse_item`). Another item is an error. The option `ignore_tags` does not apply.
	## As the one payload of an internal tag (`Cbor.Unions`), it reads the item at the content key.
	##
	## ```roc
	## Uuid := List(U8).{
	##     parser_for = |encoding| |state| {
	##         tag = Cbor.parse_cbor_tag(encoding, state)?
	##         if tag.value != 37 {
	##             return Err(Cbor.invalid_value(encoding, state))
	##         }
	##         bytes = Cbor.parse_bytes(encoding, tag.rest)?
	##         Ok({ value: Uuid.(bytes.value), rest: bytes.rest })
	##     }
	## }
	## ```
	parse_cbor_tag : Cbor, Cbor.Reader -> Try({ value : U64, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_cbor_tag = |encoding, tagged| {
		state = at_content(encoding, tagged)?
		h = head(state)?
		if (h.major == 6) Ok({ value: h.arg, rest: at(state, h.next) }) else Err(InvalidCbor(state.pos))
	}

	## Writes a tag (major type 6): its number, then `value` as the one tagged item. The pair of `parse_cbor_tag`.
	encode_tagged : U64, a, Cbor.Writer -> Try(Cbor.Writer, err) where [a.Encodable(err)]
	encode_tagged = |number, value, w| {
		{ out, st } = begin(w)
		tag_slot({ out: put_head(out, 6, number), st }, |inner| Cbor.encode_item(value, inner))
	}

	## Reads one item of the type `a` at `state`, with the `parser_for` of `a`, and gives the state after it.
	## Use it in a `parser_for` of your own, for example for the item after a tag.
	parse_item : Cbor, Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse_item = |encoding, state| {
		Shape : a
		parse_shape = Shape.parser_for(encoding)
		parse_shape(state)
	}

	## Writes `value` as one item, with the `encoder_for` of `a`. Use it in an `encoder_for` of your own.
	encode_item : a, Cbor.Writer -> Try(Cbor.Writer, err) where [a.Encodable(err)]
	encode_item = |value, w| {
		Shape : a
		encode_shape = Shape.encoder_for(with_fields(w.st.fields))
		encode_shape(value, w)
	}

	# Scalars

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_str : Cbor, Cbor.Reader -> Try({ value : Str, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_str = |cbor, state|
		match short_text(cbor, state) {
			Ok(t) => Ok(t)
			Err(NotShort) => text(untag(cbor, state)?)
		}

	## A byte string (major type 2) only. Use it in a `parser_for` of your own.
	parse_bytes : Cbor, Cbor.Reader -> Try({ value : List(U8), rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_bytes = |cbor, tagged| bytes_item(cbor, tagged)

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Reads `false` and `true`. With `BoolFromInt`, also the integers 0 and 1 (a SQL database has no boolean),
	## with the rules of an integer type, without text: a float 0.0 or 1.0 needs `FloatToInt` too.
	## Another integer is an error.
	parse_bool : Cbor, Cbor.Reader -> Try({ value : Bool, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_bool = |cbor, tagged| {
		if plain_at(cbor, tagged) {
			match tagged.bytes.get(tagged.pos) {
				Ok(0xf4) => return Ok({ value: Bool.False, rest: at(tagged, tagged.pos + 1) })
				Ok(0xf5) => return Ok({ value: Bool.True, rest: at(tagged, tagged.pos + 1) })
				_ => {}
			}
		}
		state = untag(cbor, tagged)?
		match if (state.raw > 0) Err(OutOfBounds) else state.bytes.get(state.pos) {
			Ok(0xf4) => Ok({ value: Bool.False, rest: at(state, state.pos + 1) })
			Ok(0xf5) => Ok({ value: Bool.True, rest: at(state, state.pos + 1) })
			Ok(_) if cbor.read.bool_from_int =>
				match int(no_text(cbor), state) {
					Ok({ value: 0, rest }) => Ok({ value: Bool.False, rest })
					Ok({ value: 1, rest }) => Ok({ value: Bool.True, rest })
					_ => Err(InvalidCbor(state.pos))
				}
			_ => Err(InvalidCbor(error_pos(state)))
		}
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Reads `null`, and `undefined` with `UndefinedAsNull`. A `Try(a, [Null])` reads it as `Err(Null)`, also as a record field.
	## With the option `ignore_tags`, a tag of the list before the `null` is also read.
	parse_null : Cbor, Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_null = |cbor, tagged| {
		state = untag(cbor, tagged)?
		if is_null(cbor, state) {
			Ok(at(state, state.pos + 1))
		} else {
			Err(InvalidCbor(error_pos(state)))
		}
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## The first item of an array read as a list (a `List(U8)`) needs `BytesFromArray` when each item of the array is
	## an integer 0 to 255: the writer writes such a list as a byte string. An array with another item (a null, 256) reads.
	parse_u8 : Cbor, Cbor.Reader -> Try({ value : U8, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_u8 = |cbor, state|
		if state.raw > 0 {
			# An item of a byte string read as a List(U8).
			b = state.bytes.get(state.pos) ? |_| InvalidCbor(state.pos)
			Ok({ value: b, rest: moved(state, state.pos + 1, state.raw - 1) })
		} else if state.array != no_pos and !cbor.read.bytes_from_array and bytes_as_array(state) {
			Err(InvalidCbor(state.array))
		} else {
			n = int(cbor, state)?
			v = narrow(n.value, state.pos)?.to_u8_try() ? |_| InvalidCbor(state.pos)
			Ok({ value: v, rest: n.rest })
		}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_u16 : Cbor, Cbor.Reader -> Try({ value : U16, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_u16 = |cbor, state| {
		n = int(cbor, state)?
		Ok({ value: narrow(n.value, state.pos)?.to_u16_try() ? |_| InvalidCbor(state.pos), rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_u32 : Cbor, Cbor.Reader -> Try({ value : U32, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_u32 = |cbor, state| {
		n = int(cbor, state)?
		Ok({ value: narrow(n.value, state.pos)?.to_u32_try() ? |_| InvalidCbor(state.pos), rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_u64 : Cbor, Cbor.Reader -> Try({ value : U64, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_u64 = |cbor, state| {
		if plain_at(cbor, state) {
			# Major type 0 with any head: the walk checked the head and its bytes.
			match state.bytes.get(state.pos) {
				Ok(b) if b < 0x18 => return Ok({ value: b.to_u64(), rest: at(state, state.pos + 1) })
				Ok(b) if b <= 0x1b => {
					size = (1.U64).shl_wrap((b - 0x18).to_u8_wrap())
					if size < state.bytes.len() - state.pos {
						return Ok({ value: get_be(state.bytes, state.pos + 1, size), rest: at(state, state.pos + 1 + size) })
					}
				}
				_ => {}
			}
		}
		n = int(cbor, state)?
		Ok({ value: n.value.to_u64_try() ? |_| InvalidCbor(state.pos), rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_i8 : Cbor, Cbor.Reader -> Try({ value : I8, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_i8 = |cbor, state| {
		n = int(cbor, state)?
		Ok({ value: narrow(n.value, state.pos)?.to_i8_try() ? |_| InvalidCbor(state.pos), rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_i16 : Cbor, Cbor.Reader -> Try({ value : I16, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_i16 = |cbor, state| {
		n = int(cbor, state)?
		Ok({ value: narrow(n.value, state.pos)?.to_i16_try() ? |_| InvalidCbor(state.pos), rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_i32 : Cbor, Cbor.Reader -> Try({ value : I32, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_i32 = |cbor, state| {
		n = int(cbor, state)?
		Ok({ value: narrow(n.value, state.pos)?.to_i32_try() ? |_| InvalidCbor(state.pos), rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_i64 : Cbor, Cbor.Reader -> Try({ value : I64, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_i64 = |cbor, state| {
		n = int(cbor, state)?
		Ok({ value: n.value.to_i64_try() ? |_| InvalidCbor(state.pos), rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Reads an integer (major type 0, with the leniencies of an integer type), or a bignum (tag 2, RFC 8949 3.4.3) of 16 bytes or less.
	parse_u128 : Cbor, Cbor.Reader -> Try({ value : U128, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_u128 = |cbor, state| {
		n = wide(cbor, state)?
		if (n.negative) Err(InvalidCbor(state.pos)) else Ok({ value: n.size, rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Reads an integer (major types 0 and 1, with the leniencies of an integer type), or a bignum (tag 2 or 3, RFC 8949 3.4.3)
	## in the range of an I128.
	parse_i128 : Cbor, Cbor.Reader -> Try({ value : I128, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_i128 = |cbor, state| {
		n = wide(cbor, state)?
		i = n.size.to_i128_try() ? |_| InvalidCbor(state.pos)
		Ok({ value: if (n.negative) -1 - i else i, rest: n.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Reads a float, or an integer that is exact as an F64 (any integer of size 2^53 or less).
	parse_f64 : Cbor, Cbor.Reader -> Try({ value : F64, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_f64 = |cbor, state| {
		if plain_at(cbor, state) {
			# A float head at a plain position: its bits after the initial byte (the walk checked the bytes).
			b = state.bytes.get(state.pos) ?? 0
			if b >= 0xf9 and b <= 0xfb {
				size = (1.U64).shl_wrap((b - 0xf8).to_u8_wrap())
				if size < state.bytes.len() - state.pos {
					bits = get_be(state.bytes, state.pos + 1, size)
					value = if (b == 0xfb) F64.from_bits(bits) else if (b == 0xfa) F32.from_bits(bits.to_u32_wrap()).to_f64() else half(bits)
					return Ok({ value, rest: at(state, state.pos + 1 + size) })
				}
			}
		}
		f = float(untag(cbor, state)?)?
		Ok({ value: f.value, rest: f.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Reads a float, rounded to an F32, or an integer that is exact as an F32 (any integer of size 2^24 or less).
	## A finite value outside the F32 range, and a value that is not 0 but rounds to 0, are errors.
	parse_f32 : Cbor, Cbor.Reader -> Try({ value : F32, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_f32 = |cbor, tagged| {
		state = untag(cbor, tagged)?
		f = float(state)?
		small = f.value.to_f32_wrap()
		lost =
			if f.value.is_finite() {
				small.is_infinite() or (small == 0.0 and f.value != 0.0) or (f.integer and small.to_f64() != f.value)
			} else {
				Bool.False
			}
		if (lost) Err(InvalidCbor(state.pos)) else Ok({ value: small, rest: f.rest })
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Reads exactly: an integer (major types 0 and 1), and a decimal fraction (tag 4, `[exponent, mantissa]`,
	## a mantissa that is an integer or a bignum of 127 bits or less). A decimal fraction with more than
	## 18 fraction digits, or outside the range of a Dec, is an error at the tag. Also reads a float
	## (f16, f32, f64), as its whole part plus its fraction rounded to a whole attos. A float has 15 to 17
	## significant digits, so the Dec is exact to that. NaN, an infinity and a float outside the range of a
	## Dec are errors. Another tag is an error. Text is an error, except with the option `dec_from_text`:
	## then text in the number form of JSON (`-1.25`, `4E+1`) reads exactly (see `Cbor.Options`).
	parse_dec : Cbor, Cbor.Reader -> Try({ value : Dec, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_dec = |cbor, tagged| {
		state = untag(cbor, tagged)?
		h = head(state)?
		match h.major {
			0 => Ok({ value: Dec.from_attos(h.arg.to_i128() * dec_scale), rest: at(state, h.next) })
			1 => Ok({ value: Dec.from_attos((-1 - h.arg.to_i128()) * dec_scale), rest: at(state, h.next) })
			3 if cbor.read.dec_from_text => {
				t = text(state)?
				d = dec_text(t.value) ? |_| InvalidCbor(state.pos)
				Ok({ value: d, rest: t.rest })
			}
			6 => decimal_fraction(state, cbor.read.padded)
			_ => {
				f = float(state)?
				# The whole part and the fraction apart: the product of the f64 with 10^18 loses digits.
				whole = f.value.to_i128_try() ? |_| InvalidCbor(state.pos)
				if whole.abs_diff(0) > 170141183460469231731 {
					return Err(InvalidCbor(state.pos))
				}
				frac = f.value - whole.to_f64()
				scaled = frac * 1.0e18
				frac_attos = (scaled + if (scaled < 0.0) -0.5 else 0.5).to_i128_try() ? |_| InvalidCbor(state.pos)
				attos = (whole * dec_scale).plus_try(frac_attos) ? |_| InvalidCbor(state.pos)
				Ok({ value: Dec.from_attos(attos), rest: f.rest })
			}
		}
	}

	# Containers

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_list_start : Cbor, Cbor.Reader -> Try([Counted({ len : U64, rest : Cbor.Reader }), Uncounted(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_list_start = |cbor, tagged| {
		if plain_at(cbor, tagged) {
			# An array of 23 items or less at a plain position: a 1-byte head.
			b = tagged.bytes.get(tagged.pos) ?? 0
			if b >= 0x80 and b <= 0x97 {
				len = (b - 0x80).to_u64()
				if len <= tagged.bytes.len() - tagged.pos - 1 {
					return Ok(Counted({ len, rest: { ..at(tagged, tagged.pos + 1), array: tagged.pos } }))
				}
			}
		}
		state = untag(cbor, tagged)?
		h = head(state)?
		if indefinite_at(h, state.pos) {
			return
				match h.major {
					4 => Ok(Uncounted({ ..at(state, h.next), array: state.pos }))
					# A byte string read as a `List(U8)`: `parse_list_next` goes from chunk to chunk.
					2 => Ok(Uncounted({ ..at(state, h.next), chunks: Bool.True }))
					3 if cbor.read.bytes_from_base64 => base64_list(state)
					_ => Err(InvalidCbor(state.pos))
				}
		}
		if h.arg > state.bytes.len() - h.next {
			# Each item is 1 byte or more: a count that does not fit is an error, not an allocation.
			return Err(InvalidCbor(state.pos))
		}
		match h.major {
			# The array position: a `List(U8)` reads the first item only with `BytesFromArray`.
			4 => Ok(Counted({ len: h.arg, rest: { ..at(state, h.next), array: state.pos } }))
			2 => Ok(Counted({ len: h.arg, rest: moved(state, h.next, h.arg) }))
			3 if cbor.read.bytes_from_base64 => base64_list(state)
			_ => Err(InvalidCbor(state.pos))
		}
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Only in an array or a byte string of indefinite length: `Done` at its break.
	parse_list_next : Cbor, Cbor.Reader -> Try([Item(Cbor.Reader), Done(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_list_next = |_, state|
		match list_step(state)? {
			More(s) => Ok(Item(s))
			End(s) => Ok(Done(s))
		}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Only in an array or a byte string of indefinite length: `Done` at its break.
	parse_list_after_item : Cbor, Cbor.Reader -> Try([Continue(Cbor.Reader), Done(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_list_after_item = |_, state|
		match list_step(state)? {
			More(s) => Ok(Continue(s))
			End(s) => Ok(Done(s))
		}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_tuple_start : Cbor, Cbor.Reader, U64 -> Try(Cbor.Reader, [InvalidCbor(U64), MissingRequiredField(Str)])

	## With `IndefiniteLength`, an array of indefinite length with `len` items reads too.
	parse_tuple_start = |cbor, tagged, len| {
		state = untag(cbor, tagged)?
		h = head(state)?
		until_end = indefinite_at(h, state.pos)
		if h.major != 4 or (h.arg != len and !until_end) {
			Err(InvalidCbor(state.pos))
		} else if cbor.read.indefinite {
			# `parse_tuple_end` reads the break of this tuple when it has one.
			m = memo_of(state)
			Ok(with_memo(at(state, h.next), { ..m, tuples: m.tuples.append(until_end) }))
		} else {
			Ok(at(state, h.next))
		}
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_tuple_next : Cbor, Cbor.Reader, U64, U64 -> Try(Cbor.Reader, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_tuple_next = |_, state, _, _| Ok(state)

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_tuple_end : Cbor, Cbor.Reader, U64 -> Try(Cbor.Reader, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_tuple_end = |cbor, state, _|
		if cbor.read.indefinite {
			m = memo_of(state)
			rest = with_memo(state, { ..m, tuples: m.tuples.drop_last(1) })
			match m.tuples.last() {
				Ok(Bool.True) => if (at_break(state)) Ok(at(rest, state.pos + 1)) else Err(InvalidCbor(state.pos))
				_ => Ok(rest)
			}
		} else {
			Ok(state)
		}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## A record that is the one payload of an internal tag reads the map of the tag itself.
	parse_record_start : Cbor, Cbor.Reader -> Try([Counted({ len : U64, rest : Cbor.Reader }), Uncounted(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_record_start = |cbor, tagged| {
		if tagged.raw == 0 and cbor.ignore_tags.is_empty() {
			# A map of 23 entries or less: a 1-byte head. Each entry is 2 bytes or more.
			b = tagged.bytes.get(tagged.pos) ?? 0
			if b >= 0xa0 and b <= 0xb7 {
				len = (b - 0xa0).to_u64()
				if len <= (tagged.bytes.len() - tagged.pos - 1) // 2 {
					return Ok(Counted({ len, rest: at(tagged, tagged.pos + 1) }))
				}
			}
		}
		map_start(skip_tags(cbor, tagged))
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## With `Snake` and `unknown_fields: Skip`, gives the key, and the derived parser matches it (the fast path).
	## Else it matches the key with the fields (in `Camel` case with the option `fields: Camel`), and gives the field to read.
	## Skips an entry of a key that `duplicate_keys` skips, of an unknown key (an error with `unknown_fields: Reject`),
	## and with `NullAsAbsent` of a `null` value (also after a tag of `ignore_tags`).
	parse_record_field : Cbor,
	Encoding.FieldName.FieldNames(_shape),
	Cbor.Reader -> Try(
		[
			Field({ field : Encoding.FieldName(_shape), rest : Cbor.Reader }),
			TryField({ name : Str, rest : Cbor.Reader }),
			TryFieldCaseless({ name : Str, rest : Cbor.Reader }),
			Continue(Cbor.Reader),
			Done(Cbor.Reader),
		],
		[InvalidCbor(U64), MissingRequiredField(Str)],
	)
	parse_record_field = |cbor, fields, state| {
		if !cbor.read.camel and !cbor.read.reject_unknown and !cbor.read.null_as_absent and !skipped(state) {
			# The common case: a short text key, no key to skip. The derived parser matches the name.
			match short_text(cbor, state) {
				Ok({ value, rest }) => return Ok(TryField({ name: value, rest }))
				Err(NotShort) => {}
			}
		}
		if at_break(state) {
			# The end of a map of indefinite length.
			return Ok(Done(at(state, state.pos + 1)))
		}
		key = text_head(state)?
		if skipped(state) {
			return Ok(Continue(skip(key.rest)?))
		}
		if cbor.read.null_as_absent and is_null(cbor, skip_tags(cbor, key.rest)) {
			return Ok(Continue(skip(key.rest)?))
		}
		name = key.name
		if !cbor.read.camel and !cbor.read.reject_unknown {
			# The derived parser matches the name. The walk checked the UTF-8.
			return Ok(TryField({ name: Str.from_utf8(name) ?? "", rest: key.rest }))
		}
		# Invalid UTF-8 gives "", which is the name of no field: as a compare of the bytes.
		key_str = Str.from_utf8(name) ?? ""
		if !cbor.read.camel {
			# Snake: only a field name of the same length can be the key.
			for f in fields.for_size(name.len()) {
				if Encoding.FieldName.name(f) == key_str {
					return Ok(Field({ field: f, rest: key.rest }))
				}
			}
			return if (state.pos != cbor.content.tag) Err(InvalidCbor(state.pos)) else Ok(Continue(skip(key.rest)?))
		}
		var $found : Try(Encoding.FieldName(_shape), [NoField])
		var $found = Err(NoField)
		for f in fields.iter() {
			field_name = Encoding.FieldName.name(f)
			if field_matches(cbor.read.camel, key_str, name, field_name) {
				if $found.is_ok() {
					# Two fields with one key (Camel: `a_1` and `a1`).
					return Err(InvalidCbor(state.pos))
				}
				$found = Ok(f)
				if !cbor.read.camel {
					break
				}
			}
		}
		match $found {
			Ok(field) => Ok(Field({ field, rest: key.rest }))
			Err(_) if cbor.read.reject_unknown and state.pos != cbor.content.tag => Err(InvalidCbor(state.pos))
			Err(_) => Ok(Continue(skip(key.rest)?))
		}
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## Only in a map of indefinite length: `Done` at its break.
	parse_record_after_field : Cbor, Cbor.Reader -> Try([Continue(Cbor.Reader), Done(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_record_after_field = |_, state| if (at_break(state)) Ok(Done(at(state, state.pos + 1))) else Ok(Continue(state))

	## Codec protocol: the derived `parser_for` of a type calls it for an unknown key (`TryField` of `parse_record_field`).
	skip_record_field : Cbor, Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64), MissingRequiredField(Str)])
	skip_record_field = |_, state| skip(state)

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## A map is counted. With keys to skip (`duplicate_keys`: `First`, `Last`), it is uncounted, and
	## `parse_dict_next` skips each entry of such a key.
	parse_dict_start : Cbor, Cbor.Reader -> Try([Counted({ len : U64, rest : Cbor.Reader }), Uncounted(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])

	## A `Dict` that is the one payload of an internal tag reads the item at the content key.
	parse_dict_start = |cbor, tagged| {
		state = untag(cbor, tagged)?
		match map_start(state)? {
			Counted({ len, rest }) if !memo_of(state).skips.is_empty() => Ok(Uncounted(push_dict(rest, Left(len))))
			Counted(counted) => Ok(Counted(counted))
			Uncounted(rest) => Ok(Uncounted(push_dict(rest, UntilBreak)))
		}
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## An uncounted map: skips the entries of keys to skip, then `Done` at the end of the map.
	parse_dict_next : Cbor, Cbor.Reader -> Try([Entry(Cbor.Reader), Done(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_dict_next = |_, state|
		match dict_step(state)? {
			More(s) => Ok(Entry(s))
			End(s) => Ok(Done(s))
		}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	## In an uncounted map: one entry less.
	parse_dict_after_key : Cbor, Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_dict_after_key = |_, state| {
		m = memo_of(state)
		match m.dicts.last() {
			Ok(Left(n)) if !m.skips.is_empty() => Ok(with_memo(state, { ..m, dicts: m.dicts.set(m.dicts.len() - 1, Left(n - 1)) ?? m.dicts }))
			_ => Ok(state)
		}
	}

	## Codec protocol: the derived `parser_for` of a type calls it. An app calls `Cbor.parse`.
	parse_dict_after_entry : Cbor, Cbor.Reader -> Try([Continue(Cbor.Reader), Done(Cbor.Reader)], [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_dict_after_entry = |_, state|
		match dict_step(state)? {
			More(s) => Ok(Continue(s))
			End(s) => Ok(Done(s))
		}

	# No `parse_key_start` and no `encode_key_start`: a `Dict` key of a composite type (a `Cbor.Value`, a record, a tuple,
	# a type of your own) is a compile error. Its own parser can read two different keys as one Roc key (a record skips
	# unknown fields), so the Dict would lose an entry with no error. The Roc compiler (nightly 2026-10-19) also crashes
	# on `encode_key_start` with such a key.

	## Codec protocol: a key of a `Dict(Str, v)`, and of a tag union with no payloads: text, with no tag. A tag name that
	## is not in the union is an error. A key of a composite type is a compile error: see the comment above.
	parse_key_str : Cbor, Cbor.Reader -> Try({ value : Str, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_str = |_, state| text(state)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_bool : Cbor, Cbor.Reader -> Try({ value : Bool, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_bool = |cbor, state| exact_key(state, Cbor.parse_bool(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_u8 : Cbor, Cbor.Reader -> Try({ value : U8, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_u8 = |cbor, state| exact_key(state, Cbor.parse_u8(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_i8 : Cbor, Cbor.Reader -> Try({ value : I8, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_i8 = |cbor, state| exact_key(state, Cbor.parse_i8(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_u16 : Cbor, Cbor.Reader -> Try({ value : U16, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_u16 = |cbor, state| exact_key(state, Cbor.parse_u16(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_i16 : Cbor, Cbor.Reader -> Try({ value : I16, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_i16 = |cbor, state| exact_key(state, Cbor.parse_i16(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_u32 : Cbor, Cbor.Reader -> Try({ value : U32, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_u32 = |cbor, state| exact_key(state, Cbor.parse_u32(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_i32 : Cbor, Cbor.Reader -> Try({ value : I32, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_i32 = |cbor, state| exact_key(state, Cbor.parse_i32(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_u64 : Cbor, Cbor.Reader -> Try({ value : U64, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_u64 = |cbor, state| exact_key(state, Cbor.parse_u64(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_i64 : Cbor, Cbor.Reader -> Try({ value : I64, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_i64 = |cbor, state| exact_key(state, Cbor.parse_i64(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_u128 : Cbor, Cbor.Reader -> Try({ value : U128, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_u128 = |cbor, state| exact_key(state, Cbor.parse_u128(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_i128 : Cbor, Cbor.Reader -> Try({ value : I128, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_i128 = |cbor, state| exact_key(state, Cbor.parse_i128(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_dec : Cbor, Cbor.Reader -> Try({ value : Dec, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_dec = |cbor, state| exact_key(state, Cbor.parse_dec(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_f32 : Cbor, Cbor.Reader -> Try({ value : F32, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_f32 = |cbor, state| exact_key(state, Cbor.parse_f32(cbor, state)?)

	## Codec protocol: a key of a `Dict(k, v)`. Only the form that the writer writes for the value.
	parse_key_f64 : Cbor, Cbor.Reader -> Try({ value : F64, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_key_f64 = |cbor, state| exact_key(state, Cbor.parse_f64(cbor, state)?)

	## Codec protocol: the derived `parser_for` of a tag union calls it. An app calls `Cbor.parse`.
	## `External` (default): text for a tag with no payload, else a map of one entry: the tag, then its payload,
	## or an array of its payloads when it has more than one. The same shapes as `Json`.
	## `Internal({ tag, content })`: text, or a map with the tag name at the key `tag` (see `Cbor.Unions`).
	## Codec protocol: the derived `parser_for` of a record calls it when a required field is absent.
	## The error names the Roc field.
	missing_field : Cbor, Str -> [InvalidCbor(U64), MissingRequiredField(Str)]
	missing_field = |_, name| MissingRequiredField(name)

	parse_tag_union : Cbor, Encoding.ParseTagUnionSpec(a, Cbor, Cbor.Reader, [InvalidCbor(U64), MissingRequiredField(Str)]), Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])
	parse_tag_union = |encoding, spec, tagged| {
		state = untag(encoding, tagged)?
		# The options of this union: from `parse_union` for the item at this position, else from the parse.
		# Each payload starts at another position, so it gets the options of the parse.
		(unions, case) = if (encoding.next.at == state.pos) (encoding.next.unions, encoding.next.tags) else (encoding.unions, Exact)
		h = head(state)?
		match (h.major, unions) {
			(3, _) => {
				name = text(state)?
				Encoding.ParseTagUnionSpec.parse(
					spec,
					{
						tag: roc_tag(case, name.value) ? |_| InvalidCbor(state.pos),
						encoding,
						state: name.rest,
						start_payloads: |s, count| if (count == 0) Ok(s) else Err(InvalidCbor(s.pos)),
						next_payload: |s, _, _| Err(InvalidCbor(s.pos)),
						finish_payloads: |s, _| Ok(s),
						missing: InvalidCbor(state.pos),
					},
				)
			}
			(5, External) if h.arg == 1 or indefinite_at(h, state.pos) => {
				name = text(at(state, h.next))?
				Encoding.ParseTagUnionSpec.parse(
					spec,
					{
						tag: roc_tag(case, name.value) ? |_| InvalidCbor(state.pos),
						encoding,
						state: name.rest,
						start_payloads: |s, count|
							if count == 1 {
								Ok(s)
							} else {
								payloads_start(encoding, s, count)
							},
						next_payload: |s, _, _| Ok(s),
						# The break of the payload array, then of the map, when they have an indefinite length.
						finish_payloads: |s, count| {
							after = if (count == 1) s else payloads_end(encoding, name.rest, s)?
							if (!indefinite_at(h, state.pos)) Ok(after) else if (at_break(after)) Ok(at(after, after.pos + 1)) else Err(InvalidCbor(after.pos))
						},
						missing: InvalidCbor(state.pos),
					},
				)
			}
			(5, Internal(keys)) => {
				found = scan_union(state, keys)?
				if found.tag == no_pos {
					return Err(InvalidCbor(state.pos))
				}
				name = text(at(found.end, found.tag))?
				# One payload: a record reads this map (`parse_record_start`), another reader reads the item at `content`.
				inner = with_positions(encoding, { at: state.pos, to: found.content, tag: found.tag_key }, encoding.next)
				Encoding.ParseTagUnionSpec.parse(
					spec,
					{
						tag: roc_tag(case, name.value) ? |_| InvalidCbor(state.pos),
						encoding: inner,
						# The map, with the map ends of the scan.
						state: at(found.end, state.pos),
						start_payloads: |s, count|
							if count == 0 {
								Ok(found.end)
							} else if count == 1 {
								Ok(s)
							} else {
								payloads_start(encoding, at_content(inner, s)?, count)
							},
						next_payload: |s, _, _| Ok(s),
						# The payloads end at the content or at the end of the map. The scan gave the end of the map.
						# A payload array of indefinite length must end after the last payload.
						finish_payloads: |s, count| {
							_ = if (count > 1) payloads_end(encoding, at(s, found.content), s)? else s
							Ok(at(s, found.end.pos))
						},
						missing: InvalidCbor(state.pos),
					},
				)
			}
			_ => Err(InvalidCbor(state.pos))
		}
	}

	## Reads one tag union of the type `a` at `state`, with `options` (`Cbor.UnionOptions`) for this union only.
	## Its payloads, and the other unions of the parse, keep the options of the parse. Use it in the `parser_for`
	## of a type of your own over a tag union, so that the type has its own layout and case.
	##
	## ```roc
	## Action := [Create, Update, NotFound].{
	##     parser_for = |encoding| |state| {
	##         parsed = Cbor.parse_union(encoding, { tags: Upper }, state)?
	##         Ok({ value: Action.(parsed.value), rest: parsed.rest })
	##     }
	## }
	## ```
	##
	## When `a` is not a tag union, the options have no effect.
	parse_union : Cbor, Cbor.UnionOptions, Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)]) where [a.Parseable([InvalidCbor(U64), MissingRequiredField(Str)])]
	parse_union = |encoding, options, tagged| {
		state = untag(encoding, tagged)?
		next = { at: state.pos, unions: options.?unions ?? encoding.unions, tags: options.?tags ?? Exact }
		Shape : a
		parse_shape = Shape.parser_for(with_positions(encoding, encoding.content, next))
		parse_shape(state)
	}

	# Encode. Each method writes through a `Cbor.Writer`, which counts the items.

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_str : Str, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_str = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_text(out, value), st })
	}

	## A byte string (major type 2): the head, then all of `value` in one append. `Cbor.Bytes` calls it.
	## Use it in an `encoder_for` of your own. The pair of `parse_bytes`.
	encode_bytes : List(U8), Cbor.Writer -> Try(Cbor.Writer, err)
	encode_bytes = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_head(out, 2, value.len()).concat(value), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_bool : Bool, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_bool = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: out.append(if (value) 0xf5 else 0xf4), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_null : Cbor.Writer -> Try(Cbor.Writer, err)
	encode_null = |w| {
		{ out, st } = begin(w)
		Ok({ out: out.append(0xf6), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## The first item of a list that comes from `encode_u8` makes the list a byte string (major type 2).
	encode_u8 : U8, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_u8 = |value, w| {
		{ out, st } = w
		match st.list {
			Pending(count) if st.owe => {
				start = out.len()
				Ok({ out: put_head(out, 2, count).append(value), st: { ..st, owe: Bool.False, list: Bytes({ start, count }) } })
			}
			Bytes(_) if st.owe => Ok({ out: out.append(value), st: { ..st, owe: Bool.False } })
			_ => {
				{ out: o, st: s } = begin({ out, st })
				Ok({ out: put_head(o, 0, value.to_u64()), st: s })
			}
		}
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_u16 : U16, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_u16 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_head(out, 0, value.to_u64()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_u32 : U32, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_u32 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_head(out, 0, value.to_u64()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_u64 : U64, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_u64 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_head(out, 0, value), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_i8 : I8, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_i8 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_int(out, value.to_i64()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_i16 : I16, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_i16 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_int(out, value.to_i64()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_i32 : I32, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_i32 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_int(out, value.to_i64()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_i64 : I64, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_i64 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_int(out, value), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## A value of 2^64 - 1 or less is major type 0, a larger one is a bignum (tag 2, RFC 8949 3.4.3).
	encode_u128 : U128, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_u128 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_big(out, Bool.False, value), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## A value from -2^64 to 2^64 - 1 is major type 0 or 1, another one is a bignum (tag 2, or tag 3 for -1 - n).
	encode_i128 : I128, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_i128 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_mantissa(out, value), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## The preferred serialization (RFC 8949 4.1): the shortest of f16, f32 and f64 that holds the same value.
	## Each NaN writes `f9 7e00`. An infinity and -0.0 write as f16.
	encode_f64 : F64, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_f64 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_float(out, value.to_bits()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## The shortest of f16 and f32 that holds the same value, as `encode_f64`.
	encode_f32 : F32, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_f32 = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_float(out, value.to_f64().to_bits()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## A Dec with no fraction, from -2^64 to 2^64 - 1, writes as an integer (major types 0 and 1).
	## Any other Dec writes as a decimal fraction (RFC 8949 3.4.4): the tag 4 and the array
	## `[exponent, mantissa]`, exact. The value in attos (10^-18) is the mantissa, with the exponent -18,
	## then each trailing zero digit moves to the exponent. So 3.14159 is `[-5, 314159]`.
	## A mantissa outside the 64 bit integers is a bignum (tag 2 or 3 with a byte string, 1 to 16 bytes).
	encode_dec : Dec, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_dec = |value, w| {
		{ out, st } = begin(w)
		Ok({ out: put_dec(out, value.to_attos()), st })
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## The derived encoder does not call `add` for an absent optional field or a `Try(a, [Missing])` field
	## with `Err(Missing)`, so the map can have fewer entries than `count`. More entries is a `CountMismatch`.
	## `Err(Null)` writes `null`.
	encode_record : Cbor.Writer, U64, (Cbor.Container, (Cbor.Container, Str, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Writer, err)
	encode_record = |w, count, write_fields| {
		{ out, st } = w
		# Only camelCase keys can collide: the Roc names of one record are all different.
		dup = st.fields == Camel and count > 1 and camel_collision(write_fields)
		# TODO(roc#13035): a match with no early return, not `?` (see `nest`).
		match nest({ out, st }, Head(5, count), Plain, Partial, write_fields, add_field) {
			Ok({ w: done, start, unused }) => {
				# Absent fields: a shorter head for the real count, and a gap for the rest of the old head.
				# With each field there, `done` as it is. A conditional: an early `return Ok(done)` made the encode 1.6x
				# slower (nightly-2026-11-13-03dce41).
				{ out: o, st: d } = if (unused == 0) done else shorten_head(done, start, count, count - unused)
				Ok({ out: o, st: { ..d, dup: d.dup or dup } })
			}
			Err(e) => Err(e)
		}
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## A `Dict(k, v)` writes a map (major type 5) of `count` entries, in the order of the `Dict`. Each key and each value
	## is exactly one item. A key of any type writes as that type writes: an integer key is an integer, not text.
	encode_dict : Cbor.Writer, U64, (Cbor.Container, (Cbor.Container, (Cbor.Writer -> Try(Cbor.Writer, err)), (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Writer, err)
	encode_dict = |w, count, write_entries| {
		nest(w, Head(5, count), Plain, Full, write_entries, add_entry).map_ok(|n| n.w)
	}

	## Codec protocol: a key of a `Dict(Str, v)`, and of a tag union with no payloads: text.
	## A key of a composite type is a compile error (see `parse_key_str`).
	encode_key_str : Cbor, Str, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_str = |_, key, w| Cbor.encode_str(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_bool : Cbor, Bool, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_bool = |_, key, w| Cbor.encode_bool(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_u8 : Cbor, U8, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_u8 = |_, key, w| Cbor.encode_u8(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_i8 : Cbor, I8, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_i8 = |_, key, w| Cbor.encode_i8(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_u16 : Cbor, U16, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_u16 = |_, key, w| Cbor.encode_u16(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_i16 : Cbor, I16, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_i16 = |_, key, w| Cbor.encode_i16(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_u32 : Cbor, U32, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_u32 = |_, key, w| Cbor.encode_u32(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_i32 : Cbor, I32, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_i32 = |_, key, w| Cbor.encode_i32(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_u64 : Cbor, U64, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_u64 = |_, key, w| Cbor.encode_u64(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_i64 : Cbor, I64, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_i64 = |_, key, w| Cbor.encode_i64(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_u128 : Cbor, U128, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_u128 = |_, key, w| Cbor.encode_u128(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_i128 : Cbor, I128, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_i128 = |_, key, w| Cbor.encode_i128(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_dec : Cbor, Dec, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_dec = |_, key, w| Cbor.encode_dec(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_f32 : Cbor, F32, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_f32 = |_, key, w| Cbor.encode_f32(key, w)

	## Codec protocol: a key of a `Dict(k, v)`: the same item as the value.
	encode_key_f64 : Cbor, F64, Cbor.Writer -> Try(Cbor.Writer, err)
	encode_key_f64 = |_, key, w| Cbor.encode_f64(key, w)

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## A list of `U8` (the first item comes from `encode_u8`) is a byte string. An empty list is an empty array.
	encode_list : Cbor.Writer, U64, (Cbor.Container, (Cbor.Container, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Writer, err)
	encode_list = |w, count, write_items| {
		nest(w, NoHead(count), Pending(count), Full, write_items, add_item).map_ok(|n| n.w)
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	encode_tuple : Cbor.Writer, U64, (Cbor.Container, (Cbor.Container, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Writer, err)
	encode_tuple = |w, count, write_items| {
		nest(w, Head(4, count), Plain, Full, write_items, add_item).map_ok(|n| n.w)
	}

	## Codec protocol: the derived `encoder_for` of a type calls it. An app calls `Cbor.encode`.
	## No payload: the tag name as text. One payload: `{ name: payload }`. More: `{ name: [payloads] }`.
	encode_tag : Cbor.Writer, Str, U64, (Cbor.Container, (Cbor.Container, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Writer, err)
	encode_tag = |w, name, count, write_payloads|
		if count == 0 {
			{ out, st } = begin(w)
			Ok({ out: put_text(out, name), st })
		} else {
			nest(w, Keyed(name, count), Plain, Full, write_payloads, add_item).map_ok(|n| n.w)
		}
}

## Starts one item: it takes the open place (`owe`), and writes a pending list head.
## No open place is a count mismatch: a second item in one place, or an item outside of a place.
## Each writer function takes the output out of the writer before it appends, and uses no
## closure for an append. Then the output has one reference at each append, and is not copied.
begin : Cbor.Writer -> Cbor.Writer
begin = |w| {
	{ out, st } = w
	if !st.owe {
		{ out, st: { ..st, bad: Bool.True } }
	} else {
		match st.list {
			Plain => { out, st: { ..st, owe: Bool.False } }
			Pending(count) => { out: put_head(out, 4, count), st: { ..st, owe: Bool.False, list: Plain } }
			Bytes({ start, count }) => { out: rewrite_as_array(out, start, count), st: { ..st, owe: Bool.False, list: Plain } }
		}
	}
}

## A byte string list gets an item that is not a U8: write the list again as an array.
rewrite_as_array : List(U8), U64, U64 -> List(U8)
rewrite_as_array = |out, start, count| {
	var $body = []
	for i in (start + head_size(count)).until(out.len()) {
		$body = $body.append(out.get(i) ?? 0)
	}
	$body.fold(put_head(out.take_first(start), 4, count), |o, b| put_head(o, 0, b.to_u64()))
}

## The heads of a container. `NoHead(count)`: a list, its head comes with its first item.
## `Head(major, count)`: an array or a map. `Keyed(name, count)`: a tag with payloads,
## `{ name: payload }` or `{ name: [payloads] }`.
put_heads : List(U8), [NoHead(U64), Head(U8, U64), Keyed(Str, U64)] -> List(U8)
put_heads = |out, heads|
	match heads {
		NoHead(_) => out
		Head(major, count) => put_head(out, major, count)
		Keyed(name, count) if count == 1 => put_text(put_head(out, 5, 1), name)
		Keyed(name, count) => put_head(put_text(put_head(out, 5, 1), name), 4, count)
	}

## Starts one item and writes its heads, then runs `write(container, add)` on a new level with `count` places and a
## new id. The container that `write` gives back must be of that level. `Full`: each place must have its item.
## `Partial` (a record): places can stay empty. Then back to the current level.
## Gives the position of the head and the count of empty places.
## `write` and `add` come as two arguments, not as one closure `|c| write(c, add)`: a closure that holds the `write`
## of the derived encoder for each container cost 40% of a record encode (nightly-2026-11-13-03dce41).
nest : Cbor.Writer, [NoHead(U64), Head(U8, U64), Keyed(Str, U64)], [Plain, Pending(U64), Bytes({ start : U64, count : U64 })], [Full, Partial], (Cbor.Container, add -> Try(Cbor.Container, err)), add -> Try({ w : Cbor.Writer, start : U64, unused : U64 }, err)
nest = |w, heads, list, need, write, add| {
	{ out, st } = begin(w)
	count =
		match heads {
			NoHead(n) | Head(_, n) | Keyed(_, n) => n
		}
	start = out.len()
	id = st.next
	left = st.left
	level = st.level
	# TODO(roc#13035): the early return of `?` (or of `return Err(e)`) makes the encode up to 2x slower (inlining is
	# lost). A match that gives `Err(e)` with no return does not. When the issue is fixed, go back to `?` here and in
	# the other writer functions with this TODO.
	match write(Cbor.Container.({ out: put_heads(out, heads), st: { ..st, left: count, owe: Bool.False, list, level: id, next: id + 1 } }), add) {
		Ok(Cbor.Container.({ out: o, st: d })) => {
			# A list with no item: its head is still to write.
			pending = d.list == Pending(count)
			done = if (pending) put_head(o, 4, count) else o
			# The writer of this level, the last place with its item, and with `Full` each place opened.
			ok = d.level == id and !d.owe and (need == Partial or d.left == 0)
			Ok({ w: { out: done, st: { ..d, left, level, owe: Bool.False, list: Plain, bad: d.bad or !ok } }, start, unused: d.left })
		}
		Err(e) => Err(e)
	}
}

## One value of a list, a tuple or a tag: exactly one item.
add_item : Cbor.Container, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)
add_item = |Cbor.Container.(w), write_value| slot(w, 1, write_value).map_ok(|x| Cbor.Container.(x))

## One entry of a map: exactly one item for the key, then exactly one item for the value. The entry takes one place.
add_entry : Cbor.Container, (Cbor.Writer -> Try(Cbor.Writer, err)), (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)
add_entry = |Cbor.Container.(w), write_key, write_value| {
	# TODO(roc#13035): no `?` (see `nest`).
	match slot(w, 1, write_key) {
		Ok(keyed) => slot(keyed, 0, write_value).map_ok(|x| Cbor.Container.(x))
		Err(e) => Err(e)
	}
}

## One field of a record: the key, then exactly one item.
add_field : Cbor.Container, Str, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)
add_field = |Cbor.Container.(w), name, write_value| {
	{ out, st } = w
	slot({ out: put_text(out, name), st }, 1, write_value).map_ok(|x| Cbor.Container.(x))
}

## Opens one place of the current level for `write_value`, which must write exactly one item there. The place comes
## from the current level (`used` 1), or the key of a map entry took it (`used` 0: the value of the entry). A tag uses `tag_slot`.
## The checks come when the next place opens and when the level ends (`nest`): the place before has its item (`owe`
## is false), and the level has a place left. A second item in a place finds no open place (`begin`). So the call of
## `write_value` is the last step, and its writer is not read here: no copy of the writer after each item.
slot : Cbor.Writer, U64, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Writer, err)
slot = |w, used, write_value| {
	{ out, st } = w
	bad = st.bad or st.owe or st.left < used
	left = if (st.left < used) 0 else st.left - used
	# The wasm32 dev backend copies the code around a closure call into each item encoder of the app, each copy with
	# its own stack. So the argument is a name, and the call is alone in `run_slot` (README, "Known compiler issues").
	run_slot({ out, st: { ..st, left, owe: Bool.True, bad } }, write_value)
}

## The one item after a tag head, on a level of its own with a new id: the item must be written with the writer
## after the head. A value can hold a writer (an `encoder_for` of your own), also the writer of the place before the
## tag, which has the level of the place: the new id tells the two apart, so the writer of the item is checked here.
tag_slot : Cbor.Writer, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Writer, err)
tag_slot = |w, write_value| {
	{ out, st } = w
	id = st.next
	left = st.left
	level = st.level
	# TODO(roc#13035): no `?` (see `nest`).
	match run_slot({ out, st: { ..st, owe: Bool.True, level: id, next: id + 1 } }, write_value) {
		Ok({ out: o, st: d }) => {
			ok = d.level == id and !d.owe
			Ok({ out: o, st: { ..d, left, level, owe: Bool.False, bad: d.bad or !ok } })
		}
		Err(e) => Err(e)
	}
}

## Only the call of `write_value`: see `slot`.
run_slot : Cbor.Writer, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Writer, err)
run_slot = |inner, write_value| write_value(inner)

## A record with absent fields (`n` is less than `count`): the head at `start` for `n` in place of `count`. The shortest head for `n`
## is not longer. The bytes that it frees are a gap, which `finish_output` removes once for the whole output.
shorten_head : Cbor.Writer, U64, U64, U64 -> Cbor.Writer
shorten_head = |w, start, count, n| {
	{ out, st } = w
	if n == count {
		return { out, st }
	}
	new_head = put_head([], 5, n)
	var $o = out
	for i in (0.U64).until(new_head.len()) {
		$o = $o.set(start + i, new_head.get(i) ?? 0) ?? $o
	}
	gap = { at: start + new_head.len(), len: head_size(count) - new_head.len() }
	{ out: $o, st: { ..st, gaps: if (gap.len == 0) st.gaps else st.gaps.append(gap) } }
}

## The shortest float with the same value as the f64 `bits` (RFC 8949 4.1): f16, f32 or f64.
## Each NaN is `f9 7e00`. Only bit operations, so each value is exact.
put_float : List(U8), U64 -> List(U8)
put_float = |out, bits| {
	sign = bits.shr_zf_wrap(63)
	exp = bits.shr_zf_wrap(52).bitwise_and(0x7ff)
	mant = bits.bitwise_and(0xfffffffffffff)
	if exp == 0x7ff {
		return put_be(out.append(0xf9), if (mant != 0) 0x7e00 else sign.shl_wrap(15).bitwise_or(0x7c00), 2)
	}
	if exp == 0 {
		# A zero is f16. A subnormal f64 is smaller than each f32.
		return if (mant == 0) put_be(out.append(0xf9), sign.shl_wrap(15), 2) else put_be(out.append(0xfb), bits, 8)
	}
	e = exp.to_i64_wrap() - 1023
	# The significand with its leading 1: the value is sig * 2^(e - 52).
	sig = mant.bitwise_or(0x10000000000000)
	if e >= -14 and e <= 15 and mant.bitwise_and(0x3ffffffffff) == 0 {
		put_be(out.append(0xf9), sign.shl_wrap(15).bitwise_or((e + 15).to_u64_wrap().shl_wrap(10)).bitwise_or(mant.shr_zf_wrap(42)), 2)
	} else if e >= -24 and e < -14 and low_zero(sig, (28 - e).to_u8_wrap()) {
		# An f16 subnormal: k * 2^-24, k = sig * 2^(e - 28).
		put_be(out.append(0xf9), sign.shl_wrap(15).bitwise_or(sig.shr_zf_wrap((28 - e).to_u8_wrap())), 2)
	} else if e >= -126 and e <= 127 and mant.bitwise_and(0x1fffffff) == 0 {
		put_be(out.append(0xfa), sign.shl_wrap(31).bitwise_or((e + 127).to_u64_wrap().shl_wrap(23)).bitwise_or(mant.shr_zf_wrap(29)), 4)
	} else if e >= -149 and e < -126 and low_zero(sig, (-97 - e).to_u8_wrap()) {
		# An f32 subnormal: k * 2^-149, k = sig * 2^(e + 97).
		put_be(out.append(0xfa), sign.shl_wrap(31).bitwise_or(sig.shr_zf_wrap((-97 - e).to_u8_wrap())), 4)
	} else {
		put_be(out.append(0xfb), bits, 8)
	}
}

## The `n` low bits of `x` are 0.
low_zero : U64, U8 -> Bool
low_zero = |x, n| x.bitwise_and((1.U64).shl_wrap(n) - 1) == 0

## The keys of a record (`Camel`) have a duplicate. A dry run of `write_fields` that writes only the keys, as text:
## no value is written, so it costs O(fields) for each record, with a sort.
camel_collision : (Cbor.Container, (Cbor.Container, Str, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(Cbor.Container, err)) -> Try(Cbor.Container, err)) -> Bool
camel_collision = |write_fields| {
	empty = { out: [], st: { left: 0, owe: Bool.False, list: Plain, level: 0, next: 1, bad: Bool.False, dup: Bool.False, gaps: [], fields: Camel } }
	keys = write_fields(Cbor.Container.(empty), |Cbor.Container.({ out, st }), name, _| Ok(Cbor.Container.({ out: put_text(out, name), st })))
	match keys {
		Ok(Cbor.Container.({ out, .. })) => text_duplicate(out)
		Err(_) => Bool.False
	}
}

## A list of text items (definite, shortest heads) has two items with the same bytes.
text_duplicate : List(U8) -> Bool
text_duplicate = |bytes| {
	var $keys = []
	var $p = 0
	while $p < bytes.len() {
		h = out_head(bytes, $p)
		$keys = $keys.append(bytes.sublist({ start: h.next, len: h.arg }))
		$p = h.next + h.arg
	}
	sorted = $keys.sort_with(order_bytes)
	var $before = Err(First)
	for key in sorted {
		if $before == Ok(key) {
			return Bool.True
		}
		$before = Ok(key)
	}
	Bool.False
}

## The size of the shortest head for `n`.
head_size : U64 -> U64
head_size = |n| if (n < 24) 1 else if (n < 0x100) 2 else if (n < 0x10000) 3 else if (n < 0x100000000) 5 else 9

## A writer for one item at the root.
new_writer : [Snake, Camel] -> Cbor.Writer
new_writer = |fields| { out: List.with_capacity(256), st: { left: 0, owe: Bool.True, list: Plain, level: 0, next: 1, bad: Bool.False, dup: Bool.False, gaps: [], fields } }

## The writer is the root writer, it wrote exactly one item, and each level got its count.
counts_match : Cbor.Writer -> Bool
counts_match = |w| !w.st.bad and !w.st.owe and w.st.level == 0

## The output with the gaps of old record heads removed: one pass, in place.
finish_output : Cbor.Writer -> List(U8)
finish_output = |w| {
	{ out, st } = w
	gaps = st.gaps.sort_with(|a, b| if (a.at < b.at) Before else if (a.at > b.at) After else Same)
	match gaps.first() {
		Err(_) => out
		Ok(first) => {
			var $o = out
			var $to = first.at
			var $from = first.at
			for g in gaps {
				for i in $from.until(g.at) {
					$o = $o.set($to, $o.get(i) ?? 0) ?? $o
					$to = $to + 1
				}
				$from = g.at + g.len
			}
			for i in $from.until($o.len()) {
				$o = $o.set($to, $o.get(i) ?? 0) ?? $o
				$to = $to + 1
			}
			$o.take_first($to)
		}
	}
}

# The stream writer (`Cbor.StreamWriter`). Each step checks its place before it makes bytes, and keeps no output.

## One open level of a `Cbor.StreamWriter`. `left`: the items, entries or bytes still to write (`Count`), or `Indefinite`.
## `half`: a map has a key with no value. `key`: the bytes of the last key of a map, with `key_order: Sorted` (empty before the first key).
StreamLevel : { kind : [Array, Map, ByteString, TextString], left : [Count(U64), Indefinite], half : Bool, key : List(U8) }

## The state of a `Cbor.StreamWriter`.
StreamState : { open : List(StreamLevel), root : [One, Sequence], done : Bool, fields : [Snake, Camel], sorted : Bool }

## The place of the next item. `Root`: the root item. `Item`: an array item. `Key(before)`: a map key, `before` is the
## key before it. `Value`: a map value.
StreamPlace : [Root, Item, Key(List(U8)), Value]

stream_writer : [One, Sequence], Cbor.WriteOptions -> Cbor.StreamWriter
stream_writer = |root, options|
	Cbor.StreamWriter.({ open: [], root, done: Bool.False, fields: options.?fields ?? Snake, sorted: (options.?key_order ?? Given) == Sorted })

## The place of the next item, or `Err(CountMismatch)` when the current level has no place for one.
item_place : StreamState -> Try(StreamPlace, [CountMismatch, ..e])
item_place = |s|
	match s.open.last() {
		Err(_) => if (s.root == One and s.done) Err(CountMismatch) else Ok(Root)
		Ok(level) =>
			match level.kind {
				Array => if (level.left == Count(0)) Err(CountMismatch) else Ok(Item)
				Map if level.half => Ok(Value)
				Map => if (level.left == Count(0)) Err(CountMismatch) else Ok(Key(level.key))
				ByteString | TextString => Err(CountMismatch)
			}
	}

## The state after one item at `place`. `bytes` is the key at a key place, kept with `key_order: Sorted`.
take_place : StreamState, StreamPlace, List(U8) -> StreamState
take_place = |s, place, bytes|
	match place {
		Root => { ..s, done: Bool.True }
		Item => update_top(s, |level| { ..level, left: count_down(level.left, 1) })
		Key(_) => update_top(s, |level| { ..level, half: Bool.True, key: if (s.sorted) bytes else [] })
		Value => update_top(s, |level| { ..level, half: Bool.False, left: count_down(level.left, 1) })
	}

## One item at `place`: with `key_order: Sorted`, a key must come after the key before it.
put_item : StreamState, StreamPlace, List(U8) -> Try(StreamState, [DuplicateMapKey, KeyOutOfOrder, ..e])
put_item = |s, place, bytes|
	match place {
		Key(before) if s.sorted and !before.is_empty() =>
			match order_bytes(bytes, before) {
				After => Ok(take_place(s, place, bytes))
				Same => Err(DuplicateMapKey)
				Before => Err(KeyOutOfOrder)
			}
		_ => Ok(take_place(s, place, bytes))
	}

## Opens a level at the next place, with its head. With `key_order: Sorted`, not at a key place.
open_level : Cbor.StreamWriter, [Array, Map, ByteString, TextString], U8, [Count(U64), Indefinite] -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch, ..e])
open_level = |Cbor.StreamWriter.(s), kind, major, size| {
	place = item_place(s)?
	match place {
		Key(_) if s.sorted => return Err(CountMismatch)
		_ => {}
	}
	bytes =
		match size {
			Count(n) => put_head(List.with_capacity(9), major, n)
			Indefinite => [major.shl_wrap(5).bitwise_or(31)]
		}
	taken = take_place(s, place, [])
	Ok({ bytes, writer: Cbor.StreamWriter.({ ..taken, open: taken.open.append({ kind, left: size, half: Bool.False, key: [] }) }) })
}

## The size of a byte string or a text as the size of a level.
string_size : [Length(U64), Indefinite] -> [Count(U64), Indefinite]
string_size = |size|
	match size {
		Length(n) => Count(n)
		Indefinite => Indefinite
	}

## A chunk of `len` bytes in the current level, which must be of `kind`. `Definite(next)`: the state with `len` bytes
## less to write. `Chunk`: an indefinite level, which does not change.
chunk_place : StreamState, [Array, Map, ByteString, TextString], U64 -> Try([Definite(StreamState), Chunk], [CountMismatch, ..e])
chunk_place = |s, kind, len|
	match s.open.last() {
		Ok(level) if level.kind == kind =>
			match level.left {
				Count(n) if len <= n => Ok(Definite(update_top(s, |l| { ..l, left: Count(n - len) })))
				Count(_) => Err(CountMismatch)
				Indefinite => Ok(Chunk)
			}
		_ => Err(CountMismatch)
	}

## `n` less in a `Count`. An item place was checked first, so a `Count` is not less than `n`.
count_down : [Count(U64), Indefinite], U64 -> [Count(U64), Indefinite]
count_down = |left, n|
	match left {
		Count(c) => Count(c - n)
		Indefinite => Indefinite
	}

## The state with `f` on the innermost open level.
update_top : StreamState, (StreamLevel -> StreamLevel) -> StreamState
update_top = |s, f|
	match s.open.last() {
		Ok(level) => { ..s, open: s.open.set(s.open.len() - 1, f(level)) ?? s.open }
		Err(_) => s
	}

# Deterministic encoding (`key_order: Sorted`): a second pass over the output of `finish_output`.
# 1. `out_maps` walks the heads of the output once and gives each map of 2 entries or more, with the start of each key and value.
# 2. `sort_maps` sorts the entries of each map by their key bytes, the inner maps first. A key with a map in it is compared
#    in its sorted form.
# 3. `emit` copies each byte once, the entries of each map in their sorted order.
# Cost: O(n) for the walk and the copy, O(k log k) for a map of k entries. Output with no map of 2 entries or more is not copied.

## A map of the output with 2 entries or more: its head is at `head`, its entries go from `at` to `end`. `items` is the start of each key and each value.
OutMap : { head : U64, at : U64, end : U64, items : List(U64) }

## The position of a map of the output, for `emit`.
Region : { head : U64, at : U64, end : U64 }

## A container that `out_maps` is in: the items left (a definite length), and for a map the count of item starts before it.
OutOpen : { left : U64, indefinite : Bool, map : Bool, mark : U64, head : U64, at : U64 }

## The head at `pos` of the output: its major type, its additional information, its argument and the position after it.
out_head : List(U8), U64 -> { major : U8, info : U8, arg : U64, next : U64 }
out_head = |out, pos| {
	b = out.get(pos) ?? 0
	info = b.bitwise_and(0x1f)
	size = if (info == 24) 1 else if (info == 25) 2 else if (info == 26) 4 else if (info == 27) 8 else 0
	var $arg = if (info < 24) info.to_u64() else 0
	for i in (0.U64).until(size) {
		$arg = $arg.shl_wrap(8).bitwise_or((out.get(pos + 1 + i) ?? 0).to_u64())
	}
	{ major: b.shr_zf_wrap(5), info, arg: $arg, next: pos + 1 + size }
}

## Each map of the output with 2 entries or more, in the order of their ends: an inner map comes before the map it is in.
## One walk of the heads, a loop with a list of the open containers.
out_maps : List(U8) -> List(OutMap)
out_maps = |out| {
	var $maps = []
	# The start of each item of each open map, the innermost map last.
	var $starts = []
	var $open = [{ left: 1, indefinite: Bool.False, map: Bool.False, mark: 0, head: 0, at: 0 }]
	var $p = 0
	while $p < out.len() and !$open.is_empty() {
		top = $open.last() ?? { left: 0, indefinite: Bool.False, map: Bool.False, mark: 0, head: 0, at: 0 }
		# An item ended: count it in the container it is in.
		var $ended = Bool.False
		var $last = Err(Open)
		if top.indefinite and out.get($p) == Ok(0xff) {
			$open = $open.drop_last(1)
			$last = Ok(top)
			$ended = Bool.True
		} else {
			if top.map {
				$starts = $starts.append($p)
			}
			h = out_head(out, $p)
			indefinite = h.info == 31
			if h.major == 4 or h.major == 5 or h.major == 6 or ((h.major == 2 or h.major == 3) and indefinite) {
				count = if (h.major == 5) 2 * h.arg else if (h.major == 6) 1 else h.arg
				$open = $open.append({ left: count, indefinite, map: h.major == 5, mark: $starts.len(), head: $p, at: h.next })
				$p = h.next
			} else {
				$p = if (h.major == 2 or h.major == 3) h.next + h.arg else h.next
				$ended = Bool.True
			}
		}
		# A break is not in the entries of its map.
		match $last {
			Ok(f) => {
				if f.map and $starts.len() >= f.mark + 4 {
					$maps = $maps.append({ head: f.head, at: f.at, end: $p, items: copy_from($starts, f.mark) })
				}
				$starts = $starts.drop_last($starts.len() - f.mark)
				$p = $p + 1
			}
			Err(_) => {}
		}
		var $more = Bool.True
		while $more {
			if $ended {
				$open = count_item($open)
				$ended = Bool.False
			}
			match $open.last() {
				Ok(f) if !f.indefinite and f.left == 0 => {
					$open = $open.drop_last(1)
					if f.map and $starts.len() >= f.mark + 4 {
						$maps = $maps.append({ head: f.head, at: f.at, end: $p, items: copy_from($starts, f.mark) })
					}
					$starts = $starts.drop_last($starts.len() - f.mark)
					$ended = Bool.True
				}
				_ => {
					$more = Bool.False
				}
			}
		}
	}
	$maps
}

## A new list of the items of `list` from `from` to the end. Not a slice, so `list` stays the only reference to its items.
copy_from : List(U64), U64 -> List(U64)
copy_from = |list, from| {
	var $copy = List.with_capacity(list.len() - from)
	for i in from.until(list.len()) {
		$copy = $copy.append(list.get(i) ?? 0)
	}
	$copy
}

## One more item in the container on top: a definite length has one place less.
count_item : List(OutOpen) -> List(OutOpen)
count_item = |open|
	match open.last() {
		Ok(f) if !f.indefinite => open.set(open.len() - 1, { ..f, left: if (f.left > 0) f.left - 1 else 0 }) ?? []
		_ => open
	}

## The output with the entries of each map sorted by their key bytes (RFC 8949 4.2.1). `Err(DuplicateMapKey)`: two
## entries of one map have the same key bytes.
sort_maps : List(U8) -> Try(List(U8), [DuplicateMapKey])
sort_maps = |out| {
	maps = out_maps(out)
	if maps.is_empty() {
		return Ok(out)
	}
	# The maps by position, for `emit`. `rank` gives the place of each map of `maps` in `regions`.
	indexes : List(U64)
	indexes = (0.U64).until(maps.len()).collect()
	by_at = indexes.sort_with(|a, b| ordered(head_of(maps, a), head_of(maps, b)))
	regions = by_at.map(|i| maps.get(i).map_ok(|m| { head: m.head, at: m.at, end: m.end }) ?? { head: 0, at: 0, end: 0 })
	var $rank = List.repeat(0.U64, maps.len())
	for r in (0.U64).until(by_at.len()) {
		$rank = $rank.set(by_at.get(r) ?? 0, r) ?? []
	}
	# The entries of each map in `regions`, as spans of the output: first in the given order.
	var $orders = List.repeat([], maps.len())
	for i in (0.U64).until(maps.len()) {
		$orders = $orders.set($rank.get(i) ?? 0, entry_spans(maps.get(i) ?? { head: 0, at: 0, end: 0, items: [] }).map(|e| (e.key, e.end))) ?? []
	}
	# The inner maps come first in `maps`, so each key is compared in its sorted form.
	for i in (0.U64).until(maps.len()) {
		entries = entry_spans(maps.get(i) ?? { head: 0, at: 0, end: 0, items: [] })
		keys = entries.map(|e| emit(out, regions, $orders, e.key, e.value))
		places : List(U64)
		places = (0.U64).until(entries.len()).collect()
		sorted = places.sort_with(|a, b| order_bytes(keys.get(a) ?? [], keys.get(b) ?? []))
		var $before = Err(First)
		for k in sorted {
			key = keys.get(k) ?? []
			if $before == Ok(key) {
				return Err(DuplicateMapKey)
			}
			$before = Ok(key)
		}
		$orders = $orders.set($rank.get(i) ?? 0, sorted.map(|k| entries.get(k).map_ok(|e| (e.key, e.end)) ?? (0, 0))) ?? []
	}
	Ok(emit(out, regions, $orders, 0, out.len()))
}

## The position of the head of the map `i`.
head_of : List(OutMap), U64 -> U64
head_of = |maps, i| maps.get(i).map_ok(|m| m.head) ?? 0

## The order of two positions.
ordered : U64, U64 -> [Before, Same, After]
ordered = |a, b| if (a < b) Before else if (a > b) After else Same

## Each entry of a map: the start of its key, of its value, and its end.
entry_spans : OutMap -> List({ key : U64, value : U64, end : U64 })
entry_spans = |m| {
	n = m.items.len() // 2
	var $entries = List.with_capacity(n)
	for j in (0.U64).until(n) {
		key = m.items.get(2 * j) ?? 0
		value = m.items.get(2 * j + 1) ?? 0
		end = m.items.get(2 * j + 2) ?? m.end
		$entries = $entries.append({ key, value, end })
	}
	$entries
}

## The bytewise order of RFC 8949 4.2.1: the first byte that is not the same decides, and a prefix comes first.
order_bytes : List(U8), List(U8) -> [Before, Same, After]
order_bytes = |x, y| {
	n = if (x.len() < y.len()) x.len() else y.len()
	for i in (0.U64).until(n) {
		a = x.get(i) ?? 0
		b = y.get(i) ?? 0
		if a != b {
			return if (a < b) Before else After
		}
	}
	ordered(x.len(), y.len())
}

## The bytes of the output from `from` to `to`, with the entries of each map of `regions` in the order of `orders`.
## A loop with a list of the spans still to copy, not a recursion. One search for each span.
emit : List(U8), List(Region), List(List((U64, U64))), U64, U64 -> List(U8)
emit = |out, regions, orders, from, to| {
	var $res = List.with_capacity(to - from)
	var $todo = [(from, to)]
	while !$todo.is_empty() {
		(a, b) = $todo.last() ?? (0, 0)
		$todo = $todo.drop_last(1)
		i = first_region(regions, a)
		match regions.get(i) {
			Ok(r) if r.head < b => {
				# The bytes before the entries, with the head of the map.
				$res = $res.concat(out.sublist({ start: a, len: r.at - a }))
				$todo = (orders.get(i) ?? []).fold_rev($todo.append((r.end, b)), |span, todo| todo.append(span))
			}
			_ => {
				$res = $res.concat(out.sublist({ start: a, len: b - a }))
			}
		}
	}
	$res
}

## The index of the first region with its head at `pos` or after it (a binary search). A span of entries starts after
## the head of its own map, so the search does not find that map again.
first_region : List(Region), U64 -> U64
first_region = |regions, pos| {
	var $lo = 0
	var $hi = regions.len()
	while $lo < $hi {
		mid = ($lo + $hi) // 2
		if (regions.get(mid).map_ok(|r| r.head) ?? 0) < pos {
			$lo = mid + 1
		} else {
			$hi = mid
		}
	}
	$lo
}

## The walk rules and the encoding value of a parse with `options`.
## One pass over `allow`: a parse with no leniency does no work for them.
parse_setup : Cbor.Options -> { rules : Rules, cbor : Cbor }
parse_setup = |options| {
	start = {
		..strict_read,
		camel: (options.?fields ?? Snake) == Camel,
		reject_unknown: (options.?unknown_fields ?? Skip) == Reject,
	}
	read = (options.?allow ?? []).fold(
		start,
		|r, leniency|
			match leniency {
				BoolFromInt => { ..r, bool_from_int: Bool.True }
				FloatToInt => { ..r, float_to_int: Bool.True }
				IntFromText => { ..r, int_from_text: Bool.True }
				DecFromText => { ..r, dec_from_text: Bool.True }
				NullAsAbsent => { ..r, null_as_absent: Bool.True }
				UndefinedAsNull => { ..r, undefined_as_null: Bool.True }
				PaddedNumbers => { ..r, padded: Bool.True }
				BytesFromArray => { ..r, bytes_from_array: Bool.True }
				BytesFromBase64 => { ..r, bytes_from_base64: Bool.True }
				IndefiniteLength => { ..r, indefinite: Bool.True }
			},
	)
	rules = {
		max_depth: options.?max_depth ?? 512,
		max_items: options.?max_items ?? U64.highest,
		shortest_heads: !read.padded,
		indefinite: read.indefinite,
		keys: match options.?duplicate_keys ?? Reject {
			Reject => Reject
			First => First
			Last => Last
		},
		order: match options.?key_order ?? Any {
			Any => Any
			Sorted => Sorted
		},
	}
	{ rules, cbor: Cbor.{ fields: Snake, read, ignore_tags: options.?ignore_tags ?? [], unions: options.?unions ?? External, content: no_content, next: no_next } }
}

## Reads the root item at `pos` with `parse_shape`, and gives the position after it.
## The checks of the whole item come first (`walk`), so each parse agrees with `Cbor.Value` and has a bounded size.
## The walk also gives the keys that `duplicate_keys` skips. The typed read must end where the item ends.
parse_one : List(U8), U64, Rules, (Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), ..errs])) -> Try({ value : a, next : U64 }, [InvalidCbor(U64), ..errs])
parse_one = |bytes, pos, rules, parse_shape| {
	walked = walk(at(reader(bytes), pos), rules, Bool.False)?
	parsed = parse_shape(at(walked, pos))?
	if (parsed.rest.pos == walked.pos) Ok({ value: parsed.value, next: walked.pos }) else Err(InvalidCbor(parsed.rest.pos))
}

## The encoding of a write, with the record keys in the case `fields`.
with_fields : [Snake, Camel] -> Cbor
with_fields = |fields| Cbor.{ fields, read: strict_read, ignore_tags: [], unions: External, content: no_content, next: no_next }

## A Dec in attos: an integer when it has no fraction and fits major type 0 or 1, else a decimal fraction.
put_dec : List(U8), I128 -> List(U8)
put_dec = |out, attos| {
	whole = attos // dec_scale
	if attos % dec_scale == 0 and whole >= 0 and whole <= 18446744073709551615 {
		put_head(out, 0, whole.to_u64_wrap())
	} else if attos % dec_scale == 0 and whole < 0 and whole >= -18446744073709551616 {
		put_head(out, 1, (-1 - whole).to_u64_wrap())
	} else {
		put_decimal_fraction(out, attos)
	}
}

## A decimal fraction (RFC 8949 3.4.4): the tag 4, then an array of 2: the exponent e and the mantissa m.
## The value is m * 10^e, read exactly. It is an error at the tag when it has more than 18 fraction
## digits or is outside the range of a Dec. `lenient` (`PaddedNumbers`): a bignum mantissa need not be the preferred serialization.
decimal_fraction : Cbor.Reader, Bool -> Try({ value : Dec, rest : Cbor.Reader }, [InvalidCbor(U64)])
decimal_fraction = |state, lenient| {
	bad = InvalidCbor(state.pos)
	strict = plain
	tag = head(state)?
	arr = head(at(state, tag.next))?
	if tag.arg != 4 or arr.major != 4 or arr.arg != 2 {
		return Err(bad)
	}
	e = int(strict, at(state, arr.next))?
	m = dec_mantissa(e.rest, lenient)?
	attos = scale_pow10(m.value, e.value + 18) ? |_| bad
	Ok({ value: Dec.from_attos(attos), rest: m.rest })
}

## The mantissa of a decimal fraction: an integer, or a bignum (tag 2 or 3 with a byte string, `bignum`).
dec_mantissa : Cbor.Reader, Bool -> Try({ value : I128, rest : Cbor.Reader }, [InvalidCbor(U64)])
dec_mantissa = |state, lenient| {
	h = head(state)?
	if h.major == 0 or h.major == 1 {
		int(plain, state)
	} else {
		n = bignum(state, lenient)?
		i = n.size.to_i128_try() ? |_| InvalidCbor(state.pos)
		Ok({ value: if (n.negative) -1 - i else i, rest: n.rest })
	}
}

## A bignum at `state` (RFC 8949 3.4.3): tag 2 and a byte string n, or tag 3 and n for -1 - n. n has 16 bytes or less
## (with no leading zero bytes). Strict, it is the preferred serialization (RFC 8949 4.2.2): no leading zero byte, and more
## than 8 bytes, else major type 0 or 1 is the form. `lenient` (`PaddedNumbers`) reads both.
## A byte string (major type 2), with the reader's own error: `Cbor.parse_bytes` without the codec protocol's
## wider error, for the readers inside this module.
bytes_item : Cbor, Cbor.Reader -> Try({ value : List(U8), rest : Cbor.Reader }, [InvalidCbor(U64)])
bytes_item = |cbor, tagged| {
	b = string_at(untag(cbor, tagged)?, 2)?
	Ok({ value: b.bytes, rest: b.rest })
}

bignum : Cbor.Reader, Bool -> Try({ negative : Bool, size : U128, rest : Cbor.Reader }, [InvalidCbor(U64)])
bignum = |state, lenient| {
	h = head(state)?
	if h.major != 6 or (h.arg != 2 and h.arg != 3) {
		return Err(InvalidCbor(state.pos))
	}
	b = bytes_item(plain, at(state, h.next))?
	var $lead = 0.U64
	for byte in b.value {
		if byte != 0 {
			break
		}
		$lead = $lead + 1
	}
	digits = b.value.drop_first($lead)
	if digits.len() > 16 or (!lenient and ($lead > 0 or digits.len() <= 8)) {
		return Err(InvalidCbor(state.pos))
	}
	size = digits.fold(0.U128, |acc, x| acc.shl_wrap(8).bitwise_or(x.to_u128()))
	Ok({ negative: h.arg == 3, size, rest: b.rest })
}

## An integer of a `U128` or an `I128` at `state`: a bignum (`bignum`), or an integer with the rules of `int`.
## The value is `size`, or -1 - `size` when `negative`.
wide : Cbor, Cbor.Reader -> Try({ negative : Bool, size : U128, rest : Cbor.Reader }, [InvalidCbor(U64)])
wide = |cbor, tagged| {
	state = untag(cbor, tagged)?
	h = head(state)?
	if h.major == 6 {
		bignum(state, cbor.read.padded)
	} else if h.major == 3 and cbor.read.int_from_text {
		# All digits of a U128 and an I128: `int` gives an I128, which does not hold each U128.
		t = text_head(state)?
		d = decimal(t.name) ? |_| InvalidCbor(state.pos)
		# -n is -1 - (n - 1). n is 1 or more: `-0` is not canonical.
		Ok({ negative: d.negative, size: if (d.negative) d.size - 1 else d.size, rest: t.rest })
	} else {
		n = int(cbor, state)?
		negative = n.value < 0
		Ok({ negative, size: (if (negative) -1 - n.value else n.value).to_u128_wrap(), rest: n.rest })
	}
}

## m * 10^shift as an integer: a negative shift needs a mantissa that divides, else an error.
## A mantissa of 127 bits has at most 39 digits, so each loop ends in 39 steps or less, also for a huge shift.
scale_pow10 : I128, I128 -> Try(I128, [OutOfRange])
scale_pow10 = |m, shift| {
	if m == 0 {
		return Ok(0)
	}
	var $v = m
	if shift >= 0 {
		for _ in (0.I128).until(shift) {
			$v = $v.times_try(10) ? |_| OutOfRange
		}
	} else {
		for _ in (0.I128).until(-shift) {
			if $v % 10 != 0 {
				return Err(OutOfRange)
			}
			$v = $v // 10
		}
	}
	Ok($v)
}

## The decimal fraction of `attos` (a nonzero count of 10^-18): the tag 4, `[exponent, mantissa]`.
## The exponent starts at -18, and each trailing zero digit of the mantissa moves to the exponent.
put_decimal_fraction : List(U8), I128 -> List(U8)
put_decimal_fraction = |out, attos| {
	var $m = attos
	var $e = -18.I64
	while $m % 10 == 0 {
		$m = $m // 10
		$e = $e + 1
	}
	put_mantissa(put_int(out.append(0xc4).append(0x82), $e), $m)
}

## An integer when it fits major type 0 or 1, else a bignum: tag 2 (tag 3: -1 - n) and a byte string.
put_mantissa : List(U8), I128 -> List(U8)
put_mantissa = |out, m|
	if m >= 0 {
		put_big(out, Bool.False, m.to_u128_wrap())
	} else {
		put_big(out, Bool.True, (-1 - m).to_u128_wrap())
	}

## The integer `n` (or -1 - `n` when `negative`): major type 0 or 1 when `n` fits 64 bits, else a bignum (RFC 8949 3.4.3):
## tag 2 (tag 3 when `negative`) and a byte string of `n` with no leading zero byte, the preferred serialization.
put_big : List(U8), Bool, U128 -> List(U8)
put_big = |out, negative, n|
	if n <= 18446744073709551615 {
		put_head(out, if (negative) 1 else 0, n.to_u64_wrap())
	} else {
		all : List(U8)
		all = (0.U64).until(16).map(|i| n.shr_zf_wrap((8 * (15 - i)).to_u8_wrap()).to_u8_wrap()).collect()
		var $lead = 0.U64
		for byte in all {
			if byte != 0 {
				break
			}
			$lead = $lead + 1
		}
		digits = all.drop_first($lead)
		put_head(out.append(if (negative) 0xc3 else 0xc2), 2, digits.len()).concat(digits)
	}

## One Dec unit is 10^-18, so a whole number n is n * dec_scale attos.
dec_scale : I128
dec_scale = 1_000_000_000_000_000_000

## The rules of the typed readers: one Bool for each lenient read, the case of the keys, and the rule for unknown fields.
ReadRules : {
	camel : Bool,
	reject_unknown : Bool,
	bool_from_int : Bool,
	float_to_int : Bool,
	int_from_text : Bool,
	dec_from_text : Bool,
	null_as_absent : Bool,
	undefined_as_null : Bool,
	bytes_from_array : Bool,
	bytes_from_base64 : Bool,
	padded : Bool,
	indefinite : Bool,
}

## The strict rules of `parse`.
strict_read : ReadRules
strict_read = {
	camel: Bool.False,
	reject_unknown: Bool.False,
	bool_from_int: Bool.False,
	float_to_int: Bool.False,
	int_from_text: Bool.False,
	dec_from_text: Bool.False,
	null_as_absent: Bool.False,
	undefined_as_null: Bool.False,
	bytes_from_array: Bool.False,
	bytes_from_base64: Bool.False,
	padded: Bool.False,
	indefinite: Bool.False,
}

## The options of `parse` and `encode`.
plain : Cbor
plain = with_fields(Snake)

## `cbor` with no text for an integer: the integers of a `Bool`, a `Cbor.U8Array`.
no_text : Cbor -> Cbor
no_text = |cbor| {
	Cbor.{ fields, read, ignore_tags, unions, content, next } = cbor
	Cbor.{ fields, read: { ..read, int_from_text: Bool.False }, ignore_tags, unions, content, next }
}

## No position: the start of no item.
no_pos : U64
no_pos = U64.highest

no_content : { at : U64, to : U64, tag : U64 }
no_content = { at: no_pos, to: no_pos, tag: no_pos }

no_next : { at : U64, unions : Cbor.Unions, tags : [Exact, Upper, Lower] }
no_next = { at: no_pos, unions: External, tags: Exact }

## `cbor` with other `content` and `next`.
with_positions : Cbor, { at : U64, to : U64, tag : U64 }, { at : U64, unions : Cbor.Unions, tags : [Exact, Upper, Lower] } -> Cbor
with_positions = |cbor, content, next| Cbor.{ fields: cbor.fields, read: cbor.read, ignore_tags: cbor.ignore_tags, unions: cbor.unions, content, next }

## A key of a `Dict` is `parsed` from `state` only when it is the form that the writer writes for its value: the same
## bytes as `Cbor.encode` of the value, with the shortest heads and each float as an f64 on both sides. A lenient read
## of a key (a float, text or `0` for a `Bool`, a bignum with a leading zero) is an error. So two keys of one map that
## are not the same `Cbor.Value` (the walk checked it) never give the same Roc key, and no key of the input is lost.
exact_key : Cbor.Reader, { value : a, rest : Cbor.Reader } -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64)]) where [a.Cbor.Encodable([])]
exact_key = |state, parsed| exact_key_dups(state, parsed, Keep)

## `exact_key` with the rule `dups` for the maps in the key (`canonical`). A key of `Cbor.Entries` can be a composite
## type: with `duplicate_keys: First` or `Last` (`key_dups`), a map in the key is its `Cbor.Value`, with one entry of
## each key, as the walk compares the keys. A key of a `Dict` is a number or a `Bool`, with no map: `Keep`.
exact_key_dups : Cbor.Reader, { value : a, rest : Cbor.Reader }, [Keep, First, Last] -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64)]) where [a.Cbor.Encodable([])]
exact_key_dups = |state, parsed, dups| {
	written = Cbor.encode(parsed.value)
	if canonical(state.bytes, state.pos, parsed.rest.pos, dups) == canonical(written, 0, written.len(), Keep) {
		Ok(parsed)
	} else {
		Err(InvalidCbor(state.pos))
	}
}

## The item at `state` is read as it is: not a byte of a byte string read as a `List(U8)`, not the map of an internal
## tag (`at_content`), and no tag of `ignore_tags` can be before it (`skip_tags`). Then `untag` gives `state`.
plain_at : Cbor, Cbor.Reader -> Bool
plain_at = |cbor, state| state.raw == 0 and state.pos != cbor.content.at and cbor.ignore_tags.is_empty()

## A text of 255 bytes or less with a head of 1 or 2 bytes (`60` to `78`) at a plain position (`plain_at`): the fast path of
## `parse_str` and of a record key. `NotShort` for each other case, and for invalid UTF-8 (the slow path gives the error).
short_text : Cbor, Cbor.Reader -> Try({ value : Str, rest : Cbor.Reader }, [NotShort])
short_text = |cbor, state| if (plain_at(cbor, state)) short_text_at(state) else Err(NotShort)

## `short_text` with no check of the position, for a reader that reads the text where it is (a `Dict` key, `text`).
## Not in a byte string read as a `List(U8)` (`raw`).
short_text_at : Cbor.Reader -> Try({ value : Str, rest : Cbor.Reader }, [NotShort])
short_text_at = |state| {
	b = state.bytes.get(state.pos) ? |_| NotShort
	if b < 0x60 or b > 0x78 or state.raw > 0 {
		return Err(NotShort)
	}
	# `78`: the length is the next byte (24 to 255 bytes).
	(len, start) =
		if b == 0x78 {
			((state.bytes.get(state.pos + 1) ? |_| NotShort).to_u64(), state.pos + 2)
		} else {
			((b - 0x60).to_u64(), state.pos + 1)
		}
	if len > state.bytes.len() - start {
		return Err(NotShort)
	}
	value = Str.from_utf8(state.bytes.sublist({ start, len })) ? |_| NotShort
	Ok({ value, rest: at(state, start + len) })
}

## The item that the reader of a type reads at `state`: the item at the content key when `state` is at the map
## of an internal tag with one payload (`at_content`), then with no tag of the option `ignore_tags` (`skip_tags`).
untag : Cbor, Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64)])
untag = |cbor, state| Ok(skip_tags(cbor, at_content(cbor, state)?))

## At the map of an internal tag with one payload that is not a record: the item at the content key.
## No content key is an error at the map.
at_content : Cbor, Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64)])
at_content = |cbor, state|
	# A byte of a byte string is never the map of a tag: the bytes of base64 text are not the input.
	if state.pos != cbor.content.at or state.raw > 0 {
		Ok(state)
	} else if cbor.content.to == no_pos {
		Err(InvalidCbor(state.pos))
	} else {
		Ok(at(state, cbor.content.to))
	}

## One scan of the map of an internal tag at `state`: the positions of the text keys `tag` and `content` and of their
## values (`no_pos` when there is no such key), and the end of the map. Each key must be text, else an error
## at the map. A key that `duplicate_keys` skips is not read. The walk of each value keeps the end of each map
## in it, so a nested union does not walk it again.
scan_union : Cbor.Reader, { tag : Str, content : Str } -> Try({ tag_key : U64, tag : U64, content : U64, end : Cbor.Reader }, [InvalidCbor(U64)])
scan_union = |state, keys| {
	h = head(state)?
	until_end = indefinite_at(h, state.pos)
	var $s = at(state, h.next)
	var $tag_key = no_pos
	var $tag = no_pos
	var $content = no_pos
	var $left = h.arg
	while $left > 0 and !(until_end and at_break($s)) {
		$left = $left - 1
		k = text($s) ? |_| InvalidCbor(state.pos)
		if !skipped($s) {
			if k.value == keys.tag {
				$tag_key = $s.pos
				$tag = k.rest.pos
			}
			if k.value == keys.content {
				$content = k.rest.pos
			}
		}
		$s = walk(k.rest, any_length, Bool.True)?
	}
	Ok({ tag_key: $tag_key, tag: $tag, content: $content, end: if (until_end) at($s, $s.pos + 1) else $s })
}

## The key at `state` is a key that `duplicate_keys` (`First`, `Last`) skips.
skipped : Cbor.Reader -> Bool
skipped = |state|
	match state.memo {
		Plain => Bool.False
		Memo(b) => sorted_has(Box.unbox(b).skips, state.pos)
	}

## `n` is in the sorted list `list`: a binary search.
sorted_has : List(U64), U64 -> Bool
sorted_has = |list, n| {
	var $lo = 0.U64
	var $hi = list.len()
	while $lo < $hi {
		mid = ($lo + $hi) // 2
		v = list.get(mid) ?? 0
		if v == n {
			return Bool.True
		}
		if v < n {
			$lo = mid + 1
		} else {
			$hi = mid
		}
	}
	Bool.False
}

## In an uncounted `Dict`: skips each entry at `state` with a key that `duplicate_keys` skips, one entry less for each.
skip_entries : Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64)])
skip_entries = |state| {
	var $s = state
	while skipped($s) {
		m = memo_of($s)
		left =
			match m.dicts.last() {
				Ok(Left(0)) | Err(_) => break
				Ok(Left(n)) => Left(n - 1)
				Ok(UntilBreak) => UntilBreak
			}
		$s = with_memo(skip(skip($s)?)?, { ..m, dicts: m.dicts.set(m.dicts.len() - 1, left) ?? m.dicts })
	}
	Ok($s)
}

## The array of the `count` payloads of a tag at `state` (with no tag of `ignore_tags`): the reader at its first payload.
## An indefinite length reads too, and `payloads_end` reads its break.
payloads_start : Cbor, Cbor.Reader, U64 -> Try(Cbor.Reader, [InvalidCbor(U64)])
payloads_start = |cbor, tagged, count| {
	payloads = untag(cbor, tagged)?
	t = head(payloads)?
	if (t.major == 4 and (t.arg == count or indefinite_at(t, payloads.pos))) Ok(at(payloads, t.next)) else Err(InvalidCbor(payloads.pos))
}

## After the last payload (`after`) of the payload array at `tagged`: the reader after its break, when it has an indefinite length.
payloads_end : Cbor, Cbor.Reader, Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64)])
payloads_end = |cbor, tagged, after| {
	payloads = untag(cbor, tagged)?
	t = head(payloads)?
	if !indefinite_at(t, payloads.pos) {
		Ok(after)
	} else if at_break(after) {
		Ok(at(after, after.pos + 1))
	} else {
		Err(InvalidCbor(after.pos))
	}
}

## In an uncounted `Dict`, before an entry: skips the entries of keys to skip, then `End` after the last entry
## (and after the break of an indefinite length), else `More` at the next key.
dict_step : Cbor.Reader -> Try([More(Cbor.Reader), End(Cbor.Reader)], [InvalidCbor(U64)])
dict_step = |state| {
	s = skip_entries(state)?
	m = memo_of(s)
	match m.dicts.last() {
		Ok(Left(0)) => Ok(End(with_memo(s, { ..m, dicts: m.dicts.drop_last(1) })))
		Ok(UntilBreak) if at_break(s) => Ok(End(at(with_memo(s, { ..m, dicts: m.dicts.drop_last(1) }), s.pos + 1)))
		_ => Ok(More(s))
	}
}

## In an uncounted list (an array or a byte string of indefinite length), before an item: `End` after the break,
## else `More` at the next item. In a byte string, `More` is at the next byte, with the bytes left of its chunk in `raw`.
list_step : Cbor.Reader -> Try([More(Cbor.Reader), End(Cbor.Reader)], [InvalidCbor(U64)])
list_step = |state| {
	if !state.chunks {
		return if (at_break(state)) Ok(End(at(state, state.pos + 1))) else Ok(More(state))
	}
	var $s = state
	# Each step moves on 1 byte or more: past the head of an empty chunk.
	while $s.raw == 0 {
		if base64_end($s) {
			return Ok(End(back_from_base64($s)))
		}
		if at_break($s) {
			return Ok(End({ ..at($s, $s.pos + 1), chunks: Bool.False }))
		}
		c = head($s)?
		if c.major != 2 or indefinite_at(c, $s.pos) or c.arg > $s.bytes.len() - c.next {
			return Err(InvalidCbor($s.pos))
		}
		$s = moved($s, c.next, c.arg)
	}
	Ok(More($s))
}

## Base64 text read as a `List(U8)` (`BytesFromBase64`). The bytes go in a new reader as one chunk of a byte string of
## indefinite length, so that `list_step` goes back to the input after the last byte (`back_from_base64`).
## The text that is not base64 is an error at the text.
base64_list : Cbor.Reader -> Try([Counted({ len : U64, rest : Cbor.Reader }), Uncounted(Cbor.Reader)], [InvalidCbor(U64)])
base64_list = |state| {
	t = text_head(state)?
	decoded = from_base64(t.name) ? |_| InvalidCbor(state.pos)
	if decoded.is_empty() {
		return Ok(Counted({ len: 0, rest: t.rest }))
	}
	m = memo_of(state)
	outer = { bytes: state.bytes, at: state.pos, next: t.rest.pos, array: state.array }
	inner = Cbor.Reader.{ bytes: decoded, pos: 0, raw: decoded.len(), array: no_pos, chunks: Bool.True, memo: Plain }
	Ok(Uncounted(with_memo(inner, { ..m, outer: m.outer.append(outer) })))
}

## `state` is after the last byte of base64 text read as a `List(U8)`.
base64_end : Cbor.Reader -> Bool
base64_end = |state|
	match state.memo {
		Plain => Bool.False
		Memo(b) => !Box.unbox(b).outer.is_empty()
	}

## The reader of the input after the base64 text that `state` read.
back_from_base64 : Cbor.Reader -> Cbor.Reader
back_from_base64 = |state| {
	m = memo_of(state)
	o = m.outer.last() ?? { bytes: [], at: 0, next: 0, array: no_pos }
	back = Cbor.Reader.{ bytes: o.bytes, pos: o.next, raw: 0, array: o.array, chunks: Bool.False, memo: Plain }
	with_memo(back, { ..m, outer: m.outer.drop_last(1) })
}

## The position of an error at `state`. In the bytes of base64 text (`base64_list`), the position of the text:
## these bytes are not the input.
error_pos : Cbor.Reader -> U64
error_pos = |state|
	if state.raw == 0 {
		state.pos
	} else {
		match memo_of(state).outer.last() {
			Ok(o) => o.at
			Err(_) => state.pos
		}
	}

## The bytes of base64 text (RFC 4648 4): the alphabet `A-Z a-z 0-9 + /`, with `=` padding to a multiple of 4 characters.
## No white space. The unused bits before the padding must be zero (RFC 4648 3.5), so each byte list has one text.
## One pass, and one append for each byte to a list of the right capacity.
from_base64 : List(U8) -> Try(List(U8), [NotBase64])
from_base64 = |chars| {
	n = chars.len()
	if n % 4 != 0 {
		return Err(NotBase64)
	}
	if n == 0 {
		return Ok([])
	}
	pad =
		if chars.get(n - 1) != Ok('=') {
			0
		} else if chars.get(n - 2) != Ok('=') {
			1
		} else {
			2
		}
	var $out = List.with_capacity(n // 4 * 3 - pad)
	var $i = 0
	while $i < n {
		# The characters of this group that are not padding: 4, or 2 or 3 in the last group.
		used = if ($i + 4 == n) 4 - pad else 4
		a = sextet(chars.get($i) ?? 0)
		b = sextet(chars.get($i + 1) ?? 0)
		c = if (used > 2) sextet(chars.get($i + 2) ?? 0) else 0
		d = if (used > 3) sextet(chars.get($i + 3) ?? 0) else 0
		if a > 63 or b > 63 or c > 63 or d > 63 {
			return Err(NotBase64)
		}
		$out = $out.append(a.shl_wrap(2).bitwise_or(b.shr_zf_wrap(4)))
		if used == 2 {
			if b.bitwise_and(15) != 0 {
				return Err(NotBase64)
			}
		} else {
			$out = $out.append(b.shl_wrap(4).bitwise_or(c.shr_zf_wrap(2)))
			if used == 3 {
				if c.bitwise_and(3) != 0 {
					return Err(NotBase64)
				}
			} else {
				$out = $out.append(c.shl_wrap(6).bitwise_or(d))
			}
		}
		$i = $i + 4
	}
	Ok($out)
}

## The value of a base64 character (RFC 4648 4), or 255 for another byte (also `=`).
sextet : U8 -> U8
sextet = |c|
	if c >= 'A' and c <= 'Z' {
		c - 'A'
	} else if c >= 'a' and c <= 'z' {
		c - 'a' + 26
	} else if c >= '0' and c <= '9' {
		c - '0' + 52
	} else if c == '+' {
		62
	} else if c == '/' {
		63
	} else {
		255
	}

## The item at `state` is `null`, or `undefined` with `UndefinedAsNull`.
is_null : Cbor, Cbor.Reader -> Bool
is_null = |cbor, state|
	if state.raw > 0 {
		Bool.False
	} else {
		match state.bytes.get(state.pos) {
			Ok(0xf6) => Bool.True
			Ok(0xf7) => cbor.read.undefined_as_null
			_ => Bool.False
		}
	}

## `state` is at the first item of the array at `state.array`, and each item of the array is an integer 0 to 255:
## the form of a byte string that the writer never writes. One scan of the item heads, at the first item only.
bytes_as_array : Cbor.Reader -> Bool
bytes_as_array = |state|
	match head_at(state.bytes, state.array, any_length) {
		Ok(h) if h.next == state.pos => {
			# An indefinite length: the items until the break.
			until_end = indefinite_at(h, state.array)
			var $p = h.next
			var $left = h.arg
			while $left > 0 and !(until_end and state.bytes.get($p) == Ok(0xff)) {
				$left = $left - 1
				match head_at(state.bytes, $p, loose) {
					Ok(it) if it.major == 0 and it.arg <= 255 => {
						$p = it.next
					}
					_ => return Bool.False
				}
			}
			Bool.True
		}
		_ => Bool.False
	}

## The text key `name` (its UTF-8 bytes) is the key of the field `field`: the same bytes, or with `camel` the bytes
## of `Json.snake_to_camel(field)`: each `_` goes, and a small letter after a `_` is a capital. No copy of a name.
key_matches : Bool, List(U8), List(U8) -> Bool
key_matches = |camel, name, field|
	if !camel {
		name == field
	} else {
		var $i = 0.U64
		var $k = 0.U64
		var $after = Bool.False
		while $k < field.len() {
			b = field.get($k) ?? 0
			$k = $k + 1
			if b == '_' {
				$after = Bool.True
			} else {
				want = if ($after and b >= 'a' and b <= 'z') b - 32 else b
				if name.get($i) != Ok(want) {
					return Bool.False
				}
				$i = $i + 1
				$after = Bool.False
			}
		}
		$i == name.len()
	}

## The text key `key` (its UTF-8 bytes `key_bytes`) is the key of the field `field` (`key_matches`), with no copy in most cases.
## Snake: the same text. Camel: each `_` goes, so a field shorter than `key` is not its field, and a field of the
## same length must be `key` with no `_`. A longer field has a `_`: the part before the first `_` is not changed, so `key` must
## start with it. Only a field that passes these checks is compared byte by byte.
field_matches : Bool, Str, List(U8), Str -> Bool
field_matches = |camel, key, key_bytes, field| {
	field_len = field.count_utf8_bytes()
	if !camel {
		key == field
	} else if field_len == key_bytes.len() {
		key == field and !field.contains("_")
	} else if field_len < key_bytes.len() {
		Bool.False
	} else {
		match field.split_first("_") {
			Ok({ before, .. }) => key.starts_with(before) and key_matches(Bool.True, key_bytes, field.to_utf8())
			Err(_) => Bool.False
		}
	}
}

## The UTF-8 bytes of text at `state`, and the reader after the text. The walk checked the UTF-8.
text_head : Cbor.Reader -> Try({ name : List(U8), rest : Cbor.Reader }, [InvalidCbor(U64)])
text_head = |state| {
	t = string_at(state, 3)?
	Ok({ name: t.bytes, rest: t.rest })
}

## The head of a map that reads as a record or a `Dict`.
map_start : Cbor.Reader -> Try([Counted({ len : U64, rest : Cbor.Reader }), Uncounted(Cbor.Reader)], [InvalidCbor(U64)])
map_start = |state| {
	h = head(state)?
	# Each entry is 2 bytes or more.
	if h.major == 5 and indefinite_at(h, state.pos) {
		Ok(Uncounted(at(state, h.next)))
	} else if h.major == 5 and h.arg <= (state.bytes.len() - h.next) // 2 {
		Ok(Counted({ len: h.arg, rest: at(state, h.next) }))
	} else {
		Err(InvalidCbor(state.pos))
	}
}

## The Roc tag name of the wire name `wire` in the case `case` (`Cbor.UnionOptions`). `Upper` and `Lower` take
## words of letters and digits with one `_` between two words. Each word starts with a capital, and each `_` goes.
roc_tag : [Exact, Upper, Lower], Str -> Try(Str, [NotInCase])
roc_tag = |case, wire| {
	(first, last) =
		match case {
			Exact => return Ok(wire)
			Upper => ('A', 'Z')
			Lower => ('a', 'z')
		}
	var $out = List.with_capacity(wire.count_utf8_bytes())
	var $start = Bool.True
	for b in wire.to_utf8() {
		if b == '_' {
			if $start {
				return Err(NotInCase)
			}
			$start = Bool.True
		} else if b >= '0' and b <= '9' {
			$out = $out.append(b)
			$start = Bool.False
		} else if b >= first and b <= last {
			# The small letter, then the capital at the start of a word.
			small = b.bitwise_or(0x20)
			$out = $out.append(if ($start) small - 32 else small)
			$start = Bool.False
		} else {
			return Err(NotInCase)
		}
	}
	if $start {
		return Err(NotInCase)
	}
	Str.from_utf8($out).map_err(|_| NotInCase)
}

## Skips each tag of the option `ignore_tags` before an item, so the reader of a type reads the item
## as if it had no tag. Each step moves on 1 byte or more, so the loop ends.
skip_tags : Cbor, Cbor.Reader -> Cbor.Reader
skip_tags = |cbor, state|
	if cbor.ignore_tags.is_empty() {
		state
	} else {
		var $s = state
		var $more = Bool.True
		while $more {
			match head($s) {
				Ok(h) if h.major == 6 and cbor.ignore_tags.contains(h.arg) => {
					$s = at($s, h.next)
				}
				_ => {
					$more = Bool.False
				}
			}
		}
		$s
	}

## The item of major type 7 at `state`, with the argument `arg` of its head. A simple value of
## 2 bytes (`f8`) below 32 is not well formed (RFC 8949 3.3).
simple : Cbor.Reader, U64 -> Try([SimpleFloat, SimpleBool(Bool), SimpleNull, SimpleUndefined, SimpleOther(U8)], [InvalidCbor(U64)])
simple = |state, arg| {
	info = (state.bytes.get(state.pos) ?? 0).bitwise_and(31)
	if info == 25 or info == 26 or info == 27 {
		Ok(SimpleFloat)
	} else if info == 24 {
		if (arg < 32) Err(InvalidCbor(state.pos)) else Ok(SimpleOther(arg.to_u8_wrap()))
	} else {
		match info {
			20 => Ok(SimpleBool(Bool.False))
			21 => Ok(SimpleBool(Bool.True))
			22 => Ok(SimpleNull)
			23 => Ok(SimpleUndefined)
			_ => Ok(SimpleOther(info))
		}
	}
}

## Text in the number form of JSON, `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, as an exact Dec.
## An error when it has more than 18 fraction digits (after the exponent), or is outside the range of a Dec.
dec_text : Str -> Try(Dec, [NotDecimal])
dec_text = |s| {
	bytes = s.to_utf8()
	len = bytes.len()
	neg = bytes.get(0) == Ok('-')
	int_start = if (neg) 1 else 0
	int_end = digits_end(bytes, int_start)
	# The whole part: 0, or no leading zero.
	if int_end == int_start or (int_end - int_start > 1 and bytes.get(int_start) == Ok('0')) {
		return Err(NotDecimal)
	}
	(frac_start, frac_end) =
		if bytes.get(int_end) == Ok('.') {
			(int_end + 1, digits_end(bytes, int_end + 1))
		} else {
			(int_end, int_end)
		}
	if bytes.get(int_end) == Ok('.') and frac_end == frac_start {
		return Err(NotDecimal)
	}
	(exp, end) =
		match bytes.get(frac_end) {
			Ok('e') | Ok('E') => {
				sign_len = if (bytes.get(frac_end + 1) == Ok('+') or bytes.get(frac_end + 1) == Ok('-')) 1 else 0
				e_start = frac_end + 1 + sign_len
				e_end = digits_end(bytes, e_start)
				if e_end == e_start {
					return Err(NotDecimal)
				}
				# A larger exponent changes nothing: scale_pow10 fails in 39 steps or less.
				e = bytes.sublist({ start: e_start, len: e_end - e_start }).fold(
					0.I128,
					|acc, d| {
						n = acc * 10 + (d - '0').to_i128()
						if (n > 100_000) 100_000 else n
					},
				)
				(if (bytes.get(frac_end + 1) == Ok('-')) -e else e, e_end)
			}
			_ => (0, frac_end)
		}
	if end != len {
		return Err(NotDecimal)
	}
	# The digits of the whole part and the fraction, with no trailing zero of the fraction.
	var $frac_len = frac_end - frac_start
	while $frac_len > 0 and bytes.get(frac_start + $frac_len - 1) == Ok('0') {
		$frac_len = $frac_len - 1
	}
	# The mantissa has the sign, so that -2^127 (the attos of Dec.lowest) fits.
	var $m = 0.I128
	for d in bytes.sublist({ start: int_start, len: int_end - int_start }).concat(bytes.sublist({ start: frac_start, len: $frac_len })) {
		tens = $m.times_try(10) ? |_| NotDecimal
		digit = (d - '0').to_i128()
		$m = (if (neg) tens.minus_try(digit) else tens.plus_try(digit)) ? |_| NotDecimal
	}
	attos = scale_pow10($m, exp - $frac_len.to_i128() + 18) ? |_| NotDecimal
	Ok(Dec.from_attos(attos))
}

## The position after the ASCII digits that start at `start`.
digits_end : List(U8), U64 -> U64
digits_end = |bytes, start| {
	var $i = start
	while $i < bytes.len() and (bytes.get($i) ?? 0) >= '0' and (bytes.get($i) ?? 0) <= '9' {
		$i = $i + 1
	}
	$i
}

## Reads one whole item as a `Cbor.Value`. A loop with a list of the open arrays, maps and tags, not a recursion.
## The walk of the root item did the checks (`item_at`, depth, an indefinite length only with `IndefiniteLength`).
## An entry with a key that `duplicate_keys` skips is not in the map. An item of indefinite length gives the same value as
## its definite form: the chunks of a string are joined, and an array or a map ends at its break.
## `values` has the items of the open arrays and maps that are complete. Each open container has the
## position of its first item in `values`.
read_value : Cbor.Reader -> Try({ value : Cbor.Value, rest : Cbor.Reader }, [InvalidCbor(U64)])
read_value = |state| {
	if state.raw > 0 {
		return Err(InvalidCbor(error_pos(state)))
	}
	var $pos = state.pos
	var $frames = []
	var $values = []
	var $root = Err(NotDone)
	while $root == Err(NotDone) {
		# The open array or map of indefinite length ends at its break: then it is a whole value.
		closed =
			match $frames.last() {
				Ok(f) if f.left > state.bytes.len() and state.bytes.get($pos) == Ok(0xff) => Ok(f)
				_ => Err(NoBreak)
			}
		step =
			match closed {
				Ok(f) => {
					$pos = $pos + 1
					$frames = $frames.drop_last(1)
					items = $values.drop_first(f.start)
					$values = $values.take_first(f.start)
					Item(frame_value(f.kind, items))
				}
				Err(_) => {
					# No UTF-8 check here: `text` below makes the `Str` with the check, and the error is at the same position.
					it = item_with(state.bytes, $pos, any_length, Bool.False)?
					# One item: a complete value, or the start of an array, a map or a tag.
					one =
						match it.major {
							0 => Item(Cbor.Value.Int(Cbor.IntValue.(it.arg.to_i128())))
							1 => Item(Cbor.Value.Int(Cbor.IntValue.(-1 - it.arg.to_i128())))
							# A string of definite length is the `arg` bytes before `next`: no second read of its head.
							2 if !indefinite_string(state.bytes, $pos) => Item(Cbor.Value.Bytes(state.bytes.sublist({ start: it.next - it.arg, len: it.arg })))
							3 if !indefinite_string(state.bytes, $pos) =>
								match Str.from_utf8(state.bytes.sublist({ start: it.next - it.arg, len: it.arg })) {
									Ok(t) => Item(Cbor.Value.Text(t))
									Err(_) => return Err(InvalidCbor($pos))
								}
							2 => Item(Cbor.Value.Bytes(string_at(at(state, $pos), 2)?.bytes))
							3 => Item(Cbor.Value.Text(text(at(state, $pos))?.value))
							7 =>
								match simple(at(state, $pos), it.arg)? {
									SimpleFloat => Item(Cbor.Value.Float(float(at(state, $pos))?.value))
									SimpleBool(b) => Item(Cbor.Value.Bool(b))
									SimpleNull => Item(Cbor.Value.Null)
									SimpleUndefined => Item(Cbor.Value.Undefined)
									SimpleOther(n) => Item(Cbor.Value.Simple(Cbor.SimpleValue.(n)))
								}
							4 if it.items == 0 => Item(Cbor.Value.Array([]))
							5 if it.items == 0 => Item(Cbor.Value.Map(Cbor.ValueMap.([])))
							# An indefinite length has `until_break` items: more than the bytes, so the break ends it.
							4 => Open({ kind: ArrayFrame, left: it.items })
							5 => Open({ kind: MapFrame, left: it.items })
							_ => Open({ kind: TagFrame(it.arg), left: 1 })
						}
					$pos = it.next
					one
				}
			}
		match step {
			Open(f) => {
				# The first key of a map can be a key to skip (`Last`). One instance of each key stays.
				skipped_to = if (f.kind == MapFrame) skip_keys(at(state, $pos), f.left)? else { pos: $pos, left: f.left }
				$pos = skipped_to.pos
				# Room for the items of a definite length at once (an indefinite length has more items than bytes).
				if skipped_to.left <= state.bytes.len() {
					$values = $values.reserve(skipped_to.left)
				}
				$frames = $frames.append({ kind: f.kind, left: skipped_to.left, start: $values.len() })
			}
			Item(first) => {
				# Close each container that has all its items now.
				var $v = first
				var $closing = Bool.True
				while $closing {
					match $frames.last() {
						Err(_) => {
							$root = Ok($v)
							$closing = Bool.False
						}
						Ok(top) => {
							# After a value of a map: skip the entries of the keys to skip.
							next = if (top.kind == MapFrame and top.left % 2 == 1) skip_keys(at(state, $pos), top.left - 1)? else { pos: $pos, left: top.left - 1 }
							$pos = next.pos
							if next.left > 0 {
								$values = $values.append($v)
								$frames = $frames.drop_last(1).append({ kind: top.kind, left: next.left, start: top.start })
								$closing = Bool.False
							} else {
								$frames = $frames.drop_last(1)
								$v = close_frame(top.kind, $values, top.start, $v)
								$values = $values.take_first(top.start)
							}
						}
					}
				}
			}
		}
	}
	match $root {
		Ok(v) => Ok({ value: v, rest: at(state, $pos) })
		Err(NotDone) => Err(InvalidCbor(state.pos))
	}
}

## The head at `p` is a string of indefinite length (`5f` or `7f`): its chunks are joined.
indefinite_string : List(U8), U64 -> Bool
indefinite_string = |bytes, p| (bytes.get(p) ?? 0).bitwise_and(31) == 31

## The value of a whole array, map or tag: its items are `values` from `start`, then `last`. A map takes its pairs from
## `values` in place: no list of its items first (`frame_value`), so one copy of the items less.
close_frame : [TagFrame(U64), ArrayFrame, MapFrame], List(Cbor.Value), U64, Cbor.Value -> Cbor.Value
close_frame = |kind, values, start, last|
	match kind {
		MapFrame => {
			n = values.len() - start
			var $pairs = List.with_capacity((n + 1) // 2)
			var $i = start
			while $i + 1 < values.len() {
				$pairs = $pairs.append((values.get($i) ?? Cbor.Value.Null, values.get($i + 1) ?? Cbor.Value.Null))
				$i = $i + 2
			}
			# The key of the last pair is the last of `values`, and `last` is its value.
			Cbor.Value.Map(Cbor.ValueMap.($pairs.append((values.get($i) ?? Cbor.Value.Null, last))))
		}
		_ => frame_value(kind, values.drop_first(start).append(last))
	}

## The value of a whole array, map or tag from its items.
frame_value : [TagFrame(U64), ArrayFrame, MapFrame], List(Cbor.Value) -> Cbor.Value
frame_value = |kind, items|
	match kind {
		TagFrame(n) => Cbor.Value.Tag(n, items.first() ?? Cbor.Value.Null)
		ArrayFrame => Cbor.Value.Array(items)
		MapFrame => Cbor.Value.Map(Cbor.ValueMap.(map_pairs(items)))
	}

## At a key of a map with `left` items left: skips each entry with a key that `duplicate_keys` skips.
skip_keys : Cbor.Reader, U64 -> Try({ pos : U64, left : U64 }, [InvalidCbor(U64)])
skip_keys = |state, left| {
	var $s = state
	var $left = left
	while $left > 0 and skipped($s) {
		$s = skip(skip($s)?)?
		$left = $left - 2
	}
	Ok({ pos: $s.pos, left: $left })
}

## The items of a map, in pairs of a key and a value.
map_pairs : List(Cbor.Value) -> List((Cbor.Value, Cbor.Value))
map_pairs = |items| {
	var $pairs = List.with_capacity(items.len() // 2)
	# An index loop: `chunks_of(2)` makes a list for each pair.
	var $i = 0.U64
	while $i + 1 < items.len() {
		match (items.get($i), items.get($i + 1)) {
			(Ok(k), Ok(x)) => {
				$pairs = $pairs.append((k, x))
			}
			_ => {}
		}
		$i = $i + 2
	}
	$pairs
}

## Writes a `Cbor.Value`. A loop with a list of the values still to write, not a recursion.
put_value : List(U8), Cbor.Value -> List(U8)
put_value = |out, value| {
	var $out = out
	var $todo = [value]
	var $more = Bool.True
	while $more {
		# Take the value out of the list before the match, so that the list is not shared at the next append.
		next = $todo.last()
		$todo = $todo.drop_last(1)
		match next {
			Err(_) => {
				$more = Bool.False
			}
			Ok(v) => {
				match v {
					Int(i) => {
						$out = put_mantissa($out, i.to_i128())
					}
					Float(f) => {
						$out = put_float($out, f.to_bits())
					}
					Bytes(b) => {
						$out = put_head($out, 2, b.len()).concat(b)
					}
					Text(t) => {
						$out = put_text($out, t)
					}
					Array(items) => {
						$out = put_head($out, 4, items.len())
						# The items in reverse order, with no reversed copy of the list.
						var $i = items.len()
						while $i > 0 {
							$i = $i - 1
							$todo = $todo.append(items.get($i) ?? Null)
						}
					}
					Map(map) => {
						pairs = map.to_list()
						$out = put_head($out, 5, pairs.len())
						var $j = pairs.len()
						while $j > 0 {
							$j = $j - 1
							(k, x) = pairs.get($j) ?? (Null, Null)
							$todo = $todo.append(x).append(k)
						}
					}
					Tag(n, inner) => {
						$out = put_head($out, 6, n)
						$todo = $todo.append(inner)
					}
					Bool(b) => {
						$out = $out.append(if (b) 0xf5 else 0xf4)
					}
					Null => {
						$out = $out.append(0xf6)
					}
					Undefined => {
						$out = $out.append(0xf7)
					}
					Simple(simple_value) => {
						n = simple_value.to_u8()
						$out = if (n < 20) $out.append((0xe0.U8).bitwise_or(n)) else $out.append(0xf8).append(n)
					}
				}
			}
		}
	}
	$out
}

## `Cbor.Value.is_eq`: the same as equal bytes of `Cbor.encode`. A loop with a list of the pairs still to compare, not a recursion.
same_value : Cbor.Value, Cbor.Value -> Bool
same_value = |a, b| {
	var $todo = [(a, b)]
	while !$todo.is_empty() {
		pair = $todo.last() ?? (a, b)
		$todo = $todo.drop_last(1)
		same =
			match pair {
				(Int(x), Int(y)) => x == y
				(Float(x), Float(y)) => float_bits(x) == float_bits(y)
				(Bytes(x), Bytes(y)) => x == y
				(Text(x), Text(y)) => x == y
				(Array(xs), Array(ys)) if xs.len() == ys.len() => {
					$todo = $todo.concat(xs.map2(ys, |x, y| (x, y)))
					Bool.True
				}
				(Map(xs), Map(ys)) if xs.len() == ys.len() => {
					for ((xk, xv), (yk, yv)) in xs.to_list().map2(ys.to_list(), |x, y| (x, y)) {
						$todo = $todo.append((xk, yk)).append((xv, yv))
					}
					Bool.True
				}
				(Tag(n, x), Tag(m, y)) if n == m => {
					$todo = $todo.append((x, y))
					Bool.True
				}
				(Bool(x), Bool(y)) => x == y
				(Null, Null) | (Undefined, Undefined) => Bool.True
				(Simple(x), Simple(y)) => x == y
				_ => Bool.False
			}
		if !same {
			return Bool.False
		}
	}
	Bool.True
}

## The bits of `f`, with one NaN for each NaN: the writer writes each NaN as `f9 7e00`.
float_bits : F64 -> U64
float_bits = |f| {
	bits = f.to_bits()
	if (bits.bitwise_and(0x7fffffffffffffff) > 0x7ff0000000000000) 0x7ff8000000000000 else bits
}

## `Cbor.Value.to_hash`: a kind byte and the data of each item, in the order of the bytes. A loop, not a recursion.
hash_value : Hasher, Cbor.Value -> Hasher
hash_value = |hasher, value| {
	var $h = hasher
	var $todo = [value]
	while !$todo.is_empty() {
		v = $todo.last() ?? value
		$todo = $todo.drop_last(1)
		$h =
			match v {
				Int(i) => $h.write_u8(0).write_i128(i.to_i128())
				Float(f) => $h.write_u8(1).write_u64(float_bits(f))
				Bytes(b) => $h.write_u8(2).write_u64(b.len()).write_bytes(b)
				Text(t) => $h.write_u8(3).write_u64(t.count_utf8_bytes()).write_str(t)
				Array(items) => {
					$todo = $todo.concat(items.rev())
					$h.write_u8(4).write_u64(items.len())
				}
				Map(entries) => {
					pairs = entries.to_list()
					for (k, x) in pairs.rev() {
						$todo = $todo.append(x).append(k)
					}
					$h.write_u8(5).write_u64(pairs.len())
				}
				Tag(n, inner) => {
					$todo = $todo.append(inner)
					$h.write_u8(6).write_u64(n)
				}
				Bool(b) => $h.write_u8(if (b) 8 else 7)
				Null => $h.write_u8(9)
				Undefined => $h.write_u8(10)
				Simple(n) => $h.write_u8(11).write_u8(n.to_u8())
			}
	}
	$h
}

## The index of the first key of `keys` (the bytes of each key) that is the same as a key before it:
## the smallest second index of each run of the same bytes after a sort. O(n log n), no hash.
first_duplicate : List(List(U8)) -> Try(U64, [NoDuplicate])
first_duplicate = |keys| {
	indexes : List(U64)
	indexes = (0.U64).until(keys.len()).collect()
	order = indexes.sort_with(
		|a, b| {
			x = keys.get(a) ?? []
			y = keys.get(b) ?? []
			if x.len() != y.len() {
				if (x.len() < y.len()) Before else After
			} else {
				match compare_bytes(x, y) {
					Same => if (a < b) Before else if (a > b) After else Same
					other => other
				}
			}
		},
	)
	var $found = no_pos
	for i in (1.U64).until(keys.len()) {
		later = order.get(i) ?? 0
		if keys.get(later) == keys.get(order.get(i - 1) ?? 0) and later < $found {
			$found = later
		}
	}
	if ($found == no_pos) Err(NoDuplicate) else Ok($found)
}

at : Cbor.Reader, U64 -> Cbor.Reader
at = |state, pos| moved(state, pos, 0)

## `state` at `pos`, with `raw` bytes of a byte string left.
moved : Cbor.Reader, U64, U64 -> Cbor.Reader
moved = |state, pos, raw| Cbor.Reader.{ bytes: state.bytes, pos, raw, array: state.array, chunks: state.chunks, memo: state.memo }

## The lists of a reader that most parses do not use. They are in a box, so that a copy of a reader (one for each
## item) changes one reference count, or none (`Plain`), not one for each list.
## `skips`: the positions of the keys that `duplicate_keys` (`First`, `Last`) skips, in order. From the walk of the root item.
## `dicts`: each open uncounted `Dict`, the innermost last: the entries left in a map that has keys to skip (`Left`),
## or a map of indefinite length (`UntilBreak`).
## `tuples`: each open tuple with `IndefiniteLength`, the innermost last: it has an indefinite length.
## `map_ends`: the start and end of each map that a walk of an internal tag passed, in order of start.
## `outer`: in the bytes of base64 text read as a `List(U8)` (`base64_list`), the input and the positions to go back to.
ReaderMemo : { skips : List(U64), dicts : List([Left(U64), UntilBreak]), tuples : List(Bool), map_ends : List(U64), outer : List(Outer) }

## The input of a `List(U8)` that reads base64 text: the bytes, the position of the text, the position after it, and `array`.
Outer : { bytes : List(U8), at : U64, next : U64, array : U64 }

no_memo : ReaderMemo
no_memo = { skips: [], dicts: [], tuples: [], map_ends: [], outer: [] }

## The lists of `state`.
memo_of : Cbor.Reader -> ReaderMemo
memo_of = |state|
	match state.memo {
		Plain => no_memo
		Memo(b) => Box.unbox(b)
	}

## `state` with the lists `m`.
with_memo : Cbor.Reader, ReaderMemo -> Cbor.Reader
with_memo = |state, m| {
	memo = if (m.skips.is_empty() and m.dicts.is_empty() and m.tuples.is_empty() and m.map_ends.is_empty() and m.outer.is_empty()) Plain else Memo(Box.box(m))
	{ ..state, memo }
}

## `state` in one more uncounted `Dict`.
push_dict : Cbor.Reader, [Left(U64), UntilBreak] -> Cbor.Reader
push_dict = |state, d| {
	m = memo_of(state)
	with_memo(state, { ..m, dicts: m.dicts.append(d) })
}

## The rules of the walk of the root item (from `Cbor.Options`).
## `max_depth`: the most arrays, maps and tags that an item can be in. `max_items`: the most items in the root item.
## `shortest_heads`: a head with more bytes than its argument needs is an error (RFC 8949 4.2.1).
## `indefinite`: arrays, maps, byte strings and text of indefinite length (RFC 8949 3.2) are items.
## `keys`: the rule for a duplicate key in a map. `Any`: no check.
## `order`: `Sorted`: the keys of each map are in the order of RFC 8949 4.2.1 (`key_order`). `Any`: no check.
## `Sorted` needs a key rule (`keys` is not `Any`): the keys of a map are kept only with a key rule.
Rules : { max_depth : U64, max_items : U64, shortest_heads : Bool, indefinite : Bool, keys : [Reject, First, Last, Any], order : [Any, Sorted] }

## Only the checks that no option changes, and definite lengths only: the rules of `read_value`.
loose : Rules
loose = { max_depth: U64.highest, max_items: U64.highest, shortest_heads: Bool.False, indefinite: Bool.False, keys: Any, order: Any }

## The rules of a walk in a typed parse, after the walk of the root item: no limit and no key check, any length.
## The walk of the root item rejected an indefinite length when the parse does not allow it. Also the rules of `path_at`.
any_length : Rules
any_length = { ..loose, indefinite: Bool.True }

## A list, a map or a string has no count in its head: an indefinite length. Its items end at a break (`ff`).
## The head at `p` is `h` (`head_at`). A head of 1 byte has an argument below 24, so `no_pos` there is not a count.
indefinite_at : { major : U8, arg : U64, next : U64 }, U64 -> Bool
indefinite_at = |h, p| h.arg == no_pos and h.next == p + 1

## The items left in an open array or map of indefinite length, at its start. More than any count of a definite
## length in an item that a walk accepts (each item is 1 byte or more), and even, so that a key of a map is at an
## even count, as in a definite map. The walk itself tells the two apart by `OpenItem.kind`.
until_break : U64
until_break = no_pos - 1

## The break (`ff`) at `state`: the end of an array, a map or a string of indefinite length.
at_break : Cbor.Reader -> Bool
at_break = |state| state.raw == 0 and state.bytes.get(state.pos) == Ok(0xff)

## A reader at the start of `bytes`.
reader : List(U8) -> Cbor.Reader
reader = |bytes| Cbor.Reader.{ bytes, pos: 0, raw: 0, array: no_pos, chunks: Bool.False, memo: Plain }

## The head of the item at `state` (`head_at`). In a byte string read as a `List(U8)` there is no head.
## The walk of the root item checked the head width.
head : Cbor.Reader -> Try({ major : U8, arg : U64, next : U64 }, [InvalidCbor(U64)])
head = |state|
	if state.raw > 0 {
		# An item of a byte string is a U8 only (parse_u8), never the head of an item.
		Err(InvalidCbor(error_pos(state)))
	} else {
		head_at(state.bytes, state.pos, any_length)
	}

## The initial byte at `p` and its argument (RFC 8949 3). The reserved values 28 to 30 are errors. With the rule
## `indefinite`, the head of an array, a map or a string of indefinite length has the argument `no_pos` (`indefinite_at`),
## else it is an error. A break (`ff`) is never a head: the walk reads it. With the rule `shortest_heads`, a head
## of major type 0 to 6 with more bytes than its argument needs is an error.
head_at : List(U8), U64, Rules -> Try({ major : U8, arg : U64, next : U64 }, [InvalidCbor(U64)])
head_at = |bytes, p, rules| {
	b = bytes.get(p) ? |_| InvalidCbor(p)
	major = b.shr_zf_wrap(5)
	info = b.bitwise_and(31)
	if info < 24 {
		Ok({ major, arg: info.to_u64(), next: p + 1 })
	} else if info == 31 {
		if (rules.indefinite and major >= 2 and major <= 5) Ok({ major, arg: no_pos, next: p + 1 }) else Err(InvalidCbor(p))
	} else {
		size = match info {
			24 => 1
			25 => 2
			26 => 4
			27 => 8
			_ => 0
		}
		if size == 0 or p + 1 + size > bytes.len() {
			return Err(InvalidCbor(p))
		}
		arg = get_be(bytes, p + 1, size)
		# The smallest argument of each size: 24, 2^8, 2^16, 2^32.
		least = if (size == 1) 24 else (1.U64).shl_wrap((4 * size).to_u8_wrap())
		if rules.shortest_heads and major != 7 and arg < least {
			Err(InvalidCbor(p))
		} else {
			Ok({ major, arg, next: p + 1 + size })
		}
	}
}

## The item at `p` with each check of the reader: the head (`head_at`), the room for the bytes of a string, UTF-8
## in text, a simple value. The count of an array or a map is not checked against the bytes left (`walk_from`).
## `next` is after the head and the bytes of a string. `items` is the count of the items in it: n for an array,
## 2n for a map, 1 for a tag, else 0. Each reader of whole items uses it.
## Indefinite length: a string is one item, `arg` is the length of all its chunks and `next` is after its break.
## An array or a map has `until_break` items, and its break is an item of the walk.
item_at : List(U8), U64, Rules -> Try({ major : U8, arg : U64, next : U64, items : U64 }, [InvalidCbor(U64)])
item_at = |bytes, p, rules| item_with(bytes, p, rules, Bool.True)

## `item_at`, with no UTF-8 check of text of a definite length when `utf8` is false: for a reader that makes a `Str`
## of the text (`Str.from_utf8` checks it, with the error at the same position), or that reads bytes that a walk checked.
item_with : List(U8), U64, Rules, Bool -> Try({ major : U8, arg : U64, next : U64, items : U64 }, [InvalidCbor(U64)])
item_with = |bytes, p, rules, utf8| {
	h = head_at(bytes, p, rules)?
	room = bytes.len() - h.next
	bad = Err(InvalidCbor(p))
	if indefinite_at(h, p) {
		return
			if h.major == 2 or h.major == 3 {
				# Chunks of the same major type, each a definite string, then the break (RFC 8949 3.2.3).
				var $q = h.next
				var $len = 0.U64
				while bytes.get($q) != Ok(0xff) {
					c = head_at(bytes, $q, rules)?
					if c.major != h.major or indefinite_at(c, $q) or c.arg > bytes.len() - c.next {
						return bad
					}
					if h.major == 3 and !valid_utf8(bytes, c.next, c.arg) {
						return bad
					}
					$len = $len + c.arg
					$q = c.next + c.arg
				}
				Ok({ major: h.major, arg: $len, next: $q + 1, items: 0 })
			} else {
				Ok({ major: h.major, arg: no_pos, next: h.next, items: until_break })
			}
	}
	match h.major {
		2 | 3 if h.arg > room => bad
		2 => Ok({ major: 2, arg: h.arg, next: h.next + h.arg, items: 0 })
		3 if !utf8 or valid_utf8(bytes, h.next, h.arg) => Ok({ major: 3, arg: h.arg, next: h.next + h.arg, items: 0 })
		3 => bad
		# A count needs no room in `bytes` (one truncation rule, `cut_pos`). A map of 2^63 entries or more can never be
		# whole: it has `until_break` items (even), so that 2n does not overflow.
		4 => Ok({ major: 4, arg: h.arg, next: h.next, items: h.arg })
		5 => Ok({ major: 5, arg: h.arg, next: h.next, items: if (h.arg > until_break // 2) until_break else h.arg * 2 })
		6 => Ok({ major: 6, arg: h.arg, next: h.next, items: 1 })
		# A simple value of 2 bytes (`f8`) below 32 is not well formed (RFC 8949 3.3).
		7 if bytes.get(p) == Ok(0xf8) and h.arg < 32 => bad
		_ => Ok({ major: h.major, arg: h.arg, next: h.next, items: 0 })
	}
}

## The `len` bytes at `start` are valid UTF-8 (RFC 3629): one pass, with the width of each code point from its first
## byte and the range of its second byte (no overlong form, no surrogate, nothing above U+10FFFF), as `Str.from_utf8`.
## TODO(roc#13025): `Str.from_utf8` out of line decodes each code point and checks the last bytes again (4.6x Rust on
## short text). When the issue is fixed, go back to `Str.from_utf8(bytes.sublist({ start, len })).is_ok()`, and
## remove `utf8_tail`. The test "valid_utf8 agrees with Str.from_utf8" stays.
valid_utf8 : List(U8), U64, U64 -> Bool
valid_utf8 = |bytes, start, len| {
	end = start + len
	var $i = start
	while $i < end {
		b = bytes.get($i) ?? 0xff
		if b < 0x80 {
			$i = $i + 1
		} else {
			width =
				if b >= 0xc2 and b <= 0xdf {
					2
				} else if b >= 0xe0 and b <= 0xef {
					3
				} else if b >= 0xf0 and b <= 0xf4 {
					4
				} else {
					return Bool.False
				}
			if width > end - $i or !utf8_tail(bytes, $i, b, width) {
				return Bool.False
			}
			$i = $i + width
		}
	}
	Bool.True
}

## The bytes after the first byte `b` of a code point of `width` bytes at `i`: the second byte in the range that `b`
## allows, each other byte a continuation byte (`80` to `bf`).
utf8_tail : List(U8), U64, U8, U64 -> Bool
utf8_tail = |bytes, i, b, width| {
	second = bytes.get(i + 1) ?? 0
	(lo, hi) =
		match b {
			0xe0 => (0xa0, 0xbf)
			0xed => (0x80, 0x9f)
			0xf0 => (0x90, 0xbf)
			0xf4 => (0x80, 0x8f)
			_ => (0x80, 0xbf)
		}
	cont = |k| {
		c = bytes.get(i + k) ?? 0
		c >= 0x80 and c <= 0xbf
	}
	second >= lo and second <= hi and (width < 3 or cont(2)) and (width < 4 or cont(3))
}

get_be : List(U8), U64, U64 -> U64
get_be = |bytes, start, size| {
	# A while loop: a `for` on a range costs an iterator step for each byte.
	var $n = 0.U64
	var $i = start
	while $i < start + size {
		$n = $n.shl_wrap(8).bitwise_or((bytes.get($i) ?? 0).to_u64())
		$i = $i + 1
	}
	$n
}

text : Cbor.Reader -> Try({ value : Str, rest : Cbor.Reader }, [InvalidCbor(U64)])
text = |state| {
	match short_text_at(state) {
		Ok(short) => return Ok(short)
		Err(NotShort) => {}
	}
	t = text_head(state)?
	value = Str.from_utf8(t.name) ? |_| InvalidCbor(state.pos)
	Ok({ value, rest: t.rest })
}

## The bytes of the string of major type `major` at `state`: a part of the input, or the chunks joined (indefinite length).
string_at : Cbor.Reader, U8 -> Try({ bytes : List(U8), rest : Cbor.Reader }, [InvalidCbor(U64)])
string_at = |state, major| {
	h = head(state)?
	if h.major != major {
		Err(InvalidCbor(state.pos))
	} else if indefinite_at(h, state.pos) {
		it = item_at(state.bytes, state.pos, any_length)?
		Ok({ bytes: joined(state.bytes, state.pos), rest: at(state, it.next) })
	} else if h.arg > state.bytes.len() - h.next {
		Err(InvalidCbor(state.pos))
	} else {
		Ok({ bytes: state.bytes.sublist({ start: h.next, len: h.arg }), rest: at(state, h.next + h.arg) })
	}
}

## The I128 of `int` as an I64, before the conversion to a type of 32 bits or less. The wasm32 dev backend of the
## Roc compiler (`roc build --target=wasm32 --opt=dev`, nightlies 2026-10-31 and 2026-11-01) gives `Err(OutOfRange)`
## for `I128.to_u8_try`, `to_u16_try`, `to_i8_try` and `to_i16_try` of a value in range, so a `List(U8)` (an array)
## did not read back there. `I64` to a small type is correct on each backend.
narrow : I128, U64 -> Try(I64, [InvalidCbor(U64)])
narrow = |v, pos| v.to_i64_try().map_err(|_| InvalidCbor(pos))

## An integer of major type 0 or 1, as I128 so that both u64 and -2^64 fit.
## With `FloatToInt`, a float with no fraction is also read when its size is 2^53 - 1 or less (a JS Number).
## A larger float can be the rounded value of many integers, so it is an error.
## With `IntFromText`, text that is a canonical decimal integer is also read.
int : Cbor, Cbor.Reader -> Try({ value : I128, rest : Cbor.Reader }, [InvalidCbor(U64)])
int = |cbor, tagged| {
	state = untag(cbor, tagged)?
	h = head(state)?
	match h.major {
		0 => Ok({ value: h.arg.to_i128(), rest: at(state, h.next) })
		1 => Ok({ value: -1 - h.arg.to_i128(), rest: at(state, h.next) })
		3 if cbor.read.int_from_text => {
			t = text_head(state)?
			d = decimal(t.name) ? |_| InvalidCbor(state.pos)
			# A size above I128.highest is outside the range of each type that reads through `int`.
			i = d.size.to_i128_try() ? |_| InvalidCbor(state.pos)
			Ok({ value: if (d.negative) -i else i, rest: t.rest })
		}
		7 if cbor.read.float_to_int => {
			f = float(state)?
			i = f.value.to_i128_try() ? |_| InvalidCbor(state.pos)
			safe = 9_007_199_254_740_991
			if i.to_f64() == f.value and i <= safe and i >= -safe {
				Ok({ value: i, rest: f.rest })
			} else {
				Err(InvalidCbor(state.pos))
			}
		}
		_ => Err(InvalidCbor(state.pos))
	}
}

## A canonical decimal integer: `0`, or an optional `-`, a digit 1 to 9, then digits. `size` is the value with no sign.
## At most 39 digits. Each step checks for overflow, so a size above U128.highest is an error. The caller checks the range of its type.
decimal : List(U8) -> Try({ negative : Bool, size : U128 }, [NotDecimal])
decimal = |bytes| {
	(negative, digits) =
		match bytes {
			['-', .. as rest] => (Bool.True, rest)
			_ => (Bool.False, bytes)
		}
	ok =
		match digits {
			['0'] => !negative
			[first, ..] => first >= '1' and first <= '9' and digits.len() <= 39 and digits.all(|d| d >= '0' and d <= '9')
			[] => Bool.False
		}
	if !ok {
		return Err(NotDecimal)
	}
	var $size = 0.U128
	for d in digits {
		$size = $size.times_try(10) ? |_| NotDecimal
		$size = $size.plus_try((d - '0').to_u128()) ? |_| NotDecimal
	}
	Ok({ negative, size: $size })
}

## A float, or an integer (major type 0 or 1) that is exact as an F64: then `integer` is true.
## An integer that the F64 rounds (above 2^53) is an error.
float : Cbor.Reader -> Try({ value : F64, integer : Bool, rest : Cbor.Reader }, [InvalidCbor(U64)])
float = |state| {
	h = head(state)?
	match (h.major, state.bytes.get(state.pos) ?? 0) {
		(0, _) | (1, _) => {
			i = if (h.major == 0) h.arg.to_i128() else -1 - h.arg.to_i128()
			f = i.to_f64()
			if (f.to_i128_try() == Ok(i)) Ok({ value: f, integer: Bool.True, rest: at(state, h.next) }) else Err(InvalidCbor(state.pos))
		}
		(7, 0xfb) => Ok({ value: F64.from_bits(h.arg), integer: Bool.False, rest: at(state, h.next) })
		(7, 0xfa) => Ok({ value: F32.from_bits(h.arg.to_u32_wrap()).to_f64(), integer: Bool.False, rest: at(state, h.next) })
		(7, 0xf9) => Ok({ value: half(h.arg), integer: Bool.False, rest: at(state, h.next) })
		_ => Err(InvalidCbor(state.pos))
	}
}

## IEEE 754 binary16 (RFC 8949 Appendix D).
half : U64 -> F64
half = |h| {
	exp = h.shr_zf_wrap(10).bitwise_and(0x1f)
	mant = h.bitwise_and(0x3ff).to_f64()
	value =
		if exp == 0 {
			mant * 0.000000059604644775390625 # 2^-24
		} else if exp != 31 {
			(mant + 1024.0) * pow2(exp.to_i64_wrap() - 25)
		} else if mant == 0.0 {
			F64.infinity
		} else {
			F64.nan
		}
	if (h.bitwise_and(0x8000) != 0) -value else value
}

pow2 : I64 -> F64
pow2 = |e| {
	var $v = 1.0.F64
	if e >= 0 {
		for _ in (0.I64).until(e) {
			$v = $v * 2.0
		}
	} else {
		for _ in (0.I64).until(-e) {
			$v = $v / 2.0
		}
	}
	$v
}

## Skips one whole item, with the checks of `item_at`: an unknown record field, a map entry. In a parse, after the walk of the root item.
skip : Cbor.Reader -> Try(Cbor.Reader, [InvalidCbor(U64)])
skip = |state| {
	# An item with no items in it (most unknown fields) needs no walk state. On an error, the walk gives the position.
	# A flat array or map of definite length (each item with no items in it): a count, no walk state.
	# TODO(roc#13035): one expression with no early return (see `nest`).
	end =
		if state.raw > 0 {
			Err(Nested)
		} else {
			match item_at(state.bytes, state.pos, any_length) {
				Ok(it) if it.items == 0 => Ok(it.next)
				Ok(it) if it.major == 4 or it.major == 5 => skip_flat(state.bytes, it.next, it.items)
				_ => Err(Nested)
			}
		}
	match end {
		Ok(e) => Ok(at(state, e))
		Err(Nested) => walk(state, any_length, Bool.False)
	}
}

## The end of `items` whole items from `p`, each with no items in it (`item_at`). `Nested` at an item with items in it,
## at an error, and for a count larger than the bytes (an indefinite length has `until_break` items): `walk` reads
## those, with the same end or the same error position.
skip_flat : List(U8), U64, U64 -> Try(U64, [Nested])
skip_flat = |bytes, p, items| {
	if items > bytes.len() - p {
		return Err(Nested)
	}
	var $q = p
	var $k = 0.U64
	while $k < items {
		it = item_at(bytes, $q, any_length) ? |_| Nested
		if it.items != 0 {
			return Err(Nested)
		}
		$q = it.next
		$k = $k + 1
	}
	Ok($q)
}

## Walks one whole item with the checks of `item_at` and `rules`, and gives the reader after it (`walk_from` on all
## the bytes). With `keep`, the start and end of each map go in `map_ends` (`scan_union`). With a key rule, the reader
## gets the positions of the keys to skip. When the bytes end in the item, the error is at `cut_pos`.
walk : Cbor.Reader, Rules, Bool -> Try(Cbor.Reader, [InvalidCbor(U64)])
walk = |state, rules, keep| {
	if state.raw > 0 {
		return Err(InvalidCbor(error_pos(state)))
	}
	m = memo_of(state)
	# The common case first: no map ends to keep or to use, no key order. `fast_walk` gives the same end, or `Slow`.
	if !keep and m.map_ends.is_empty() and rules.order == Any {
		match fast_walk(state.bytes, state.pos, rules) {
			Ok(pos) => {
				end = moved(state, pos, 0)
				return if (rules.keys != Any) Ok(with_memo(end, { ..m, skips: [] })) else Ok(end)
			}
			Err(Slow) => {}
		}
	}
	w =
		match walk_from(state.bytes, walk_start(state.pos, m.map_ends, keep), rules)? {
			Whole(ws) => ws
			Cut(ws) => return Err(InvalidCbor(cut_pos(state.bytes, ws)))
		}
	end = moved(state, w.pos, 0)
	if rules.keys != Any {
		Ok(with_memo(end, { ..m, map_ends: w.ends, skips: w.skips.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same) }))
	} else if keep {
		Ok(with_memo(end, { ..m, map_ends: w.ends }))
	} else {
		# With no `keep`, `w.ends` is the list of `state`.
		Ok(end)
	}
}

## The walk of one whole item of definite length with the checks of `item_at` and `rules`, in one loop with no
## walk state: the position after the item. `Slow` for each case that it does not take, and for each error, so that
## `walk_from` gives the result and the error position: an indefinite length or a break, a reserved head, a cut item,
## more items than `max_items` or than the bytes left, more open items than `max_depth`, a key that is an array, a
## map or a tag, and a duplicate key (`Reject` is an error; `First` and `Last` need the keys to skip).
## `open` holds two numbers for each open item, the innermost last: the items left in it, and the index of its first
## key in `keys` (for a map with a key rule, else `no_pos`). `keys` has the start and end of each key of the open maps.
fast_walk : List(U8), U64, Rules -> Try(U64, [Slow])
fast_walk = |bytes, start, rules| {
	n = bytes.len()
	check = rules.keys != Any
	var $open = List.with_capacity(32)
	var $keys = []
	var $left = 1.U64
	var $first = no_pos
	var $count = 0.U64
	var $p = start
	var $more = Bool.True
	while $more {
		if $left == 0 {
			# The innermost open item is whole: compare the keys of a map, and go back to the item it is in.
			if $first != no_pos {
				found = dup_keys(bytes, $keys.drop_first($first), rules) ? |_| Slow
				if !found.is_empty() {
					return Err(Slow)
				}
				$keys = $keys.take_first($first)
			}
			k = $open.len()
			if k == 0 {
				$more = Bool.False
			} else {
				$left = $open.get(k - 2) ?? 0
				$first = $open.get(k - 1) ?? no_pos
				$open = $open.drop_last(2)
			}
		} else {
			b = bytes.get($p) ? |_| Slow
			major = b.shr_zf_wrap(5)
			info = b.bitwise_and(31)
			var $arg = info.to_u64()
			var $q = $p + 1
			if info >= 24 {
				size =
					match info {
						24 => 1
						25 => 2
						26 => 4
						27 => 8
						_ => return Err(Slow)
					}
				if $q + size > n {
					return Err(Slow)
				}
				$arg = get_be(bytes, $q, size)
				least = if (size == 1) 24 else (1.U64).shl_wrap((4 * size).to_u8_wrap())
				if rules.shortest_heads and major != 7 and $arg < least {
					return Err(Slow)
				}
				$q = $q + size
			}
			if $count >= rules.max_items {
				return Err(Slow)
			}
			$count = $count + 1
			is_key = $first != no_pos and $left % 2 == 0
			$left = $left - 1
			if major == 2 or major == 3 {
				if $arg > n - $q or (major == 3 and !valid_utf8(bytes, $q, $arg)) {
					return Err(Slow)
				}
				$q = $q + $arg
			} else if major >= 4 and major <= 6 {
				if is_key or $open.len() // 2 >= rules.max_depth or (major != 6 and $arg > n - $q) {
					return Err(Slow)
				}
				$open = $open.append($left).append($first)
				$left = if (major == 4) $arg else if (major == 5) 2 * $arg else 1
				$first = if (check and major == 5) $keys.len() else no_pos
			} else if b == 0xf8 and $arg < 32 {
				# A simple value of 2 bytes below 32 is not well formed (RFC 8949 3.3).
				return Err(Slow)
			}
			if is_key {
				$keys = $keys.append($p).append($q)
			}
			$p = $q
		}
	}
	Ok($p)
}

## The state of a walk of one item, kept between two calls of `walk_from`. Each position is in the bytes of the walk.
## `pos`: the next head. `count`: the items so far (`max_items`). `open`: each open item, the innermost last.
## `keys`: the start and end of each key of the open maps with a key rule. `skips`: the keys that `duplicate_keys` skips.
## `ends`: `map_ends` of the reader. `keep`: put the start and end of each map in `ends`.
WalkState : { pos : U64, count : U64, open : List(OpenItem), keys : List(U64), skips : List(U64), ends : List(U64), keep : Bool }

## One open item of a walk. `left`: the items left in it. `slot`: the index of its end in `ends` (or `no_pos`).
## `first`: for a map with a key rule, the index of its first key in `keys` (else `no_pos`). `start`: its head.
## `kind`: 0 for a definite length or a tag, else the major type of an indefinite length (2 to 5). A string of
## indefinite length is open until its break: its items are its chunks, and they do not count.
OpenItem : { left : U64, slot : U64, first : U64, start : U64, kind : U8 }

## The state at the start of a walk of the item at `pos`.
walk_start : U64, List(U64), Bool -> WalkState
walk_start = |pos, ends, keep| { pos, count: 0, open: [], keys: [], skips: [], ends, keep }

## Walks the item of `ws` in `bytes`, from `ws.pos`, with the checks of `item_at` and `rules`. A loop with a list of
## the open items, not a recursion. More open items than `max_depth`, or more items than `max_items`, is an error at
## the item that goes over. A map in `ends` is not walked again. With a key rule, the keys of each map are compared
## when the map ends (`dup_keys`).
## `Whole`: the item ends at `pos`. `Cut`: the bytes end in the item. The state changes only after a whole head (and
## a whole string of definite length), so a walk from the `Cut` state with more bytes gives the same result as
## one walk of all the bytes. A count of an array or a map needs no room in `bytes`: each step reads 1 byte or more.
walk_from : List(U8), WalkState, Rules -> Try([Whole(WalkState), Cut(WalkState)], [InvalidCbor(U64)])
walk_from = |bytes, ws, rules| {
	sorted = rules.order == Sorted
	check = rules.keys != Any
	keep = ws.keep
	var $ends = ws.ends
	var $pos = ws.pos
	var $count = ws.count
	var $open = ws.open
	var $keys = ws.keys
	var $skips = ws.skips
	var $more = Bool.True
	while $more {
		start = $pos
		inner = $open.last() ?? { left: 0, slot: no_pos, first: no_pos, start: no_pos, kind: 0 }
		top = inner.left
		# Only with `indefinite`: a break, a chunk of an open string, or the head of a string of indefinite length.
		# At the end of the bytes `b` is 0, and `cut_at` sees the end.
		b = if (rules.indefinite) bytes.get($pos) ?? 0 else 0
		var $whole = Bool.False
		if rules.indefinite and (b == 0xff or inner.kind == 2 or inner.kind == 3 or b.bitwise_and(0xdf) == 0x5f) {
			if b == 0xff {
				# A break: the end of the open item of indefinite length. Not an item. A map needs a value for each key.
				if inner.kind == 0 or (inner.kind == 5 and top % 2 != 0) {
					return Err(InvalidCbor(start))
				}
				$pos = $pos + 1
				# The open item is whole now, as after its last item.
				$open = $open.set($open.len() - 1, { ..inner, left: 1 }) ?? $open
				$whole = Bool.True
			} else if inner.kind == 2 or inner.kind == 3 {
				# A chunk of the open string: a string of definite length of the same major type (RFC 8949 3.2.3).
				c =
					match head_at(bytes, $pos, rules) {
						Ok(h) => h
						Err(e) => {
							if !cut_at(bytes, $pos, rules) {
								return Err(e)
							}
							return Ok(Cut({ pos: $pos, count: $count, open: $open, keys: $keys, skips: $skips, ends: $ends, keep }))
						}
					}
				if c.major != inner.kind or indefinite_at(c, $pos) {
					return Err(InvalidCbor(inner.start))
				}
				if c.arg > bytes.len() - c.next {
					return Ok(Cut({ pos: $pos, count: $count, open: $open, keys: $keys, skips: $skips, ends: $ends, keep }))
				}
				if inner.kind == 3 and !valid_utf8(bytes, c.next, c.arg) {
					return Err(InvalidCbor(inner.start))
				}
				$pos = c.next + c.arg
			} else {
				# The head of a string of indefinite length: one item, open until its break.
				if $count >= rules.max_items {
					return Err(InvalidCbor(start))
				}
				$count = $count + 1
				$pos = $pos + 1
				if check and inner.first != no_pos and top % 2 == 0 {
					$keys = $keys.append(start).append(no_pos)
				}
				$open = $open.append({ left: until_break, slot: no_pos, first: no_pos, start, kind: b.shr_zf_wrap(5) })
			}
		} else {
			it =
				match item_at(bytes, $pos, rules) {
					Ok(i) => i
					Err(e) => {
						if !cut_at(bytes, $pos, rules) {
							return Err(e)
						}
						return Ok(Cut({ pos: $pos, count: $count, open: $open, keys: $keys, skips: $skips, ends: $ends, keep }))
					}
				}
			# After `item_at`: each error of `item_at` here is at `start` too.
			if $count >= rules.max_items {
				return Err(InvalidCbor(start))
			}
			$count = $count + 1
			$pos = it.next
			if it.major >= 4 and it.major <= 6 and $open.len() >= rules.max_depth {
				return Err(InvalidCbor(start))
			}
			in_map = check and inner.first != no_pos
			if in_map and top % 2 == 0 {
				# A key: its end comes when it is whole.
				$keys = $keys.append(start).append(no_pos)
			}
			known = if (it.major == 5 and !$ends.is_empty()) map_end($ends, start) else Err(NotFound)
			match known {
				Ok(end) => {
					$pos = end
					$whole = Bool.True
				}
				Err(_) if it.items == 0 => {
					$whole = Bool.True
				}
				Err(_) => {
					end_slot =
						if keep and it.major == 5 {
							$ends = $ends.append(start).append(0)
							$ends.len() - 1
						} else {
							no_pos
						}
					kind = if (it.next == start + 1 and it.arg == no_pos) it.major else 0
					$open = $open.append({ left: it.items, slot: end_slot, first: if (check and it.major == 5) $keys.len() else no_pos, start, kind })
				}
			}
		}
		# Count the whole item in each open item that it completes.
		var $closing = $whole
		while $closing {
			match $open.last() {
				Err(_) => {
					$more = Bool.False
					$closing = Bool.False
				}
				Ok(o) if o.left > 1 => {
					if o.left % 2 == 0 and o.first != no_pos {
						# The whole item is a key of the map.
						$keys = $keys.set($keys.len() - 1, $pos) ?? $keys
						if sorted and $keys.len() >= o.first + 4 {
							# `key_order: Sorted`: compare the key with the key before it. Keep only this key.
							step = sorted_key(bytes, $keys, $skips, $pos, rules)?
							$keys = step.keys
							$skips = step.skips
						}
					}
					$open = $open.set($open.len() - 1, { ..o, left: o.left - 1 }) ?? $open
					$closing = Bool.False
				}
				Ok(o) => {
					if o.first != no_pos {
						if !sorted {
							found = dup_keys(bytes, $keys.drop_first(o.first), rules)?
							if !found.is_empty() {
								$skips = $skips.concat(found)
							}
						}
						$keys = $keys.take_first(o.first)
					}
					$ends = $ends.set(o.slot, $pos) ?? $ends
					$open = $open.drop_last(1)
				}
			}
		}
	}
	Ok(Whole({ pos: $pos, count: $count, open: $open, keys: $keys, skips: $skips, ends: $ends, keep }))
}

## The item at `p` is cut by the end of `bytes`: its head is not whole, or it is a string of definite length with a
## valid head and its data is not whole. For an error of `item_at` or `head_at` at `p`.
cut_at : List(U8), U64, Rules -> Bool
cut_at = |bytes, p, rules|
	match bytes.get(p) {
		Err(_) => Bool.True
		Ok(b) => {
			size =
				match b.bitwise_and(31) {
					24 => 1
					25 => 2
					26 => 4
					27 => 8
					_ => 0
				}
			if p + 1 + size > bytes.len() {
				Bool.True
			} else {
				match head_at(bytes, p, rules) {
					Ok(h) => (h.major == 2 or h.major == 3) and !indefinite_at(h, p) and h.arg > bytes.len() - h.next
					Err(_) => Bool.False
				}
			}
		}
	}

## The position of the error when the bytes end in the item of a `Cut` walk (one rule for each reader): the head of
## the innermost item that is not whole. That is a cut head or a cut string at `pos`, an open string of indefinite
## length (its chunks are not items), or else the innermost open array, map or tag. With no open item, `pos`.
cut_pos : List(U8), WalkState -> U64
cut_pos = |bytes, ws|
	match ws.open.last() {
		Ok(o) if o.kind == 2 or o.kind == 3 or ws.pos >= bytes.len() => o.start
		_ => ws.pos
	}

## `key_order: Sorted`: the last key of `keys` (start and end, in pairs; it ends at `end`) against the key before it.
## Less is an error at the key. Equal is a duplicate: `Reject` is an error at the key, `First` skips the key, `Last`
## skips the key before. Gives `keys` with only the last key of the two, and `skips`.
sorted_key : List(U8), List(U64), List(U64), U64, Rules -> Try({ keys : List(U64), skips : List(U64) }, [InvalidCbor(U64)])
sorted_key = |bytes, keys, skips, end, rules| {
	n = keys.len()
	key = keys.get(n - 2) ?? 0
	before = keys.get(n - 4) ?? 0
	dropped =
		match order_keys(bytes, before, keys.get(n - 3) ?? 0, key, end, rules) {
			Before => no_pos
			After => return Err(InvalidCbor(key))
			Same =>
				match rules.keys {
					First => key
					Last => before
					_ => return Err(InvalidCbor(key))
				}
		}
	kept = keys.drop_last(4).append(key).append(end)
	Ok({ keys: kept, skips: if (dropped == no_pos) skips else skips.append(dropped) })
}

## The order of RFC 8949 4.2.1 of the key from `a` to `a_end` and the key from `b` to `b_end`: the bytewise order of
## their deterministic encoding (`deterministic`), and a prefix comes first. `Same`: the keys are the same `Cbor.Value`
## in that encoding. An integer, or bytes or text of a definite length, with the shortest head is deterministic as it
## is: it is compared in place, with no copy.
order_keys : List(U8), U64, U64, U64, U64, Rules -> [Before, Same, After]
order_keys = |bytes, a, a_end, b, b_end, rules|
	if plain_key(bytes, a, rules) and plain_key(bytes, b, rules) {
		la = a_end - a
		lb = b_end - b
		n = if (la < lb) la else lb
		var $k = 0.U64
		while $k < n {
			x = bytes.get(a + $k) ?? 0
			y = bytes.get(b + $k) ?? 0
			if x != y {
				return if (x < y) Before else After
			}
			$k = $k + 1
		}
		ordered(la, lb)
	} else {
		order_bytes(deterministic(bytes, a, a_end, key_dups(rules)), deterministic(bytes, b, b_end, key_dups(rules)))
	}

## The key at `p` is an integer, or bytes or text of a definite length, with the shortest head: its bytes are its
## deterministic encoding. With the rule `shortest_heads` the walk checked the head. Else only a 1-byte head is sure.
plain_key : List(U8), U64, Rules -> Bool
plain_key = |bytes, p, rules| {
	first = bytes.get(p) ?? 0xff
	info = first.bitwise_and(31)
	first < 0x80 and info != 31 and (rules.shortest_heads or info < 24)
}

## The duplicate keys of one map: `keys` has the start and end of each key, in order. Two keys are the same when they
## are the same `Cbor.Value`: the same bytes with shortest heads and each float as an f64 (`canonical`). Text with shortest
## heads is canonical as it is. `Reject`: an error at the first key that is the same as a key before it. `First` and
## `Last`: the positions of the keys to skip. Sorted, so O(n log n) for n keys: no hash of an attacker key.
dup_keys : List(U8), List(U64), Rules -> Try(List(U64), [InvalidCbor(U64)])
dup_keys = |bytes, keys, rules| {
	n = keys.len() // 2
	# With `PaddedNumbers`, each key head is checked: a map with only shortest text keys keeps the fast paths.
	heads = !rules.shortest_heads
	if n < 2 or (n <= 32 and no_same_text(bytes, keys, heads)) {
		# A small map of text keys with no duplicate (a record): no list and no sort.
		return Ok([])
	}
	# Text keys of a definite length with shortest heads are canonical as they are: they are compared in place
	# (no list for each key). Else each key is compared in its canonical form.
	in_place = all_text(bytes, keys, heads)
	key_bytes : List(List(U8))
	key_bytes =
		if in_place {
			[]
		} else {
			var $kb = List.with_capacity(n)
			var $k = 0.U64
			while $k < n {
				start = keys.get(2 * $k) ?? 0
				end = keys.get(2 * $k + 1) ?? 0
				$kb = $kb.append(canonical(bytes, start, end, key_dups(rules)))
				$k = $k + 1
			}
			$kb
		}
	# The indexes of the keys, in order of their bytes, then of their position.
	var $indexes = List.with_capacity(n)
	var $j = 0.U64
	while $j < n {
		$indexes = $indexes.append($j)
		$j = $j + 1
	}
	order =
		if in_place {
			$indexes.sort_with(|a, b| span_order(bytes, keys, a, b))
		} else {
			$indexes.sort_with(
				|a, b| {
					x = key_bytes.get(a) ?? []
					y = key_bytes.get(b) ?? []
					if x.len() != y.len() {
						if (x.len() < y.len()) Before else After
					} else {
						match compare_bytes(x, y) {
							Same => if (a < b) Before else After
							other => other
						}
					}
				},
			)
		}
	# Each run of the same key: the indexes of its instances, in order.
	var $skips = []
	var $error = no_pos
	var $run_start = 0.U64
	var $i = 1.U64
	while $i <= n {
		same =
			if $i == n {
				Bool.False
			} else {
				a = order.get($i) ?? 0
				b = order.get($i - 1) ?? 0
				if (in_place) span_same(bytes, keys, a, b) else key_bytes.get(a) == key_bytes.get(b)
			}
		if !same {
			if $i - $run_start > 1 {
				run = order.sublist({ start: $run_start, len: $i - $run_start })
				second = run.get(1) ?? 0
				if second < $error {
					$error = second
				}
				$skips = $skips.concat(
					match rules.keys {
						First => run.drop_first(1)
						Last => run.drop_last(1)
						_ => []
					},
				)
			}
			$run_start = $i
		}
		$i = $i + 1
	}
	if $error == no_pos {
		Ok([])
	} else if rules.keys == Reject {
		Err(InvalidCbor(keys.get(2 * $error) ?? 0))
	} else {
		Ok($skips.map(|i| keys.get(2 * i) ?? 0))
	}
}

## Each key of `keys` (start and end, in pairs) is text of a definite length (not `7f`). With `heads`, each key head is also the shortest.
all_text : List(U8), List(U64), Bool -> Bool
all_text = |bytes, keys, heads| {
	var $i = 0.U64
	while $i < keys.len() {
		if !text_key(bytes, keys.get($i) ?? 0, keys.get($i + 1) ?? 0, heads) {
			return Bool.False
		}
		$i = $i + 2
	}
	Bool.True
}

## The key from `start` to `end` is text of a definite length. With `heads`, its head is also the shortest for its length.
text_key : List(U8), U64, U64, Bool -> Bool
text_key = |bytes, start, end, heads| {
	first = bytes.get(start) ?? 0
	if first.shr_zf_wrap(5) != 3 or first == 0x7f {
		Bool.False
	} else if !heads or first < 0x78 {
		Bool.True
	} else {
		# The head size from the initial byte: 2, 3, 5 or 9 bytes.
		size = (1.U64).shl_wrap((first - 0x78).to_u8_wrap()) + 1
		end - start >= size and head_size(end - start - size) == size
	}
}

## The keys `a` and `b` (indexes in `keys`) have the same bytes.
span_same : List(U8), List(U64), U64, U64 -> Bool
span_same = |bytes, keys, a, b| {
	sa = keys.get(2 * a) ?? 0
	la = (keys.get(2 * a + 1) ?? 0) - sa
	sb = keys.get(2 * b) ?? 0
	la == (keys.get(2 * b + 1) ?? 0) - sb and same_bytes(bytes, sa, sb, la)
}

## The order of the keys `a` and `b` (indexes in `keys`, start and end in pairs) by their bytes in `bytes`: the shorter
## first, then the bytes, then the position. Two different indexes are never `Same`.
span_order : List(U8), List(U64), U64, U64 -> [Before, Same, After]
span_order = |bytes, keys, a, b| {
	sa = keys.get(2 * a) ?? 0
	la = (keys.get(2 * a + 1) ?? 0) - sa
	sb = keys.get(2 * b) ?? 0
	lb = (keys.get(2 * b + 1) ?? 0) - sb
	if la != lb {
		if (la < lb) Before else After
	} else {
		var $k = 0.U64
		while $k < la {
			x = bytes.get(sa + $k) ?? 0
			y = bytes.get(sb + $k) ?? 0
			if x != y {
				return if (x < y) Before else After
			}
			$k = $k + 1
		}
		if (a < b) Before else if (a > b) After else Same
	}
}

## Each key of `keys` (start and end, in pairs) is text of a definite length (with `heads`, also with the shortest head),
## and no two keys have the same bytes: a compare of each pair in place.
no_same_text : List(U8), List(U64), Bool -> Bool
no_same_text = |bytes, keys, heads| {
	n = keys.len() // 2
	var $i = 0.U64
	while $i < n {
		a = keys.get(2 * $i) ?? 0
		a_end = keys.get(2 * $i + 1) ?? 0
		a_len = a_end - a
		if !text_key(bytes, a, a_end, heads) {
			return Bool.False
		}
		var $j = 0.U64
		while $j < $i {
			b = keys.get(2 * $j) ?? 0
			if (keys.get(2 * $j + 1) ?? 0) - b == a_len and same_bytes(bytes, a, b, a_len) {
				return Bool.False
			}
			$j = $j + 1
		}
		$i = $i + 1
	}
	Bool.True
}

## The `len` bytes at `a` and at `b` are the same.
same_bytes : List(U8), U64, U64, U64 -> Bool
same_bytes = |bytes, a, b, len| {
	var $i = 0.U64
	while $i < len {
		if bytes.get(a + $i) != bytes.get(b + $i) {
			return Bool.False
		}
		$i = $i + 1
	}
	Bool.True
}

## The order of two byte lists of the same length.
compare_bytes : List(U8), List(U8) -> [Before, Same, After]
compare_bytes = |x, y| {
	var $i = 0.U64
	while $i < x.len() {
		a = x.get($i) ?? 0
		b = y.get($i) ?? 0
		if a != b {
			return if (a < b) Before else After
		}
		$i = $i + 1
	}
	Same
}

## The bytes of the items from `start` to `end` as `Cbor.encode` of their `Cbor.Value` writes them: the shortest
## heads, definite lengths, and each float as an f64. A simple value stays as it is. A loop with a list of the open
## arrays, maps and tags, not a recursion. An array or a map of indefinite length gets its head when its break comes:
## its items go to a new output, which then goes after the head. `dups`: `Keep` gives each entry of each map, as the
## bytes have it (the exact form of a key). `First` and `Last` give one entry of each key of a map, as the `Cbor.Value`
## reader reads it with `duplicate_keys` (`key_dups`): so two keys are the same here when they are the same `Cbor.Value`.
canonical : List(U8), U64, U64, [Keep, First, Last] -> List(U8)
canonical = |bytes, start, end, dups| canonical_with(bytes, start, end, Bool.False, dups)

## The deterministic encoding of RFC 8949 4.2.1 of the items from `start` to `end`: `canonical` with the shortest float
## (`put_float`) in place of the f64. It is what `Cbor.encode` writes for the items as a `Cbor.Value`, so the order of
## `key_order: Sorted` on read is the order of `sort_maps` on write.
deterministic : List(U8), U64, U64, [Keep, First, Last] -> List(U8)
deterministic = |bytes, start, end, dups| canonical_with(bytes, start, end, Bool.True, dups)

## The rule for the duplicate keys in a key (`canonical`): the rule of the walk, so a key is compared as its
## `Cbor.Value`. With `Reject` the walk has no duplicate key, so `Keep` gives the same bytes.
key_dups : Rules -> [Keep, First, Last]
key_dups = |rules|
	match rules.keys {
		First => First
		Last => Last
		_ => Keep
	}

## `canonical` (`short` false) or `deterministic` (`short` true).
canonical_with : List(U8), U64, U64, Bool, [Keep, First, Last] -> List(U8)
canonical_with = |bytes, start, end, short, dups| {
	collapse = dups != Keep
	var $out = []
	# Each open item: the items left (definite), or the count of its items so far and the output before it (an
	# indefinite length, or a map with `collapse`: `buffered`). With `collapse`, `marks` has the start of each item of
	# a map in `$out`.
	var $open = []
	var $p = start
	while $p < end {
		top = $open.last()
		whole =
			match top {
				Ok(f) if f.indefinite and bytes.get($p) == Ok(0xff) => {
					$out = close_buffered(f, $out, dups)
					$open = $open.drop_last(1)
					$p = $p + 1
					Bool.True
				}
				_ => {
					# An item of the open item: count it.
					$open =
						match top {
							Ok(f) => $open.set($open.len() - 1, { ..f, left: if (f.indefinite) f.left else f.left - 1, count: f.count + 1, marks: if (collapse and f.major == 5) f.marks.append($out.len()) else f.marks }) ?? $open
							Err(_) => $open
						}
					match item_at(bytes, $p, any_length) {
						Ok(it) if it.major == 7 => {
							$out =
								match float(at(reader(bytes), $p)) {
									Ok(f) if short => put_float($out, f.value.to_bits())
									Ok(f) => put_be($out.append(0xfb), f.value.to_bits(), 8)
									Err(_) => $out.concat(bytes.sublist({ start: $p, len: it.next - $p }))
								}
							$p = it.next
							Bool.True
						}
						Ok(it) if (it.major == 2 or it.major == 3) and bytes.get($p) == Ok(it.major.shl_wrap(5).bitwise_or(31)) => {
							$out = put_head($out, it.major, it.arg).concat(joined(bytes, $p))
							$p = it.next
							Bool.True
						}
						Ok(it) if it.major == 2 or it.major == 3 => {
							$out = put_head($out, it.major, it.arg).concat(bytes.sublist({ start: it.next - it.arg, len: it.arg }))
							$p = it.next
							Bool.True
						}
						Ok(it) if it.items == until_break => {
							$open = $open.append({ indefinite: Bool.True, buffered: Bool.True, major: it.major, left: 0, count: 0, before: $out, marks: [] })
							$out = []
							$p = it.next
							Bool.False
						}
						Ok(it) if it.items > 0 and collapse and it.major == 5 => {
							# The head comes when the map closes, with the count of its entries after `dedup_entries`.
							$open = $open.append({ indefinite: Bool.False, buffered: Bool.True, major: it.major, left: it.items, count: 0, before: $out, marks: [] })
							$out = []
							$p = it.next
							Bool.False
						}
						Ok(it) if it.items > 0 => {
							$out = put_head($out, it.major, it.arg)
							$open = $open.append({ indefinite: Bool.False, buffered: Bool.False, major: it.major, left: it.items, count: 0, before: [], marks: [] })
							$p = it.next
							Bool.False
						}
						Ok(it) => {
							$out = put_head($out, it.major, it.arg)
							$p = it.next
							Bool.True
						}
						Err(_) => {
							$p = end
							Bool.False
						}
					}
				}
			}
		if whole {
			# Close each definite item that has all its items now.
			var $closing = Bool.True
			while $closing {
				match $open.last() {
					Ok(f) if !f.indefinite and f.left == 0 => {
						if f.buffered {
							$out = close_buffered(f, $out, dups)
						}
						$open = $open.drop_last(1)
					}
					_ => {
						$closing = Bool.False
					}
				}
			}
		}
	}
	$out
}

## The output of a buffered item of `canonical_with` when it closes: the output before it, its head with the count
## of its items, then its items (`out`). For a map with `First` or `Last`, one entry of each key (`dedup_entries`).
close_buffered : { indefinite : Bool, buffered : Bool, major : U8, left : U64, count : U64, before : List(U8), marks : List(U64) }, List(U8), [Keep, First, Last] -> List(U8)
close_buffered = |f, out, dups|
	if f.major == 5 and dups != Keep {
		d = dedup_entries(out, f.marks, dups)
		put_head(f.before, 5, d.count).concat(d.bytes)
	} else {
		put_head(f.before, f.major, if (f.major == 5) f.count // 2 else f.count).concat(out)
	}

## The entries of one map in `out` (`marks`: the start of each key and value) with one entry for each key, as the
## `Cbor.Value` reader reads the map: `First` keeps the first entry of a key, `Last` the last one, each in its place.
## Two keys are the same when their bytes are (each inner map has one entry of each key already). A sort of the keys,
## so O(n log n) for n entries: no hash of an attacker key.
dedup_entries : List(U8), List(U64), [Keep, First, Last] -> { bytes : List(U8), count : U64 }
dedup_entries = |out, marks, dups| {
	n = marks.len() // 2
	key = |i| {
		s = marks.get(2 * i) ?? 0
		out.sublist({ start: s, len: (marks.get(2 * i + 1) ?? s) - s })
	}
	if n < 2 or dups == Keep {
		return { bytes: out, count: n }
	}
	order = (0.U64).until(n).fold(
		List.with_capacity(n),
		|acc, i| acc.append(i),
	).sort_with(
		|a, b|
			match order_bytes(key(a), key(b)) {
				Same => ordered(a, b)
				other => other
			},
	)
	# Each run of the same key: all its entries but one are dropped.
	var $drop = List.repeat(Bool.False, n)
	var $run = 0.U64
	var $i = 1.U64
	while $i <= n {
		same = $i < n and order_bytes(key(order.get($i - 1) ?? 0), key(order.get($i) ?? 0)) == Same
		if !same {
			kept = if (dups == First) $run else $i - 1
			for r in $run.until($i) {
				if r != kept {
					$drop = $drop.set(order.get(r) ?? 0, Bool.True) ?? $drop
				}
			}
			$run = $i
		}
		$i = $i + 1
	}
	var $bytes = List.with_capacity(out.len())
	var $count = 0.U64
	for j in (0.U64).until(n) {
		if !($drop.get(j) ?? Bool.False) {
			s = marks.get(2 * j) ?? 0
			e = marks.get(2 * j + 2) ?? out.len()
			$bytes = put_span($bytes, out, s, e - s)
			$count = $count + 1
		}
	}
	{ bytes: $bytes, count: $count }
}

## The bytes of the chunks of the string of indefinite length at `p`, joined. The walk checked the chunks.
joined : List(U8), U64 -> List(U8)
joined = |bytes, p| {
	var $out = []
	var $q = p + 1
	while bytes.get($q) != Ok(0xff) {
		match head_at(bytes, $q, loose) {
			Ok(c) => {
				$out = $out.concat(bytes.sublist({ start: c.next, len: c.arg }))
				$q = c.next + c.arg
			}
			Err(_) => {
				return $out
			}
		}
	}
	$out
}

## The end of the map at `pos` from `map_ends` (pairs of start and end, in order of start).
map_end : List(U64), U64 -> Try(U64, [NotFound])
map_end = |ends, pos| {
	var $lo = 0.U64
	var $hi = ends.len() // 2
	while $lo < $hi {
		mid = ($lo + $hi) // 2
		start = ends.get(2 * mid) ?? 0
		if start == pos {
			return ends.get(2 * mid + 1).map_err(|_| NotFound)
		}
		if start < pos {
			$lo = mid + 1
		} else {
			$hi = mid
		}
	}
	Err(NotFound)
}

## The path to the item that starts at `pos` (see `path_at`) in a valid item. One pass over the items,
## with a loop and a list of the open containers, not a recursion.
## Only `path_at` calls it, after `skip` of all the bytes (each check of `item_at`): so the steps here do not check
## the UTF-8 of text again. The `Str` of a key is made only for the path that it gives.
path_to : Cbor.Reader, U64 -> Try(List(Cbor.Step), [NotFound])
path_to = |state, pos| {
	bytes = state.bytes
	var $p = state.pos
	# One entry for each open array or map: is it a map, the items left, the index of the next item.
	var $open = []
	# One step for each open container that has an item in progress: an index, the position of a text key,
	# or a map key that is not text (no path).
	var $path = []
	while $p <= pos {
		# Here $p is at the start of an item, and $path is the path of that item.
		if $p == pos {
			return $path.map_try(
				|step|
					match step {
						Index(i) => Ok(Index(i))
						KeyAt(k) => text(at(state, k)).map_ok(|t| Key(t.value)).map_err(|_| NotFound)
						NotText => Err(NotFound)
					},
			)
		}
		it = item_with(bytes, $p, any_length, Bool.False) ? |_| NotFound
		$p = it.next
		# A tag: its item follows, with the same path.
		if it.major != 6 {
			if it.major == 4 or it.major == 5 {
				# An indefinite length: `no_pos` entries left, until the break.
				$open = $open.append({ map: it.major == 5, left: it.arg, index: 0 })
			}
			# Go to the start of the next item. Close each container that has no items left.
			var $next = Bool.False
			while !$next {
				top = $open.last() ? |_| NotFound
				if top.index > 0 {
					$path = $path.drop_last(1)
				}
				if top.left == no_pos and bytes.get($p) == Ok(0xff) {
					$p = $p + 1
					$open = $open.drop_last(1)
				} else if top.left == 0 {
					$open = $open.drop_last(1)
				} else {
					key =
						if top.map {
							k = item_with(bytes, $p, any_length, Bool.False) ? |_| NotFound
							if k.major == 3 {
								key_at = $p
								$p = k.next
								KeyAt(key_at)
							} else {
								after = skip(at(state, $p)) ? |_| NotFound
								$p = after.pos
								NotText
							}
						} else {
							Index(top.index)
						}
					$open = $open.drop_last(1).append({ map: top.map, left: if (top.left == no_pos) no_pos else top.left - 1, index: top.index + 1 })
					$path = $path.append(key)
					$next = Bool.True
				}
			}
		}
	}
	Err(NotFound)
}

put_head : List(U8), U8, U64 -> List(U8)
put_head = |out, major, n| {
	m = major.shl_wrap(5)
	if n < 24 {
		out.append(m.bitwise_or(n.to_u8_wrap()))
	} else if n < 0x100 {
		out.append(m.bitwise_or(24)).append(n.to_u8_wrap())
	} else if n < 0x10000 {
		put_be(out.append(m.bitwise_or(25)), n, 2)
	} else if n < 0x100000000 {
		put_be(out.append(m.bitwise_or(26)), n, 4)
	} else {
		put_be(out.append(m.bitwise_or(27)), n, 8)
	}
}

## A text head, then the bytes of the text, with no copy of the text into a new list.
put_text : List(U8), Str -> List(U8)
put_text = |out, s| Json.append_json_string_bytes(put_head(out, 3, s.count_utf8_bytes()), s)

put_int : List(U8), I64 -> List(U8)
put_int = |out, i|
	if i >= 0 {
		put_head(out, 0, i.to_u64_wrap())
	} else {
		put_head(out, 1, (-1 - i).to_u64_wrap())
	}

put_be : List(U8), U64, U64 -> List(U8)
put_be = |out, n, size| {
	var $o = out
	for i in (0.U64).until(size) {
		$o = $o.append(n.shr_zf_wrap((8 * (size - 1 - i)).to_u8_wrap()).to_u8_wrap())
	}
	$o
}

# Streams: Cbor.Items
#
# Buffer: a window with an offset. `buf` starts at the stream position `base`, and `off` is the start of the next item
# in it. A whole item moves `off` and copies nothing. `push` appends its chunk first (`append_items`): with no open
# bytes the chunk becomes `buf`, with no copy; with open bytes at `off > 0` the bytes before `off` are dropped and the
# open bytes are copied one time (the walk state moves by `off`); at `off == 0` the chunk is appended in place, and the
# capacity grows by a factor of 2. Then `push` takes each item that is whole (`items_next`) until the bytes end.
# Each item is walked one time with `walk_from`: a `Cut` walk is kept and goes on after the next chunk. Then the typed
# reader reads the item in `buf`, with the keys that the walk found to skip.
# The append is in place only when the decoder has one reference: `push` takes it, and gives the next one back, so a
# loop that sets its variable to the next decoder (`$items = r.rest?`) keeps one reference.

## The phase of a `Cbor.Items`. `Head`: the tags and the head of the root array. `Counted(n)`: n items left in an array
## of definite length. `UntilBreak`: items of an array of indefinite length until its break. `Sequence`: root items
## until the end of the input. `AfterRoot`: the array is complete, and no byte can come after it.
ItemsPhase : [Head, Counted(U64), UntilBreak, Sequence, AfterRoot]

## An `Unknown` length for `Iter.custom`, of the type of the compiler: the length of a range of 2^64 values does not
## fit a U64. The type of this argument is not the same in all nightly compilers.
unknown_length = (0.U64).range_len_if_known(U64.highest, 1, Inclusive)

## A decoder with no bytes, in `phase`, with the most bytes `limit` for one item.
new_items : Cbor.Options, ItemsPhase, U64 -> Cbor.Items
new_items = |options, phase, limit| {
	setup = parse_setup(options)
	{ buf: [], base: 0, off: 0, phase, cut: Idle, count: 0, depth: 0, root: no_pos, input_done: Bool.False, limit, rules: setup.rules, cbor: setup.cbor }
}

## `items` with `chunk` after its bytes. `buf` is taken out of the record first, so it has one reference at the
## append when `items` has one. No early return of `items`: then `items` is borrowed, and each append copies `buf`.
append_items : Cbor.Items, List(U8) -> Cbor.Items
append_items = |items, chunk| {
	{ buf, base, off, phase, cut, count, depth, root, input_done, limit, rules, cbor } = items
	len = buf.len()
	if chunk.is_empty() {
		{ buf, base, off, phase, cut, count, depth, root, input_done, limit, rules, cbor }
	} else if off >= len {
		# No open bytes: the chunk is the buffer, with no copy.
		{ buf: chunk, base: base + len, off: 0, phase, cut, count, depth, root, input_done, limit, rules, cbor }
	} else if off > 0 {
		# Drop the bytes before `off`: one copy of the open bytes. Then `off` is 0 until the next item.
		{ buf: grow(buf.drop_first(off), chunk), base: base + off, off: 0, phase, cut: shift_walk(cut, off), count, depth, root, input_done, limit, rules, cbor }
	} else {
		{ buf: grow(buf, chunk), base, off, phase, cut, count, depth, root, input_done, limit, rules, cbor }
	}
}

## `buf` with `chunk` after it. When the capacity is too small, it grows to two times the length or more, so a series
## of appends is linear in all.
grow : List(U8), List(U8) -> List(U8)
grow = |buf, chunk| {
	n = chunk.len()
	start = if (buf.capacity() - buf.len() >= n) buf else buf.reserve(if (buf.len() > n) buf.len() else n)
	start.concat(chunk)
}

## The walk state `cut` with each position `d` bytes less: the bytes before it are dropped.
shift_walk : [Idle, Open(WalkState)], U64 -> [Idle, Open(WalkState)]
shift_walk = |cut, d|
	match cut {
		Idle => Idle
		Open(ws) =>
			Open({
				pos: ws.pos - d,
				count: ws.count,
				open: ws.open.map(|o| { ..o, start: o.start - d }),
				# A key with no end yet has the end `no_pos`.
				keys: ws.keys.map(|k| if (k == no_pos) k else k - d),
				skips: ws.skips.map(|k| k - d),
				ends: ws.ends.map(|k| k - d),
				keep: ws.keep,
			})
	}

## `items` with the input complete.
end_items : Cbor.Items -> Cbor.Items
end_items = |items| {
	{ buf, base, off, phase, cut, count, depth, root, limit, rules, cbor, .. } = items
	{ buf, base, off, phase, cut, count, depth, root, input_done: Bool.True, limit, rules, cbor }
}

## `Cbor.Items.push`: the items that are whole after `chunk`, each read with `parse_shape`, and the next decoder or
## the error. The items before an error are in `values`.
push_items : Cbor.Items, List(U8), (Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])), (U64 -> [InvalidCbor(U64), MissingRequiredField(Str), ..e]) -> { values : List(a), rest : Try(Cbor.Items, [InvalidCbor(U64), MissingRequiredField(Str), ..e]) }
push_items = |items, chunk, parse_shape, too_large| {
	var $s = append_items(items, chunk)
	var $values = []
	var $err = Ok({})
	var $more = Bool.True
	while $more {
		match items_next($s, parse_shape, too_large) {
			Ok(Item(value, next)) => {
				$values = $values.append(value)
				$s = next
			}
			Ok(NeedInput(next)) | Ok(End(next)) => {
				$s = next
				$more = Bool.False
			}
			Err(e) => {
				$err = Err(e)
				$more = Bool.False
			}
		}
	}
	match $err {
		Ok(_) => { values: $values, rest: Ok($s) }
		Err(e) => { values: $values, rest: Err(e) }
	}
}

## A reader that reads no value: for `finish`, which needs no type. After `push`, no item of the bytes is whole, so
## the end of the input gives `End` or the error of the cut item before a reader runs.
no_parse : Cbor.Reader -> Try({ value : {}, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str), ..e])
no_parse = |state| Err(InvalidCbor(state.pos))

## `Cbor.Items.finish`: `Ok` when the input can end after the bytes so far, else the error of the cut item.
finish_items : Cbor.Items -> Try({}, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64)])
finish_items = |items|
	match items_next(end_items(items), no_parse, |p| TooLarge(p)) {
		Ok(End(_)) => Ok({})
		# Not reached: with the input complete, the bytes end in an item only with an error.
		Ok(NeedInput(rest)) | Ok(Item(_, rest)) => Err(InvalidCbor(rest.position()))
		Err(e) => Err(e)
	}

## The next step of `items`: the heads of the root, then one item read with `parse_shape`. `too_large` makes the
## error of an item larger than the limit (`TooLarge`; `parse_sequence` has no limit and no such tag).
items_next : Cbor.Items, (Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])), (U64 -> [InvalidCbor(U64), MissingRequiredField(Str), ..e]) -> Try([Item(a, Cbor.Items), NeedInput(Cbor.Items), End(Cbor.Items)], [InvalidCbor(U64), MissingRequiredField(Str), ..e])
items_next = |items, parse_shape, too_large| {
	var $s = items
	while $s.phase == Head {
		match root_head($s, 4)? {
			Moved(s) => {
				$s = s
			}
			Wait => return Ok(NeedInput($s))
		}
	}
	{ buf, base, off: p, phase, cut, count, depth, root, input_done, limit, rules, cbor } = $s
	len = buf.len()
	match phase {
		Counted(0) | AfterRoot =>
			if p < len {
				# Bytes after the root array, as in `parse_with`.
				Err(InvalidCbor(base + p))
			} else {
				rest = { buf, base, off: p, phase: AfterRoot, cut, count, depth, root, input_done, limit, rules, cbor }
				if (input_done) Ok(End(rest)) else Ok(NeedInput(rest))
			}
		UntilBreak if buf.get(p) == Ok(0xff) =>
			items_next({ buf, base, off: p + 1, phase: AfterRoot, cut, count, depth, root, input_done, limit, rules, cbor }, parse_shape, too_large)
		_ if p >= len =>
			if !input_done {
				Ok(NeedInput({ buf, base, off: p, phase, cut, count, depth, root, input_done, limit, rules, cbor }))
			} else if phase == Sequence {
				Ok(End({ buf, base, off: p, phase, cut, count, depth, root, input_done, limit, rules, cbor }))
			} else {
				# The bytes end between two items: the error is at the open array (one truncation rule).
				Err(InvalidCbor(root))
			}
		_ => {
			in_sequence = phase == Sequence
			# An item of the array is in `depth` levels of the root, and its items count in the whole root.
			item_rules = if (in_sequence) rules else { ..rules, max_depth: rules.max_depth - depth }
			match walk_item(buf, base, p, cut, if (in_sequence) 0 else count, limit, item_rules, input_done) {
				Err(InvalidCbor(e)) => Err(InvalidCbor(e))
				Err(Big(q)) => Err(too_large(q))
				Ok(Open(ws)) => Ok(NeedInput({ buf, base, off: p, phase, cut: Open(ws), count, depth, root, input_done, limit, rules, cbor }))
				Ok(Whole(ws)) => {
					end = ws.pos
					start = at(reader(buf), p)
					state = if (ws.skips.is_empty()) start else with_memo(start, { ..no_memo, skips: ws.skips.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same) })
					parsed =
						match parse_shape(state) {
							Ok(x) => x
							Err(InvalidCbor(e)) => return Err(InvalidCbor(base + e))
							Err(other) => return Err(other)
						}
					if parsed.rest.pos != end {
						return Err(InvalidCbor(base + parsed.rest.pos))
					}
					left =
						match phase {
							Counted(n) => Counted(n - 1)
							other => other
						}
					Ok(Item(parsed.value, { buf, base, off: end, phase: left, cut: Idle, count: if (in_sequence) count else ws.count, depth, root, input_done, limit, rules, cbor }))
				}
			}
		}
	}
}

## The walk of the item at `p` in `buf` (stream position `base + p`), from the state `cut` of an earlier `Cut`, or
## from the start with the items `count` of the root so far. The walk sees only the first `budget` bytes of the item.
## `Whole(ws)`: the item ends at `ws.pos`. `Open(ws)`: the bytes end in the item, and more can come. The errors are at
## stream positions: `Big(pos)` when the item is not whole in its first `budget` bytes and more bytes exist (then the
## caller gives `TooLarge`), the error of a cut item after the end of the input, or an error of the walk.
walk_item : List(U8), U64, U64, [Idle, Open(WalkState)], U64, U64, Rules, Bool -> Try([Whole(WalkState), Open(WalkState)], [InvalidCbor(U64), Big(U64)])
walk_item = |buf, base, p, cut, count, budget, rules, input_done| {
	from =
		match cut {
			Open(ws) => ws
			Idle => { ..walk_start(p, [], Bool.False), count }
		}
	window = buf.len() - p > budget
	seen = if (window) buf.sublist({ start: 0, len: p + budget }) else buf
	match walk_from(seen, from, rules) {
		Err(InvalidCbor(e)) => Err(InvalidCbor(base + e))
		Ok(Cut(ws)) =>
			if window {
				Err(Big(base + p))
			} else if input_done {
				Err(InvalidCbor(base + cut_pos(buf, ws)))
			} else {
				Ok(Open(ws))
			}
		Ok(Whole(ws)) => Ok(Whole(ws))
	}
}

## One head of the root of `Items.array` or `Entries.map`: a tag of `ignore_tags`, or the head of the container of
## the major type `major` (4 or 5). Each one counts for `max_items` and `max_depth`, as in the walk of `parse_with`.
## `Wait`: the head is not whole in the bytes so far. The phase after the container head counts its items (or entries).
root_head : Cbor.Items, U8 -> Try([Moved(Cbor.Items), Wait], [InvalidCbor(U64)])
root_head = |items, major| {
	{ buf, base, off: p, cut, count, depth, root, input_done, limit, rules, cbor, .. } = items
	h =
		match head_at(buf, p, rules) {
			Ok(x) => x
			Err(InvalidCbor(e)) => {
				if !cut_at(buf, p, rules) {
					return Err(InvalidCbor(base + e))
				}
				if !input_done {
					return Ok(Wait)
				}
				# One truncation rule: a cut head, or else the innermost open tag.
				return Err(InvalidCbor(if (p >= buf.len() and root != no_pos) root else base + p))
			}
		}
	start = base + p
	if count >= rules.max_items or depth >= rules.max_depth {
		return Err(InvalidCbor(start))
	}
	if h.major == 6 and cbor.ignore_tags.contains(h.arg) {
		Ok(Moved({ buf, base, off: h.next, phase: Head, cut, count: count + 1, depth: depth + 1, root: start, input_done, limit, rules, cbor }))
	} else if h.major == major {
		phase = if (indefinite_at(h, p)) UntilBreak else Counted(h.arg)
		Ok(Moved({ buf, base, off: h.next, phase, cut, count: count + 1, depth: depth + 1, root: start, input_done, limit, rules, cbor }))
	} else {
		# Another type of root: the error of `parse_with` as a `List(a)` or a `Dict(k, v)`.
		Err(InvalidCbor(start))
	}
}

# Streams: Cbor.Entries

# An entry is two items in the window of `Cbor.Items` (one shared record, with `append_items`,
# `end_items`, `root_head` and `walk_item`): the key, then the value. Each one is walked when it is whole, and the
# `off` of the window stays at the start of the entry until the entry is given, so the key bytes stay in `buf`. When
# the key is whole, it is checked against the keys before it: a `KeySet` of canonical bytes (`key_order: Any`), or
# the one key before (`Sorted`). Then the value is walked, and the typed readers read the key and the value in `buf`.
# With `Sorted` and `Last`, a whole entry waits at `off` (`held`) until the next key is greater (it is given) or the
# same (it is dropped), or the map ends.

## A decoder of the entries of a root map, with no bytes.
new_entries : Cbor.Options -> Cbor.Entries
new_entries = |options| {
	items = new_items(options, Head, options.?max_buffer ?? 16_777_216)
	{ items, part: Key, held: 0, held_key: 0, held_skips: [], keys: no_keys, prev: [], first: Bool.True }
}

## `entries` with `chunk` after its bytes (`append_items`).
append_entries : Cbor.Entries, List(U8) -> Cbor.Entries
append_entries = |entries, chunk| {
	{ items, part, held, held_key, held_skips, keys, prev, first } = entries
	{ items: append_items(items, chunk), part, held, held_key, held_skips, keys, prev, first }
}

## `entries` with the input complete.
end_entries : Cbor.Entries -> Cbor.Entries
end_entries = |entries| {
	{ items, part, held, held_key, held_skips, keys, prev, first } = entries
	{ items: end_items(items), part, held, held_key, held_skips, keys, prev, first }
}

## `Cbor.Entries.push`: the entries that are whole after `chunk`, and the next decoder or the error. The entries
## before an error are in `values`.
push_entries : Cbor.Entries, List(U8), (Cbor.Reader -> Try({ value : k, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])), (Cbor.Reader -> Try({ value : v, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])) -> { values : List((k, v)), rest : Try(Cbor.Entries, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable, ..e]) }
push_entries = |entries, chunk, parse_key, parse_value| {
	var $s = append_entries(entries, chunk)
	var $values = []
	var $err = Ok({})
	var $more = Bool.True
	while $more {
		match entries_next($s, parse_key, parse_value) {
			Ok(Entry(key, value, next)) => {
				$values = $values.append((key, value))
				$s = next
			}
			Ok(NeedInput(next)) | Ok(End(next)) => {
				$s = next
				$more = Bool.False
			}
			Err(e) => {
				$err = Err(e)
				$more = Bool.False
			}
		}
	}
	match $err {
		Ok(_) => { values: $values, rest: Ok($s) }
		Err(e) => { values: $values, rest: Err(e) }
	}
}

## `Cbor.Entries.finish`: `Ok` when the input can end after the bytes so far, else the error of the cut entry.
finish_entries : Cbor.Entries -> Try({}, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable])
finish_entries = |entries|
	match entries_next(end_entries(entries), no_parse, no_parse) {
		Ok(End(_)) => Ok({})
		# Not reached: with the input complete, the bytes end in an entry only with an error.
		Ok(NeedInput(rest)) | Ok(Entry(_, _, rest)) => Err(InvalidCbor(rest.position()))
		Err(e) => Err(e)
	}

## The window `items` with the start `off` of the next entry or item, the phase, the walk and the count of the root.
moved_items : Cbor.Items, U64, ItemsPhase, [Idle, Open(WalkState)], U64 -> Cbor.Items
moved_items = |items, off, phase, cut, count| {
	{ buf, base, depth, root, input_done, limit, rules, cbor, .. } = items
	{ buf, base, off, phase, cut, count, depth, root, input_done, limit, rules, cbor }
}

## A key reader `parse` with the check of a key of a `Dict` (`exact_key_dups` with `dups`): only the form that the writer writes.
exact_key_with : Cbor.Reader, (Cbor.Reader -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])), [Keep, First, Last] -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str), ..e]) where [a.Cbor.Encodable([])]
exact_key_with = |state, parse, dups| {
	parsed = parse(state)?
	match exact_key_dups(state, parsed, dups) {
		Ok(x) => Ok(x)
		Err(InvalidCbor(p)) => Err(InvalidCbor(p))
	}
}

## The next step of `entries`: the heads of the root map, then the steps of `entry_step` until an entry, a wait or
## the end. With `duplicate_keys: Last` and `key_order: Any`, the error `NotStreamable` before any byte is read.
entries_next : Cbor.Entries, (Cbor.Reader -> Try({ value : k, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])), (Cbor.Reader -> Try({ value : v, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])) -> Try([Entry(k, v, Cbor.Entries), NeedInput(Cbor.Entries), End(Cbor.Entries)], [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable, ..e])
entries_next = |entries, parse_key, parse_value| {
	{ items, part, held, held_key, held_skips, keys, prev, first } = entries
	if items.rules.keys == Last and items.rules.order == Any {
		return Err(NotStreamable)
	}
	var $s = items
	while $s.phase == Head {
		match root_head($s, 5)? {
			Moved(s) => {
				$s = s
			}
			Wait => return Ok(NeedInput({ items: $s, part, held, held_key, held_skips, keys, prev, first }))
		}
	}
	var $e = { items: $s, part, held, held_key, held_skips, keys, prev, first }
	var $out = Again
	var $more = Bool.True
	while $more {
		# The decoder comes back in each step, so `$e` is set again before the next step: one reference to `buf`.
		{ entries: next, out } = entry_step($e, parse_key, parse_value)?
		$e = next
		match out {
			Again => {}
			other => {
				$out = other
				$more = Bool.False
			}
		}
	}
	match $out {
		Give(key, value) => Ok(Entry(key, value, $e))
		Done => Ok(End($e))
		_ => Ok(NeedInput($e))
	}
}

## One step of the entries of the root map (after its head): the key of the open entry, its value, the end of the
## map, or the bytes after it. `Again`: a step was made, and more can follow. `Give`: an entry. `Wait`: more bytes
## are needed. `Done`: the map is complete and the input ended at its end.
entry_step : Cbor.Entries, (Cbor.Reader -> Try({ value : k, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])), (Cbor.Reader -> Try({ value : v, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])) -> Try({ entries : Cbor.Entries, out : [Again, Give(k, v), Wait, Done] }, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable, ..e])
entry_step = |entries, parse_key, parse_value| {
	{ items, part, held, held_key, held_skips, keys, prev, first } = entries
	buf = items.buf
	base = items.base
	off = items.off
	phase = items.phase
	rules = items.rules
	input_done = items.input_done
	len = buf.len()
	sorted = rules.order == Sorted
	# The bytes that the duplicate check keeps count in `max_buffer`, with the held entry.
	kept = held + (if (sorted) prev.len() else keys.size)
	# An item of the map is in `depth` levels of the root, and its items count in the whole root.
	item_rules = { ..rules, max_depth: rules.max_depth - items.depth }
	match part {
		Key => {
			p = off + held
			ended =
				match phase {
					Counted(0) => Bool.True
					UntilBreak => buf.get(p) == Ok(0xff)
					_ => Bool.False
				}
			if phase == AfterRoot {
				if p < len {
					# Bytes after the root map, as in `parse_with`.
					Err(InvalidCbor(base + p))
				} else if input_done {
					Ok({ entries: { items, part, held, held_key, held_skips, keys, prev, first }, out: Done })
				} else {
					Ok({ entries: { items, part, held, held_key, held_skips, keys, prev, first }, out: Wait })
				}
			} else if ended {
				if held > 0 {
					# The map ends: the held entry is the last of its key.
					pair = read_entry(buf, base, off, held_key, p, held_skips.map(|x| x + off), parse_key, parse_value)?
					Ok({ entries: { items: moved_items(items, p, phase, Idle, items.count), part, held: 0, held_key: 0, held_skips: [], keys, prev, first }, out: Give(pair.0, pair.1) })
				} else {
					after = if (phase == UntilBreak) p + 1 else p
					Ok({ entries: { items: moved_items(items, after, AfterRoot, Idle, items.count), part, held, held_key, held_skips, keys, prev, first }, out: Again })
				}
			} else if p >= len {
				if input_done {
					# The bytes end between two entries: the error is at the open map (one truncation rule).
					Err(InvalidCbor(items.root))
				} else {
					Ok({ entries: { items, part, held, held_key, held_skips, keys, prev, first }, out: Wait })
				}
			} else {
				match walk_item(buf, base, p, items.cut, items.count, items.limit.minus_saturated(kept), item_rules, input_done) {
					Err(InvalidCbor(x)) => Err(InvalidCbor(x))
					Err(Big(x)) => Err(TooLarge(x))
					Ok(Open(ws)) => Ok({ entries: { items: moved_items(items, off, phase, Open(ws), items.count), part, held, held_key, held_skips, keys, prev, first }, out: Wait })
					Ok(Whole(ws)) => {
						end = ws.pos
						# The skips inside the key, from the start of the entry.
						value_part = |later| Value({ key: end - p, later, skips: ws.skips.map(|x| x - p) })
						if sorted {
							order = if (first) Before else key_after(prev, buf, p, end, rules)
							match order {
								After => Err(InvalidCbor(base + p))
								Same =>
									match rules.keys {
										First => Ok({ entries: { items: moved_items(items, off, phase, Idle, ws.count), part: value_part(Bool.True), held, held_key, held_skips, keys, prev, first }, out: Again })
										# The held entry is not the last of its key: it is dropped.
										Last => Ok({ entries: { items: moved_items(items, p, phase, Idle, ws.count), part: value_part(Bool.False), held: 0, held_key: 0, held_skips: [], keys, prev, first }, out: Again })
										_ => Err(InvalidCbor(base + p))
									}
								Before => {
									key = deterministic_copy(buf, p, end, rules)
									if held > 0 {
										# A greater key: the held entry is the last of its key.
										pair = read_entry(buf, base, off, held_key, p, held_skips.map(|x| x + off), parse_key, parse_value)?
										Ok({ entries: { items: moved_items(items, p, phase, Idle, ws.count), part: value_part(Bool.False), held: 0, held_key: 0, held_skips: [], keys, prev: key, first: Bool.False }, out: Give(pair.0, pair.1) })
									} else {
										Ok({ entries: { items: moved_items(items, off, phase, Idle, ws.count), part: value_part(Bool.False), held, held_key, held_skips, keys, prev: key, first: Bool.False }, out: Again })
									}
								}
							}
						} else {
							# The canonical bytes of the key: in place for an integer, or bytes or text with the shortest head.
							in_place = plain_key(buf, p, rules)
							canon = if (in_place) [] else canonical(buf, p, end, key_dups(rules))
							(src, start, size) = if (in_place) (buf, p, end - p) else (canon, 0, canon.len())
							if keys_has(keys, src, start, size) {
								if rules.keys == First {
									Ok({ entries: { items: moved_items(items, off, phase, Idle, ws.count), part: value_part(Bool.True), held, held_key, held_skips, keys, prev, first }, out: Again })
								} else {
									Err(InvalidCbor(base + p))
								}
							} else {
								added = keys_add(keys, src, start, size)
								if added.size > items.limit {
									Err(TooLarge(base + p))
								} else {
									Ok({ entries: { items: moved_items(items, off, phase, Idle, ws.count), part: value_part(Bool.False), held, held_key, held_skips, keys: added, prev, first }, out: Again })
								}
							}
						}
					}
				}
			}
		}
		Value({ key, later, skips }) => {
			# The open entry starts after the held entry. Its value starts after its key.
			e = off + held
			p = e + key
			if p >= len and input_done {
				# The bytes end after a key: the error is at the open map.
				Err(InvalidCbor(items.root))
			} else {
				match walk_item(buf, base, p, items.cut, items.count, items.limit.minus_saturated(kept + key), item_rules, input_done) {
					Err(InvalidCbor(x)) => Err(InvalidCbor(x))
					Err(Big(x)) => Err(TooLarge(x))
					Ok(Open(ws)) => Ok({ entries: { items: moved_items(items, off, phase, Open(ws), items.count), part, held, held_key, held_skips, keys, prev, first }, out: Wait })
					Ok(Whole(ws)) => {
						end = ws.pos
						left =
							match phase {
								Counted(n) => Counted(n - 1)
								other => other
							}
						if later {
							# A later instance of a key (`First`): walked and counted, not given.
							Ok({ entries: { items: moved_items(items, end, left, Idle, ws.count), part: Key, held, held_key, held_skips, keys, prev, first }, out: Again })
						} else if sorted and rules.keys == Last {
							# The entry waits for the next key (no entry is held here: a key before the value gave or dropped it).
							Ok({ entries: { items: moved_items(items, e, left, Idle, ws.count), part: Key, held: end - e, held_key: key, held_skips: skips.concat(ws.skips.map(|x| x - e)), keys, prev, first }, out: Again })
						} else {
							pair = read_entry(buf, base, e, key, end, skips.map(|x| x + e).concat(ws.skips), parse_key, parse_value)?
							Ok({ entries: { items: moved_items(items, end, left, Idle, ws.count), part: Key, held, held_key, held_skips, keys, prev, first }, out: Give(pair.0, pair.1) })
						}
					}
				}
			}
		}
	}
}

## The typed key and value of the entry at `start` in `buf`: the key has `key_len` bytes, and the value ends at `end`.
## `skips`: the keys that `duplicate_keys` skips inside them. The error positions are in the stream (`base`).
read_entry : List(U8), U64, U64, U64, U64, List(U64), (Cbor.Reader -> Try({ value : k, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])), (Cbor.Reader -> Try({ value : v, rest : Cbor.Reader }, [InvalidCbor(U64), MissingRequiredField(Str)])) -> Try((k, v), [InvalidCbor(U64), MissingRequiredField(Str), ..e])
read_entry = |buf, base, start, key_len, end, skips, parse_key, parse_value| {
	at_key = at(reader(buf), start)
	state = if (skips.is_empty()) at_key else with_memo(at_key, { ..no_memo, skips: skips.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same) })
	k =
		match parse_key(state) {
			Ok(x) => x
			Err(InvalidCbor(x)) => return Err(InvalidCbor(base + x))
			Err(other) => return Err(other)
		}
	if k.rest.pos != start + key_len {
		return Err(InvalidCbor(base + k.rest.pos))
	}
	v =
		match parse_value(at(state, start + key_len)) {
			Ok(x) => x
			Err(InvalidCbor(x)) => return Err(InvalidCbor(base + x))
			Err(other) => return Err(other)
		}
	if v.rest.pos != end {
		return Err(InvalidCbor(base + v.rest.pos))
	}
	Ok((k.value, v.value))
}

## `key_order: Sorted` in a stream: the order of RFC 8949 4.2.1 of the key before (`prev`, its deterministic bytes) and
## the key from `start` to `end` in `bytes` (`order_keys` with one key outside `bytes`). A key that is deterministic as
## it is (`plain_key`) is compared in place.
key_after : List(U8), List(U8), U64, U64, Rules -> [Before, Same, After]
key_after = |prev, bytes, start, end, rules|
	if plain_key(bytes, start, rules) {
		la = prev.len()
		lb = end - start
		n = if (la < lb) la else lb
		var $k = 0.U64
		while $k < n {
			x = prev.get($k) ?? 0
			y = bytes.get(start + $k) ?? 0
			if x != y {
				return if (x < y) Before else After
			}
			$k = $k + 1
		}
		ordered(la, lb)
	} else {
		order_bytes(prev, deterministic(bytes, start, end, key_dups(rules)))
	}

## The deterministic bytes of the key from `start` to `end`, in a list of their own (no `sublist` of the buffer: it
## would keep the buffer, and the next append would copy it).
deterministic_copy : List(U8), U64, U64, Rules -> List(U8)
deterministic_copy = |bytes, start, end, rules|
	if (plain_key(bytes, start, rules)) put_span(List.with_capacity(end - start), bytes, start, end - start) else deterministic(bytes, start, end, key_dups(rules))

## `out` with the `len` bytes at `start` in `src` after it, one by one: a `concat` to an empty list can give the
## `sublist` itself, which shares `src`.
put_span : List(U8), List(U8), U64, U64 -> List(U8)
put_span = |out, src, start, len| {
	var $out = out
	var $i = start
	while $i < start + len {
		$out = $out.append(src.get($i) ?? 0)
		$i = $i + 1
	}
	$out
}

## The keys of a streamed map with `key_order: Any`, for the duplicate check of 4.5 of the design: the canonical bytes
## of each distinct key, with no hash (an attacker key cannot flood it). Sorted runs, the largest first, each with a
## power of 2 of keys (a binary counter): a lookup is a binary search in each run, O(log^2 n) compares; an insert
## merges the runs of the same size, O(log n) moves for each key. `size`: the bytes of the keys, and 8 for each key.
KeySet : { runs : List(KeyRun), size : U64 }

## One sorted run of a `KeySet`: the keys one after the other in `bytes`, and the end of each key in `ends`. The order
## is the shorter key first, then the bytes.
KeyRun : { bytes : List(U8), ends : List(U64) }

no_keys : KeySet
no_keys = { runs: [], size: 0 }

## The order of key `i` of `run` and the `len` bytes at `start` of `src`: the shorter first, then the bytes.
run_order : KeyRun, U64, List(U8), U64, U64 -> [Before, Same, After]
run_order = |run, i, src, start, len| {
	a = if (i == 0) 0 else run.ends.get(i - 1) ?? 0
	la = (run.ends.get(i) ?? 0) - a
	if la != len {
		ordered(la, len)
	} else {
		var $k = 0.U64
		while $k < la {
			x = run.bytes.get(a + $k) ?? 0
			y = src.get(start + $k) ?? 0
			if x != y {
				return if (x < y) Before else After
			}
			$k = $k + 1
		}
		Same
	}
}

## The key of the `len` bytes at `start` of `src` is in `set`: a binary search in each run.
keys_has : KeySet, List(U8), U64, U64 -> Bool
keys_has = |set, src, start, len| {
	for run in set.runs {
		var $lo = 0.U64
		var $hi = run.ends.len()
		while $lo < $hi {
			mid = ($lo + $hi) // 2
			match run_order(run, mid, src, start, len) {
				Same => return Bool.True
				Before => {
					$lo = mid + 1
				}
				After => {
					$hi = mid
				}
			}
		}
	}
	Bool.False
}

## `set` with the key of the `len` bytes at `start` of `src`, which is not in it: a new run of one key, then the last
## two runs are merged while they have the same count of keys.
keys_add : KeySet, List(U8), U64, U64 -> KeySet
keys_add = |set, src, start, len| {
	{ runs, size } = set
	var $runs = runs.append({ bytes: put_span(List.with_capacity(len), src, start, len), ends: [len] })
	var $more = Bool.True
	while $more and $runs.len() >= 2 {
		n = $runs.len()
		a = $runs.get(n - 2) ?? { bytes: [], ends: [] }
		b = $runs.get(n - 1) ?? { bytes: [], ends: [] }
		if a.ends.len() == b.ends.len() {
			$runs = $runs.drop_last(2).append(merge_runs(a, b))
		} else {
			$more = Bool.False
		}
	}
	{ runs: $runs, size: size + len + 8 }
}

## The keys of two sorted runs with no key in common, as one sorted run.
merge_runs : KeyRun, KeyRun -> KeyRun
merge_runs = |a, b| {
	na = a.ends.len()
	nb = b.ends.len()
	var $bytes = List.with_capacity(a.bytes.len() + b.bytes.len())
	var $ends = List.with_capacity(na + nb)
	var $i = 0.U64
	var $j = 0.U64
	while $i < na or $j < nb {
		b_start = if ($j == 0) 0 else b.ends.get($j - 1) ?? 0
		b_len = (b.ends.get($j) ?? b_start) - b_start
		take_a = $j >= nb or ($i < na and run_order(a, $i, b.bytes, b_start, b_len) == Before)
		if take_a {
			a_start = if ($i == 0) 0 else a.ends.get($i - 1) ?? 0
			$bytes = put_span($bytes, a.bytes, a_start, (a.ends.get($i) ?? 0) - a_start)
			$i = $i + 1
		} else {
			$bytes = put_span($bytes, b.bytes, b_start, b_len)
			$j = $j + 1
		}
		$ends = $ends.append($bytes.len())
	}
	{ bytes: $bytes, ends: $ends }
}

# Streams: ByteChunks and TextChunks
#
# One record and one implementation for both decoders: `major` is 2 (bytes) or 3 (text). No walk state: the root is
# a run of heads (the tags, the string head, the chunk heads of an indefinite length) and data. A head is read when it
# is whole in `buf`. Data goes out as a `sublist` of `buf`, with no copy, cut where `buf` ends; for text, before a cut
# code point (`utf8_cut`). `push` appends its chunk first (`append_chunks`): with nothing left in `buf`, the chunk
# becomes `buf` (no copy); with the bytes of a cut head (8 or less) or of a cut code point (3 or less), they and the
# chunk are copied into a new `buf`. So memory is bounded by the chunk size.

## The phase of a chunk decoder. `Head`: the tags and the string head. `Data(n)`: n bytes left of a string of definite
## length. `Segments`: a string of indefinite length, at a chunk head or its break. `Inner(n)`: n bytes left of a
## chunk of it. `AfterRoot`: the string is complete, and no byte can come after it.
ChunkPhase : [Head, Data(U64), Segments, Inner(U64), AfterRoot]

## The state of a `Cbor.ByteChunks` or `Cbor.TextChunks`. `buf` starts at the stream position `base`, and `off` is the
## next byte to read in it. `count` and `depth`: the items and levels so far, for `max_items` and `max_depth`. `open`:
## the stream position of the innermost head (a tag, then the string), or `no_pos`: the position of a truncation error,
## and of a UTF-8 error. `cfg`: what does not change.
ChunkState : {
	buf : List(U8),
	base : U64,
	off : U64,
	phase : ChunkPhase,
	count : U64,
	depth : U64,
	open : U64,
	input_done : Bool,
	cfg : { major : U8, rules : Rules, tags : List(U64) },
}

## A chunk decoder with no bytes, of strings of major type `major`.
new_chunks : Cbor.Options, U8 -> ChunkState
new_chunks = |options, major| {
	setup = parse_setup(options)
	{ buf: [], base: 0, off: 0, phase: Head, count: 0, depth: 0, open: no_pos, input_done: Bool.False, cfg: { major, rules: setup.rules, tags: setup.cbor.ignore_tags } }
}

## `s` with the input complete.
end_chunks : ChunkState -> ChunkState
end_chunks = |s| {
	{ buf, base, off, phase, count, depth, open, cfg, .. } = s
	{ buf, base, off, phase, count, depth, open, input_done: Bool.True, cfg }
}

## `s` with `chunk` after the bytes of `buf` that are not read (a cut head or a cut code point, or none).
append_chunks : ChunkState, List(U8) -> ChunkState
append_chunks = |s, chunk| {
	{ buf, base, off, phase, count, depth, open, input_done, cfg } = s
	len = buf.len()
	if chunk.is_empty() {
		{ buf, base, off, phase, count, depth, open, input_done, cfg }
	} else if off >= len {
		# Nothing left: the chunk is the buffer, with no copy.
		{ buf: chunk, base: base + len, off: 0, phase, count, depth, open, input_done, cfg }
	} else {
		left = buf.sublist({ start: off, len: len - off })
		{ buf: List.with_capacity(len - off + chunk.len()).concat(left).concat(chunk), base: base + off, off: 0, phase, count, depth, open, input_done, cfg }
	}
}

## The chunks of data in the bytes of `start` until it needs more bytes, and the next state, or an error. With the
## input complete, more bytes needed is the error of a cut string. `open`: the head of the string of the chunks.
chunks_run : ChunkState -> { pieces : List(List(U8)), open : U64, rest : Try(ChunkState, [InvalidCbor(U64)]) }
chunks_run = |start| {
	var $s = start
	var $pieces = []
	var $err = Ok({})
	var $more = Bool.True
	while $more {
		match chunk_step($s) {
			Ok(Moved(s)) => {
				$s = s
			}
			Ok(Piece(data, s)) => {
				$pieces = $pieces.append(data)
				$s = s
			}
			Ok(Wait(s)) => {
				if s.input_done {
					# One truncation rule: a cut head before the string, else the innermost open head.
					$err = Err(InvalidCbor(if (s.phase == Head and (s.off < s.buf.len() or s.open == no_pos)) s.base + s.off else s.open))
				}
				$s = s
				$more = Bool.False
			}
			Ok(Done(s)) => {
				$s = s
				$more = Bool.False
			}
			Err(e) => {
				$err = Err(e)
				$more = Bool.False
			}
		}
	}
	match $err {
		Ok(_) => { pieces: $pieces, open: $s.open, rest: Ok($s) }
		Err(e) => { pieces: $pieces, open: $s.open, rest: Err(e) }
	}
}

## `Cbor.ByteChunks.finish` and `Cbor.TextChunks.finish`: `Ok` when the string is complete, else the error of a cut
## string. After `push`, no data is left to give: a cut code point is the error of a cut string.
finish_chunks : ChunkState -> Try({}, [InvalidCbor(U64)])
finish_chunks = |s| {
	r = chunks_run(end_chunks(s))
	match r.rest {
		# Not reached with pieces: `push` gave each piece of the bytes so far.
		Ok(rest) => if (r.pieces.is_empty()) Ok({}) else Err(InvalidCbor(rest.open))
		Err(e) => Err(e)
	}
}

## One step of a chunk decoder in the bytes of `buf`: a head read (`Moved`), a chunk of data, `Wait` for more bytes, or
## `Done` (after the end of the input, the string is complete). The checks are the checks of `walk_from` on the same heads.
chunk_step : ChunkState -> Try([Moved(ChunkState), Piece(List(U8), ChunkState), Wait(ChunkState), Done(ChunkState)], [InvalidCbor(U64)])
chunk_step = |s| {
	{ buf, base, off, phase, count, depth, open, input_done, cfg } = s
	len = buf.len()
	rules = cfg.rules
	match phase {
		Head => {
			h =
				match head_at(buf, off, rules) {
					Ok(x) => x
					Err(InvalidCbor(e)) => return if (cut_at(buf, off, rules)) Ok(Wait(s)) else Err(InvalidCbor(base + e))
				}
			pos = base + off
			if count >= rules.max_items {
				return Err(InvalidCbor(pos))
			}
			if h.major == 6 and cfg.tags.contains(h.arg) {
				# A tag of `ignore_tags`: one more level, as in the walk.
				if depth >= rules.max_depth {
					return Err(InvalidCbor(pos))
				}
				Ok(Moved({ buf, base, off: h.next, phase: Head, count: count + 1, depth: depth + 1, open: pos, input_done, cfg }))
			} else if h.major == cfg.major {
				next_phase = if (indefinite_at(h, off)) Segments else Data(h.arg)
				Ok(Moved({ buf, base, off: h.next, phase: next_phase, count: count + 1, depth, open: pos, input_done, cfg }))
			} else {
				# Another type of root: the error of `parse_with` as a `List(U8)` or a `Str`.
				Err(InvalidCbor(pos))
			}
		}
		Data(0) => Ok(Moved({ buf, base, off, phase: AfterRoot, count, depth, open, input_done, cfg }))
		Inner(0) => Ok(Moved({ buf, base, off, phase: Segments, count, depth, open, input_done, cfg }))
		Data(n) | Inner(n) => {
			have = len - off
			take = if (have >= n) n else if (cfg.major == 3) utf8_cut(buf, off, have) else have
			if take == 0 {
				Ok(Wait(s))
			} else {
				left =
					match phase {
						Inner(_) => Inner(n - take)
						_ => Data(n - take)
					}
				Ok(Piece(buf.sublist({ start: off, len: take }), { buf, base, off: off + take, phase: left, count, depth, open, input_done, cfg }))
			}
		}
		Segments =>
			if off >= len {
				Ok(Wait(s))
			} else if buf.get(off) == Ok(0xff) {
				Ok(Moved({ buf, base, off: off + 1, phase: AfterRoot, count, depth, open, input_done, cfg }))
			} else {
				# A chunk: a string of definite length of the same major type (RFC 8949 3.2.3).
				match head_at(buf, off, rules) {
					Err(InvalidCbor(e)) => if (cut_at(buf, off, rules)) Ok(Wait(s)) else Err(InvalidCbor(base + e))
					Ok(c) if c.major != cfg.major or indefinite_at(c, off) => Err(InvalidCbor(open))
					Ok(c) => Ok(Moved({ buf, base, off: c.next, phase: Inner(c.arg), count, depth, open, input_done, cfg }))
				}
			}
		AfterRoot =>
			if off < len {
				# Bytes after the string, as in `parse_with`.
				Err(InvalidCbor(base + off))
			} else if input_done {
				Ok(Done(s))
			} else {
				Ok(Wait(s))
			}
	}
}

## How many of the `have` bytes at `off` end at a code point boundary: all of them, or the bytes before a code point
## that the end cuts. UTF-8 is self-synchronizing: the lead byte of a cut code point is one of the last 3 bytes.
## A lead byte 4 or more bytes before the end starts a code point that is whole (or not valid), so 3 bytes are enough.
## Bytes that are not valid UTF-8 are not kept back: `Str.from_utf8` rejects them.
utf8_cut : List(U8), U64, U64 -> U64
utf8_cut = |buf, off, have| {
	end = off + have
	var $i = end
	var $lead = no_pos
	while $lead == no_pos and $i > off and end - $i < 3 {
		$i = $i - 1
		if (buf.get($i) ?? 0).bitwise_and(0xc0) != 0x80 {
			$lead = $i
		}
	}
	if $lead == no_pos {
		have
	} else {
		b = buf.get($lead) ?? 0
		need = if (b >= 0xf0) 4 else if (b >= 0xe0) 3 else if (b >= 0xc0) 2 else 1
		if (end - $lead < need) $lead - off else have
	}
}

# Streams: the adapters to `Stream`
#
# `from_stream` of each decoder and the writer adapters (`array_stream` to `text_stream`) are one loop each, with the
# steps of the type in a record. A step of the output stream gives the next value of the last `push`, and pushes the
# next chunk of the source only when no value is left. So no chunk is read before it is needed. The decoder is given
# to `push` and set again in each branch, so it has one reference at the `push` (the writer the same way).

## What `decode_stream` needs besides the `push` and `finish` of the decoder: the errors of `push` and of `finish` as
## errors of the stream (`push_error`, `finish_error`), and a decoder with no bytes (`spent`) for the state after the
## end, so that the end state keeps no buffer. The decoder itself is called by its methods (`d.push`), not by a
## function in this record: a decoder given to a function in a record (a call the compiler cannot see through) was
## not unique in the callee, so each `push` copied the open item (measured: quadratic `stream_adapter`).
DecodeSteps(d, perr, ferr, err) : {
	push_error : perr -> err,
	finish_error : ferr -> err,
	spent : d,
}

## The methods of a decoder that `decode_stream` calls.
d.Decoder(o, perr, ferr) : where [d.push : d, List(U8) -> { values : List(o), rest : Try(d, perr) }, d.finish : d -> Try({}, ferr)]

## The state of a `decode_stream`: the decoder, the values of the last `push` that are not given yet (from `index`),
## the source, and `Reading` (the source can give more chunks), `Failed(err)` (the error after the values) or `Over`.
DecodeState(d, o, e, err) : { decoder : d, queue : List(o), index : U64, phase : [Reading, Failed(err), Over], source : Stream(Try(List(U8), e)) }

## A source with no chunks: the source of the state after the end.
no_chunks : {} -> Stream(Try(List(U8), e))
no_chunks = |_| Stream.from_iter([].iter())

## The values of `start` with the chunks of `source`: a source error `e` is `Err(Input(e))`, then the end.
decode_stream : d, Stream(Try(List(U8), e)), DecodeSteps(d, perr, ferr, [InvalidCbor(U64), Input(e), ..x]) -> Stream(Try(o, [InvalidCbor(U64), Input(e), ..x])) where [d.Decoder(o, perr, ferr)]
decode_stream = |start, source, steps|
	Stream.custom(
		{ decoder: start, queue: [], index: 0, phase: Reading, source },
		unknown_length,
		|state| decode_step!(state, steps),
	)

## One step of a `decode_stream`: the next value or error and the next state, or `NoMore` after the end. The values of
## the last `push` come first, one at a time; then `pump!` pushes chunks until it has more values.
decode_step! : DecodeState(d, o, e, [InvalidCbor(U64), Input(e), ..x]), DecodeSteps(d, perr, ferr, [InvalidCbor(U64), Input(e), ..x]) => Try((Try(o, [InvalidCbor(U64), Input(e), ..x]), DecodeState(d, o, e, [InvalidCbor(U64), Input(e), ..x])), [NoMore]) where [d.Decoder(o, perr, ferr)]
decode_step! = |state, steps| {
	{ decoder, queue, index, phase, source } = state
	if index < queue.len() {
		match queue.get(index) {
			Ok(value) => Ok((Ok(value), { decoder, queue, index: index + 1, phase, source }))
			Err(_) => Err(NoMore)
		}
	} else {
		match phase {
			Reading => {
				{ decoder: next, values, source: more, end } = pump!(decoder, source, steps)
				match (values.get(0), end) {
					(Ok(value), More) => Ok((Ok(value), { decoder: next, queue: values, index: 1, phase: Reading, source: more }))
					# The values before the error come first.
					(Ok(value), Failed(e)) => Ok((Ok(value), { decoder: steps.spent, queue: values, index: 1, phase: Failed(e), source: no_chunks({}) }))
					(_, Failed(e)) => Ok((Err(e), { decoder: steps.spent, queue: [], index: 0, phase: Over, source: no_chunks({}) }))
					_ => Err(NoMore)
				}
			}
			Failed(e) => Ok((Err(e), { decoder: steps.spent, queue: [], index: 0, phase: Over, source: no_chunks({}) }))
			Over => Err(NoMore)
		}
	}
}

## Pushes the chunks of `source` into `start` until a `push` gives values or an error, or the source ends (`finish`).
## `More`: the values, and the decoder and the source after them.
pump! : d, Stream(Try(List(U8), e)), DecodeSteps(d, perr, ferr, [InvalidCbor(U64), Input(e), ..x]) => { decoder : d, values : List(o), source : Stream(Try(List(U8), e)), end : [More, Failed([InvalidCbor(U64), Input(e), ..x]), Ended] } where [d.Decoder(o, perr, ferr)]
pump! = |start, src, steps| {
	var $d = start
	var $source = src
	var $values = []
	var $end = More
	var $going = Bool.True
	while $going {
		match $source.next!() {
			One({ item: Ok(chunk), rest: more }) => {
				$source = more
				match $d.push(chunk) {
					{ values, rest: Ok(next) } => {
						$d = next
						if !values.is_empty() {
							$values = values
							$going = Bool.False
						}
					}
					{ values, rest: Err(e) } => {
						$d = steps.spent
						$values = values
						$end = Failed((steps.push_error)(e))
						$going = Bool.False
					}
				}
			}
			One({ item: Err(e), rest: _ }) => {
				$d = steps.spent
				$end = Failed(Input(e))
				$going = Bool.False
			}
			Skip({ rest: more }) => {
				$source = more
			}
			Done => {
				$end =
					match $d.finish() {
						Ok(_) => Ended
						Err(e) => Failed((steps.finish_error)(e))
					}
				$d = steps.spent
				$going = Bool.False
			}
		}
	}
	{ decoder: $d, values: $values, source: $source, end: $end }
}

## A writer step: the bytes and the next writer.
WriteStep(err) : Try({ bytes : List(U8), writer : Cbor.StreamWriter }, err)

## The steps of a writer adapter for `encode_stream`: the step before the first value (`open`), the step of one
## value (`put`), and the step after the last value (`close`).
EncodeSteps(a, err) : {
	open : Cbor.StreamWriter -> WriteStep(err),
	put : Cbor.StreamWriter, a -> WriteStep(err),
	close : Cbor.StreamWriter -> WriteStep(err),
}

## The state of an `encode_stream`: the writer, the source, and `Start` (before `open`), `Body` or `Over`.
EncodeState(a, e) : { writer : Cbor.StreamWriter, source : Stream(Try(a, e)), phase : [Start, Body, Over] }

## A source with no values: the source of the state after the end.
no_values : {} -> Stream(Try(a, e))
no_values = |_| Stream.from_iter([].iter())

## The bytes of `start` with the values of `source`, one list for each step that gives bytes: a source error `e` is
## `Err(Input(e))`, then the end. A writer error ends the stream too.
encode_stream : Cbor.StreamWriter, Stream(Try(a, e)), EncodeSteps(a, [Input(e), ..x]) -> Stream(Try(List(U8), [Input(e), ..x]))
encode_stream = |start, source, steps|
	Stream.custom(
		{ writer: start, source, phase: Start },
		unknown_length,
		|state| encode_step!(state, steps),
	)

## One step of an `encode_stream`: the next bytes (not empty) or error and the next state, or `NoMore` after the end.
encode_step! : EncodeState(a, e), EncodeSteps(a, [Input(e), ..x]) => Try((Try(List(U8), [Input(e), ..x]), EncodeState(a, e)), [NoMore])
encode_step! = |state, steps| {
	{ writer, source, phase } = state
	var $w = writer
	var $source = source
	var $phase = phase
	var $out = Err(NoMore)
	while $phase != Over {
		step =
			if $phase == Start {
				$phase = Body
				(steps.open)($w)
			} else {
				match $source.next!() {
					One({ item: Ok(value), rest: more }) => {
						$source = more
						(steps.put)($w, value)
					}
					One({ item: Err(e), rest: _ }) => {
						$source = no_values({})
						Err(Input(e))
					}
					Skip({ rest: more }) => {
						$source = more
						Ok({ bytes: [], writer: $w })
					}
					Done => {
						$source = no_values({})
						$phase = Over
						(steps.close)($w)
					}
				}
			}
		match step {
			Ok({ bytes, writer: next }) => {
				$w = next
				if !bytes.is_empty() {
					$out = Ok((Ok(bytes), { writer: next, source: $source, phase: $phase }))
					$source = no_values({})
					$phase = Over
				}
			}
			Err(e) => {
				$out = Ok((Err(e), { writer: $w, source: no_values({}), phase: Over }))
				$phase = Over
			}
		}
	}
	$out
}

# RFC 8949 Appendix A vectors (the part in this profile)

## The U64 0 writes as 00.
expect Cbor.encode(0.U64) == [0x00]

## The U64 23 writes as 17, in the head.
expect Cbor.encode(23.U64) == [0x17]

## The U64 24 writes as 18 18, with a 1-byte argument.
expect Cbor.encode(24.U64) == [0x18, 0x18]

## The U64 1000 writes as 19 03 e8, with a 2-byte argument.
expect Cbor.encode(1000.U64) == [0x19, 0x03, 0xe8]

## The U64 1000000 writes as 1a 00 0f 42 40, with a 4-byte argument.
expect Cbor.encode(1000000.U64) == [0x1a, 0x00, 0x0f, 0x42, 0x40]

## The largest U64 writes as 1b and 8 bytes of ff.
expect Cbor.encode(18446744073709551615.U64) == [0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

## The I64 -1 writes as 20.
expect Cbor.encode(-1.I64) == [0x20]

## The I64 -1000 writes as 39 03 e7.
expect Cbor.encode(-1000.I64) == [0x39, 0x03, 0xe7]

## The F64 1.1 writes as an f64 (fb 3f f1 99 99 99 99 99 9a).
expect Cbor.encode(1.1.F64) == [0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a]

## Bool.True writes as f5.
expect Cbor.encode(Bool.True) == [0xf5]

## The text "IETF" writes as 64 and its 4 bytes.
expect Cbor.encode("IETF") == [0x64, 0x49, 0x45, 0x54, 0x46]

## The text "ü" writes as 62 c3 bc (2 bytes of UTF-8).
expect Cbor.encode("\u(fc)") == [0x62, 0xc3, 0xbc]

## The list [1, 2, 3] writes as 83 01 02 03.
expect Cbor.encode([1.U64, 2, 3]) == [0x83, 0x01, 0x02, 0x03]

## The record { a: 1, b: [2, 3] } writes as a map of 2 with the text keys "a" and "b".
expect Cbor.encode({ a: 1.U64, b: [2.U64, 3] }) == [0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03]

## A U64 with an 8-byte head (1b 00 00 00 e8 d4 a5 10 00) reads as 1000000000000.
expect {
	r : Try(U64, _)
	r = Cbor.parse([0x1b, 0x00, 0x00, 0x00, 0xe8, 0xd4, 0xa5, 0x10, 0x00])
	r == Ok(1000000000000)
}

## An I64 reads 38 63 as -100.
expect {
	r : Try(I64, _)
	r = Cbor.parse([0x38, 0x63])
	r == Ok(-100)
}

## Half floats: 1.5, 65504.0, 5.960464477539063e-8, -4.0
expect {
	r : Try(List(F64), _)
	r = Cbor.parse([0x84, 0xf9, 0x3e, 0x00, 0xf9, 0x7b, 0xff, 0xf9, 0x00, 0x01, 0xf9, 0xc4, 0x00])
	r == Ok([1.5, 65504.0, 0.00000005960464477539063, -4.0])
}

## An F64 reads the f32 fa 47 c3 50 00 as 100000.0.
expect {
	r : Try(F64, _)
	r = Cbor.parse([0xfa, 0x47, 0xc3, 0x50, 0x00])
	r == Ok(100000.0)
}

## A byte string as a List(U8) (h'01020304')
expect {
	r : Try(List(U8), _)
	r = Cbor.parse([0x44, 0x01, 0x02, 0x03, 0x04])
	r == Ok([1, 2, 3, 4])
}

## Indefinite lengths are not in the profile: [_ 1, 2]
expect {
	r : Try(List(U64), _)
	r = Cbor.parse([0x9f, 0x01, 0x02, 0xff])
	r == Err(InvalidCbor(0))
}

# Records, tags, optional fields

Pkg : { name : Str, version : Str, size : U64, tags : List(Str), yanked : Bool }

## A Pkg record (text, a number, a list of text, a bool) round trips.
expect {
	p : Pkg
	p = { name: "roc-lang/http", version: "2.0.0", size: 51385, tags: ["http", "web"], yanked: Bool.False }
	parsed : Try(Pkg, _)
	parsed = Cbor.parse(Cbor.encode(p))
	parsed == Ok(p)
}

## An unknown field is skipped, and a missing optional field is absent.
expect {
	bytes = Cbor.encode({ extra: { deep: [1.U64, 2] }, name: "x" })
	r : Try({ name : Str, nick : Try(Str, [Missing]) }, _)
	r = Cbor.parse(bytes)
	r == Ok({ name: "x", nick: Err(Missing) })
}

## A record with no "age" field for a required age is the error MissingRequiredField("age").
expect {
	r : Try({ name : Str, age : U64 }, _)
	r = Cbor.parse(Cbor.encode({ name: "x" }))
	r == Err(MissingRequiredField("age"))
}

## Only the fields that are there count: the head says 1, not 2.
expect {
	v : { count : U64, label ?: Str }
	v = { count: 5 }
	Cbor.encode(v) == [0xa1, 0x65, 0x63, 0x6f, 0x75, 0x6e, 0x74, 0x05]
}

Shape : [Circle(F64), Rect(F64, F64), Empty]

## A list of tags, with a payload of 1 and 2 values and with no payload, round trips.
expect {
	shapes : List(Shape)
	shapes = [Circle(1.5), Rect(2.0, 3.0), Empty]
	parsed : Try(List(Shape), _)
	parsed = Cbor.parse(Cbor.encode(shapes))
	parsed == Ok(shapes)
}

## The same shapes as Json: {"Circle": 1.5} and "Empty"
expect Cbor.encode(Empty) == [0x65, 0x45, 0x6d, 0x70, 0x74, 0x79]

## With fields: Camel, the key "userId" reads as the field user_id: 7.
expect {
	r : Try({ user_id : U64 }, _)
	r = Cbor.parse_with([0xa1, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x07], { fields: Camel })
	r == Ok({ user_id: 7 })
}

## A long list: the head has room for the real count.
expect {
	xs : List(U64)
	xs = (0.U64).until(300).collect()
	parsed : Try(List(U64), _)
	parsed = Cbor.parse(Cbor.encode(xs))
	parsed == Ok(xs)
}

## A List(U8) writes a byte string (h'010203'). Cbor.U8Array writes an array of numbers.
expect Cbor.encode([1.U8, 2, 3]) == [0x43, 0x01, 0x02, 0x03]

## A Cbor.U8Array of [1, 2, 3] writes as an array: 83 01 02 03.
expect Cbor.encode(Cbor.U8Array.([1, 2, 3])) == [0x83, 0x01, 0x02, 0x03]

## A List(U8) reads a byte string, also as a record field, and round trips.
expect {
	v : { id : U64, data : List(U8) }
	v = { id: 7, data: [0, 255, 16] }
	parsed : Try({ id : U64, data : List(U8) }, _)
	parsed = Cbor.parse(Cbor.encode(v))
	parsed == Ok(v)
}

## Cbor.U8Array reads an array of integers 0 to 255 (a JS peer that sends bytes as a plain array).
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x83, 0x01, 0x02, 0x03])
	r == Ok(Cbor.U8Array.([1, 2, 3]))
}

## The array form also works as a record field, when empty, and with `FloatToInt` a float that has no fraction (a JS Number).
expect {
	r : Try({ id : U64, data : Cbor.U8Array }, _)
	r = Cbor.parse([0xa2, 0x62, 0x69, 0x64, 0x07, 0x64, 0x64, 0x61, 0x74, 0x61, 0x82, 0x00, 0x18, 0xff])
	r == Ok({ id: 7, data: Cbor.U8Array.([0, 255]) })
}

## An empty array (80) reads as an empty Cbor.U8Array.
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x80])
	r == Ok(Cbor.U8Array.([]))
}

## With `FloatToInt`, the f64 3.0 in an array reads as the Cbor.U8Array [3].
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse_with([0x81, 0xfb, 0x40, 0x08, 0, 0, 0, 0, 0, 0], { allow: [FloatToInt] })
	r == Ok(Cbor.U8Array.([3]))
}

## With no option, the f64 3.0 in an array is an error at the item (byte 1).
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x81, 0xfb, 0x40, 0x08, 0, 0, 0, 0, 0, 0])
	r == Err(InvalidCbor(1))
}

## An item of the array that is not 0 to 255 is an error at the item: 256, -1, 1.5, text, and the count of a long array.
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x82, 0x01, 0x19, 0x01, 0x00])
	r == Err(InvalidCbor(2))
}

## The item -1 is an error at the item (byte 2).
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x82, 0x01, 0x20])
	r == Err(InvalidCbor(2))
}

## The item 1.5 (an f64) is an error at the item (byte 1).
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x81, 0xfb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0])
	r == Err(InvalidCbor(1))
}

## The text item "1" is an error at the item (byte 1).
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x81, 0x61, 0x31])
	r == Err(InvalidCbor(1))
}

## Text is not an item, also with `IntFromText`.
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse_with([0x81, 0x61, 0x31], { allow: [IntFromText] })
	r == Err(InvalidCbor(1))
}

## An array count of 2^36, more than the input, is an error at the array (byte 0).
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x9b, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## Another type (text, a map, an integer) is still an error at the start.
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x61, 0x31])
	r == Err(InvalidCbor(0))
}

## The integer 1 is not an array: an error at byte 0.
expect {
	r : Try(Cbor.U8Array, _)
	r = Cbor.parse([0x01])
	r == Err(InvalidCbor(0))
}

## List(U8) reads a byte string, also as a record field. A non-empty array needs `BytesFromArray`: the error is at the array.
expect {
	r : Try({ id : U64, data : List(U8) }, _)
	r = Cbor.parse([0xa2, 0x62, 0x69, 0x64, 0x07, 0x64, 0x64, 0x61, 0x74, 0x61, 0x43, 0x01, 0x02, 0x03])
	r == Ok({ id: 7, data: [1, 2, 3] })
}

## With `BytesFromArray`, the array [1, 2] reads as the List(U8) [1, 2].
expect {
	r : Try(List(U8), _)
	r = Cbor.parse_with([0x82, 0x01, 0x02], { allow: [BytesFromArray] })
	r == Ok([1, 2])
}

## With no option, the array [1, 2] read as a List(U8) is an error at the array (byte 0).
expect {
	r : Try(List(U8), _)
	r = Cbor.parse([0x82, 0x01, 0x02])
	r == Err(InvalidCbor(0))
}

# Dec

## A Dec with no fraction writes as an integer: an untyped literal list works as a SQL parameter list.
expect Cbor.encode([1]) == [0x81, 0x01]

## The Dec 0 writes as the integer 00.
expect Cbor.encode(0.Dec) == [0x00]

## The Dec 1000 writes as the integer 19 03 e8.
expect Cbor.encode(1000.Dec) == [0x19, 0x03, 0xe8]

## The Dec -1 writes as the integer 20.
expect Cbor.encode(-1.Dec) == [0x20]

## The Dec -1000 writes as the integer 39 03 e7.
expect Cbor.encode(-1000.Dec) == [0x39, 0x03, 0xe7]

## The Dec 2^64 - 1 writes as the integer 1b and 8 bytes of ff.
expect Cbor.encode(18446744073709551615.Dec) == [0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

## The Dec -2^64 writes as the integer 3b and 8 bytes of ff.
expect Cbor.encode(-18446744073709551616.Dec) == [0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

## A Dec with a fraction writes as a decimal fraction, tag 4 and [exponent, mantissa]: 3.14159 is [-5, 314159].
expect Cbor.encode(3.14159.Dec) == [0xc4, 0x82, 0x24, 0x1a, 0x00, 0x04, 0xcb, 0x2f]

## The Dec 0.1 writes as the decimal fraction [-1, 1].
expect Cbor.encode(0.1.Dec) == [0xc4, 0x82, 0x20, 0x01]

## The Dec 1.1 writes as the decimal fraction [-1, 11].
expect Cbor.encode(1.1.Dec) == [0xc4, 0x82, 0x20, 0x0b]

## The Dec -0.5 writes as the decimal fraction [-1, -5].
expect Cbor.encode(-0.5.Dec) == [0xc4, 0x82, 0x20, 0x24]

## The smallest unit of a Dec (10^-18) writes as the decimal fraction [-18, 1].
expect Cbor.encode(0.000000000000000001.Dec) == [0xc4, 0x82, 0x31, 0x01]

## A whole Dec outside the integer range of CBOR is a decimal fraction too, with a positive exponent: 10^20 is [20, 1].
expect Cbor.encode(100000000000000000000.Dec) == [0xc4, 0x82, 0x14, 0x01]

## A mantissa outside the 64 bit integers is a bignum (tag 2, tag 3: -1 - n) with a byte string.
expect Cbor.encode(18446744073709551616.Dec) == [0xc4, 0x82, 0x00, 0xc2, 0x49, 0x01, 0, 0, 0, 0, 0, 0, 0, 0]

## Dec.highest writes as [-18, a tag 2 bignum of 16 bytes 7f ff .. ff].
expect Cbor.encode(Dec.highest) == [0xc4, 0x82, 0x31, 0xc2, 0x50, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

## Dec.lowest writes as [-18, a tag 3 bignum of 16 bytes 7f ff .. ff].
expect Cbor.encode(Dec.lowest) == [0xc4, 0x82, 0x31, 0xc3, 0x50, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]

## Dec reads an integer, a decimal fraction or a float.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0x18, 0x2a])
	r == Ok(42)
}

## A Dec reads the integer -2^64 (3b and 8 bytes of ff).
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	r == Ok(-18446744073709551616)
}

## A Dec reads the f64 1.5 as 1.5.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xfb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0])
	r == Ok(1.5)
}

## A Dec reads the f16 1.5 (f9 3e 00) as 1.5.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xf9, 0x3e, 0x00])
	r == Ok(1.5)
}

## A Dec round trips exactly: whole, with a fraction, the smallest unit, the largest and smallest Dec, negative.
expect {
	xs : List(Dec)
	xs = [0, 1, -1, 1000000, 2.5, -0.25, 0.1, 1234.5, 3.14159, -3.14159, 0.00013, 0.000000000000000001, -0.000000000000000001, 18446744073709551616, -18446744073709551617, 100000000000000000000, -100000000000000000000, 170141183460469231731, Dec.highest, Dec.lowest]
	r : Try(List(Dec), _)
	r = Cbor.parse(Cbor.encode(xs))
	r == Ok(xs)
}

## Dec reads a decimal fraction: a positive exponent, a mantissa with spare zeros. A bignum mantissa with leading zero
## bytes, or that fits 64 bits, needs `PaddedNumbers` (RFC 8949 4.2.2 preferred serialization).
expect {
	r : Try(List(Dec), _)
	r = Cbor.parse_with([0x83, 0xc4, 0x82, 0x02, 0x03, 0xc4, 0x82, 0x31, 0x0a, 0xc4, 0x82, 0x31, 0xc2, 0x42, 0x00, 0x01], { allow: [PaddedNumbers] })
	r == Ok([300, 0.000000000000000010, 0.000000000000000001])
}

## With no option, a bignum mantissa with a leading zero byte is an error at its tag (byte 12).
expect {
	r : Try(List(Dec), _)
	r = Cbor.parse([0x83, 0xc4, 0x82, 0x02, 0x03, 0xc4, 0x82, 0x31, 0x0a, 0xc4, 0x82, 0x31, 0xc2, 0x42, 0x00, 0x01])
	r == Err(InvalidCbor(12))
}

## A decimal fraction with more than 18 fraction digits, or out of the range of a Dec, is an error at the tag.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc4, 0x82, 0x33, 0x01])
	r == Err(InvalidCbor(0))
}

## The decimal fraction [21, 1] (10^21) is out of the range of a Dec: an error at the tag (byte 0).
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc4, 0x82, 0x15, 0x01])
	r == Err(InvalidCbor(0))
}

## A bignum mantissa with leading zero bytes (17 bytes, the value 1) reads with `PaddedNumbers`. A huge exponent is an error, with no long loop.
expect {
	r : Try(Dec, _)
	r = Cbor.parse_with([0xc4, 0x82, 0x31, 0xc2, 0x51, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01], { allow: [PaddedNumbers] })
	r == Ok(0.000000000000000001)
}

## A decimal fraction with the exponent 2^63 - 1 is an error at its tag (byte 1).
expect {
	r : Try(List(Dec), _)
	r = Cbor.parse([0x82, 0xc4, 0x82, 0x1b, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0xc4, 0x82, 0x3b, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01])
	r == Err(InvalidCbor(1))
}

## The mantissa 10 with the exponent -19 is the whole attos 1.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc4, 0x82, 0x32, 0x0a])
	r == Ok(0.000000000000000001)
}

## Another tag, an array of 3, a text mantissa, a bignum of 17 bytes, and cut input are errors.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc5, 0x82, 0x20, 0x01])
	r == Err(InvalidCbor(0))
}

## A tag 4 with an array of 3 is an error at the tag (byte 0).
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc4, 0x83, 0x20, 0x01, 0x01])
	r == Err(InvalidCbor(0))
}

## A decimal fraction with a text mantissa is an error at the mantissa (byte 3).
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc4, 0x82, 0x20, 0x61, 0x31])
	r == Err(InvalidCbor(3))
}

## A bignum mantissa of 17 bytes with no leading zero is an error at the bignum tag (byte 3).
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc4, 0x82, 0x31, 0xc2, 0x51].concat(List.repeat(1, 17)))
	r == Err(InvalidCbor(3))
}

## An array of 2 with 1 byte left: the error is at the array.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0xc4, 0x82, 0x24])
	r == Err(InvalidCbor(1))
}

## A decimal fraction in a record field, between other fields.
expect {
	v : { a : U64, price : Dec, b : Str }
	v = { a: 1, price: 19.99, b: "x" }
	r : Try({ a : U64, price : Dec, b : Str }, _)
	r = Cbor.parse(Cbor.encode(v))
	r == Ok(v)
}

## A small fraction is rounded to the nearest attos, not cut (an f64 of 0.00013 times 10^18 is a little under 130000000000000).
expect {
	r : Try(List(Dec), _)
	r = Cbor.parse(Cbor.encode([0.00013.F64, 0.00104, 0.0021, -0.00026]))
	r == Ok([0.00013, 0.00104, 0.0021, -0.00026])
}

## NaN, an infinity and a float outside the range of a Dec are errors.
expect {
	r : Try(Dec, _)
	r = Cbor.parse(Cbor.encode(F64.nan))
	r == Err(InvalidCbor(0))
}

## An f64 infinity read as a Dec is an error at byte 0.
expect {
	r : Try(Dec, _)
	r = Cbor.parse(Cbor.encode(F64.infinity))
	r == Err(InvalidCbor(0))
}

## The f64 1.0e30, outside the range of a Dec, is an error at byte 0.
expect {
	r : Try(Dec, _)
	r = Cbor.parse(Cbor.encode(1.0e30.F64))
	r == Err(InvalidCbor(0))
}

## Text, a map and a bool are errors.
expect {
	r : Try(Dec, _)
	r = Cbor.parse([0x61, 0x31])
	r == Err(InvalidCbor(0))
}

## A head of width 24: 24 bytes or more.
expect {
	b : List(U8)
	b = (0.U8).until(30).collect()
	Cbor.encode(b).take_first(2) == [0x58, 30]
}

# Malformed input: an error, never a crash and never a large allocation

## A text length near 2^64: the sum with the position overflowed.
expect {
	r : Try(Str, _)
	r = Cbor.parse([0x7b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	r == Err(InvalidCbor(0))
}

## A byte string length near 2^64.
expect {
	r : Try(List(U8), _)
	r = Cbor.parse([0x5b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	r == Err(InvalidCbor(0))
}

## An array count larger than the input: the derived parser allocated the count first.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse([0x9b, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## A byte string length larger than the input, read as a List(U8).
expect {
	r : Try(List(U8), _)
	r = Cbor.parse([0x5b, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## A map count larger than the input, read as a Dict.
expect {
	r : Try(Dict(Str, U64), _)
	r = Cbor.parse([0xbb, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## An unknown field with a map count near 2^64: the item count overflowed.
expect {
	r : Try({ n : U64 }, _)
	r = Cbor.parse([0xa1, 0x61, 0x78, 0xbb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	r == Err(InvalidCbor(3))
}

## An unknown field with a text length near 2^64.
expect {
	r : Try({ n : U64 }, _)
	r = Cbor.parse([0xa1, 0x61, 0x78, 0x7b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	r == Err(InvalidCbor(3))
}

## An unknown field with 511 nested arrays (512 with the map) reads. With 100,000, the error is at the 513th head.
expect {
	r : Try({ n : Try(U64, [Missing]) }, _)
	r = Cbor.parse([0xa1, 0x61, 0x78].concat(List.repeat(0x81, 511)).append(0x00))
	r == Ok({ n: Err(Missing) })
}

## An unknown field with 100,000 nested arrays is an error at byte 514, the 513th head.
expect {
	r : Try({ n : Try(U64, [Missing]) }, _)
	r = Cbor.parse([0xa1, 0x61, 0x78].concat(List.repeat(0x81, 100000)).append(0x00))
	r == Err(InvalidCbor(514))
}

## A byte string reads as a List(U8) only. Its bytes are not the items of another type.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse([0x42, 0x01, 0x02])
	r == Err(InvalidCbor(1))
}

## A byte string h'f5' read as a List(Bool) is an error at byte 1.
expect {
	r : Try(List(Bool), _)
	r = Cbor.parse([0x41, 0xf5])
	r == Err(InvalidCbor(1))
}

## A byte string h'f6' read as a List(Try(U64, [Null])) is an error at byte 1.
expect {
	r : Try(List(Try(U64, [Null])), _)
	r = Cbor.parse([0x41, 0xf6])
	r == Err(InvalidCbor(1))
}

## An unknown field with more items than bytes: the error is at the innermost open array (one truncation rule).
expect {
	r : Try({ n : U64 }, _)
	r = Cbor.parse([0xa1, 0x61, 0x78, 0x82, 0x81, 0x00])
	r == Err(InvalidCbor(3))
}

## An F32 reads an f64 that is outside the F32 range as an error, not as an infinity.
expect {
	r : Try(F32, _)
	r = Cbor.parse(Cbor.encode(1.0e300.F64))
	r == Err(InvalidCbor(0))
}

## The largest F32, an infinity and NaN still read as an F32.
expect {
	r : Try(List(F32), _)
	r = Cbor.parse(Cbor.encode([F32.highest.to_f64(), -(F32.highest.to_f64()), F64.infinity]))
	r == Ok([F32.highest, -F32.highest, F32.infinity])
}

## An f64 NaN reads as an F32 NaN.
expect {
	r : Try(F32, _)
	r = Cbor.parse(Cbor.encode(F64.nan))
	match r {
		Ok(f) => f.is_nan()
		Err(_) => Bool.False
	}
}

# Integers from floats and from text, and path_at

## [{"name": "a", "id": f64 2^53}]. The value of "id" starts at 12.
float_big : List(U8)
float_big = [0x81, 0xa2, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61, 0x62, 0x69, 0x64, 0xfb, 0x43, 0x40, 0, 0, 0, 0, 0, 0]

## The CBOR text of `s` (255 bytes or less).
cbor_text : Str -> List(U8)
cbor_text = |s| {
	n = s.count_utf8_bytes().to_u8_wrap()
	head_bytes = if (n < 24) [0x60 + n] else [0x78, n]
	head_bytes.concat(s.to_utf8())
}

ints : Cbor.Options
ints = { allow: [IntFromText] }

floats : Cbor.Options
floats = { allow: [FloatToInt] }

## An f64 of 2^53 or more is an error for an integer type: it can be the rounded value of many integers.
expect {
	r : Try(List({ name : Str, id : I64 }), _)
	r = Cbor.parse_with(float_big, floats)
	r == Err(InvalidCbor(12))
}

## With `FloatToInt`, an f64 of size 2^53 - 1 or less reads as an integer. With no option, it is an error.
expect {
	r : Try(I64, _)
	r = Cbor.parse_with([0xfb, 0x43, 0x3f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], floats)
	r == Ok(9007199254740991)
}

## With `FloatToInt`, the f64 -(2^53 - 1) reads as the I64 -9007199254740991.
expect {
	r : Try(I64, _)
	r = Cbor.parse_with([0xfb, 0xc3, 0x3f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], floats)
	r == Ok(-9007199254740991)
}

## With no option, the f64 -(2^53 - 1) read as an I64 is an error at byte 0.
expect {
	r : Try(I64, _)
	r = Cbor.parse([0xfb, 0xc3, 0x3f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	r == Err(InvalidCbor(0))
}

## An f64 of -2^53 is an error for an integer type.
expect {
	r : Try(I64, _)
	r = Cbor.parse_with([0xfb, 0xc3, 0x40, 0, 0, 0, 0, 0, 0], floats)
	r == Err(InvalidCbor(0))
}

## An f64 of 2^53 still reads as an F64.
expect {
	r : Try(F64, _)
	r = Cbor.parse(float_big.drop_first(12))
	r == Ok(9007199254740992.0)
}

## int_from_text: canonical decimal text in the range of the type reads as an integer.
expect {
	r : Try(I64, _)
	r = Cbor.parse_with(cbor_text("-9223372036854775808"), ints)
	r == Ok(-9223372036854775808)
}

## With `IntFromText`, the text "9223372036854775807" reads as the largest I64.
expect {
	r : Try(I64, _)
	r = Cbor.parse_with(cbor_text("9223372036854775807"), ints)
	r == Ok(9223372036854775807)
}

## With `IntFromText`, the text "0" reads as the I64 0.
expect {
	r : Try(I64, _)
	r = Cbor.parse_with(cbor_text("0"), ints)
	r == Ok(0)
}

## With `IntFromText`, the text "18446744073709551615" reads as the largest U64.
expect {
	r : Try(U64, _)
	r = Cbor.parse_with(cbor_text("18446744073709551615"), ints)
	r == Ok(18446744073709551615)
}

## int_from_text: a value out of the range of the type is an error.
expect {
	r : Try(I64, _)
	r = Cbor.parse_with(cbor_text("9223372036854775808"), ints)
	r == Err(InvalidCbor(0))
}

## With `IntFromText`, the text "256" read as a U8 is an error at byte 0.
expect {
	r : Try(U8, _)
	r = Cbor.parse_with(cbor_text("256"), ints)
	r == Err(InvalidCbor(0))
}

## With `IntFromText`, the text "-1" read as a U64 is an error at byte 0.
expect {
	r : Try(U64, _)
	r = Cbor.parse_with(cbor_text("-1"), ints)
	r == Err(InvalidCbor(0))
}

## int_from_text: text that is not canonical is an error.
expect
	["-0", "01", "+1", " 1", "1 ", "1.0", "1e3", "", "-", "0x10", "123456789012345678901"].all(
		|s| {
			r : Try(I64, _)
			r = Cbor.parse_with(cbor_text(s), ints)
			r == Err(InvalidCbor(0))
		},
	)

## Without int_from_text, text is an error for an integer type.
expect {
	r : Try(I64, _)
	r = Cbor.parse(cbor_text("12"))
	r == Err(InvalidCbor(0))
}

## int_from_text does not change a Str.
expect {
	r : Try(Str, _)
	r = Cbor.parse_with(cbor_text("12"), ints)
	r == Ok("12")
}

## int_from_text in a record field. A bad value is an error at its position.
expect {
	r : Try(List({ name : Str, id : I64 }), _)
	r = Cbor.parse_with([0x81, 0xa2, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61, 0x62, 0x69, 0x64].concat(cbor_text("123")), ints)
	r == Ok([{ name: "a", id: 123 }])
}

## With `IntFromText`, the text "1.5" in the field "id" is an error at its position (byte 12).
expect {
	r : Try(List({ name : Str, id : I64 }), _)
	r = Cbor.parse_with([0x81, 0xa2, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61, 0x62, 0x69, 0x64].concat(cbor_text("1.5")), ints)
	r == Err(InvalidCbor(12))
}

## int_from_text: 45 digits is an error, not an overflow of the I128 of the decoder.
expect {
	r : Try(U64, _)
	r = Cbor.parse_with(cbor_text(Str.repeat("9", 45)), ints)
	r == Err(InvalidCbor(0))
}

## fields: Camel reads the camelCase key only.
expect {
	bytes = [0xa1, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x07]
	a : Try({ user_id : U64 }, _)
	a = Cbor.parse_with(bytes, { fields: Camel })
	b : Try({ user_id : U64 }, _)
	b = Cbor.parse(bytes)
	a == Ok({ user_id: 7 }) and b == Err(MissingRequiredField("user_id"))
}

## path_at names the item of an error position.
expect Cbor.path_at(float_big, 12) == Ok([Index(0), Key("id")])

## path_at of float_big at 7 (the value of "name") is [Index(0), Key("name")].
expect Cbor.path_at(float_big, 7) == Ok([Index(0), Key("name")])

## path_at of float_big at 1 (the map) is [Index(0)].
expect Cbor.path_at(float_big, 1) == Ok([Index(0)])

## path_at of float_big at 0 (the root item) is the empty path.
expect Cbor.path_at(float_big, 0) == Ok([])

## A position in the middle of an item, at a map key, or past the end: not found.
expect Cbor.path_at(float_big, 13) == Err(NotFound)

## path_at of float_big at 2 (the key "name") is NotFound.
expect Cbor.path_at(float_big, 2) == Err(NotFound)

## path_at of float_big at 99 (past the end) is NotFound.
expect Cbor.path_at(float_big, 99) == Err(NotFound)

## The second item of an array, after a nested map, and in a tagged value.
expect Cbor.path_at([0x82, 0xa1, 0x61, 0x61, 0x81, 0x01, 0x02], 6) == Ok([Index(1)])

## path_at at 5 (the item 1 in [{"a": [1]}, 2]) is [Index(0), Key("a"), Index(0)].
expect Cbor.path_at([0x82, 0xa1, 0x61, 0x61, 0x81, 0x01, 0x02], 5) == Ok([Index(0), Key("a"), Index(0)])

## path_at at 3 (the second item of the array in tag 1) is [Index(1)].
expect Cbor.path_at([0xc1, 0x82, 0x01, 0x02], 3) == Ok([Index(1)])

## 512 nested arrays: a loop, not a recursion. path_at has no depth limit, so it finds the item of any depth error.
expect Cbor.path_at(List.repeat(0x81, 512).append(0x00), 512) == Ok(List.repeat(Index(0), 512))

## path_at of the item in 100,000 nested arrays is 100,000 of Index(0).
expect Cbor.path_at(List.repeat(0x81, 100000).append(0x00), 100000) == Ok(List.repeat(Index(0), 100000))

## The rule `shortest_heads` (the default of a parse): a head with more bytes than its argument needs is an error.
## A float (major type 7) is not a head of this kind.
strict : Rules
strict = { max_depth: 512, max_items: U64.highest, shortest_heads: Bool.True, indefinite: Bool.False, keys: Reject, order: Any }

## head_at with the strict rules: 18 17 (a padded 23) is an error at byte 0.
expect head_at([0x18, 0x17], 0, strict) == Err(InvalidCbor(0))

## head_at with the strict rules: 18 18 reads the argument 24.
expect head_at([0x18, 0x18], 0, strict).map_ok(|h| h.arg) == Ok(24)

## head_at with the strict rules: 39 00 ff (a padded 255) is an error at byte 0.
expect head_at([0x39, 0x00, 0xff], 0, strict) == Err(InvalidCbor(0))

## head_at with the strict rules: 39 01 00 reads the argument 256.
expect head_at([0x39, 0x01, 0x00], 0, strict).map_ok(|h| h.arg) == Ok(256)

## head_at with the strict rules: 5a 00 00 ff ff (a padded byte string length) is an error at byte 0.
expect head_at([0x5a, 0x00, 0x00, 0xff, 0xff], 0, strict) == Err(InvalidCbor(0))

## head_at with the strict rules: 5a 00 01 00 00 reads the argument 65536.
expect head_at([0x5a, 0x00, 0x01, 0x00, 0x00], 0, strict).map_ok(|h| h.arg) == Ok(65536)

## head_at with the strict rules: 9b 00 00 00 00 ff ff ff ff (a padded array count) is an error at byte 0.
expect head_at([0x9b, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff], 0, strict) == Err(InvalidCbor(0))

## head_at with the strict rules: 9b 00 00 00 01 00 00 00 00 reads the argument 2^32.
expect head_at([0x9b, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00], 0, strict).map_ok(|h| h.arg) == Ok(4294967296)

## head_at with the strict rules: the f16 f9 00 00 is not a padded head, so it reads.
expect head_at([0xf9, 0x00, 0x00], 0, strict).is_ok()

## walk with the strict rules: 81 18 01 (a padded 1 in an array) is an error at byte 1.
expect walk(reader([0x81, 0x18, 0x01]), strict, Bool.False).map_ok(|s| s.pos) == Err(InvalidCbor(1))

## skip does not check the shortest heads: it skips 81 18 01 to the end (byte 3).
expect skip(reader([0x81, 0x18, 0x01])).map_ok(|s| s.pos) == Ok(3)

## The depth limit: 512 nested arrays walk, 513 is an error at the 513th head.
expect walk(reader(List.repeat(0x81, 512).append(0x00)), strict, Bool.False).is_ok()

## walk with the strict rules: 513 nested arrays are an error at byte 512, the 513th head.
expect walk(reader(List.repeat(0x81, 513).append(0x00)), strict, Bool.False).map_ok(|s| s.pos) == Err(InvalidCbor(512))

## A walk with `keep` gives the start and end of each map. A later walk takes the end of a map from `map_ends`.
expect walk(reader([0x81, 0xa1, 0x01, 0xa0]), loose, Bool.True).map_ok(|s| memo_of(s).map_ends) == Ok([1, 4])

## skip takes the end of a map from `map_ends`: with the map at 1 ending at 2, the skip ends at byte 2.
expect skip(with_memo(reader([0x81, 0xa1, 0x01, 0xa0]), { ..no_memo, map_ends: [1, 2] })).map_ok(|s| s.pos) == Ok(2)

## `walk` takes the fast path (`fast_walk`) when it can: it gives the same end, the same keys to skip, and the same
## error position as `walk_from` alone. Each case where `fast_walk` gives `Slow` is here: an error of a head, of a
## string, of UTF-8 and of a simple value, a cut item, a count larger than the bytes, an indefinite length, the
## depth and item limits, a key that is a map, and a duplicate key with each rule.
general_walk : List(U8), Rules -> Try((U64, List(U64)), [InvalidCbor(U64)])
general_walk = |bytes, rules|
	match walk_from(bytes, walk_start(0, [], Bool.False), rules)? {
		Whole(ws) => Ok((ws.pos, ws.skips.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same)))
		Cut(ws) => Err(InvalidCbor(cut_pos(bytes, ws)))
	}

same_as_general : List(U8), Rules -> Bool
same_as_general = |bytes, rules|
	walk(reader(bytes), rules, Bool.False).map_ok(|s| (s.pos, memo_of(s).skips)) == general_walk(bytes, rules)

fast_walk_inputs : List(List(U8))
fast_walk_inputs = [
	[0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x01, 0xf9, 0x3c, 0x00],
	[0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02],
	[0xa3, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02, 0x61, 0x61, 0x03],
	[0xa2, 0x01, 0x02, 0x01, 0x03],
	[0xa1, 0xa0, 0x01],
	[0xa1, 0x81, 0x01, 0x02],
	[0x81, 0x18, 0x01],
	[0x82, 0x01],
	[0x9a, 0xff, 0xff, 0xff, 0xff, 0x00],
	[0x62, 0x61],
	[0x62, 0xc3, 0x28],
	[0x63, 0xe6, 0xbc, 0xa2],
	[0xf8, 0x1f],
	[0xf8, 0x20],
	[0x1c],
	[0xff],
	[0x9f, 0x01, 0xff],
	[0x82, 0x5f, 0x41, 0x01, 0xff, 0x02],
	[0xdb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01],
	[0xc1, 0xc2, 0x40],
	[0xfb, 0x3f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x19, 0x00, 0x01],
	[],
	List.repeat(0x81, 512).append(0x00),
	List.repeat(0x81, 513).append(0x00),
	[0x83, 0xa1, 0x61, 0x6b, 0x01, 0xa2, 0x61, 0x6b, 0x01, 0x61, 0x6b, 0x02, 0x00],
]

## The strict rules of a parse: the fast walk agrees with walk_from on each input.
expect fast_walk_inputs.all(|b| same_as_general(b, strict))

## The rules of read_value (no shortest heads, no key rule): the fast walk agrees with walk_from.
expect fast_walk_inputs.all(|b| same_as_general(b, loose))

## The rules of skip (indefinite lengths allowed): the fast walk agrees with walk_from.
expect fast_walk_inputs.all(|b| same_as_general(b, any_length))

## duplicate_keys First: the same keys to skip as walk_from.
expect fast_walk_inputs.all(|b| same_as_general(b, { ..strict, keys: First }))

## duplicate_keys Last: the same keys to skip as walk_from.
expect fast_walk_inputs.all(|b| same_as_general(b, { ..strict, keys: Last }))

## max_items 3: the error at the same item as walk_from.
expect fast_walk_inputs.all(|b| same_as_general(b, { ..strict, max_items: 3 }))

## max_depth 1: the error at the same item as walk_from.
expect fast_walk_inputs.all(|b| same_as_general(b, { ..strict, max_depth: 1 }))

## PaddedNumbers (no shortest heads): the fast walk agrees with walk_from.
expect fast_walk_inputs.all(|b| same_as_general(b, { ..strict, shortest_heads: Bool.False }))

## Each cut of a record list: the error at the same position.
expect {
	bytes = [0x82, 0xa2, 0x62, 0x69, 0x64, 0x01, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x62, 0x78, 0x79, 0xa0]
	cuts : List(U64)
	cuts = (0.U64).until(bytes.len() + 1).collect()
	cuts.all(|n| same_as_general(bytes.take_first(n), strict))
}

## valid_utf8 agrees with Str.from_utf8: each sequence of 1 and 2 bytes, and for 3 and 4 bytes each first and second
## byte with the third and fourth bytes from a set of edges.
same_utf8 : List(U8) -> Bool
same_utf8 = |b| valid_utf8(b, 0, b.len()) == Str.from_utf8(b).is_ok()

all_bytes : List(U8)
all_bytes = {
	ns : List(U64)
	ns = (0.U64).until(256).collect()
	ns.map(|n| n.to_u8_wrap())
}

utf8_edges : List(U8)
utf8_edges = [0x00, 0x7f, 0x80, 0x8f, 0x90, 0x9f, 0xa0, 0xbf, 0xc0, 0xff]

## valid_utf8 agrees with Str.from_utf8 on each 1-byte sequence.
expect all_bytes.all(|a| same_utf8([a]))

## valid_utf8 agrees with Str.from_utf8 on each 2-byte sequence.
expect all_bytes.all(|a| all_bytes.all(|b| same_utf8([a, b])))

## valid_utf8 agrees with Str.from_utf8 on 3 bytes: each first and second byte, the third from the edges.
expect all_bytes.all(|a| all_bytes.all(|b| utf8_edges.all(|c| same_utf8([a, b, c]))))

## valid_utf8 agrees with Str.from_utf8 on 4 bytes: the first bytes f0 to f5, each second byte, the rest from the edges.
expect [0xf0, 0xf1, 0xf3, 0xf4, 0xf5].all(|a| all_bytes.all(|b| utf8_edges.all(|c| utf8_edges.all(|d| same_utf8([a, b, c, d])))))

## valid_utf8 agrees with Str.from_utf8 on mixed text, a cut code point at the end, and no bytes.
expect same_utf8("é漢🎉 user-é漢🎉-ü1".to_utf8()) and same_utf8([0x61, 0xe6, 0xbc]) and same_utf8([])

## The fast paths of `parse_str`, of a record key and of `parse_u64` (`short_text`, `plain_at`): each head width, and
## the cases they give to the general reader, with the same value or error position.
## A text with a 2-byte head (78) reads on the fast path.
expect {
	r : Try(Str, _)
	r = Cbor.parse([0x78, 0x18].concat(List.repeat('a', 24)))
	r == Ok(Str.repeat("a", 24))
}

## A cut text with a 2-byte head: the error at its head, from the general reader.
expect {
	r : Try(Str, _)
	r = Cbor.parse([0x78, 0x18, 'a'])
	r == Err(InvalidCbor(0))
}

## Invalid UTF-8 in a short text: the error at its head, from the general reader.
expect {
	r : Try(Str, _)
	r = Cbor.parse([0x62, 0xc3, 0x28])
	r == Err(InvalidCbor(0))
}

## With ignore_tags, a text after a tag reads (not a plain position).
expect {
	r : Try(Str, _)
	r = Cbor.parse_with([0xc6, 0x61, 0x61], { ignore_tags: [6] })
	r == Ok("a")
}

## parse_u64 reads each head width of major type 0 on the fast path.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse([0x84, 0x17, 0x18, 0x18, 0x19, 0x01, 0x00, 0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	r == Ok([23, 24, 256, U64.highest])
}

## A padded integer head with PaddedNumbers reads its value.
expect {
	r : Try(U64, _)
	r = Cbor.parse_with([0x19, 0x00, 0x05], { allow: [PaddedNumbers] })
	r == Ok(5)
}

## An unknown record key with a 2-byte head is skipped.
expect {
	r : Try({ ab : U64 }, _)
	r = Cbor.parse([0xa2, 0x62, 0x61, 0x62, 0x01, 0x78, 0x18].concat(List.repeat('x', 24)).append(0x02))
	r == Ok({ ab: 1 })
}

## duplicate_keys Last: the record key fast path does not read the skipped first key.
expect {
	r : Try({ ab : U64 }, _)
	r = Cbor.parse_with([0xa2, 0x62, 0x61, 0x62, 0x01, 0x62, 0x61, 0x62, 0x02], { duplicate_keys: Last })
	r == Ok({ ab: 2 })
}

## duplicate_keys First: the record key fast path does not read the skipped second key.
expect {
	r : Try({ ab : U64 }, _)
	r = Cbor.parse_with([0xa2, 0x62, 0x61, 0x62, 0x01, 0x62, 0x61, 0x62, 0x02], { duplicate_keys: First })
	r == Ok({ ab: 1 })
}

## A Cbor.Value text of definite length with invalid UTF-8 in an array is an error at its head (byte 1).
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse([0x81, 0x62, 0xc3, 0x28])
	r == Err(InvalidCbor(1))
}

## A Cbor.Value byte string of definite length reads its bytes.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse([0x82, 0x42, 0x01, 0x02, 0x61, 0x61])
	r == Ok(Cbor.Value.Array([Cbor.Value.Bytes([0x01, 0x02]), Cbor.Value.Text("a")]))
}

## A Cbor.Value text of indefinite length (with IndefiniteLength) joins its chunks.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with([0x7f, 0x61, 0x61, 0x61, 0x62, 0xff], { allow: [IndefiniteLength] })
	r == Ok(Cbor.Value.Text("ab"))
}

## parse_f64 reads each float width on its fast path: f16 1.5, f32 1.5 and f64 1.5.
expect {
	r : Try(List(F64), _)
	r = Cbor.parse([0x83, 0xf9, 0x3e, 0x00, 0xfa, 0x3f, 0xc0, 0x00, 0x00, 0xfb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0])
	r == Ok([1.5, 1.5, 1.5])
}

## parse_f64 still reads an integer (the general path).
expect {
	r : Try(F64, _)
	r = Cbor.parse([0x18, 0x64])
	r == Ok(100.0)
}

## With ignore_tags, a record after a tag reads (parse_record_start takes the general path).
expect {
	r : Try({ a : U64 }, _)
	r = Cbor.parse_with([0xc6, 0xa1, 0x61, 0x61, 0x01], { ignore_tags: [6] })
	r == Ok({ a: 1 })
}

## A cut array of records is an error at the same position as before the fast path (the walk finds it first).
expect {
	r : Try(List({ a : U64 }), _)
	r = Cbor.parse([0x82, 0xa1, 0x61, 0x61, 0x01])
	r == Err(InvalidCbor(0))
}

## A record field that is a list of bools reads on the fast paths of parse_list_start and parse_bool.
expect {
	r : Try({ b : List(Bool) }, _)
	r = Cbor.parse([0xa1, 0x61, 0x62, 0x82, 0xf5, 0xf4])
	r == Ok({ b: [Bool.True, Bool.False] })
}

## skip of an unknown field that is a flat map, a flat array, and a nested array (the walk).
expect {
	r : Try({ a : U64 }, _)
	r = Cbor.parse([0xa4, 0x61, 0x6d, 0xa1, 0x01, 0x02, 0x61, 0x6c, 0x82, 0x01, 0x02, 0x61, 0x6e, 0x81, 0x81, 0x01, 0x61, 0x61, 0x05])
	r == Ok({ a: 5 })
}

## A Dict(Str, U64) key of 24 bytes or more (a 2-byte head) reads on the fast path of text.
expect {
	r : Try(Dict(Str, U64), _)
	r = Cbor.parse([0xa1, 0x78, 0x18].concat(List.repeat('k', 24)).append(0x01))
	r == Ok(Dict.from_list([(Str.repeat("k", 24), 1)]))
}

## A Dict(Str, U64) key with invalid UTF-8 is an error at the key (the general path).
expect {
	r : Try(Dict(Str, U64), _)
	r = Cbor.parse([0xa1, 0x62, 0xc3, 0x28, 0x01])
	r == Err(InvalidCbor(1))
}

## Chunk independence of `walk_from`: for each prefix of `bytes`, a walk of the prefix in one part and a walk in two
## parts (a walk of the first part, then a walk of the whole prefix from its `Cut` state) give the same result,
## at each split.
same_walks : List(U8), Rules, Bool -> Bool
same_walks = |bytes, rules, keep| {
	var $n = 0
	while $n <= bytes.len() {
		prefix = bytes.take_first($n)
		one = walk_from(prefix, walk_start(0, [], keep), rules)
		var $k = 0
		while $k <= $n {
			two =
				match walk_from(prefix.take_first($k), walk_start(0, [], keep), rules) {
					Ok(Cut(ws)) => walk_from(prefix, ws, rules)
					other => other
				}
			if two != one {
				return Bool.False
			}
			$k = $k + 1
		}
		$n = $n + 1
	}
	Bool.True
}

## The position of the error of `walk` for each prefix of `bytes` that is not the whole item.
cut_positions : List(U8), Rules -> List(U64)
cut_positions = |bytes, rules| {
	var $out = []
	var $n = 0
	while $n < bytes.len() {
		p =
			match walk(reader(bytes.take_first($n)), rules, Bool.False) {
				Ok(_) => no_pos
				Err(InvalidCbor(q)) => q
			}
		$out = $out.append(p)
		$n = $n + 1
	}
	$out
}

## The state of a walk that is whole, else `Err(NotWhole)`.
whole_state : Try([Whole(WalkState), Cut(WalkState)], [InvalidCbor(U64)]) -> Try(WalkState, [NotWhole])
whole_state = |r|
	match r {
		Ok(Whole(ws)) => Ok(ws)
		_ => Err(NotWhole)
	}

## The state of a walk that is cut, else `Err(NotCut)`.
cut_state : Try([Whole(WalkState), Cut(WalkState)], [InvalidCbor(U64)]) -> Try(WalkState, [NotCut])
cut_state = |r|
	match r {
		Ok(Cut(ws)) => Ok(ws)
		_ => Err(NotCut)
	}

indefinite_rules : Rules
indefinite_rules = { ..strict, indefinite: Bool.True }

## {"a": [1, 256], "b": 1([_ (_ h'01', h'02'), "€"])}: a map, a 3-byte head, a tag, an indefinite array and byte string.
nested : List(U8)
nested = [0xa2, 0x61, 0x61, 0x82, 0x01, 0x19, 0x01, 0x00, 0x61, 0x62, 0xc1, 0x9f, 0x5f, 0x41, 0x01, 0x41, 0x02, 0xff, 0x63, 0xe2, 0x82, 0xac, 0xff]

## [{"a": 1, "a": 2}, 1(2), 4294967296, 1.5 as f64]: a duplicate key (`First` skips it), a 9-byte head, a float.
with_dup : List(U8)
with_dup = [0x84, 0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02, 0xc1, 0x02, 0x1b, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0xfb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0]

## Valid items, and items with an error, with each rule set: one part and two parts agree.
expect same_walks(nested, indefinite_rules, Bool.False)

## nested with indefinite lengths and `keep`: one part and two parts agree.
expect same_walks(nested, indefinite_rules, Bool.True)

## nested with indefinite lengths, `keys: First` and `keep`: one part and two parts agree.
expect same_walks(nested, { ..indefinite_rules, keys: First }, Bool.True)

## nested with the rules any_length: one part and two parts agree.
expect same_walks(nested, any_length, Bool.False)

## with_dup with `keys: First` and `keep`: one part and two parts agree.
expect same_walks(with_dup, { ..strict, keys: First }, Bool.True)

## with_dup with the strict rules (a duplicate key is an error): one part and two parts agree.
expect same_walks(with_dup, strict, Bool.False)

## An array with a reserved head (1c) is an error: one part and two parts agree.
expect same_walks([0x82, 0x01, 0x1c, 0x00], strict, Bool.False)

## A text chunk in a byte string of indefinite length, in a map of indefinite length: one part and two parts agree.
expect same_walks([0xbf, 0x61, 0x61, 0x5f, 0x41, 0x01, 0x61, 0x02, 0xff, 0xff], indefinite_rules, Bool.False)

## An array count of 2^60 with 2 bytes left: one part and two parts agree.
expect same_walks([0x9b, 0x10, 0, 0, 0, 0, 0, 0, 0, 0x00, 0x00], strict, Bool.False)

## The end of a whole walk of `bytes`, or the position of its error.
walk_end : List(U8), Rules -> Try(U64, U64)
walk_end = |bytes, rules|
	match walk_from(bytes, walk_start(0, [], Bool.False), rules) {
		Ok(Whole(ws)) => Ok(ws.pos)
		Ok(Cut(ws)) => Err(cut_pos(bytes, ws))
		Err(InvalidCbor(p)) => Err(p)
	}

sorted_rules : Rules
sorted_rules = { ..strict, order: Sorted }

## {1: {"a": 1, "b": 2}, "x": [1], "yy": {10: 0, -1: 0}}: keys in the order of RFC 8949 4.2.1, a map in a map.
sorted_nested : List(U8)
sorted_nested = [0xa3, 0x01, 0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02, 0x61, 0x78, 0x81, 0x01, 0x62, 0x79, 0x79, 0xa2, 0x0a, 0x00, 0x20, 0x00]

## [{"a": 1, "a": 2, "b": 3}, {"b": 1, "a": 2}]: equal keys that are adjacent, then a key out of order at 15.
sorted_dup : List(U8)
sorted_dup = [0x82, 0xa3, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02, 0x61, 0x62, 0x03, 0xa2, 0x61, 0x62, 0x01, 0x61, 0x61, 0x02]

## key_order: Sorted: the check is in the walk, so a cut and a walk from the cut state give the same result.
expect same_walks(sorted_nested, sorted_rules, Bool.False)

## sorted_nested with `Sorted`, `keys: First` and `keep`: one part and two parts agree.
expect same_walks(sorted_nested, { ..sorted_rules, keys: First }, Bool.True)

## sorted_dup with `Sorted` and a duplicate key as an error: one part and two parts agree.
expect same_walks(sorted_dup, sorted_rules, Bool.False)

## sorted_dup with `Sorted` and `keys: First`: one part and two parts agree.
expect same_walks(sorted_dup, { ..sorted_rules, keys: First }, Bool.False)

## sorted_dup with `Sorted`, `keys: Last` and `keep`: one part and two parts agree.
expect same_walks(sorted_dup, { ..sorted_rules, keys: Last }, Bool.True)

## nested with indefinite lengths and `Sorted`: one part and two parts agree.
expect same_walks(nested, { ..indefinite_rules, order: Sorted }, Bool.False)

## sorted_nested with `Sorted` is whole, with the end at 21.
expect walk_end(sorted_nested, sorted_rules) == Ok(21)

## sorted_dup with `Sorted` and a duplicate key as an error: the error is at the second "a" (byte 5).
expect walk_end(sorted_dup, sorted_rules) == Err(5)

## {"b": 1, "a": 2} with `Sorted` and `keys: First`: the key out of order is an error at byte 4.
expect walk_end(sorted_dup.drop_first(11), { ..sorted_rules, keys: First }) == Err(4)

## {"b": 1, "a": 2} with the strict rules (no order check) is whole, with the end at 7.
expect walk_end(sorted_dup.drop_first(11), strict) == Ok(7)

## {"a": 1, "a": 2, "b": 3} with `Sorted` and `keys: First`: the key to skip is the second "a" (at 4).
expect whole_state(walk_from(sorted_dup.sublist({ start: 1, len: 10 }), walk_start(0, [], Bool.False), { ..sorted_rules, keys: First })).map_ok(|ws| ws.skips) == Ok([4])

## {"a": 1, "a": 2, "b": 3} with `Sorted` and `keys: Last`: the key to skip is the first "a" (at 1).
expect whole_state(walk_from(sorted_dup.sublist({ start: 1, len: 10 }), walk_start(0, [], Bool.False), { ..sorted_rules, keys: Last })).map_ok(|ws| ws.skips) == Ok([1])

## The order compares the deterministic encoding: a padded head and a float of more bytes than it needs.
expect order_keys([0x18, 0x0a, 0x20], 0, 2, 2, 3, { ..strict, shortest_heads: Bool.False }) == Before

## order_keys: the f64 1.0 comes before the f32 1.5.
expect order_keys([0xfb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0, 0xfa, 0x3f, 0xc0, 0, 0], 0, 9, 9, 14, strict) == Before

## order_keys: the f64 1.0 and the f16 1.0 are the same key.
expect order_keys([0xfb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0, 0xf9, 0x3c, 0x00], 0, 9, 9, 12, strict) == Same

## deterministic writes the f64 1.0 as the f16 f9 3c 00.
expect deterministic([0xfb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0], 0, 9, Keep) == [0xf9, 0x3c, 0x00]

## The state at a cut holds the work so far: the items, the open items, the keys of the open map.
expect
	match cut_state(walk_from(with_dup.take_first(6), walk_start(0, [], Bool.True), { ..strict, keys: First })) {
		Ok(ws) => ws.pos == 5 and ws.count == 4 and ws.open.len() == 2 and ws.keys == [2, 4]
		Err(_) => Bool.False
	}

## A whole walk of with_dup with `keys: First` ends at 28, and the key to skip is the second "a" (at 5).
expect whole_state(walk_from(with_dup, walk_start(0, [], Bool.True), { ..strict, keys: First })).map_ok(|ws| (ws.pos, ws.skips)) == Ok((28, [5]))

## The truncation rule: the head of the innermost item that is not whole. A chunk of a string of indefinite
## length is not an item: a cut chunk is an error at the head of its string.
expect cut_positions(nested, indefinite_rules) == [0, 0, 1, 0, 3, 3, 5, 5, 0, 8, 0, 10, 11, 12, 12, 12, 12, 12, 11, 18, 18, 18, 11]

## A map whose count needs 2^64 items or more: no overflow, and the bytes end in the map.
expect walk(reader([0xbb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]), strict, Bool.False).map_ok(|s| s.pos) == Err(InvalidCbor(0))

## Keys with the shortest heads: the same key with another head width is the same key.
expect canonical([0x78, 0x01, 0x61, 0x19, 0x00, 0x05], 0, 6, Keep) == [0x61, 0x61, 0x05]

## canonical writes the f16 1.0 as the f64 1.0.
expect canonical([0xf9, 0x3c, 0x00], 0, 3, Keep) == [0xfb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0]

## dup_keys with no shortest heads: "a" and "a" with a padded head (78 01 61) are the same key, an error at byte 4.
expect dup_keys([0xa2, 0x61, 0x61, 0x01, 0x78, 0x01, 0x61, 0x02], [1, 3, 4, 7], { ..strict, shortest_heads: Bool.False }) == Err(InvalidCbor(4))

## dup_keys with the strict rules compares the key bytes as they are: "a" and 78 01 61 differ, no key to skip.
expect dup_keys([0xa2, 0x61, 0x61, 0x01, 0x78, 0x01, 0x61, 0x02], [1, 3, 4, 7], strict) == Ok([])

## A key rule for each instance: `First` skips the later ones, `Last` the earlier ones. 20 keys (the sort), 3 of them "a".
many_keys : { bytes : List(U8), keys : List(U64) }
many_keys = {
	# The keys "a", then 1 byte each from 0x62, with "a" again at index 7 and 15.
	names : List(U8)
	names = (0.U8).until(20).map(|i| if (i == 0 or i == 7 or i == 15) 0x61 else 0x62 + i).collect()
	bytes = names.fold([], |acc, b| acc.append(0x61).append(b))
	spans : List(List(U64))
	spans = (0.U64).until(20).map(|i| [2 * i, 2 * i + 2]).collect()
	keys = spans.join()
	{ bytes, keys }
}

## dup_keys of many_keys with `Reject`: the error is at the second "a" (byte 14).
expect dup_keys(many_keys.bytes, many_keys.keys, strict) == Err(InvalidCbor(14))

## dup_keys of many_keys with `keys: First`: the keys to skip are the later "a" keys, at 14 and 30.
expect dup_keys(many_keys.bytes, many_keys.keys, { ..strict, keys: First }) == Ok([14, 30])

## dup_keys of many_keys with `keys: Last`: the keys to skip are the earlier "a" keys, at 0 and 14.
expect dup_keys(many_keys.bytes, many_keys.keys, { ..strict, keys: Last }) == Ok([0, 14])

## Options: each field is optional. The full record, a record bound with let (with the annotation `Cbor.Options`), one field, and no field.
expect {
	bytes = [0xa1, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x61, 0x37]
	full : Try({ user_id : U64 }, _)
	full = Cbor.parse_with(bytes, { fields: Camel, allow: [IntFromText] })
	opts : Cbor.Options
	opts = { fields: Camel, allow: [IntFromText] }
	bound : Try({ user_id : U64 }, _)
	bound = Cbor.parse_with(bytes, opts)
	only_text : Try({ user_id : U64 }, _)
	only_text = Cbor.parse_with([0xa1, 0x67, 0x75, 0x73, 0x65, 0x72, 0x5f, 0x69, 0x64, 0x61, 0x37], { allow: [IntFromText] })
	only_camel : Try({ user_id : U64 }, _)
	only_camel = Cbor.parse_with(bytes, { fields: Camel })
	none : Try({ user_id : U64 }, _)
	none = Cbor.parse_with([0xa1, 0x67, 0x75, 0x73, 0x65, 0x72, 0x5f, 0x69, 0x64, 0x07], {})
	full == Ok({ user_id: 7 }) and bound == full and only_text == full and only_camel == Err(InvalidCbor(8)) and none == full
}

## Options: an omitted field has the default of `parse` (Snake, strict).
expect {
	snake_key = [0xa1, 0x67, 0x75, 0x73, 0x65, 0x72, 0x5f, 0x69, 0x64, 0x07]
	a : Try({ user_id : U64 }, _)
	a = Cbor.parse_with(snake_key, {})
	b : Try({ user_id : U64 }, _)
	b = Cbor.parse_with([0x61, 0x37], {})
	c : Try(U64, _)
	c = Cbor.parse_with([0x61, 0x37], {})
	a == Ok({ user_id: 7 }) and b == Err(InvalidCbor(0)) and c == Err(InvalidCbor(0))
}

## Cbor.U8Array.to_list gives the list back.
expect Cbor.U8Array.([1, 2, 3]).to_list() == [1, 2, 3]
