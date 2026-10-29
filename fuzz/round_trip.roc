app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Fuzz
import pkg.Cbor

# L1 target: Cbor.parse(Cbor.encode(v)) gives v back, for random values of one record type.
# Cbor.parse_with with int_from_text gives the same value.
# A record with Err(Null) in a field reads back as Err(Missing): a null value in a map is no key.
# A tag of the option ignore_tags before each value changes nothing. A Cbor.Value of each kind reads back.

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
	values : List(Cbor.Value),
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

## A Cbor.Value with no container: each kind. Int is in -2^64 to 2^64 - 1, and Simple is not 20 to 31.
leaf : Fuzz.Generator(Cbor.Value)
leaf = Fuzz.map(
	{ pick: Fuzz.u8, n: Fuzz.u64, f: Fuzz.f64, s: Fuzz.str, b: Fuzz.bytes }.Fuzz,
	|g|
		match g.pick % 9 {
			0 => Cbor.Value.Int(g.n.to_i128())
			1 => Cbor.Value.Int(-1 - g.n.to_i128())
			2 => Cbor.Value.Float(g.f)
			3 => Cbor.Value.Text(g.s)
			4 => Cbor.Value.Bytes(g.b)
			5 => Cbor.Value.Bool(g.pick > 128)
			6 => Cbor.Value.Null
			7 => Cbor.Value.Undefined
			_ => {
				n = g.n.to_u8_wrap()
				Cbor.Value.Simple(if (n >= 20 and n < 32) n + 12 else n)
			}
		},
)

## A Cbor.Value of a depth of `depth` or less: a leaf, an array, a map with any keys, or a tag.
any_value : U8 -> Fuzz.Generator(Cbor.Value)
any_value = |depth|
	if depth == 0 {
		leaf
	} else {
		Fuzz.map(
			{ pick: Fuzz.u8, one: leaf, items: Fuzz.list(any_value(depth - 1), 4), keys: Fuzz.list(leaf, 4), n: Fuzz.u64 }.Fuzz,
			|g|
				match g.pick % 4 {
					0 => g.one
					1 => Cbor.Value.Array(g.items)
					2 => Cbor.Value.Map(g.keys.map_with_index(|k, i| (k, g.items.get(i) ?? g.one)))
					_ => Cbor.Value.Tag(g.n, g.items.first() ?? g.one)
				},
		)
	}

## Puts the tag 6 before each value, not before a map key and not inside a tag.
wrap : Cbor.Value -> Cbor.Value
wrap = |v|
	match v {
		Array(items) => Cbor.Value.Tag(6, Cbor.Value.Array(items.map(wrap)))
		Map(pairs) => Cbor.Value.Tag(6, Cbor.Value.Map(pairs.map(|(k, x)| (k, wrap(x)))))
		_ => Cbor.Value.Tag(6, v)
	}

## `wrap` for each field of the item, except `values`: a Cbor.Value keeps each tag.
wrap_item : Cbor.Value -> Cbor.Value
wrap_item = |v|
	match v {
		Map(pairs) => Cbor.Value.Tag(6, Cbor.Value.Map(pairs.map(|(k, x)| if (k == Cbor.Value.Text("values")) (k, x) else (k, wrap(x)))))
		_ => wrap(v)
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
	values: Fuzz.list(any_value(3), 3),
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
	# The tag 6 before each value, with ignore_tags: [6], reads the same item.
	as_value : Try(Cbor.Value, _)
	as_value = Cbor.parse(bytes)
	tagged : Try(Item, _)
	tagged =
		match as_value {
			Ok(v) => Cbor.parse_with(Cbor.encode(wrap_item(v)), { ignore_tags: [6] })
			Err(e) => Err(e)
		}
	if (back == Ok(value) and with_text == back and from_wire == Ok({ id: value.id, note: value.note }) and tagged == back) Fuzz.keep else crash "the round trip changed the value"
}

target = Fuzz.target_with!({
	name: "round-trip",
	generator: item,
	test!,
	show: |value| Str.inspect(value),
})
