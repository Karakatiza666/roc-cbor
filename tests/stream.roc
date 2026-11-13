app [] { pkg: "../src/main.roc" }

# The stream decoder Cbor.Items (0.5.0), through the public API of the package. `Items.array` gives the items of one
# top-level array, `Items.sequence` the root items of an RFC 8742 sequence, from bytes that come in chunks.
# The property of most tests: for each split of the input into chunks (chunks of 1 byte, each split in 2 parts and
# each split in 3 parts), the stream gives the same items and the same error as `parse_with` of a `List(a)`, or as
# a model of `parse_sequence_with` made of `parse_prefix_with`. Error positions are in the whole stream. The steps
# are `push` (the values that a chunk completes, and the next decoder or the error) and `finish`.

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

## The errors of each read in this file: a closed union, so that results compare with `==`.
Errs : [InvalidCbor(U64), TooLarge(U64), MissingRequiredField(Str)]

## The items that `start` gives when it gets `chunks` one at a time with `push`, then `finish`. `end` is `Ok` after
## `finish`, else the error. The loop is bounded by the chunks.
drive : Cbor.Items, List(List(U8)) -> { values : List(a), end : Try({}, Errs) } where [a.Cbor.Parseable(Cbor.Error)]
drive = |start, chunks| {
	var $items = start
	var $values = []
	var $end = Ok({})
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r : { values : List(a), rest : Try(Cbor.Items, Errs) }
			r = $items.push(chunk)
			$values = $values.concat(r.values)
			match r.rest {
				Ok(next) => {
					$items = next
				}
				Err(e) => {
					$items = Cbor.Items.sequence({})
					$end = Err(e)
					$going = Bool.False
				}
			}
		}
	}
	if $going {
		$end = finished($items.finish())
	}
	{ values: $values, end: $end }
}

## The error of `finish` in the union of the tests.
finished : Try({}, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64)]) -> Try({}, Errs)
finished = |r|
	match r {
		Ok(_) => Ok({})
		Err(InvalidCbor(p)) => Err(InvalidCbor(p))
		Err(MissingRequiredField(f)) => Err(MissingRequiredField(f))
		Err(TooLarge(p)) => Err(TooLarge(p))
	}

## The result of `drive` as one `Try`: the items, or the error.
stream : Cbor.Items, List(List(U8)) -> Try(List(a), Errs) where [a.Cbor.Parseable(Cbor.Error)]
stream = |start, chunks| {
	r = drive(start, chunks)
	match r.end {
		Ok(_) => Ok(r.values)
		Err(e) => Err(e)
	}
}

## The splits of `bytes`: chunks of 1 byte, each split in 2 parts, each split in 3 parts, and 1 byte chunks with an
## empty chunk between each two.
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

## Each split of `bytes` given to `start` gives `want`.
each_split : Cbor.Items, List(U8), Try(List(a), Errs) -> Bool where [a.Cbor.Parseable(Cbor.Error), a.is_eq : a, a -> Bool]
each_split = |start, bytes, want| {
	var $all = Bool.True
	for chunks in splits(bytes) {
		got : Try(List(a), Errs)
		got = stream(start, chunks)
		if got != want {
			$all = Bool.False
		}
	}
	$all
}

## `Items.array` agrees with `parse_with` as a `List(a)` for each split of `bytes`.
## `read` is `parse_with` for one item type (a `List(a)` cannot be parsed in a generic function).
array_agrees : List(U8), Cbor.Options, (List(U8), Cbor.Options -> Try(List(a), Errs)) -> Bool where [a.Cbor.Parseable(Cbor.Error), a.is_eq : a, a -> Bool]
array_agrees = |bytes, options, read| {
	want = read(bytes, options)
	each_split(Cbor.Items.array(options), bytes, want)
}

## A model of `parse_sequence_with`: `parse_prefix_with` for each item. The positions are in all of `bytes`.
sequence_model : List(U8), Cbor.Options -> Try(List(a), Errs) where [a.Cbor.Parseable(Cbor.Error)]
sequence_model = |bytes, options| {
	var $rest = bytes
	var $values = []
	while !$rest.is_empty() {
		at = bytes.len() - $rest.len()
		r : Try({ value : a, rest : List(U8) }, Errs)
		r = Cbor.parse_prefix_with($rest, options)
		match r {
			Ok(one) => {
				$values = $values.append(one.value)
				$rest = one.rest
			}
			Err(InvalidCbor(p)) => return Err(InvalidCbor(at + p))
			Err(e) => return Err(e)
		}
	}
	Ok($values)
}

## `Items.sequence` and `parse_sequence_with` agree with the model for each split of `bytes`.
sequence_agrees : List(U8), Cbor.Options, (List(U8), Cbor.Options -> Try(List(a), Errs)) -> Bool where [a.Cbor.Parseable(Cbor.Error), a.is_eq : a, a -> Bool]
sequence_agrees = |bytes, options, _read| {
	want : Try(List(a), Errs)
	want = sequence_model(bytes, options)
	whole : Try(List(a), Errs)
	whole = Cbor.parse_sequence_with(bytes, options)
	whole == want and each_split(Cbor.Items.sequence(options), bytes, want)
}

## `each_split` with items of the type U64.
split_u64s : Cbor.Items, List(U8), Try(List(U64), Errs) -> Bool
split_u64s = |start, bytes, want| each_split(start, bytes, want)

## `array_agrees` for `bytes` and for each prefix of it (a cut input).
array_prefixes_agree : List(U8), Cbor.Options, (List(U8), Cbor.Options -> Try(List(a), Errs)) -> Bool where [a.Cbor.Parseable(Cbor.Error), a.is_eq : a, a -> Bool]
array_prefixes_agree = |bytes, options, type| {
	var $all = Bool.True
	for n in 0..=bytes.len() {
		if !array_agrees(bytes.take_first(n), options, type) {
			$all = Bool.False
		}
	}
	$all
}

## `sequence_agrees` for `bytes` and for each prefix of it.
sequence_prefixes_agree : List(U8), Cbor.Options, (List(U8), Cbor.Options -> Try(List(a), Errs)) -> Bool where [a.Cbor.Parseable(Cbor.Error), a.is_eq : a, a -> Bool]
sequence_prefixes_agree = |bytes, options, type| {
	var $all = Bool.True
	for n in 0..=bytes.len() {
		if !sequence_agrees(bytes.take_first(n), options, type) {
			$all = Bool.False
		}
	}
	$all
}

Row : { id : U64, name : Str }

rows : List(U8)
rows = Cbor.encode([{ id: 1, name: "a" }, { id: 300, name: "bb" }, { id: 70000, name: "ccc" }])

## `parse_with` for each item type of the tests. Only the type matters to `sequence_agrees`.
u64s : List(U8), Cbor.Options -> Try(List(U64), Errs)
u64s = |b, o| Cbor.parse_with(b, o)

texts : List(U8), Cbor.Options -> Try(List(Str), Errs)
texts = |b, o| Cbor.parse_with(b, o)

row_type : List(U8), Cbor.Options -> Try(List(Row), Errs)
row_type = |b, o| Cbor.parse_with(b, o)

values : List(U8), Cbor.Options -> Try(List(Cbor.Value), Errs)
values = |b, o| Cbor.parse_with(b, o)

indefinite : Cbor.Options
indefinite = { allow: [IndefiniteLength] }

# Each split gives the same items as one chunk

## Integers with heads of 1, 2, 3, 5 and 9 bytes, in a definite and an indefinite array, and as a sequence.
expect {
	items = "0018181901001a000100001b0000000100000000"
	array_prefixes_agree(hex("85${items}"), {}, u64s) and array_prefixes_agree(hex("9f${items}ff"), indefinite, u64s) and sequence_prefixes_agree(hex(items), {}, u64s)
}

## Records, and each cut of them.
expect array_prefixes_agree(rows, {}, row_type)

## The records as a sequence (no array head) give the same items as parse_sequence_with, for each cut.
expect sequence_prefixes_agree(rows.drop_first(1), {}, row_type)

## Text with code points of 2, 3 and 4 bytes, cut at each offset.
expect array_prefixes_agree(hex("8362c3a963e282ac64f09f9880"), {}, texts)

## Nested items as Cbor.Value: arrays, maps, tags, an indefinite text, a float.
expect array_prefixes_agree(hex("84a2616101616282020381c1007f6161ff"), indefinite, values) and array_prefixes_agree(hex("82fb3ff199999999999a80"), {}, values)

## The values of the stream, and End.
expect {
	r : Try(List(Row), Errs)
	r = stream(Cbor.Items.array({}), [rows.take_first(5), rows.drop_first(5)])
	r == Ok([{ id: 1, name: "a" }, { id: 300, name: "bb" }, { id: 70000, name: "ccc" }])
}

# Empty input, an empty array, no finish

## An empty sequence is Ok; an empty input for an array is the error of `parse_with` (at 0).
expect {
	a : Try(List(U64), Errs)
	a = stream(Cbor.Items.sequence({}), [])
	b : Try(List(U64), Errs)
	b = stream(Cbor.Items.array({}), [])
	c : Try(List(U64), Errs)
	c = stream(Cbor.Items.sequence({}), [[], []])
	a == Ok([]) and b == Err(InvalidCbor(0)) and c == Ok([])
}

## An empty array, definite and indefinite: no items, then the end.
expect array_agrees([0x80], {}, u64s) and array_agrees([0x9f, 0xff], indefinite, u64s)

## The stream of 80 is Ok([]), and of 9f then ff in two chunks with IndefiniteLength is Ok([]).
expect {
	a : Try(List(U64), Errs)
	a = stream(Cbor.Items.array({}), [[0x80]])
	b : Try(List(U64), Errs)
	b = stream(Cbor.Items.array(indefinite), [[0x9f], [0xff]])
	a == Ok([]) and b == Ok([])
}

## A push gives the items that its chunk completes, also the last item of a sequence and the end of the array, and
## the next decoder; the end of the input is only `finish`.
expect {
	a : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	a = Cbor.Items.sequence({}).push([0x01])
	b : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	b = Cbor.Items.array({}).push([0x80])
	match (a.rest, b.rest) {
		(Ok(x), Ok(y)) => a.values == [1] and b.values == [] and x.finish() == Ok({}) and y.finish() == Ok({}) and x.position() == 1 and y.position() == 1
		_ => Bool.False
	}
}

## position: after each item that `push` gave, and not after a cut item.
expect {
	a = Cbor.Items.sequence({})
	r1 : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	r1 = a.push([0x01, 0x19])
	match r1.rest {
		Ok(rest) => {
			r2 : { values : List(U64), rest : Try(Cbor.Items, Errs) }
			r2 = rest.push([0x01, 0x00])
			match r2.rest {
				Ok(last) => r1.values == [1] and r2.values == [256] and a.position() == 0 and rest.position() == 1 and last.position() == 4
				Err(_) => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## An empty chunk changes nothing: no values, the same position, and the same items after it. Also in a cut item.
expect {
	r1 : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	r1 = Cbor.Items.array({}).push([0x83, 0x01, 0x19])
	match r1.rest {
		Ok(d) => {
			r2 : { values : List(U64), rest : Try(Cbor.Items, Errs) }
			r2 = d.push([])
			match r2.rest {
				Ok(e) => {
					r3 : { values : List(U64), rest : Try(Cbor.Items, Errs) }
					r3 = e.push([0x01, 0x00, 0x02])
					fresh : { values : List(U64), rest : Try(Cbor.Items, Errs) }
					fresh = Cbor.Items.sequence({}).push([])
					r1.values == [1] and r2.values == [] and e.position() == d.position() and r3.values == [256, 2] and fresh.values == [] and fresh.rest.map_ok(|x| x.position()) == Ok(0)
				}
				Err(_) => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## A chunk of N items of 1 byte gives exactly N values from one push, and the next decoder holds no byte of them:
## its position is N, an empty push gives nothing, and the input can end there.
expect {
	n = 5000
	bytes = List.repeat(0x07, n)
	r : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	r = Cbor.Items.sequence({}).push(bytes)
	match r.rest {
		Ok(next) => {
			again : { values : List(U64), rest : Try(Cbor.Items, Errs) }
			again = next.push([])
			r.values.len() == n and r.values == List.repeat(7, n) and next.position() == n and again.values == [] and next.finish() == Ok({})
		}
		Err(_) => Bool.False
	}
}

## The items before an error come back in `values` of the push that finds the error, with the error in `rest`.
expect {
	r : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	r = Cbor.Items.sequence({}).push(hex("01021c03"))
	s : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	s = Cbor.Items.array({}).push(hex("8301026161"))
	r.values == [1, 2] and r.rest.map_ok(|_| {}) == Err(InvalidCbor(2)) and s.values == [1, 2] and s.rest.map_ok(|_| {}) == Err(InvalidCbor(3))
}

## finish of a cut item: the error at the cut head, or at the open array (one truncation rule), in the whole stream.
expect {
	cut_head : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	cut_head = Cbor.Items.sequence({}).push([0x01, 0x02, 0x19, 0x01])
	cut_array : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	cut_array = Cbor.Items.array({}).push([0x83, 0x01])
	cut_inner : { values : List(List(U64)), rest : Try(Cbor.Items, Errs) }
	cut_inner = Cbor.Items.sequence({}).push([0x81, 0x01, 0x82, 0x01])
	match (cut_head.rest, cut_array.rest, cut_inner.rest) {
		(Ok(a), Ok(b), Ok(c)) => a.finish() == Err(InvalidCbor(2)) and b.finish() == Err(InvalidCbor(0)) and c.finish() == Err(InvalidCbor(2)) and cut_inner.values == [[1]]
		_ => Bool.False
	}
}

## A decoder that is kept and given to push again gives the same items (it is copied, not changed).
expect {
	r : { values : List(U64), rest : Try(Cbor.Items, Errs) }
	r = Cbor.Items.sequence({}).push([0x01, 0x19, 0x01])
	match r.rest {
		Ok(d) => {
			x : { values : List(U64), rest : Try(Cbor.Items, Errs) }
			x = d.push([0x00])
			y : { values : List(U64), rest : Try(Cbor.Items, Errs) }
			y = d.push([0x02])
			x.values == [256] and y.values == [258] and d.position() == 1
		}
		Err(_) => Bool.False
	}
}

# Bytes after the array

## An error at the first extra byte, as in parse_with, also in a later chunk.
expect array_agrees(hex("820102ff"), {}, u64s) and array_agrees(hex("82010203"), {}, u64s) and array_agrees(hex("9f0102ff00"), indefinite, u64s)

## The chunks 82 01 02, then an empty chunk, then 03: the items 1 and 2, then an error at byte 3.
expect {
	r = drive(Cbor.Items.array({}), [[0x82, 0x01, 0x02], [], [0x03]])
	got : List(U64)
	got = r.values
	got == [1, 2] and r.end == Err(InvalidCbor(3))
}

# Indefinite length

## An indefinite root array without IndefiniteLength is an error at its head; a break in a definite array is an error.
expect {
	a : Try(List(U64), Errs)
	a = stream(Cbor.Items.array({}), [[0x9f, 0x01, 0xff]])
	a == Err(InvalidCbor(0)) and array_agrees(hex("9f01ff"), {}, u64s) and array_agrees(hex("8201ff"), indefinite, u64s)
}

## An indefinite item in a sequence needs IndefiniteLength, as in parse_sequence_with.
expect sequence_agrees(hex("019f02ff03"), {}, values) and sequence_agrees(hex("019f02ff03"), indefinite, values)

# Root of another type, and tags before the root

## A map, a text and a byte string at the root: an error at the root head.
expect {
	a : Try(List(U64), Errs)
	a = stream(Cbor.Items.array({}), [[0xa0]])
	b : Try(List(U64), Errs)
	b = stream(Cbor.Items.array({}), [[0x61, 0x61]])
	c : Try(List(U64), Errs)
	c = stream(Cbor.Items.array({}), [[0x41, 0x01]])
	a == Err(InvalidCbor(0)) and b == Err(InvalidCbor(0)) and c == Err(InvalidCbor(0)) and array_agrees([0xa0], {}, u64s) and array_agrees([0x61, 0x61], {}, u64s)
}

## ignore_tags: the tags before the root are skipped. A tag not in the list is an error at the tag.
expect array_prefixes_agree(hex("c6d865820102"), { ignore_tags: [6, 101] }, u64s)

## c6 then c7 81 01 in two chunks with ignore_tags [6]: the unlisted tag 7 is an error at byte 1, the same as parse_with.
expect {
	a : Try(List(U64), Errs)
	a = stream(Cbor.Items.array({ ignore_tags: [6] }), [[0xc6], [0xc7, 0x81, 0x01]])
	a == Err(InvalidCbor(1)) and array_agrees(hex("c6c78101"), { ignore_tags: [6] }, u64s)
}

# Errors at stream positions

## A type error in the third record: items 1 and 2, then the error at its position in the stream, for each split.
expect {
	bad = Cbor.encode([{ id: 1, name: "a" }, { id: 2, name: "b" }]).concat(Cbor.encode({ id: "x", name: "c" }))
	bytes = [0x83].concat(bad.drop_first(1))
	want : Try(List(Row), Errs)
	want = Cbor.parse(bytes)
	r = drive(Cbor.Items.array({}), bytes.chunks_of(3))
	got : List(Row)
	got = r.values
	want == Err(InvalidCbor(29)) and got == [{ id: 1, name: "a" }, { id: 2, name: "b" }] and r.end == Err(InvalidCbor(29)) and array_agrees(bytes, {}, row_type)
}

## A missing field and an ill-formed byte in a later chunk, in a sequence.
expect {
	missing = Cbor.encode({ id: 1, name: "a" }).concat(Cbor.encode({ id: 2 }))
	ill = hex("0102031c")
	cut : Try(List(U64), Errs)
	cut = stream(Cbor.Items.sequence({}), [[0x01], [0x02, 0x03], [0x1c]])
	sequence_prefixes_agree(missing, {}, row_type) and sequence_agrees(ill, {}, u64s) and cut == Err(InvalidCbor(3))
}

## A header item of another type, then items of a type: a `push` for each type.
expect {
	head = Cbor.encode("rows-v1")
	bytes = Cbor.encode({ id: 7, name: "x" }).concat(Cbor.encode({ id: 8, name: "y" }))
	h : { values : List(Str), rest : Try(Cbor.Items, Errs) }
	h = Cbor.Items.sequence({}).push(head)
	match h.rest {
		Ok(rest) => {
			r : Try(List(Row), Errs)
			r = stream(rest, [bytes.take_first(5), bytes.drop_first(5)])
			h.values == ["rows-v1"] and r == Ok([{ id: 7, name: "x" }, { id: 8, name: "y" }])
		}
		Err(_) => Bool.False
	}
}

# max_buffer and TooLarge

## An item of exactly max_buffer bytes is Ok. One byte more is TooLarge at the start of the item, for each split.
expect {
	bytes = hex("00190100")
	a : Try(List(U64), Errs)
	a = Cbor.parse_sequence_with(bytes, { max_buffer: 2 })
	split_u64s(Cbor.Items.sequence({ max_buffer: 3 }), bytes, Ok([0, 256])) and split_u64s(Cbor.Items.sequence({ max_buffer: 2 }), bytes, Err(TooLarge(1))) and a == Ok([0, 256])
}

## In an array: the position is in the stream.
expect split_u64s(Cbor.Items.array({ max_buffer: 3 }), hex("821964001a00010000"), Err(TooLarge(4))) and split_u64s(Cbor.Items.array({ max_buffer: 3 }), hex("8219640019010000"), Err(InvalidCbor(7)))

## A cut item of max_buffer bytes is the error of a cut item, not TooLarge: no more bytes exist.
expect split_u64s(Cbor.Items.sequence({ max_buffer: 2 }), hex("001901"), Err(InvalidCbor(1)))

## An ill-formed byte after max_buffer bytes of an item: TooLarge (the walk sees max_buffer bytes). In them: InvalidCbor.
expect split_u64s(Cbor.Items.sequence({ max_buffer: 2 }), hex("82011c"), Err(TooLarge(0))) and split_u64s(Cbor.Items.sequence({ max_buffer: 3 }), hex("82011c"), Err(InvalidCbor(2)))

## A large item in chunks of 1 KiB: the decoder keeps it while it is at most max_buffer bytes, and refuses the next one.
expect {
	big = Cbor.encode(List.repeat(7.U8, 9000))
	bytes = big.concat(Cbor.encode(List.repeat(7.U8, 10000)))
	r = drive(Cbor.Items.sequence({ max_buffer: 9003 }), bytes.chunks_of(1024))
	got : List(List(U8))
	got = r.values
	got == [List.repeat(7, 9000)] and r.end == Err(TooLarge(9003))
}

# Options inside items

## max_depth 512: an item with 511 levels in the array is Ok, 512 is an error at the 513th head; one root tag takes one more level.
expect {
	deep = |n| List.repeat(0x81, n).append(0x00)
	ok = [0x81].concat(deep(511))
	over = [0x81].concat(deep(512))
	tagged = [0xc6, 0x81].concat(deep(510))
	tagged_over = [0xc6, 0x81].concat(deep(511))
	t : Cbor.Options
	t = { ignore_tags: [6] }
	a : Try(List(Cbor.Value), Errs)
	a = stream(Cbor.Items.array({}), ok.chunks_of(100))
	b : Try(List(Cbor.Value), Errs)
	b = stream(Cbor.Items.array({}), over.chunks_of(100))
	c : Try(List(Cbor.Value), Errs)
	c = stream(Cbor.Items.array(t), tagged.chunks_of(100))
	d : Try(List(Cbor.Value), Errs)
	d = stream(Cbor.Items.array(t), tagged_over.chunks_of(100))
	a.is_ok() and b == Err(InvalidCbor(512)) and c.is_ok() and d == Err(InvalidCbor(512)) and array_agrees(hex("81818180"), { max_depth: 3 }, values) and array_agrees(hex("c681818180"), { max_depth: 4, ignore_tags: [6] }, values)
}

## max_items: the array and each item in it count in the whole root. In a sequence, each item counts alone.
expect {
	whole = array_agrees(hex("83010203"), { max_items: 3 }, u64s) and array_agrees(hex("83010203"), { max_items: 4 }, u64s)
	a : Try(List(U64), Errs)
	a = stream(Cbor.Items.array({ max_items: 3 }), [[0x83, 0x01], [0x02, 0x03]])
	b : Try(List(List(U64)), Errs)
	b = stream(Cbor.Items.sequence({ max_items: 3 }), [hex("820102820304")])
	c : Try(List(List(U64)), Errs)
	c = stream(Cbor.Items.sequence({ max_items: 2 }), [hex("820102")])
	whole and a == Err(InvalidCbor(3)) and b == Ok([[1, 2], [3, 4]]) and c == Err(InvalidCbor(2)) and sequence_agrees(hex("820102820304"), { max_items: 2 }, values)
}

## duplicate_keys and key_order inside items, the same as parse_with.
expect {
	dup = hex("81a2616101616102")
	out_of_order = hex("81a2616201616102")
	a : Try(List(Cbor.Value), Errs)
	a = stream(Cbor.Items.array({}), dup.chunks_of(1))
	b : Try(List({ a : U64 }), Errs)
	b = stream(Cbor.Items.array({ duplicate_keys: Last }), dup.chunks_of(1))
	c : Try(List({ a : U64 }), Errs)
	c = stream(Cbor.Items.array({ duplicate_keys: First }), dup.chunks_of(2))
	d : Try(List(Cbor.Value), Errs)
	d = stream(Cbor.Items.array({ key_order: Sorted }), out_of_order.chunks_of(1))
	a == Err(InvalidCbor(5)) and b == Ok([{ a: 2 }]) and c == Ok([{ a: 1 }]) and d == Err(InvalidCbor(5)) and array_agrees(dup, { duplicate_keys: Last }, values) and array_agrees(out_of_order, { key_order: Sorted, duplicate_keys: First }, values)
}

## Leniencies inside items: BoolFromInt, PaddedNumbers, and a strict read without them.
expect {
	ints = hex("82011801")
	a : Try(List(Bool), Errs)
	a = stream(Cbor.Items.array({ allow: [BoolFromInt] }), [hex("820100")])
	b : Try(List(Bool), Errs)
	b = stream(Cbor.Items.array({}), [hex("820100")])
	c : Try(List(U64), Errs)
	c = stream(Cbor.Items.array({ allow: [PaddedNumbers] }), ints.chunks_of(1))
	d : Try(List(U64), Errs)
	d = stream(Cbor.Items.array({}), ints.chunks_of(1))
	a == Ok([Bool.True, Bool.False]) and b == Err(InvalidCbor(1)) and c == Ok([1, 1]) and d == Err(InvalidCbor(2))
}

## Internal tag unions inside items, and Cbor.Raw items with the bytes of each item.
Pay : [Cash, Card({ last4 : Str }), Check(U64)]

## Three internal tag unions (kind and value keys) in 1-byte chunks read as Cash, Card({ last4: "42" }) and Check(7).
expect {
	kind : Cbor.Options
	kind = { unions: Internal({ tag: "kind", content: "value" }) }
	bytes = hex("83a1646b696e646443617368a2646b696e646443617264656c61737434623432a2646b696e6465436865636b6576616c756507")
	a : Try(List(Pay), Errs)
	a = stream(Cbor.Items.array(kind), bytes.chunks_of(1))
	pays : List(U8), Cbor.Options -> Try(List(Pay), Errs)
	pays = |b, o| Cbor.parse_with(b, o)
	a == Ok([Cash, Card({ last4: "42" }), Check(7)]) and array_agrees(bytes, kind, pays)
}

## Cbor.Raw items in 2-byte chunks give the bytes of each item: 01, 81 02 and a1 61 61 61 62.
expect {
	bytes = hex("83018102a161616162")
	a : Try(List(Cbor.Raw), Errs)
	a = stream(Cbor.Items.array({}), bytes.chunks_of(2))
	a.map_ok(|l| l.map(|r| r.to_bytes())) == Ok([[0x01], [0x81, 0x02], hex("a161616162")])
}
