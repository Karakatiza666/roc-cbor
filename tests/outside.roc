app [] { pkg: "../src/main.roc" }

# A format outside the package, with state of its own beside the CBOR state: the handles that a value holds.
# On write it collects them in a list, and the payload has the place of each one. On read it gets the list.

import pkg.Cbor

## The state of a write: the writer, and the handles so far.
Enc : Cbor.WriterWith(List(Str))

## The state in a container.
In : Cbor.ContainerWith(List(Str))

## The state of a read: the encoding and the reader of roc-cbor, and the handles.
Rd : { cbor : Cbor, r : Cbor.Reader, table : List(Str) }

## A handle: it does not cross as bytes. The payload has its place in the list.
Handle := Str.{
	is_eq : _

	encoder_for : Out -> (Handle, Enc -> Try(Enc, err))
	encoder_for = |_| |Handle.(name), e| {
		{ writer, state } = e
		place = state.len()
		Ok({ writer: Cbor.encode_u64(place, writer)?, state: state.append(name) })
	}

	parser_for : Out -> (Rd -> Try({ value : Handle, rest : Rd }, Cbor.Error))
	parser_for = |_| |d| {
		place = Cbor.parse_u64(d.cbor, d.r)?
		match d.table.get(place.value) {
			Ok(name) => Ok({ value: Handle.(name), rest: { ..d, r: place.rest } })
			Err(_) => Err(Cbor.invalid_value(d.cbor, d.r))
		}
	}
}

## One item: the value, and the state after it.
item : Rd, Try({ value : a, rest : Cbor.Reader }, Cbor.Error) -> Try({ value : a, rest : Rd }, Cbor.Error)
item = |d, read|
	match read {
		Ok({ value, rest }) => Ok({ value, rest: { ..d, r: rest } })
		Err(e) => Err(e)
	}

## The state after a step of a reader.
step : Rd, Try(Cbor.Reader, Cbor.Error) -> Try(Rd, Cbor.Error)
step = |d, read|
	match read {
		Ok(rest) => Ok({ ..d, r: rest })
		Err(e) => Err(e)
	}

Out := [Default].{
	invalid_value : Out, Rd -> Cbor.Error
	invalid_value = |_, d| Cbor.invalid_value(d.cbor, d.r)

	missing_field : Out, Str -> Cbor.Error
	missing_field = |_, name| MissingRequiredField(name)

	rename_field : Out, Str -> Str
	rename_field = |_, name| name

	encode_str : Str, Enc -> Try(Enc, err)
	encode_str = |v, e| Ok({ writer: Cbor.encode_str(v, e.writer)?, state: e.state })

	parse_str : Out, Rd -> Try({ value : Str, rest : Rd }, Cbor.Error)
	parse_str = |_, d| item(d, Cbor.parse_str(d.cbor, d.r))

	encode_bool : Bool, Enc -> Try(Enc, err)
	encode_bool = |v, e| Ok({ writer: Cbor.encode_bool(v, e.writer)?, state: e.state })

	parse_bool : Out, Rd -> Try({ value : Bool, rest : Rd }, Cbor.Error)
	parse_bool = |_, d| item(d, Cbor.parse_bool(d.cbor, d.r))

	encode_u8 : U8, Enc -> Try(Enc, err)
	encode_u8 = |v, e| Ok({ writer: Cbor.encode_u8(v, e.writer)?, state: e.state })

	parse_u8 : Out, Rd -> Try({ value : U8, rest : Rd }, Cbor.Error)
	parse_u8 = |_, d| item(d, Cbor.parse_u8(d.cbor, d.r))

	encode_u64 : U64, Enc -> Try(Enc, err)
	encode_u64 = |v, e| Ok({ writer: Cbor.encode_u64(v, e.writer)?, state: e.state })

	parse_u64 : Out, Rd -> Try({ value : U64, rest : Rd }, Cbor.Error)
	parse_u64 = |_, d| item(d, Cbor.parse_u64(d.cbor, d.r))

	encode_i64 : I64, Enc -> Try(Enc, err)
	encode_i64 = |v, e| Ok({ writer: Cbor.encode_i64(v, e.writer)?, state: e.state })

	parse_i64 : Out, Rd -> Try({ value : I64, rest : Rd }, Cbor.Error)
	parse_i64 = |_, d| item(d, Cbor.parse_i64(d.cbor, d.r))

	encode_f64 : F64, Enc -> Try(Enc, err)
	encode_f64 = |v, e| Ok({ writer: Cbor.encode_f64(v, e.writer)?, state: e.state })

	parse_f64 : Out, Rd -> Try({ value : F64, rest : Rd }, Cbor.Error)
	parse_f64 = |_, d| item(d, Cbor.parse_f64(d.cbor, d.r))

	# A list

	encode_list : Enc, U64, (In, (In, (Enc -> Try(Enc, err)) -> Try(In, err)) -> Try(In, err)) -> Try(Enc, err)
	encode_list = |e, count, write_items| Cbor.encode_list_carry(e, count, write_items)

	parse_list_start : Out, Rd -> Try([Counted({ len : U64, rest : Rd }), Uncounted(Rd)], Cbor.Error)
	parse_list_start = |_, d|
		match Cbor.parse_list_start(d.cbor, d.r)? {
			Counted({ len, rest }) => Ok(Counted({ len, rest: { ..d, r: rest } }))
			Uncounted(rest) => Ok(Uncounted({ ..d, r: rest }))
		}

	parse_list_next : Out, Rd -> Try([Item(Rd), Done(Rd)], Cbor.Error)
	parse_list_next = |_, d|
		match Cbor.parse_list_next(d.cbor, d.r)? {
			Item(rest) => Ok(Item({ ..d, r: rest }))
			Done(rest) => Ok(Done({ ..d, r: rest }))
		}

	parse_list_after_item : Out, Rd -> Try([Continue(Rd), Done(Rd)], Cbor.Error)
	parse_list_after_item = |_, d|
		match Cbor.parse_list_after_item(d.cbor, d.r)? {
			Continue(rest) => Ok(Continue({ ..d, r: rest }))
			Done(rest) => Ok(Done({ ..d, r: rest }))
		}

	# A record

	encode_record : Enc, U64, (In, (In, Str, (Enc -> Try(Enc, err)) -> Try(In, err)) -> Try(In, err)) -> Try(Enc, err)
	encode_record = |e, count, write_fields| Cbor.encode_record_carry(e, count, write_fields)

	parse_record_start : Out, Rd -> Try([Counted({ len : U64, rest : Rd }), Uncounted(Rd)], Cbor.Error)
	parse_record_start = |_, d|
		match Cbor.parse_record_start(d.cbor, d.r)? {
			Counted({ len, rest }) => Ok(Counted({ len, rest: { ..d, r: rest } }))
			Uncounted(rest) => Ok(Uncounted({ ..d, r: rest }))
		}

	parse_record_field : Out, Encoding.FieldName.FieldNames(_shape), Rd -> Try([Field({ field : Encoding.FieldName(_shape), rest : Rd }), TryField({ name : Str, rest : Rd }), TryFieldCaseless({ name : Str, rest : Rd }), Continue(Rd), Done(Rd)], Cbor.Error)
	parse_record_field = |_, names, d|
		match Cbor.parse_record_field(d.cbor, names, d.r)? {
			Field({ field, rest }) => Ok(Field({ field, rest: { ..d, r: rest } }))
			TryField({ name, rest }) => Ok(TryField({ name, rest: { ..d, r: rest } }))
			TryFieldCaseless({ name, rest }) => Ok(TryFieldCaseless({ name, rest: { ..d, r: rest } }))
			Continue(rest) => Ok(Continue({ ..d, r: rest }))
			Done(rest) => Ok(Done({ ..d, r: rest }))
		}

	parse_record_after_field : Out, Rd -> Try([Continue(Rd), Done(Rd)], Cbor.Error)
	parse_record_after_field = |_, d|
		match Cbor.parse_record_after_field(d.cbor, d.r)? {
			Continue(rest) => Ok(Continue({ ..d, r: rest }))
			Done(rest) => Ok(Done({ ..d, r: rest }))
		}

	skip_record_field : Out, Rd -> Try(Rd, Cbor.Error)
	skip_record_field = |_, d| step(d, Cbor.skip_record_field(d.cbor, d.r))

	# A tuple

	encode_tuple : Enc, U64, (In, (In, (Enc -> Try(Enc, err)) -> Try(In, err)) -> Try(In, err)) -> Try(Enc, err)
	encode_tuple = |e, count, write_items| Cbor.encode_tuple_carry(e, count, write_items)

	parse_tuple_start : Out, Rd, U64 -> Try(Rd, Cbor.Error)
	parse_tuple_start = |_, d, len| step(d, Cbor.parse_tuple_start(d.cbor, d.r, len))

	parse_tuple_next : Out, Rd, U64, U64 -> Try(Rd, Cbor.Error)
	parse_tuple_next = |_, d, index, len| step(d, Cbor.parse_tuple_next(d.cbor, d.r, index, len))

	parse_tuple_end : Out, Rd, U64 -> Try(Rd, Cbor.Error)
	parse_tuple_end = |_, d, len| step(d, Cbor.parse_tuple_end(d.cbor, d.r, len))

	# A tag union: the layout of roc-cbor, read with its public readers

	encode_tag : Enc, Str, U64, (In, (In, (Enc -> Try(Enc, err)) -> Try(In, err)) -> Try(In, err)) -> Try(Enc, err)
	encode_tag = |e, name, count, write_payloads| Cbor.encode_tag_carry(e, name, count, write_payloads)

	parse_tag_union : Out, Encoding.ParseTagUnionSpec(a, Out, Rd, Cbor.Error), Rd -> Try({ value : a, rest : Rd }, Cbor.Error)
	parse_tag_union = |encoding, spec, d|
		match Cbor.peek(d.cbor, d.r)? {
			Text => {
				name = Cbor.parse_str(d.cbor, d.r)?
				Encoding.ParseTagUnionSpec.parse(
					spec,
					{
						tag: name.value,
						encoding,
						state: { ..d, r: name.rest },
						start_payloads: |s, count| if (count == 0) Ok(s) else Err(Cbor.invalid_value(s.cbor, s.r)),
						next_payload: |s, _, _| Err(Cbor.invalid_value(s.cbor, s.r)),
						finish_payloads: |s, _| Ok(s),
						missing: Cbor.invalid_value(d.cbor, d.r),
					},
				)
			}
			Map => {
				entry =
					match Cbor.parse_dict_start(d.cbor, d.r)? {
						Counted({ len, rest }) if len == 1 => rest
						_ => return Err(Cbor.invalid_value(d.cbor, d.r))
					}
				name = Cbor.parse_key_str(d.cbor, entry)?
				key_done = Cbor.parse_dict_after_key(d.cbor, name.rest)?
				Encoding.ParseTagUnionSpec.parse(
					spec,
					{
						tag: name.value,
						encoding,
						state: { ..d, r: key_done },
						start_payloads: |s, count| if (count == 1) Ok(s) else step(s, Cbor.parse_tuple_start(s.cbor, s.r, count)),
						next_payload: |s, index, count| if (count == 1) Ok(s) else step(s, Cbor.parse_tuple_next(s.cbor, s.r, index, count)),
						finish_payloads: |s, count| if (count == 1) Ok(s) else step(s, Cbor.parse_tuple_end(s.cbor, s.r, count)),
						missing: Cbor.invalid_value(d.cbor, d.r),
					},
				)
			}
			_ => Err(Cbor.invalid_value(d.cbor, d.r))
		}

	# A Dict: a key place, then a value place, for each entry

	encode_dict : Enc, U64, (In, (In, (Enc -> Try(Enc, err)), (Enc -> Try(Enc, err)) -> Try(In, err)) -> Try(In, err)) -> Try(Enc, err)
	encode_dict = |e, count, write_entries| Cbor.encode_dict_carry(e, count, write_entries)

	parse_dict_start : Out, Rd -> Try([Counted({ len : U64, rest : Rd }), Uncounted(Rd)], Cbor.Error)
	parse_dict_start = |_, d|
		match Cbor.parse_dict_start(d.cbor, d.r)? {
			Counted({ len, rest }) => Ok(Counted({ len, rest: { ..d, r: rest } }))
			Uncounted(rest) => Ok(Uncounted({ ..d, r: rest }))
		}

	parse_dict_next : Out, Rd -> Try([Entry(Rd), Done(Rd)], Cbor.Error)
	parse_dict_next = |_, d|
		match Cbor.parse_dict_next(d.cbor, d.r)? {
			Entry(rest) => Ok(Entry({ ..d, r: rest }))
			Done(rest) => Ok(Done({ ..d, r: rest }))
		}

	parse_dict_after_key : Out, Rd -> Try(Rd, Cbor.Error)
	parse_dict_after_key = |_, d| step(d, Cbor.parse_dict_after_key(d.cbor, d.r))

	parse_dict_after_entry : Out, Rd -> Try([Continue(Rd), Done(Rd)], Cbor.Error)
	parse_dict_after_entry = |_, d|
		match Cbor.parse_dict_after_entry(d.cbor, d.r)? {
			Continue(rest) => Ok(Continue({ ..d, r: rest }))
			Done(rest) => Ok(Done({ ..d, r: rest }))
		}

	encode_key_str : Out, Str, Enc -> Try(Enc, err)
	encode_key_str = |_, v, e| Ok({ writer: Cbor.encode_str(v, e.writer)?, state: e.state })

	parse_key_str : Out, Rd -> Try({ value : Str, rest : Rd }, Cbor.Error)
	parse_key_str = |_, d| item(d, Cbor.parse_key_str(d.cbor, d.r))

	encode_key_u64 : Out, U64, Enc -> Try(Enc, err)
	encode_key_u64 = |_, v, e| Ok({ writer: Cbor.encode_u64(v, e.writer)?, state: e.state })

	parse_key_u64 : Out, Rd -> Try({ value : U64, rest : Rd }, Cbor.Error)
	parse_key_u64 = |_, d| item(d, Cbor.parse_key_u64(d.cbor, d.r))
}

## Writes `value` through the outside format: the bytes, and the handles beside them.
write : a, Cbor.WriteOptions -> Try({ bytes : List(U8), held : List(Str) }, [CountMismatch, DuplicateMapKey, ..err])
	where [a.encoder_for : Out -> (a, Enc -> Try(Enc, [CountMismatch, DuplicateMapKey, ..err]))]
write = |value, options| {
	Shape : a
	encode_shape = Shape.encoder_for(Out.Default)
	e = encode_shape(value, { writer: Cbor.Writer.new(options), state: [] })?
	bytes = e.writer.finish()?
	Ok({ bytes, held: e.state })
}

## Reads a value through the outside format, with the handles `table`.
read : List(U8), List(Str), Cbor.Options -> Try(a, Cbor.Error)
	where [a.parser_for : Out -> (Rd -> Try({ value : a, rest : Rd }, Cbor.Error))]
read = |bytes, table, options| {
	start = Cbor.Reader.new(bytes, options)?
	Shape : a
	parse_shape = Shape.parser_for(Out.Default)
	parsed = parse_shape({ cbor: start.cbor, r: start.reader, table })?
	parsed.rest.r.finish()?
	Ok(parsed.value)
}

# The bytes are the bytes of Cbor.encode_with, and the value reads back

Shape : [Circle(F64), Rect(F64, F64), Dot]

Row : { id : U64, name : Str, tags : List(Str), shape : Shape, pair : (I64, Bool), data : List(U8), nick ?: Str }

row : Row
row = { id: 7, name: "a", tags: ["x", "y"], shape: Rect(1.5, 2.0), pair: (-3, Bool.True), data: [1, 2, 3] }

## A record with a list, a tag union, a tuple, a byte string and an absent optional field.
expect {
	sent = write(row, {})
	sent.map_ok(|s| s.bytes) == Cbor.encode_with(row, {})
}

## The row reads back through Cbor.Reader.new, the parse_* methods and Cbor.Reader.finish.
expect {
	back : Try(Row, _)
	back = read(Cbor.encode(row), [], {})
	back == Ok(row)
}

## With the optional field.
expect {
	with_nick : Row
	with_nick = { ..row, nick: "n" }
	sent = write(with_nick, {})
	sent.map_ok(|s| s.bytes) == Cbor.encode_with(with_nick, {})
}

## A list of records, each tag layout, an empty list, sorted keys.
expect {
	rows : List(Row)
	rows = [row, { ..row, shape: Dot, tags: [] }, { ..row, shape: Circle(0.5) }]
	sent = write(rows, { key_order: Sorted })
	back : Try(List(Row), _)
	back = read(sent.map_ok(|s| s.bytes) ?? [], [], { key_order: Sorted })
	sent.map_ok(|s| s.bytes) == Cbor.encode_with(rows, { key_order: Sorted }) and back == Ok(rows)
}

## A Dict: a key place and a value place for each entry.
expect {
	d : Dict(Str, List(U64))
	d = Dict.from_list([("b", [1, 2]), ("a", [])])
	sent = write(d, {})
	back : Try(Dict(Str, List(U64)), _)
	back = read(sent.map_ok(|s| s.bytes) ?? [], [], {})
	sent.map_ok(|s| s.bytes) == Cbor.encode_with(d, {}) and back == Ok(d)
}

# The state of the caller: the handles beside the bytes

## A record with a list of handles: the payload has the places 0 and 1, and the handles are beside it.
expect {
	sent = write({ note: "x", docs: [Handle.("a.txt"), Handle.("b.txt")] }, {})
	sent == Ok({ bytes: Cbor.encode({ note: "x", docs: [0.U64, 1] }), held: ["a.txt", "b.txt"] })
}

## It reads back with the handles.
expect {
	bytes = Cbor.encode({ note: "x", docs: [0.U64, 1] })
	back : Try({ note : Str, docs : List(Handle) }, _)
	back = read(bytes, ["a.txt", "b.txt"], {})
	back == Ok({ note: "x", docs: [Handle.("a.txt"), Handle.("b.txt")] })
}

## A place that the table does not have is an error at the place.
expect {
	bytes = Cbor.encode({ note: "x", docs: [0.U64, 1] })
	back : Try({ note : Str, docs : List(Handle) }, _)
	back = read(bytes, ["a.txt"], {})
	back == Err(InvalidCbor(8))
}

# The start and the end of a read

## Bytes after the item are an error at the first extra byte.
expect {
	back : Try(U64, _)
	back = read([0x01, 0x02], [], {})
	back == Err(InvalidCbor(1))
}

## The walk comes first: a longer head is an error, also in a field that the type skips.
expect {
	back : Try({ a : U64 }, _)
	back = read([0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x18, 0x01], [], {})
	back == Err(InvalidCbor(6))
}

## max_depth applies.
expect {
	back : Try(List(List(U64)), _)
	back = read([0x81, 0x81, 0x01], [], { max_depth: 1 })
	back == Err(InvalidCbor(1))
}

## A read that ends before the end of the item is an error at its end.
expect {
	start = Cbor.Reader.new([0x82, 0x01, 0x02], {})
	match start {
		Ok({ cbor, reader }) =>
			match Cbor.parse_list_start(cbor, reader) {
				Ok(Counted({ rest, .. })) => rest.finish() == Err(InvalidCbor(1))
				_ => Bool.False
			}
		Err(_) => Bool.False
	}
}

# Count mismatch: the checks of the callbacks of the package, with a value of the caller

## An encoder_for of the outside format that writes what the test asks for, also a wrong count of items.
Probe := [
	Nothing,
	TwoRoot,
	List(U64, U64),
	Slot(U64),
	Tuple(U64, U64),
	Tag(U64, U64),
	Record(U64, U64),
	Dict(U64, U64),
	KeyOnly,
	Sneak,
	Keep,
].{
	encoder_for : Out -> (Probe, Enc -> Try(Enc, err))
	encoder_for = |_| |probe, e|
		match probe {
			Nothing => Ok(e)
			TwoRoot => seven(seven(e)?)
			List(declared, written) => Cbor.encode_list_carry(e, declared, |c, add| items(c, add, written))
			Slot(n) => Cbor.encode_list_carry(e, 1, |c, add| add(c, |v| sevens(v, n)))
			Tuple(declared, written) => Cbor.encode_tuple_carry(e, declared, |c, add| items(c, add, written))
			Tag(declared, written) => Cbor.encode_tag_carry(e, "T", declared, |c, add| items(c, add, written))
			Record(declared, written) =>
				Cbor.encode_record_carry(
					e,
					declared,
					|c, add| {
						var $c = c
						for i in (0.U64).until(written) {
							$c = add($c, "k${i.to_str()}", seven)?
						}
						Ok($c)
					},
				)
			Dict(declared, written) =>
				Cbor.encode_dict_carry(
					e,
					declared,
					|c, add| {
						var $c = c
						for _ in (0.U64).until(written) {
							$c = add($c, seven, seven)?
						}
						Ok($c)
					},
				)
			KeyOnly => Cbor.encode_dict_carry(e, 1, |c, add| add(c, seven, |v| Ok(v)))
			# A slot gives back the writer of the level above.
			Sneak => Cbor.encode_list_carry(e, 1, |c, add| add(c, |_inner| seven(e)))
			# The value of the caller that an item changes is the value after the container.
			Keep => Cbor.encode_list_carry(e, 2, |c, add| add(add(c, mark)?, mark))
		}
}

## The item 7.
seven : Enc -> Try(Enc, err)
seven = |e| Ok({ writer: Cbor.encode_u64(7, e.writer)?, state: e.state })

## The item 7, and one more handle in the value of the caller.
mark : Enc -> Try(Enc, err)
mark = |e| Ok({ writer: Cbor.encode_u64(7, e.writer)?, state: e.state.append("m") })

## `n` items, each one 7.
sevens : Enc, U64 -> Try(Enc, err)
sevens = |e, n| {
	var $e = e
	for _ in (0.U64).until(n) {
		$e = seven($e)?
	}
	Ok($e)
}

## `n` calls of `add`, each with one item.
items : c, (c, (Enc -> Try(Enc, err)) -> Try(c, err)), U64 -> Try(c, err)
items = |c, add, n| {
	var $c = c
	for _ in (0.U64).until(n) {
		$c = add($c, seven)?
	}
	Ok($c)
}

## The bytes of a probe.
probe : Probe -> Try(List(U8), [CountMismatch, DuplicateMapKey])
probe = |p| write(p, {}).map_ok(|sent| sent.bytes)

## No root item: CountMismatch.
expect probe(Probe.Nothing) == Err(CountMismatch)

## Two root items: CountMismatch.
expect probe(Probe.TwoRoot) == Err(CountMismatch)

## A list of 1 whose place gets 0 items: CountMismatch.
expect probe(Probe.Slot(0)) == Err(CountMismatch)

## A list of 1 whose place gets 2 items: CountMismatch.
expect probe(Probe.Slot(2)) == Err(CountMismatch)

## A list of 1 whose place gets 1 item: 81 07.
expect probe(Probe.Slot(1)) == Ok([0x81, 0x07])

## A list of 3 with 1 item: CountMismatch.
expect probe(Probe.List(3, 1)) == Err(CountMismatch)

## A list of 1 with 2 items: CountMismatch.
expect probe(Probe.List(1, 2)) == Err(CountMismatch)

## A list of 2 with 2 items: 82 07 07.
expect probe(Probe.List(2, 2)) == Ok([0x82, 0x07, 0x07])

## A list of 0 with no item: 80.
expect probe(Probe.List(0, 0)) == Ok([0x80])

## A tuple of 2 with 1 item: CountMismatch.
expect probe(Probe.Tuple(2, 1)) == Err(CountMismatch)

## A tuple of 2 with 2 items: 82 07 07.
expect probe(Probe.Tuple(2, 2)) == Ok([0x82, 0x07, 0x07])

## A tag of 2 payloads with 1: CountMismatch.
expect probe(Probe.Tag(2, 1)) == Err(CountMismatch)

## A tag of 1 payload with 2: CountMismatch.
expect probe(Probe.Tag(1, 2)) == Err(CountMismatch)

## A tag with no payload is its name as text: 61 54.
expect probe(Probe.Tag(0, 0)) == Ok([0x61, 0x54])

## A tag of 1 payload: a map of the name to the payload, a1 61 54 07.
expect probe(Probe.Tag(1, 1)) == Ok([0xa1, 0x61, 0x54, 0x07])

## A tag of 2 payloads: a map of the name to an array, a1 61 54 82 07 07.
expect probe(Probe.Tag(2, 2)) == Ok([0xa1, 0x61, 0x54, 0x82, 0x07, 0x07])

## A record of 1 field with 2 fields: CountMismatch.
expect probe(Probe.Record(1, 2)) == Err(CountMismatch)

## A record of 2 with one field: the head is for 1 (a1 62 6b 30 07).
expect probe(Probe.Record(2, 1)) == Ok([0xa1, 0x62, 0x6b, 0x30, 0x07])

## A dict of 1 entry with 1 entry: a1 07 07.
expect probe(Probe.Dict(1, 1)) == Ok([0xa1, 0x07, 0x07])

## A dict of 2 entries with 1: CountMismatch.
expect probe(Probe.Dict(2, 1)) == Err(CountMismatch)

## A dict of 1 entry with 2: CountMismatch.
expect probe(Probe.Dict(1, 2)) == Err(CountMismatch)

## A key with no value.
expect probe(Probe.KeyOnly) == Err(CountMismatch)

## The writer of the level above given back.
expect probe(Probe.Sneak) == Err(CountMismatch)

## Nested in a derived record and list.
expect write({ a: 1.U64, b: [Probe.Nothing] }, {}).map_ok(|sent| sent.bytes) == Err(CountMismatch)

## The value of the caller comes out of the container with the changes of each item.
expect write(Probe.Keep, {}) == Ok({ bytes: [0x82, 0x07, 0x07], held: ["m", "m"] })

# Options

## Sorted: the entries of each map are sorted.
expect write({ b: 1.U64, a: 2.U64 }, { key_order: Sorted }).map_ok(|sent| sent.bytes) == Cbor.encode_with({ b: 1.U64, a: 2.U64 }, { key_order: Sorted })

## Camel: two fields with one key are DuplicateMapKey, as in encode_with. The outside format gives the keys.
Twice := {}.{
	encoder_for : Out -> (Twice, Enc -> Try(Enc, err))
	encoder_for = |_| |_, e| Cbor.encode_record_carry(e, 2, |c, add| add(add(c, "a1", seven)?, "a1", seven))
}

## Two fields with the key a1 and fields: Camel: DuplicateMapKey.
expect write(Twice.({}), { fields: Camel }).map_ok(|sent| sent.bytes) == Err(DuplicateMapKey)

## Two fields with the key a1 and no option: written as they are, as encode_record does.
expect write(Twice.({}), {}).map_ok(|sent| sent.bytes) == Ok([0xa2, 0x62, 0x61, 0x31, 0x07, 0x62, 0x61, 0x31, 0x07])

## Two fields with the key a1 and key_order: Sorted: DuplicateMapKey from the sort.
expect write(Twice.({}), { key_order: Sorted }).map_ok(|sent| sent.bytes) == Err(DuplicateMapKey)

# Cbor.Reader.new and Cbor.Writer.new with the parsers and writers of the package

## Reads one value of the type of the result with Cbor.Reader.new, Cbor.parse_item and Cbor.Reader.finish.
read_plain : List(U8), Cbor.Options -> Try(a, Cbor.Error) where [a.Cbor.Readable]
read_plain = |bytes, options| {
	start = Cbor.Reader.new(bytes, options)?
	parsed = Cbor.parse_item(start.cbor, start.reader)?
	parsed.rest.finish()?
	Ok(parsed.value)
}

## unknown_fields: Reject reaches the record reader: the unknown key b is an error at the key (byte 4).
expect {
	r : Try({ a : U64 }, _)
	r = read_plain([0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02], { unknown_fields: Reject })
	r == Err(InvalidCbor(4))
}

## duplicate_keys: Last reaches the record reader: the second a is read.
expect {
	r : Try({ a : U64 }, _)
	r = read_plain([0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02], { duplicate_keys: Last })
	r == Ok({ a: 2 })
}

## With the default duplicate_keys: Reject, the walk of Cbor.Reader.new finds the second a (byte 4).
expect {
	r : Try({ a : U64 }, _)
	r = read_plain([0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02], {})
	r == Err(InvalidCbor(4))
}

## fields: Camel reaches the record reader: the key userId reads as the field user_id.
expect {
	r : Try({ user_id : U64 }, _)
	r = read_plain([0xa1, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x07], { fields: Camel })
	r == Ok({ user_id: 7 })
}

## allow: [BoolFromInt] reaches the Bool reader: 1 reads as true.
expect {
	r : Try(Bool, _)
	r = read_plain([0x01], { allow: [BoolFromInt] })
	r == Ok(Bool.True)
}

## Cbor.Writer.new and Cbor.Writer.finish give the bytes of encode_with, here with key_order: Sorted.
expect {
	v = { b: 1.U64, a: "x" }
	options : Cbor.WriteOptions
	options = { key_order: Sorted }
	written : Try(Cbor.Writer, [CountMismatch, DuplicateMapKey])
	written = Cbor.encode_item(v, Cbor.Writer.new(options))
	match written {
		Ok(w) => w.finish() == Cbor.encode_with(v, options)
		Err(_) => Bool.False
	}
}

## A writer of Cbor.Writer.new with no item: finish gives CountMismatch.
expect {
	r : Try(List(U8), [CountMismatch, DuplicateMapKey])
	r = Cbor.Writer.new({}).finish()
	r == Err(CountMismatch)
}

## Reads the base64 text "AQI=" as a List(U8) in steps: finish after the last decoded byte (still inside the text),
## and finish after the text. Inside base64 text the reader holds the decoded bytes, so its position alone is not the end.
base64_finish : {} -> Try({ inside : Bool, after : Bool }, Cbor.Error)
base64_finish = |{}| {
	start = Cbor.Reader.new([0x64, 0x41, 0x51, 0x49, 0x3d], { allow: [BytesFromBase64] })?
	c = start.cbor
	s0 =
		match Cbor.parse_list_start(c, start.reader)? {
			Uncounted(s) => s
			Counted({ rest, .. }) => rest
		}
	s1 =
		match Cbor.parse_list_next(c, s0)? {
			Item(s) | Done(s) => s
		}
	a = Cbor.parse_u8(c, s1)?
	s2 =
		match Cbor.parse_list_after_item(c, a.rest)? {
			Continue(s) | Done(s) => s
		}
	b = Cbor.parse_u8(c, s2)?
	s3 =
		match Cbor.parse_list_after_item(c, b.rest)? {
			Continue(s) | Done(s) => s
		}
	Ok({ inside: b.rest.finish().is_ok(), after: s3.finish().is_ok() })
}

## Cbor.Reader.finish inside the decoded bytes of base64 text is an error; after the text it is Ok.
expect base64_finish({}) == Ok({ inside: Bool.False, after: Bool.True })
