app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.6.1/GDoZFRDnzMRiVk9nE8wdWn52btGsM1GhcY9VDKqy9f1Y.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Fuzz
import pkg.Cbor

# L1 target: Cbor.parse, Cbor.parse_with and Cbor.path_at never crash, for any bytes and several target types.
# Also with the options fields, ignore_tags, unknown_fields, max_items, duplicate_keys, the lenient reads
# (Cbor.sql_rows, IntFromText, DecFromText, PaddedNumbers), and into Cbor.Value.
# Tag unions with an internal tag (the option unions), and a type with Cbor.parse_union.
# A Cbor.Value that reads writes bytes that read the same Cbor.Value with the strict reader.
# One notion of valid: when a typed parse gives Ok, the same bytes give Ok as a Cbor.Value with the same walk options.
# path_at gives Ok when the bytes are one well-formed item (a Cbor.Value with the loosest options).
# A Dict with integer keys, U128 and I128. IndefiniteLength: a parse that gives Ok strict gives the same value with it,
# and path_at walks each item that it reads.
# Cbor.Raw reads the exact bytes of the item that Cbor.Value reads. Cbor.parse_sequence and Cbor.parse_prefix agree
# with Cbor.parse, and a sequence writes back.

Row : { id : U64, name : Str, tags : List(Str), cells : List(List(I64)), note : Try(Str, [Missing]), flag : Bool, extra ?: Bool }

## A union with each kind of payload: none, a record, one item, a Dict, two items, a union, a list.
Shape := [Dot, Box({ w : U32, label : Try(Str, [Missing]) }), Size(U64), Counts(Dict(Str, U64)), Span(I64, Str), Nest(Shape), Many(List(Shape)), Any(Cbor.Value)].{
	parser_for : _
}

## Tag names in upper snake case, an internal tag `op`.
Act := [Create, NotFound, SetMode(Shape), Move({ to : Str })].{
	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Act, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { unions: Internal({ tag: "op", content: "value" }), tags: Upper }, state)?
		Ok({ value: Act.(parsed.value), rest: parsed.rest })
	}
}

## The error position is in the input, or at its end.
in_input : Try(a, Cbor.Error), U64 -> Bool
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
	camel = Cbor.parse_with(bytes, { fields: Camel })
	numbers : Try(List(U64), _)
	numbers = Cbor.parse(bytes)
	text : Try(Str, _)
	text = Cbor.parse(bytes)
	nullable : Try(Try(U64, [Null]), _)
	nullable = Cbor.parse(bytes)
	cells : Try(List((Bool, Try(I64, [Null]))), _)
	cells = Cbor.parse(bytes)
	raw : Try(Cbor.U8Array, _)
	raw = Cbor.parse(bytes)
	small : Try(List(U8), _)
	small = Cbor.parse(bytes)
	dec : Try(Dec, _)
	dec = Cbor.parse(bytes)
	decs : Try(List(Dec), _)
	decs = Cbor.parse(bytes)
	dict : Try(Dict(Str, U64), _)
	dict = Cbor.parse(bytes)
	int_dict : Try(Dict(U64, Str), _)
	int_dict = Cbor.parse(bytes)
	wide : Try(List(U128), _)
	wide = Cbor.parse(bytes)
	signed : Try(List(I128), _)
	signed = Cbor.parse_with(bytes, { allow: [PaddedNumbers, FloatToInt] })
	# Indefinite lengths: the same types, and a Dict with a key to skip.
	indefinite : Cbor.Options
	indefinite = { allow: [IndefiniteLength] }
	indef_row : Try(Row, _)
	indef_row = Cbor.parse_with(bytes, indefinite)
	indef_small : Try(List(List(U8)), _)
	indef_small = Cbor.parse_with(bytes, indefinite)
	indef_text : Try(List(Str), _)
	indef_text = Cbor.parse_with(bytes, indefinite)
	indef_dict : Try(Dict(U64, Str), _)
	indef_dict = Cbor.parse_with(bytes, { allow: [IndefiniteLength], duplicate_keys: First })
	indef_cells : Try(List((Bool, Try(I64, [Null]))), _)
	indef_cells = Cbor.parse_with(bytes, indefinite)
	indef_shapes : Try(List(Shape), _)
	indef_shapes = Cbor.parse_with(bytes, { allow: [IndefiniteLength], unions: Internal({ tag: "kind", content: "value" }) })
	text_row : Try(Row, _)
	text_row = Cbor.parse_with(bytes, { fields: Camel, allow: [IntFromText] })
	text_ints : Try(List(I8), _)
	text_ints = Cbor.parse_with(bytes, { allow: [IntFromText] })
	tag_opts : Cbor.Options
	tag_opts = { ignore_tags: [6, 10, 4], allow: [DecFromText] }
	tag_row : Try(Row, _)
	tag_row = Cbor.parse_with(bytes, tag_opts)
	tag_decs : Try(List(Try(Dec, [Null])), _)
	tag_decs = Cbor.parse_with(bytes, tag_opts)
	text_dec : Try(Dec, _)
	text_dec = Cbor.parse_with(bytes, { allow: [DecFromText] })
	# The lenient reads of SQL rows: the walk is the same as the strict one.
	rows : Cbor.Options
	rows = { allow: Cbor.sql_rows, unknown_fields: Reject, max_items: 200 }
	rows_row : Try(Row, _)
	rows_row = Cbor.parse_with(bytes, rows)
	rows_cells : Try(List((Bool, Try(I64, [Null]), List(U8))), _)
	rows_cells = Cbor.parse_with(bytes, rows)
	internal : Cbor.Options
	internal = { unions: Internal({ tag: "kind", content: "value" }), ignore_tags: [6] }
	shapes : Try(List(Shape), _)
	shapes = Cbor.parse_with(bytes, internal)
	shape_row : Try({ id : U64, shape : Shape, act : Act, acts : List(Act) }, _)
	shape_row = Cbor.parse_with(bytes, internal)
	# A duplicate key: the last instance, in each reader. Any head width.
	last : Cbor.Options
	last = { duplicate_keys: Last, allow: [PaddedNumbers], unions: Internal({ tag: "kind", content: "value" }) }
	last_row : Try(Row, _)
	last_row = Cbor.parse_with(bytes, last)
	last_dict : Try(Dict(Str, U64), _)
	last_dict = Cbor.parse_with(bytes, last)
	last_shapes : Try(List(Shape), _)
	last_shapes = Cbor.parse_with(bytes, last)
	last_any : Try(Cbor.Value, _)
	last_any = Cbor.parse_with(bytes, last)
	first_any : Try(Cbor.Value, _)
	first_any = Cbor.parse_with(bytes, { duplicate_keys: First, allow: [PaddedNumbers] })
	# The loosest walk: the checks that no option changes, the checks of path_at (any head width, any length).
	loose_any : Try(Cbor.Value, _)
	loose_any = Cbor.parse_with(bytes, { duplicate_keys: Last, allow: [PaddedNumbers, IndefiniteLength], max_depth: U64.highest })
	# Cbor.Value with IndefiniteLength, and with First for the Dict that has it.
	indef_any : Try(Cbor.Value, _)
	indef_any = Cbor.parse_with(bytes, indefinite)
	indef_first_any : Try(Cbor.Value, _)
	indef_first_any = Cbor.parse_with(bytes, { allow: [IndefiniteLength], duplicate_keys: First })
	acts : Try(List(Act), _)
	acts = Cbor.parse(bytes)
	any : Try(Cbor.Value, _)
	any = Cbor.parse(bytes)
	anys : Try({ id : U64, v : Cbor.Value, w : List(Cbor.Value) }, _)
	anys = Cbor.parse_with(bytes, tag_opts)
	# A Cbor.Raw reads exactly the bytes of the item that Cbor.Value reads, also as a record field.
	raw_item : Try(Cbor.Raw, _)
	raw_item = Cbor.parse(bytes)
	raw_row : Try({ id : U64, v : Cbor.Raw }, _)
	raw_row = Cbor.parse_with(bytes, tag_opts)
	raw_last : Try(Cbor.Raw, _)
	raw_last = Cbor.parse_with(bytes, last)
	if raw_item.is_ok() != any.is_ok() or raw_item != Cbor.Raw.from_bytes(bytes) or raw_last.is_ok() != last_any.is_ok() {
		crash "Cbor.Raw does not agree with Cbor.Value"
	}
	if raw_item.map_ok(|r| r.to_bytes() == bytes) == Ok(Bool.False) or raw_last.map_ok(|r| r.to_bytes() == bytes) == Ok(Bool.False) {
		crash "Cbor.Raw does not keep the exact bytes"
	}
	if raw_item.map_ok(|r| Cbor.encode(r) == bytes) == Ok(Bool.False) {
		crash "Cbor.Raw does not write its bytes"
	}
	# A CBOR sequence: one item gives the same as parse. The items of a sequence write a sequence that reads back.
	# Raw items of a sequence give all of the bytes. A prefix is the first item of the sequence.
	seq : Try(List(Cbor.Value), _)
	seq = Cbor.parse_sequence(bytes)
	raws : Try(List(Cbor.Raw), _)
	raws = Cbor.parse_sequence_with(bytes, last)
	prefix : Try({ value : Cbor.Value, rest : List(U8) }, _)
	prefix = Cbor.parse_prefix(bytes)
	if any.is_ok() and seq != any.map_ok(|v| [v]) {
		crash "parse_sequence of one item is not parse"
	}
	match seq {
		Ok(items) => {
			again : Try(List(Cbor.Value), _)
			again = Cbor.parse_sequence(items.map(|v| Cbor.encode(v)).join())
			if again != Ok(items) {
				crash "a sequence does not read back"
			}
			first_ok = items.first().map_ok(|f| prefix.map_ok(|p| p.value == f) == Ok(Bool.True)) ?? Bool.True
			if !first_ok {
				crash "parse_prefix is not the first item of the sequence"
			}
		}
		Err(_) => {}
	}
	if raws.map_ok(|rs| rs.map(|r| r.to_bytes()).join() == bytes) == Ok(Bool.False) {
		crash "the Raw items of a sequence are not all of the bytes"
	}
	match prefix {
		Ok(p) =>
			if p.rest.len() >= len or bytes.drop_first(len - p.rest.len()) != p.rest {
				crash "parse_prefix gives a wrong rest"
			}
		Err(_) => {}
	}
	if !in_input(seq, len) or !in_input(prefix, len) or !in_input(raws, len) {
		crash "error position past the end of the input"
	}
	# Each Cbor.Value writes bytes with shortest heads and no duplicate key: the strict reader reads them back.
	same = [any, last_any, first_any, loose_any, indef_any].all(
		|r| match r {
			Ok(v) => {
				again : Try(Cbor.Value, _)
				again = Cbor.parse(Cbor.encode(v))
				again == Ok(v)
			}
			Err(_) => Bool.True
		},
	)
	if !same {
		crash "a Cbor.Value does not read back"
	}
	indef_ok = in_input(indef_row, len) and in_input(indef_small, len) and in_input(indef_text, len) and in_input(indef_dict, len) and in_input(indef_cells, len) and in_input(indef_shapes, len)
	if !indef_ok or !in_input(int_dict, len) or !in_input(wide, len) or !in_input(signed, len) {
		crash "error position past the end of the input"
	}
	# IndefiniteLength reads more, never another value.
	if (row.is_ok() and indef_row != row) or (cells.is_ok() and indef_cells != cells) {
		crash "IndefiniteLength changes a value that the strict reader reads"
	}
	# path_at walks any length: the root of bytes that a parse with IndefiniteLength reads has the path [].
	# One notion of valid with IndefiniteLength: a typed Ok gives Ok as a Cbor.Value with the same walk options.
	if ([indef_row.is_ok(), indef_small.is_ok(), indef_text.is_ok(), indef_cells.is_ok(), indef_shapes.is_ok()].any(|t| t) and !indef_any.is_ok()) or (indef_dict.is_ok() and !indef_first_any.is_ok()) {
		crash "a typed parse with IndefiniteLength gives Ok, but Cbor.Value gives Err"
	}
	if [indef_row.is_ok(), indef_small.is_ok(), indef_text.is_ok(), indef_dict.is_ok(), indef_cells.is_ok(), indef_shapes.is_ok()].any(|t| t) and Cbor.path_at(bytes, 0) != Ok([]) {
		crash "path_at(bytes, 0) is not [] for an item that IndefiniteLength reads"
	}
	ok = in_input(shapes, len) and in_input(shape_row, len) and in_input(acts, len) and in_input(tag_row, len) and in_input(tag_decs, len) and in_input(text_dec, len) and in_input(any, len) and in_input(anys, len) and in_input(row, len) and in_input(camel, len) and in_input(numbers, len) and in_input(text, len) and in_input(nullable, len) and in_input(cells, len) and in_input(raw, len) and in_input(small, len) and in_input(dec, len) and in_input(decs, len) and in_input(dict, len) and in_input(text_row, len) and in_input(text_ints, len) and in_input(rows_row, len) and in_input(rows_cells, len) and in_input(last_row, len) and in_input(last_dict, len) and in_input(last_shapes, len) and in_input(last_any, len)
	if !ok {
		crash "error position past the end of the input"
	}
	typed = [int_dict.is_ok(), wide.is_ok(), row.is_ok(), camel.is_ok(), numbers.is_ok(), text.is_ok(), nullable.is_ok(), cells.is_ok(), raw.is_ok(), small.is_ok(), dec.is_ok(), decs.is_ok(), dict.is_ok(), text_row.is_ok(), text_ints.is_ok(), tag_row.is_ok(), tag_decs.is_ok(), text_dec.is_ok(), shapes.is_ok(), shape_row.is_ok(), acts.is_ok(), anys.is_ok(), rows_row.is_ok(), rows_cells.is_ok(), raw_item.is_ok(), raw_row.is_ok()]
	if typed.any(|t| t) and !any.is_ok() {
		crash "a typed parse gives Ok, but Cbor.Value gives Err"
	}
	if [last_row.is_ok(), last_dict.is_ok(), last_shapes.is_ok()].any(|t| t) and !last_any.is_ok() {
		crash "a typed parse with duplicate_keys: Last gives Ok, but Cbor.Value gives Err"
	}
	# A stricter walk accepts less: strict, then Last or First, then the loosest walk.
	if (any.is_ok() and !last_any.is_ok()) or (last_any.is_ok() != first_any.is_ok()) or (last_any.is_ok() and !loose_any.is_ok()) {
		crash "a stricter walk accepts bytes that a looser walk rejects"
	}
	# path_at at the error position of each parse, and at the start, the middle and the end.
	positions = [row, camel, text_row].keep_oks(
		|r| match r {
			Err(InvalidCbor(pos)) => Ok(pos)
			_ => Err(NoPosition)
		},
	).concat([0, len // 2, len])
	paths = positions.map(|pos| Cbor.path_at(bytes, pos))
	# The root item starts at 0: its path is [] when the bytes are one well-formed item, else each path is NotFound.
	if loose_any.is_ok() and paths.get(paths.len() - 3) != Ok(Ok([])) {
		crash "path_at(bytes, 0) is not [] for a well-formed item"
	}
	if !loose_any.is_ok() and paths.any(|p| p.is_ok()) {
		crash "path_at gives Ok for bytes that are not well-formed"
	}
	Fuzz.keep
}

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
	name: "parse-never-crashes",
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || [] }),
		Fuzz.example({ name: "short", revision: "1", make: || [0x01, 0x82, 0x18, 0x2a, 0xa1, 0x61, 0x61, 0x00] }),
		Fuzz.example({ name: "ramp", revision: "1", make: || ramp }),
	],
	generator: Fuzz.raw_bytes,
	test!,
	show: |bytes| Str.inspect(bytes),
})
