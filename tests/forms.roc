app [] { pkg: "../src/main.roc" }

import pkg.Cbor

f64 : List(U8), Cbor.Options -> Try(F64, Cbor.Error)
f64 = |b, o| Cbor.parse_with(b, o)

f32 : List(U8), Cbor.Options -> Try(F32, Cbor.Error)
f32 = |b, o| Cbor.parse_with(b, o)

dec : List(U8), Cbor.Options -> Try(Dec, Cbor.Error)
dec = |b, o| Cbor.parse_with(b, o)

# Compatible reads keep the former forms; Encoder refuses them at their position.
expect {
	alternatives = [
		[0x00],
		[0xfa, 0x3f, 0xc0, 0, 0],
		[0xfb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0],
		[0xf9, 0x7e, 1],
		[0xf9, 0xfe, 0],
		[0xfa, 0x7f, 0xc0, 0, 0],
		[0xfb, 0x7f, 0xf8, 0, 0, 0, 0, 0, 1],
	]
	alternatives.all(|b| f64(b, {}).is_ok() and f64(b, { forms: Encoder }) == Err(InvalidCbor(0)) and f32(b, { forms: Encoder, allow: [FloatToInt] }) == Err(InvalidCbor(0)))
}

# F64 to F32 rounding is compatible only, even when both encoders use the same width.
expect {
	b = Cbor.encode(0.1.F64)
	f32(b, {}).is_ok() and f32(b, { forms: Encoder }) == Err(InvalidCbor(0)) and f64(b, { forms: Encoder }) == Ok(0.1)
}

# Each encoder width, infinities, canonical NaN and signed zero.
expect {
	values = [0.0.F64, F64.from_bits(0x8000000000000000), 1.5, 65504.0, 65505.0, 0.1, F64.from_bits(1), F64.from_bits(0x36a0000000000000), F64.infinity, -F64.infinity, F64.nan]
	values.all(|v| f64(Cbor.encode(v), { forms: Encoder }).map_ok(|back| if (v.is_nan()) back.is_nan() else back.to_bits() == v.to_bits()) == Ok(Bool.True))
}

expect {
	values = [0.0.F32, F32.from_bits(0x80000000), 1.5, 65505.0, 0.1, F32.from_bits(1), F32.infinity, -F32.infinity, F32.nan]
	values.all(|v| f32(Cbor.encode(v), { forms: Encoder }).map_ok(|back| if (v.is_nan()) back.is_nan() else back.to_bits() == v.to_bits()) == Ok(Bool.True))
}

# Fractions for integers, extra zeroes, alternative exponent, padded heads, floats and text.
expect {
	alternatives = [
		[0xc4, 0x82, 0x00, 0x01],
		[0xc4, 0x82, 0x20, 0x0a],
		[0xc4, 0x82, 0x21, 0x18, 0x96],
		[0xc4, 0x82, 0x00, 0x00],
		[0xd8, 0x04, 0x82, 0x20, 0x0f],
		[0xc4, 0x98, 0x02, 0x20, 0x0f],
		[0xc4, 0x82, 0x38, 0x00, 0x0f],
		[0xc4, 0x82, 0x20, 0x18, 0x0f],
		[0x18, 0x01],
		[0xf9, 0x3e, 0x00],
		Cbor.encode("1.5"),
	]
	alternatives.all(|b| dec(b, { allow: [DecFromText, PaddedNumbers] }).is_ok() and dec(b, { forms: Encoder, allow: [DecFromText, PaddedNumbers, FloatToInt] }) == Err(InvalidCbor(0)))
}

expect {
	values = [0.Dec, 1, -1, 1.5, -1.5, 0.000000000000000001, 18446744073709551615, -18446744073709551616, 18446744073709551616, -18446744073709551617, Dec.from_attos(I128.highest), Dec.from_attos(I128.lowest)]
	values.all(|v| dec(Cbor.encode(v), { forms: Encoder }) == Ok(v))
}

expect {
	compatible : Try(List(U8), _)
	compatible = Cbor.parse([0x40])
	rejected : Try(List(U8), _)
	rejected = Cbor.parse_with([0x40], { forms: Encoder })
	ordinary : Try(List(Str), _)
	ordinary = Cbor.parse_with([0x40], { forms: Encoder })
	array : Try(List(U8), _)
	array = Cbor.parse_with([0x80], { forms: Encoder })
	bytes : Try(Cbor.Bytes, _)
	bytes = Cbor.parse_with([0x40], { forms: Encoder })
	direct = Cbor.Reader.new([0x40], { forms: Encoder }).map_ok(|s| Cbor.parse_bytes(s.cbor, s.reader).map_ok(|b| b.value))
	compatible == Ok([]) and rejected == Err(InvalidCbor(0)) and ordinary == Err(InvalidCbor(0)) and array == Ok([]) and bytes == Ok(Cbor.Bytes.from_list([])) and direct == Ok(Ok([]))
}

# The option reaches outside formats, nested reads, map keys and streams.
expect {
	start = Cbor.Reader.new([0xfa, 0x3f, 0xc0, 0, 0], { forms: Encoder })
	start.map_ok(|s| Cbor.parse_f64(s.cbor, s.reader).map_ok(|v| v.value)) == Ok(Err(InvalidCbor(0)))
}

expect {
	parsed : Try(List(Dec), _)
	parsed = Cbor.parse_with([0x81, 0xf9, 0x3e, 0], { forms: Encoder })
	parsed == Err(InvalidCbor(1))
}

expect {
	parsed : Try(Dict(F64, U64), _)
	parsed = Cbor.parse_with([0xa1, 0xfa, 0x3f, 0xc0, 0, 0, 0], { forms: Encoder })
	parsed == Err(InvalidCbor(1))
}

expect {
	r : Try(F64, _)
	r = Cbor.parse_with([0xc6, 0xf9, 0x3e, 0], { forms: Encoder, ignore_tags: [6] })
	r == Err(InvalidCbor(0))
}

# Internal union layout still routes to the payload; forms applies to its scalar bytes.
expect {
	b = Cbor.encode({ kind: "Number", value: 1.5.F64 })
	r : Try([Number(F64)], _)
	r = Cbor.parse_with(b, { forms: Encoder, unions: Internal({ tag: "kind", content: "value" }) })
	r == Ok(Number(1.5))
}

expect {
	b = Cbor.encode({ kind: "Number", value: 1.5.Dec })
	r : Try([Number(Dec)], _)
	r = Cbor.parse_with(b, { forms: Encoder, unions: Internal({ tag: "kind", content: "value" }) })
	r == Ok(Number(1.5))
}

expect {
	step : { values : List(F64), rest : Try(Cbor.Items, [InvalidCbor(U64), MissingRequiredField(Str), TooLarge(U64)]) }
	step = Cbor.Items.array({ forms: Encoder }).push([0x81, 0xfa, 0x3f, 0xc0, 0, 0])
	step.values == [] and step.rest.map_ok(|_| {}) == Err(InvalidCbor(1))
}

# Padded bignum mantissas are compatible with PaddedNumbers, but never the encoder's decimal form.
expect {
	v = Dec.from_attos(I128.highest)
	b = Cbor.encode(v)
	alternatives = [
		[0xc4, 0x82, 0x20, 0xc2, 0x41, 0x0f],
		b.take_first(3).concat([0xd8, 0x02]).concat(b.drop_first(4)),
		b.take_first(4).concat([0x58, 0x10]).concat(b.drop_first(5)),
		b.take_first(4).concat([0x51, 0]).concat(b.drop_first(5)),
	]
	alternatives.all(|bytes| dec(bytes, { allow: [PaddedNumbers] }).is_ok() and dec(bytes, { forms: Encoder, allow: [PaddedNumbers] }) == Err(InvalidCbor(0)))
}

# Exact scalar forms take priority over ignored tags: preserve the encoder's decimal tag 4,
# and refuse an extra tag rather than silently stripping it.
expect dec(Cbor.encode(1.5.Dec), { forms: Encoder, ignore_tags: [4] }) == Ok(1.5)

expect {
	b = [0xc6].concat(Cbor.encode(1.5.Dec))
	dec(b, { forms: Encoder, ignore_tags: [6] }) == Err(InvalidCbor(0)) and f32([0xc6, 0xf9, 0x3e, 0], { forms: Encoder, ignore_tags: [6] }) == Err(InvalidCbor(0))
}
