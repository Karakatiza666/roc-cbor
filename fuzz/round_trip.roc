app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.6.1/GDoZFRDnzMRiVk9nE8wdWn52btGsM1GhcY9VDKqy9f1Y.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Arbitrary
import fuzz.Fuzz
import pkg.Cbor

# L1 target: Cbor.parse(Cbor.encode(v)) gives v back, for random values of one record type, with the strict reader.
# The lenient reads (Cbor.sql_rows, IntFromText), duplicate_keys: First and Last, unknown_fields: Reject and a
# max_items of the item count give the same value: the writer writes no data that they read in another way.
# A record with Err(Null) in a field writes null, which reads back as Err(Null), and as Err(Missing) with Cbor.sql_rows.
# A tag of the option ignore_tags before each value changes nothing. A Cbor.Value of each kind reads back.
# U128 and I128 (bignums above 64 bits), and a Dict with integer keys. The bytes as base64 text read back with
# BytesFromBase64, and the U128 and I128 as decimal text with IntFromText.
# Each Cbor.Value made through the public constructors reads back as an equal value (encode cannot fail for it),
# is_eq agrees with the bytes, and equal values have the same hash.
# key_order: Sorted: the bytes read back as the same value (also with the read option key_order: Sorted), and the
# encode (Sorted) of their Cbor.Value gives the same bytes. A Cbor.Value map keeps the order of its entries (and is
# equal only to a map with the same order), so it reads back with its entries in the sorted order (sort_maps).

Kind : [Empty, One(U32), Two(Str, I16)]

Item : {
	id : U64,
	delta : I64,
	name : Str,
	tags : List(Str),
	data : Cbor.U8Array,
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
	wide : U128,
	signed : I128,
	lookup : Dict(U64, Str),
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

## A Cbor.Value with no container: each kind, through the checked constructors. An I128 out of -2^64 to 2^64 - 1
## and a simple value of 20 to 31 are an error, and the generator checks it.
leaf : Fuzz.Generator(Cbor.Value)
leaf = Fuzz.map(
	{ pick: Fuzz.u8, n: Fuzz.u64, s: Fuzz.str }.Fuzz,
	|g|
		match g.pick % 10 {
			0 => Cbor.Value.Int(Cbor.IntValue.from_u64(g.n))
			1 => Cbor.Value.Int(Cbor.IntValue.from_i64(g.n.to_i64_wrap()))
			2 => {
				# Near the ends of the range, and out of it.
				hi = g.pick // 16
				i = g.n.to_i128() * (if (hi % 2 == 0) 1 else -1) - (hi // 2 % 4).to_i128()
				in_range = i >= -18446744073709551616 and i <= 18446744073709551615
				match Cbor.IntValue.from_i128(i) {
					Ok(n) if in_range and n.to_i128() == i => Cbor.Value.Int(n)
					Err(OutOfRange) if !in_range => Cbor.Value.Null
					_ => crash "IntValue.from_i128 does not check the range"
				}
			}
			3 => Cbor.Value.Float(F64.from_bits(g.n))
			4 => Cbor.Value.Text(g.s)
			5 => Cbor.Value.Bytes(g.s.to_utf8().append(g.n.to_u8_wrap()))
			6 => Cbor.Value.Bool(g.pick > 128)
			7 => if (g.pick > 128) Cbor.Value.Null else Cbor.Value.Undefined
			_ => {
				n = g.n.to_u8_wrap()
				match Cbor.SimpleValue.from_u8(n) {
					Ok(simple) if n < 20 or n >= 32 => Cbor.Value.Simple(simple)
					Err(InvalidSimple) if n >= 20 and n < 32 => Cbor.Value.Undefined
					_ => crash "SimpleValue.from_u8 does not check 20 to 31"
				}
			}
		},
)

## A Cbor.Value of a depth of `depth` or less: a leaf, an array, a map with any keys, or a tag.
## A map comes from `ValueMap.from_list` of keys that can repeat. On `DuplicateKey(k)`, `k` must be there two times,
## and the map is made with `insert` (the last value of each key). Few bytes of input make a map.
any_value : U8 -> Fuzz.Generator(Cbor.Value)
any_value = |depth|
	if depth == 0 {
		leaf
	} else {
		Fuzz.map(
			{ pick: Fuzz.u8, keys: Fuzz.list(leaf, 3), items: Fuzz.list(any_value(depth - 1), 3) }.Fuzz,
			|g| {
				one = g.keys.first() ?? Cbor.Value.Null
				match g.pick % 6 {
					0 => one
					1 => Cbor.Value.Array(g.items)
					2 => Cbor.Value.Tag((g.pick // 6).to_u64() * 0x0101010101010101, g.items.first() ?? one)
					pick => {
						# Keys from the leaves, or from the items (arrays and maps as keys), and a repeat of the first key.
						base = if (pick == 4) g.items else g.keys
						keys = base.concat(if (pick == 5) base.take_first(1) else [])
						pairs = keys.map_with_index(|k, i| (k, g.items.get(i) ?? one))
						match Cbor.ValueMap.from_list(pairs) {
							Ok(m) => Cbor.Value.Map(m)
							Err(DuplicateKey(k)) =>
								if keys.count_if(|other| other == k) >= 2 {
									Cbor.Value.Map(pairs.fold(Cbor.ValueMap.empty(), |acc, (key, x)| acc.insert(key, x)))
								} else {
									crash "ValueMap.from_list gives a key that is there one time"
								}
						}
					}
				}
			},
		)
	}

## The same map with `f` on each value.
map_values : Cbor.ValueMap, (Cbor.Value -> Cbor.Value) -> Cbor.Value
map_values = |m, f| Cbor.Value.Map(m.to_list().fold(Cbor.ValueMap.empty(), |acc, (k, x)| acc.insert(k, f(x))))

## Puts the tag 6 before each value, not before a map key and not inside a tag.
wrap : Cbor.Value -> Cbor.Value
wrap = |v|
	match v {
		Array(items) => Cbor.Value.Tag(6, Cbor.Value.Array(items.map(wrap)))
		Map(m) => Cbor.Value.Tag(6, map_values(m, wrap))
		_ => Cbor.Value.Tag(6, v)
	}

## `wrap` for each field of the item, except `values`: a Cbor.Value keeps each tag.
wrap_item : Cbor.Value -> Cbor.Value
wrap_item = |v|
	match v {
		Map(m) => Cbor.Value.Tag(6, Cbor.Value.Map(m.to_list().fold(Cbor.ValueMap.empty(), |acc, (k, x)| acc.insert(k, if (k == Cbor.Value.Text("values")) x else wrap(x)))))
		_ => wrap(v)
	}

## The Cbor.Value property: each value that app code can make writes bytes that the strict reader reads back
## as an equal value. `is_eq` is the same as equal bytes, and equal values have the same hash (a Set of both has 1 item).
value_reads_back : Cbor.Value, Cbor.Value -> Bool
value_reads_back = |v, other| {
	bytes = Cbor.encode(v)
	back : Try(Cbor.Value, _)
	back = Cbor.parse(bytes)
	same_hash =
		match back {
			Ok(b) => Set.from_list([v, b]).len() == 1
			Err(_) => Bool.False
		}
	back == Ok(v) and same_hash and (v == other) == (bytes == Cbor.encode(other))
}

## A map key that is an array or a map: two such keys can be different values (the entries in another order)
## with the same sorted bytes. Only then can `key_order: Sorted` give `DuplicateMapKey` for a value of the generator.
has_container_key : Cbor.Value -> Bool
has_container_key = |v|
	match v {
		Array(items) => items.any(has_container_key)
		Map(m) =>
			m.to_list().any(
				|(k, x)|
					match k {
						Array(_) | Map(_) => Bool.True
						_ => has_container_key(k) or has_container_key(x)
					},
			)
		Tag(_, inner) => has_container_key(inner)
		_ => Bool.False
	}

## Each map in `v` has its keys in strictly increasing bytewise order of their Sorted bytes (RFC 8949 4.2.1).
keys_sorted : Cbor.Value -> Bool
keys_sorted = |v|
	match v {
		Array(items) => items.all(keys_sorted)
		Map(m) => {
			pairs = m.to_list()
			keys = pairs.map(|(k, _)| Cbor.encode_with(k, { key_order: Sorted }) ?? [])
			increasing = keys.map_with_index(|k, i| i == 0 or before(keys.get(i - 1) ?? [], k)).all(|ok| ok)
			increasing and pairs.all(|(k, x)| keys_sorted(k) and keys_sorted(x))
		}
		Tag(_, inner) => keys_sorted(inner)
		_ => Bool.True
	}

## `x` comes before `y` in bytewise order: the first byte that is not the same, or `x` is a prefix of `y`.
before : List(U8), List(U8) -> Bool
before = |x, y|
	match (x, y) {
		([], [_, ..]) => Bool.True
		([a, .. as xs], [b, .. as ys]) => if (a == b) before(xs, ys) else a < b
		_ => Bool.False
	}

## `v` with the entries of each map (also of a map in a key) in the order of `key_order: Sorted`: the bytewise order
## of the Sorted bytes of their keys (RFC 8949 4.2.1). The sorted bytes of `v` read back as this value: a ValueMap
## keeps the order of its entries, and its `is_eq` compares them in that order.
sort_maps : Cbor.Value -> Cbor.Value
sort_maps = |v|
	match v {
		Array(items) => Cbor.Value.Array(items.map(sort_maps))
		Map(m) => {
			keyed = m.to_list().map(
				|(k, x)| {
					key = sort_maps(k)
					{ bytes: Cbor.encode_with(key, { key_order: Sorted }) ?? [], key, x: sort_maps(x) }
				},
			)
			sorted = keyed.sort_with(|a, b| if (before(a.bytes, b.bytes)) Before else if (before(b.bytes, a.bytes)) After else Same)
			# Two keys with the same sorted bytes: the Sorted encode is DuplicateMapKey, and this value is not used.
			Cbor.Value.Map(Cbor.ValueMap.from_list(sorted.map(|e| (e.key, e.x))) ?? m)
		}
		Tag(n, inner) => Cbor.Value.Tag(n, sort_maps(inner))
		_ => v
	}

## The deterministic property for `bytes` (the Given encode) and `sorted` (the Sorted encode of the same value):
## the sorted bytes read back as a Cbor.Value whose Sorted encode is the same bytes, also with the read option
## `key_order: Sorted`. `DuplicateMapKey` only with a container key.
sorted_ok : List(U8), Try(List(U8), [CountMismatch, DuplicateMapKey]) -> Bool
sorted_ok = |bytes, sorted|
	match sorted {
		Ok(b) => {
			v : Try(Cbor.Value, _)
			v = Cbor.parse(b)
			match v {
				Ok(x) => {
					strict_order : Try(Cbor.Value, _)
					strict_order = Cbor.parse_with(b, { key_order: Sorted })
					Cbor.encode_with(x, { key_order: Sorted }) == Ok(b) and b.len() == bytes.len() and keys_sorted(x) and strict_order == Ok(x)
				}
				Err(_) => Bool.False
			}
		}
		Err(DuplicateMapKey) => {
			v : Try(Cbor.Value, _)
			v = Cbor.parse(bytes)
			v.map_ok(has_container_key) == Ok(Bool.True)
		}
		Err(CountMismatch) => Bool.False
	}

item : Fuzz.Generator(Item)
item = {
	id: Fuzz.u64,
	delta: Fuzz.map(Fuzz.u64, |n| n.to_i64_wrap()),
	name: Fuzz.str,
	tags: Fuzz.list(Fuzz.str, 4),
	data: Fuzz.map(Fuzz.bytes, |b| Cbor.U8Array.(b)),
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
	wide: Fuzz.map({ hi: Fuzz.u64, lo: Fuzz.u64, z: Fuzz.u8 }.Fuzz, |g| g.hi.to_u128().shl_wrap(64).bitwise_or(g.lo.to_u128()).shr_zf_wrap(g.z % 128)),
	signed: Fuzz.map({ hi: Fuzz.u64, lo: Fuzz.u64, z: Fuzz.u8 }.Fuzz, |g| g.hi.to_u128().shl_wrap(64).bitwise_or(g.lo.to_u128()).to_i128_wrap().shr_wrap(g.z % 128)),
	lookup: Fuzz.map(Fuzz.list(Fuzz.map({ k: Fuzz.u64, v: Fuzz.str }.Fuzz, |p| (p.k % 1000, p.v)), 6), |pairs| Dict.from_list(pairs)),
}.Fuzz

test! : { any : List(Cbor.Value), item : Item } => Fuzz.Outcome
test! = |g| {
	value = g.item
	# The Cbor.Value property, for values of their own (first, so that short inputs make them) and in the item.
	any_ok = g.any.map_with_index(|v, i| value_reads_back(v, g.any.get(i + 1) ?? v)).all(|ok| ok)
	if !any_ok {
		crash "a Cbor.Value does not read back, or is_eq or to_hash does not agree with the bytes"
	}
	if !g.any.all(|v| sorted_ok(Cbor.encode(v), Cbor.encode_with(v, { key_order: Sorted }))) {
		crash "key_order: Sorted: a Cbor.Value does not give the same bytes again"
	}
	bytes = Cbor.encode(value)
	# key_order: Sorted reads back as the same item with the read option key_order: Sorted, and is stable. The maps of
	# a Cbor.Value read back with their entries in the sorted order.
	sorted_bytes = Cbor.encode_with(value, { key_order: Sorted })
	sorted_back : Try(Item, _)
	sorted_back = sorted_bytes.map_ok(|b| Cbor.parse_with(b, { key_order: Sorted })) ?? Ok(value)
	sorted_value = if (sorted_bytes.is_ok()) { ..value, values: value.values.map(sort_maps) } else value
	if !sorted_ok(bytes, sorted_bytes) or sorted_back != Ok(sorted_value) {
		crash "key_order: Sorted: the item does not read back, or the bytes change in a second encode"
	}
	back : Try(Item, _)
	back = Cbor.parse(bytes)
	# The lenient reads, the duplicate key rules, unknown_fields: Reject and an exact max_items change nothing.
	items = count_items(bytes)
	others : List(Cbor.Options)
	others = [
		{ allow: [IntFromText, DecFromText, PaddedNumbers, BytesFromBase64] },
		{ allow: Cbor.sql_rows },
		{ duplicate_keys: First, unknown_fields: Reject },
		{ duplicate_keys: Last, max_items: items },
	]
	same = others.all(
		|options| {
			r : Try(Item, _)
			r = Cbor.parse_with(bytes, options)
			r == back
		},
	)
	# One item less than the count is an error.
	over : Try(Item, _)
	over = Cbor.parse_with(bytes, { max_items: items - 1 })
	# Err(Null) in a map field writes null, which reads back as Err(Null), and as Err(Missing) with sql_rows.
	wire_bytes = Cbor.encode(wire(value))
	from_wire : Try(Wire, _)
	from_wire = Cbor.parse(wire_bytes)
	from_rows : Try({ id : U64, note : Try(Str, [Missing]) }, _)
	from_rows = Cbor.parse_with(wire_bytes, { allow: Cbor.sql_rows })
	# The tag 6 before each value, with ignore_tags: [6], reads the same item.
	as_value : Try(Cbor.Value, _)
	as_value = Cbor.parse(bytes)
	tagged : Try(Item, _)
	tagged =
		match as_value {
			Ok(v) => Cbor.parse_with(Cbor.encode(wrap_item(v)), { ignore_tags: [6] })
			Err(e) => Err(e)
		}
	# Each Cbor.Value reads back, and is_eq agrees with the bytes for each pair.
	values_ok = value.values.map_with_index(|v, i| value_reads_back(v, value.values.get(i + 1) ?? v)).all(|ok| ok)
	if !values_ok {
		crash "a Cbor.Value does not read back, or is_eq or to_hash does not agree with the bytes"
	}
	# Bytes from the item as base64 text (each length mod 3), and the U128 and I128 as decimal text, read back with the leniencies.
	raw = value.small.concat(value.name.to_utf8()).concat([0, 8, 16, 24, 32, 40, 48, 56].map(|k| value.id.shr_zf_wrap(k).to_u8_wrap())).drop_first(value.delta.to_u64_wrap() % 3)
	as_text = Cbor.encode({ small: to_base64(raw), blob: to_base64(raw), wide: value.wide.to_str(), signed: value.signed.to_str() })
	from_text : Try({ small : List(U8), blob : Cbor.Bytes, wide : U128, signed : I128 }, _)
	from_text = Cbor.parse_with(as_text, { allow: [BytesFromBase64, IntFromText] })
	if from_text != Ok({ small: raw, blob: Cbor.Bytes.from_list(raw), wide: value.wide, signed: value.signed }) {
		crash "base64 text or decimal text did not read back"
	}
	if (back == Ok(value) and same and over.is_err() and from_wire == Ok(wire(value)) and from_rows == Ok({ id: value.id, note: value.note }) and tagged == back) Fuzz.keep else crash "the round trip changed the value"
}

b64_alphabet : List(U8)
b64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_utf8()

## The base64 text of `bytes` (RFC 4648 4), with padding.
to_base64 : List(U8) -> Str
to_base64 = |bytes| {
	var $out = []
	for group in bytes.chunks_of(3) {
		x = group.get(0) ?? 0
		y = group.get(1) ?? 0
		z = group.get(2) ?? 0
		v = x.to_u32().shl_wrap(16).bitwise_or(y.to_u32().shl_wrap(8)).bitwise_or(z.to_u32())
		char = |i| b64_alphabet.get(v.shr_zf_wrap(18 - 6 * i).bitwise_and(63).to_u64()) ?? '?'
		$out = $out.append(char(0)).append(char(1))
		$out = $out.append(if (group.len() > 1) char(2) else '=')
		$out = $out.append(if (group.len() > 2) char(3) else '=')
	}
	Str.from_utf8($out) ?? ""
}

## The count of data items in one well-formed item with definite lengths: each head, also each key and tag.
count_items : List(U8) -> U64
count_items = |bytes| {
	var $p = 0.U64
	var $count = 0.U64
	while $p < bytes.len() {
		b = bytes.get($p) ?? 0
		info = b.bitwise_and(31)
		size = if (info < 24) 0 else if (info == 24) 1 else if (info == 25) 2 else if (info == 26) 4 else 8
		arg = (0.U64).until(size).fold(if (info < 24) info.to_u64() else 0, |n, i| n.shl_wrap(8).bitwise_or((bytes.get($p + 1 + i) ?? 0).to_u64()))
		major = b.shr_zf_wrap(5)
		# A string has its bytes after the head. Floats and simple values have only the head.
		$p = $p + 1 + size + if (major == 2 or major == 3) arg else 0
		$count = $count + 1
	}
	$count
}

## The property's value, from the input bytes: the generator reads them as its entropy, as roc-fuzz's own
## typed inputs do. The value type holds `Cbor` encoders, so it cannot have roc-fuzz's derived input format.
input_of : List(U8) -> { any : List(Cbor.Value), item : Item }
input_of = |bytes| ({ any: Fuzz.list(any_value(4), 4), item }.Fuzz)(Arbitrary.new(bytes)).value

## An example input: the bytes 0 to 255, in order.
ramp : List(U8)
ramp = {
	var $out = []
	for n in 0..<256 {
		$out = $out.append(n.to_u8_wrap())
	}
	$out
}

target = Fuzz.target_with!({
	name: "round-trip",
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || [] }),
		Fuzz.example({ name: "short", revision: "1", make: || [0x01, 0x82, 0x18, 0x2a, 0xa1, 0x61, 0x61, 0x00] }),
		Fuzz.example({ name: "ramp", revision: "1", make: || ramp }),
	],
	generator: Fuzz.raw_bytes,
	test!: |bytes| test!(input_of(bytes)),
	show: |bytes| Str.inspect(input_of(bytes)),
})
