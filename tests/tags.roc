app [] { pkg: "../src/main.roc" }

# CBOR tags and dynamic values (0.3.0), through the public API of the package.
# The building blocks: Cbor.parse_cbor_tag, Cbor.encode_cbor_tag, Cbor.peek, Cbor.parse_item,
# Cbor.encode_item, Cbor.Value, and the options ignore_tags and dec_from_text.
# The types of this file are types of an app: the package has no type for a tag of its own.
# The tags 6, 10, 12 and 88 are unassigned in the IANA registry, so a peer can use them for its own types.

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

# Types of an app, over tags

## A UUID (RFC 9562): the IANA tag 37 and a byte string of 16 bytes.
Uuid := List(U8).{
	is_eq : _

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

## A time of a peer: a private tag 12 and the array `[seconds, nanoseconds]`.
Instant := { secs : I64, nanos : U32 }.{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Instant, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		if tag.value != 12 {
			return Err(Cbor.invalid_value(encoding, state))
		}
		pair : { value : (I64, U32), rest : Cbor.State }
		pair = Cbor.parse_item(encoding, tag.rest)?
		Ok({ value: Instant.{ secs: pair.value.0, nanos: pair.value.1 }, rest: pair.rest })
	}

	encoder_for : Cbor -> (Instant, List(U8) -> Try(List(U8), []))
	encoder_for = |_| |Instant.{ secs, nanos }, out| {
		tagged = Cbor.encode_cbor_tag(12, out)?
		Cbor.encode_item((secs, nanos), tagged)
	}
}

## A point of a peer: a private tag 88 and the array `[x, y]`. A geometry type is a type of the app:
## the package has no geometry types.
Point := { x : F64, y : F64 }.{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Point, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		if tag.value != 88 {
			return Err(Cbor.invalid_value(encoding, state))
		}
		xy : { value : (F64, F64), rest : Cbor.State }
		xy = Cbor.parse_item(encoding, tag.rest)?
		Ok({ value: Point.{ x: xy.value.0, y: xy.value.1 }, rest: xy.rest })
	}
}

## A link of a peer: a private tag 8 and `[table, key]`. The key can be text, a number or an array, so it is a Cbor.Value.
Link := { table : Str, key : Cbor.Value }.{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Link, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		if tag.value != 8 {
			return Err(Cbor.invalid_value(encoding, state))
		}
		pair : { value : (Str, Cbor.Value), rest : Cbor.State }
		pair = Cbor.parse_item(encoding, tag.rest)?
		Ok({ value: Link.{ table: pair.value.0, key: pair.value.1 }, rest: pair.rest })
	}

	encoder_for : Cbor -> (Link, List(U8) -> Try(List(U8), []))
	encoder_for = |_| |Link.{ table, key }, out| {
		tagged = Cbor.encode_cbor_tag(8, out)?
		Cbor.encode_item((table, key), tagged)
	}
}

## A value that is one of several types, picked with Cbor.peek.
Cell := [Number(I64), Word(Str), When(Instant), Nothing].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Cell, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state|
		match Cbor.peek(encoding, state)? {
			Int => {
				n = Cbor.parse_i64(encoding, state)?
				Ok({ value: Cell.Number(n.value), rest: n.rest })
			}
			Text => {
				t = Cbor.parse_str(encoding, state)?
				Ok({ value: Cell.Word(t.value), rest: t.rest })
			}
			Tag(12) => {
				i = Cbor.parse_item(encoding, state)?
				Ok({ value: Cell.When(i.value), rest: i.rest })
			}
			Null => Ok({ value: Cell.Nothing, rest: Cbor.parse_null(encoding, state)? })
			_ => Err(Cbor.invalid_value(encoding, state))
		}
}

# parse_cbor_tag and encode_cbor_tag in a type of an app

uuid_bytes : List(U8)
uuid_bytes = hex("d8255000112233445566778899aabbccddeeff")

expect {
	r : Try(Uuid, _)
	r = Cbor.parse(uuid_bytes)
	r == Ok(Uuid.(hex("00112233445566778899aabbccddeeff")))
}

expect Cbor.encode(Uuid.(hex("00112233445566778899aabbccddeeff"))) == uuid_bytes

## Another tag, the item with no tag, and a short byte string are errors at the tag.
expect {
	r : Try(Uuid, _)
	r = Cbor.parse(hex("d8265000112233445566778899aabbccddeeff"))
	r == Err(InvalidCbor(0))
}

expect {
	r : Try(Uuid, _)
	r = Cbor.parse(hex("5000112233445566778899aabbccddeeff"))
	r == Err(InvalidCbor(0))
}

expect {
	r : Try(Uuid, _)
	r = Cbor.parse(hex("d8254100"))
	r == Err(InvalidCbor(0))
}

## A tag with a head of 1 to 8 bytes: 12 in 1 byte (cc) and in 8 bytes (db 00..0c).
expect {
	r : Try(List(Instant), _)
	r = Cbor.parse(hex("82cc821a690168a01a1dcd6500db000000000000000c820100"))
	r == Ok([Instant.{ secs: 1761700000, nanos: 500000000 }, Instant.{ secs: 1, nanos: 0 }])
}

expect Cbor.encode(Instant.{ secs: 1761700000, nanos: 500000000 }) == hex("cc821a690168a01a1dcd6500")

## Round trip of a record with a field of each type.
expect {
	v : { at : Instant, id : Uuid, link : Link }
	v = { at: Instant.{ secs: -5, nanos: 7 }, id: Uuid.(List.repeat(9, 16)), link: Link.{ table: "person", key: Cbor.Value.Text("ada") } }
	r : Try({ at : Instant, id : Uuid, link : Link }, _)
	r = Cbor.parse(Cbor.encode(v))
	r == Ok(v)
}

## The item after the tag has the wrong type: the error is at the item.
expect {
	r : Try(Instant, _)
	r = Cbor.parse(hex("cc8261780100"))
	r == Err(InvalidCbor(2))
}

## parse_cbor_tag on an item that is not a tag is an error at the item, also inside a record.
expect {
	r : Try({ at : Instant }, _)
	r = Cbor.parse(hex("a1626174820100"))
	r == Err(InvalidCbor(4))
}

## A point.
expect {
	r : Try(Point, _)
	r = Cbor.parse(hex("d85882fb3ff8000000000000fb4004000000000000"))
	r == Ok(Point.{ x: 1.5, y: 2.5 })
}

## A link with a key of each kind: text, a number, an array with a tag in it.
expect {
	r : Try(List(Link), _)
	r = Cbor.parse(hex("83c88266706572736f6e63616461c8826174182ac882617482c88261616178cc820102"))
	r
		== Ok([
			Link.{ table: "person", key: Cbor.Value.Text("ada") },
			Link.{ table: "t", key: Cbor.Value.Int(42) },
			Link.{
				table: "t",
				key: Cbor.Value.Array([Cbor.Value.Tag(8, Cbor.Value.Array([Cbor.Value.Text("a"), Cbor.Value.Text("x")])), Cbor.Value.Tag(12, Cbor.Value.Array([Cbor.Value.Int(1), Cbor.Value.Int(2)]))]),
			},
		])
}

# Cbor.peek

## The kind of each item. peek does not move the state, so the reader after it reads the whole item.
expect {
	r : Try(List(Cell), _)
	r = Cbor.parse(hex("8401617acc820102f6"))
	r == Ok([Cell.Number(1), Cell.Word("z"), Cell.When(Instant.{ secs: 1, nanos: 2 }), Cell.Nothing])
}

## A kind that the type does not take is an error at the item: a float, a map, another tag, bytes.
expect {
	r : Try(Cell, _)
	r = Cbor.parse(hex("f93e00"))
	r == Err(InvalidCbor(0))
}

expect {
	r : Try(List(Cell), _)
	r = Cbor.parse(hex("8201c80102"))
	r == Err(InvalidCbor(2))
}

expect {
	r : Try(Cell, _)
	r = Cbor.parse(hex("a0"))
	r == Err(InvalidCbor(0))
}

## Each kind, from a Cbor.Value parser that records it: peek in a parser_for of an app.
Kinds := List(Cbor.Kind).{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Kinds, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		start = Cbor.parse_list_start(encoding, state)?
		match start {
			Counted({ len, rest }) => {
				var $s = rest
				var $kinds = []
				for _ in (0.U64).until(len) {
					$kinds = $kinds.append(Cbor.peek(encoding, $s)?)
					item : { value : Cbor.Value, rest : Cbor.State }
					item = Cbor.parse_item(encoding, $s)?
					$s = item.rest
				}
				Ok({ value: Kinds.($kinds), rest: $s })
			}
			Uncounted(_) => Err(Cbor.invalid_value(encoding, state))
		}
	}
}

expect {
	r : Try(Kinds, _)
	r = Cbor.parse(hex("8d00204161617780a0c100f4f5f6f7f0f820"))
	match r {
		Ok(Kinds.(kinds)) => kinds == [Int, Int, Bytes, Text, Array, Map, Tag(1), Bool, Bool, Null, Undefined, Simple(16), Simple(32)]
		Err(_) => Bool.False
	}
}

expect {
	r : Try(Kinds, _)
	r = Cbor.parse(hex("83f93e00fa3fc00000fb3ff8000000000000"))
	match r {
		Ok(Kinds.(kinds)) => kinds == [Float, Float, Float]
		Err(_) => Bool.False
	}
}

## Not well formed: an indefinite length, a reserved head (1c), f8 below 32, a break (ff).
expect {
	r : Try(Kinds, _)
	r = Cbor.parse(hex("819f"))
	r == Err(InvalidCbor(1))
}

expect {
	r : Try(Kinds, _)
	r = Cbor.parse(hex("811c"))
	r == Err(InvalidCbor(1))
}

expect {
	r : Try(Kinds, _)
	r = Cbor.parse(hex("81f81f"))
	r == Err(InvalidCbor(1))
}

expect {
	r : Try(Kinds, _)
	r = Cbor.parse(hex("81ff"))
	r == Err(InvalidCbor(1))
}

# Cbor.Value

value_of : Str -> Try(Cbor.Value, [InvalidCbor(U64)])
value_of = |h| Cbor.parse(hex(h))

## Each variant reads, and writes back to the same bytes.
expect {
	cases = [
		("00", Cbor.Value.Int(0)),
		("1bffffffffffffffff", Cbor.Value.Int(18446744073709551615)),
		("3bffffffffffffffff", Cbor.Value.Int(-18446744073709551616)),
		("3863", Cbor.Value.Int(-100)),
		("fb3ff8000000000000", Cbor.Value.Float(1.5)),
		("43010203", Cbor.Value.Bytes([1, 2, 3])),
		("62c3bc", Cbor.Value.Text("\u(fc)")),
		("820102", Cbor.Value.Array([Cbor.Value.Int(1), Cbor.Value.Int(2)])),
		("a201020360", Cbor.Value.Map([(Cbor.Value.Int(1), Cbor.Value.Int(2)), (Cbor.Value.Int(3), Cbor.Value.Text(""))])),
		("c11a514b67b0", Cbor.Value.Tag(1, Cbor.Value.Int(1363896240))),
		("c6f6", Cbor.Value.Tag(6, Cbor.Value.Null)),
		("f4", Cbor.Value.Bool(Bool.False)),
		("f5", Cbor.Value.Bool(Bool.True)),
		("f6", Cbor.Value.Null),
		("f7", Cbor.Value.Undefined),
		("f0", Cbor.Value.Simple(16)),
		("f8ff", Cbor.Value.Simple(255)),
		("80", Cbor.Value.Array([])),
		("a0", Cbor.Value.Map([])),
	]
	cases.all(|(h, v)| value_of(h) == Ok(v) and Cbor.encode(v) == hex(h))
}

## f16 and f32 read as a Float, and write as f64.
expect value_of("f93e00") == Ok(Cbor.Value.Float(1.5))
expect value_of("fa47c35000") == Ok(Cbor.Value.Float(100000.0))
expect Cbor.encode(Cbor.Value.Float(1.5)) == hex("fb3ff8000000000000")

## A tag of a tag, and a map with a key that is there two times: each stays, in order.
expect value_of("d820d8206161") == Ok(Cbor.Value.Tag(32, Cbor.Value.Tag(32, Cbor.Value.Text("a"))))
expect value_of("a2616101616102") == Ok(Cbor.Value.Map([(Cbor.Value.Text("a"), Cbor.Value.Int(1)), (Cbor.Value.Text("a"), Cbor.Value.Int(2))]))

## Nested arrays and maps close in the right order.
expect {
	v = Cbor.Value.Array([Cbor.Value.Map([(Cbor.Value.Text("k"), Cbor.Value.Array([Cbor.Value.Int(1), Cbor.Value.Tag(4, Cbor.Value.Array([]))]))]), Cbor.Value.Int(2), Cbor.Value.Array([Cbor.Value.Array([])])])
	value_of("83a1616b8201c480028180") == Ok(v) and Cbor.encode(v) == hex("83a1616b8201c480028180")
}

## Int outside -2^64 to 2^64 - 1 writes as a bignum (tag 2 or 3), which reads back as a Tag.
expect Cbor.encode(Cbor.Value.Int(18446744073709551616)) == hex("c249010000000000000000")
expect value_of("c249010000000000000000") == Ok(Cbor.Value.Tag(2, Cbor.Value.Bytes([1, 0, 0, 0, 0, 0, 0, 0, 0])))
expect Cbor.encode(Cbor.Value.Int(-18446744073709551617)) == hex("c349010000000000000000")

## Simple(20) to Simple(23) are false, true, null and undefined. Simple(24) to Simple(31) are not valid: undefined.
expect Cbor.encode(Cbor.Value.Simple(20)) == [0xf4]
expect Cbor.encode(Cbor.Value.Simple(23)) == [0xf7]
expect Cbor.encode(Cbor.Value.Simple(24)) == [0xf7]
expect Cbor.encode(Cbor.Value.Simple(19)) == [0xf3]

## Equal when the bytes are equal.
expect Cbor.Value.Simple(22) == Cbor.Value.Null
expect Cbor.Value.Int(1) != Cbor.Value.Float(1.0)
expect Cbor.Value.Float(0.0) != Cbor.Value.Float(-0.0)
expect Cbor.Value.Float(F64.nan) == Cbor.Value.Float(F64.nan)

## A key of a Dict and an item of a Set.
expect {
	d = Dict.empty().insert(Cbor.Value.Text("a"), 1.U64).insert(Cbor.Value.Array([Cbor.Value.Int(1)]), 2)
	d.get(Cbor.Value.Array([Cbor.Value.Int(1)])) == Ok(2) and d.get(Cbor.Value.Text("b")) == Err(KeyNotFound)
}

## Not well formed or not in the profile: an error at the item.
expect value_of("") == Err(InvalidCbor(0))
expect value_of("9f01ff") == Err(InvalidCbor(0))
expect value_of("8201") == Err(InvalidCbor(0))
expect value_of("82018181") == Err(InvalidCbor(3))
expect value_of("82015f") == Err(InvalidCbor(2))
expect value_of("f818") == Err(InvalidCbor(0))
expect value_of("c6") == Err(InvalidCbor(1))
expect value_of("6261ff") == Err(InvalidCbor(0))
expect value_of("0001") == Err(InvalidCbor(1))

## A bad count is an error at the head, not a large list.
expect value_of("9bffffffffffffffff") == Err(InvalidCbor(0))
expect value_of("bb7fffffffffffffff") == Err(InvalidCbor(0))
expect value_of("a3010203") == Err(InvalidCbor(0))

## 100,000 nested arrays and 100,000 nested tags: a loop, not a recursion. The writer is a loop too.
expect {
	deep = List.repeat(0x81, 100000).append(0x00)
	r = value_of_bytes(deep)
	match r {
		Ok(v) => Cbor.encode(v) == deep
		Err(_) => Bool.False
	}
}

expect {
	deep = List.repeat(0xc1, 100000).append(0x00)
	r = value_of_bytes(deep)
	match r {
		Ok(v) => Cbor.encode(v) == deep
		Err(_) => Bool.False
	}
}

value_of_bytes : List(U8) -> Try(Cbor.Value, [InvalidCbor(U64)])
value_of_bytes = |bytes| Cbor.parse(bytes)

## A Cbor.Value field of a record: a null value is no key, as for any field.
expect {
	r : Try({ v : Cbor.Value, w : Try(Cbor.Value, [Missing]) }, _)
	r = Cbor.parse(hex("a26176c2410161776161"))
	r == Ok({ v: Cbor.Value.Tag(2, Cbor.Value.Bytes([1])), w: Ok(Cbor.Value.Text("a")) })
}

expect {
	r : Try({ v : Cbor.Value }, _)
	r = Cbor.parse(hex("a16176f6"))
	r == Err(MissingRequiredField("v"))
}

# Option ignore_tags

tags6 : Cbor.Options
tags6 = { ignore_tags: [6] }

## A tag of the list before null: null. At the root of a Try(a, [Null]), in a list, and as a map value.
expect {
	r : Try(Try(U64, [Null]), _)
	r = Cbor.parse_with(hex("c6f6"), tags6)
	r == Ok(Err(Null))
}

expect {
	r : Try(List(Try(U64, [Null])), _)
	r = Cbor.parse_with(hex("82c6f601"), tags6)
	r == Ok([Err(Null), Ok(1)])
}

## In a map read as a record: no key, the same as a null value (rule N1).
expect {
	r : Try({ name : Str, nick ?: Str, note : Try(Str, [Missing]) }, _)
	r = Cbor.parse_with(hex("a3646e616d656141646e69636bc6f6646e6f7465c6f7"), tags6)
	match r {
		Ok(row) => row.name == "A" and row.?nick == Err(MissingField) and row.note == Err(Missing)
		Err(_) => Bool.False
	}
}

expect {
	r : Try({ name : Str, nick : Str }, _)
	r = Cbor.parse_with(hex("a2646e616d656141646e69636bc6f6"), tags6)
	r == Err(MissingRequiredField("nick"))
}

## With no option, the tag is an error at the tag, and a record field with it is an error too.
expect {
	r : Try(Try(U64, [Null]), _)
	r = Cbor.parse(hex("c6f6"))
	r == Err(InvalidCbor(0))
}

expect {
	r : Try({ nick ?: Str }, _)
	r = Cbor.parse(hex("a1646e69636bc6f6"))
	r == Err(InvalidCbor(6))
}

## A tag that is not in the list stays an error. A tag of the list before another item reads the item.
expect {
	r : Try(Try(U64, [Null]), _)
	r = Cbor.parse_with(hex("c7f6"), tags6)
	r == Err(InvalidCbor(0))
}

expect {
	r : Try({ a : U64, b : Str, c : List(Bool), d : F64, e : Cbor.Bytes, f : (U8, U8), g : [X, Y(U8)] }, _)
	r = Cbor.parse_with(hex("a76161c6016162c661786163c681c6f56164c6fb3ff80000000000006165c641ff6166c682c601c6026167c6a16159c607"), { ignore_tags: [6] })
	r == Ok({ a: 1, b: "x", c: [Bool.True], d: 1.5, e: Cbor.Bytes.([255]), f: (1, 2), g: Y(7) })
}

## A tag before the array of the payloads of a Roc tag: {"Z": 6([6(1), 6("a")])}.
expect {
	r : Try([X, Z(U8, Str)], _)
	r = Cbor.parse_with(hex("a1615ac682c601c66161"), tags6)
	r == Ok(Z(1, "a"))
}

## Several tags of the list, one after the other.
expect {
	r : Try(U8, _)
	r = Cbor.parse_with(hex("c6c7c605"), { ignore_tags: [6, 7] })
	r == Ok(5)
}

## A Cbor.Value keeps each tag, also a tag of the list. peek and parse_cbor_tag see it too.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with(hex("c6f6"), tags6)
	r == Ok(Cbor.Value.Tag(6, Cbor.Value.Null))
}

expect {
	r : Try(Cell, _)
	r = Cbor.parse_with(hex("c6f6"), tags6)
	r == Err(InvalidCbor(0))
}

## The tag 4 of a Dec is a tag like another: in the list, a decimal fraction is an array, so an error.
expect {
	r : Try(Dec, _)
	r = Cbor.parse_with(hex("c482211904e2"), { ignore_tags: [4] })
	r == Err(InvalidCbor(1))
}

# Option dec_from_text

dec_text : Str -> Try(Dec, [InvalidCbor(U64)])
dec_text = |s| Cbor.parse_with(Cbor.encode(s), { dec_from_text: Bool.True })

expect dec_text("12.50") == Ok(12.5)
expect dec_text("4E+1") == Ok(40)
expect dec_text("4e1") == Ok(40)
expect dec_text("0") == Ok(0)
expect dec_text("-0") == Ok(0)
expect dec_text("-1.25e-3") == Ok(-0.00125)
expect dec_text("123456.789E-3") == Ok(123.456789)
expect dec_text("0.000000000000000001") == Ok(0.000000000000000001)
expect dec_text("1.0000000000000000000000000000000000000000000000") == Ok(1)
expect dec_text("170141183.460469231731687303715884105727E+12") == Ok(Dec.highest)
expect dec_text("-170141183460469231731.687303715884105728") == Ok(Dec.lowest)
expect dec_text("0E+99999999999999999999") == Ok(0)
expect dec_text("25E-1") == Ok(2.5)

## More than 18 fraction digits, out of range, or not in the number form of JSON: an error at the text.
expect dec_text("0.0000000000000000001") == Err(InvalidCbor(0))
expect dec_text("170141183460469231732") == Err(InvalidCbor(0))
expect dec_text("1E+99999999999999999999") == Err(InvalidCbor(0))
expect dec_text("1E-99999999999999999999") == Err(InvalidCbor(0))
expect ["", "-", "01", "+1", "1.", ".5", "1e", "1e+", " 1", "1 ", "1.5.5", "0x10", "1_000", "NaN", "Infinity", "1E5.5", "--1"].all(|s| dec_text(s) == Err(InvalidCbor(0)))

## With no option, text is an error, as before.
expect {
	r : Try(Dec, _)
	r = Cbor.parse(Cbor.encode("1.5"))
	r == Err(InvalidCbor(0))
}

## dec_from_text does not change the other types: a U64 and a F64 do not read text.
expect {
	r : Try(U64, _)
	r = Cbor.parse_with(Cbor.encode("1"), { dec_from_text: Bool.True })
	r == Err(InvalidCbor(0))
}

## A peer that sends a decimal as a private tag 10 and text: ignore_tags and dec_from_text together.
## The integers, the decimal fractions (tag 4) and the floats still read.
expect {
	r : Try(List(Dec), _)
	r = Cbor.parse_with(hex("85ca6531322e3530ca6434452b3104c482211904e2f93e00"), { ignore_tags: [10], dec_from_text: Bool.True })
	r == Ok([12.5, 40, 4, 12.5, 1.5])
}

# A whole row of a peer with its own tags

## {"id": 8["person", "ada"], "at": 12[1761700000, 500000000], "price": 10"4E+1", "spot": 88[1.5, 2.5],
##  "uid": 37(h'00..ff'), "nick": 6(null), "extra": 12[0, 0]}
expect {
	Row : { id : Link, at : Instant, price : Dec, spot : Point, uid : Uuid, nick ?: Str }
	bytes = hex("a7626964c88266706572736f6e63616461626174cc821a690168a01a1dcd6500657072696365ca6434452b316473706f74d85882fb3ff8000000000000fb400400000000000063756964d8255000112233445566778899aabbccddeeff646e69636bc6f6656578747261cc820000")
	r : Try(Row, _)
	r = Cbor.parse_with(bytes, { ignore_tags: [6, 10], dec_from_text: Bool.True })
	match r {
		Ok(row) =>
			row.id == Link.{ table: "person", key: Cbor.Value.Text("ada") }
				and row.at == Instant.{ secs: 1761700000, nanos: 500000000 }
				and row.price == 40
				and row.spot == Point.{ x: 1.5, y: 2.5 }
				and row.uid == Uuid.(hex("00112233445566778899aabbccddeeff"))
				and row.?nick == Err(MissingField)
		Err(_) => Bool.False
	}
}
