app [] { pkg: "../src/main.roc" }

# The stream writer Cbor.StreamWriter (0.5.0), through the public API of the package. Each kind of level, definite
# and indefinite, nested levels, a sequence, the 9-byte head, each count error, an error that keeps the old writer,
# and the key check of key_order: Sorted. The output reads back with Cbor.parse_with, and a definite form has the
# same bytes as Cbor.encode_with of the same value.

import pkg.Cbor

## One step of the writer.
Op : [
	OpenArray([Count(U64), Indefinite]),
	OpenMap([Count(U64), Indefinite]),
	OpenBytes([Length(U64), Indefinite]),
	OpenText([Length(U64), Indefinite]),
	Item(Cbor.Value),
	Entry(Cbor.Value, Cbor.Value),
	Chunk(List(U8)),
	TextChunk(Str),
	Close,
]

## Does `op` on `w`.
step : Cbor.StreamWriter, Op -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch, DuplicateMapKey, KeyOutOfOrder])
step = |w, op|
	match op {
		OpenArray(size) => w.open_array(size)
		OpenMap(size) => w.open_map(size)
		OpenBytes(size) => w.open_bytes(size)
		OpenText(size) => w.open_text(size)
		Item(value) => w.item(value)
		Entry(key, value) => w.entry(key, value)
		Chunk(data) => w.bytes_chunk(data)
		TextChunk(text) => w.text_chunk(text)
		Close => w.close()
	}

## Does each op on `start`, and joins the bytes.
play : Cbor.StreamWriter, List(Op) -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch, DuplicateMapKey, KeyOutOfOrder])
play = |start, ops| {
	var $w = start
	var $out = []
	for op in ops {
		s = step($w, op)?
		$out = $out.concat(s.bytes)
		$w = s.writer
	}
	Ok({ bytes: $out, writer: $w })
}

## The bytes of `ops` on `start`, after `finish`.
run : Cbor.StreamWriter, List(Op) -> Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder])
run = |start, ops| {
	done = play(start, ops)?
	done.writer.finish()?
	Ok(done.bytes)
}

## The bytes of `ops` for one root item, with no options.
one : List(Op) -> Try(List(U8), [CountMismatch, DuplicateMapKey, KeyOutOfOrder])
one = |ops| run(Cbor.StreamWriter.new({}), ops)

## The ops, then `finish`: the first error. `Ok` is a test failure.
fails : Cbor.StreamWriter, List(Op) -> [CountMismatch, DuplicateMapKey, KeyOutOfOrder, NoError]
fails = |start, ops|
	match run(start, ops) {
		Ok(_) => NoError
		Err(CountMismatch) => CountMismatch
		Err(DuplicateMapKey) => DuplicateMapKey
		Err(KeyOutOfOrder) => KeyOutOfOrder
	}

## The error of one step. `NoError` for `Ok`.
err : Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch, DuplicateMapKey, KeyOutOfOrder]) -> [CountMismatch, DuplicateMapKey, KeyOutOfOrder, NoError]
err = |r|
	match r {
		Ok(_) => NoError
		Err(CountMismatch) => CountMismatch
		Err(DuplicateMapKey) => DuplicateMapKey
		Err(KeyOutOfOrder) => KeyOutOfOrder
	}

## The ops on a new writer, then one more op: its error. The ops before it must be Ok.
last_fails : List(Op), Op -> [CountMismatch, DuplicateMapKey, KeyOutOfOrder, NoError, BadSetup]
last_fails = |ops, op|
	match play(Cbor.StreamWriter.new({}), ops) {
		Err(_) => BadSetup
		Ok(done) =>
			match step(done.writer, op) {
				Ok(_) => NoError
				Err(CountMismatch) => CountMismatch
				Err(DuplicateMapKey) => DuplicateMapKey
				Err(KeyOutOfOrder) => KeyOutOfOrder
			}
	}

indefinite : Cbor.Options
indefinite = { allow: [IndefiniteLength] }

## A Cbor.Value map of distinct keys.
vmap : List((Cbor.Value, Cbor.Value)) -> Cbor.Value
vmap = |pairs|
	match Cbor.ValueMap.from_list(pairs) {
		Ok(m) => Cbor.Value.Map(m)
		Err(_) => crash "a duplicate key in a test map"
	}

# Each kind of level, definite: the same bytes as encode_with

## A definite array: [1, "a"].
expect {
	bytes = one([OpenArray(Count(2)), Item(Int(1)), Item(Text("a")), Close])
	value : Cbor.Value
	value = Array([Int(1), Text("a")])
	back : Try(Cbor.Value, _)
	back = Cbor.parse(bytes ?? [])
	bytes == Ok([0x82, 0x01, 0x61, 0x61]) and bytes == Cbor.encode_with(value, {}) and back == Ok(value)
}

## A definite empty array, and an array of a 2-byte count.
expect {
	empty = one([OpenArray(Count(0)), Close])
	items = List.repeat(Item(Int(0)), 300)
	long = one(List.concat([OpenArray(Count(300))], items).append(Close))
	long_value : List(U64)
	long_value = List.repeat(0, 300)
	empty == Ok([0x80]) and long == Cbor.encode_with(long_value, {}) and (long ?? []).take_first(3) == [0x99, 0x01, 0x2c]
}

## A definite map with `entry`, and the same map with `item` for each key and value.
expect {
	a = one([OpenMap(Count(2)), Entry(Text("a"), Int(1)), Entry(Text("b"), Int(2)), Close])
	b = one([OpenMap(Count(2)), Item(Text("a")), Item(Int(1)), Item(Text("b")), Item(Int(2)), Close])
	value = Dict.from_list([("a", 1.U64), ("b", 2)])
	back : Try(Dict(Str, U64), _)
	back = Cbor.parse(a ?? [])
	a == Ok([0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02]) and a == b and a == Cbor.encode_with(value, {}) and back == Ok(value)
}

## A definite byte string in two chunks, and an empty one.
expect {
	bytes = one([OpenBytes(Length(5)), Chunk([1, 2]), Chunk([3, 4, 5]), Close])
	empty = one([OpenBytes(Length(0)), Close])
	value : List(U8)
	value = [1, 2, 3, 4, 5]
	back : Try(List(U8), _)
	back = Cbor.parse(bytes ?? [])
	bytes == Ok([0x45, 1, 2, 3, 4, 5]) and bytes == Cbor.encode_with(value, {}) and back == Ok(value) and empty == Ok([0x40])
}

## A definite text in chunks: the length counts bytes of UTF-8 (the euro sign is 3 bytes).
expect {
	bytes = one([OpenText(Length(7)), TextChunk("ab"), TextChunk(""), TextChunk("c€d"), Close])
	back : Try(Str, _)
	back = Cbor.parse(bytes ?? [])
	bytes == Cbor.encode_with("abc€d", {}) and back == Ok("abc€d")
}

# Each kind of level, indefinite: reads back with IndefiniteLength

## An indefinite array, and an empty one.
expect {
	bytes = one([OpenArray(Indefinite), Item(Int(1)), Item(Text("a")), Close])
	empty = one([OpenArray(Indefinite), Close])
	back : Try(Cbor.Value, _)
	back = Cbor.parse_with(bytes ?? [], indefinite)
	strict : Try(Cbor.Value, _)
	strict = Cbor.parse(bytes ?? [])
	bytes == Ok([0x9f, 0x01, 0x61, 0x61, 0xff]) and back == Ok(Array([Int(1), Text("a")])) and strict == Err(InvalidCbor(0)) and empty == Ok([0x9f, 0xff])
}

## An indefinite map with `entry` and with `item`.
expect {
	bytes = one([OpenMap(Indefinite), Entry(Text("a"), Int(1)), Item(Text("b")), Item(Int(2)), Close])
	back : Try({ a : U64, b : U64 }, _)
	back = Cbor.parse_with(bytes ?? [], indefinite)
	bytes == Ok([0xbf, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02, 0xff]) and back == Ok({ a: 1, b: 2 })
}

## An indefinite byte string: each chunk is a definite byte string, also an empty chunk.
expect {
	bytes = one([OpenBytes(Indefinite), Chunk([1, 2]), Chunk([]), Chunk([3, 4, 5]), Close])
	back : Try(List(U8), _)
	back = Cbor.parse_with(bytes ?? [], indefinite)
	bytes == Ok([0x5f, 0x42, 1, 2, 0x40, 0x43, 3, 4, 5, 0xff]) and back == Ok([1, 2, 3, 4, 5])
}

## An indefinite text: each chunk is a definite text.
expect {
	bytes = one([OpenText(Indefinite), TextChunk("ab"), TextChunk("€")])
	closed = one([OpenText(Indefinite), TextChunk("ab"), TextChunk("€"), Close])
	back : Try(Str, _)
	back = Cbor.parse_with(closed ?? [], indefinite)
	bytes == Err(CountMismatch) and closed == Ok([0x7f, 0x62, 0x61, 0x62, 0x63, 0xe2, 0x82, 0xac, 0xff]) and back == Ok("ab€")
}

# Nested levels

## Definite levels in definite levels: the same bytes as encode_with of the value.
expect {
	ops = [
		OpenArray(Count(3)),
		OpenMap(Count(2)),
		Entry(Text("id"), Int(7)),
		Item(Text("data")),
		OpenBytes(Length(3)),
		Chunk([9, 8]),
		Chunk([7]),
		Close,
		Close,
		OpenArray(Count(1)),
		OpenText(Length(2)),
		TextChunk("x"),
		TextChunk("y"),
		Close,
		Close,
		Item(Null),
		Close,
	]
	bytes = one(ops)
	value : Cbor.Value
	value = Array([vmap([(Text("id"), Int(7)), (Text("data"), Bytes([9, 8, 7]))]), Array([Text("xy")]), Null])
	back : Try(Cbor.Value, _)
	back = Cbor.parse(bytes ?? [])
	bytes == Cbor.encode_with(value, {}) and back == Ok(value)
}

## Indefinite and definite levels mixed: an indefinite array of a definite byte string, an indefinite map with an
## indefinite text value, and an indefinite byte string.
expect {
	ops = [
		OpenArray(Indefinite),
		OpenBytes(Length(2)),
		Chunk([1, 2]),
		Close,
		OpenMap(Indefinite),
		Item(Text("t")),
		OpenText(Indefinite),
		TextChunk("a"),
		TextChunk("b"),
		Close,
		Close,
		OpenBytes(Indefinite),
		Chunk([3]),
		Close,
		Close,
	]
	bytes = one(ops)
	back : Try(Cbor.Value, _)
	back = Cbor.parse_with(bytes ?? [], indefinite)
	strict : Try(Cbor.Value, _)
	strict = Cbor.parse(bytes ?? [])
	back == Ok(Array([Bytes([1, 2]), vmap([(Text("t"), Text("ab"))]), Bytes([3])])) and strict == Err(InvalidCbor(0))
}

## A streamed key with `Given`: an indefinite text at a key place.
expect {
	bytes = one([OpenMap(Count(1)), OpenText(Indefinite), TextChunk("k"), Close, Item(Int(1)), Close])
	back : Try({ k : U64 }, _)
	back = Cbor.parse_with(bytes ?? [], indefinite)
	back == Ok({ k: 1 })
}

## A typed item: the options of the writer apply in the item (fields: Camel, key_order: Sorted sorts its maps).
expect {
	w = Cbor.StreamWriter.new({ fields: Camel, key_order: Sorted })
	opened = w.open_array(Count(1)) ?? crash "open"
	added = opened.writer.item({ user_id: 1.U64, a_b: 2.U8 }) ?? crash "item"
	closed = added.writer.close() ?? crash "close"
	bytes = opened.bytes.concat(added.bytes).concat(closed.bytes)
	expected = Cbor.encode_with([{ user_id: 1.U64, a_b: 2.U8 }], { fields: Camel, key_order: Sorted })
	back : Try(List({ user_id : U64, a_b : U8 }), _)
	back = Cbor.parse_with(bytes, { fields: Camel, key_order: Sorted })
	closed.writer.finish() == Ok({}) and Ok(bytes) == expected and back == Ok([{ user_id: 1, a_b: 2 }]) and bytes.take_first(5) == [0x81, 0xa2, 0x62, 0x61, 0x42]
}

## A typed entry with a record value: the key and the value in one step.
expect {
	w = Cbor.StreamWriter.new({})
	opened = w.open_map(Indefinite) ?? crash "open"
	added = opened.writer.entry(5.U64, { x: "y" }) ?? crash "entry"
	closed = added.writer.close() ?? crash "close"
	bytes = opened.bytes.concat(added.bytes).concat(closed.bytes)
	back : Try(Dict(U64, { x : Str }), _)
	back = Cbor.parse_with(bytes, indefinite)
	added.bytes == [0x05, 0xa1, 0x61, 0x78, 0x61, 0x79] and back == Ok(Dict.from_list([(5, { x: "y" })]))
}

# The error unions are open: each step composes with `?` in one function, with an error of the app

## Each step with `?` in one function, and an error of the app in the same union.
upload : U64 -> Try(List(U8), _)
upload = |n| {
	if n == 0 {
		return Err(Empty)
	}
	opened = Cbor.StreamWriter.new({}).open_array(Count(n))?
	var $w = opened.writer
	var $out = opened.bytes
	for i in (0.U64).until(n) {
		s = $w.item(i)?
		$out = $out.concat(s.bytes)
		$w = s.writer
	}
	closed = $w.close()?
	closed.writer.finish()?
	Ok($out.concat(closed.bytes))
}

## upload(2) writes [0, 1] as 82 00 01, and upload(0) is the app error Err(Empty).
expect {
	ok = upload(2)
	empty = upload(0)
	ok == Ok([0x82, 0x00, 0x01]) and empty == Err(Empty)
}

# The root: one item (new) or a sequence

## A sequence of 3 items, two of them streamed; and an empty sequence.
expect {
	ops = [Item(Int(1)), OpenArray(Indefinite), Item(Int(2)), Close, OpenBytes(Length(1)), Chunk([3]), Close]
	bytes = run(Cbor.StreamWriter.sequence({}), ops)
	back : Try(List(Cbor.Value), _)
	back = Cbor.parse_sequence_with(bytes ?? [], indefinite)
	empty = run(Cbor.StreamWriter.sequence({}), [])
	bytes == Ok([0x01, 0x9f, 0x02, 0xff, 0x41, 0x03]) and back == Ok([Int(1), Array([Int(2)]), Bytes([3])]) and empty == Ok([])
}

## A sequence ends only between items: finish with an open level is an error.
expect fails(Cbor.StreamWriter.sequence({}), [Item(Int(1)), OpenArray(Count(1))]) == CountMismatch

## `new`: one root item. No item, or a second item, is an error.
expect {
	none = fails(Cbor.StreamWriter.new({}), [])
	second = last_fails([Item(Int(1))], Item(Int(2)))
	second_open = last_fails([OpenArray(Count(0)), Close], OpenArray(Count(0)))
	none == CountMismatch and second == CountMismatch and second_open == CountMismatch
}

# The 9-byte head

## The shortest head for each size, also 2^32 - 1 (5 bytes) and 2^32 (9 bytes).
expect {
	head = |n| Cbor.StreamWriter.new({}).open_bytes(Length(n)).map_ok(|s| s.bytes)
	head(5_000_000_000) == Ok([0x5b, 0x00, 0x00, 0x00, 0x01, 0x2a, 0x05, 0xf2, 0x00])
		and head(4_294_967_295) == Ok([0x5a, 0xff, 0xff, 0xff, 0xff])
		and head(4_294_967_296) == Ok([0x5b, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])
		and head(23) == Ok([0x57])
		and head(24) == Ok([0x58, 24])
}

## The same head for a text, an array and a map.
expect {
	w = Cbor.StreamWriter.new({})
	text = w.open_text(Length(5_000_000_000)).map_ok(|s| s.bytes)
	array = w.open_array(Count(5_000_000_000)).map_ok(|s| s.bytes)
	map = w.open_map(Count(5_000_000_000)).map_ok(|s| s.bytes)
	text == Ok([0x7b, 0x00, 0x00, 0x00, 0x01, 0x2a, 0x05, 0xf2, 0x00])
		and array == Ok([0x9b, 0x00, 0x00, 0x00, 0x01, 0x2a, 0x05, 0xf2, 0x00])
		and map == Ok([0xbb, 0x00, 0x00, 0x00, 0x01, 0x2a, 0x05, 0xf2, 0x00])
}

## A byte string of 5,000,000,000 bytes, streamed in full: one list of 1 MiB used again, then the rest.
## Each definite chunk is the list itself, so no 5 GB is in memory. One byte too many and an early close are errors.
expect {
	size = 5_000_000_000
	block = List.repeat(7.U8, 1_048_576)
	opened = Cbor.StreamWriter.new({}).open_bytes(Length(size)) ?? crash "open"
	var $w = opened.writer
	var $sent = 0
	var $same = Bool.True
	while $sent + block.len() <= size {
		s = $w.bytes_chunk(block) ?? crash "chunk"
		$same = $same and s.bytes.len() == block.len()
		$sent = $sent + block.len()
		$w = s.writer
	}
	rest = size - $sent
	early = $w.close()
	too_many = $w.bytes_chunk(List.repeat(7, rest + 1))
	last = $w.bytes_chunk(List.repeat(7, rest)) ?? crash "last"
	one_more = last.writer.bytes_chunk([7])
	closed = last.writer.close() ?? crash "close"
	opened.bytes == [0x5b, 0x00, 0x00, 0x00, 0x01, 0x2a, 0x05, 0xf2, 0x00]
		and $same
		and early.is_err()
		and too_many.is_err()
		and one_more.is_err()
		and last.bytes.len() == rest
		and closed.bytes == []
		and closed.writer.finish() == Ok({})
}

## `close` with no data of a large length is an error.
expect last_fails([OpenBytes(Length(5_000_000_000))], Close) == CountMismatch

# Count errors: the step gives CountMismatch and no bytes

## Too few: close of a definite array, map, byte string or text before its count or length.
expect {
	array = last_fails([OpenArray(Count(2)), Item(Int(1))], Close)
	map = last_fails([OpenMap(Count(1))], Close)
	map_half = last_fails([OpenMap(Count(1)), Item(Text("a"))], Close)
	bytes = last_fails([OpenBytes(Length(3)), Chunk([1, 2])], Close)
	text = last_fails([OpenText(Length(3)), TextChunk("ab")], Close)
	array == CountMismatch and map == CountMismatch and map_half == CountMismatch and bytes == CountMismatch and text == CountMismatch
}

## Too many: one more item in a full array or map, one more level, one byte more.
expect {
	array = last_fails([OpenArray(Count(1)), Item(Int(1))], Item(Int(2)))
	array_open = last_fails([OpenArray(Count(1)), Item(Int(1))], OpenArray(Indefinite))
	map = last_fails([OpenMap(Count(1)), Entry(Text("a"), Int(1))], Item(Text("b")))
	map_entry = last_fails([OpenMap(Count(1)), Entry(Text("a"), Int(1))], Entry(Text("b"), Int(2)))
	bytes = last_fails([OpenBytes(Length(3)), Chunk([1, 2])], Chunk([3, 4]))
	text = last_fails([OpenText(Length(3)), TextChunk("ab")], TextChunk("€"))
	array == CountMismatch and array_open == CountMismatch and map == CountMismatch and map_entry == CountMismatch and bytes == CountMismatch and text == CountMismatch
}

## The wrong kind of step for the level: a chunk in an array or a map, an item or a level in a string, a byte chunk in
## a text, a text chunk in a byte string, a chunk at the root.
expect {
	chunk_array = last_fails([OpenArray(Indefinite)], Chunk([1]))
	text_map = last_fails([OpenMap(Indefinite)], TextChunk("a"))
	item_bytes = last_fails([OpenBytes(Indefinite)], Item(Bytes([1])))
	item_text = last_fails([OpenText(Length(1))], Item(Text("a")))
	open_bytes = last_fails([OpenBytes(Indefinite)], OpenBytes(Length(1)))
	open_text = last_fails([OpenText(Indefinite)], OpenText(Indefinite))
	bytes_in_text = last_fails([OpenText(Indefinite)], Chunk([0x61]))
	text_in_bytes = last_fails([OpenBytes(Indefinite)], TextChunk("a"))
	chunk_root = last_fails([], Chunk([1]))
	text_root = last_fails([], TextChunk("a"))
	List.all(
		[chunk_array, text_map, item_bytes, item_text, open_bytes, open_text, bytes_in_text, text_in_bytes, chunk_root, text_root],
		|e| e == CountMismatch,
	)
}

## `close` with nothing to close: at the root, or one `close` too many.
expect {
	root = last_fails([], Close)
	after = last_fails([OpenArray(Indefinite), Close], Close)
	root == CountMismatch and after == CountMismatch
}

## An indefinite map with a key and no value: close is an error.
expect last_fails([OpenMap(Indefinite), Item(Text("a"))], Close) == CountMismatch

## `entry` only at a key place of a map: not at a value place, not in an array, not at the root.
expect {
	value_place = last_fails([OpenMap(Indefinite), Item(Text("a"))], Entry(Text("b"), Int(1)))
	array = last_fails([OpenArray(Indefinite)], Entry(Text("b"), Int(1)))
	root = last_fails([], Entry(Text("b"), Int(1)))
	value_place == CountMismatch and array == CountMismatch and root == CountMismatch
}

## `finish` with an open level, definite or indefinite, also when the level has all its items.
expect {
	a = fails(Cbor.StreamWriter.new({}), [OpenArray(Indefinite), Item(Int(1))])
	b = fails(Cbor.StreamWriter.new({}), [OpenArray(Count(1)), Item(Int(1))])
	c = fails(Cbor.StreamWriter.new({}), [OpenArray(Count(1)), OpenBytes(Length(0)), Close])
	d = fails(Cbor.StreamWriter.new({}), [OpenText(Length(0))])
	a == CountMismatch and b == CountMismatch and c == CountMismatch and d == CountMismatch
}

## A count error of a hand-written encoder in an item comes out of `item`.
expect {
	opened = Cbor.StreamWriter.new({}).open_array(Indefinite) ?? crash "open"
	bad = opened.writer.item(Bad.(0))
	match bad {
		Err(CountMismatch) => Bool.True
		_ => Bool.False
	}
}

## An encoder_for that writes 2 items in one place.
Bad := U8.{
	encoder_for : Cbor -> (Bad, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |_, w| Cbor.encode_u64(2, Cbor.encode_u64(1, w)?)
}

# An error keeps the old writer

## After an error, the writer before it does the next steps, and the output is valid.
expect {
	opened = Cbor.StreamWriter.new({}).open_array(Count(2)) ?? crash "open"
	first = opened.writer.item(1.U64) ?? crash "first"
	wrong = first.writer.bytes_chunk([1])
	early = first.writer.close()
	second = first.writer.item(2.U64) ?? crash "second"
	too_many = second.writer.item(3.U64)
	closed = second.writer.close() ?? crash "close"
	bytes = opened.bytes.concat(first.bytes).concat(second.bytes).concat(closed.bytes)
	wrong.is_err() and early.is_err() and too_many.is_err() and closed.writer.finish() == Ok({}) and bytes == [0x82, 0x01, 0x02]
}

# key_order: Sorted on a streamed map

sorted : Cbor.StreamWriter
sorted = Cbor.StreamWriter.new({ key_order: Sorted })

## Keys in order (the bytewise order: "b" before "aa", text before an array) read back with key_order: Sorted.
expect {
	bytes = run(sorted, [OpenMap(Indefinite), Entry(Text("b"), Int(1)), Item(Text("aa")), Item(Int(2)), Entry(Array([]), Null), Close])
	back : Try(Cbor.Value, _)
	back = Cbor.parse_with(bytes ?? [], { allow: [IndefiniteLength], key_order: Sorted })
	back == Ok(vmap([(Text("b"), Int(1)), (Text("aa"), Int(2)), (Array([]), Null)]))
}

## A definite sorted map has the bytes of encode_with(.., { key_order: Sorted }).
expect {
	bytes = run(sorted, [OpenMap(Count(3)), Entry(Text("a"), Int(1)), Entry(Text("b"), Int(2)), Entry(Text("aa"), Int(3)), Close])
	bytes == Cbor.encode_with(Dict.from_list([("aa", 3.U64), ("b", 2), ("a", 1)]), { key_order: Sorted })
}

## A smaller key: KeyOutOfOrder, with `entry` and with `item`. An equal key: DuplicateMapKey.
expect {
	start = play(sorted, [OpenMap(Indefinite), Entry(Text("b"), Int(1))]) ?? crash "start"
	smaller = step(start.writer, Entry(Text("a"), Int(2)))
	smaller_item = step(start.writer, Item(Text("a")))
	longer = step(start.writer, Item(Text("aa")))
	equal = step(start.writer, Entry(Text("b"), Int(2)))
	equal_item = step(start.writer, Item(Text("b")))
	err(smaller) == KeyOutOfOrder and err(smaller_item) == KeyOutOfOrder and longer.is_ok() and err(equal) == DuplicateMapKey and err(equal_item) == DuplicateMapKey
}

## The check is for each map level: a nested map starts with no key, and the outer map keeps its key.
expect {
	ops = [OpenMap(Indefinite), Item(Text("m")), OpenMap(Count(2)), Entry(Text("z"), Int(1)), Entry(Text("zz"), Int(2)), Close]
	start = play(sorted, ops) ?? crash "start"
	smaller = step(start.writer, Item(Text("a")))
	equal = step(start.writer, Item(Text("m")))
	bigger = step(start.writer, Item(Text("n")))
	err(smaller) == KeyOutOfOrder and err(equal) == DuplicateMapKey and bigger.is_ok()
}

## A level at a key place: CountMismatch with Sorted (the key has no bytes to compare). At a value place it is fine.
expect {
	start = play(sorted, [OpenMap(Indefinite), Entry(Text("a"), Int(1))]) ?? crash "start"
	key_array = step(start.writer, OpenArray(Count(0)))
	key_text = step(start.writer, OpenText(Indefinite))
	value = play(start.writer, [Item(Text("b")), OpenArray(Count(0)), Close, Close])
	err(key_array) == CountMismatch and err(key_text) == CountMismatch and value.map_ok(|d| d.bytes) == Ok([0x61, 0x62, 0x80, 0xff])
}

## After KeyOutOfOrder the old writer goes on with a key in order.
expect {
	start = play(sorted, [OpenMap(Count(2)), Entry(Text("b"), Int(1))]) ?? crash "start"
	bad = step(start.writer, Entry(Text("a"), Int(2)))
	good = play(start.writer, [Entry(Text("c"), Int(2)), Close])
	bytes = good.map_ok(|d| start.bytes.concat(d.bytes))
	good_finish = good.map_ok(|d| d.writer.finish())
	err(bad) == KeyOutOfOrder and bytes == Ok([0xa2, 0x61, 0x62, 0x01, 0x61, 0x63, 0x02]) and good_finish == Ok(Ok({}))
}

## With Given (the default), a streamed map is not checked.
expect {
	bytes = one([OpenMap(Indefinite), Entry(Text("b"), Int(1)), Entry(Text("a"), Int(2)), Entry(Text("a"), Int(3)), Close])
	bytes == Ok([0xbf, 0x61, 0x62, 0x01, 0x61, 0x61, 0x02, 0x61, 0x61, 0x03, 0xff])
}
