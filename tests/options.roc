app [] { pkg: "../src/main.roc" }

# The reader options (0.5.0), through the public API of the package: the strict default, each lenient read
# (Cbor.Leniency) on and off, null in a record, duplicate_keys in each reader, unknown_fields, max_items,
# max_depth, the Camel key of two fields, and exact floats.

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

first : Cbor.Options
first = { duplicate_keys: First }

last : Cbor.Options
last = { duplicate_keys: Last }

kind : Cbor.Unions
kind = Internal({ tag: "kind", content: "value" })

# BoolFromInt and FloatToInt

## A Bool reads only false and true. With BoolFromInt, also 0 and 1. A float 1.0 needs FloatToInt too.
expect {
	r : Try(Bool, _)
	r = Cbor.parse([0x01])
	r == Err(InvalidCbor(0))
}

## With BoolFromInt, [false, true, 0, 1] reads as [false, true, false, true].
expect {
	r : Try(List(Bool), _)
	r = Cbor.parse_with([0x84, 0xf4, 0xf5, 0x00, 0x01], { allow: [BoolFromInt] })
	r == Ok([Bool.False, Bool.True, Bool.False, Bool.True])
}

## A float 1.0 (f9 3c 00) as a Bool is an error with BoolFromInt or FloatToInt alone, and true with both.
expect {
	one : List(U8)
	one = [0xf9, 0x3c, 0x00]
	a : Try(Bool, _)
	a = Cbor.parse_with(one, { allow: [BoolFromInt] })
	b : Try(Bool, _)
	b = Cbor.parse_with(one, { allow: [FloatToInt] })
	c : Try(Bool, _)
	c = Cbor.parse_with(one, { allow: [BoolFromInt, FloatToInt] })
	a == Err(InvalidCbor(0)) and b == Err(InvalidCbor(0)) and c == Ok(Bool.True)
}

## An integer type reads only major types 0 and 1. With FloatToInt, a float with no fraction of size 2^53 - 1 or less.
expect {
	r : Try(I64, _)
	r = Cbor.parse([0xf9, 0xc4, 0x00])
	r == Err(InvalidCbor(0))
}

## With FloatToInt, -4.0 (f9 c4 00) and 100000.0 (fa 47c35000) read as the I64 values -4 and 100000.
expect {
	r : Try(List(I64), _)
	r = Cbor.parse_with([0x82, 0xf9, 0xc4, 0x00, 0xfa, 0x47, 0xc3, 0x50, 0x00], { allow: [FloatToInt] })
	r == Ok([-4, 100000])
}

## With FloatToInt, 1.5 (f9 3e 00) as a U64 is an error at byte 0.
expect {
	r : Try(U64, _)
	r = Cbor.parse_with([0xf9, 0x3e, 0x00], { allow: [FloatToInt] })
	r == Err(InvalidCbor(0))
}

# IntFromText and DecFromText

## "-12" reads as an I64 only with IntFromText, and "1.5" reads as a Dec only with DecFromText.
expect {
	a : Try(I64, _)
	a = Cbor.parse(Cbor.encode("-12"))
	b : Try(I64, _)
	b = Cbor.parse_with(Cbor.encode("-12"), { allow: [IntFromText] })
	c : Try(Dec, _)
	c = Cbor.parse(Cbor.encode("1.5"))
	d : Try(Dec, _)
	d = Cbor.parse_with(Cbor.encode("1.5"), { allow: [DecFromText] })
	a == Err(InvalidCbor(0)) and b == Ok(-12) and c == Err(InvalidCbor(0)) and d == Ok(1.5)
}

# UndefinedAsNull

## undefined is not null: an error for each type, except a Cbor.Value. With UndefinedAsNull, it is null.
expect {
	r : Try(Try(U64, [Null]), _)
	r = Cbor.parse([0xf7])
	r == Err(InvalidCbor(0))
}

## With UndefinedAsNull, undefined (f7) reads as Err(Null).
expect {
	r : Try(Try(U64, [Null]), _)
	r = Cbor.parse_with([0xf7], { allow: [UndefinedAsNull] })
	r == Ok(Err(Null))
}

## With UndefinedAsNull, undefined (f7) still reads as Cbor.Value.Undefined.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with([0xf7], { allow: [UndefinedAsNull] })
	r == Ok(Cbor.Value.Undefined)
}

## In a record with NullAsAbsent: undefined is no key only with UndefinedAsNull too.
expect {
	bytes = [0xa1, 0x61, 0x61, 0xf7]
	a : Try({ a : Try(U64, [Missing]) }, _)
	a = Cbor.parse_with(bytes, { allow: [NullAsAbsent] })
	b : Try({ a : Try(U64, [Missing]) }, _)
	b = Cbor.parse_with(bytes, { allow: [NullAsAbsent, UndefinedAsNull] })
	a == Err(InvalidCbor(3)) and b == Ok({ a: Err(Missing) })
}

# PaddedNumbers

## A head longer than needed is an error at the head, also in an unknown field and in a map key.
## With PaddedNumbers, it reads.
expect {
	a : Try(U64, _)
	a = Cbor.parse([0x18, 0x01])
	b : Try(U64, _)
	b = Cbor.parse_with([0x18, 0x01], { allow: [PaddedNumbers] })
	a == Err(InvalidCbor(0)) and b == Ok(1)
}

## {"a": 1, "z": [a byte string with a 2-byte head]} is an error at byte 7, and reads with PaddedNumbers.
expect {
	# {"a": 1, "z": [h'' with a 2 byte head]}
	bytes = [0xa2, 0x61, 0x61, 0x01, 0x61, 0x7a, 0x81, 0x59, 0x00, 0x00]
	a : Try({ a : U64 }, _)
	a = Cbor.parse(bytes)
	b : Try({ a : U64 }, _)
	b = Cbor.parse_with(bytes, { allow: [PaddedNumbers] })
	a == Err(InvalidCbor(7)) and b == Ok({ a: 1 })
}

## The key "a" with a 1-byte length head (78 01 61) is an error at byte 1, and reads with PaddedNumbers.
expect {
	# {"a" with a 1 byte length head: 1}
	bytes = [0xa1, 0x78, 0x01, 0x61, 0x01]
	a : Try({ a : U64 }, _)
	a = Cbor.parse(bytes)
	b : Try({ a : U64 }, _)
	b = Cbor.parse_with(bytes, { allow: [PaddedNumbers] })
	a == Err(InvalidCbor(1)) and b == Ok({ a: 1 })
}

# BytesFromArray

## A List(U8) reads a byte string and an empty array (the writer writes an empty List(U8) as 80).
## A non-empty array needs BytesFromArray. The error is at the array.
expect {
	empty : List(U8)
	empty = []
	a : Try(List(U8), _)
	a = Cbor.parse(Cbor.encode(empty))
	b : Try({ id : U64, data : List(U8) }, _)
	b = Cbor.parse([0xa2, 0x62, 0x69, 0x64, 0x07, 0x64, 0x64, 0x61, 0x74, 0x61, 0x82, 0x01, 0x02])
	c : Try({ id : U64, data : List(U8) }, _)
	c = Cbor.parse_with([0xa2, 0x62, 0x69, 0x64, 0x07, 0x64, 0x64, 0x61, 0x74, 0x61, 0x82, 0x01, 0x02], { allow: [BytesFromArray] })
	Cbor.encode(empty) == [0x80] and a == Ok([]) and b == Err(InvalidCbor(10)) and c == Ok({ id: 7, data: [1, 2] })
}

## A list of lists: the error is at the inner array.
expect {
	r : Try(List(List(U8)), _)
	r = Cbor.parse([0x82, 0x41, 0x05, 0x81, 0x06])
	r == Err(InvalidCbor(3))
}

## Other lists of integers read an array with no option. Cbor.U8Array always reads an array, never a byte string.
expect {
	a : Try(List(U16), _)
	a = Cbor.parse([0x82, 0x01, 0x02])
	b : Try(Cbor.U8Array, _)
	b = Cbor.parse([0x82, 0x01, 0x02])
	c : Try(Cbor.U8Array, _)
	c = Cbor.parse([0x42, 0x01, 0x02])
	a == Ok([1, 2]) and b == Ok(Cbor.U8Array.([1, 2])) and c == Err(InvalidCbor(0))
}

## The writer writes a byte string only when each item of the list is a U8, else an array. Each form reads back
## with no option: a List(Try(U8, [Null])) with a null is an array, and only an array of integers 0 to 255 needs BytesFromArray.
expect {
	lists : List(List(Try(U8, [Null])))
	lists = [[], [Ok(1)], [Ok(1), Err(Null)], [Err(Null), Ok(1)], [Err(Null)]]
	lists.all(
		|v| {
			r : Try(List(Try(U8, [Null])), _)
			r = Cbor.parse(Cbor.encode(v))
			r == Ok(v)
		},
	)
}

## [1, null] reads as a List(Try(U8, [Null])); [1, 2] is an error at byte 0 for it; [1, null] is an error at byte 2 for a List(U8).
expect {
	a : Try(List(Try(U8, [Null])), _)
	a = Cbor.parse([0x82, 0x01, 0xf6])
	b : Try(List(Try(U8, [Null])), _)
	b = Cbor.parse([0x82, 0x01, 0x02])
	c : Try(List(U8), _)
	c = Cbor.parse([0x82, 0x01, 0xf6])
	a == Ok([Ok(1), Err(Null)]) and b == Err(InvalidCbor(0)) and c == Err(InvalidCbor(2))
}

## A nominal type over U8 whose codec calls encode_u8 and parse_u8: a list of it is a byte string, and reads back.
Byte := U8.{
	is_eq : _

	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Byte, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		b = Cbor.parse_u8(encoding, state)?
		Ok({ value: Byte.(b.value), rest: b.rest })
	}

	encoder_for : Cbor -> (Byte, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Byte.(b), w| Cbor.encode_u8(b, w)
}

## A List(Byte) of 1 and 255 writes as the byte string 42 01 ff. It and an empty list read back.
expect {
	v : List(Byte)
	v = [Byte.(1), Byte.(255)]
	empty : List(Byte)
	empty = []
	r : Try(List(Byte), _)
	r = Cbor.parse(Cbor.encode(v))
	e : Try(List(Byte), _)
	e = Cbor.parse(Cbor.encode(empty))
	Cbor.encode(v) == [0x42, 0x01, 0xff] and r == Ok(v) and e == Ok(empty)
}

# Null in a record (no option)

## The value of a key goes to the reader of the field. Err(Null) and Cbor.Value.Null read back.
expect {
	v : { x : Try(Str, [Null]), y : Cbor.Value }
	v = { x: Err(Null), y: Cbor.Value.Null }
	r : Try({ x : Try(Str, [Null]), y : Cbor.Value }, _)
	r = Cbor.parse(Cbor.encode(v))
	Cbor.encode(v) == [0xa2, 0x61, 0x78, 0xf6, 0x61, 0x79, 0xf6] and r == Ok(v)
}

## An optional field, a Try(a, [Missing]) field and a required field with a null: an error at the null.
expect {
	bytes = [0xa2, 0x61, 0x62, 0x01, 0x61, 0x61, 0xf6]
	a : Try({ a ?: Str, b : U8 }, _)
	a = Cbor.parse(bytes)
	b : Try({ a : Try(Str, [Missing]), b : U8 }, _)
	b = Cbor.parse(bytes)
	c : Try({ a : Str, b : U8 }, _)
	c = Cbor.parse(bytes)
	a.is_err() and b == Err(InvalidCbor(6)) and c == Err(InvalidCbor(6))
}

## With NullAsAbsent: the null is no key (rule N1 of 0.4).
expect {
	bytes = [0xa2, 0x61, 0x62, 0x01, 0x61, 0x61, 0xf6]
	opts : Cbor.Options
	opts = { allow: [NullAsAbsent] }
	b : Try({ a : Try(Str, [Missing]), b : U8 }, _)
	b = Cbor.parse_with(bytes, opts)
	c : Try({ a : Try(Str, [Null]), b : U8 }, _)
	c = Cbor.parse_with(bytes, opts)
	b == Ok({ a: Err(Missing), b: 1 }) and c == Err(MissingRequiredField("a"))
}

# duplicate_keys: a record

## {"a": 1, "b": 2, "a": 3}: Reject is an error at the second "a". First and Last read that instance.
dup_ab : List(U8)
dup_ab = [0xa3, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02, 0x61, 0x61, 0x03]

## With no option, an error at byte 7. First reads {a: 1, b: 2}, Last reads {a: 3, b: 2}.
expect {
	a : Try({ a : U64, b : U64 }, _)
	a = Cbor.parse(dup_ab)
	b : Try({ a : U64, b : U64 }, _)
	b = Cbor.parse_with(dup_ab, first)
	c : Try({ a : U64, b : U64 }, _)
	c = Cbor.parse_with(dup_ab, last)
	a == Err(InvalidCbor(7)) and b == Ok({ a: 1, b: 2 }) and c == Ok({ a: 3, b: 2 })
}

## An unknown key two times is a duplicate too: {"z": 1, "a": 1, "z": 2}.
expect {
	r : Try({ a : U64 }, _)
	r = Cbor.parse([0xa3, 0x61, 0x7a, 0x01, 0x61, 0x61, 0x01, 0x61, 0x7a, 0x02])
	r == Err(InvalidCbor(7))
}

## A null value counts as a key: {"a": null, "a": 5} with NullAsAbsent.
expect {
	bytes = [0xa2, 0x61, 0x61, 0xf6, 0x61, 0x61, 0x05]
	a : Try({ a : Try(U64, [Missing]) }, _)
	a = Cbor.parse_with(bytes, { allow: [NullAsAbsent] })
	b : Try({ a : Try(U64, [Missing]) }, _)
	b = Cbor.parse_with(bytes, { allow: [NullAsAbsent], duplicate_keys: First })
	c : Try({ a : Try(U64, [Missing]) }, _)
	c = Cbor.parse_with(bytes, { allow: [NullAsAbsent], duplicate_keys: Last })
	a == Err(InvalidCbor(4)) and b == Ok({ a: Err(Missing) }) and c == Ok({ a: Ok(5) })
}

## A duplicate key in a nested map, also in an unknown field that the record skips.
expect {
	# {"o": {"x": 1, "x": 2}, "u": {"y": 1, "y": 2}}
	bytes = [0xa2, 0x61, 0x6f, 0xa2, 0x61, 0x78, 0x01, 0x61, 0x78, 0x02, 0x61, 0x75, 0xa2, 0x61, 0x79, 0x01, 0x61, 0x79, 0x02]
	a : Try({ o : { x : U64 } }, _)
	a = Cbor.parse(bytes)
	b : Try({ o : { x : U64 } }, _)
	b = Cbor.parse_with(bytes, last)
	a == Err(InvalidCbor(7)) and b == Ok({ o: { x: 2 } })
}

# duplicate_keys: a Dict

## {"a": 1, "b": 2, "a": 3} as a Dict: an error at byte 7, "a" is 1 with First and 3 with Last.
expect {
	a : Try(Dict(Str, U64), _)
	a = Cbor.parse(dup_ab)
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with(dup_ab, first)
	c : Try(Dict(Str, U64), _)
	c = Cbor.parse_with(dup_ab, last)
	a == Err(InvalidCbor(7)) and b == Ok(Dict.from_list([("a", 1), ("b", 2)])) and c == Ok(Dict.from_list([("a", 3), ("b", 2)]))
}

## A Dict in a Dict and a Dict in a list, each with a key to skip: each map ends at its own end.
expect {
	# {"x": {"a": 1, "a": 2}, "y": {"b": 3}, "x": {}}
	bytes = [0xa3, 0x61, 0x78, 0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02, 0x61, 0x79, 0xa1, 0x61, 0x62, 0x03, 0x61, 0x78, 0xa0]
	a : Try(Dict(Str, Dict(Str, U64)), _)
	a = Cbor.parse_with(bytes, first)
	b : Try(Dict(Str, Dict(Str, U64)), _)
	b = Cbor.parse_with(bytes, last)
	a == Ok(Dict.from_list([("x", Dict.from_list([("a", 1)])), ("y", Dict.from_list([("b", 3)]))]))
		and b == Ok(Dict.from_list([("x", Dict.empty()), ("y", Dict.from_list([("b", 3)]))]))
}

## [{"a": 1, "a": 2}, {"b": 3}] with First reads as [{"a": 1}, {"b": 3}].
expect {
	# [{"a": 1, "a": 2}, {"b": 3}]
	bytes = [0x82, 0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02, 0xa1, 0x61, 0x62, 0x03]
	r : Try(List(Dict(Str, U64)), _)
	r = Cbor.parse_with(bytes, first)
	r == Ok([Dict.from_list([("a", 1)]), Dict.from_list([("b", 3)])])
}

# duplicate_keys: the keys of an internal tag (F4)

Pay : [Card({ kind : Str, last4 : Str }), Evil({ kind : Str, last4 : Str }), Check(U64)]

## {"kind": "Card", "kind": "Evil", "last4": "1"}: the tag and the record field come from the same instance.
f4 : List(U8)
f4 = hex("a3646b696e646443617264646b696e64644576696c656c617374346131")

## With no duplicate_keys option, the second "kind" key is an error at byte 11.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with(f4, { unions: kind })
	r == Err(InvalidCbor(11))
}

## First reads Card and Last reads Evil, each with last4 "1".
expect {
	a : Try(Pay, _)
	a = Cbor.parse_with(f4, { unions: kind, duplicate_keys: First })
	b : Try(Pay, _)
	b = Cbor.parse_with(f4, { unions: kind, duplicate_keys: Last })
	a == Ok(Card({ kind: "Card", last4: "1" })) and b == Ok(Evil({ kind: "Evil", last4: "1" }))
}

## {"kind": "Check", "value": 1, "value": 2}: the content key.
check_twice : List(U8)
check_twice = hex("a3646b696e6465436865636b6576616c7565016576616c756502")

## With no option, an error at the second "value" key, byte 19. First reads Check(1), Last reads Check(2).
expect {
	a : Try(Pay, _)
	a = Cbor.parse_with(check_twice, { unions: kind })
	b : Try(Pay, _)
	b = Cbor.parse_with(check_twice, { unions: kind, duplicate_keys: First })
	c : Try(Pay, _)
	c = Cbor.parse_with(check_twice, { unions: kind, duplicate_keys: Last })
	a == Err(InvalidCbor(19)) and b == Ok(Check(1)) and c == Ok(Check(2))
}

# duplicate_keys: a Cbor.Value

## A Cbor.Value map of distinct keys.
vmap : List((Cbor.Value, Cbor.Value)) -> Cbor.Value
vmap = |pairs|
	match Cbor.ValueMap.from_list(pairs) {
		Ok(m) => Cbor.Value.Map(m)
		Err(_) => crash "a duplicate key in a test map"
	}

## A Cbor.Value map {"a": 1, "a": 2}: an error at byte 4, {"a": 1} with First, {"a": 2} with Last.
expect {
	bytes = [0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02]
	a : Try(Cbor.Value, _)
	a = Cbor.parse(bytes)
	b : Try(Cbor.Value, _)
	b = Cbor.parse_with(bytes, first)
	c : Try(Cbor.Value, _)
	c = Cbor.parse_with(bytes, last)
	a == Err(InvalidCbor(4)) and b == Ok(vmap([(Text("a"), Int(1))])) and c == Ok(vmap([(Text("a"), Int(2))]))
}

## The keys of a Cbor.Value map are equal when they are equal as Cbor.Value: 1.0 as f16 and as f64, [1] and [1] with a long head.
expect {
	floats = [0xa2, 0xf9, 0x3c, 0x00, 0x01, 0xfb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0, 0x02]
	a : Try(Cbor.Value, _)
	a = Cbor.parse(floats)
	arrays = [0xa2, 0x81, 0x01, 0x01, 0x98, 0x01, 0x18, 0x01, 0x02]
	b : Try(Cbor.Value, _)
	b = Cbor.parse_with(arrays, { allow: [PaddedNumbers] })
	c : Try(Cbor.Value, _)
	c = Cbor.parse_with(arrays, { allow: [PaddedNumbers], duplicate_keys: Last })
	a == Err(InvalidCbor(5)) and b == Err(InvalidCbor(4)) and c == Ok(vmap([(Array([Int(1)]), Int(2))]))
}

## A Cbor.Value field of a record and a map in an array, with Last.
expect {
	# {"v": [{"k": 1, "j": 0, "k": 2}]}
	bytes = [0xa1, 0x61, 0x76, 0x81, 0xa3, 0x61, 0x6b, 0x01, 0x61, 0x6a, 0x00, 0x61, 0x6b, 0x02]
	r : Try({ v : Cbor.Value }, _)
	r = Cbor.parse_with(bytes, last)
	r == Ok({ v: Cbor.Value.Array([vmap([(Text("j"), Int(0)), (Text("k"), Int(2))])]) })
}

## 1000 keys, the same key at 0, 500 and 999: the sort finds each.
expect {
	keys : List(Str)
	keys = (0.U64).until(1000).map(|i| if (i == 0 or i == 500 or i == 999) "a" else "k${i.to_str()}").collect()
	entries : List(List(U8))
	entries = keys.map(|k| Cbor.encode(k).append(0x00))
	bytes = [0xb9, 0x03, 0xe8].concat(entries.join())
	a : Try(Cbor.Value, _)
	a = Cbor.parse(bytes)
	b : Try(Dict(Str, U8), _)
	b = Cbor.parse_with(bytes, last)
	at_500 = entries.take_first(500).map(|e| e.len()).sum() + 3
	a == Err(InvalidCbor(at_500)) and b.map_ok(|d| d.len()) == Ok(998)
}

# unknown_fields

## Skip (default): an unknown key is skipped. Reject: an error at the key.
expect {
	bytes = [0xa2, 0x61, 0x61, 0x01, 0x61, 0x7a, 0x02]
	a : Try({ a : U64 }, _)
	a = Cbor.parse(bytes)
	b : Try({ a : U64 }, _)
	b = Cbor.parse_with(bytes, { unknown_fields: Reject })
	a == Ok({ a: 1 }) and b == Err(InvalidCbor(4))
}

## The tag key of an internal tag is not an unknown field of its record payload. Another key is.
expect {
	ok_bytes = hex("a2646b696e646443617264656c617374346131")
	a : Try([Card({ last4 : Str })], _)
	a = Cbor.parse_with(ok_bytes, { unions: kind, unknown_fields: Reject })
	extra = hex("a3646b696e646443617264656c6173743461316178f6")
	b : Try([Card({ last4 : Str })], _)
	b = Cbor.parse_with(extra, { unions: kind, unknown_fields: Reject })
	a == Ok(Card({ last4: "1" })) and b == Err(InvalidCbor(19))
}

## A Dict has no unknown key.
expect {
	r : Try(Dict(Str, U64), _)
	r = Cbor.parse_with([0xa1, 0x61, 0x7a, 0x02], { unknown_fields: Reject })
	r == Ok(Dict.from_list([("z", 2)]))
}

# max_items and max_depth

## [1, 2, 3] is 4 items, {"a": 1} is 3, a tag and its item are 2. One item more than the limit: an error at that item.
expect {
	a : Try(List(U64), _)
	a = Cbor.parse_with([0x83, 0x01, 0x02, 0x03], { max_items: 4 })
	b : Try(List(U64), _)
	b = Cbor.parse_with([0x83, 0x01, 0x02, 0x03], { max_items: 3 })
	c : Try({ a : U64 }, _)
	c = Cbor.parse_with([0xa1, 0x61, 0x61, 0x01], { max_items: 2 })
	d : Try(Cbor.Value, _)
	d = Cbor.parse_with([0xc1, 0x01], { max_items: 1 })
	a == Ok([1, 2, 3]) and b == Err(InvalidCbor(3)) and c == Err(InvalidCbor(3)) and d == Err(InvalidCbor(1))
}

## The items of an unknown field count too.
expect {
	r : Try({ a : U64 }, _)
	r = Cbor.parse_with([0xa2, 0x61, 0x61, 0x01, 0x61, 0x7a, 0x82, 0x00, 0x00], { max_items: 6 })
	r == Err(InvalidCbor(8))
}

## With max_depth 2, [[1]] reads and [[[1]]] is an error at the third array, byte 2.
expect {
	a : Try(List(List(U64)), _)
	a = Cbor.parse_with([0x81, 0x81, 0x01], { max_depth: 2 })
	b : Try(List(List(List(U64))), _)
	b = Cbor.parse_with([0x81, 0x81, 0x81, 0x01], { max_depth: 2 })
	a == Ok([[1]]) and b == Err(InvalidCbor(2))
}

# fields: Camel (F7)

## Two fields with one key (a_1 and a1 are both "a1"): an error at the key. Snake has no such pair.
expect {
	r : Try({ a_1 : U64, a1 : U64 }, _)
	r = Cbor.parse_with([0xa1, 0x62, 0x61, 0x31, 0x01], { fields: Camel })
	r == Err(InvalidCbor(1))
}

## With no option (snake keys), {"a1": 1, "a_1": 2} reads as a1 = 1 and a_1 = 2.
expect {
	bytes = [0xa2, 0x62, 0x61, 0x31, 0x01, 0x63, 0x61, 0x5f, 0x31, 0x02]
	r : Try({ a_1 : U64, a1 : U64 }, _)
	r = Cbor.parse(bytes)
	r == Ok({ a_1: 2, a1: 1 })
}

## MissingRequiredField names the Roc field, not the key.
expect {
	r : Try({ user_id : U64, display_name : Str }, _)
	r = Cbor.parse_with([0xa1, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x07], { fields: Camel })
	r == Err(MissingRequiredField("display_name"))
}

## Camel: a capital after each `_` (also after `__`), a digit stays, and the snake key is not read.
expect {
	r : Try({ a__b : U64, x_1y : U64 }, _)
	r = Cbor.parse_with(Cbor.encode_with({ a__b: 1.U64, x_1y: 2.U64 }, { fields: Camel }) ?? [], { fields: Camel })
	s : Try({ a__b : U64 }, _)
	s = Cbor.parse_with(Cbor.encode({ a__b: 1.U64 }), { fields: Camel })
	r == Ok({ a__b: 1, x_1y: 2 }) and s == Err(MissingRequiredField("a__b"))
}

## Camel: a field name that is the start of a key is not that key. `user` and `userName` read, `username` is no field.
expect {
	r : Try({ user : U64, user_name : U64 }, _)
	r = Cbor.parse_with(Cbor.encode_with({ user: 1.U64, user_name: 2.U64 }, { fields: Camel }) ?? [], { fields: Camel, unknown_fields: Reject })
	s : Try({ user : U64, user_name : U64 }, _)
	s = Cbor.parse_with([0xa2, 0x64, 'u', 's', 'e', 'r', 0x01, 0x68, 'u', 's', 'e', 'r', 'n', 'a', 'm', 'e', 0x02], { fields: Camel, unknown_fields: Reject })
	r == Ok({ user: 1, user_name: 2 }) and s == Err(InvalidCbor(7))
}

# Exact floats (F9)

## An F32 that is not 0 but rounds to 0 is an error. A small F32 that does not round to 0 reads.
expect {
	a : Try(F32, _)
	a = Cbor.parse(hex("fb01a56e1fc2f8f359"))
	b : Try(F32, _)
	b = Cbor.parse(hex("fb37a16c262777579c"))
	c : Try(F32, _)
	c = Cbor.parse(hex("fb8000000000000000"))
	a == Err(InvalidCbor(0)) and b.map_ok(|f| f > 0.0) == Ok(Bool.True) and c.map_ok(|f| f == 0.0) == Ok(Bool.True)
}

## An integer reads as a float only when the float is exact: 2^53 + 1 and 2^64 - 1 are errors, 2^53 and -2^64 read.
expect {
	a : Try(F64, _)
	a = Cbor.parse(hex("1b0020000000000001"))
	b : Try(F64, _)
	b = Cbor.parse(hex("1bffffffffffffffff"))
	c : Try(F64, _)
	c = Cbor.parse(hex("1b0020000000000000"))
	d : Try(F64, _)
	d = Cbor.parse(hex("3bffffffffffffffff"))
	a == Err(InvalidCbor(0)) and b == Err(InvalidCbor(0)) and c == Ok(9007199254740992.0) and d == Ok(-18446744073709551616.0)
}

## An F32: an integer exact as an F32 (2^24) reads, 2^24 + 1 is an error.
expect {
	a : Try(F32, _)
	a = Cbor.parse(hex("1a01000000"))
	b : Try(F32, _)
	b = Cbor.parse(hex("1a01000001"))
	a == Ok(16777216.0) and b == Err(InvalidCbor(0))
}

# Cbor.sql_rows

## Cbor.sql_rows is [BoolFromInt, FloatToInt, NullAsAbsent, UndefinedAsNull, BytesFromArray].
expect Cbor.sql_rows == [BoolFromInt, FloatToInt, NullAsAbsent, UndefinedAsNull, BytesFromArray]

## IntFromText also reads a 128-bit integer type.
expect {
	r : Try(U128, _)
	r = Cbor.parse_with([0x63, '1', '2', '3'], { allow: [IntFromText] })
	r == Ok(123)
}

## IntFromText reads "-123" as an I128.
expect {
	r : Try(I128, _)
	r = Cbor.parse_with([0x64, '-', '1', '2', '3'], { allow: [IntFromText] })
	r == Ok(-123)
}

## The text `s` read as a U128 with IntFromText.
u128_text : Str -> Try(U128, Cbor.Error)
u128_text = |s| Cbor.parse_with(Cbor.encode(s), { allow: [IntFromText] })

## The text `s` read as an I128 with IntFromText.
i128_text : Str -> Try(I128, Cbor.Error)
i128_text = |s| Cbor.parse_with(Cbor.encode(s), { allow: [IntFromText] })

## The text `s` read as a U64 with IntFromText.
u64_text : Str -> Try(U64, Cbor.Error)
u64_text = |s| Cbor.parse_with(Cbor.encode(s), { allow: [IntFromText] })

## IntFromText reads each U128: 2^64 and the maximum. The maximum + 1 (39 digits) and 40 digits are errors, with no wrap.
expect u128_text("18446744073709551616") == Ok(18446744073709551616)

## IntFromText reads the U128 maximum.
expect u128_text("340282366920938463463374607431768211455") == Ok(340282366920938463463374607431768211455)

## IntFromText: the U128 maximum + 1 is an error at byte 0.
expect u128_text("340282366920938463463374607431768211456") == Err(InvalidCbor(0))

## IntFromText: 39 nines is above the U128 maximum, an error at byte 0.
expect u128_text("999999999999999999999999999999999999999") == Err(InvalidCbor(0))

## IntFromText: a U128 text of 40 digits is an error at byte 0.
expect u128_text("1000000000000000000000000000000000000000") == Err(InvalidCbor(0))

## IntFromText: "-1" is an error at byte 0 for a U128.
expect u128_text("-1") == Err(InvalidCbor(0))

## IntFromText reads each I128: the minimum and the maximum. One past each end is an error.
expect i128_text("-170141183460469231731687303715884105728") == Ok(I128.lowest)

## IntFromText reads the I128 maximum.
expect i128_text("170141183460469231731687303715884105727") == Ok(I128.highest)

## IntFromText: the I128 minimum - 1 is an error at byte 0.
expect i128_text("-170141183460469231731687303715884105729") == Err(InvalidCbor(0))

## IntFromText: the I128 maximum + 1 is an error at byte 0.
expect i128_text("170141183460469231731687303715884105728") == Err(InvalidCbor(0))

## IntFromText reads "-18446744073709551617", below -2^64, as an I128.
expect i128_text("-18446744073709551617") == Ok(-18446744073709551617)

## IntFromText: "-" and 40 digits is an error at byte 0 for an I128.
expect i128_text("-1000000000000000000000000000000000000000") == Err(InvalidCbor(0))

## The text must be canonical: no leading zero, no `-0`, no `+`, no space. 0 reads.
expect u128_text("0") == Ok(0) and i128_text("0") == Ok(0)

## A leading zero ("0123", "-0123") is an error at byte 0.
expect u128_text("0123") == Err(InvalidCbor(0)) and i128_text("-0123") == Err(InvalidCbor(0))

## "-0" is an error at byte 0 for an I128 and a U128.
expect i128_text("-0") == Err(InvalidCbor(0)) and u128_text("-0") == Err(InvalidCbor(0))

## A "+" sign ("+1") is an error at byte 0 for a U128 and an I128.
expect u128_text("+1") == Err(InvalidCbor(0)) and i128_text("+1") == Err(InvalidCbor(0))

## A space before or after the digits (" 1", "1 ") is an error at byte 0.
expect u128_text(" 1") == Err(InvalidCbor(0)) and i128_text("1 ") == Err(InvalidCbor(0))

## Empty text and "-" alone are errors at byte 0.
expect u128_text("") == Err(InvalidCbor(0)) and i128_text("-") == Err(InvalidCbor(0))

## A smaller type keeps its range: U64 text above the U64 maximum is an error.
expect u64_text("18446744073709551615") == Ok(18446744073709551615)

## U64 text of the U64 maximum + 1 is an error at byte 0.
expect u64_text("18446744073709551616") == Err(InvalidCbor(0))

## U64 text of the U128 maximum is an error at byte 0.
expect u64_text("340282366920938463463374607431768211455") == Err(InvalidCbor(0))

# BytesFromBase64

b64 : Cbor.Options
b64 = { allow: [BytesFromBase64] }

b64_alphabet : List(U8)
b64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()

## The base64 text of `bytes` (RFC 4648 4), with padding.
to_base64 : List(U8) -> Str
to_base64 = |bytes| {
	var $out = []
	for group in bytes.chunks_of(3) {
		x = group.get(0) ?? 0
		y = group.get(1) ?? 0
		z = group.get(2) ?? 0
		v = x.to_u32().shl_wrap(16).bitwise_or(y.to_u32().shl_wrap(8)).bitwise_or(z.to_u32())
		char = |i| b64_alphabet.get(v.shr_zf_wrap(18 - 6 * i).bitwise_and(63).to_u64()) ?? '?'
		$out = $out.append(char(0)).append(char(1))
		$out = $out.append(if (group.len() > 1) char(2) else '=')
		$out = $out.append(if (group.len() > 2) char(3) else '=')
	}
	Str.from_utf8($out) ?? ""
}

## The text `s` read with BytesFromBase64 as a Cbor.Bytes and as a List(U8). The two must agree.
from_text : Str -> Try(List(U8), Cbor.Error)
from_text = |s| {
	a : Try(Cbor.Bytes, Cbor.Error)
	a = Cbor.parse_with(Cbor.encode(s), b64)
	l : Try(List(U8), Cbor.Error)
	l = Cbor.parse_with(Cbor.encode(s), b64)
	if (a.map_ok(|x| x.to_list()) == l) l else Err(InvalidCbor(999))
}

## The test vectors of RFC 4648 10.
expect from_text("") == Ok([])

## Base64 "Zg==" reads as "f".
expect from_text("Zg==") == Ok("f".to_utf8())

## Base64 "Zm8=" reads as "fo".
expect from_text("Zm8=") == Ok("fo".to_utf8())

## Base64 "Zm9v" reads as "foo".
expect from_text("Zm9v") == Ok("foo".to_utf8())

## Base64 "Zm9vYg==" reads as "foob".
expect from_text("Zm9vYg==") == Ok("foob".to_utf8())

## Base64 "Zm9vYmE=" reads as "fooba".
expect from_text("Zm9vYmE=") == Ok("fooba".to_utf8())

## Base64 "Zm9vYmFy" reads as "foobar".
expect from_text("Zm9vYmFy") == Ok("foobar".to_utf8())

## Each byte value reads back, with each length of the last group (0, 1 and 2 bytes of padding).
expect {
	var $all = []
	for i in (0.U64).until(256) {
		$all = $all.append(i.to_u8_wrap())
	}
	all = $all
	[0, 1, 2].all(|k| from_text(to_base64(all.drop_first(k))) == Ok(all.drop_first(k)))
}

## Each text that is not base64 is an error at the text: padding missing, extra or not at the end.
expect from_text("Zg") == Err(InvalidCbor(0)) and from_text("Zm8") == Err(InvalidCbor(0)) and from_text("Z") == Err(InvalidCbor(0))

## Too much padding ("Zg===", "Z===", "====") is an error at byte 0.
expect from_text("Zg===") == Err(InvalidCbor(0)) and from_text("Z===") == Err(InvalidCbor(0)) and from_text("====") == Err(InvalidCbor(0))

## Padding not at the end ("Zg==Zg==", "Z=g=", "Zm=v") is an error at byte 0.
expect from_text("Zg==Zg==") == Err(InvalidCbor(0)) and from_text("Z=g=") == Err(InvalidCbor(0)) and from_text("Zm=v") == Err(InvalidCbor(0))

## The unused bits before the padding must be zero (RFC 4648 3.5): one text for each byte list.
expect from_text("Zg==") == Ok(['f']) and from_text("Zh==") == Err(InvalidCbor(0)) and from_text("Zv==") == Err(InvalidCbor(0))

## "Zm8=" reads as "fo". "Zm9=" and "Zm/=" have unused bits set: errors at byte 0.
expect from_text("Zm8=") == Ok(['f', 'o']) and from_text("Zm9=") == Err(InvalidCbor(0)) and from_text("Zm/=") == Err(InvalidCbor(0))

## White space, line breaks, base64url and text that is not ASCII are errors.
expect from_text(" Zg=") == Err(InvalidCbor(0)) and from_text("Zg==\n") == Err(InvalidCbor(0)) and from_text("Zm9v\r\nYg==") == Err(InvalidCbor(0))

## A space or a tab inside the text ("Zm 9", "Zm9v" tab "YmFy") is an error at byte 0.
expect from_text("Zm 9") == Err(InvalidCbor(0)) and from_text("Zm9v\tYmFy") == Err(InvalidCbor(0))

## The base64url characters - and _ are errors at byte 0.
expect from_text("-_-_") == Err(InvalidCbor(0)) and from_text("Zm9v-w==") == Err(InvalidCbor(0)) and from_text("Zm9v_w==") == Err(InvalidCbor(0))

## "+/+/" reads as fb ff bf.
expect from_text("+/+/") == Ok([0xfb, 0xff, 0xbf])

## Text that is not ASCII ("éé", "Zm9vé===") is an error at byte 0.
expect from_text("éé") == Err(InvalidCbor(0)) and from_text("Zm9vé===") == Err(InvalidCbor(0))

## Without the leniency, text is an error for a List(U8) and a Cbor.Bytes.
expect {
	a : Try(Cbor.Bytes, _)
	a = Cbor.parse(Cbor.encode("Zm9v"))
	l : Try(List(U8), _)
	l = Cbor.parse_with(Cbor.encode("Zm9v"), { allow: [BytesFromArray] })
	a == Err(InvalidCbor(0)) and l == Err(InvalidCbor(0))
}

## Str, Cbor.Value and Cbor.U8Array do not change.
expect {
	s : Try(Str, _)
	s = Cbor.parse_with(Cbor.encode("Zm9v"), b64)
	v : Try(Cbor.Value, _)
	v = Cbor.parse_with(Cbor.encode("Zm9v"), b64)
	u : Try(Cbor.U8Array, _)
	u = Cbor.parse_with(Cbor.encode("Zm9v"), b64)
	s == Ok("Zm9v") and v == Ok(Text("Zm9v")) and u == Err(InvalidCbor(0))
}

## Record fields, and the items after them: the reader goes back to the input after the bytes of the text.
expect {
	bytes = Cbor.encode({ id: 7.U8, data: "Zm9v", blob: "YmFy", empty: "", after: "end" })
	r : Try({ id : U8, data : List(U8), blob : Cbor.Bytes, empty : List(U8), after : Str }, _)
	r = Cbor.parse_with(bytes, b64)
	r == Ok({ id: 7, data: "foo".to_utf8(), blob: Cbor.Bytes.from_list("bar".to_utf8()), empty: [], after: "end" })
}

## Text that is not base64 in a field is an error at that text.
expect {
	bytes = Cbor.encode({ a: 1.U8, data: "Zh==" })
	r : Try({ a : U8, data : List(U8) }, _)
	r = Cbor.parse_with(bytes, b64)
	# a2 61 61 01 64 64 61 74 61: the text is at 9.
	r == Err(InvalidCbor(9))
}

## A list of byte lists, a tuple, and a byte string next to the text.
expect {
	l : Try(List(List(U8)), _)
	l = Cbor.parse_with(Cbor.encode(["Zg==", "", "Zm8="]), b64)
	t : Try((List(U8), U8, List(U8)), _)
	t = Cbor.parse_with([0x83, 0x64, 'Z', 'm', '9', 'v', 0x05, 0x42, 0x01, 0x02], b64)
	l == Ok([['f'], [], ['f', 'o']]) and t == Ok(("foo".to_utf8(), 5, [1, 2]))
}

## With BytesFromArray too, a List(U8) reads an array, a byte string and base64 text.
expect {
	r : Try(List(List(U8)), _)
	r = Cbor.parse_with([0x83, 0x82, 0x01, 0x02, 0x41, 0x03, 0x64, 'Z', 'm', '9', 'v'], { allow: [BytesFromArray, BytesFromBase64] })
	r == Ok([[1, 2], [3], "foo".to_utf8()])
}

## Another list type does not read the text: the error is at the text, not in its bytes.
expect {
	r : Try((U8, List(U16)), _)
	r = Cbor.parse_with([0x82, 0x01, 0x64, 'A', 'A', 'A', 'A'], b64)
	s : Try(List(Str), _)
	s = Cbor.parse_with([0x64, 'A', 'A', 'A', 'A'], b64)
	r == Err(InvalidCbor(2)) and s == Err(InvalidCbor(0))
}

## Text of indefinite length (IndefiniteLength): the chunks are joined, then read as base64.
expect {
	bytes = [0x7f, 0x63, 'Z', 'm', '9', 0x65, 'v', 'Y', 'm', 'F', 'y', 0xff]
	opts : Cbor.Options
	opts = { allow: [IndefiniteLength, BytesFromBase64] }
	l : Try(List(U8), _)
	l = Cbor.parse_with(bytes, opts)
	a : Try(Cbor.Bytes, _)
	a = Cbor.parse_with(bytes, opts)
	l == Ok("foobar".to_utf8()) and a == Ok(Cbor.Bytes.from_list("foobar".to_utf8()))
}
