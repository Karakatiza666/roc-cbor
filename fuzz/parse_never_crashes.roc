app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Fuzz
import pkg.Cbor

# L1 target: Cbor.parse and Cbor.parse_camel never crash, for any bytes and several target types.
# The record has no optional field (`?:`): nightly-2026-10-12 crashes when it builds a parse into one.

Row : { id : U64, name : Str, tags : List(Str), cells : List(List(I64)), note : Try(Str, [Null]), extra : Try(Bool, [Missing]) }

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
	dict : Try(Dict(Str, U64), _)
	dict = Cbor.parse(bytes)
	ok = in_input(row, len) and in_input(camel, len) and in_input(numbers, len) and in_input(text, len) and in_input(nullable, len) and in_input(raw, len) and in_input(small, len) and in_input(dict, len)
	if ok Fuzz.keep else crash "error position past the end of the input"
}

target = Fuzz.target_with!({
	name: "parse-never-crashes",
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes),
})
