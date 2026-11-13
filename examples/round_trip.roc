app [] { pkg: "../src/main.roc" }

# Uses each public item of the package: Cbor.encode, Cbor.encode_try, Cbor.encode_with, Cbor.WriteOptions,
# Cbor.parse, Cbor.parse_with, Cbor.Options, Cbor.Leniency, Cbor.sql_rows, Cbor.path_at, Cbor.Step, Cbor.U8Array,
# Cbor.Parseable and Cbor.Encodable. CI runs it on the source and on the bundle.
# Also the building blocks for a type over a CBOR tag: Cbor.parse_cbor_tag, Cbor.encode_tagged, Cbor.Writer,
# Cbor.parse_item, Cbor.peek, Cbor.Kind, Cbor.Value, the option ignore_tags and the lenient read DecFromText.
# Also Cbor.ValueMap, Cbor.IntValue, Cbor.parse_sequence, Cbor.parse_prefix and Cbor.Raw.
# Also reads a SQL row (Cbor.sql_rows): a NULL column into an optional field, a 0 or 1 column into a Bool.
# Also reads tag unions of a peer: an internal tag (Cbor.Unions), and tag names in upper snake case
# (Cbor.parse_union, Cbor.UnionOptions).

import pkg.Cbor

Pkg : {
	name : Str,
	size : U64,
	tags : List(Str),
	digest : List(U8),
	note ?: Str,
	license : Try(Str, [Missing]),
}

## A UUID (RFC 9562): the IANA tag 37 and a byte string. A type of the app reads and writes the tag.
Uuid := List(U8).{
	is_eq : _

	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Uuid, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		if tag.value != 37 {
			return Err(Cbor.invalid_value(encoding, state))
		}
		bytes : { value : List(U8), rest : Cbor.Reader }
		bytes = Cbor.parse_item(encoding, tag.rest)?
		Ok({ value: Uuid.(bytes.value), rest: bytes.rest })
	}

	encoder_for : Cbor -> (Uuid, Cbor.Writer -> Try(Cbor.Writer, []))
	encoder_for = |_| |Uuid.(bytes), w| Cbor.encode_tagged(37, bytes, w)
}

## A key that is a number or text: Cbor.peek picks the reader.
Key := [Number(U64), Name(Str)].{
	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Key, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state|
		match Cbor.peek(encoding, state)? {
			Int => Cbor.parse_u64(encoding, state).map_ok(|n| { value: Key.Number(n.value), rest: n.rest })
			Text => Cbor.parse_str(encoding, state).map_ok(|t| { value: Key.Name(t.value), rest: t.rest })
			_ => Err(Cbor.invalid_value(encoding, state))
		}
}

## An action of a peer in upper snake case, "NOT_FOUND": Cbor.parse_union gives the type its own tag name case.
Action := [Create, NotFound].{
	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Action, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		options : Cbor.UnionOptions
		options = { tags: Upper }
		parsed = Cbor.parse_union(encoding, options, state)?
		Ok({ value: Action.(parsed.value), rest: parsed.rest })
	}
}

## A function of your own that wraps `Cbor.encode` repeats its constraint.
to_cbor : a -> List(U8) where [a.Cbor.Encodable([])]
to_cbor = |value| Cbor.encode(value)

## A function of your own that wraps `Cbor.parse` repeats its constraint.
from_cbor : List(U8) -> Try(a, Cbor.Error) where [a.Cbor.Parseable(Cbor.Error)]
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
		digest: [0xde, 0xad],
		license: Ok("UPL-1.0"),
	}
	bytes = to_cbor(pkg)
	echo!("encode: ${hex(bytes)}\n")

	parsed : Try(Pkg, _)
	parsed = from_cbor(bytes)
	match parsed {
		Ok(p) => echo!("parse: same=${Str.inspect(p == pkg)} size=${p.size.to_str()} digest=${hex(p.digest)}\n")
		Err(InvalidCbor(pos)) => echo!("parse: invalid CBOR at ${pos.to_str()}\n")
		Err(MissingRequiredField(name)) => echo!("parse: missing field ${name}\n")
	}

	# A JS object with camelCase keys: { userId: 7, displayName: "Ann" }
	js = [0xa2, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x07, 0x6b, 0x64, 0x69, 0x73, 0x70, 0x6c, 0x61, 0x79, 0x4e, 0x61, 0x6d, 0x65, 0x63, 0x41, 0x6e, 0x6e]
	user : Try({ user_id : U64, display_name : Str }, _)
	user = Cbor.parse_with(js, { fields: Camel })
	echo!("fields Camel: ${Str.inspect(user)}\n")

	# The same keys on write: encode_with and the option fields. encode_try gives Err(CountMismatch)
	# when an encoder_for of your own writes a wrong count of items.
	write_options : Cbor.WriteOptions
	write_options = { fields: Camel }
	camel = Cbor.encode_with({ user_id: 7.U64 + args.len(), display_name: "Ann" }, write_options)
	checked = Cbor.encode_try({ user_id: 7.U64 })
	echo!("encode_with: ${Str.inspect(camel.map_ok(hex))} encode_try: ${Str.inspect(checked.map_ok(hex))}\n")

	missing : Try({ user_id : U64, email : Str }, _)
	missing = Cbor.parse_with(js, { fields: Camel })
	echo!("missing field: ${Str.inspect(missing)}\n")

	# A peer that sends a 64-bit id as text, as SQL CAST(id AS TEXT) gives it.
	# The `args` keep the value unknown at compile time.
	id_text : Str
	id_text = Str.concat("9007199254740993", Str.repeat("0", args.len()))
	text_row : { name : Str, id : Str }
	text_row = { name: "a", id: id_text }
	text_rows = Cbor.encode([text_row])
	options : Cbor.Options
	options = { allow: [IntFromText] }
	rows : Try(List({ name : Str, id : I64 }), _)
	rows = Cbor.parse_with(text_rows, options)
	echo!("parse_with: ${Str.inspect(rows)}\n")

	# Without IntFromText, the text is an error. path_at names the field of the error.
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

	# A D1 BLOB arrives as an array of numbers: Cbor.U8Array reads it (a List(U8) with BytesFromArray). A Dec with no fraction is an integer.
	blob : Try(Cbor.U8Array, _)
	blob = Cbor.parse([0x82, 0x01, 0x18, 0xff])
	echo!("blob: ${Str.inspect(blob)} params: ${hex(to_cbor([1, 2]))} ${hex(to_cbor([1.5]))}\n")

	# A SQL row: a NULL column is no key, a boolean column is 0 or 1.
	# {"name": "a", "note": null, "active": 1}. The `args` keep the value unknown at compile time.
	sql_row = [0xa3, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61, 0x64, 0x6e, 0x6f, 0x74, 0x65, 0xf6, 0x66, 0x61, 0x63, 0x74, 0x69, 0x76, 0x65, 0x01].concat(List.repeat(0x00, args.len()))
	row : Try({ name : Str, note ?: Str, active : Bool }, _)
	row = Cbor.parse_with(sql_row, { allow: Cbor.sql_rows })
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

	# A peer with tags of its own: tag 6 before null is a null, tag 10 before text is a decimal.
	# {"price": 10("4E+1"), "note": 6(null)}. The `args` keep the value unknown at compile time.
	peer_row = [0xa2, 0x65, 0x70, 0x72, 0x69, 0x63, 0x65, 0xca, 0x64, 0x34, 0x45, 0x2b, 0x31, 0x64, 0x6e, 0x6f, 0x74, 0x65, 0xc6, 0xf6].concat(List.repeat(0x00, args.len()))
	priced : Try({ price : Dec, note : Try(Str, [Null]) }, _)
	priced = Cbor.parse_with(peer_row, { ignore_tags: [6, 10], allow: [DecFromText] })
	match priced {
		Ok(p) => echo!("peer row: price=${p.price.to_str()} note=${Str.inspect(p.note)}\n")
		Err(e) => echo!("peer row: ${Str.inspect(e)}\n")
	}

	# A peer with an internal tag: {"action": "NOT_FOUND", "pay": {"kind": "Check", "value": 7}}.
	# A Cbor.ValueMap has no duplicate key: `insert` sets a key, `from_list` gives Err(DuplicateKey(key)).
	payment = Cbor.ValueMap.empty().insert(Text("kind"), Text("Check")).insert(Text("value"), Int(Cbor.IntValue.from_u64(7 + args.len())))
	notice_bytes = Cbor.encode(Cbor.Value.Map(Cbor.ValueMap.empty().insert(Text("action"), Text("NOT_FOUND")).insert(Text("pay"), Map(payment))))
	layout : Cbor.Unions
	layout = Internal({ tag: "kind", content: "value" })
	notice : Try({ action : Action, pay : [Cash, Check(U64)] }, _)
	notice = Cbor.parse_with(notice_bytes, { unions: layout })
	match notice {
		Ok({ action: Action.NotFound, pay }) => echo!("unions: action=NotFound pay=${Str.inspect(pay)}\n")
		Ok(_) => echo!("unions: other action\n")
		Err(e) => echo!("unions: ${Str.inspect(e)}\n")
	}

	# A CBOR sequence (RFC 8742), one item at the start of the bytes, and an item kept as its exact bytes.
	seq : Try(List(Str), _)
	seq = Cbor.parse_sequence([0x61, 0x61, 0x61, 0x62].concat(List.repeat(0x60, args.len())))
	prefix : Try({ value : U64, rest : List(U8) }, _)
	prefix = Cbor.parse_prefix([0x18, 0x2a, 0xff, 0xfe])
	signed : Try({ payload : Cbor.Raw, sig : List(U8) }, _)
	signed = Cbor.parse([0xa2, 0x67, 0x70, 0x61, 0x79, 0x6c, 0x6f, 0x61, 0x64, 0x82, 0x01, 0x02, 0x63, 0x73, 0x69, 0x67, 0x41, 0x09])
	echo!("sequence: ${Str.inspect(seq)} prefix: ${Str.inspect(prefix)} raw payload: ${Str.inspect(signed.map_ok(|r| r.payload.to_bytes()))}\n")

	extra : Try(U64, _)
	extra = Cbor.parse([0x01, 0x02])
	echo!("extra byte: ${Str.inspect(extra)}\n")
	Ok({})
}
