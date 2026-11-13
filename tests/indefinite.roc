app [] { pkg: "../src/main.roc" }

# Indefinite lengths (0.5.0, G7 of the audit of 0.4.1), through the public API of the package: the leniency
# IndefiniteLength (RFC 8949 3.2). Arrays, maps, byte strings and text of indefinite length, each with its break,
# in each typed reader. Strict, each one is an error.

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

indefinite : Cbor.Options
indefinite = { allow: [IndefiniteLength] }

# Strict: an error at the head, also in a skipped item

## Strict, an array of indefinite length (9f 01 02 ff) as a List(U64) is an error at byte 0.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse(hex("9f0102ff"))
	r == Err(InvalidCbor(0))
}

## Strict, an unknown record field with an empty array of indefinite length (9f ff) is an error at byte 6.
expect {
	r : Try({ a : U64 }, _)
	r = Cbor.parse(hex("a261610161789fff"))
	r == Err(InvalidCbor(6))
}

# Arrays

## With IndefiniteLength, 9f 01 02 ff reads as the List(U64) [1, 2].
expect {
	r : Try(List(U64), _)
	r = Cbor.parse_with(hex("9f0102ff"), indefinite)
	r == Ok([1, 2])
}

## Nested, empty, and an array of definite length in one of indefinite length.
expect {
	r : Try(List(List(U64)), _)
	r = Cbor.parse_with(hex("9f9fff8201029f03ffff"), indefinite)
	r == Ok([[], [1, 2], [3]])
}

## A tuple: the break after the last item. More items, or no break, is an error.
expect {
	r : Try((U64, Str), _)
	r = Cbor.parse_with(hex("9f016161ff"), indefinite)
	r == Ok((1, "a"))
}

## A tuple (U64, Str) with a third item before the break (9f 01 61 61 02 ff) is an error at byte 4.
expect {
	r : Try((U64, Str), _)
	r = Cbor.parse_with(hex("9f01616102ff"), indefinite)
	r == Err(InvalidCbor(4))
}

## A list of an indefinite and a definite tuple (9f 9f 01 02 ff 82 03 04 ff) reads as [(1, 2), (3, 4)].
expect {
	r : Try(List((U64, U64)), _)
	r = Cbor.parse_with(hex("9f9f0102ff820304ff"), indefinite)
	r == Ok([(1, 2), (3, 4)])
}

## A List(U8) reads an array of integers 0 to 255 of indefinite length only with BytesFromArray, as a definite one.
expect {
	bytes = hex("9f0102ff")
	a : Try(List(U8), _)
	a = Cbor.parse_with(bytes, indefinite)
	b : Try(List(U8), _)
	b = Cbor.parse_with(bytes, { allow: [IndefiniteLength, BytesFromArray] })
	c : Try(Cbor.U8Array, _)
	c = Cbor.parse_with(bytes, indefinite)
	a == Err(InvalidCbor(0)) and b == Ok([1, 2]) and c.map_ok(|x| x.to_list()) == Ok([1, 2])
}

# Byte strings and text: the chunks are joined

## A byte string with the chunks 01 02, empty and 03 (5f 42 01 02 40 41 03 ff) reads as the List(U8) [1, 2, 3].
expect {
	r : Try(List(U8), _)
	r = Cbor.parse_with(hex("5f420102404103ff"), indefinite)
	r == Ok([1, 2, 3])
}

## Byte strings in a list: empty and 01 of indefinite length, and a definite 02, read as [[], [1], [2]].
expect {
	r : Try(List(List(U8)), _)
	r = Cbor.parse_with(hex("9f5fff5f4101ff4102ff"), indefinite)
	r == Ok([[], [1], [2]])
}

## A byte string of indefinite length (5f 42 01 02 41 03 ff) reads as the Cbor.Bytes 01 02 03.
expect {
	r : Try(Cbor.Bytes, _)
	r = Cbor.parse_with(hex("5f4201024103ff"), indefinite)
	r.map_ok(|b| b.to_list()) == Ok([1, 2, 3])
}

## Text with the chunks "ab", "c" and "" (7f 62 61 62 61 63 60 ff) reads as "abc".
expect {
	r : Try(Str, _)
	r = Cbor.parse_with(hex("7f626162616360ff"), indefinite)
	r == Ok("abc")
}

## A chunk of another major type, a chunk of indefinite length, and text with a code point split in two chunks are errors.
expect {
	r : Try(Str, _)
	r = Cbor.parse_with(hex("7f4161ff"), indefinite)
	r == Err(InvalidCbor(0))
}

## Text with a chunk of indefinite length in it (7f 7f ff ff) is an error at byte 0.
expect {
	r : Try(Str, _)
	r = Cbor.parse_with(hex("7f7fffff"), indefinite)
	r == Err(InvalidCbor(0))
}

## Text with the code point c3 bc split in two chunks (7f 61 c3 61 bc ff) is an error at byte 0.
expect {
	r : Try(Str, _)
	r = Cbor.parse_with(hex("7f61c361bcff"), indefinite)
	r == Err(InvalidCbor(0))
}

# Maps

## A record, with an unknown field of indefinite length.
expect {
	r : Try({ a : U64, b : Str }, _)
	r = Cbor.parse_with(hex("bf616101617a9f01ff61627f6178ffff"), indefinite)
	r == Ok({ a: 1, b: "x" })
}

## A key with no value, and a break at the root, are errors.
expect {
	r : Try({ a : U64 }, _)
	r = Cbor.parse_with(hex("bf6161016162ff"), indefinite)
	r == Err(InvalidCbor(6))
}

## The walk checks it, also where no typed reader goes (`path_at`).
expect Cbor.path_at(hex("bf6161016162ff"), 0) == Err(NotFound)

## A break at the root (ff) is an error at byte 0.
expect {
	r : Try(U64, _)
	r = Cbor.parse_with(hex("ff"), indefinite)
	r == Err(InvalidCbor(0))
}

## A break in an array of definite length (82 01 ff) is an error at byte 2.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse_with(hex("8201ff"), indefinite)
	r == Err(InvalidCbor(2))
}

## A Dict, with a key that is not text.
expect {
	r : Try(Dict(U64, Str), _)
	r = Cbor.parse_with(hex("bf016161026162ff"), indefinite)
	r == Ok(Dict.from_list([(1, "a"), (2, "b")]))
}

## duplicate_keys: a text key of indefinite length is the same key as the definite one.
expect {
	bytes = hex("bf6161017f6161ff02ff")
	a : Try(Dict(Str, U64), _)
	a = Cbor.parse_with(bytes, indefinite)
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with(bytes, { allow: [IndefiniteLength], duplicate_keys: First })
	c : Try(Dict(Str, U64), _)
	c = Cbor.parse_with(bytes, { allow: [IndefiniteLength], duplicate_keys: Last })
	a == Err(InvalidCbor(4)) and b == Ok(Dict.from_list([("a", 1)])) and c == Ok(Dict.from_list([("a", 2)]))
}

## An array key of indefinite length is the same key as the definite one. Else the Dict keeps one entry with no error.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with(hex("a2820102019f0102ff02"), indefinite)
	r == Err(InvalidCbor(5))
}

## A record key of indefinite length.
expect {
	r : Try({ ab : U64 }, _)
	r = Cbor.parse_with(hex("a17f61616162ff01"), indefinite)
	r == Ok({ ab: 1 })
}

# Tag unions

## A tag union in a map of indefinite length, with a payload array of indefinite length, reads as Wire("eu", 9).
expect {
	r : Try([Wire(Str, U64), Cash], _)
	r = Cbor.parse_with(hex("bf64576972659f62657509ffff"), indefinite)
	r == Ok(Wire("eu", 9))
}

## A tag union in a map of indefinite length (bf 65 "Check" 07 ff) reads as Check(7).
expect {
	r : Try([Check(U64)], _)
	r = Cbor.parse_with(hex("bf65436865636b07ff"), indefinite)
	r == Ok(Check(7))
}

## The payload array of an internal tag ends at its break.
expect {
	opts : Cbor.Options
	opts = { allow: [IndefiniteLength], unions: Internal({ tag: "kind", content: "value" }) }
	a : Try([Wire(Str, U64)], _)
	a = Cbor.parse_with(hex("bf646b696e6464576972656576616c75659f62657509ffff"), opts)
	b : Try([Wire(Str, U64)], _)
	b = Cbor.parse_with(hex("bf646b696e6464576972656576616c75659f6265750907ffff"), opts)
	a == Ok(Wire("eu", 9)) and b == Err(InvalidCbor(22))
}

# Limits and other readers

## max_depth and max_items count the items of indefinite length. A break is not an item.
expect {
	a : Try(List(List(U64)), _)
	a = Cbor.parse_with(hex("9f9fffff"), { allow: [IndefiniteLength], max_depth: 1 })
	b : Try(List(U64), _)
	b = Cbor.parse_with(hex("9f0102ff"), { allow: [IndefiniteLength], max_items: 3 })
	c : Try(List(U64), _)
	c = Cbor.parse_with(hex("9f0102ff"), { allow: [IndefiniteLength], max_items: 2 })
	a == Err(InvalidCbor(1)) and b == Ok([1, 2]) and c == Err(InvalidCbor(2))
}

## path_at walks items of indefinite length.
expect Cbor.path_at(hex("bf61619f0102ffff"), 5) == Ok([Key("a"), Index(1)])

## Cbor.Value: an item of indefinite length is the same value as its definite form, so it writes the definite form.
## Strict, an error at the head.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with(hex("bf61619f015f41014102ff7f61626163ffffa09fffff"), indefinite)
	r.map_ok(|v| Cbor.encode(v)) == Ok(hex("a261618301420102626263a080"))
}

## Strict, an empty array of indefinite length (9f ff) as a Cbor.Value is an error at byte 0.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(hex("9fff"))
	r == Err(InvalidCbor(0))
}

## Nested, and a tag around an item of indefinite length.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with(hex("9f9f9fffffc69f01ffff"), indefinite)
	r.map_ok(|v| Cbor.encode(v)) == Ok(hex("828180c68101"))
}
