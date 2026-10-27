app [] { pkg: "../src/main.roc" }

# Uses each public item of the package: Cbor.encode, Cbor.parse, Cbor.parse_camel,
# Cbor.parse_with, Cbor.Options, Cbor.path_at, Cbor.Step, Cbor.Bytes, Cbor.Parseable and Cbor.Encodable. CI runs it on the source and on the bundle.
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

	extra : Try(U64, _)
	extra = Cbor.parse([0x01, 0x02])
	echo!("extra byte: ${Str.inspect(extra)}\n")
	Ok({})
}
