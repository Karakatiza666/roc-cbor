app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Fuzz
import pkg.Cbor

# L1 target: Cbor.parse(Cbor.encode(v)) gives v back, for random values of one record type.
# Cbor.parse_with with int_from_text gives the same value.
# A record with Err(Null) in a field reads back as Err(Missing): a null value in a map is no key.

Kind : [Empty, One(U32), Two(Str, I16)]

Item : {
	id : U64,
	delta : I64,
	name : Str,
	tags : List(Str),
	data : Cbor.Bytes,
	small : List(U8),
	score : F64,
	ratio : F32,
	price : Dec,
	note : Try(Str, [Missing]),
	flag : Bool,
	cells : List(Try(I64, [Null])),
	kind : Kind,
	pairs : List((U8, Str)),
	nested : List(List(U64)),
}

## NaN is not equal to itself, so the generator gives 0 in its place.
no_nan64 : F64 -> F64
no_nan64 = |f| if (f.is_nan()) 0.0 else f

no_nan32 : F32 -> F32
no_nan32 = |f| if (f.is_nan()) 0.0 else f

kind : Fuzz.Generator(Kind)
kind = Fuzz.map(
	{ pick: Fuzz.u8, n: Fuzz.u64, s: Fuzz.str }.Fuzz,
	|g|
		match g.pick % 3 {
			0 => Empty
			1 => One(g.n.to_u32_wrap())
			_ => Two(g.s, g.n.to_i16_wrap())
		},
)

note : Fuzz.Generator(Try(Str, [Missing]))
note = Fuzz.map({ pick: Fuzz.u8, s: Fuzz.str }.Fuzz, |g| if (g.pick % 2 == 0) Err(Missing) else Ok(g.s))

cell : Fuzz.Generator(Try(I64, [Null]))
cell = Fuzz.map({ pick: Fuzz.u8, n: Fuzz.u64 }.Fuzz, |g| if (g.pick % 2 == 0) Err(Null) else Ok(g.n.to_i64_wrap()))

## The same row as written by a peer that gives a null for no value.
Wire : { id : U64, note : Try(Str, [Null]) }

wire : Item -> Wire
wire = |v| {
	id: v.id,
	note: match v.note {
		Ok(s) => Ok(s)
		Err(Missing) => Err(Null)
	},
}

item : Fuzz.Generator(Item)
item = {
	id: Fuzz.u64,
	delta: Fuzz.map(Fuzz.u64, |n| n.to_i64_wrap()),
	name: Fuzz.str,
	tags: Fuzz.list(Fuzz.str, 4),
	data: Fuzz.map(Fuzz.bytes, |b| Cbor.Bytes.(b)),
	small: Fuzz.bytes,
	score: Fuzz.map(Fuzz.f64, no_nan64),
	ratio: Fuzz.map(Fuzz.f32, no_nan32),
	price: Fuzz.map({ a: Fuzz.u64, b: Fuzz.u64, z: Fuzz.u8 }.Fuzz, |g| Dec.from_attos((g.a.to_i64_wrap().to_i128() * 4_611_686_018_427_387_904 + g.b.to_i128()) // (10.I128).pow(g.z.to_i128() % 19))),
	note,
	flag: Fuzz.map(Fuzz.u8, |b| b % 2 == 0),
	cells: Fuzz.list(cell, 6),
	kind,
	pairs: Fuzz.list(Fuzz.map({ k: Fuzz.u8, v: Fuzz.str }.Fuzz, |p| (p.k, p.v)), 4),
	nested: Fuzz.list(Fuzz.list(Fuzz.u64, 30), 3),
}.Fuzz

test! : Item => Fuzz.Outcome
test! = |value| {
	bytes = Cbor.encode(value)
	back : Try(Item, _)
	back = Cbor.parse(bytes)
	# int_from_text changes nothing when the integers are CBOR integers.
	with_text : Try(Item, _)
	with_text = Cbor.parse_with(bytes, { fields: Snake, int_from_text: Bool.True })
	# Err(Null) in a map field is not written, so it reads back as Err(Missing).
	from_wire : Try({ id : U64, note : Try(Str, [Missing]) }, _)
	from_wire = Cbor.parse(Cbor.encode(wire(value)))
	if (back == Ok(value) and with_text == back and from_wire == Ok({ id: value.id, note: value.note })) Fuzz.keep else crash "the round trip changed the value"
}

target = Fuzz.target_with!({
	name: "round-trip",
	generator: item,
	test!,
	show: |value| Str.inspect(value),
})
