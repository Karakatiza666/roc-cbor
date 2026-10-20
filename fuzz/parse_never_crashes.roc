app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Fuzz
import pkg.Cbor

# L1 target: Cbor.parse, Cbor.parse_camel, Cbor.parse_with and Cbor.path_at never crash, for any
# bytes and several target types.

Row : { id : U64, name : Str, tags : List(Str), cells : List(List(I64)), note : Try(Str, [Null]), extra ?: Bool }

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
	ok = in_input(row, len) and in_input(camel, len) and in_input(numbers, len) and in_input(text, len) and in_input(nullable, len) and in_input(raw, len) and in_input(small, len) and in_input(dec, len) and in_input(decs, len) and in_input(dict, len) and in_input(text_row, len) and in_input(text_ints, len)
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
