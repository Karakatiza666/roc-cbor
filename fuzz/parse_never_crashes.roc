app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Fuzz
import pkg.Cbor

# L1 target: Cbor.parse, Cbor.parse_camel, Cbor.parse_with and Cbor.path_at never crash, for any
# bytes and several target types. Also with the options ignore_tags and dec_from_text, and into Cbor.Value.
# Tag unions with an internal tag (the option unions), and a type with Cbor.parse_union.
# A Cbor.Value that reads writes bytes that read the same Cbor.Value.

Row : { id : U64, name : Str, tags : List(Str), cells : List(List(I64)), note : Try(Str, [Missing]), flag : Bool, extra ?: Bool }

## A union with each kind of payload: none, a record, one item, a Dict, two items, a union, a list.
Shape := [Dot, Box({ w : U32, label : Try(Str, [Missing]) }), Size(U64), Counts(Dict(Str, U64)), Span(I64, Str), Nest(Shape), Many(List(Shape)), Any(Cbor.Value)].{
	parser_for : _
}

## Tag names in upper snake case, an internal tag `op`.
Act := [Create, NotFound, SetMode(Shape), Move({ to : Str })].{
	parser_for : Cbor -> (Cbor.State -> Try({ value : Act, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { unions: Internal({ tag: "op", content: "value" }), tags: Upper }, state)?
		Ok({ value: Act.(parsed.value), rest: parsed.rest })
	}
}

## The error position is in the input, or at its end.
in_input : Try(a, [InvalidCbor(U64), MissingRequiredField(Str)]), U64 -> Bool
in_input = |r, len|
	match r {
		Err(InvalidCbor(pos)) => pos <= len
		_ => Bool.True
	}

## Any bytes give a value or an error, never a crash, for each target type.
test! : List(U8) => Fuzz.Outcome
test! = |bytes| {
	len = bytes.len()
	row : Try(Row, _)
	row = Cbor.parse(bytes)
	camel : Try(Row, _)
	camel = Cbor.parse_camel(bytes)
	numbers : Try(List(U64), _)
	numbers = Cbor.parse(bytes)
	text : Try(Str, _)
	text = Cbor.parse(bytes)
	nullable : Try(Try(U64, [Null]), _)
	nullable = Cbor.parse(bytes)
	cells : Try(List((Bool, Try(I64, [Null]))), _)
	cells = Cbor.parse(bytes)
	raw : Try(Cbor.Bytes, _)
	raw = Cbor.parse(bytes)
	small : Try(List(U8), _)
	small = Cbor.parse(bytes)
	dec : Try(Dec, _)
	dec = Cbor.parse(bytes)
	decs : Try(List(Dec), _)
	decs = Cbor.parse(bytes)
	dict : Try(Dict(Str, U64), _)
	dict = Cbor.parse(bytes)
	text_row : Try(Row, _)
	text_row = Cbor.parse_with(bytes, { fields: Camel, int_from_text: Bool.True })
	text_ints : Try(List(I8), _)
	text_ints = Cbor.parse_with(bytes, { fields: Snake, int_from_text: Bool.True })
	tag_opts : Cbor.Options
	tag_opts = { ignore_tags: [6, 10, 4], dec_from_text: Bool.True }
	tag_row : Try(Row, _)
	tag_row = Cbor.parse_with(bytes, tag_opts)
	tag_decs : Try(List(Try(Dec, [Null])), _)
	tag_decs = Cbor.parse_with(bytes, tag_opts)
	text_dec : Try(Dec, _)
	text_dec = Cbor.parse_with(bytes, { dec_from_text: Bool.True })
	internal : Cbor.Options
	internal = { unions: Internal({ tag: "kind", content: "value" }), ignore_tags: [6] }
	shapes : Try(List(Shape), _)
	shapes = Cbor.parse_with(bytes, internal)
	shape_row : Try({ id : U64, shape : Shape, act : Act, acts : List(Act) }, _)
	shape_row = Cbor.parse_with(bytes, internal)
	acts : Try(List(Act), _)
	acts = Cbor.parse(bytes)
	any : Try(Cbor.Value, _)
	any = Cbor.parse(bytes)
	anys : Try({ id : U64, v : Cbor.Value, w : List(Cbor.Value) }, _)
	anys = Cbor.parse_with(bytes, tag_opts)
	same =
		match any {
			Ok(v) => {
				again : Try(Cbor.Value, _)
				again = Cbor.parse(Cbor.encode(v))
				again == Ok(v)
			}
			Err(_) => Bool.True
		}
	if !same {
		crash "a Cbor.Value does not read back"
	}
	ok = in_input(shapes, len) and in_input(shape_row, len) and in_input(acts, len) and in_input(tag_row, len) and in_input(tag_decs, len) and in_input(text_dec, len) and in_input(any, len) and in_input(anys, len) and in_input(row, len) and in_input(camel, len) and in_input(numbers, len) and in_input(text, len) and in_input(nullable, len) and in_input(cells, len) and in_input(raw, len) and in_input(small, len) and in_input(dec, len) and in_input(decs, len) and in_input(dict, len) and in_input(text_row, len) and in_input(text_ints, len)
	if !ok {
		crash "error position past the end of the input"
	}
	# path_at at the error position of each parse, and at the start, the middle and the end.
	positions = [row, camel, text_row].keep_oks(
		|r| match r {
			Err(InvalidCbor(pos)) => Ok(pos)
			_ => Err(NoPosition)
		},
	).concat([0, len // 2, len])
	paths = positions.map(|pos| Cbor.path_at(bytes, pos))
	# The root item starts at 0, so its path is [] when the input is not empty.
	if len > 0 and paths.get(paths.len() - 3) != Ok(Ok([])) {
		crash "path_at(bytes, 0) is not []"
	}
	Fuzz.keep
}

target = Fuzz.target_with!({
	name: "parse-never-crashes",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes),
})
