app [] { pkg: "../src/main.roc" }

# Preferred floats and deterministic encoding (0.5.0, W8 and C3 of the audit of 0.4.1), through the public API
# of the package: each float in the shortest of f16, f32 and f64 (RFC 8949 4.1), and `key_order: Sorted` (RFC 8949 4.2.1).

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

## The value writes the hex bytes `h`.
writes : a, Str -> Bool where [a.Cbor.Encodable([])]
writes = |value, h| Cbor.encode(value) == hex(h)

## The value writes the hex bytes `h` with `key_order: Sorted`.
sorts : a, Str -> Bool where [a.Cbor.Encodable([CountMismatch, DuplicateMapKey])]
sorts = |value, h| Cbor.encode_with(value, { key_order: Sorted }) == Ok(hex(h))

## A map written by hand with encode_dict: each key is text.
Keys := List(Str).{
	encoder_for : Cbor -> (Keys, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Keys.(keys), w|
		Cbor.encode_dict(
			w,
			keys.len(),
			|c, add| {
				var $c = c
				for k in keys {
					$c = add($c, |kw| Cbor.encode_str(k, kw), |vw| Cbor.encode_u64(7, vw))?
				}
				Ok($c)
			},
		)
}

vmap : List((Cbor.Value, Cbor.Value)) -> Cbor.Value
vmap = |pairs| Cbor.Value.Map(Cbor.ValueMap.from_list(pairs) ?? Cbor.ValueMap.empty())

text : Str -> Cbor.Value
text = |s| Cbor.Value.Text(s)

# Floats: the shortest form with the same value

## f16 at its edges: the largest (65504), the smallest normal (2^-14), the largest and the smallest subnormal.
expect writes(65504.0.F64, "f97bff")

## 2^-14, the smallest normal f16, writes as f9 04 00.
expect writes(0.00006103515625.F64, "f90400")

## The largest f16 subnormal (1023 * 2^-24) writes as f9 03 ff.
expect writes(0.00006097555160522461.F64, "f903ff")

## The smallest f16 subnormal (2^-24) writes as f9 00 01.
expect writes(0.00000005960464477539063.F64, "f90001")

## 3 * 2^-24, an f16 subnormal, writes as f9 00 03.
expect writes(0.00000017881393432617188.F64, "f90003")

## Just out of f16: one more bit (65505), too large (65520 rounds to an f16 infinity), too small (2^-25), a fraction of
## the smallest subnormal (1.5 * 2^-24).
expect writes(65505.0.F64, "fa477fe100")

## 65520 rounds to an f16 infinity, so it writes as f32 (fa 47 7f f0 00).
expect writes(65520.0.F64, "fa477ff000")

## 2^-25 is too small for f16 and writes as f32 (fa 33 00 00 00).
expect writes(0.000000029802322387695312.F64, "fa33000000")

## 1.5 * 2^-24 is not exact in f16 and writes as f32 (fa 33 c0 00 00).
expect writes(0.00000008940696716308594.F64, "fa33c00000")

## f32 at its edges: the smallest normal (2^-126) and the smallest subnormal (2^-149). A subnormal f64 stays f64.
expect writes(F64.from_bits(0x3810000000000000), "fa00800000")

## 2^-149, the smallest f32 subnormal, writes as fa 00 00 00 01.
expect writes(F64.from_bits(0x36a0000000000000), "fa00000001")

## The smallest f64 subnormal (bits 1) stays f64: fb 00 00 00 00 00 00 00 01.
expect writes(F64.from_bits(1), "fb0000000000000001")

## Exact only in f64: 1e-7, 0.1, 2^24 + 1.
expect writes(0.0000001.F64, "fb3e7ad7f29abcaf48")

## 0.1 is exact only in f64: fb 3f b9 99 99 99 99 99 9a.
expect writes(0.1.F64, "fb3fb999999999999a")

## 2^24 + 1 (16777217) is exact only in f64: fb 41 70 00 00 10 00 00 00.
expect writes(16777217.0.F64, "fb4170000010000000")

## NaN, the infinities and -0.0 as f16.
expect writes(F64.nan, "f97e00")

## A negative NaN writes the same f16 NaN f9 7e 00.
expect writes(-F64.nan, "f97e00")

## Infinity writes as f9 7c 00.
expect writes(F64.infinity, "f97c00")

## -Infinity writes as f9 fc 00.
expect writes(-F64.infinity, "f9fc00")

## -0.0 writes as f9 80 00.
expect writes(-0.0.F64, "f98000")

## F32 values: f16 when exact, else f32.
expect writes(1.5.F32, "f93e00")

## The F32 65504.0 writes as the f16 f9 7b ff.
expect writes(65504.0.F32, "f97bff")

## The F32 -0.0 writes as the f16 f9 80 00.
expect writes(-0.0.F32, "f98000")

## The F32 infinity writes as the f16 f9 7c 00.
expect writes(F32.infinity, "f97c00")

## The F32 0.1 is not exact in f16 and writes as f32 (fa 3d cc cc cd).
expect writes(0.1.F32, "fa3dcccccd")

## The F32 1e-7 writes as f32 (fa 33 d6 bf 95).
expect writes(0.0000001.F32, "fa33d6bf95")

## Each value reads back exactly, an F32 also from an f16.
expect {
	values = [65504.0.F64, 65505.0, 0.00006097555160522461, 0.00000005960464477539063, 0.0000001, 0.1, 16777217.0, -0.0, F64.infinity, F64.from_bits(1), F64.from_bits(0x36a0000000000000)]
	values.all(|f| (Cbor.parse(Cbor.encode(f)) ?? 0.5.F64).to_bits() == f.to_bits())
}

## Each F32 value reads back with the same bits, also the ones written as f16.
expect {
	values = [1.5.F32, 65504.0, 0.00000005960464477539063, -0.0, 0.1, 0.0000001, F32.infinity]
	values.all(|f| (Cbor.parse(Cbor.encode(f)) ?? 0.5.F32).to_bits() == f.to_bits())
}

## A NaN reads back as a NaN.
expect (Cbor.parse(Cbor.encode(F64.nan)) ?? 0.0.F64).is_nan()

## A Cbor.Value float: each NaN is equal to each NaN (they write the same bytes), 0.0 and -0.0 are not equal.
expect Cbor.Value.Float(F64.nan) == Cbor.Value.Float(-F64.nan)

## A Cbor.Value float 0.0 is not equal to -0.0.
expect Cbor.Value.Float(0.0) != Cbor.Value.Float(-0.0)

## A Cbor.Value float 0.1 writes as f64 (fb 3f b9 99 99 99 99 99 9a).
expect writes(Cbor.Value.Float(0.1), "fb3fb999999999999a")

# key_order: Sorted (RFC 8949 4.2.1)

## The bytewise order of the keys: "b" (61 62) before "aa" (62 61 61). Given keeps the order of the fields.
expect writes({ aa: 1.U64, b: 2.U64 }, "a262616101616202")

## With Sorted, the record { aa: 1, b: 2 } writes "b" before "aa": a2 61 62 02 62 61 61 01.
expect sorts({ aa: 1.U64, b: 2.U64 }, "a261620262616101")

## Integer keys: bytewise, not shorter first. 24 (18 18) comes before -1 (20).
expect {
	d : Dict(I64, Str)
	d = Dict.from_list([(-1, "m"), (24, "x"), (10, "t"), (0, "z")])
	sorts(d, "a400617a0a61741818617820616d")
}

## Nested maps: each map is sorted, the inner ones too, also in an array.
expect sorts({ zz: { b: 1.U64, aa: 2.U64 }, a: [{ cc: 0.U64, d: 0.U64 }] }, "a2616181a261640062636300627a7aa261620162616102")

## A record with absent fields: the shorter head, then the sort.
expect {
	v : { aa : Try(U64, [Missing]), b : U64, ccc : U64, d : U64 }
	v = { aa: Err(Missing), b: 1, ccc: 2, d: 3 }
	sorts(v, "a36162016164036363636302")
}

## A Dict: the same bytes for any order of insert. Given keeps the order of the Dict.
expect {
	one : Dict(Str, U64)
	one = Dict.from_list([("bb", 1), ("a", 2), ("c", 3)])
	two : Dict(Str, U64)
	two = Dict.from_list([("c", 3), ("a", 2), ("bb", 1)])
	sorted = "a361610261630362626201"
	sorts(one, sorted) and sorts(two, sorted) and Cbor.encode(one) != Cbor.encode(two)
}

## A Cbor.Value map with a map as a key: the keys compare in their sorted form. Unsorted, k1 (a2 62 61 61 00 ..) is before
## k2 (a2 62 61 61 01 ..). Sorted, k2 (a2 61 62 00 ..) is before k1 (a2 61 62 05 ..).
expect {
	k1 = vmap([(text("aa"), Cbor.Value.Int(0)), (text("b"), Cbor.Value.Int(5))])
	k2 = vmap([(text("aa"), Cbor.Value.Int(1)), (text("b"), Cbor.Value.Int(0))])
	m = vmap([(k1, Cbor.Value.Int(1)), (k2, Cbor.Value.Int(2)), (Cbor.Value.Int(3), Cbor.Value.Null)])
	sorts(m, "a303f6a26162006261610102a26162056261610001")
}

## The same Cbor.Value map built in two orders writes the same bytes.
expect {
	pairs = [(text("b"), Cbor.Value.Int(1)), (Cbor.Value.Int(-1), Cbor.Value.Null), (text("aa"), Cbor.Value.Bool(Bool.True))]
	sorts(vmap(pairs), "a320f6616201626161f5") and Cbor.encode_with(vmap(pairs.rev()), { key_order: Sorted }) == Cbor.encode_with(vmap(pairs), { key_order: Sorted })
}

## A Cbor.Value map reads back from its sorted bytes with its entries in the sorted order: `0` (`00`) before `""` (`60`).
## A ValueMap keeps the order of its entries, so that is not equal to the map in the other order, but it writes the same
## sorted bytes. (Fuzz, round_trip: the property expected the map in its first order.)
expect {
	given = vmap([(text(""), text("")), (Cbor.Value.Int(Cbor.IntValue.from_u64(0)), text(""))])
	sorted = vmap([(Cbor.Value.Int(Cbor.IntValue.from_u64(0)), text("")), (text(""), text(""))])
	bytes = Cbor.encode_with(given, { key_order: Sorted }) ?? []
	back : Try(Cbor.Value, _)
	back = Cbor.parse_with(bytes, { key_order: Sorted })
	bytes == hex("a200606060") and back == Ok(sorted) and given != sorted and sorts(sorted, "a200606060")
}

## A map of indefinite length in a Cbor.Raw is sorted too, and keeps its break. A byte string that looks like a map does not change.
expect {
	raw : Try(Cbor.Raw, _)
	raw = Cbor.parse_with(hex("bf616202616101ff"), { allow: [IndefiniteLength] })
	match raw {
		Ok(r) => sorts({ r, s: Cbor.Bytes.from_list(hex("a2616202616101")) }, "a26172bf616101616202ff617347a2616202616101")
		Err(_) => Bool.False
	}
}

## Data with no map of two entries does not change.
expect sorts([1.U64, 2, 3], "83010203")

## Sorted on { a: [{ b: 1 }] }, with maps of one entry, gives the same bytes a1 61 61 81 a1 61 62 01.
expect sorts({ a: [{ b: 1.U64 }] }, "a1616181a1616201")

## Two entries with the same key bytes: an error. An encoder_for of your own, and two fields with one camelCase key.
expect Cbor.encode_with(Keys.(["a", "b", "a"]), { key_order: Sorted }) == Err(DuplicateMapKey)

## Without Sorted, the keys "a", "b", "a" write as given with no error: a3 61 61 07 61 62 07 61 61 07.
expect Cbor.encode_with(Keys.(["a", "b", "a"]), {}) == Ok(hex("a3616107616207616107"))

## With Sorted and Camel, the fields a_1 and a1 both write the key "a1": an error DuplicateMapKey.
expect Cbor.encode_with({ a_1: 1.U64, a1: 2.U64 }, { fields: Camel, key_order: Sorted }) == Err(DuplicateMapKey)

## With Given (the default) too: a derived record never writes a key two times. Also in a list, and with one field absent
## (no collision then). Different camelCase keys write as before.
expect Cbor.encode_with({ a_1: 1.U64, a1: 2.U64 }, { fields: Camel }) == Err(DuplicateMapKey)

## With Camel, a_1 and a1 in a record in a list is also an error DuplicateMapKey.
expect Cbor.encode_with([{ x: { a_1: 1.U64, a1: 2.U64 } }], { fields: Camel }) == Err(DuplicateMapKey)

## With Camel, a_1 absent (Err(Missing)) and a1: 2 write one entry a1: 2 (a1 62 61 31 02).
expect {
	v : { a_1 : Try(U64, [Missing]), a1 : U64 }
	v = { a_1: Err(Missing), a1: 2 }
	Cbor.encode_with(v, { fields: Camel }) == Ok(hex("a162613102"))
}

## With Camel, a_b and ab write the different keys "aB" and "ab" with no error.
expect Cbor.encode_with({ a_b: 1.U64, ab: 2.U64 }, { fields: Camel }) == Ok(hex("a26261420162616202"))

## Without Camel, a_1 and a1 are the different keys "a_1" and "a1": no error.
expect Cbor.encode_with({ a_1: 1.U64, a1: 2.U64 }, {}) == Ok(hex("a26261310263615f3101"))

## A round trip: the sorted bytes read back, and the encode of the parse gives the same bytes.
expect {
	v = { zz: { b: 1.U64, aa: [2.5.F64, 0.1] }, a: Dict.from_list([("y", -1.I64), ("x", 7)]), m: "t" }
	bytes = Cbor.encode_with(v, { key_order: Sorted }) ?? []
	back : Try({ zz : { b : U64, aa : List(F64) }, a : Dict(Str, I64), m : Str }, _)
	back = Cbor.parse(bytes)
	value : Try(Cbor.Value, _)
	value = Cbor.parse(bytes)
	again = value.map_ok(|x| Cbor.encode_with(x, { key_order: Sorted }) ?? [])
	back == Ok(v) and again == Ok(bytes)
}
