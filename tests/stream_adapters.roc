app [] { pkg: "../src/main.roc" }

# The adapters between the stream types of the package and the builtin `Stream` (0.5.0), through the public API of
# the package: `from_stream` of Cbor.Items, Cbor.Entries, Cbor.ByteChunks and Cbor.TextChunks, and the writer adapters
# Cbor.StreamWriter.array_stream, map_stream, sequence_stream, bytes_stream and text_stream.
#
# An app, not a `roc test` file: a `Stream` is effectful (`Stream.next!`), and an `expect` cannot run an effect. The
# sources are pure lists lifted with `Stream.from_iter`. `roc tests/stream_adapters.roc` prints each failed check and
# exits with 1. Each drive of an output stream stops after `step_limit` items.
#
# The property of most checks: for each split of the input into chunks, the adapter gives the events of a push loop
# (`push` of each chunk, then `finish`) over the same chunks: the same values, then the same error.

import pkg.Cbor

# Helpers

hex_digit : U8 -> U8
hex_digit = |c| if (c >= 97) c - 87 else c - 48

hex : Str -> List(U8)
hex = |s|
	s.to_utf8().chunks_of(2).map(
		|pair|
			match pair {
				[hi, lo] => hex_digit(hi) * 16 + hex_digit(lo)
				_ => crash "odd hex"
			},
	)

## The error of a source in this file.
Fail : [Poison]

## The errors of the decoders in this file: a closed union, so that results compare with `==`.
Errs : [InvalidCbor(U64), TooLarge(U64), NotStreamable, MissingRequiredField(Str), Input(Fail)]

## The errors of the chunk decoders.
ChunkErrs : [InvalidCbor(U64), Input(Fail)]

## The errors of the writer adapters.
WriteErrs : [CountMismatch, DuplicateMapKey, KeyOutOfOrder, Input(Fail)]

## The most items of one drive of an output stream (and the most steps of a push loop): each check needs far fewer.
step_limit : U64
step_limit = 100_000

## A source of the chunks, in order.
source : List(List(U8)) -> Stream(Try(List(U8), Fail))
source = |chunks| Stream.from_iter(chunks.map(|c| Ok(c)).iter())

## A source of the chunks, then the error `Poison`.
failing : List(List(U8)) -> Stream(Try(List(U8), Fail))
failing = |chunks| Stream.from_iter(chunks.map(|c| Ok(c)).append(Err(Poison)).iter())

## A source of the values, then `Poison` when `fail`.
values : List(a), Bool -> Stream(Try(a, Fail))
values = |list, fail| {
	oks = list.map(|v| Ok(v))
	Stream.from_iter((if (fail) oks.append(Err(Poison)) else oks).iter())
}

## The items of `stream`, at most `step_limit`.
drain! : Stream(a) => List(a)
drain! = |stream| stream.take_first(step_limit).collect!()

## The splits of `bytes`: one chunk, chunks of 1 byte, 1 byte chunks with an empty chunk after each, and each split
## in 2 parts and in 3 parts.
splits : List(U8) -> List(List(List(U8)))
splits = |bytes| {
	n = bytes.len()
	var $out = [[bytes], bytes.chunks_of(1)]
	var $spaced = []
	for b in bytes {
		$spaced = $spaced.append([b]).append([])
	}
	$out = $out.append($spaced)
	for i in 0..=n {
		$out = $out.append([bytes.take_first(i), bytes.drop_first(i)])
		for j in i..=n {
			$out = $out.append([bytes.take_first(i), bytes.sublist({ start: i, len: j - i }), bytes.drop_first(j)])
		}
	}
	$out
}

# The push loops: the values of each `push` over the chunks, then the error of `push` or `finish`, as the adapter
# gives them. Each loop is bounded by its chunks.

push_items : Cbor.Items, List(List(U8)) -> List(Try(a, Errs)) where [a.Cbor.Parseable(Cbor.Error)]
push_items = |start, chunks| {
	var $d = start
	var $out = []
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r : { values : List(a), rest : Try(Cbor.Items, Errs) }
			r = $d.push(chunk)
			$out = $out.concat(r.values.map(|v| Ok(v)))
			match r.rest {
				Ok(next) => {
					$d = next
				}
				Err(e) => {
					$d = Cbor.Items.sequence({})
					$out = $out.append(Err(e))
					$going = Bool.False
				}
			}
		}
	}
	if $going {
		match $d.finish() {
			Ok(_) => {}
			Err(InvalidCbor(p)) => {
				$out = $out.append(Err(InvalidCbor(p)))
			}
			Err(MissingRequiredField(f)) => {
				$out = $out.append(Err(MissingRequiredField(f)))
			}
			Err(TooLarge(p)) => {
				$out = $out.append(Err(TooLarge(p)))
			}
		}
	}
	$out
}

push_entries : Cbor.Entries, List(List(U8)) -> List(Try((k, v), Errs)) where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error)]
push_entries = |start, chunks| {
	var $d = start
	var $out = []
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r : { values : List((k, v)), rest : Try(Cbor.Entries, Errs) }
			r = $d.push(chunk)
			$out = $out.concat(r.values.map(|v| Ok(v)))
			match r.rest {
				Ok(next) => {
					$d = next
				}
				Err(e) => {
					$d = Cbor.Entries.map({})
					$out = $out.append(Err(e))
					$going = Bool.False
				}
			}
		}
	}
	if $going {
		match $d.finish() {
			Ok(_) => {}
			Err(InvalidCbor(p)) => {
				$out = $out.append(Err(InvalidCbor(p)))
			}
			Err(MissingRequiredField(f)) => {
				$out = $out.append(Err(MissingRequiredField(f)))
			}
			Err(TooLarge(p)) => {
				$out = $out.append(Err(TooLarge(p)))
			}
			Err(NotStreamable) => {
				$out = $out.append(Err(NotStreamable))
			}
		}
	}
	$out
}

push_bytes : Cbor.ByteChunks, List(List(U8)) -> List(Try(List(U8), ChunkErrs))
push_bytes = |start, chunks| {
	var $d = start
	var $out = []
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r = $d.push(chunk)
			$out = $out.concat(r.values.map(|v| Ok(v)))
			match r.rest {
				Ok(next) => {
					$d = next
				}
				Err(InvalidCbor(p)) => {
					$d = Cbor.ByteChunks.new({})
					$out = $out.append(Err(InvalidCbor(p)))
					$going = Bool.False
				}
			}
		}
	}
	if $going {
		match $d.finish() {
			Ok(_) => {}
			Err(InvalidCbor(p)) => {
				$out = $out.append(Err(InvalidCbor(p)))
			}
		}
	}
	$out
}

push_text : Cbor.TextChunks, List(List(U8)) -> List(Try(Str, ChunkErrs))
push_text = |start, chunks| {
	var $d = start
	var $out = []
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r = $d.push(chunk)
			$out = $out.concat(r.values.map(|v| Ok(v)))
			match r.rest {
				Ok(next) => {
					$d = next
				}
				Err(InvalidCbor(p)) => {
					$d = Cbor.TextChunks.new({})
					$out = $out.append(Err(InvalidCbor(p)))
					$going = Bool.False
				}
			}
		}
	}
	if $going {
		match $d.finish() {
			Ok(_) => {}
			Err(InvalidCbor(p)) => {
				$out = $out.append(Err(InvalidCbor(p)))
			}
		}
	}
	$out
}

## A `read!` that gives the same chunk at each call (a platform read function with no end).
read_ones! : () => Try(List(U8), Fail)
read_ones! = || Ok([0x01])

## A `read!` at the end of its input.
read_end! : () => Try(List(U8), Fail)
read_end! = || Ok([])

## A `read!` that fails.
read_fail! : () => Try(List(U8), Fail)
read_fail! = || Err(Poison)

# The properties: each split gives the events of the push loop.

## `Items.array` (or `sequence`) with `from_stream` gives the events of `push_items` for each split of `bytes`.
items_agree! : Cbor.Items, List(U8), List(Try(a, Errs)) => Bool where [a.Cbor.Parseable(Cbor.Error), a.is_eq : a, a -> Bool]
items_agree! = |start, bytes, want| {
	var $all = push_items(start, [bytes]) == want
	for chunks in splits(bytes) {
		out : Stream(Try(a, Errs))
		out = start.from_stream(source(chunks))
		if drain!(out) != want or push_items(start, chunks) != want {
			$all = Bool.False
		}
	}
	$all
}

entries_agree! : Cbor.Entries, List(U8), List(Try((k, v), Errs)) => Bool where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error), k.is_eq : k, k -> Bool, v.is_eq : v, v -> Bool]
entries_agree! = |start, bytes, want| {
	var $all = push_entries(start, [bytes]) == want
	for chunks in splits(bytes) {
		out : Stream(Try((k, v), Errs))
		out = start.from_stream(source(chunks))
		if drain!(out) != want or push_entries(start, chunks) != want {
			$all = Bool.False
		}
	}
	$all
}

## `ByteChunks.from_stream` gives the pieces of the push loop for each split (the pieces depend on the split).
bytes_agree! : List(U8), Cbor.Options => Bool
bytes_agree! = |bytes, options| {
	var $all = Bool.True
	for chunks in splits(bytes) {
		start = Cbor.ByteChunks.new(options)
		if drain!(start.from_stream(source(chunks))) != push_bytes(start, chunks) {
			$all = Bool.False
		}
	}
	$all
}

text_agrees! : List(U8), Cbor.Options => Bool
text_agrees! = |bytes, options| {
	var $all = Bool.True
	for chunks in splits(bytes) {
		start = Cbor.TextChunks.new(options)
		if drain!(start.from_stream(source(chunks))) != push_text(start, chunks) {
			$all = Bool.False
		}
	}
	$all
}

## The pieces joined, and the last error.
joined : List(Try(List(U8), e)) -> Try(List(U8), e)
joined = |pieces|
	pieces.fold(
		Ok([]),
		|acc, piece|
			match (acc, piece) {
				(Ok(all), Ok(p)) => Ok(all.concat(p))
				(Ok(_), Err(e)) => Err(e)
				(Err(e), _) => Err(e)
			},
	)

Row : { id : U64, name : Str }

indefinite : Cbor.Options
indefinite = { allow: [IndefiniteLength] }

# The checks

## Each check: its name and its result.
checks! : {} => List((Str, Bool))
checks! = |_| {
	# 3 rows, 2 of them with a name cut by each split.
	rows = Cbor.encode([{ id: 1, name: "a" }, { id: 2, name: "€uro" }, { id: 300, name: "" }])
	row_list : List(Try(Row, Errs))
	row_list = [Ok({ id: 1, name: "a" }), Ok({ id: 2, name: "€uro" }), Ok({ id: 300, name: "" })]

	# Items: splits, errors, the end of the source.
	u64s : List(Try(U64, Errs))
	u64s = [Ok(1), Ok(2), Ok(3)]
	no_u64 : List(Try(U64, Errs))
	no_u64 = []
	type_error : List(Try(U64, Errs))
	type_error = [Ok(1), Err(InvalidCbor(2))]
	cut : List(Try(U64, Errs))
	cut = [Ok(1), Err(InvalidCbor(0))]
	extra : List(Try(U64, Errs))
	extra = [Ok(1), Err(InvalidCbor(2))]
	empty_array : List(Try(U64, Errs))
	empty_array = [Err(InvalidCbor(0))]
	source_err : List(Try(U64, Errs))
	source_err = [Ok(1), Err(Input(Poison))]
	lazy_items : List(Try(U64, Errs))
	lazy_items = [Ok(1), Ok(2), Err(Input(Poison))]
	value_items : List(Try(Cbor.Value, Errs))
	value_items = [Ok(Cbor.Value.Int(Cbor.IntValue.from_u64(1))), Ok(Cbor.Value.Text("a")), Err(InvalidCbor(4))]

	from_bad : Stream(Try(U64, Errs))
	from_bad = Cbor.Items.array({}).from_stream(source([hex("8301f6"), hex("02")]))
	from_bad_poison : Stream(Try(U64, Errs))
	from_bad_poison = Cbor.Items.array({}).from_stream(failing([hex("8301f602")]))
	from_err : Stream(Try(U64, Errs))
	from_err = Cbor.Items.array({}).from_stream(failing([hex("8201")]))
	from_err_first : Stream(Try(U64, Errs))
	from_err_first = Cbor.Items.array({}).from_stream(failing([]))
	from_lazy : Stream(Try(U64, Errs))
	from_lazy = Cbor.Items.sequence({}).from_stream(failing([hex("0102")]))
	from_lazy_cut : Stream(Try(U64, Errs))
	from_lazy_cut = Cbor.Items.array({}).from_stream(failing([hex("83"), hex("01"), hex("0203")]))
	from_empty : Stream(Try(U64, Errs))
	from_empty = Cbor.Items.array({}).from_stream(source([]))
	from_empty_seq : Stream(Try(U64, Errs))
	from_empty_seq = Cbor.Items.sequence({}).from_stream(source([]))
	from_skip : Stream(Try(U64, Errs))
	from_skip = Cbor.Items.array({}).from_stream(source([hex("83"), [], hex("01"), [], hex("0203")]).drop_if(|c| c == Ok([])))
	from_first : Stream(Try(U64, Errs))
	from_first = Cbor.Items.array({}).from_stream(failing([hex("8301"), hex("02")])).take_first(1)
	from_too_large : Stream(Try(List(U64), Errs))
	from_too_large = Cbor.Items.array({ max_buffer: 4 }).from_stream(source([hex("81"), hex("8401"), hex("0203"), hex("04")]))
	too_large : List(Try(List(U64), Errs))
	too_large = [Err(TooLarge(1))]

	# chunk_source: a read! function as a source.
	from_ones : Stream(Try(U64, Errs))
	from_ones = Cbor.Items.sequence({}).from_stream(Cbor.chunk_source(read_ones!)).take_first(3)
	from_read_fail : Stream(Try(U64, Errs))
	from_read_fail = Cbor.Items.sequence({}).from_stream(Cbor.chunk_source(read_fail!))
	from_many : Stream(Try(U64, Errs))
	from_many = Cbor.Items.sequence({}).from_stream(failing([List.repeat(0x01, 1000)]))
	many : List(Try(U64, Errs))
	many = List.repeat(Ok(1), 1000).append(Err(Input(Poison)))
	from_before : Stream(Try(U64, Errs))
	from_before = Cbor.Items.sequence({}).from_stream(failing([hex("01021c")]))

	# Entries.
	map_ab = hex("a2616101616202")
	ab : List(Try((Str, U64), Errs))
	ab = [Ok(("a", 1)), Ok(("b", 2))]
	dup : List(Try((Str, U64), Errs))
	dup = [Ok(("a", 1)), Err(InvalidCbor(4))]
	last_any : List(Try((Str, U64), Errs))
	last_any = [Err(NotStreamable)]
	entry_err : List(Try((Str, U64), Errs))
	entry_err = [Ok(("a", 1)), Err(Input(Poison))]
	from_entry_err : Stream(Try((Str, U64), Errs))
	from_entry_err = Cbor.Entries.map({}).from_stream(failing([hex("a2616101"), hex("6162")]))
	from_entry_empty : Stream(Try((Str, U64), Errs))
	from_entry_empty = Cbor.Entries.map({}).from_stream(source([]))
	# NotStreamable from `finish`: an empty source gives no push.
	from_last_empty : Stream(Try((Str, U64), Errs))
	from_last_empty = Cbor.Entries.map({ duplicate_keys: Last }).from_stream(source([]))
	entry_empty : List(Try((Str, U64), Errs))
	entry_empty = [Err(InvalidCbor(0))]
	from_tagged_key : Stream(Try((Str, U64), Errs))
	from_tagged_key = Cbor.Entries.map({ ignore_tags: [6] }).from_stream(source([hex("a1c6616101")]))

	# ByteChunks and TextChunks.
	bytes_def = hex("4a00010203040506070809")
	bytes_indef = hex("5f4300010241034200ff")
	text_cut = hex("6a61e282ac62f09f8e8963")
	text_bad = hex("6461ff6262")

	# Writers.
	ints = values([1.U64, 2, 3], Bool.False)
	write_indef : List(Try(List(U8), WriteErrs))
	write_indef = drain!(Cbor.StreamWriter.array_stream(ints, Indefinite, {}))
	write_count : List(Try(List(U8), WriteErrs))
	write_count = drain!(Cbor.StreamWriter.array_stream(values([1.U64, 2, 3], Bool.False), Count(3), {}))
	write_more : List(Try(List(U8), WriteErrs))
	write_more = drain!(Cbor.StreamWriter.array_stream(values([1.U64, 2, 3], Bool.True), Count(2), {}))
	write_fewer : List(Try(List(U8), WriteErrs))
	write_fewer = drain!(Cbor.StreamWriter.array_stream(values([1.U64, 2, 3], Bool.True), Count(4), {}))
	write_fail : List(Try(List(U8), WriteErrs))
	write_fail = drain!(Cbor.StreamWriter.array_stream(values([1.U64], Bool.True), Indefinite, {}))
	write_empty : List(Try(List(U8), WriteErrs))
	write_empty = drain!(Cbor.StreamWriter.array_stream(values([], Bool.False), Indefinite, {}))
	write_zero : List(Try(List(U8), WriteErrs))
	write_zero = drain!(Cbor.StreamWriter.array_stream(values([], Bool.False), Count(0), {}))
	write_rows : List(Try(List(U8), WriteErrs))
	write_rows = drain!(Cbor.StreamWriter.array_stream(values([{ id: 1, name: "a" }, { id: 2, name: "€uro" }, { id: 300, name: "" }], Bool.False), Count(3), {}))
	write_seq : List(Try(List(U8), WriteErrs))
	write_seq = drain!(Cbor.StreamWriter.sequence_stream(values(["a", "bc"], Bool.False), {}))
	write_seq_empty : List(Try(List(U8), WriteErrs))
	write_seq_empty = drain!(Cbor.StreamWriter.sequence_stream(values([], Bool.False), {}))
	write_seq_fail : List(Try(List(U8), WriteErrs))
	write_seq_fail = drain!(Cbor.StreamWriter.sequence_stream(values([1.U64], Bool.True), {}))
	write_map : List(Try(List(U8), WriteErrs))
	write_map = drain!(Cbor.StreamWriter.map_stream(values([("a", 1.U64), ("b", 2)], Bool.False), Indefinite, {}))
	write_map_count : List(Try(List(U8), WriteErrs))
	write_map_count = drain!(Cbor.StreamWriter.map_stream(values([("a", 1.U64), ("b", 2)], Bool.False), Count(2), {}))
	write_unsorted : List(Try(List(U8), WriteErrs))
	write_unsorted = drain!(Cbor.StreamWriter.map_stream(values([("b", 1.U64), ("a", 2)], Bool.False), Indefinite, { key_order: Sorted }))
	write_dup : List(Try(List(U8), WriteErrs))
	write_dup = drain!(Cbor.StreamWriter.map_stream(values([("a", 1.U64), ("a", 2)], Bool.False), Indefinite, { key_order: Sorted }))
	write_bytes : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	write_bytes = drain!(Cbor.StreamWriter.bytes_stream(values([[1, 1, 1], [], [1, 1, 1]], Bool.False), Length(6)))
	write_bytes_fail : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	write_bytes_fail = drain!(Cbor.StreamWriter.bytes_stream(values([[1]], Bool.True), Indefinite))
	write_bytes_long : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	write_bytes_long = drain!(Cbor.StreamWriter.bytes_stream(values([[1, 1], [1, 1]], Bool.True), Length(3)))
	write_bytes_short : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	write_bytes_short = drain!(Cbor.StreamWriter.bytes_stream(values([[1, 1]], Bool.False), Length(3)))
	write_bytes_none : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	write_bytes_none = drain!(Cbor.StreamWriter.bytes_stream(values([], Bool.False), Length(0)))
	write_text : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	write_text = drain!(Cbor.StreamWriter.text_stream(values(["a", "€"], Bool.False), Indefinite))
	write_text_len : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	write_text_len = drain!(Cbor.StreamWriter.text_stream(values(["a", "€"], Bool.False), Length(4)))

	# A round trip: array_stream, then Items.from_stream on its pieces as chunks.
	round_source : Stream(Try(List(U8), Fail))
	round_source = Stream.from_iter(write_rows.map(|p| p.map_err(|_| Poison)).iter())
	round_rows : Stream(Try(Row, Errs))
	round_rows = Cbor.Items.array({}).from_stream(round_source)

	# A 9-byte head: the head of a byte string of 2^32 bytes, then the source fails, before any data.
	big_head : List(Try(List(U8), [CountMismatch, Input(Fail)]))
	big_head = drain!(Cbor.StreamWriter.bytes_stream(values([], Bool.True), Length(4_294_967_296)))

	[
		("items: rows, each split", items_agree!(Cbor.Items.array({}), rows, row_list)),
		("items: sequence, each split", items_agree!(Cbor.Items.sequence({}), hex("010203"), u64s)),
		("items: indefinite array, each split", items_agree!(Cbor.Items.array(indefinite), hex("9f010203ff"), u64s)),
		("items: 9-byte heads, each split", items_agree!(Cbor.Items.array({}), hex("821b00000001000000001b0000000100000001"), [Ok(4_294_967_296.U64), Ok(4_294_967_297)])),
		("items: type error ends the stream, each split", items_agree!(Cbor.Items.array({}), hex("8301f602"), type_error)),
		("items: Cbor.Value, error, each split", items_agree!(Cbor.Items.array({}), hex("830161611c"), value_items)),
		("items: cut array (finish at the end of the source)", items_agree!(Cbor.Items.array({}), hex("8201"), cut)),
		("items: bytes after the root", items_agree!(Cbor.Items.array({}), hex("810102"), extra)),
		("items: sequence of nothing", items_agree!(Cbor.Items.sequence({}), [], no_u64)),
		("items: an error ends the stream, later chunks unread", drain!(from_bad) == type_error),
		("items: an error ends the stream before a source error", drain!(from_bad_poison) == type_error),
		("items: source error after the items it cut", drain!(from_err) == source_err),
		("items: source error first", drain!(from_err_first) == [Err(Input(Poison))]),
		("items: lazy, each item before the next pull", drain!(from_lazy) == lazy_items),
		("items: lazy, cut items wait for chunks", drain!(from_lazy_cut) == [Ok(1), Ok(2), Ok(3), Err(Input(Poison))]),
		("items: empty source, array", drain!(from_empty) == empty_array),
		("items: empty source, sequence", drain!(from_empty_seq) == no_u64),
		("items: Skip steps of the source", drain!(from_skip) == u64s),
		("items: take_first(1)", drain!(from_first) == [Ok(1)]),
		("items: max_buffer", drain!(from_too_large) == too_large),
		("chunk_source: each read! is a chunk, lazily", drain!(from_ones) == [Ok(1), Ok(1), Ok(1)]),
		("chunk_source: an empty chunk ends", drain!(Cbor.Items.sequence({}).from_stream(Cbor.chunk_source(read_end!))) == no_u64),
		("chunk_source: an empty chunk ends, a cut array", drain!(Cbor.Items.array({}).from_stream(Cbor.chunk_source(read_end!))) == empty_array),
		("chunk_source: a read! error is the last item", drain!(Cbor.chunk_source(read_fail!)) == [Err(Poison)]),
		("chunk_source: a read! error is Input", drain!(from_read_fail) == [Err(Input(Poison))]),
		("items: one chunk of many items, one at a time", drain!(from_many) == many),
		("items: the items before an error in one chunk, then the error", drain!(from_before) == [Ok(1), Ok(2), Err(InvalidCbor(2))]),
		("entries: each split", entries_agree!(Cbor.Entries.map({}), map_ab, ab)),
		("entries: indefinite, each split", entries_agree!(Cbor.Entries.map(indefinite), hex("bf616101616202ff"), ab)),
		("entries: duplicate key, each split", entries_agree!(Cbor.Entries.map({}), hex("a2616101616102"), dup)),
		("entries: Last with Any", entries_agree!(Cbor.Entries.map({ duplicate_keys: Last }), map_ab, last_any)),
		("entries: Last with Sorted, each split", entries_agree!(Cbor.Entries.map({ duplicate_keys: Last, key_order: Sorted }), hex("a3616101616103616202"), [Ok(("a", 3)), Ok(("b", 2))])),
		("entries: source error", drain!(from_entry_err) == entry_err),
		("entries: empty source", drain!(from_entry_empty) == entry_empty),
		("entries: Last with Any, empty source: NotStreamable from finish", drain!(from_last_empty) == last_any),
		("entries: a key only in the form of the writer (a tag before it)", drain!(from_tagged_key) == [Err(InvalidCbor(1))]),
		("bytes: definite, each split", bytes_agree!(bytes_def, {})),
		("bytes: indefinite, each split", bytes_agree!(bytes_indef, indefinite)),
		("bytes: cut, each split", bytes_agree!(hex("4a000102"), {})),
		("bytes: text root, each split", bytes_agree!(hex("6161"), {})),
		("bytes: joined", joined(drain!(Cbor.ByteChunks.new({}).from_stream(source(bytes_def.chunks_of(3))))) == Ok(bytes_def.drop_first(1))),
		("bytes: source error after the data so far", drain!(Cbor.ByteChunks.new({}).from_stream(failing([hex("4300"), hex("01")]))) == [Ok([0]), Ok([1]), Err(Input(Poison))]),
		("bytes: empty source", drain!(Cbor.ByteChunks.new({}).from_stream(source([]))) == [Err(InvalidCbor(0))]),
		("bytes: empty byte string", drain!(Cbor.ByteChunks.new({}).from_stream(source([[0x40]]))) == []),
		("text: code points cut, each split", text_agrees!(text_cut, {})),
		("text: invalid UTF-8, each split", text_agrees!(text_bad, {})),
		("text: indefinite, each split", text_agrees!(hex("7f626161626262ff"), indefinite)),
		("text: euro sign cut", drain!(Cbor.TextChunks.new({}).from_stream(source([hex("6561e2"), hex("82ac62")]))) == [Ok("a"), Ok("€b")]),
		("text: source error", drain!(Cbor.TextChunks.new({}).from_stream(failing([hex("6261")]))) == [Ok("a"), Err(Input(Poison))]),
		("text: empty source", drain!(Cbor.TextChunks.new({}).from_stream(source([]))) == [Err(InvalidCbor(0))]),
		("array_stream: Indefinite", write_indef == [Ok([0x9f]), Ok([1]), Ok([2]), Ok([3]), Ok([0xff])]),
		("array_stream: Count", write_count == [Ok([0x83]), Ok([1]), Ok([2]), Ok([3])]),
		("array_stream: one item too many", write_more == [Ok([0x82]), Ok([1]), Ok([2]), Err(CountMismatch)]),
		("array_stream: too few (a source error first)", write_fewer == [Ok([0x84]), Ok([1]), Ok([2]), Ok([3]), Err(Input(Poison))]),
		("array_stream: too few", drain!(Cbor.StreamWriter.array_stream(values([1.U64], Bool.False), Count(2), {})) == [Ok([0x82]), Ok([1]), Err(CountMismatch)]),
		("array_stream: source error", write_fail == [Ok([0x9f]), Ok([1]), Err(Input(Poison))]),
		("array_stream: empty source", write_empty == [Ok([0x9f]), Ok([0xff])]),
		("array_stream: empty source, Count(0)", write_zero == [Ok([0x80])]),
		("array_stream: rows read back", drain!(round_rows) == row_list),
		("array_stream: the bytes of encode", joined(write_rows) == Ok(rows)),
		("sequence_stream", write_seq == [Ok(hex("6161")), Ok(hex("626263"))]),
		("sequence_stream: empty source", write_seq_empty == []),
		("sequence_stream: source error", write_seq_fail == [Ok([1]), Err(Input(Poison))]),
		("map_stream: Indefinite", write_map == [Ok([0xbf]), Ok(hex("616101")), Ok(hex("616202")), Ok([0xff])]),
		("map_stream: Count", write_map_count == [Ok([0xa2]), Ok(hex("616101")), Ok(hex("616202"))]),
		("map_stream: Sorted, a key out of order", write_unsorted == [Ok([0xbf]), Ok(hex("616201")), Err(KeyOutOfOrder)]),
		("map_stream: Sorted, an equal key", write_dup == [Ok([0xbf]), Ok(hex("616101")), Err(DuplicateMapKey)]),
		("bytes_stream: Length, chunks as they are", write_bytes == [Ok([0x46]), Ok([1, 1, 1]), Ok([1, 1, 1])]),
		("bytes_stream: source error", write_bytes_fail == [Ok([0x5f]), Ok([0x41, 1]), Err(Input(Poison))]),
		("bytes_stream: a byte too many", write_bytes_long == [Ok([0x43]), Ok([1, 1]), Err(CountMismatch)]),
		("bytes_stream: a byte too few", write_bytes_short == [Ok([0x43]), Ok([1, 1]), Err(CountMismatch)]),
		("bytes_stream: empty source", write_bytes_none == [Ok([0x40])]),
		("bytes_stream: 9-byte head", big_head == [Ok(hex("5b0000000100000000")), Err(Input(Poison))]),
		("text_stream: Indefinite", write_text == [Ok([0x7f]), Ok(hex("6161")), Ok(hex("63e282ac")), Ok([0xff])]),
		("text_stream: Length", write_text_len == [Ok([0x64]), Ok(hex("61")), Ok(hex("e282ac"))]),
	]
}

main! = |_args| {
	results = checks!({})
	failed = results.keep_if(|(_, ok)| !ok)
	for (name, _) in failed {
		echo!("FAIL ${name}\n")
	}
	echo!("stream_adapters: ${(results.len() - failed.len()).to_str()} of ${results.len().to_str()} checks pass\n")
	if (failed.is_empty()) Ok({}) else Err(Exit(1))
}
