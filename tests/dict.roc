app [] { pkg: "../src/main.roc" }

# A Dict and wide integers (0.5.0, G5 of the audit of 0.4.1), through the public API of the package:
# encode_dict with the item check of each key and value, Dict keys that are not text on read with the
# duplicate-key rule, a key read only in the form that the writer writes, and U128 and I128 with bignums.

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

## A map written by hand with encode_dict: `declared` entries, `written` calls of `add`, and the count of
## items that each key and each value writes.
Entries := { declared : U64, written : U64, key_items : U64, value_items : U64 }.{
	encoder_for : Cbor -> (Entries, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Entries.({ declared, written, key_items, value_items }), w|
		Cbor.encode_dict(
			w,
			declared,
			|c, add| {
				var $c = c
				for i in (0.U64).until(written) {
					$c = add($c, |k| ones(k, key_items, i), |v| ones(v, value_items, 7))?
				}
				Ok($c)
			},
		)
}

## `n` items, each one `value`.
ones : Cbor.Writer, U64, U64 -> Try(Cbor.Writer, err)
ones = |w, n, value| {
	var $w = w
	for _ in (0.U64).until(n) {
		$w = Cbor.encode_u64(value, $w)?
	}
	Ok($w)
}

# encode_dict: a Dict writes a map

## The keys of each type write as that type: text, an integer, a negative integer, a Bool, a bignum. The order of the Dict.
expect Cbor.encode(Dict.from_list([("a", 1.U64), ("b", 2)])) == hex("a2616101616202")

## Integer keys: {1: "a", 24: "b"} writes a2 01 6161 1818 6162.
expect Cbor.encode(Dict.from_list([(1.U64, "a"), (24, "b")])) == hex("a201616118186162")

## Negative integer keys: {-1: true, -25: false} writes a2 20 f5 3818 f4.
expect Cbor.encode(Dict.from_list([(-1.I64, Bool.True), (-25, Bool.False)])) == hex("a220f53818f4")

## Bool keys: {false: 0, true: 1} writes a2 f4 00 f5 01.
expect Cbor.encode(Dict.from_list([(Bool.False, 0.U8), (Bool.True, 1)])) == hex("a2f400f501")

## A U128 key of 2^64 writes as the bignum c2 49 01 00 00 00 00 00 00 00 00.
expect Cbor.encode(Dict.from_list([(18446744073709551616.U128, 0.U8)])) == hex("a1c24901000000000000000000")

## A List(U8) value writes as a byte string: {1: [1, 2]} writes a1 01 42 01 02.
expect Cbor.encode(Dict.empty() |> Dict.insert(1.U8, [1.U8, 2])) == hex("a101420102")

## An empty Dict is an empty map.
expect {
	d : Dict(U64, Str)
	d = Dict.empty()
	Cbor.encode(d) == [0xa0]
}

## A key of a tag union with no payloads is its name.
expect {
	d : Dict([Alpha, Beta], U64)
	d = Dict.from_list([(Alpha, 1), (Beta, 2)])
	r : Try(Dict([Alpha, Beta], U64), _)
	r = Cbor.parse(Cbor.encode(d))
	Cbor.encode(d) == hex("a265416c70686101644265746102") and r == Ok(d)
}

## A Dict in a record and in a Dict.
expect Cbor.encode({ m: Dict.from_list([(1.U64, Dict.from_list([("x", 2.U64)]))]) }) == hex("a1616da101a1617802")

## Each entry is exactly one key and one value, and the count of entries is the declared count.
expect Cbor.encode_try(Entries.({ declared: 2, written: 2, key_items: 1, value_items: 1 })) == Ok(hex("a200070107"))

## A key that writes no item is a CountMismatch.
expect Cbor.encode_try(Entries.({ declared: 1, written: 1, key_items: 0, value_items: 1 })) == Err(CountMismatch)

## A key that writes two items is a CountMismatch.
expect Cbor.encode_try(Entries.({ declared: 1, written: 1, key_items: 2, value_items: 1 })) == Err(CountMismatch)

## A value that writes no item is a CountMismatch.
expect Cbor.encode_try(Entries.({ declared: 1, written: 1, key_items: 1, value_items: 0 })) == Err(CountMismatch)

## A value that writes two items is a CountMismatch.
expect Cbor.encode_try(Entries.({ declared: 1, written: 1, key_items: 1, value_items: 2 })) == Err(CountMismatch)

## One entry written for a declared count of 2 is a CountMismatch.
expect Cbor.encode_try(Entries.({ declared: 2, written: 1, key_items: 1, value_items: 1 })) == Err(CountMismatch)

## Two entries written for a declared count of 1 is a CountMismatch.
expect Cbor.encode_try(Entries.({ declared: 1, written: 2, key_items: 1, value_items: 1 })) == Err(CountMismatch)

# Dict keys that are not text, on read

## Each key type reads back.
expect {
	d = Dict.from_list([(1.U64, "a"), (1000, "b"), (0, "c")])
	r : Try(Dict(U64, Str), _)
	r = Cbor.parse(Cbor.encode(d))
	r == Ok(d)
}

## A Dict(I32, U8) with the negative keys -1 and -1000 reads back.
expect {
	d = Dict.from_list([(-1.I32, 1.U8), (7, 2), (-1000, 3)])
	r : Try(Dict(I32, U8), _)
	r = Cbor.parse(Cbor.encode(d))
	r == Ok(d)
}

## A Dict(Bool, Str) with the keys true and false reads back.
expect {
	d = Dict.from_list([(Bool.True, "t"), (Bool.False, "f")])
	r : Try(Dict(Bool, Str), _)
	r = Cbor.parse(Cbor.encode(d))
	r == Ok(d)
}

## A Dict(U128, U8) with the key U128.highest (a bignum) reads back.
expect {
	d = Dict.from_list([(340282366920938463463374607431768211455.U128, 1.U8), (5, 2)])
	r : Try(Dict(U128, U8), _)
	r = Cbor.parse(Cbor.encode(d))
	r == Ok(d)
}

## A Dict(I128, U8) with the key I128.lowest (a negative bignum) reads back.
expect {
	d = Dict.from_list([(-170141183460469231731687303715884105728.I128, 1.U8), (-5, 2)])
	r : Try(Dict(I128, U8), _)
	r = Cbor.parse(Cbor.encode(d))
	r == Ok(d)
}

## A Dict(Dec, Str) with the keys 1.5, 2 and -0.25 reads back.
expect {
	d = Dict.from_list([(1.5.Dec, "a"), (2, "b"), (-0.25, "c")])
	r : Try(Dict(Dec, Str), _)
	r = Cbor.parse(Cbor.encode(d))
	r == Ok(d)
}

## A key of a composite type (a Cbor.Value, a record, a tuple) is a compile error in both directions: the format
## has no parse_key_start and no encode_key_start. A tag union with no payloads reads its name only.
expect {
	r : Try(Dict([Alpha, Beta], U64), _)
	r = Cbor.parse(hex("a265416c706861016547616d6d6102"))
	# The derived parser gives the error after the key, at its value.
	r == Err(InvalidCbor(14))
}

## A Dict(U8, Dict(I8, Str)), a Dict in a Dict, reads back.
expect {
	d = Dict.from_list([(7.U8, Dict.from_list([(-1.I8, "x")]))])
	r : Try(Dict(U8, Dict(I8, Str)), _)
	r = Cbor.parse(Cbor.encode(d))
	r == Ok(d)
}

## A key of the wrong type is an error at the key.
expect {
	r : Try(Dict(U64, Str), _)
	r = Cbor.parse(hex("a201616161626162"))
	r == Err(InvalidCbor(4))
}

## duplicate_keys applies to each key type: Reject (an error at the second key), First, Last.
expect {
	bytes = hex("a3016161026162016163")
	a : Try(Dict(U64, Str), _)
	a = Cbor.parse(bytes)
	b : Try(Dict(U64, Str), _)
	b = Cbor.parse_with(bytes, { duplicate_keys: First })
	c : Try(Dict(U64, Str), _)
	c = Cbor.parse_with(bytes, { duplicate_keys: Last })
	a == Err(InvalidCbor(7)) and b == Ok(Dict.from_list([(1, "a"), (2, "b")])) and c == Ok(Dict.from_list([(1, "c"), (2, "b")]))
}

## The same key with a longer head is a duplicate, also with PaddedNumbers.
expect {
	r : Try(Dict(U64, Str), _)
	r = Cbor.parse_with(hex("a201616118016162"), { allow: [PaddedNumbers] })
	r == Err(InvalidCbor(4))
}

## PaddedNumbers, a small map: only the last key has a longer head, and it is the same as "a". All shortest: no duplicate.
expect {
	a : Try(Dict(Str, U64), _)
	a = Cbor.parse_with(hex("a36161016162027801616103"), { allow: [PaddedNumbers] })
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with(hex("a3616101616202616303"), { allow: [PaddedNumbers] })
	a == Err(InvalidCbor(7)) and b.map_ok(|d| d.len()) == Ok(3)
}

## The 40 keys "k10" to "k49" (shortest heads, value 0), then `last` with value 0, in a map of 41 entries (more than 32).
big_map : List(U8) -> List(U8)
big_map = |last| {
	keys = (10.U8).until(50).fold([0xb8, 41], |acc, i| acc.concat([0x63, 0x6b, 0x30 + i // 10, 0x30 + i % 10, 0x00]))
	keys.concat(last).append(0x00)
}

## PaddedNumbers, a large map: only the last key has a longer head. The same as "k10": a duplicate at the last key (2 + 40 * 5).
## A new key "k50": no duplicate, with a longer head or with the shortest head.
expect {
	a : Try(Dict(Str, U64), _)
	a = Cbor.parse_with(big_map([0x78, 0x03, 0x6b, 0x31, 0x30]), { allow: [PaddedNumbers] })
	b : Try(Dict(Str, U64), _)
	b = Cbor.parse_with(big_map([0x78, 0x03, 0x6b, 0x35, 0x30]), { allow: [PaddedNumbers] })
	c : Try(Dict(Str, U64), _)
	c = Cbor.parse_with(big_map([0x63, 0x6b, 0x35, 0x30]), { allow: [PaddedNumbers] })
	a == Err(InvalidCbor(202)) and b.map_ok(|d| d.len()) == Ok(41) and c.map_ok(|d| d.len()) == Ok(41)
}

## A key reads only in the form that the writer writes. Else two different keys of the map give one Roc key, and
## the Dict loses an entry with no error: 1 and the decimal fraction 10 * 10^-1, 0 and false with BoolFromInt,
## 1 and the float 1.0 with FloatToInt, 1 and the text "1" with IntFromText, 2^64 and its bignum with a leading zero.
expect {
	r : Try(Dict(Dec, Str), _)
	r = Cbor.parse(hex("a2016161c482200a6162"))
	r == Err(InvalidCbor(4))
}

## With BoolFromInt, the Bool keys false (f4) and 0 in one map are an error at the second key, byte 4.
expect {
	r : Try(Dict(Bool, Str), _)
	r = Cbor.parse_with(hex("a2f46161006162"), { allow: [BoolFromInt] })
	r == Err(InvalidCbor(4))
}

## With FloatToInt, the U64 keys 1 and 1.0 (f9 3c 00) in one map are an error at the second key, byte 4.
expect {
	r : Try(Dict(U64, Str), _)
	r = Cbor.parse_with(hex("a2016161f93c006162"), { allow: [FloatToInt] })
	r == Err(InvalidCbor(4))
}

## With IntFromText, the U64 keys 1 and "1" (61 31) in one map are an error at the second key, byte 4.
expect {
	r : Try(Dict(U64, Str), _)
	r = Cbor.parse_with(hex("a201616161316162"), { allow: [IntFromText] })
	r == Err(InvalidCbor(4))
}

## With PaddedNumbers, the U128 keys 2^64 and 2^64 as a bignum with a leading zero byte are an error at the second key, byte 14.
expect {
	r : Try(Dict(U128, Str), _)
	r = Cbor.parse_with(hex("a2c2490100000000000000006161c24a000100000000000000006162"), { allow: [PaddedNumbers] })
	r == Err(InvalidCbor(14))
}

## The same leniencies still read a value that is not a key.
expect {
	r : Try(Dict(Str, U64), _)
	r = Cbor.parse_with(hex("a26161f93c0061626131"), { allow: [FloatToInt, IntFromText] })
	r == Ok(Dict.from_list([("a", 1), ("b", 1)]))
}

## A key of a Dict of floats: f16, f32 and f64 of one value are the same key.
expect {
	r : Try(List(Dict(F64, U8)), _)
	r = Cbor.parse(hex("82a1f93e0001a1fb3ff800000000000002"))
	r.is_ok()
}

# U128 and I128

## A value in the range of major types 0 and 1 is an integer, a larger one a bignum with no leading zero byte (RFC 8949 3.4.3).
expect Cbor.encode(18446744073709551615.U128) == hex("1bffffffffffffffff")

## The U128 2^64 writes as the bignum c2 49 01 00 00 00 00 00 00 00 00.
expect Cbor.encode(18446744073709551616.U128) == hex("c249010000000000000000")

## U128.highest writes as a bignum of 16 bytes ff.
expect Cbor.encode(U128.highest) == hex("c250ffffffffffffffffffffffffffffffff")

## The U128 0 writes 00.
expect Cbor.encode(0.U128) == [0x00]

## The I128 -2^64 writes as the integer 3b ffffffffffffffff.
expect Cbor.encode(-18446744073709551616.I128) == hex("3bffffffffffffffff")

## The I128 -2^64 - 1 writes as the negative bignum c3 49 01 00 00 00 00 00 00 00 00.
expect Cbor.encode(-18446744073709551617.I128) == hex("c349010000000000000000")

## I128.lowest writes as the negative bignum c3 50 7f ff .. ff.
expect Cbor.encode(I128.lowest) == hex("c3507fffffffffffffffffffffffffffffff")

## I128.highest writes as the bignum c2 50 7f ff .. ff.
expect Cbor.encode(I128.highest) == hex("c2507fffffffffffffffffffffffffffffff")

## The I128 -1 writes 20.
expect Cbor.encode(-1.I128) == [0x20]

## Each value reads back.
expect {
	xs = [0.U128, 1, 18446744073709551615, 18446744073709551616, U128.highest]
	r : Try(List(U128), _)
	r = Cbor.parse(Cbor.encode(xs))
	r == Ok(xs)
}

## A List(I128) of 0, -1, -2^64, -2^64 - 1, 2^64, I128.lowest and I128.highest reads back.
expect {
	xs = [0.I128, -1, -18446744073709551616, -18446744073709551617, 18446744073709551616, I128.lowest, I128.highest]
	r : Try(List(I128), _)
	r = Cbor.parse(Cbor.encode(xs))
	r == Ok(xs)
}

## Out of range: a negative U128, an I128 above 2^127 - 1 or below -2^127, a bignum of 17 bytes.
expect {
	r : Try(U128, _)
	r = Cbor.parse(hex("20"))
	r == Err(InvalidCbor(0))
}

## A negative bignum (c3 49 01 00 ..) is an error at byte 0 for a U128.
expect {
	r : Try(U128, _)
	r = Cbor.parse(hex("c349010000000000000000"))
	r == Err(InvalidCbor(0))
}

## The bignum 2^127 (c2 50 80 00 ..) is above I128.highest: an error at byte 0.
expect {
	r : Try(I128, _)
	r = Cbor.parse(hex("c25080000000000000000000000000000000"))
	r == Err(InvalidCbor(0))
}

## The negative bignum c3 50 80 00 .. (-2^127 - 1) is below I128.lowest: an error at byte 0.
expect {
	r : Try(I128, _)
	r = Cbor.parse(hex("c35080000000000000000000000000000000"))
	r == Err(InvalidCbor(0))
}

## A bignum of 17 bytes (c2 51 01 00 ..) is an error at byte 0 for a U128.
expect {
	r : Try(U128, _)
	r = Cbor.parse(hex("c2510100000000000000000000000000000000"))
	r == Err(InvalidCbor(0))
}

## Strict, a bignum is the preferred serialization (RFC 8949 4.2.2): no leading zero byte, and a value above 64 bits.
## PaddedNumbers reads both.
expect {
	bytes = hex("c24a00010000000000000000")
	a : Try(U128, _)
	a = Cbor.parse(bytes)
	b : Try(U128, _)
	b = Cbor.parse_with(bytes, { allow: [PaddedNumbers] })
	a == Err(InvalidCbor(0)) and b == Ok(18446744073709551616)
}

## The negative bignum c3 41 01 (-2, in the range of major type 1) is an error at byte 0, and -2 with PaddedNumbers.
expect {
	bytes = hex("c34101")
	a : Try(I128, _)
	a = Cbor.parse(bytes)
	b : Try(I128, _)
	b = Cbor.parse_with(bytes, { allow: [PaddedNumbers] })
	a == Err(InvalidCbor(0)) and b == Ok(-2)
}

## The leniencies of an integer type apply: a float with FloatToInt, text with IntFromText.
expect {
	r : Try(List(I128), _)
	r = Cbor.parse_with(hex("82f9c400622d33"), { allow: [FloatToInt, IntFromText] })
	r == Ok([-4, -3])
}

## Another tag is an error.
expect {
	r : Try(U128, _)
	r = Cbor.parse(hex("c44101"))
	r == Err(InvalidCbor(0))
}
