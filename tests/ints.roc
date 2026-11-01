app [] { pkg: "../src/main.roc" }

# Small integer types (0.4.1), through the public API of the package.
# The reader keeps a CBOR integer as an I128 and goes through an I64 before U8, U16, U32, I8, I16 and I32.
# Cause: the wasm32 dev backend of the Roc compiler (roc build --target=wasm32 --opt=dev, nightlies 2026-10-31 and
# 2026-11-01) gives Err(OutOfRange) for I128.to_u8_try, to_u16_try, to_i8_try and to_i16_try of a value in range.
# `roc test` runs the interpreter, so these expects keep the rules of the range. The wasm32 dev check of the bug is
# in the cloudflare-workers platform (conformance, the memo checks of a dev build).
# Bytes: 0x18 0xff is 255, 0x19 0x01 0x00 is 256, 0x20 is -1, 0x38 0x7f is -128, 0x38 0x80 is -129.

import pkg.Cbor

## A List(U8) is an array of integers. It reads back, also at the bounds 0 and 255.
expect {
	v = [0.U8, 1, 127, 128, 255]
	r : Try(List(U8), _)
	r = Cbor.parse(Cbor.encode(v))
	r == Ok(v)
}

## A List(U8) in a tag payload and in a record (the shape of a JWK: Talon slice 108b).
expect {
	v : [Rsa({ n : List(U8), e : List(U8) }), Okp({ x : List(U8) })]
	v = Rsa({ n: [0, 200, 255], e: [1, 0, 1] })
	r : Try([Rsa({ n : List(U8), e : List(U8) }), Okp({ x : List(U8) })], _)
	r = Cbor.parse(Cbor.encode(v))
	r == Ok(v)
}

## Cbor.Bytes reads an array of integers 0 to 255 (a D1 BLOB).
expect {
	r : Try(Cbor.Bytes, _)
	r = Cbor.parse([0x83, 0x00, 0x18, 0xff, 0x05])
	r.map_ok(|b| b.to_list()) == Ok([0, 255, 5])
}

## Cbor.Bytes: 256 in the array is an error at that item (position 1).
expect {
	r : Try(Cbor.Bytes, _)
	r = Cbor.parse([0x81, 0x19, 0x01, 0x00])
	r.map_ok(|b| b.to_list()) == Err(InvalidCbor(1))
}

## U8: 255 reads, 256 and -1 are errors at the item.
expect {
	a : Try(U8, _)
	a = Cbor.parse([0x18, 0xff])
	b : Try(U8, _)
	b = Cbor.parse([0x19, 0x01, 0x00])
	c : Try(U8, _)
	c = Cbor.parse([0x20])
	a == Ok(255) and b == Err(InvalidCbor(0)) and c == Err(InvalidCbor(0))
}

## U16: 65535 reads, 65536 is an error.
expect {
	a : Try(U16, _)
	a = Cbor.parse([0x19, 0xff, 0xff])
	b : Try(U16, _)
	b = Cbor.parse([0x1a, 0x00, 0x01, 0x00, 0x00])
	a == Ok(65535) and b == Err(InvalidCbor(0))
}

## U32: 2^32 - 1 reads, 2^32 is an error.
expect {
	a : Try(U32, _)
	a = Cbor.parse([0x1a, 0xff, 0xff, 0xff, 0xff])
	b : Try(U32, _)
	b = Cbor.parse([0x1b, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])
	a == Ok(4_294_967_295) and b == Err(InvalidCbor(0))
}

## I8: -128 and 127 read, -129 and 128 are errors.
expect {
	a : Try(I8, _)
	a = Cbor.parse([0x38, 0x7f])
	b : Try(I8, _)
	b = Cbor.parse([0x18, 0x7f])
	c : Try(I8, _)
	c = Cbor.parse([0x38, 0x80])
	d : Try(I8, _)
	d = Cbor.parse([0x18, 0x80])
	a == Ok(-128) and b == Ok(127) and c == Err(InvalidCbor(0)) and d == Err(InvalidCbor(0))
}

## I16: -32768 reads, -32769 is an error.
expect {
	a : Try(I16, _)
	a = Cbor.parse([0x39, 0x7f, 0xff])
	b : Try(I16, _)
	b = Cbor.parse([0x39, 0x80, 0x00])
	a == Ok(-32768) and b == Err(InvalidCbor(0))
}

## I32: -2^31 reads, -2^31 - 1 is an error.
expect {
	a : Try(I32, _)
	a = Cbor.parse([0x3a, 0x7f, 0xff, 0xff, 0xff])
	b : Try(I32, _)
	b = Cbor.parse([0x3a, 0x80, 0x00, 0x00, 0x00])
	a == Ok(-2_147_483_648) and b == Err(InvalidCbor(0))
}

## A value outside the I64 range is an error for a small type, not a wrap: 2^64 - 1 as U8 and -2^64 as I8.
expect {
	a : Try(U8, _)
	a = Cbor.parse([0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	b : Try(I8, _)
	b = Cbor.parse([0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
	a == Err(InvalidCbor(0)) and b == Err(InvalidCbor(0))
}

## A list of each small type reads back.
expect {
	v = { a: [-128.I8, 0, 127], b: [-32768.I16, 32767], c: [-2_147_483_648.I32, 2_147_483_647], d: [0.U16, 65535], e: [0.U32, 4_294_967_295] }
	r : Try({ a : List(I8), b : List(I16), c : List(I32), d : List(U16), e : List(U32) }, _)
	r = Cbor.parse(Cbor.encode(v))
	r == Ok(v)
}
