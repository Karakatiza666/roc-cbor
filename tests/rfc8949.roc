app [] { pkg: "../src/main.roc" }

# RFC 8949 Appendix A test vectors, for the parts that the profile covers.
# A vector outside the profile is an expect that the parse is an error.
# Each vector is the hex text of the RFC.

import pkg.Cbor

# Helpers

hex_digit : U8 -> U8
hex_digit = |c| if c >= 97 c - 87 else c - 48

hex : Str -> List(U8)
hex = |s|
	s.to_utf8().chunks_of(2).map(
		|pair|
			match pair {
				[hi, lo] => hex_digit(hi) * 16 + hex_digit(lo)
				_ => crash "odd hex"
			},
	)

## The bytes of `value` are the hex text `h`.
writes : a, Str -> Bool where [a.Cbor.Encodable([])]
writes = |value, h| Cbor.encode(value) == hex(h)

## The hex text `h` parses to `value`.
reads : a, Str -> Bool where [a.is_eq : a, a -> Bool, a.Cbor.Parseable([InvalidCbor(U64), ..errs])]
reads = |value, h| {
	r : Try(a, _)
	r = Cbor.parse(hex(h))
	match r {
		Ok(v) => v == value
		Err(_) => Bool.False
	}
}

## Both: the shortest form of the RFC.
both : a, Str -> Bool where [a.is_eq : a, a -> Bool, a.Cbor.Parseable([InvalidCbor(U64), ..errs]), a.Cbor.Encodable([])]
both = |value, h| writes(value, h) and reads(value, h)

## The hex text `h` parsed as the type of `witness` is `Err(InvalidCbor(pos))`. Gives `pos`.
error_at : a, Str -> Try(U64, [Parsed, Other]) where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]
error_at = |_, h| {
	r : Try(a, _)
	r = Cbor.parse(hex(h))
	match r {
		Ok(_) => Err(Parsed)
		Err(InvalidCbor(pos)) => Ok(pos)
		Err(_) => Err(Other)
	}
}

## The hex text `h` parses as an F64 with the bits of `value` (so -0.0 differs from 0.0).
reads_f64 : F64, Str -> Bool
reads_f64 = |value, h| {
	r : Try(F64, _)
	r = Cbor.parse(hex(h))
	match r {
		Ok(v) => v.to_bits() == value.to_bits()
		Err(_) => Bool.False
	}
}

## The hex text `h` parses as an F64 that is NaN.
reads_nan : Str -> Bool
reads_nan = |h| {
	r : Try(F64, _)
	r = Cbor.parse(hex(h))
	match r {
		Ok(v) => v.is_nan()
		Err(_) => Bool.False
	}
}

expect hex("1b00ff") == [0x1b, 0x00, 0xff]

# Integers, major types 0 and 1 (all widths of the argument)

expect both(0.U64, "00")
expect both(1.U64, "01")
expect both(10.U64, "0a")
expect both(23.U64, "17")
expect both(24.U64, "1818")
expect both(25.U64, "1819")
expect both(100.U64, "1864")
expect both(1000.U64, "1903e8")
expect both(1000000.U64, "1a000f4240")
expect both(1000000000000.U64, "1b000000e8d4a51000")
expect both(18446744073709551615.U64, "1bffffffffffffffff")
expect both(-1.I64, "20")
expect both(-10.I64, "29")
expect both(-100.I64, "3863")
expect both(-1000.I64, "3903e7")

# One type for each width: U8, U16, U32, I8, I16, I32 (the same bytes as U64 and I64)

expect both(24.U8, "1818")
expect both(255.U8, "18ff")
expect both(1000.U16, "1903e8")
expect both(65535.U16, "19ffff")
expect both(1000000.U32, "1a000f4240")
expect both(4294967295.U32, "1affffffff")
expect both(-100.I8, "3863")
expect both(-128.I8, "387f")
expect both(-1000.I16, "3903e7")
expect both(-32768.I16, "397fff")
expect both(-1000000.I32, "3a000f423f")
expect both(-2147483648.I32, "3a7fffffff")
expect both(9223372036854775807.I64, "1b7fffffffffffffff")
expect both(-9223372036854775808.I64, "3b7fffffffffffffff")

# A value that does not fit the type is an error at the start of the item

expect error_at(0.U8, "190100") == Ok(0)
expect error_at(0.U8, "20") == Ok(0)
expect error_at(0.U16, "1a00010000") == Ok(0)
expect error_at(0.U32, "1b0000000100000000") == Ok(0)
expect error_at(0.I8, "3880") == Ok(0)
expect error_at(0.I8, "1880") == Ok(0)
expect error_at(0.I16, "398000") == Ok(0)
expect error_at(0.I32, "3a80000000") == Ok(0)
expect error_at(0.I64, "1b8000000000000000") == Ok(0)
expect error_at(0.I64, "3bffffffffffffffff") == Ok(0)

# Any width of the argument is read, also when it is longer than needed

expect reads(0.U64, "1800")
expect reads(10.U64, "180a")
expect reads(1.U64, "190001")
expect reads(1.U64, "1a00000001")
expect reads(1.U64, "1b0000000000000001")
expect reads(-1.I64, "3800")
expect reads(-1.I64, "3b0000000000000000")

# Bignums (tags 2 and 3) are not in the profile

expect error_at(0.U64, "c249010000000000000000") == Ok(0)
expect error_at(0.I64, "c349010000000000000000") == Ok(0)

# Floats: f16, f32 and f64 are read, f64 and f32 are written

expect reads_f64(0.0, "f90000")
expect reads_f64(-0.0, "f98000")
expect reads_f64(1.0, "f93c00")
expect reads_f64(1.1, "fb3ff199999999999a")
expect reads_f64(1.5, "f93e00")
expect reads_f64(65504.0, "f97bff")
expect reads_f64(100000.0, "fa47c35000")
expect reads_f64(3.4028234663852886e38, "fa7f7fffff")
expect reads_f64(1.0e300, "fb7e37e43c8800759c")
expect reads_f64(0.00000005960464477539063, "f90001")
expect reads_f64(0.00006103515625, "f90400")
expect reads_f64(-4.0, "f9c400")
expect reads_f64(-4.1, "fbc010666666666666")
expect reads_f64(F64.infinity, "f97c00")
expect reads_nan("f97e00")
expect reads_f64(-F64.infinity, "f9fc00")
expect reads_f64(F64.infinity, "fa7f800000")
expect reads_nan("fa7fc00000")
expect reads_f64(-F64.infinity, "faff800000")
expect reads_f64(F64.infinity, "fb7ff0000000000000")
expect reads_nan("fb7ff8000000000000")
expect reads_f64(-F64.infinity, "fbfff0000000000000")

# An f64 is always written in 9 bytes (the profile does not shorten it)

expect writes(0.0.F64, "fb0000000000000000")
expect writes(-0.0.F64, "fb8000000000000000")
expect writes(1.0.F64, "fb3ff0000000000000")
expect writes(1.1.F64, "fb3ff199999999999a")
expect writes(1.0e300.F64, "fb7e37e43c8800759c")
expect writes(-4.1.F64, "fbc010666666666666")
expect writes(F64.infinity, "fb7ff0000000000000")
expect writes(-F64.infinity, "fbfff0000000000000")

# An f32 is written in 5 bytes, and read from f16, f32 and f64

expect writes(100000.0.F32, "fa47c35000")
expect writes(3.4028234663852886e38.F32, "fa7f7fffff")
expect writes(-4.0.F32, "fac0800000")
expect reads(100000.0.F32, "fa47c35000")
expect reads(1.5.F32, "f93e00")
expect reads(-4.0.F32, "f9c400")
expect reads(1.5.F32, "fb3ff8000000000000")

# An integer is read as a float. A float with no fraction is read as an integer only when its
# size is 2^53 - 1 or less: a larger float can be the rounded value of many integers.

expect reads(100.0.F64, "1864")
expect reads(-1.0.F64, "20")
expect reads(1.U64, "f93c00")
expect reads(9007199254740991.U64, "fb433fffffffffffff")
expect error_at(0.U64, "fb4340000000000000") == Ok(0)
expect reads(-4.I64, "f9c400")
expect error_at(0.U64, "f93e00") == Ok(0)
expect error_at(0.U64, "f97e00") == Ok(0)
expect error_at(0.U64, "f97c00") == Ok(0)
expect error_at(0.U64, "fbc3e0000000000000") == Ok(0)

# Simple values

expect both(Bool.False, "f4")
expect both(Bool.True, "f5")
expect error_at(Bool.False, "f6") == Ok(0)
expect error_at(Bool.False, "f0") == Ok(0)
expect error_at(Bool.False, "f8ff") == Ok(0)

# null and undefined both read as the `Null` of a `Try`

null_u64 : Try(U64, [Null])
null_u64 = Err(Null)

five_u64 : Try(U64, [Null])
five_u64 = Ok(5)

expect both(null_u64, "f6")
expect reads(null_u64, "f7")
expect reads(five_u64, "05")
expect error_at(0.U64, "f6") == Ok(0)
expect error_at(0.U64, "f7") == Ok(0)

# Text, major type 3

expect both("", "60")
expect both("a", "6161")
expect both("IETF", "6449455446")
expect both("\"\\", "62225c")
expect both("\u(fc)", "62c3bc")
expect both("\u(6c34)", "63e6b0b4")
expect both("\u(10151)", "64f0908591")
expect writes(Str.repeat("a", 24), "7818616161616161616161616161616161616161616161616161")
expect error_at("", "62c328") == Ok(0)
expect error_at("", "4161") == Ok(0)

# Byte strings, major type 2: `Cbor.Bytes` and `List(U8)` read them

expect both(Cbor.Bytes.([]), "40")
expect both(Cbor.Bytes.([1, 2, 3, 4]), "4401020304")
expect reads([1.U8, 2, 3, 4], "4401020304")
expect writes([1.U8, 2, 3, 4], "8401020304")
expect error_at(Cbor.Bytes.([]), "6161") == Ok(0)
expect reads(Cbor.Bytes.([1, 2, 3]), "83010203")

# Arrays, major type 4

empty_u64 : List(U64)
empty_u64 = []

one_to_25 : List(U64)
one_to_25 = (1.U64).to(25).collect()

expect both(empty_u64, "80")
expect both([1.U64, 2, 3], "83010203")
expect both((1.U64, [2.U64, 3], [4.U64, 5]), "8301820203820405")
expect both(("a", { b: "c" }), "826161a161626163")

# 25 items: the profile reads the 1-byte argument of the RFC, and writes a 2-byte argument
# (the head of a container has room for 25 or more items).

expect reads(one_to_25, "98190102030405060708090a0b0c0d0e0f101112131415161718181819")
expect writes(one_to_25, "9900190102030405060708090a0b0c0d0e0f101112131415161718181819")
expect reads(one_to_25, "9900190102030405060708090a0b0c0d0e0f101112131415161718181819")

# A tuple of the wrong length is an error

expect error_at((1.U64, 2.U64), "83010203") == Ok(0)
expect error_at((1.U64, 2.U64, 3.U64), "820102") == Ok(0)

# Maps, major type 5: a record reads a map with text keys

expect both({}, "a0")
expect both({ a: 1.U64, b: [2.U64, 3] }, "a26161016162820203")
expect both({ a: "A", b: "B", c: "C", d: "D", e: "E" }, "a56161614161626142616361436164614461656145")
expect reads(Dict.from_list([("a", "A"), ("b", "B")]), "a26161614161626142")

# A key that is not text is an error at the key

expect error_at({ a: 1.U64 }, "a10102") == Ok(1)
expect error_at({ a: 1.U64 }, "a201020304") == Ok(1)

# Tags, major type 6: a tag is not in the profile when it is a value

expect error_at("", "c074323031332d30332d32315432303a30343a30305a") == Ok(0)
expect error_at(0.U64, "c11a514b67b0") == Ok(0)
expect error_at(0.0.F64, "c1fb41d452d9ec200000") == Ok(0)
expect error_at(Cbor.Bytes.([]), "d74401020304") == Ok(0)
expect error_at(Cbor.Bytes.([]), "d818456449455446") == Ok(0)
expect error_at("", "d82076687474703a2f2f7777772e6578616d706c652e636f6d") == Ok(0)

# ...but a tagged value in a field that the record does not have is skipped

expect reads({ n: 1.U64 }, "a2656578747261c11a514b67b0616e01")
expect reads({ n: 1.U64 }, "a2656578747261c249010000000000000000616e01")
expect reads({ n: 1.U64 }, "a265657874726181a1616b4401020304616e01")

# Indefinite lengths are not in the profile: an error at the first byte

expect error_at(Cbor.Bytes.([]), "5f42010243030405ff") == Ok(0)
expect error_at("", "7f657374726561646d696e67ff") == Ok(0)
expect error_at(empty_u64, "9fff") == Ok(0)
expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "9f018202039f0405ffff") == Ok(0)
expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "9f01820203820405ff") == Ok(0)
expect error_at({ a: 1.U64, b: [2.U64, 3] }, "bf61610161629f0203ffff") == Ok(0)
expect error_at({ a: Bool.True }, "bf6346756ef563416d7421ff") == Ok(0)
expect error_at(one_to_25, "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff") == Ok(0)

# ...and in the middle of a value: an error where the indefinite item starts

expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "83018202039f0405ff") == Ok(5)
expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "83019f0203ff820405") == Ok(2)
expect error_at(("a", { b: "c" }), "826161bf61626163ff") == Ok(3)

# The break code alone, reserved additional information, and malformed input

expect error_at(0.U64, "ff") == Ok(0)
expect error_at(0.U64, "1c") == Ok(0)
expect error_at(0.U64, "1d") == Ok(0)
expect error_at(0.U64, "1e") == Ok(0)
expect error_at(0.U64, "1f") == Ok(0)
expect error_at(0.U64, "") == Ok(0)
expect error_at(0.U64, "18") == Ok(0)
expect error_at(0.U64, "1b00") == Ok(0)
expect error_at("", "6449") == Ok(0)
# An array with more items than bytes is an error at its head, before the parser makes the list
expect error_at(empty_u64, "8301") == Ok(0)
# A count that fits the bytes, with an item that does not, is an error where the item is missing
expect error_at(empty_u64, "821818") == Ok(3)

# Bytes after the value are an error at the position of the first one

expect error_at(0.U64, "0000") == Ok(1)
expect error_at(empty_u64, "8301020300") == Ok(4)
