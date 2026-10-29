app [] { pkg: "../src/main.roc" }

# Uses each public item of the package: Cbor.encode, Cbor.parse, Cbor.parse_camel,
# Cbor.parse_with, Cbor.Options, Cbor.path_at, Cbor.Step, Cbor.Bytes, Cbor.Parseable and Cbor.Encodable. CI runs it on the source and on the bundle.
# Also the building blocks for a type over a CBOR tag: Cbor.parse_cbor_tag, Cbor.encode_cbor_tag,
# Cbor.parse_item, Cbor.encode_item, Cbor.peek, Cbor.Kind, Cbor.Value, and the options ignore_tags and dec_from_text.
# Also reads a SQL row: a NULL column into an optional field, a 0 or 1 column into a Bool.

import pkg.Cbor

Pkg : {
	name : Str,
	size : U64,
	tags : List(Str),
	digest : Cbor.Bytes,
	note ?: Str,
	license : Try(Str, [Missing]),
}

## A UUID (RFC 9562): the IANA tag 37 and a byte string. A type of the app reads and writes the tag.
Uuid := List(U8).{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Uuid, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		if tag.value != 37 {
			return Err(Cbor.invalid_value(encoding, state))
		}
		bytes : { value : Cbor.Bytes, rest : Cbor.State }
		bytes = Cbor.parse_item(encoding, tag.rest)?
		Ok({ value: Uuid.(bytes.value.to_list()), rest: bytes.rest })
	}

	encoder_for : Cbor -> (Uuid, List(U8) -> Try(List(U8), []))
	encoder_for = |_| |Uuid.(bytes), out| {
		tagged = Cbor.encode_cbor_tag(37, out)?
		Cbor.encode_item(Cbor.Bytes.(bytes), tagged)
	}
}

## A key that is a number or text: Cbor.peek picks the reader.
Key := [Number(U64), Name(Str)].{
	parser_for : Cbor -> (Cbor.State -> Try({ value : Key, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state|
		match Cbor.peek(encoding, state)? {
			Int => Cbor.parse_u64(encoding, state).map_ok(|n| { value: Key.Number(n.value), rest: n.rest })
			Text => Cbor.parse_str(encoding, state).map_ok(|t| { value: Key.Name(t.value), rest: t.rest })
			_ => Err(Cbor.invalid_value(encoding, state))
		}
}

## A function of your own that wraps `Cbor.encode` repeats its constraint.
to_cbor : a -> List(U8) where [a.Cbor.Encodable([])]
to_cbor = |value| Cbor.encode(value)

## A function of your own that wraps `Cbor.parse` repeats its constraint.
from_cbor : List(U8) -> Try(a, [InvalidCbor(U64), ..errs]) where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]
from_cbor = |bytes| Cbor.parse(bytes)

hex : List(U8) -> Str
hex = |bytes|
	bytes.fold(
		"",
		|acc, b| {
			digit = |n| if (n < 10) n + 48 else n + 87
			acc.concat(Str.from_utf8([digit(b // 16), digit(b % 16)]) ?? "??")
		},
	)

main! = |args| {
	pkg : Pkg
	pkg = {
		name: "roc-cbor",
		# 2^53 + 1: above the safe integers of JS. The `args` keep the value unknown at compile time.
		size: 9_007_199_254_740_993 + args.len(),
		tags: ["cbor", "codec"],
		digest: Cbor.Bytes.([0xde, 0xad]),
		license: Ok("UPL-1.0"),
	}
	bytes = to_cbor(pkg)
	echo!("encode: ${hex(bytes)}\n")

	parsed : Try(Pkg, _)
	parsed = from_cbor(bytes)
	match parsed {
		Ok(p) => echo!("parse: same=${Str.inspect(p == pkg)} size=${p.size.to_str()} digest=${hex(p.digest.to_list())}\n")
		Err(InvalidCbor(pos)) => echo!("parse: invalid CBOR at ${pos.to_str()}\n")
		Err(MissingRequiredField(name)) => echo!("parse: missing field ${name}\n")
	}

	# A JS object with camelCase keys: { userId: 7, displayName: "Ann" }
	js = [0xa2, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x07, 0x6b, 0x64, 0x69, 0x73, 0x70, 0x6c, 0x61, 0x79, 0x4e, 0x61, 0x6d, 0x65, 0x63, 0x41, 0x6e, 0x6e]
	user : Try({ user_id : U64, display_name : Str }, _)
	user = Cbor.parse_camel(js)
	echo!("parse_camel: ${Str.inspect(user)}\n")

	missing : Try({ user_id : U64, email : Str }, _)
	missing = Cbor.parse_camel(js)
	echo!("missing field: ${Str.inspect(missing)}\n")

	# A peer that sends a 64-bit id as text, as SQL CAST(id AS TEXT) gives it.
	# The `args` keep the value unknown at compile time.
	id_text : Str
	id_text = Str.concat("9007199254740993", Str.repeat("0", args.len()))
	text_row : { name : Str, id : Str }
	text_row = { name: "a", id: id_text }
	text_rows = Cbor.encode([text_row])
	options : Cbor.Options
	options = { fields: Snake, int_from_text: Bool.True }
	rows : Try(List({ name : Str, id : I64 }), _)
	rows = Cbor.parse_with(text_rows, options)
	echo!("parse_with: ${Str.inspect(rows)}\n")

	# Without int_from_text, the text is an error. path_at names the field of the error.
	plain : Try(List({ name : Str, id : I64 }), _)
	plain = Cbor.parse(text_rows)
	match plain {
		Err(InvalidCbor(pos)) => {
			path : Try(List(Cbor.Step), [NotFound])
			path = Cbor.path_at(text_rows, pos)
			echo!("path_at: error at ${pos.to_str()}, path ${Str.inspect(path)}\n")
		}
		_ => echo!("path_at: no error\n")
	}

	# A D1 BLOB arrives as an array of numbers: Cbor.Bytes reads it. A Dec with no fraction is an integer.
	blob : Try(Cbor.Bytes, _)
	blob = Cbor.parse([0x82, 0x01, 0x18, 0xff])
	echo!("blob: ${Str.inspect(blob)} params: ${hex(to_cbor([1, 2]))} ${hex(to_cbor([1.5]))}\n")

	# A SQL row: a NULL column is no key, a boolean column is 0 or 1.
	# {"name": "a", "note": null, "active": 1}. The `args` keep the value unknown at compile time.
	sql_row = [0xa3, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61, 0x64, 0x6e, 0x6f, 0x74, 0x65, 0xf6, 0x66, 0x61, 0x63, 0x74, 0x69, 0x76, 0x65, 0x01].concat(List.repeat(0x00, args.len()))
	row : Try({ name : Str, note ?: Str, active : Bool }, _)
	row = Cbor.parse(sql_row)
	match row {
		Ok(r) => echo!("sql row: name=${r.name} note=${Str.inspect(r.?note)} active=${Str.inspect(r.active)}\n")
		Err(e) => echo!("sql row: ${Str.inspect(e)}\n")
	}

	# A type over a tag, a key of two kinds, and any item as a Cbor.Value (it keeps the tag 1).
	id = Uuid.(List.repeat(0xab, 16 + args.len()))
	tagged : Try({ id : Uuid, any : Cbor.Value }, _)
	tagged = Cbor.parse(Cbor.encode({ id, any: Cbor.Value.Tag(1, Cbor.Value.Int(0)) }))
	keys : Try(List(Key), _)
	keys = Cbor.parse([0x82, 0x07, 0x61, 0x61])
	any : Try(Cbor.Value, _)
	any = Cbor.parse([0xc1, 0x1a, 0x51, 0x4b, 0x67, 0xb0])
	echo!("tags: id=${Str.inspect(tagged.map_ok(|t| t.id == id))} keys=${Str.inspect(keys.is_ok())} any=${Str.inspect(any)}\n")

	# A peer with tags of its own: tag 6 before null is no value, tag 10 before text is a decimal.
	# {"price": 10("4E+1"), "note": 6(null)}. The `args` keep the value unknown at compile time.
	peer_row = [0xa2, 0x65, 0x70, 0x72, 0x69, 0x63, 0x65, 0xca, 0x64, 0x34, 0x45, 0x2b, 0x31, 0x64, 0x6e, 0x6f, 0x74, 0x65, 0xc6, 0xf6].concat(List.repeat(0x00, args.len()))
	priced : Try({ price : Dec, note ?: Str }, _)
	priced = Cbor.parse_with(peer_row, { ignore_tags: [6, 10], dec_from_text: Bool.True })
	match priced {
		Ok(p) => echo!("peer row: price=${p.price.to_str()} note=${Str.inspect(p.?note)}\n")
		Err(e) => echo!("peer row: ${Str.inspect(e)}\n")
	}

	extra : Try(U64, _)
	extra = Cbor.parse([0x01, 0x02])
	echo!("extra byte: ${Str.inspect(extra)}\n")
	Ok({})
}
