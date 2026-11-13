app [] { pkg: "../src/main.roc" }

# RFC 8949 Appendix A test vectors, for the parts that the profile covers.
# A vector outside the profile is an expect that the parse is an error.
# Each vector is the hex text of the RFC.

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

## The bytes of `value` are the hex text `h`.
writes : a, Str -> Bool where [a.Cbor.Encodable([])]
writes = |value, h| Cbor.encode(value) == hex(h)

## The hex text `h` parses to `value`.
reads : a, Str -> Bool where [a.is_eq : a, a -> Bool, a.Cbor.Parseable(Cbor.Error)]
reads = |value, h| {
	r : Try(a, _)
	r = Cbor.parse(hex(h))
	match r {
		Ok(v) => v == value
		Err(_) => Bool.False
	}
}

## The hex text `h` parses to `value` with the lenient reads `allow`.
reads_with : a, Str, List(Cbor.Leniency) -> Bool where [a.is_eq : a, a -> Bool, a.Cbor.Parseable(Cbor.Error)]
reads_with = |value, h, allow| {
	r : Try(a, _)
	r = Cbor.parse_with(hex(h), { allow: allow })
	match r {
		Ok(v) => v == value
		Err(_) => Bool.False
	}
}

## Both: the shortest form of the RFC.
both : a, Str -> Bool where [a.is_eq : a, a -> Bool, a.Cbor.Parseable(Cbor.Error), a.Cbor.Encodable([])]
both = |value, h| writes(value, h) and reads(value, h)

## The hex text `h` parsed as the type of `witness` is `Err(InvalidCbor(pos))`. Gives `pos`.
error_at : a, Str -> Try(U64, [Parsed, Other]) where [a.Cbor.Parseable(Cbor.Error)]
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

## The hex helper turns the text 1b00ff into the bytes 1b 00 ff.
expect hex("1b00ff") == [0x1b, 0x00, 0xff]

# Integers, major types 0 and 1 (all widths of the argument)

## RFC 8949 Appendix A: 00 is 0, read and written as a U64.
expect both(0.U64, "00")

## RFC 8949 Appendix A: 01 is 1, read and written as a U64.
expect both(1.U64, "01")

## RFC 8949 Appendix A: 0a is 10, read and written as a U64.
expect both(10.U64, "0a")

## RFC 8949 Appendix A: 17 is 23, read and written as a U64.
expect both(23.U64, "17")

## RFC 8949 Appendix A: 18 18 is 24, read and written as a U64.
expect both(24.U64, "1818")

## RFC 8949 Appendix A: 18 19 is 25, read and written as a U64.
expect both(25.U64, "1819")

## RFC 8949 Appendix A: 18 64 is 100, read and written as a U64.
expect both(100.U64, "1864")

## RFC 8949 Appendix A: 19 03e8 is 1000, read and written as a U64.
expect both(1000.U64, "1903e8")

## RFC 8949 Appendix A: 1a 000f4240 is 1000000, read and written as a U64.
expect both(1000000.U64, "1a000f4240")

## RFC 8949 Appendix A: 1b 000000e8d4a51000 is 1000000000000, read and written as a U64.
expect both(1000000000000.U64, "1b000000e8d4a51000")

## RFC 8949 Appendix A: 1b ffffffffffffffff is 18446744073709551615, read and written as a U64.
expect both(18446744073709551615.U64, "1bffffffffffffffff")

## RFC 8949 Appendix A: 20 is -1, read and written as an I64.
expect both(-1.I64, "20")

## RFC 8949 Appendix A: 29 is -10, read and written as an I64.
expect both(-10.I64, "29")

## RFC 8949 Appendix A: 38 63 is -100, read and written as an I64.
expect both(-100.I64, "3863")

## RFC 8949 Appendix A: 39 03e7 is -1000, read and written as an I64.
expect both(-1000.I64, "3903e7")

# One type for each width: U8, U16, U32, I8, I16, I32 (the same bytes as U64 and I64)

## A U8 24 is 18 18, read and written.
expect both(24.U8, "1818")

## A U8 255, the largest U8, is 18 ff, read and written.
expect both(255.U8, "18ff")

## A U16 1000 is 19 03e8, read and written.
expect both(1000.U16, "1903e8")

## A U16 65535, the largest U16, is 19 ffff, read and written.
expect both(65535.U16, "19ffff")

## A U32 1000000 is 1a 000f4240, read and written.
expect both(1000000.U32, "1a000f4240")

## A U32 4294967295, the largest U32, is 1a ffffffff, read and written.
expect both(4294967295.U32, "1affffffff")

## An I8 -100 is 38 63, read and written.
expect both(-100.I8, "3863")

## An I8 -128, the smallest I8, is 38 7f, read and written.
expect both(-128.I8, "387f")

## An I16 -1000 is 39 03e7, read and written.
expect both(-1000.I16, "3903e7")

## An I16 -32768, the smallest I16, is 39 7fff, read and written.
expect both(-32768.I16, "397fff")

## An I32 -1000000 is 3a 000f423f, read and written.
expect both(-1000000.I32, "3a000f423f")

## An I32 -2147483648, the smallest I32, is 3a 7fffffff, read and written.
expect both(-2147483648.I32, "3a7fffffff")

## An I64 9223372036854775807, the largest I64, is 1b 7fffffffffffffff, read and written.
expect both(9223372036854775807.I64, "1b7fffffffffffffff")

## An I64 -9223372036854775808, the smallest I64, is 3b 7fffffffffffffff, read and written.
expect both(-9223372036854775808.I64, "3b7fffffffffffffff")

# A value that does not fit the type is an error at the start of the item

## 256 (19 0100) does not fit a U8: an error at byte 0.
expect error_at(0.U8, "190100") == Ok(0)

## -1 (20) does not fit a U8: an error at byte 0.
expect error_at(0.U8, "20") == Ok(0)

## 65536 (1a 00010000) does not fit a U16: an error at byte 0.
expect error_at(0.U16, "1a00010000") == Ok(0)

## 4294967296 (1b 0000000100000000) does not fit a U32: an error at byte 0.
expect error_at(0.U32, "1b0000000100000000") == Ok(0)

## -129 (38 80) does not fit an I8: an error at byte 0.
expect error_at(0.I8, "3880") == Ok(0)

## 128 (18 80) does not fit an I8: an error at byte 0.
expect error_at(0.I8, "1880") == Ok(0)

## -32769 (39 8000) does not fit an I16: an error at byte 0.
expect error_at(0.I16, "398000") == Ok(0)

## -2147483649 (3a 80000000) does not fit an I32: an error at byte 0.
expect error_at(0.I32, "3a80000000") == Ok(0)

## 2^63 (1b 8000000000000000) does not fit an I64: an error at byte 0.
expect error_at(0.I64, "1b8000000000000000") == Ok(0)

## -2^64 (3b ffffffffffffffff) does not fit an I64: an error at byte 0.
expect error_at(0.I64, "3bffffffffffffffff") == Ok(0)

# A head longer than needed is an error (RFC 8949 4.2.1). With `PaddedNumbers`, any width of the argument is read.

## 0 in a 1-byte argument (18 00) reads as 0 with PaddedNumbers.
expect reads_with(0.U64, "1800", [PaddedNumbers])

## 10 in a 1-byte argument (18 0a) reads as 10 with PaddedNumbers.
expect reads_with(10.U64, "180a", [PaddedNumbers])

## 1 in a 2-byte argument (19 0001) reads as 1 with PaddedNumbers.
expect reads_with(1.U64, "190001", [PaddedNumbers])

## 1 in a 4-byte argument (1a 00000001) reads as 1 with PaddedNumbers.
expect reads_with(1.U64, "1a00000001", [PaddedNumbers])

## 1 in an 8-byte argument (1b 0000000000000001) reads as 1 with PaddedNumbers.
expect reads_with(1.U64, "1b0000000000000001", [PaddedNumbers])

## -1 in a 1-byte argument (38 00) reads as -1 with PaddedNumbers.
expect reads_with(-1.I64, "3800", [PaddedNumbers])

## -1 in an 8-byte argument (3b 0000000000000000) reads as -1 with PaddedNumbers.
expect reads_with(-1.I64, "3b0000000000000000", [PaddedNumbers])

## 0 in a 1-byte argument (18 00) is an error at byte 0 without PaddedNumbers.
expect error_at(0.U64, "1800") == Ok(0)

## 1 in a 2-byte argument (19 0001) is an error at byte 0 without PaddedNumbers.
expect error_at(0.U64, "190001") == Ok(0)

## 1 in an 8-byte argument (1b 0000000000000001) is an error at byte 0 without PaddedNumbers.
expect error_at(0.U64, "1b0000000000000001") == Ok(0)

## -1 in a 1-byte argument (38 00) is an error at byte 0 without PaddedNumbers.
expect error_at(0.I64, "3800") == Ok(0)

# Bignums (tags 2 and 3) are not in the profile

## RFC 8949 Appendix A: c2 49 010000000000000000 (bignum 18446744073709551616) is an error at byte 0 as a U64.
expect error_at(0.U64, "c249010000000000000000") == Ok(0)

## RFC 8949 Appendix A: c3 49 010000000000000000 (bignum -18446744073709551617) is an error at byte 0 as an I64.
expect error_at(0.I64, "c349010000000000000000") == Ok(0)

# Floats: f16, f32 and f64 are read, f64 and f32 are written

## RFC 8949 Appendix A: f9 0000 reads as 0.0.
expect reads_f64(0.0, "f90000")

## RFC 8949 Appendix A: f9 8000 reads as -0.0, not 0.0.
expect reads_f64(-0.0, "f98000")

## RFC 8949 Appendix A: f9 3c00 reads as 1.0.
expect reads_f64(1.0, "f93c00")

## RFC 8949 Appendix A: fb 3ff199999999999a reads as 1.1.
expect reads_f64(1.1, "fb3ff199999999999a")

## RFC 8949 Appendix A: f9 3e00 reads as 1.5.
expect reads_f64(1.5, "f93e00")

## RFC 8949 Appendix A: f9 7bff reads as 65504.0.
expect reads_f64(65504.0, "f97bff")

## RFC 8949 Appendix A: fa 47c35000 reads as 100000.0.
expect reads_f64(100000.0, "fa47c35000")

## RFC 8949 Appendix A: fa 7f7fffff reads as 3.4028234663852886e+38.
expect reads_f64(3.4028234663852886e38, "fa7f7fffff")

## RFC 8949 Appendix A: fb 7e37e43c8800759c reads as 1.0e+300.
expect reads_f64(1.0e300, "fb7e37e43c8800759c")

## RFC 8949 Appendix A: f9 0001 reads as 5.960464477539063e-8.
expect reads_f64(0.00000005960464477539063, "f90001")

## RFC 8949 Appendix A: f9 0400 reads as 0.00006103515625.
expect reads_f64(0.00006103515625, "f90400")

## RFC 8949 Appendix A: f9 c400 reads as -4.0.
expect reads_f64(-4.0, "f9c400")

## RFC 8949 Appendix A: fb c010666666666666 reads as -4.1.
expect reads_f64(-4.1, "fbc010666666666666")

## RFC 8949 Appendix A: f9 7c00 reads as Infinity.
expect reads_f64(F64.infinity, "f97c00")

## RFC 8949 Appendix A: f9 7e00 reads as NaN.
expect reads_nan("f97e00")

## RFC 8949 Appendix A: f9 fc00 reads as -Infinity.
expect reads_f64(-F64.infinity, "f9fc00")

## RFC 8949 Appendix A: fa 7f800000 reads as Infinity.
expect reads_f64(F64.infinity, "fa7f800000")

## RFC 8949 Appendix A: fa 7fc00000 reads as NaN.
expect reads_nan("fa7fc00000")

## RFC 8949 Appendix A: fa ff800000 reads as -Infinity.
expect reads_f64(-F64.infinity, "faff800000")

## RFC 8949 Appendix A: fb 7ff0000000000000 reads as Infinity.
expect reads_f64(F64.infinity, "fb7ff0000000000000")

## RFC 8949 Appendix A: fb 7ff8000000000000 reads as NaN.
expect reads_nan("fb7ff8000000000000")

## RFC 8949 Appendix A: fb fff0000000000000 reads as -Infinity.
expect reads_f64(-F64.infinity, "fbfff0000000000000")

# A float is written in the shortest of f16, f32 and f64 that holds the same value (preferred serialization, RFC 8949 4.1).
# These are all the float vectors of Appendix A.

## RFC 8949 Appendix A: the F64 0.0 writes as f9 0000.
expect writes(0.0.F64, "f90000")

## RFC 8949 Appendix A: the F64 -0.0 writes as f9 8000.
expect writes(-0.0.F64, "f98000")

## RFC 8949 Appendix A: the F64 1.0 writes as f9 3c00.
expect writes(1.0.F64, "f93c00")

## RFC 8949 Appendix A: the F64 1.1 writes as fb 3ff199999999999a.
expect writes(1.1.F64, "fb3ff199999999999a")

## RFC 8949 Appendix A: the F64 1.5 writes as f9 3e00.
expect writes(1.5.F64, "f93e00")

## RFC 8949 Appendix A: the F64 65504.0 writes as f9 7bff.
expect writes(65504.0.F64, "f97bff")

## RFC 8949 Appendix A: the F64 100000.0 writes as fa 47c35000.
expect writes(100000.0.F64, "fa47c35000")

## RFC 8949 Appendix A: the F64 3.4028234663852886e+38 writes as fa 7f7fffff.
expect writes(3.4028234663852886e38.F64, "fa7f7fffff")

## RFC 8949 Appendix A: the F64 1.0e+300 writes as fb 7e37e43c8800759c.
expect writes(1.0e300.F64, "fb7e37e43c8800759c")

## RFC 8949 Appendix A: the F64 5.960464477539063e-8 writes as f9 0001.
expect writes(5.960464477539063e-8.F64, "f90001")

## RFC 8949 Appendix A: the F64 0.00006103515625 writes as f9 0400.
expect writes(0.00006103515625.F64, "f90400")

## RFC 8949 Appendix A: the F64 -4.0 writes as f9 c400.
expect writes(-4.0.F64, "f9c400")

## RFC 8949 Appendix A: the F64 -4.1 writes as fb c010666666666666.
expect writes(-4.1.F64, "fbc010666666666666")

## RFC 8949 Appendix A: the F64 Infinity writes as f9 7c00.
expect writes(F64.infinity, "f97c00")

## RFC 8949 Appendix A: the F64 NaN writes as f9 7e00.
expect writes(F64.nan, "f97e00")

## RFC 8949 Appendix A: the F64 -Infinity writes as f9 fc00.
expect writes(-F64.infinity, "f9fc00")

# An F32 is written in the shortest of f16 and f32, and read from f16, f32 and f64

## The F32 100000.0 writes as f32 (fa 47c35000).
expect writes(100000.0.F32, "fa47c35000")

## The F32 3.4028234663852886e+38 writes as f32 (fa 7f7fffff).
expect writes(3.4028234663852886e38.F32, "fa7f7fffff")

## The F32 -4.0 writes as f16 (f9 c400).
expect writes(-4.0.F32, "f9c400")

## The F32 NaN writes as f16 (f9 7e00).
expect writes(F32.nan, "f97e00")

## An f32 (fa 47c35000) reads as the F32 100000.0.
expect reads(100000.0.F32, "fa47c35000")

## An f16 (f9 3e00) reads as the F32 1.5.
expect reads(1.5.F32, "f93e00")

## An f16 (f9 c400) reads as the F32 -4.0.
expect reads(-4.0.F32, "f9c400")

## An f64 (fb 3ff8000000000000) reads as the F32 1.5.
expect reads(1.5.F32, "fb3ff8000000000000")

# An integer is read as a float when the float is exact. With `FloatToInt`, a float with no fraction is read as an
# integer only when its size is 2^53 - 1 or less: a larger float can be the rounded value of many integers.

## The integer 100 (18 64) reads as the F64 100.0.
expect reads(100.0.F64, "1864")

## The integer -1 (20) reads as the F64 -1.0.
expect reads(-1.0.F64, "20")

## The float 1.0 (f9 3c00) reads as the U64 1 with FloatToInt.
expect reads_with(1.U64, "f93c00", [FloatToInt])

## The float 2^53 - 1 (fb 433fffffffffffff) reads as the U64 9007199254740991 with FloatToInt.
expect reads_with(9007199254740991.U64, "fb433fffffffffffff", [FloatToInt])

## The float -4.0 (f9 c400) reads as the I64 -4 with FloatToInt.
expect reads_with(-4.I64, "f9c400", [FloatToInt])

## The float 1.0 (f9 3c00) is an error at byte 0 as a U64 without FloatToInt.
expect error_at(0.U64, "f93c00") == Ok(0)

## The float -4.0 (f9 c400) is an error at byte 0 as an I64 without FloatToInt.
expect error_at(0.I64, "f9c400") == Ok(0)

## The float 2^53 (fb 4340000000000000) is an error at byte 0 as a U64.
expect error_at(0.U64, "fb4340000000000000") == Ok(0)

## The float 1.5 (f9 3e00) is an error at byte 0 as a U64.
expect error_at(0.U64, "f93e00") == Ok(0)

## NaN (f9 7e00) is an error at byte 0 as a U64.
expect error_at(0.U64, "f97e00") == Ok(0)

## Infinity (f9 7c00) is an error at byte 0 as a U64.
expect error_at(0.U64, "f97c00") == Ok(0)

## The float -2^63 (fb c3e0000000000000) is an error at byte 0 as a U64.
expect error_at(0.U64, "fbc3e0000000000000") == Ok(0)

# Simple values

## RFC 8949 Appendix A: f4 is false, read and written.
expect both(Bool.False, "f4")

## RFC 8949 Appendix A: f5 is true, read and written.
expect both(Bool.True, "f5")

## RFC 8949 Appendix A: null (f6) is an error at byte 0 as a Bool.
expect error_at(Bool.False, "f6") == Ok(0)

## RFC 8949 Appendix A: simple(16) (f0) is an error at byte 0 as a Bool.
expect error_at(Bool.False, "f0") == Ok(0)

## RFC 8949 Appendix A: simple(255) (f8 ff) is an error at byte 0 as a Bool.
expect error_at(Bool.False, "f8ff") == Ok(0)

# null reads as the `Null` of a `Try`. undefined does too with `UndefinedAsNull`.

null_u64 : Try(U64, [Null])
null_u64 = Err(Null)

five_u64 : Try(U64, [Null])
five_u64 = Ok(5)

## RFC 8949 Appendix A: null (f6) is Err(Null), read and written.
expect both(null_u64, "f6")

## RFC 8949 Appendix A: undefined (f7) reads as Err(Null) with UndefinedAsNull.
expect reads_with(null_u64, "f7", [UndefinedAsNull])

## RFC 8949 Appendix A: undefined (f7) is an error at byte 0 without UndefinedAsNull.
expect error_at(null_u64, "f7") == Ok(0)

## 5 (05) reads as Ok(5) in a Try(U64, [Null]).
expect reads(five_u64, "05")

## null (f6) is an error at byte 0 as a U64.
expect error_at(0.U64, "f6") == Ok(0)

## undefined (f7) is an error at byte 0 as a U64.
expect error_at(0.U64, "f7") == Ok(0)

# Text, major type 3

## RFC 8949 Appendix A: 60 is the empty text, read and written.
expect both("", "60")

## RFC 8949 Appendix A: 61 61 is "a", read and written.
expect both("a", "6161")

## RFC 8949 Appendix A: 64 49455446 is "IETF", read and written.
expect both("IETF", "6449455446")

## RFC 8949 Appendix A: 62 225c is the text of a quote and a backslash, read and written.
expect both("\"\\", "62225c")

## RFC 8949 Appendix A: 62 c3bc is "\u(fc)", read and written.
expect both("\u(fc)", "62c3bc")

## RFC 8949 Appendix A: 63 e6b0b4 is "\u(6c34)", read and written.
expect both("\u(6c34)", "63e6b0b4")

## RFC 8949 Appendix A: 64 f0908591 is "\u(10151)", read and written.
expect both("\u(10151)", "64f0908591")

## A text of 24 "a" writes with a 1-byte length (78 18).
expect writes(Str.repeat("a", 24), "7818616161616161616161616161616161616161616161616161")

## Text that is not valid UTF-8 (62 c328) is an error at byte 0.
expect error_at("", "62c328") == Ok(0)

## A byte string (41 61) is an error at byte 0 as a Str.
expect error_at("", "4161") == Ok(0)

# Byte strings, major type 2: a `List(U8)` reads and writes them. An empty one writes an empty array, which reads back.
# A non-empty array needs `BytesFromArray`.

empty_u8 : List(U8)
empty_u8 = []

## RFC 8949 Appendix A: the empty byte string (40) reads as an empty List(U8).
expect reads(empty_u8, "40")

## An empty List(U8) writes as the empty array (80), which reads back.
expect both(empty_u8, "80")

## RFC 8949 Appendix A: 44 01020304 is the List(U8) [1, 2, 3, 4], read and written.
expect both([1.U8, 2, 3, 4], "4401020304")

## Text (61 61) is an error at byte 0 as a List(U8).
expect error_at(empty_u8, "6161") == Ok(0)

## The array [1, 2, 3] (83 010203) reads as a List(U8) with BytesFromArray.
expect reads_with([1.U8, 2, 3], "83010203", [BytesFromArray])

## The array [1, 2, 3] (83 010203) is an error at byte 0 as a List(U8) without BytesFromArray.
expect error_at(empty_u8, "83010203") == Ok(0)

## A Cbor.U8Array of [1, 2, 3] is the array 83 010203, read and written.
expect both(Cbor.U8Array.([1, 2, 3]), "83010203")

# Arrays, major type 4

empty_u64 : List(U64)
empty_u64 = []

one_to_25 : List(U64)
one_to_25 = (1.U64).to(25).collect()

## RFC 8949 Appendix A: 80 is the empty array, read and written as a List(U64).
expect both(empty_u64, "80")

## RFC 8949 Appendix A: 83 010203 is [1, 2, 3], read and written.
expect both([1.U64, 2, 3], "83010203")

## RFC 8949 Appendix A: 83 01 820203 820405 is [1, [2, 3], [4, 5]], read and written as a tuple.
expect both((1.U64, [2.U64, 3], [4.U64, 5]), "8301820203820405")

## RFC 8949 Appendix A: 82 6161 a1 6162 6163 is ["a", {"b": "c"}], read and written as a tuple.
expect both(("a", { b: "c" }), "826161a161626163")

# 25 items: the 1-byte argument of the RFC. A 2-byte argument needs `PaddedNumbers`.

## RFC 8949 Appendix A: 98 19 and the items 1 to 25 is the list 1 to 25, read and written.
expect both(one_to_25, "98190102030405060708090a0b0c0d0e0f101112131415161718181819")

## The list 1 to 25 with a 2-byte count (99 0019) reads with PaddedNumbers.
expect reads_with(one_to_25, "9900190102030405060708090a0b0c0d0e0f101112131415161718181819", [PaddedNumbers])

## The list 1 to 25 with a 2-byte count (99 0019) is an error at byte 0 without PaddedNumbers.
expect error_at(one_to_25, "9900190102030405060708090a0b0c0d0e0f101112131415161718181819") == Ok(0)

# A tuple of the wrong length is an error

## An array of 3 items (83 010203) is an error at byte 0 as a tuple of 2.
expect error_at((1.U64, 2.U64), "83010203") == Ok(0)

## An array of 2 items (82 0102) is an error at byte 0 as a tuple of 3.
expect error_at((1.U64, 2.U64, 3.U64), "820102") == Ok(0)

# Maps, major type 5: a record reads a map with text keys

## RFC 8949 Appendix A: a0 is the empty map, read and written as the empty record.
expect both({}, "a0")

## RFC 8949 Appendix A: a2 6161 01 6162 820203 is {a: 1, b: [2, 3]}, read and written as a record.
expect both({ a: 1.U64, b: [2.U64, 3] }, "a26161016162820203")

## RFC 8949 Appendix A: a5 and the keys a to e with the values A to E is a record of 5 text fields, read and written.
expect both({ a: "A", b: "B", c: "C", d: "D", e: "E" }, "a56161614161626142616361436164614461656145")

## The map {"a": "A", "b": "B"} (a2 6161 6141 6162 6142) reads as a Dict.
expect reads(Dict.from_list([("a", "A"), ("b", "B")]), "a26161614161626142")

# A key that is not text is an error at the key

## The map {1: 2} (a1 0102) is an error at byte 1, the key, as a record.
expect error_at({ a: 1.U64 }, "a10102") == Ok(1)

## RFC 8949 Appendix A: a2 01020304 ({1: 2, 3: 4}) is an error at byte 1, the first key, as a record.
expect error_at({ a: 1.U64 }, "a201020304") == Ok(1)

# Tags, major type 6: a tag is not in the profile when it is a value

## RFC 8949 Appendix A: tag 0 date text (c0 74 ...) is an error at byte 0 as a Str.
expect error_at("", "c074323031332d30332d32315432303a30343a30305a") == Ok(0)

## RFC 8949 Appendix A: tag 1 epoch time (c1 1a514b67b0) is an error at byte 0 as a U64.
expect error_at(0.U64, "c11a514b67b0") == Ok(0)

## RFC 8949 Appendix A: tag 1 epoch time as a float (c1 fb41d452d9ec200000) is an error at byte 0 as an F64.
expect error_at(0.0.F64, "c1fb41d452d9ec200000") == Ok(0)

## RFC 8949 Appendix A: tag 23 on bytes (d7 4401020304) is an error at byte 0 as a List(U8).
expect error_at(empty_u8, "d74401020304") == Ok(0)

## RFC 8949 Appendix A: tag 24 on bytes (d8 18 456449455446) is an error at byte 0 as a List(U8).
expect error_at(empty_u8, "d818456449455446") == Ok(0)

## RFC 8949 Appendix A: tag 32 on a URI text (d8 20 76 ...) is an error at byte 0 as a Str.
expect error_at("", "d82076687474703a2f2f7777772e6578616d706c652e636f6d") == Ok(0)

# ...but a tagged value in a field that the record does not have is skipped

## A record {n} skips an unknown field that holds tag 1 (c1 1a514b67b0) and reads n as 1.
expect reads({ n: 1.U64 }, "a2656578747261c11a514b67b0616e01")

## A record {n} skips an unknown field that holds a bignum (c2 49 ...) and reads n as 1.
expect reads({ n: 1.U64 }, "a2656578747261c249010000000000000000616e01")

## A record {n} skips an unknown field that holds [{"k": bytes}] and reads n as 1.
expect reads({ n: 1.U64 }, "a265657874726181a1616b4401020304616e01")

# Indefinite lengths are not in the profile: an error at the first byte

## RFC 8949 Appendix A: indefinite bytes (5f 420102 43030405 ff) is an error at byte 0.
expect error_at(empty_u8, "5f42010243030405ff") == Ok(0)

## RFC 8949 Appendix A: indefinite text "streaming" (7f ... ff) is an error at byte 0.
expect error_at("", "7f657374726561646d696e67ff") == Ok(0)

## RFC 8949 Appendix A: the empty indefinite array (9f ff) is an error at byte 0.
expect error_at(empty_u64, "9fff") == Ok(0)

## RFC 8949 Appendix A: 9f 01 820203 9f0405ff ff is an error at byte 0.
expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "9f018202039f0405ffff") == Ok(0)

## RFC 8949 Appendix A: 9f 01 820203 820405 ff is an error at byte 0.
expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "9f01820203820405ff") == Ok(0)

## RFC 8949 Appendix A: bf 6161 01 6162 9f0203ff ff is an error at byte 0.
expect error_at({ a: 1.U64, b: [2.U64, 3] }, "bf61610161629f0203ffff") == Ok(0)

## RFC 8949 Appendix A: bf 6346756e f5 63416d74 21 ff ({"Fun": true, "Amt": -2}) is an error at byte 0.
expect error_at({ a: Bool.True }, "bf6346756ef563416d7421ff") == Ok(0)

## RFC 8949 Appendix A: 9f and the items 1 to 25 and ff is an error at byte 0.
expect error_at(one_to_25, "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff") == Ok(0)

# ...and in the middle of a value: an error where the indefinite item starts

## RFC 8949 Appendix A: 83 01 820203 9f0405ff is an error at byte 5, the indefinite array.
expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "83018202039f0405ff") == Ok(5)

## RFC 8949 Appendix A: 83 01 9f0203ff 820405 is an error at byte 2, the indefinite array.
expect error_at((1.U64, [2.U64, 3], [4.U64, 5]), "83019f0203ff820405") == Ok(2)

## RFC 8949 Appendix A: 82 6161 bf 6162 6163 ff is an error at byte 3, the indefinite map.
expect error_at(("a", { b: "c" }), "826161bf61626163ff") == Ok(3)

# The break code alone, reserved additional information, and malformed input

## A break code alone (ff) is an error at byte 0.
expect error_at(0.U64, "ff") == Ok(0)

## The reserved additional information 28 (1c) is an error at byte 0.
expect error_at(0.U64, "1c") == Ok(0)

## The reserved additional information 29 (1d) is an error at byte 0.
expect error_at(0.U64, "1d") == Ok(0)

## The reserved additional information 30 (1e) is an error at byte 0.
expect error_at(0.U64, "1e") == Ok(0)

## An indefinite length on an integer (1f) is an error at byte 0.
expect error_at(0.U64, "1f") == Ok(0)

## No bytes at all is an error at byte 0.
expect error_at(0.U64, "") == Ok(0)

## A head 18 with no argument byte is an error at byte 0.
expect error_at(0.U64, "18") == Ok(0)

## A head 1b with 1 of its 8 argument bytes is an error at byte 0.
expect error_at(0.U64, "1b00") == Ok(0)

## Text of length 4 with 1 byte (64 49) is an error at byte 0.
expect error_at("", "6449") == Ok(0)
# The bytes end in an array: the error is at the head of the innermost open array (one truncation rule).
# The walk runs before the parser makes the list, so a large count gives no large list.
## An array of 3 with 1 item (83 01) is an error at byte 0, the array head.
expect error_at(empty_u64, "8301") == Ok(0)

## An array of 2 whose first item has no argument byte (82 18 18) is an error at byte 0, the array head.
expect error_at(empty_u64, "821818") == Ok(0)

# Bytes after the value are an error at the position of the first one

## A byte after the value (00 00) is an error at byte 1.
expect error_at(0.U64, "0000") == Ok(1)

## A byte after the array [1, 2, 3] (83 010203 00) is an error at byte 4.
expect error_at(empty_u64, "8301020300") == Ok(4)
