app [] { pkg: "../src/main.roc" }

# The stream decoder Cbor.Entries (0.5.0), through the public API of the package: the entries of one top-level map,
# from bytes that come in chunks. The property of most tests: for each split of the input into chunks (chunks of 1
# byte, 1-byte chunks with empty chunks between them, each split in 2 parts and each split in 3 parts), the stream
# gives the same entries and the same error as `parse_with` of a `Dict(k, v)`. Error positions are in the whole stream.

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
Errs : [InvalidCbor(U64), TooLarge(U64), NotStreamable, MissingRequiredField(Str)]

## The entries that `start` gives when it gets `chunks` one at a time with `push`, then `finish`. `end` is `Ok` after
## `finish`, else the error. The loop is bounded by the chunks.
drive : Cbor.Entries, List(List(U8)) -> { entries : List((k, v)), end : Try({}, Errs) } where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error)]
drive = |start, chunks| {
	var $d = start
	var $entries = []
	var $end = Ok({})
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r : { values : List((k, v)), rest : Try(Cbor.Entries, Errs) }
			r = $d.push(chunk)
			$entries = $entries.concat(r.values)
			match r.rest {
				Ok(next) => {
					$d = next
				}
				Err(e) => {
					$d = Cbor.Entries.map({})
					$end = Err(e)
					$going = Bool.False
				}
			}
		}
	}
	if $going {
		$end = finished($d.finish())
	}
	{ entries: $entries, end: $end }
}

## The error of `finish` in the union of the tests.
finished : Try({}, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64), NotStreamable]) -> Try({}, Errs)
finished = |r|
	match r {
		Ok(_) => Ok({})
		Err(InvalidCbor(p)) => Err(InvalidCbor(p))
		Err(MissingRequiredField(f)) => Err(MissingRequiredField(f))
		Err(TooLarge(p)) => Err(TooLarge(p))
		Err(NotStreamable) => Err(NotStreamable)
	}

## The result of `drive` as one `Try`: the entries, or the error.
stream : Cbor.Entries, List(List(U8)) -> Try(List((k, v)), Errs) where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error)]
stream = |start, chunks| {
	r = drive(start, chunks)
	match r.end {
		Ok(_) => Ok(r.entries)
		Err(e) => Err(e)
	}
}

## The splits of `bytes`: one chunk, chunks of 1 byte, 1-byte chunks with an empty chunk after each, each split in
## 2 parts, each split in 3 parts.
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
each_split : Cbor.Entries, List(U8), Try(List((k, v)), Errs) -> Bool where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error), k.is_eq : k, k -> Bool, v.is_eq : v, v -> Bool]
each_split = |start, bytes, want| {
	var $all = Bool.True
	for chunks in splits(bytes) {
		got : Try(List((k, v)), Errs)
		got = stream(start, chunks)
		if got != want {
			$all = Bool.False
		}
	}
	$all
}

## `Entries.map` agrees with `parse_with` as a `Dict(k, v)` for each split of `bytes`. `read` is `parse_with` of one
## `Dict` type, as the list of its entries (a `Dict` cannot be parsed in a generic function).
map_agrees : List(U8), Cbor.Options, (List(U8), Cbor.Options -> Try(List((k, v)), Errs)) -> Bool where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error), k.is_eq : k, k -> Bool, v.is_eq : v, v -> Bool]
map_agrees = |bytes, options, read| each_split(Cbor.Entries.map(options), bytes, read(bytes, options))

## `each_split` with entries of the types Str and U64.
split_str_u64 : Cbor.Entries, List(U8), Try(List((Str, U64)), Errs) -> Bool
split_str_u64 = |start, bytes, want| each_split(start, bytes, want)

## `map_agrees` for `bytes` and for each prefix of it (a cut input).
prefixes_agree : List(U8), Cbor.Options, (List(U8), Cbor.Options -> Try(List((k, v)), Errs)) -> Bool where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error), k.is_eq : k, k -> Bool, v.is_eq : v, v -> Bool]
prefixes_agree = |bytes, options, read| {
	var $all = Bool.True
	for n in 0..=bytes.len() {
		if !map_agrees(bytes.take_first(n), options, read) {
			$all = Bool.False
		}
	}
	$all
}

## `parse_with` for each Dict type of the tests, as the list of its entries.
str_u64 : List(U8), Cbor.Options -> Try(List((Str, U64)), Errs)
str_u64 = |b, o| {
	r : Try(Dict(Str, U64), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

u64_str : List(U8), Cbor.Options -> Try(List((U64, Str)), Errs)
u64_str = |b, o| {
	r : Try(Dict(U64, Str), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

u64_u64 : List(U8), Cbor.Options -> Try(List((U64, U64)), Errs)
u64_u64 = |b, o| {
	r : Try(Dict(U64, U64), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

f64_u64 : List(U8), Cbor.Options -> Try(List((F64, U64)), Errs)
f64_u64 = |b, o| {
	r : Try(Dict(F64, U64), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

bool_u64 : List(U8), Cbor.Options -> Try(List((Bool, U64)), Errs)
bool_u64 = |b, o| {
	r : Try(Dict(Bool, U64), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

str_value : List(U8), Cbor.Options -> Try(List((Str, Cbor.Value)), Errs)
str_value = |b, o| {
	r : Try(Dict(Str, Cbor.Value), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

Row : { id : U64, name : Str }

str_row : List(U8), Cbor.Options -> Try(List((Str, Row)), Errs)
str_row = |b, o| {
	r : Try(Dict(Str, Row), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

str_dict : List(U8), Cbor.Options -> Try(List((Str, Dict(Str, U64))), Errs)
str_dict = |b, o| {
	r : Try(Dict(Str, Dict(Str, U64)), Errs)
	r = Cbor.parse_with(b, o)
	r.map_ok(|d| d.to_list())
}

indefinite : Cbor.Options
indefinite = { allow: [IndefiniteLength] }

## { "a": 1, "bb": 300, "ccc": 70000 }
abc : List(U8)
abc = hex("a361610162626219012c636363631a00011170")

# Each split gives the entries of parse_with

## Text keys, and each cut of the map.
expect prefixes_agree(abc, {}, str_u64)

## Integer keys with heads of 1, 2, 3, 5 and 9 bytes.
expect prefixes_agree(hex("a50061611818616219010061631a0001000061641b00000001000000006165"), {}, u64_str)

## Records as values.
expect {
	bytes = Cbor.encode(Dict.from_list([("x", { id: 1, name: "a" }), ("y", { id: 300, name: "bb" })]))
	prefixes_agree(bytes, {}, str_row)
}

## The entries, in the order of the map.
expect {
	r : Try(List((Str, U64)), Errs)
	r = stream(Cbor.Entries.map({}), [abc.take_first(5), abc.drop_first(5)])
	r == Ok([("a", 1), ("bb", 300), ("ccc", 70000)])
}

## An empty map, definite and indefinite; an empty input is the error of parse_with (at 0).
expect {
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({}), [[0xa0]])
	b : Try(List((Str, U64)), Errs)
	b = stream(Cbor.Entries.map(indefinite), [[0xbf], [0xff]])
	c : Try(List((Str, U64)), Errs)
	c = stream(Cbor.Entries.map({}), [])
	a == Ok([]) and b == Ok([]) and c == Err(InvalidCbor(0)) and map_agrees([0xa0], {}, str_u64) and map_agrees([0xbf, 0xff], indefinite, str_u64)
}

## A push gives the entries that its chunk completes, also the last one of the map; the end is only `finish`.
expect {
	r : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
	r = Cbor.Entries.map({}).push(hex("a1616101"))
	match r.rest {
		Ok(d) => r.values == [("a", 1)] and d.position() == 4 and d.finish() == Ok({})
		Err(_) => Bool.False
	}
}

## position: after each entry that `push` gave (a key alone is not an entry), in the whole stream. An empty chunk
## changes nothing.
expect {
	r1 : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
	r1 = Cbor.Entries.map({}).push(hex("a2616101"))
	match r1.rest {
		Ok(rest) => {
			r2 : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
			r2 = rest.push(hex("6162"))
			match r2.rest {
				Ok(d2) => {
					r3 : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
					r3 = d2.push([])
					match r3.rest {
						Ok(d3) => {
							r4 : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
							r4 = d3.push(hex("190100"))
							match r4.rest {
								Ok(last) => r1.values == [("a", 1)] and r2.values == [] and r3.values == [] and rest.position() == 4 and d2.position() == 4 and d3.position() == 4 and r4.values == [("b", 256)] and last.position() == 9 and last.finish() == Ok({})
								Err(_) => Bool.False
							}
						}
						Err(_) => Bool.False
					}
				}
				Err(_) => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## The entries before an error come back in `values`. finish of a cut entry: the error at the open map, or at a cut
## head inside the value.
expect {
	r : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
	r = Cbor.Entries.map({}).push(hex("a361610161620261636161"))
	cut : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
	cut = Cbor.Entries.map({}).push(hex("a2616101616219"))
	inner : { values : List((Str, List(U64))), rest : Try(Cbor.Entries, Errs) }
	inner = Cbor.Entries.map({}).push(hex("a1616182"))
	errors = r.values == [("a", 1), ("b", 2)] and r.rest.map_ok(|_| {}) == Err(InvalidCbor(9))
	match (cut.rest, inner.rest) {
		(Ok(c), Ok(i)) => errors and cut.values == [("a", 1)] and c.finish() == Err(InvalidCbor(6)) and i.finish() == Err(InvalidCbor(3))
		_ => Bool.False
	}
}

## A chunk of N entries of 2 bytes (integer keys and values) gives exactly N entries from one push.
expect {
	n = 20
	var $bytes = [0xb4]
	for k in (0.U8).until(20) {
		$bytes = $bytes.append(k).append(0x07)
	}
	bytes = $bytes
	r : { values : List((U64, U64)), rest : Try(Cbor.Entries, Errs) }
	r = Cbor.Entries.map({}).push(bytes)
	match r.rest {
		Ok(d) => r.values.len() == n and r.values.get(19) == Ok((19, 7)) and d.position() == 41 and d.finish() == Ok({})
		Err(_) => Bool.False
	}
}

# Indefinite length

## An indefinite map with IndefiniteLength, each cut; without it, an error at the root head; a break in a
## definite map, or a break after a key, is an error.
expect prefixes_agree(hex("bf616101616202ff"), indefinite, str_u64)

## The indefinite map bf 61 61 01 61 62 02 ff with IndefiniteLength agrees with parse_with for the whole input and each cut.
expect {
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({}), [hex("bf616101ff")])
	a == Err(InvalidCbor(0)) and map_agrees(hex("bf616101ff"), {}, str_u64) and map_agrees(hex("a2616101ff"), indefinite, str_u64) and map_agrees(hex("bf6161ff"), indefinite, str_u64)
}

# Bytes after the map, root of another type, tags before the root

## An error at the first extra byte, also in a later chunk.
expect {
	r = drive(Cbor.Entries.map({}), [hex("a1616101"), [], [0x00]])
	got : List((Str, U64))
	got = r.entries
	got == [("a", 1)] and r.end == Err(InvalidCbor(4)) and map_agrees(hex("a161610100"), {}, str_u64) and map_agrees(hex("bf616101ff00"), indefinite, str_u64)
}

## An array, a text and a byte string at the root: an error at the root head.
expect {
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({}), [[0x80]])
	a == Err(InvalidCbor(0)) and map_agrees([0x80], {}, str_u64) and map_agrees([0x61, 0x61], {}, str_u64) and map_agrees([0x41, 0x01], {}, str_u64)
}

## ignore_tags: the tags before the root are skipped (each cut). A tag not in the list is an error at the tag.
expect prefixes_agree(hex("c6d865a1616101"), { ignore_tags: [6, 101] }, str_u64)

## c6 c7 a0 in two chunks with ignore_tags [6]: the unlisted tag 7 is an error at byte 1, the same as parse_with.
expect {
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({ ignore_tags: [6] }), [[0xc6], [0xc7, 0xa0]])
	a == Err(InvalidCbor(1)) and map_agrees(hex("c6c7a0"), { ignore_tags: [6] }, str_u64)
}

# Duplicate keys of the root map

## key_order: Any. Reject: the error at the second key. First: the later entry is walked, and not given.
## A cut input after a whole second key has two errors: the stream gives the key (it checks each key when the key is
## whole), parse_with the cut (its walk checks the keys of a map at the end of the map). Both reject the input.
expect {
	dup = hex("a3616101616202616103")
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({}), dup.chunks_of(1))
	b : Try(List((Str, U64)), Errs)
	b = stream(Cbor.Entries.map({ duplicate_keys: First }), dup.chunks_of(1))
	a == Err(InvalidCbor(7)) and b == Ok([("a", 1), ("b", 2)]) and prefixes_agree(dup.drop_last(2), {}, str_u64) and map_agrees(dup, {}, str_u64) and str_u64(dup.drop_last(1), {}) == Err(InvalidCbor(0)) and prefixes_agree(dup, { duplicate_keys: First }, str_u64)
}

## key_order: Any with Last: NotStreamable at the first push, before any byte, and at finish, for each split.
expect {
	start = Cbor.Entries.map({ duplicate_keys: Last })
	s : { values : List((Str, U64)), rest : Try(Cbor.Entries, Errs) }
	s = start.push([])
	none : List(U8)
	none = []
	is_not_streamable =
		match s.rest {
			Err(NotStreamable) => s.values == []
			_ => Bool.False
		}
	is_not_streamable and start.finish() == Err(NotStreamable) and split_str_u64(start, hex("a1616101"), Err(NotStreamable)) and split_str_u64(start, none, Err(NotStreamable))
}

## A duplicate key in a later chunk, with many keys between: the KeySet (sorted runs) finds it.
expect {
	# The keys in a mixed order (17 * i mod 40), so that each merge of two runs must sort.
	keys = (0.U64).until(40).fold([], |acc, i| acc.concat(Cbor.encode((17 * i) % 40)).concat(Cbor.encode(i)))
	ok = [0xb8, 40].concat(keys)
	dup = [0xb8, 41].concat(keys).concat([0x05, 0x00])
	a : Try(List((U64, U64)), Errs)
	a = stream(Cbor.Entries.map({}), ok.chunks_of(7))
	b : Try(List((U64, U64)), Errs)
	b = stream(Cbor.Entries.map({}), dup.chunks_of(7))
	c : Try(List((U64, U64)), Errs)
	c = stream(Cbor.Entries.map({ duplicate_keys: First }), dup.chunks_of(7))
	a == u64_u64(ok, {}) and a.is_ok() and b == Err(InvalidCbor(dup.len() - 2)) and b == u64_u64(dup, {}) and c == u64_u64(dup, { duplicate_keys: First })
}

## A key with a duplicate key in it is the Cbor.Value without the skipped entry: {"a": 0} and {"a": 0, "a": 0}
## are the same key, with key_order Any and Sorted (tests/value.roc and tests/key_order.roc: the same in parse_with).
expect {
	bytes = hex("a2a161610004a261610061610005")
	a : Try(List(({ a : U64 }, U64)), Errs)
	a = stream(Cbor.Entries.map({ duplicate_keys: First }), bytes.chunks_of(1))
	b : Try(List(({ a : U64 }, U64)), Errs)
	b = stream(Cbor.Entries.map({ key_order: Sorted, duplicate_keys: Last }), bytes.chunks_of(3))
	a == Ok([({ a: 0 }, 4)]) and b == Ok([({ a: 0 }, 5)])
}

## Keys that differ only in head width (PaddedNumbers) or float width are the same key (the canonical rule).
expect map_agrees(hex("a20101180102"), { allow: [PaddedNumbers] }, u64_u64) and map_agrees(hex("a2f93c0001fb3ff000000000000002"), {}, f64_u64) and map_agrees(hex("a2f93c0001fb3ff000000000000002"), { duplicate_keys: First }, f64_u64)

## key_order: Sorted. Reject: the error at the second key. A key less than the key before: an error at the key.
## "b" comes before "aa" (the shorter encoding first).
expect {
	dup = hex("a3616101616102616203")
	low = hex("a2616201616102")
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({ key_order: Sorted }), dup.chunks_of(1))
	b : Try(List((Str, U64)), Errs)
	b = stream(Cbor.Entries.map({ key_order: Sorted }), low.chunks_of(1))
	a == Err(InvalidCbor(4)) and b == Err(InvalidCbor(4)) and prefixes_agree(dup, { key_order: Sorted }, str_u64) and prefixes_agree(low, { key_order: Sorted, duplicate_keys: First }, str_u64) and map_agrees(hex("a261620162616102"), { key_order: Sorted }, str_u64)
}

## key_order: Sorted with First and Last: a run of 3 equal keys across chunk boundaries gives the first or the last
## of the run, for each split and each cut.
expect {
	run = hex("a4616101616102616103616204")
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({ key_order: Sorted, duplicate_keys: First }), run.chunks_of(3))
	b : Try(List((Str, U64)), Errs)
	b = stream(Cbor.Entries.map({ key_order: Sorted, duplicate_keys: Last }), run.chunks_of(3))
	a == Ok([("a", 1), ("b", 4)]) and b == Ok([("a", 3), ("b", 4)]) and prefixes_agree(run, { key_order: Sorted, duplicate_keys: First }, str_u64) and prefixes_agree(run, { key_order: Sorted, duplicate_keys: Last }, str_u64)
}

## Sorted and Last: the held entry is given at the end of the map, also of an indefinite map; a run at the end.
expect prefixes_agree(hex("bf616101616202616203ff"), { key_order: Sorted, duplicate_keys: Last, allow: [IndefiniteLength] }, str_u64)

## Sorted and Last: a dropped entry is not parsed (a type error in it is no error), as in parse_with.
expect {
	bytes = hex("a261616178616101")
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map({ key_order: Sorted, duplicate_keys: Last }), bytes.chunks_of(1))
	a == Ok([("a", 1)]) and map_agrees(bytes, { key_order: Sorted, duplicate_keys: Last }, str_u64)
}

## Duplicate keys inside a held value: the skips of the held entry come with it (Sorted, Last).
expect {
	bytes = hex("a26161a26178016178026162a0")
	a : Try(List((Str, Dict(Str, U64))), Errs)
	a = stream(Cbor.Entries.map({ key_order: Sorted, duplicate_keys: Last }), bytes.chunks_of(2))
	a.map_ok(|l| l.map(|(k, d)| (k, d.to_list()))) == Ok([("a", [("x", 2)]), ("b", [])]) and prefixes_agree(bytes, { key_order: Sorted, duplicate_keys: Last }, str_dict) and prefixes_agree(bytes, { duplicate_keys: First }, str_dict)
}

## The same as Cbor.Value values: a value reads both instances of an inner key when the skips are lost.
expect {
	bytes = hex("a26161a26178016178026162a0")
	sorted_last : Cbor.Options
	sorted_last = { key_order: Sorted, duplicate_keys: Last }
	a : Try(List((Str, Cbor.Value)), Errs)
	a = stream(Cbor.Entries.map(sorted_last), bytes.chunks_of(2))
	want : Try(Cbor.Value, Errs)
	want = Cbor.parse(hex("a1617802"))
	a.map_ok(|l| l.map(|(_, v)| Ok(v) == want)) == Ok([Bool.True, Bool.False]) and map_agrees(bytes, sorted_last, str_value)
}

## A key with a map in it is compared as its Cbor.Value (Sorted, Last): {0: h'', 0: 9} is {0: 9}, before
## {0: 0, 14: 0}. The held entry is given when the second key comes, and its key is not a Str: the error is at the
## first key (1), not an order error at the second key (7). (Fuzz input of the target stream, 0.5.0.)
expect {
	bytes = hex("a2a20040000900a200000e0000")
	options : Cbor.Options
	options = { key_order: Sorted, duplicate_keys: Last }
	a : Try(List((Str, U64)), Errs)
	a = stream(Cbor.Entries.map(options), bytes.chunks_of(1))
	a == Err(InvalidCbor(1)) and map_agrees(bytes, options, str_u64)
}

## Duplicate keys inside a key or a value are checked by the walk of the item, as in parse_with.
expect map_agrees(hex("a16161a2617801617802"), {}, str_value) and map_agrees(hex("a16161a2617801617802"), { key_order: Sorted }, str_value)

# The exact form of a key

## A key reads only in the form that the writer writes for its value: with BoolFromInt, the key 0 of a
## Dict(Bool, v) is an error, and a key with a tag of ignore_tags is an error. As in parse_with.
expect {
	a : Try(List((Bool, U64)), Errs)
	a = stream(Cbor.Entries.map({ allow: [BoolFromInt] }), [hex("a10001")])
	b : Try(List((Str, U64)), Errs)
	b = stream(Cbor.Entries.map({ ignore_tags: [6] }), [hex("a1c6616101")])
	c : Try(List((Bool, U64)), Errs)
	c = stream(Cbor.Entries.map({}), [hex("a1f401")])
	a == Err(InvalidCbor(1)) and a == bool_u64(hex("a10001"), { allow: [BoolFromInt] }) and b == Err(InvalidCbor(1)) and b == str_u64(hex("a1c6616101"), { ignore_tags: [6] }) and c == Ok([(Bool.False, 1)])
}

## A padded integer key reads with PaddedNumbers (the canonical form is the same). A float key 1.0 is not a U64 key.
expect map_agrees(hex("a1180102"), { allow: [PaddedNumbers] }, u64_u64) and map_agrees(hex("a1f93c0002"), { allow: [FloatToInt] }, u64_u64)

# Errors at stream positions, limits

## A type error in the third value: two entries, then the error at its position, for each split.
expect {
	bytes = hex("a361610161620261636178")
	r = drive(Cbor.Entries.map({}), bytes.chunks_of(3))
	got : List((Str, U64))
	got = r.entries
	got == [("a", 1), ("b", 2)] and r.end == Err(InvalidCbor(9)) and map_agrees(bytes, {}, str_u64)
}

## A missing field of a record value.
expect map_agrees(hex("a1617aa162696401"), {}, str_row)

## max_items: the map, each key and each value count in the whole root (with a root tag).
expect map_agrees(hex("a2616101616202"), { max_items: 4 }, str_u64) and map_agrees(hex("a2616101616202"), { max_items: 5 }, str_u64) and map_agrees(hex("c6a2616101616202"), { max_items: 5, ignore_tags: [6] }, str_u64)

## max_depth: the root map and its tags take levels.
expect map_agrees(hex("a16161818100"), { max_depth: 3 }, str_value) and map_agrees(hex("a16161818100"), { max_depth: 2 }, str_value) and map_agrees(hex("c6a161618100"), { max_depth: 2, ignore_tags: [6] }, str_value) and map_agrees(hex("a181810001"), { max_depth: 2 }, str_value)

## max_depth 512: a value with 511 levels in the map is Ok, 512 is an error at the 513th head.
expect {
	deep = |n| List.repeat(0x81, n).append(0x00)
	ok = hex("a16161").concat(deep(511))
	over = hex("a16161").concat(deep(512))
	a : Try(List((Str, Cbor.Value)), Errs)
	a = stream(Cbor.Entries.map({}), ok.chunks_of(100))
	b : Try(List((Str, Cbor.Value)), Errs)
	b = stream(Cbor.Entries.map({}), over.chunks_of(100))
	a.is_ok() and b == Err(InvalidCbor(514)) and b == str_value(over, {})
}

## max_buffer: a value of exactly the bytes that are left is Ok, one byte more is TooLarge at the value. The key of
## the open entry and the keys of the KeySet (bytes + 8 each) count: in { "a": 256 } with max_buffer 15, the value
## of 3 bytes fits in 15 - 10 (the KeySet) - 2 (the key).
expect {
	bytes = hex("a16161190100")
	a = str_u64(bytes, { max_buffer: 1 })
	split_str_u64(Cbor.Entries.map({ max_buffer: 15 }), bytes, Ok([("a", 256)])) and split_str_u64(Cbor.Entries.map({ max_buffer: 14 }), bytes, Err(TooLarge(3))) and a == Ok([("a", 256)])
}

## Key memory over max_buffer: TooLarge at the key that goes over (Any). The same map with Sorted keeps one key.
expect {
	keys = (0.U64).until(200).fold([], |acc, i| acc.concat(Cbor.encode(i)).append(0x00))
	bytes = [0xb8, 200].concat(keys)
	a : Try(List((U64, U64)), Errs)
	a = stream(Cbor.Entries.map({ max_buffer: 100 }), bytes.chunks_of(16))
	b : Try(List((U64, U64)), Errs)
	b = stream(Cbor.Entries.map({ max_buffer: 100, key_order: Sorted }), bytes.chunks_of(16))
	# Each key of 1 byte keeps 9 bytes. After 11 keys, 99 bytes are kept, and the key of the open entry takes 1: no
	# byte is left for the value of the 11th entry (at 2 + 10 * 2 + 1).
	c : Try(List((U64, U64)), Errs)
	c = stream(Cbor.Entries.map({ max_buffer: 95 }), bytes.chunks_of(16))
	# With max_buffer 95, the 11th key itself goes over (90 + 9): TooLarge at the key.
	a == Err(TooLarge(23)) and c == Err(TooLarge(22)) and b == u64_u64(bytes, {}) and b.is_ok()
}

## Sorted and Last: the held entry counts in max_buffer until a key equal to its key drops it. With max_buffer 12, the
## second "a" (2 bytes) fits next to the held entry (8 bytes) and the key before (2 bytes), and its value of 6 bytes
## fits only after the drop. 14 bytes for the second value: TooLarge at it.
expect {
	sorted_last : Cbor.Options
	sorted_last = { key_order: Sorted, duplicate_keys: Last, max_buffer: 12 }
	a : Try(List((Str, List(U8))), Errs)
	a = stream(Cbor.Entries.map(sorted_last), [hex("a26161450102030405616145060708090a")])
	b : Try(List((Str, List(U8))), Errs)
	b = stream(Cbor.Entries.map(sorted_last), [hex("a2616145010203040561614d0102030405060708090a0b0c0d")])
	a == Ok([("a", [6, 7, 8, 9, 10])]) and b == Err(TooLarge(11))
}

## A cut value of the bytes that are left is the error of a cut item, not TooLarge: no more bytes exist.
expect split_str_u64(Cbor.Entries.map({ max_buffer: 14 }), hex("a161611901"), Err(InvalidCbor(3))) and str_u64(hex("a161611901"), {}) == Err(InvalidCbor(3))

## A large value in chunks of 1 KiB: kept while it fits, and the next one is refused.
expect {
	big = Cbor.encode(List.repeat(7.U8, 9000))
	bytes = hex("a26161").concat(big).concat(hex("6162")).concat(Cbor.encode(List.repeat(7.U8, 10000)))
	r = drive(Cbor.Entries.map({ max_buffer: 9025 }), bytes.chunks_of(1024))
	got : List((Str, List(U8)))
	got = r.entries
	got == [("a", List.repeat(7, 9000))] and r.end == Err(TooLarge(9008))
}
