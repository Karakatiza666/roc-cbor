app [] { pkg: "../src/main.roc" }

# One truncation rule for each reader (0.5.0), through the public API of the package. When the bytes end in an
# item, the error is at the head of the innermost item that is not whole: a cut head, a cut string, an open string
# of indefinite length, or else the innermost open array, map or tag. A count of an array or a map is not checked
# against the bytes left, so a stream and `parse_with` give the same error for the same bytes.

import pkg.Cbor

indefinite : Cbor.Options
indefinite = { allow: [IndefiniteLength] }

## The error position of a parse of `bytes` as a `Cbor.Value`, or `Ok`.
value_at : List(U8), Cbor.Options -> Try({}, [At(U64)])
value_at = |bytes, options| {
	r : Try(Cbor.Value, _)
	r = Cbor.parse_with(bytes, options)
	match r {
		Ok(_) => Ok({})
		Err(InvalidCbor(p)) => Err(At(p))
		Err(MissingRequiredField(_)) => Err(At(U64.highest))
	}
}

## The error position of a parse as a `Cbor.Value` for each prefix of `bytes` that is not the whole item.
positions : List(U8), Cbor.Options -> List(U64)
positions = |bytes, options| {
	var $out = []
	var $n = 0
	while $n < bytes.len() {
		p =
			match value_at(bytes.take_first($n), options) {
				Ok(_) => U64.highest
				Err(At(q)) => q
			}
		$out = $out.append(p)
		$n = $n + 1
	}
	$out
}

## `path_at` gives `NotFound` for each prefix of `bytes` that is not the whole item.
no_paths : List(U8) -> Bool
no_paths = |bytes| {
	var $all = Bool.True
	for n in 0..<bytes.len() {
		if Cbor.path_at(bytes.take_first(n), 0) != Err(NotFound) {
			$all = Bool.False
		}
	}
	$all
}

# The table of the design (section 4.8)

## An array of 2 with only 1 item (82 01) is an error at byte 0, the open array.
expect value_at([0x82, 0x01], {}) == Err(At(0))

## An inner array of 2 with only 1 item (82 82 01) is an error at byte 1, the inner array.
expect value_at([0x82, 0x82, 0x01], {}) == Err(At(1))

## Text of 2 bytes with only 1 byte (62 61) is an error at byte 0.
expect value_at([0x62, 0x61], {}) == Err(At(0))

## A cut text in an array (84 00 61) is an error at byte 2, the text.
expect value_at([0x84, 0x00, 0x61], {}) == Err(At(2))

## A map with a key and no value (a2 61 61) is an error at byte 0, the map.
expect value_at([0xa2, 0x61, 0x61], {}) == Err(At(0))

## A cut text in an inner array (82 83 01 62 61) is an error at byte 3, the text.
expect value_at([0x82, 0x83, 0x01, 0x62, 0x61], {}) == Err(At(3))

## A typed reader walks the item first, so it gives the same positions.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse([0x84, 0x00, 0x61])
	r == Err(InvalidCbor(2))
}

## A List(List(U64)) from 82 82 01 is an error at byte 1, the inner array.
expect {
	r : Try(List(List(U64)), _)
	r = Cbor.parse([0x82, 0x82, 0x01])
	r == Err(InvalidCbor(1))
}

## Inputs whose position changed in 0.5.0: before, a missing item at the end was an error at the end, a count that
## did not fit was an error at the outer head, and a cut string of indefinite length was an error at a chunk.
expect value_at([0x83, 0x01, 0x82, 0x01, 0x02], {}) == Err(At(0))

## A tag with no item (c1) is an error at byte 0.
expect value_at([0xc1], {}) == Err(At(0))

## A tag with no item in an array (81 c1) is an error at byte 1, the tag.
expect value_at([0x81, 0xc1], {}) == Err(At(1))

## An open array of indefinite length (9f 01) is an error at byte 0.
expect value_at([0x9f, 0x01], indefinite) == Err(At(0))

## A byte string of indefinite length with no break (5f) is an error at byte 0.
expect value_at([0x5f], indefinite) == Err(At(0))

## A cut chunk head in a byte string of indefinite length (5f 5a 00) is an error at byte 0, the string.
expect value_at([0x5f, 0x5a, 0x00], indefinite) == Err(At(0))

## Open text of indefinite length in an array (82 7f 61 61) is an error at byte 1, the text.
expect value_at([0x82, 0x7f, 0x61, 0x61], indefinite) == Err(At(1))

## Not a truncation: an error in the bytes that are there comes first, at its own position.
expect value_at([0x83, 0x01, 0x1c], {}) == Err(At(2))

## A 1-byte head for 1 (18 01) in a cut array (83 01 18 01) is an error at byte 2, the head.
expect value_at([0x83, 0x01, 0x18, 0x01], {}) == Err(At(2))

## Text that is not UTF-8 (62 ff ff) in a cut array is an error at byte 1, the text.
expect value_at([0x83, 0x62, 0xff, 0xff], {}) == Err(At(1))

## A text chunk in a byte string of indefinite length (5f 61 61) is an error at byte 0.
expect value_at([0x5f, 0x61, 0x61], indefinite) == Err(At(0))

# Truncation at each position

## [[1, 2], 3]
expect positions([0x82, 0x82, 0x01, 0x02, 0x03], {}) == [0, 0, 1, 1, 0]

## path_at gives NotFound for each cut of [[1, 2], 3].
expect no_paths([0x82, 0x82, 0x01, 0x02, 0x03])

## {"a": 256, "bc": [true]}: a cut text, a cut 3-byte head, a key with no value.
rec_bytes : List(U8)
rec_bytes = [0xa2, 0x61, 0x61, 0x19, 0x01, 0x00, 0x62, 0x62, 0x63, 0x81, 0xf5]

## Each cut of the map read as a Cbor.Value gives the error positions 0, 0, 1, 0, 3, 3, 0, 6, 6, 0, 9.
expect positions(rec_bytes, {}) == [0, 0, 1, 0, 3, 3, 0, 6, 6, 0, 9]

## path_at gives NotFound for each cut of the map.
expect no_paths(rec_bytes)

## The whole map reads as { a: 256, bc: [true] }, and each cut read as the record gives the same positions.
expect {
	ok : Try({ a : U64, bc : List(Bool) }, _)
	ok = Cbor.parse(rec_bytes)
	var $typed = []
	for n in 0..<rec_bytes.len() {
		r : Try({ a : U64, bc : List(Bool) }, _)
		r = Cbor.parse(rec_bytes.take_first(n))
		p =
			match r {
				Ok(_) => U64.highest
				Err(InvalidCbor(q)) => q
				Err(MissingRequiredField(_)) => U64.highest - 1
			}
		$typed = $typed.append(p)
	}
	ok == Ok({ a: 256, bc: [Bool.True] }) and $typed == [0, 0, 1, 0, 3, 3, 0, 6, 6, 0, 9]
}

## 1([_ (_ h'01', h'02'), "€"]): a tag, an indefinite array, an indefinite byte string, text of 3 UTF-8 bytes.
## A chunk is not an item: a cut chunk is an error at the head of its string.
tagged : List(U8)
tagged = [0xc1, 0x9f, 0x5f, 0x41, 0x01, 0x41, 0x02, 0xff, 0x63, 0xe2, 0x82, 0xac, 0xff]

## The whole tagged item reads as a Cbor.Value with IndefiniteLength.
expect value_at(tagged, indefinite) == Ok({})

## Each cut of the tagged item gives the error positions 0, 0, 1, 2, 2, 2, 2, 2, 1, 8, 8, 8, 1.
expect positions(tagged, indefinite) == [0, 0, 1, 2, 2, 2, 2, 2, 1, 8, 8, 8, 1]

## path_at gives NotFound for each cut of the tagged item.
expect no_paths(tagged)

# A count far larger than the input

## A head that declares 2^60 items, then 1 byte. The walk reads only the bytes that are there and stops at their
## end, so the typed reader never makes a list for the count.
expect {
	r : Try(List(U64), _)
	r = Cbor.parse([0x9b, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## A Dict from a map head of 2^60 entries (bb ..) then 1 byte is an error at byte 0.
expect {
	r : Try(Dict(U64, U64), _)
	r = Cbor.parse([0xbb, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## A List(U8) from a byte string head of 2^60 bytes (5b ..) then 1 byte is an error at byte 0.
expect {
	r : Try(List(U8), _)
	r = Cbor.parse([0x5b, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## A Cbor.Bytes from a byte string head of 2^60 bytes (5b ..) then 1 byte is an error at byte 0.
expect {
	r : Try(Cbor.Bytes, _)
	r = Cbor.parse([0x5b, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(0))
}

## A Cbor.Value from an array head of 2^60 items then 1 byte is an error at byte 0.
expect value_at([0x9b, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], {}) == Err(At(0))

## The largest counts: 2^64 - 1 items, and a map of 2^64 - 1 entries (2^65 - 2 items).
expect value_at([0x9b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00], {}) == Err(At(0))

## A map head of 2^64 - 1 entries (bb ff ff ff ff ff ff ff ff) then 1 byte is an error at byte 0.
expect value_at([0xbb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00], {}) == Err(At(0))

## A map head of 2^63 entries (bb 80 00 00 00 00 00 00 00) then 1 byte is an error at byte 0.
expect value_at([0xbb, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], {}) == Err(At(0))

## In an unknown field of a record: the skip of the field stops at the end of the bytes too.
expect {
	r : Try({ a : U64 }, _)
	r = Cbor.parse([0xa2, 0x61, 0x61, 0x01, 0x61, 0x78, 0x9b, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
	r == Err(InvalidCbor(6))
}
