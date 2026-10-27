app [] { pkg: "../src/main.roc" }

# Rows from SQL databases (0.2.2), through the public API of the package.
# A SQL database (SQLite, D1) has no boolean: it gives the integers 0 and 1. A nullable column gives NULL.
# Rules: a Bool reads 0 and 1. In a map, a null (or undefined) value is the same as no key, in both directions.
# Map bytes: {"a": null} is a1 61 61 f6, {"a": 0} is a1 61 61 00.

import pkg.Cbor

# Bool from the integers 0 and 1

## A Bool field reads 0 as false and 1 as true.
expect {
	r : Try({ a : Bool }, _)
	r = Cbor.parse([0xa1, 0x61, 0x61, 0x00])
	r == Ok({ a: Bool.False })
}

expect {
	r : Try({ a : Bool }, _)
	r = Cbor.parse([0xa1, 0x61, 0x61, 0x01])
	r == Ok({ a: Bool.True })
}

## Any argument width: 1 in 1 byte (18 01) and in 8 bytes.
expect {
	r : Try(List(Bool), _)
	r = Cbor.parse([0x82, 0x18, 0x01, 0x1b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
	r == Ok([Bool.True, Bool.False])
}

## false, true, 0 and 1 in one list.
expect {
	r : Try(List(Bool), _)
	r = Cbor.parse([0x84, 0xf4, 0xf5, 0x00, 0x01])
	r == Ok([Bool.False, Bool.True, Bool.False, Bool.True])
}

## Another integer is an error at the integer: 2, -1 (20), 256 (19 01 00).
expect {
	r : Try({ a : Bool }, _)
	r = Cbor.parse([0xa1, 0x61, 0x61, 0x02])
	r == Err(InvalidCbor(3))
}

expect {
	r : Try(List(Bool), _)
	r = Cbor.parse([0x82, 0x01, 0x20])
	r == Err(InvalidCbor(2))
}

expect {
	r : Try(Bool, _)
	r = Cbor.parse([0x19, 0x01, 0x00])
	r == Err(InvalidCbor(0))
}

## A float follows the integer rules: 1.0 (f9 3c 00) is true, 0.5 (f9 38 00) is an error.
expect {
	r : Try(Bool, _)
	r = Cbor.parse([0xf9, 0x3c, 0x00])
	r == Ok(Bool.True)
}

expect {
	r : Try(Bool, _)
	r = Cbor.parse([0xf9, 0x38, 0x00])
	r == Err(InvalidCbor(0))
}

## Text is not a Bool, also with int_from_text: "1" (61 31).
expect {
	r : Try(Bool, _)
	r = Cbor.parse_with([0x61, 0x31], { int_from_text: Bool.True })
	r == Err(InvalidCbor(0))
}

## null is not a Bool.
expect {
	r : Try(List(Bool), _)
	r = Cbor.parse([0x81, 0xf6])
	r == Err(InvalidCbor(1))
}

## A byte string is not a list of Bool: its byte 01 is not an item.
expect {
	r : Try(List(Bool), _)
	r = Cbor.parse([0x41, 0x01])
	r == Err(InvalidCbor(1))
}

## The writer stays CBOR false and true.
expect Cbor.encode([Bool.False, Bool.True]) == [0x82, 0xf4, 0xf5]

# A null value in a map is the same as no key

## An optional field: a null is absent. The fields before and after it read.
expect {
	r : Try({ a ?: Str, b : U8, c : U8 }, _)
	r = Cbor.parse([0xa3, 0x61, 0x62, 0x01, 0x61, 0x61, 0xf6, 0x61, 0x63, 0x02])
	match r {
		Ok(v) => v.?a.is_err() and v.b == 1 and v.c == 2
		Err(_) => Bool.False
	}
}

## An optional field with a value still reads it.
expect {
	r : Try({ a ?: Str }, _)
	r = Cbor.parse([0xa1, 0x61, 0x61, 0x61, 0x78])
	match r {
		Ok(v) => v.?a == Ok("x")
		Err(_) => Bool.False
	}
}

## A Try(a, [Missing]) field: a null is Err(Missing), the same as no key.
expect {
	r : Try({ a : Try(Str, [Missing]), b : U8 }, _)
	r = Cbor.parse([0xa2, 0x61, 0x61, 0xf6, 0x61, 0x62, 0x01])
	r == Ok({ a: Err(Missing), b: 1 })
}

## undefined (f7) is the same as null.
expect {
	r : Try({ a : Try(Str, [Missing]), b : U8 }, _)
	r = Cbor.parse([0xa2, 0x61, 0x61, 0xf7, 0x61, 0x62, 0x01])
	r == Ok({ a: Err(Missing), b: 1 })
}

## Each field of a row is null: the record has only absent fields.
expect {
	r : Try({ a : Try(U64, [Missing]), b : Try(Bool, [Missing]) }, _)
	r = Cbor.parse([0xa2, 0x61, 0x61, 0xf6, 0x61, 0x62, 0xf6])
	r == Ok({ a: Err(Missing), b: Err(Missing) })
}

## A required field with a null is MissingRequiredField, with the name of the field.
expect {
	r : Try({ a : Str, b : U8 }, _)
	r = Cbor.parse([0xa2, 0x61, 0x61, 0xf6, 0x61, 0x62, 0x01])
	r == Err(MissingRequiredField("a"))
}

## A Try(a, [Null]) field is required: a null is MissingRequiredField too. Use an optional field.
expect {
	r : Try({ a : Try(Str, [Null]), b : U8 }, _)
	r = Cbor.parse([0xa2, 0x61, 0x62, 0x01, 0x61, 0x61, 0xf6])
	r == Err(MissingRequiredField("a"))
}

expect {
	r : Try({ a : Try(Str, [Null]) }, _)
	r = Cbor.parse([0xa1, 0x61, 0x61, 0x61, 0x78])
	r == Ok({ a: Ok("x") })
}

## A null of an unknown key is skipped, as any unknown key is.
expect {
	r : Try({ b : U8 }, _)
	r = Cbor.parse([0xa2, 0x61, 0x7a, 0xf6, 0x61, 0x62, 0x01])
	r == Ok({ b: 1 })
}

## A nested record: a null of an optional record field is absent, and a null in the inner map too.
expect {
	r : Try({ outer : { x : Try(U8, [Missing]) }, gone : Try({ y : U8 }, [Missing]) }, _)
	r = Cbor.parse([0xa2, 0x65, 0x6f, 0x75, 0x74, 0x65, 0x72, 0xa1, 0x61, 0x78, 0xf6, 0x64, 0x67, 0x6f, 0x6e, 0x65, 0xf6])
	r == Ok({ outer: { x: Err(Missing) }, gone: Err(Missing) })
}

## A camelCase key with a null: the same rule.
expect {
	r : Try({ user_id : Try(U64, [Missing]) }, _)
	r = Cbor.parse_camel([0xa1, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0xf6])
	r == Ok({ user_id: Err(Missing) })
}

## A key at the end of the input, with no value, is an error at the end.
expect {
	r : Try({ a : Try(U8, [Missing]) }, _)
	r = Cbor.parse([0xa1, 0x61, 0x61])
	r == Err(InvalidCbor(3))
}

## A map count that is larger than the entries: the error is at the end, also after a null entry.
expect {
	r : Try({ a : Try(U8, [Missing]) }, _)
	r = Cbor.parse([0xa2, 0x61, 0x61, 0xf6, 0x00])
	r.is_err()
}

## The position of an error after a null entry is the position in the input (the value of "b").
expect {
	bytes = [0xa2, 0x61, 0x61, 0xf6, 0x61, 0x62, 0x61, 0x78]
	r : Try({ a ?: Str, b : U8 }, _)
	r = Cbor.parse(bytes)
	r == Err(InvalidCbor(6)) and Cbor.path_at(bytes, 6) == Ok([Key("b")])
}

# A null outside a map: only Try(a, [Null]) reads it

## A list item: Try(a, [Null]) reads null as Err(Null).
expect {
	r : Try(List(Try(U64, [Null])), _)
	r = Cbor.parse([0x82, 0xf6, 0x05])
	r == Ok([Err(Null), Ok(5)])
}

## A list item of another type: a null is an error at the item.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse([0x82, 0x05, 0xf6])
	r == Err(InvalidCbor(2))
}

## A tuple item (a row read as a tuple).
expect {
	r : Try(List((Str, Try(I64, [Null]))), _)
	r = Cbor.parse([0x81, 0x82, 0x61, 0x78, 0xf6])
	r == Ok([("x", Err(Null))])
}

expect {
	r : Try((Str, I64), _)
	r = Cbor.parse([0x82, 0x61, 0x78, 0xf6])
	r == Err(InvalidCbor(3))
}

## A Dict keeps each entry: a null value needs Try(v, [Null]).
expect {
	r : Try(Dict(Str, Try(U64, [Null])), _)
	r = Cbor.parse([0xa1, 0x61, 0x61, 0xf6])
	r == Ok(Dict.from_list([("a", Err(Null))]))
}

expect {
	r : Try(Dict(Str, U64), _)
	r = Cbor.parse([0xa1, 0x61, 0x61, 0xf6])
	r == Err(InvalidCbor(3))
}

# The writer: a null value in a map is not written

## Err(Null) in a record field: the key is not written, and the head has the real count.
expect {
	v : { a : Try(Str, [Null]), b : U8 }
	v = { a: Err(Null), b: 1 }
	Cbor.encode(v) == [0xa1, 0x61, 0x62, 0x01]
}

expect {
	v : { a : Try(Str, [Null]) }
	v = { a: Err(Null) }
	Cbor.encode(v) == [0xa0]
}

## Ok(x) is written as x.
expect {
	v : { a : Try(Str, [Null]) }
	v = { a: Ok("x") }
	Cbor.encode(v) == [0xa1, 0x61, 0x61, 0x61, 0x78]
}

## A value with the last byte f6 is not a null: 246 is 18 f6.
expect Cbor.encode({ a: 246.U8, b: 1.U8 }) == [0xa2, 0x61, 0x61, 0x18, 0xf6, 0x61, 0x62, 0x01]

## The tag Null is text, not a null: it is written.
expect {
	v : { a : [Null, Some(U8)] }
	v = { a: Null }
	Cbor.encode(v) == [0xa1, 0x61, 0x61, 0x64, 0x4e, 0x75, 0x6c, 0x6c]
}

## Err(Missing) and an absent optional field are not written (as before).
expect {
	v : { a : Try(Str, [Missing]), b ?: U8, c : U8 }
	v = { a: Err(Missing), c: 2 }
	Cbor.encode(v) == [0xa1, 0x61, 0x63, 0x02]
}

## A null outside a map is written: a list item, a tuple item, the root.
expect {
	v : List(Try(U64, [Null]))
	v = [Err(Null), Ok(5)]
	Cbor.encode(v) == [0x82, 0xf6, 0x05]
}

expect {
	v : (Str, Try(I64, [Null]))
	v = ("x", Err(Null))
	Cbor.encode(v) == [0x82, 0x61, 0x78, 0xf6]
}

expect {
	v : Try(U64, [Null])
	v = Err(Null)
	Cbor.encode(v) == [0xf6]
}

## Round trip: a record with Err(Null) reads back into an optional field and into Try(a, [Missing]).
expect {
	v : List({ id : U64, note : Try(Str, [Null]) })
	v = [{ id: 1, note: Err(Null) }, { id: 2, note: Ok("n") }]
	bytes = Cbor.encode(v)
	r : Try(List({ id : U64, note : Try(Str, [Missing]) }), _)
	r = Cbor.parse(bytes)
	r == Ok([{ id: 1, note: Err(Missing) }, { id: 2, note: Ok("n") }])
}

expect {
	v : { id : U64, note : Try(Str, [Null]) }
	v = { id: 1, note: Err(Null) }
	r : Try({ id : U64, note ?: Str }, _)
	r = Cbor.parse(Cbor.encode(v))
	match r {
		Ok(p) => p.id == 1 and p.?note.is_err()
		Err(_) => Bool.False
	}
}

## Round trip of a list of Try(a, [Null]) items and of Bool.
expect {
	v : { flags : List(Bool), cells : List(Try(I64, [Null])) }
	v = { flags: [Bool.True, Bool.False], cells: [Ok(-3), Err(Null)] }
	r : Try({ flags : List(Bool), cells : List(Try(I64, [Null])) }, _)
	r = Cbor.parse(Cbor.encode(v))
	r == Ok(v)
}
