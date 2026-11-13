app [] { pkg: "../src/main.roc" }

# The read option key_order (0.5.0), through the public API of the package. With `key_order: Sorted` the keys of
# each map must be in the order of RFC 8949 4.2.1: the bytewise order of the deterministic encoding of each key.
# A key out of order is an error at the key, in each reader: a record, a nested map, a skipped field, a Dict,
# a Cbor.Value, an internal tag, parse_prefix and parse_sequence. Equal keys are adjacent, and duplicate_keys
# applies to them. `Any` (the default) does not change.

import pkg.Cbor

sorted : Cbor.Options
sorted = { key_order: Sorted }

## A Cbor.Value map of distinct keys.
vmap : List((Cbor.Value, Cbor.Value)) -> Cbor.Value
vmap = |pairs|
	match Cbor.ValueMap.from_list(pairs) {
		Ok(m) => Cbor.Value.Map(m)
		Err(_) => crash "a duplicate key in a test map"
	}

# Sorted input reads

## With First or Last, a key is compared as its Cbor.Value, without the entries that are skipped in it: the keys
## {0: 0} and {0: 0, 0: 0} are the same key.
expect {
	bytes = [0xa2, 0xa1, 0x00, 0x00, 0x04, 0xa2, 0x00, 0x00, 0x00, 0x00, 0x05]
	zero = vmap([(Int(0), Int(0))])
	first : Try(Cbor.Value, _)
	first = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: First })
	last : Try(Cbor.Value, _)
	last = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: Last })
	first == Ok(vmap([(zero, Int(4))])) and last == Ok(vmap([(zero, Int(5))]))
}

## {"a": 1, "b": 2} as a record, a Dict and a Cbor.Value.
expect {
	bytes = [0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02]
	a : Try({ a : U64, b : U64 }, _)
	a = Cbor.parse_with(bytes, sorted)
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with(bytes, sorted)
	c : Try(Cbor.Value, _)
	c = Cbor.parse_with(bytes, sorted)
	a == Ok({ a: 1, b: 2 }) and b == Ok(Dict.from_list([("a", 1), ("b", 2)])) and c == Ok(vmap([(Text("a"), Int(1)), (Text("b"), Int(2))]))
}

## The bytes of encode_with(.., { key_order: Sorted }) read back with key_order: Sorted, also a record in a Dict.
expect {
	value = { zeta: 1.U64, alpha: Dict.from_list([(300.U64, "c"), (2, "b"), (1, "a")]), mid: [{ y: 1.U8, x: 2.U8 }] }
	bytes = Cbor.encode_with(value, { key_order: Sorted }) ?? []
	back : Try({ zeta : U64, alpha : Dict(U64, Str), mid : List({ y : U8, x : U8 }) }, _)
	back = Cbor.parse_with(bytes, sorted)
	back == Ok(value)
}

# A key out of order: an error at the key

## {"b": 1, "a": 2}: the root map of a record and of a Dict.
b_a : List(U8)
b_a = [0xa2, 0x61, 0x62, 0x01, 0x61, 0x61, 0x02]

## With Sorted, {"b": 1, "a": 2} is an error at the key "a" (byte 4), as a record and as a Dict.
expect {
	a : Try({ a : U64, b : U64 }, _)
	a = Cbor.parse_with(b_a, sorted)
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with(b_a, sorted)
	a == Err(InvalidCbor(4)) and b == Err(InvalidCbor(4))
}

## {2: 0, 1: 0} as a Dict with integer keys.
expect {
	r : Try(Dict(U64, U64), _)
	r = Cbor.parse_with([0xa2, 0x02, 0x00, 0x01, 0x00], sorted)
	r == Err(InvalidCbor(3))
}

## {"o": {"y": 1, "x": 2}}: a nested map.
expect {
	r : Try({ o : { x : U64, y : U64 } }, _)
	r = Cbor.parse_with([0xa1, 0x61, 0x6f, 0xa2, 0x61, 0x79, 0x01, 0x61, 0x78, 0x02], sorted)
	r == Err(InvalidCbor(7))
}

## {"a": 1, "u": {"y": 1, "x": 2}}: the map is in an unknown field that the record skips, and in a Cbor.Value.
unknown_b_a : List(U8)
unknown_b_a = [0xa2, 0x61, 0x61, 0x01, 0x61, 0x75, 0xa2, 0x61, 0x79, 0x01, 0x61, 0x78, 0x02]

## With Sorted, the unsorted map in the unknown field "u" is an error at byte 10, as a record and as a Cbor.Value; parse reads { a: 1 }.
expect {
	a : Try({ a : U64 }, _)
	a = Cbor.parse_with(unknown_b_a, sorted)
	b : Try(Cbor.Value, _)
	b = Cbor.parse_with(unknown_b_a, sorted)
	any : Try({ a : U64 }, _)
	any = Cbor.parse(unknown_b_a)
	a == Err(InvalidCbor(10)) and b == Err(InvalidCbor(10)) and any == Ok({ a: 1 })
}

## {{"b": 1, "a": 2}: 0}: a map in a key is checked too.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with([0xa1, 0xa2, 0x61, 0x62, 0x01, 0x61, 0x61, 0x02, 0x00], sorted)
	r == Err(InvalidCbor(5))
}

## {"a": 1, "b": 2, "a": 3}: an equal key that is not adjacent is a key out of order, also with First and Last.
expect {
	bytes = [0xa3, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02, 0x61, 0x61, 0x03]
	a : Try({ a : U64, b : U64 }, _)
	a = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: First })
	b : Try({ a : U64, b : U64 }, _)
	b = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: Last })
	c : Try({ a : U64, b : U64 }, _)
	c = Cbor.parse_with(bytes, { duplicate_keys: First })
	a == Err(InvalidCbor(7)) and b == Err(InvalidCbor(7)) and c == Ok({ a: 1, b: 2 })
}

## parse_sequence and parse_prefix: {"a": 1} then {"b": 1, "a": 2}. The position is in the whole input.
expect {
	bytes = [0xa1, 0x61, 0x61, 0x01].concat(b_a)
	a : Try(List(Dict(Str, U64)), _)
	a = Cbor.parse_sequence_with(bytes, sorted)
	b : Try({ value : Dict(Str, U64), rest : List(U8) }, _)
	b = Cbor.parse_prefix_with(b_a.concat([0x00]), sorted)
	c : Try(List(Dict(Str, U64)), _)
	c = Cbor.parse_sequence(bytes)
	a == Err(InvalidCbor(8)) and b == Err(InvalidCbor(4)) and c.is_ok()
}

# An internal tag: the tag key can be at any place in the sorted order

Shape : [Dot({ a : Str }), Box({ a : Str, w : U64 })]

type_tag : Cbor.Unions
type_tag = Internal({ tag: "type", content: "value" })

## With Sorted, {"a": "x", "type": "Dot"} (the tag key last) reads as Dot({ a: "x" }).
expect {
	# {"a": "x", "type": "Dot"}: the tag key is the last key.
	bytes = [0xa2, 0x61, 0x61, 0x61, 0x78, 0x64, 0x74, 0x79, 0x70, 0x65, 0x63, 0x44, 0x6f, 0x74]
	r : Try(Shape, _)
	r = Cbor.parse_with(bytes, { unions: type_tag, key_order: Sorted })
	r == Ok(Dot({ a: "x" }))
}

## With Sorted, {"type": "Dot", "a": "x"} is an error at the key "a" (byte 10); without Sorted it reads as Dot({ a: "x" }).
expect {
	# {"type": "Dot", "a": "x"}: out of order at the key "a".
	bytes = [0xa2, 0x64, 0x74, 0x79, 0x70, 0x65, 0x63, 0x44, 0x6f, 0x74, 0x61, 0x61, 0x61, 0x78]
	r : Try(Shape, _)
	r = Cbor.parse_with(bytes, { unions: type_tag, key_order: Sorted })
	any : Try(Shape, _)
	any = Cbor.parse_with(bytes, { unions: type_tag })
	r == Err(InvalidCbor(10)) and any == Ok(Dot({ a: "x" }))
}

## A record written with key_order: Sorted reads back with Sorted as Box({ a: "y", w: 3 }).
expect {
	# The writer and the reader agree on an internal tag in a sorted map.
	bytes = Cbor.encode_with({ w: 3.U64, type: "Box", a: "y" }, { key_order: Sorted }) ?? []
	r : Try(Shape, _)
	r = Cbor.parse_with(bytes, { unions: type_tag, key_order: Sorted })
	r == Ok(Box({ a: "y", w: 3 }))
}

# Keys of different types and lengths: the bytes of the encoding decide, so a shorter key comes first

## {10: 0, -1: 0, "z": 0, "aa": 0}: 0a, 20, 61 7a, 62 61 61.
mixed : List(U8)
mixed = [0xa4, 0x0a, 0x00, 0x20, 0x00, 0x61, 0x7a, 0x00, 0x62, 0x61, 0x61, 0x00]

## With Sorted, the map {10: 0, -1: 0, "z": 0, "aa": 0} is in order and reads as a Cbor.Value.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with(mixed, sorted)
	r == Ok(vmap([(Int(10), Int(0)), (Int(-1), Int(0)), (Text("z"), Int(0)), (Text("aa"), Int(0))]))
}

## The writer gives the same order from any order of the entries.
expect {
	v = vmap([(Text("aa"), Int(0)), (Text("z"), Int(0)), (Int(-1), Int(0)), (Int(10), Int(0))])
	Cbor.encode_with(v, { key_order: Sorted }) == Ok(mixed)
}

## "aa" before "z" is out of order. "b" before "aa" is in order (a shorter text comes first).
expect {
	swapped = [0xa4, 0x0a, 0x00, 0x20, 0x00, 0x62, 0x61, 0x61, 0x00, 0x61, 0x7a, 0x00]
	a : Try(Cbor.Value, _)
	a = Cbor.parse_with(swapped, sorted)
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with([0xa2, 0x61, 0x62, 0x00, 0x62, 0x61, 0x61, 0x00], sorted)
	a == Err(InvalidCbor(9)) and b == Ok(Dict.from_list([("b", 0), ("aa", 0)]))
}

## -1 before 10 is out of order (0x20 after 0x0a); 24 (18 18) before 23 (17) is out of order.
expect {
	a : Try(Dict(I64, U64), _)
	a = Cbor.parse_with([0xa2, 0x20, 0x00, 0x0a, 0x00], sorted)
	b : Try(Dict(U64, U64), _)
	b = Cbor.parse_with([0xa2, 0x18, 0x18, 0x00, 0x17, 0x00], sorted)
	c : Try(Dict(U64, U64), _)
	c = Cbor.parse_with([0xa2, 0x17, 0x00, 0x18, 0x18, 0x00], sorted)
	a == Err(InvalidCbor(3)) and b == Err(InvalidCbor(4)) and c == Ok(Dict.from_list([(23, 0), (24, 0)]))
}

# A float key is compared in its shortest form

## {1.0 as f16: 0, 1.5 as f32: 0}: the f32 key is f9 3e00 in its shortest form, after f9 3c00.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with([0xa2, 0xf9, 0x3c, 0x00, 0x00, 0xfa, 0x3f, 0xc0, 0x00, 0x00, 0x00], sorted)
	r == Ok(vmap([(Float(1.0), Int(0)), (Float(1.5), Int(0))]))
}

## {2.0: 0, 1.1: 0}: 2.0 is f9 4000, before 1.1 (fb 3ff1..), as the writer sorts them. As f64 bits 2.0 is after 1.1.
expect {
	bytes = [0xa2, 0xf9, 0x40, 0x00, 0x00, 0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a, 0x00]
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with(bytes, sorted)
	Cbor.encode_with(vmap([(Float(1.1), Int(0)), (Float(2.0), Int(0))]), { key_order: Sorted }) == Ok(bytes) and r == Ok(vmap([(Float(2.0), Int(0)), (Float(1.1), Int(0))]))
}

## {2.0 as f64: 0, 1.1: 0}: the same keys. The shortest form of the first key decides, not its bytes.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with([0xa2, 0xfb, 0x40, 0, 0, 0, 0, 0, 0, 0, 0x00, 0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a, 0x00], sorted)
	r.is_ok()
}

## {1.5 as f16: 0, 1.0 as f64: 0}: the bytes f9 and fb are in order, but the shortest forms (3e00, 3c00) are not.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with([0xa2, 0xf9, 0x3e, 0x00, 0x00, 0xfb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0, 0x00], sorted)
	r == Err(InvalidCbor(5))
}

## {1.0 as f16: 1, 1.0 as f64: 2}: the same key. Reject, First, Last.
expect {
	bytes = [0xa2, 0xf9, 0x3c, 0x00, 0x01, 0xfb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0, 0x02]
	a : Try(Cbor.Value, _)
	a = Cbor.parse_with(bytes, sorted)
	b : Try(Cbor.Value, _)
	b = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: First })
	c : Try(Cbor.Value, _)
	c = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: Last })
	a == Err(InvalidCbor(5)) and b == Ok(vmap([(Float(1.0), Int(1))])) and c == Ok(vmap([(Float(1.0), Int(2))]))
}

# The deterministic form of a padded head and of a text of indefinite length

## {4 as 19 0004: 0, 5: 0} with PaddedNumbers: in order (the raw bytes 19 and 05 are not). {5: 0, 4 as 19 0004: 0}: not.
expect {
	a : Try(Dict(U64, U64), _)
	a = Cbor.parse_with([0xa2, 0x19, 0x00, 0x04, 0x00, 0x05, 0x00], { key_order: Sorted, allow: [PaddedNumbers] })
	b : Try(Dict(U64, U64), _)
	b = Cbor.parse_with([0xa2, 0x05, 0x00, 0x19, 0x00, 0x04, 0x00], { key_order: Sorted, allow: [PaddedNumbers] })
	c : Try(Dict(U64, U64), _)
	c = Cbor.parse_with([0xa2, 0x05, 0x00, 0x19, 0x00, 0x04, 0x00], { allow: [PaddedNumbers] })
	a == Ok(Dict.from_list([(4, 0), (5, 0)])) and b == Err(InvalidCbor(3)) and c.is_ok()
}

## {(_ "a"): 0, "b": 0} with IndefiniteLength: in order (the raw bytes 7f and 61 are not). Swapped: not.
expect {
	a : Try(Cbor.Value, _)
	a = Cbor.parse_with([0xa2, 0x7f, 0x61, 0x61, 0xff, 0x00, 0x61, 0x62, 0x00], { key_order: Sorted, allow: [IndefiniteLength] })
	b : Try(Cbor.Value, _)
	b = Cbor.parse_with([0xa2, 0x61, 0x62, 0x00, 0x7f, 0x61, 0x61, 0xff, 0x00], { key_order: Sorted, allow: [IndefiniteLength] })
	a == Ok(vmap([(Text("a"), Int(0)), (Text("b"), Int(0))])) and b == Err(InvalidCbor(4))
}

# duplicate_keys with adjacent equal keys

## {"a": 1, "a": 2, "b": 3}
a_a_b : List(U8)
a_a_b = [0xa3, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02, 0x61, 0x62, 0x03]

## With Sorted, {"a": 1, "a": 2, "b": 3} as a record: Reject is an error at byte 4, First gives a: 1, Last gives a: 2.
expect {
	a : Try({ a : U64, b : U64 }, _)
	a = Cbor.parse_with(a_a_b, sorted)
	b : Try({ a : U64, b : U64 }, _)
	b = Cbor.parse_with(a_a_b, { key_order: Sorted, duplicate_keys: First })
	c : Try({ a : U64, b : U64 }, _)
	c = Cbor.parse_with(a_a_b, { key_order: Sorted, duplicate_keys: Last })
	a == Err(InvalidCbor(4)) and b == Ok({ a: 1, b: 3 }) and c == Ok({ a: 2, b: 3 })
}

## With Sorted, {"a": 1, "a": 2, "b": 3} as a Dict: First gives "a": 1, Last gives "a": 2, also as a Cbor.Value.
expect {
	a : Try(Dict(Str, U64), _)
	a = Cbor.parse_with(a_a_b, { key_order: Sorted, duplicate_keys: First })
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with(a_a_b, { key_order: Sorted, duplicate_keys: Last })
	c : Try(Cbor.Value, _)
	c = Cbor.parse_with(a_a_b, { key_order: Sorted, duplicate_keys: Last })
	a == Ok(Dict.from_list([("a", 1), ("b", 3)])) and b == Ok(Dict.from_list([("a", 2), ("b", 3)])) and c == Ok(vmap([(Text("a"), Int(2)), (Text("b"), Int(3))]))
}

## A run of 3 equal keys, {"a": 1, "a": 2, "a": 3}: the first or the last of the run.
expect {
	bytes = [0xa3, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02, 0x61, 0x61, 0x03]
	a : Try({ a : U64 }, _)
	a = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: First })
	b : Try({ a : U64 }, _)
	b = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: Last })
	c : Try({ a : U64 }, _)
	c = Cbor.parse_with(bytes, sorted)
	a == Ok({ a: 1 }) and b == Ok({ a: 3 }) and c == Err(InvalidCbor(4))
}

# A key with a map in it

## A key is compared as its Cbor.Value. With Last, the key {0: 1, 0: 2} is {0: 2} (deterministic bytes a1 00 02):
## { {0: 1, 0: 2}: 1, {0: 2}: 2 } has one key two times, and Last gives the second entry. With the bytes as they are
## (a2 00 01 00 02) the second key would come before the first.
expect {
	twice = [0xa2, 0xa2, 0x00, 0x01, 0x00, 0x02, 0x01, 0xa1, 0x00, 0x02, 0x02]
	a : Try(Cbor.Value, _)
	a = Cbor.parse_with(twice, { key_order: Sorted, duplicate_keys: Last })
	a == Ok(vmap([(vmap([(Int(0), Int(2))]), Int(2))]))
}

## { {0: h'', 0: 9}: 0, {0: 0, 14: 0}: 0 } with Last: the first key is {0: 9} (a1 ..), before {0: 0, 14: 0} (a2 ..).
## With the bytes as they are (a2 00 40 ..) the second key would come before the first.
expect {
	bytes = [0xa2, 0xa2, 0x00, 0x40, 0x00, 0x09, 0x00, 0xa2, 0x00, 0x00, 0x0e, 0x00, 0x00]
	a : Try(Cbor.Value, _)
	a = Cbor.parse_with(bytes, { key_order: Sorted, duplicate_keys: Last })
	a == Ok(vmap([(vmap([(Int(0), Int(9))]), Int(0)), (vmap([(Int(0), Int(0)), (Int(14), Int(0))]), Int(0))]))
}

## The same with key_order: Any and First: the key {0: 1, 0: 2} is {0: 1}, so { {0: 1, 0: 2}: 1, {0: 1}: 2 } has one
## key two times, and First gives the first entry.
expect {
	twice = [0xa2, 0xa2, 0x00, 0x01, 0x00, 0x02, 0x01, 0xa1, 0x00, 0x01, 0x02]
	a : Try(Cbor.Value, _)
	a = Cbor.parse_with(twice, { duplicate_keys: First })
	a == Ok(vmap([(vmap([(Int(0), Int(1))]), Int(1))]))
}

# key_order: Any does not change

## With key_order: Any or no option, {"b": 1, "a": 2} reads as { a: 2, b: 1 }, and {"a": 1, "a": 2, "b": 3} is still an error at byte 4.
expect {
	a : Try({ a : U64, b : U64 }, _)
	a = Cbor.parse(b_a)
	b : Try({ a : U64, b : U64 }, _)
	b = Cbor.parse_with(b_a, { key_order: Any })
	c : Try({ a : U64, b : U64 }, _)
	c = Cbor.parse_with(a_a_b, { key_order: Any })
	a == Ok({ a: 2, b: 1 }) and b == a and c == Err(InvalidCbor(4))
}
