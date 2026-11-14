app [] { pkg: "../src/main.roc" }

# Dynamic values and protocol support (0.5.0), through the public API of the package.
# Cbor.ValueMap has no duplicate key (W9). Cbor.IntValue and Cbor.SimpleValue hold only what the writer
# can write as a CBOR integer or simple value (W14). is_eq and to_hash are a loop (D5).
# Cbor.parse_prefix and Cbor.parse_sequence (G3, RFC 8742). Cbor.Raw keeps the exact bytes of an item (G4).
# The property of each test group: each Cbor.Value that app code can make writes bytes that Cbor.parse reads back
# as an equal value.

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

## A Cbor.Value map of distinct keys.
vmap : List((Cbor.Value, Cbor.Value)) -> Cbor.Value
vmap = |pairs|
	match Cbor.ValueMap.from_list(pairs) {
		Ok(m) => Cbor.Value.Map(m)
		Err(_) => crash "a duplicate key in a test map"
	}

## The value writes `h`, and `h` reads back as the value.
writes : Cbor.Value, Str -> Bool
writes = |v, h| {
	back : Try(Cbor.Value, _)
	back = Cbor.parse(hex(h))
	Cbor.encode(v) == hex(h) and back == Ok(v)
}

## The value reads back as an equal value, with the same hash.
reads_back : Cbor.Value -> Bool
reads_back = |v| {
	back : Try(Cbor.Value, _)
	back = Cbor.parse(Cbor.encode(v))
	match back {
		Ok(b) => b == v and Set.from_list([v, b]).len() == 1
		Err(_) => Bool.False
	}
}

# P16 (W9): Cbor.ValueMap

## The entries keep the order of the list.
expect {
	m = Cbor.ValueMap.from_list([(Text("b"), Int(1)), (Int(-1), Null), (Text("a"), Array([]))])
	m.map_ok(|x| x.to_list()) == Ok([(Text("b"), Int(1)), (Int(-1), Null), (Text("a"), Array([]))])
}

## A duplicate key is an error with the second instance of the key.
expect Cbor.ValueMap.from_list([(Text("a"), Int(1)), (Text("b"), Int(2)), (Text("a"), Int(3))]) == Err(DuplicateKey(Text("a")))

## Keys are the same when they are the same Cbor.Value: an array, a map, a tag, a float.
expect {
	inner = vmap([(Int(1), Int(2))])
	pairs : List((Cbor.Value, Cbor.Value))
	pairs = [(Array([Int(1)]), Null), (inner, Null), (Tag(1, Text("x")), Null), (Float(1.5), Null)]
	pairs.all(|(k, _)| Cbor.ValueMap.from_list(pairs.append((k, Undefined))) == Err(DuplicateKey(k)))
}

## The first key that is there a second time: the error has the key at index 3 (`b`), not at index 4 (`a`).
expect Cbor.ValueMap.from_list([(Text("a"), Null), (Text("b"), Null), (Text("c"), Null), (Text("b"), Null), (Text("a"), Null)]) == Err(DuplicateKey(Text("b")))

## Different keys: Int(1) and Float(1.0), 0.0 and -0.0, Text and Bytes of the same bytes, Simple(16) and Int(16).
expect {
	r = Cbor.ValueMap.from_list([(Int(1), Null), (Float(1.0), Null), (Float(0.0), Null), (Float(-0.0), Null), (Text("a"), Null), (Bytes([97]), Null), (Simple(16), Null), (Int(16), Null)])
	r.map_ok(|m| m.len()) == Ok(8)
}

## 1000 keys with a duplicate at 0 and 999.
expect {
	keys : List(Cbor.Value)
	keys = (0.U64).until(1000).map(|i| if (i == 999) Cbor.Value.Text("k0") else Cbor.Value.Text("k${i.to_str()}")).collect()
	Cbor.ValueMap.from_list(keys.map(|k| (k, Cbor.Value.Null))) == Err(DuplicateKey(Text("k0")))
}

## empty, get, insert (a key keeps its place, a new key goes at the end), len.
expect {
	m = Cbor.ValueMap.empty().insert(Text("a"), Int(1)).insert(Int(2), Int(2)).insert(Text("a"), Int(3))
	m.to_list() == [(Text("a"), Int(3)), (Int(2), Int(2))] and m.get(Text("a")) == Ok(Int(3)) and m.get(Int(3)) == Err(KeyNotFound) and m.len() == 2 and Cbor.ValueMap.empty().len() == 0
}

## A map writes its entries in order, and reads back.
expect writes(vmap([(Text("b"), Int(1)), (Int(-1), Null)]), "a261620120f6")

## The reader keeps the winner of a duplicate key with First and Last, in the order of the bytes.
expect {
	bytes = hex("a3616101616202616103")
	first : Try(Cbor.Value, _)
	first = Cbor.parse_with(bytes, { duplicate_keys: First })
	last : Try(Cbor.Value, _)
	last = Cbor.parse_with(bytes, { duplicate_keys: Last })
	first == Ok(vmap([(Text("a"), Int(1)), (Text("b"), Int(2))])) and last == Ok(vmap([(Text("b"), Int(2)), (Text("a"), Int(3))]))
}

## A key with a duplicate key in it is the Cbor.Value without the entry that First or Last skips: in
## {{0: 0}: 4, {0: 0, 0: 0}: ""} the two keys are the same. The value reads back (fuzz parse_never_crashes).
expect {
	zero = vmap([(Int(0), Int(0))])
	first : Try(Cbor.Value, _)
	first = Cbor.parse_with(hex("a2a1000004a20000000060"), { duplicate_keys: First })
	last : Try(Cbor.Value, _)
	last = Cbor.parse_with(hex("a2a1000004a20000000060"), { duplicate_keys: Last })
	# The fuzz input: indefinite lengths, and 20 instances of the key in the inner map.
	fuzz_bytes = hex("bfa1000004b4").concat(List.repeat(0, 40)).concat(hex("60ff"))
	fuzz : Try(Cbor.Value, _)
	fuzz = Cbor.parse_with(fuzz_bytes, { duplicate_keys: Last, allow: [IndefiniteLength] })
	back = |r| r.map_ok(|v| Cbor.parse(Cbor.encode(v)) == Ok(v)) == Ok(Bool.True)
	first == Ok(vmap([(zero, Int(4))])) and last == Ok(vmap([(zero, Text(""))])) and fuzz == last and back(first) and back(last)
}

## Two maps with the same entries in another order are not equal: their bytes are not equal.
expect vmap([(Int(1), Null), (Int(2), Null)]) != vmap([(Int(2), Null), (Int(1), Null)])

# P17 (W14): Cbor.IntValue and Cbor.SimpleValue

## The ends of the range, as literals and from an I128. One more is OutOfRange.
expect Cbor.IntValue.from_i128(18446744073709551615).map_ok(|n| n.to_i128()) == Ok(18446744073709551615)

## IntValue.from_i128 of -2^64, the lowest value, is Ok.
expect Cbor.IntValue.from_i128(-18446744073709551616).map_ok(|n| n.to_i128()) == Ok(-18446744073709551616)

## IntValue.from_i128 of 2^64 is OutOfRange.
expect Cbor.IntValue.from_i128(18446744073709551616) == Err(OutOfRange)

## IntValue.from_i128 of -2^64 - 1 is OutOfRange.
expect Cbor.IntValue.from_i128(-18446744073709551617) == Err(OutOfRange)

## IntValue.from_i128 of I128.highest is OutOfRange.
expect Cbor.IntValue.from_i128(I128.highest) == Err(OutOfRange)

## IntValue.from_i128 of I128.lowest is OutOfRange.
expect Cbor.IntValue.from_i128(I128.lowest) == Err(OutOfRange)

## IntValue.from_i64 of I64.lowest gives -2^63 back.
expect Cbor.IntValue.from_i64(I64.lowest).to_i128() == -9223372036854775808

## IntValue.from_u64 of U64.highest gives 2^64 - 1 back.
expect Cbor.IntValue.from_u64(U64.highest).to_i128() == 18446744073709551615

## Int(2^64 - 1) writes 1b ffffffffffffffff and reads back.
expect writes(Int(18446744073709551615), "1bffffffffffffffff")

## Int(-2^64) writes 3b ffffffffffffffff and reads back.
expect writes(Int(-18446744073709551616), "3bffffffffffffffff")

## Int(-1) writes 20 and reads back.
expect writes(Int(-1), "20")

## Int(0) writes 00 and reads back.
expect writes(Int(0), "00")

## A bignum (tag 2) stays a tag: an Int cannot hold it, so it reads back as the same Tag.
expect writes(Tag(2, Bytes([1, 0, 0, 0, 0, 0, 0, 0, 0])), "c249010000000000000000")

## Simple values: 0 to 19 in one byte, 32 to 255 in two. 20 to 31 are an error.
expect writes(Simple(0), "e0")

## Simple(19) writes f3 and reads back.
expect writes(Simple(19), "f3")

## Simple(32) writes f8 20 and reads back.
expect writes(Simple(32), "f820")

## Simple(255) writes f8 ff and reads back.
expect writes(Simple(255), "f8ff")

## SimpleValue.from_u8 of 20, 21, 22, 23, 24 and 31 is InvalidSimple.
expect [20, 21, 22, 23, 24, 31].all(|n| Cbor.SimpleValue.from_u8(n) == Err(InvalidSimple))

## SimpleValue.from_u8 of 0, 19, 32 and 255 gives the same number back.
expect [0, 19, 32, 255].all(|n| Cbor.SimpleValue.from_u8(n).map_ok(|s| s.to_u8()) == Ok(n))

## Each of the 256 U8 values: a simple value that reads back, or an error for 20 to 31.
expect {
	numbers : List(U8)
	numbers = (0.U64).until(256).map(|i| i.to_u8_wrap()).collect()
	numbers.all(
		|n|
			match Cbor.SimpleValue.from_u8(n) {
				Ok(s) => (n < 20 or n >= 32) and reads_back(Simple(s))
				Err(InvalidSimple) => n >= 20 and n < 32
			},
	)
}

## Simple(20) to Simple(23) are not the same as false, true, null and undefined any more: they cannot be made.
expect Cbor.Value.Simple(19) != Cbor.Value.Bool(Bool.False)

# P18 (D5): is_eq and to_hash

## Equal when the bytes are equal.
expect Cbor.Value.Float(0.0) != Cbor.Value.Float(-0.0)

## Two NaN floats are equal.
expect Cbor.Value.Float(F64.nan) == Cbor.Value.Float(F64.nan)

## Int(1) and Float(1.0) are not equal.
expect Cbor.Value.Int(1) != Cbor.Value.Float(1.0)

## Text "a" and Bytes [97] are not equal.
expect Cbor.Value.Text("a") != Cbor.Value.Bytes([97])

## Tag 1 and tag 2 of the same content are not equal.
expect Cbor.Value.Tag(1, Int(1)) != Cbor.Value.Tag(2, Int(1))

## Arrays of 1 and 2 items are not equal.
expect Cbor.Value.Array([Int(1)]) != Cbor.Value.Array([Int(1), Int(1)])

## Maps with the same key and another value are not equal.
expect vmap([(Int(1), Int(2))]) != vmap([(Int(1), Int(3))])

## Maps with another key and the same value are not equal.
expect vmap([(Int(1), Int(2))]) != vmap([(Int(2), Int(2))])

## Undefined and Null are not equal.
expect Cbor.Value.Undefined != Cbor.Value.Null

## is_eq agrees with the bytes for each pair of a list of values.
expect {
	values : List(Cbor.Value)
	values = [Int(0), Int(-1), Float(0.0), Float(-0.0), Float(F64.nan), Text(""), Bytes([]), Array([]), Cbor.Value.Map(Cbor.ValueMap.empty()), Tag(0, Null), Bool(Bool.True), Null, Undefined, Simple(0), vmap([(Null, Null)]), Array([Null]), Tag(0, Undefined)]
	values.all(|a| values.all(|b| (a == b) == (Cbor.encode(a) == Cbor.encode(b))))
}

## Equal values have the same hash: a Set of a value and the value that reads back has one item.
## A Dict with a Cbor.Value key.
expect {
	v = vmap([(Array([Float(F64.nan)]), Tag(3, Bytes([1]))), (Text("k"), Simple(255))])
	d = Dict.empty().insert(v, 1.U64).insert(Cbor.Value.Text("a"), 2)
	reads_back(v) and d.get(vmap([(Array([Float(F64.nan)]), Tag(3, Bytes([1]))), (Text("k"), Simple(255))])) == Ok(1) and d.get(Cbor.Value.Text("b")) == Err(KeyNotFound)
}

## A value of n nested arrays and tags around inner.
deep : U64, Cbor.Value -> Cbor.Value
deep = |n, inner| {
	var $v = inner
	for i in (0.U64).until(n) {
		$v = if (i % 2 == 0) Cbor.Value.Array([$v]) else Cbor.Value.Tag(i, $v)
	}
	$v
}

## The same value, with each 25,000th level also kept in a list, outermost first.
deep_levels : U64, Cbor.Value -> List(Cbor.Value)
deep_levels = |n, inner| {
	var $v = inner
	var $levels = []
	for i in (0.U64).until(n) {
		$v = if (i % 2 == 0) Cbor.Value.Array([$v]) else Cbor.Value.Tag(i, $v)
		if i % 25000 == 24999 {
			$levels = $levels.append($v)
		}
	}
	$levels.rev()
}

## 500,000 nested arrays and tags: is_eq and to_hash are a loop, with no stack overflow. On x86-64 a
## recursive is_eq overflows at 200,000 levels, and a recursive to_hash at 300,000.
## The drop of Roc is recursive, so the value is not dropped in one piece: the list of deep_levels is the
## value under test, and it drops at most 25,000 levels at a time. Do not take the outermost level out of
## the list: when that level is dropped after the list, the drop is 500,000 levels deep.
expect {
	a = deep_levels(500000, Int(1))
	b = deep_levels(500000, Int(1))
	c = deep_levels(500000, Int(2))
	a.len() == 20 and a == b and a != c and Set.from_list([a, b]).len() == 1
}

# P19 (G3): Cbor.parse_prefix and Cbor.parse_sequence

## One item at the start, and the bytes after it.
expect {
	r : Try({ value : Cbor.Value, rest : List(U8) }, _)
	r = Cbor.parse_prefix(hex("a1616101ff00"))
	r == Ok({ value: vmap([(Text("a"), Int(1))]), rest: [0xff, 0x00] })
}

## A record {a: 1} with no bytes after it reads, with an empty rest.
expect {
	r : Try({ value : { a : U64 }, rest : List(U8) }, _)
	r = Cbor.parse_prefix(hex("a1616101"))
	r == Ok({ value: { a: 1 }, rest: [] })
}

## No item, a bad item, or an item that does not fit the type: an error at its position.
expect {
	empty : Try({ value : Cbor.Value, rest : List(U8) }, _)
	empty = Cbor.parse_prefix([])
	cut : Try({ value : Cbor.Value, rest : List(U8) }, _)
	cut = Cbor.parse_prefix(hex("8201"))
	typed : Try({ value : Str, rest : List(U8) }, _)
	typed = Cbor.parse_prefix(hex("0102"))
	empty == Err(InvalidCbor(0)) and cut == Err(InvalidCbor(0)) and typed == Err(InvalidCbor(0))
}

## The checks of parse apply: a non-shortest head is an error, and reads with PaddedNumbers.
expect {
	strict : Try({ value : U64, rest : List(U8) }, _)
	strict = Cbor.parse_prefix(hex("180100"))
	lenient : Try({ value : U64, rest : List(U8) }, _)
	lenient = Cbor.parse_prefix_with(hex("180100"), { allow: [PaddedNumbers] })
	strict == Err(InvalidCbor(0)) and lenient == Ok({ value: 1, rest: [0] })
}

## A sequence of zero or more items.
expect {
	none : Try(List(Cbor.Value), _)
	none = Cbor.parse_sequence([])
	three : Try(List(Cbor.Value), _)
	three = Cbor.parse_sequence(hex("01616180"))
	none == Ok([]) and three == Ok([Int(1), Text("a"), Array([])])
}

## A sequence of the records {id: 1} and {id: 2} reads as a list of records.
expect {
	r : Try(List({ id : U64 }), _)
	r = Cbor.parse_sequence(hex("a162696401a162696402"))
	r == Ok([{ id: 1 }, { id: 2 }])
}

## The position of an error is in all of the bytes: a bad second item, a cut last item, a type error in the third item.
expect {
	bad : Try(List(Cbor.Value), _)
	bad = Cbor.parse_sequence(hex("0102a2616101616102"))
	cut : Try(List(Cbor.Value), _)
	cut = Cbor.parse_sequence(hex("01028301"))
	typed : Try(List(U8), _)
	typed = Cbor.parse_sequence(hex("01026161"))
	bad == Err(InvalidCbor(6)) and cut == Err(InvalidCbor(2)) and typed == Err(InvalidCbor(2))
}

## The options apply to each item: max_items counts the items of one item, duplicate_keys reads each map.
expect {
	bytes = hex("820102820304")
	ok : Try(List(List(U16)), _)
	ok = Cbor.parse_sequence_with(bytes, { max_items: 3 })
	over : Try(List(List(U16)), _)
	over = Cbor.parse_sequence_with(bytes, { max_items: 2 })
	last : Try(List(Cbor.Value), _)
	last = Cbor.parse_sequence_with(hex("a2616101616102a0"), { duplicate_keys: Last })
	ok == Ok([[1, 2], [3, 4]]) and over == Err(InvalidCbor(2)) and last == Ok([vmap([(Text("a"), Int(2))]), Cbor.Value.Map(Cbor.ValueMap.empty())])
}

## The encodes of the items of a sequence, one after the other, read back.
expect {
	items : List(Cbor.Value)
	items = [Int(1), vmap([(Int(1), Null)]), Simple(32), Tag(9, Array([]))]
	r : Try(List(Cbor.Value), _)
	r = Cbor.parse_sequence(items.map(|v| Cbor.encode(v)).join())
	r == Ok(items)
}

# P20 (G4): Cbor.Raw

## from_bytes: exactly one item with the strict checks.
expect Cbor.Raw.from_bytes(hex("a1616182f93e00f6")).map_ok(|r| r.to_bytes()) == Ok(hex("a1616182f93e00f6"))

## Raw.from_bytes of no bytes is an error at byte 0.
expect Cbor.Raw.from_bytes([]) == Err(InvalidCbor(0))

## Raw.from_bytes of two items (01 02) is an error at byte 1.
expect Cbor.Raw.from_bytes(hex("0102")) == Err(InvalidCbor(1))

## Raw.from_bytes of a padded head (18 01) is an error at byte 0.
expect Cbor.Raw.from_bytes(hex("1801")) == Err(InvalidCbor(0))

## Raw.from_bytes of a map with the key "a" twice is an error at the second key, byte 4.
expect Cbor.Raw.from_bytes(hex("a2616101616102")) == Err(InvalidCbor(4))

## Raw.from_bytes of a cut array (82 01) is an error at byte 0.
expect Cbor.Raw.from_bytes(hex("8201")) == Err(InvalidCbor(0))

## Raw.from_bytes of text with invalid UTF-8 (62 61 ff) is an error at byte 0.
expect Cbor.Raw.from_bytes(hex("6261ff")) == Err(InvalidCbor(0))

## A record field keeps the exact bytes of its item: an f16 float, a tag.
expect {
	# {"payload": [1.5 as f16, 6(null)], "sig": h'09'}
	bytes = hex("a2677061796c6f616482f93e00c6f6637369674109")
	r : Try({ payload : Cbor.Raw, sig : List(U8) }, _)
	r = Cbor.parse(bytes)
	match r {
		Ok(signed) => signed.payload.to_bytes() == hex("82f93e00c6f6") and signed.sig == [9]
		Err(_) => Bool.False
	}
}

## With options, a Raw keeps bytes that only those options read: a long head, a duplicate key.
expect {
	long : Try(List(Cbor.Raw), _)
	long = Cbor.parse_with(hex("81190001"), { allow: [PaddedNumbers] })
	dup : Try(Cbor.Raw, _)
	dup = Cbor.parse_with(hex("a2616101616102"), { duplicate_keys: Last })
	long.map_ok(|rs| rs.map(|r| r.to_bytes())) == Ok([hex("190001")]) and dup.map_ok(|r| r.to_bytes()) == Ok(hex("a2616101616102"))
}

## The writer writes the bytes as one item: in an array, and as a record field.
expect {
	a = Cbor.Raw.from_bytes(hex("f93e00")) ?? crash "raw"
	b = Cbor.Raw.from_bytes(hex("a0")) ?? crash "raw"
	Cbor.encode([a, b]) == hex("82f93e00a0") and Cbor.encode({ x: a }) == hex("a16178f93e00")
}

## A Raw parses into a type with Cbor.parse of its bytes.
expect {
	raw = Cbor.Raw.from_bytes(hex("a1626964182a")) ?? crash "raw"
	r : Try({ id : U64 }, _)
	r = Cbor.parse(raw.to_bytes())
	r == Ok({ id: 42 })
}

## A Raw keeps each tag, also a tag of ignore_tags, and is the content of an internal tag.
expect {
	tagged : Try(List(Cbor.Raw), _)
	tagged = Cbor.parse_with(hex("81c601"), { ignore_tags: [6] })
	internal : Try([Blob(Cbor.Raw)], _)
	internal = Cbor.parse_with(hex("a2646b696e6464426c6f626576616c7565c101"), { unions: Internal({ tag: "kind", content: "value" }) })
	tagged.map_ok(|rs| rs.map(|r| r.to_bytes())) == Ok([hex("c601")]) and internal.map_ok(|Blob(r)| r.to_bytes()) == Ok(hex("c101"))
}

# The property: each value that the types let app code make reads back as an equal value.

## Edge values (the integer ends, NaN, -0.0, infinity, simple values, a nested map, a large tag, 511 levels) read back equal, with the same hash.
expect {
	values : List(Cbor.Value)
	values = [
		Int(18446744073709551615),
		Int(-18446744073709551616),
		Float(F64.nan),
		Float(-0.0),
		Float(F64.infinity),
		Simple(19),
		Simple(32),
		Text("\u(fc)"),
		Bytes([0, 255]),
		vmap([(Array([Int(1)]), vmap([(Float(1.0), Null)])), (Tag(2, Bytes([1])), Undefined), (Simple(0), Bool(Bool.False))]),
		Tag(18446744073709551615, Array([Null, Undefined])),
		deep(511, Null),
	]
	values.all(reads_back)
}
