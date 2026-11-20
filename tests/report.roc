app [] { pkg: "../src/main.roc" }

import pkg.Cbor

empty_list : List(U64)
empty_list = []

report : a, Cbor.WriteOptions -> Try({ bytes : List(U8), max_depth : U64 }, [CountMismatch, DuplicateMapKey]) where [a.Cbor.Encodable([CountMismatch, DuplicateMapKey])]
report = |value, options| Cbor.encode_item(value, Cbor.Writer.open(options).writer)?.finish_report()

# The depth is exactly the first max_depth that accepts the bytes, for both finish paths.
checks : a, U64 -> Bool where [a.Cbor.Encodable([CountMismatch, DuplicateMapKey])]
checks = |value, depth| {
	opts : List(Cbor.WriteOptions)
	opts = [{}, { key_order: Sorted }, { fields: Camel, key_order: Sorted }]
	opts.all(
		|options|
			match report(value, options) {
				Ok(r) => r.max_depth == depth and Ok(r.bytes) == Cbor.encode_with(value, options) and Cbor.Reader.new(r.bytes, { max_depth: depth }).is_ok() and (depth == 0 or Cbor.Reader.new(r.bytes, { max_depth: depth - 1 }).is_err())
				Err(_) => Bool.False
			},
	)
}

expect checks(1.U64, 0)
expect checks("text", 0)
expect checks(Cbor.Bytes.from_list([0x81, 0xc4, 0xa0]), 0)
expect checks(empty_list, 1)
expect checks({}, 1)
expect checks(1.5.Dec, 2)
expect checks((18446744073709551616.U128), 1)
expect checks(Dec.from_attos(I128.highest), 3)
expect checks({ a: [1.5.Dec], b: [Dec.from_attos(I128.highest)] }, 5)

# Empty containers count, and wide siblings reset to their parent's depth.
expect checks([empty_list, [1]], 2)
expect checks({ a: { a: 1 }, b: { b: { c: 1 } } }, 3)

nested : Cbor.Value, U64 -> Cbor.Value
nested = |leaf, count| (0.U64).until(count).fold(
	leaf,
	|v, i|
		match i % 3 {
			0 => Cbor.Value.Array([v])
			1 => Cbor.Value.Tag(6, v)
			_ => Cbor.Value.Map(Cbor.ValueMap.from_list([(Cbor.Value.Text("x"), v)]) ?? Cbor.ValueMap.empty())
		},
)

# The actual scalar encoders add decimal and bignum levels inside the outer containers.
Deep := { outer : U64, leaf : [Decimal(Dec), Big(U128), EmptyArray, EmptyMap] }.{
	encoder_for : Cbor -> (Deep, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Deep.(d), w|
		if d.outer > 0 {
			Cbor.encode_tagged(6, Deep.({ ..d, outer: d.outer - 1 }), w)
		} else {
			match d.leaf {
				Decimal(n) => Cbor.encode_dec(n, w)
				Big(n) => Cbor.encode_u128(n, w)
				EmptyArray => Cbor.encode_item(empty_list, w)
				EmptyMap => Cbor.encode_item({}, w)
			}
		}
}

expect [511.U64, 512, 513].all(
	|depth|
		checks(nested(Cbor.Value.Null, depth), depth) and
			checks(Deep.({ outer: depth - 2, leaf: Decimal(1.5) }), depth) and
				checks(Deep.({ outer: depth - 3, leaf: Decimal(Dec.from_attos(I128.highest)) }), depth) and
					checks(Deep.({ outer: depth - 1, leaf: Big(18446744073709551616) }), depth) and
						checks(Deep.({ outer: depth - 1, leaf: EmptyArray }), depth) and
							checks(Deep.({ outer: depth - 1, leaf: EmptyMap }), depth),
)

# Raw indefinite strings use a traversal stack but add no physical depth.
expect {
	raw : Try(Cbor.Raw, _)
	raw = Cbor.parse_with([0x9f, 0x5f, 0x41, 0, 0xff, 0xbf, 0x61, 'a', 0x9f, 0xff, 0xff, 0xff], { allow: [IndefiniteLength] })
	match raw {
		Ok(v) => {
			r = report(v, {})
			r.map_ok(|x| x.max_depth) == Ok(3) and r.map_ok(|x| Ok(x.bytes) == Cbor.encode_with(v, {})) == Ok(Bool.True)
		}
		Err(_) => Bool.False
	}
}

# open supplies a format value immediately, with the writer's field naming.
expect [Snake, Camel].all(
	|fields| {
		o = Cbor.Writer.open({ fields: fields })
		r = Cbor.Reader.new([0], { fields: fields }) ?? crash "reader"
		key = Cbor.rename_field(o.cbor, "user_id")
		w : Try(Cbor.Writer, [CountMismatch, DuplicateMapKey])
		w = Cbor.encode_key_str(o.cbor, key, o.writer)
		key == (if (fields == Camel) "userId" else "user_id") and
			Cbor.missing_field(o.cbor, "user_id") == Cbor.missing_field(r.cbor, "user_id") and
				w.map_ok(|v| v.finish_report().map_ok(|x| x.bytes)) == Ok(Ok(Cbor.encode(key)))
	},
)

expect Cbor.Writer.open({}).writer.finish_report() == Err(CountMismatch)
expect report({ a_1: 1.U64, a1: 2.U64 }, { fields: Camel }) == Err(DuplicateMapKey)

# Sorted duplicate keys and CountMismatch retain finish's error precedence.
Bad := [Count, Duplicate].{
	is_eq : _
	encoder_for : Cbor -> (Bad, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |v, w| Cbor.encode_dict(
		w,
		if (v == Count) 1 else 2,
		|c, add| {
			c1 = add(c, |k| Cbor.encode_str("x", k), |x| Cbor.encode_u64(1, x))?
			add(c1, |k| Cbor.encode_str("x", k), |x| Cbor.encode_u64(2, x))
		},
	)
}

expect report(Bad.Count, { key_order: Sorted }) == Err(CountMismatch)
expect report(Bad.Duplicate, { key_order: Sorted }) == Err(DuplicateMapKey)
expect report(Bad.Duplicate, {}).map_ok(|r| r.bytes) == Cbor.encode_with(Bad.Duplicate, {})
