app [] { pkg: "../src/main.roc" }

# A format of your own (README, section "A format of your own"), with state beside the state of roc-cbor: the handles
# that a value holds. A handle does not cross as bytes. The payload has its place in a list, and the list goes beside
# the payload. Uses Cbor.Writer.new, Cbor.Writer.finish, Cbor.WriterWith, Cbor.ContainerWith, Cbor.encode_record_carry,
# Cbor.encode_list_carry, Cbor.Reader.new, Cbor.Reader.finish and the parse_* methods. CI runs it on the source and on
# the bundle.

import pkg.Cbor

## The state of a write: the writer of roc-cbor, and the handles so far.
Enc : Cbor.WriterWith(List(Str))

## The state of a read: the encoding and the reader of roc-cbor, and the handles.
Read : { cbor : Cbor, reader : Cbor.Reader, handles : List(Str) }

Handle := Str.{
	is_eq : _

	## Writes the place of the handle, and adds the handle to the state.
	encoder_for : Wire -> (Handle, Enc -> Try(Enc, err))
	encoder_for = |_| |Handle.(name), { writer, state }|
		match Cbor.encode_u64(state.len(), writer) {
			Ok(after) => Ok({ writer: after, state: state.append(name) })
			Err(e) => Err(e)
		}

	## Reads the place, and gives the handle at that place.
	parser_for : Wire -> (Read -> Try({ value : Handle, rest : Read }, Cbor.Error))
	parser_for = |_| |d| {
		place = Cbor.parse_u64(d.cbor, d.reader)?
		match d.handles.get(place.value) {
			Ok(name) => Ok({ value: Handle.(name), rest: { ..d, reader: place.rest } })
			Err(_) => Err(Cbor.invalid_value(d.cbor, d.reader))
		}
	}
}

## The format: each method is one call of the same method of Cbor.
Wire := [Default].{
	rename_field : Wire, Str -> Str
	rename_field = |_, name| name

	missing_field : Wire, Str -> Cbor.Error
	missing_field = |_, name| MissingRequiredField(name)

	encode_record : Enc, U64, (Cbor.ContainerWith(List(Str)), (Cbor.ContainerWith(List(Str)), Str, (Enc -> Try(Enc, err)) -> Try(Cbor.ContainerWith(List(Str)), err)) -> Try(Cbor.ContainerWith(List(Str)), err)) -> Try(Enc, err)
	encode_record = |e, count, write_fields| Cbor.encode_record_carry(e, count, write_fields)

	encode_list : Enc, U64, (Cbor.ContainerWith(List(Str)), (Cbor.ContainerWith(List(Str)), (Enc -> Try(Enc, err)) -> Try(Cbor.ContainerWith(List(Str)), err)) -> Try(Cbor.ContainerWith(List(Str)), err)) -> Try(Enc, err)
	encode_list = |e, count, write_items| Cbor.encode_list_carry(e, count, write_items)

	parse_record_start : Wire, Read -> Try([Counted({ len : U64, rest : Read }), Uncounted(Read)], Cbor.Error)
	parse_record_start = |_, d|
		match Cbor.parse_record_start(d.cbor, d.reader)? {
			Counted({ len, rest }) => Ok(Counted({ len, rest: { ..d, reader: rest } }))
			Uncounted(rest) => Ok(Uncounted({ ..d, reader: rest }))
		}

	parse_record_field : Wire, Encoding.FieldName.FieldNames(_shape), Read -> Try([Field({ field : Encoding.FieldName(_shape), rest : Read }), TryField({ name : Str, rest : Read }), TryFieldCaseless({ name : Str, rest : Read }), Continue(Read), Done(Read)], Cbor.Error)
	parse_record_field = |_, names, d|
		match Cbor.parse_record_field(d.cbor, names, d.reader)? {
			Field({ field, rest }) => Ok(Field({ field, rest: { ..d, reader: rest } }))
			TryField({ name, rest }) => Ok(TryField({ name, rest: { ..d, reader: rest } }))
			TryFieldCaseless({ name, rest }) => Ok(TryFieldCaseless({ name, rest: { ..d, reader: rest } }))
			Continue(rest) => Ok(Continue({ ..d, reader: rest }))
			Done(rest) => Ok(Done({ ..d, reader: rest }))
		}

	parse_record_after_field : Wire, Read -> Try([Continue(Read), Done(Read)], Cbor.Error)
	parse_record_after_field = |_, d|
		match Cbor.parse_record_after_field(d.cbor, d.reader)? {
			Continue(rest) => Ok(Continue({ ..d, reader: rest }))
			Done(rest) => Ok(Done({ ..d, reader: rest }))
		}

	skip_record_field : Wire, Read -> Try(Read, Cbor.Error)
	skip_record_field = |_, d| Ok({ ..d, reader: Cbor.skip_record_field(d.cbor, d.reader)? })

	parse_list_start : Wire, Read -> Try([Counted({ len : U64, rest : Read }), Uncounted(Read)], Cbor.Error)
	parse_list_start = |_, d|
		match Cbor.parse_list_start(d.cbor, d.reader)? {
			Counted({ len, rest }) => Ok(Counted({ len, rest: { ..d, reader: rest } }))
			Uncounted(rest) => Ok(Uncounted({ ..d, reader: rest }))
		}

	parse_list_next : Wire, Read -> Try([Item(Read), Done(Read)], Cbor.Error)
	parse_list_next = |_, d|
		match Cbor.parse_list_next(d.cbor, d.reader)? {
			Item(rest) => Ok(Item({ ..d, reader: rest }))
			Done(rest) => Ok(Done({ ..d, reader: rest }))
		}

	parse_list_after_item : Wire, Read -> Try([Continue(Read), Done(Read)], Cbor.Error)
	parse_list_after_item = |_, d|
		match Cbor.parse_list_after_item(d.cbor, d.reader)? {
			Continue(rest) => Ok(Continue({ ..d, reader: rest }))
			Done(rest) => Ok(Done({ ..d, reader: rest }))
		}
}

Doc : { docs : List(Handle) }

## The payload, and the handles beside it.
send : a -> Try({ bytes : List(U8), handles : List(Str) }, [CountMismatch, DuplicateMapKey, ..err])
	where [a.encoder_for : Wire -> (a, Enc -> Try(Enc, [CountMismatch, DuplicateMapKey, ..err]))]
send = |value| {
	Shape : a
	encode_shape = Shape.encoder_for(Wire.Default)
	e = encode_shape(value, { writer: Cbor.Writer.new({ key_order: Sorted }), state: [] })?
	Ok({ bytes: e.writer.finish()?, handles: e.state })
}

## The value of a payload, with the handles that came beside it.
receive : List(U8), List(Str) -> Try(a, Cbor.Error)
	where [a.parser_for : Wire -> (Read -> Try({ value : a, rest : Read }, Cbor.Error))]
receive = |bytes, handles| {
	start = Cbor.Reader.new(bytes, { key_order: Sorted, unknown_fields: Reject })?
	Shape : a
	parse_shape = Shape.parser_for(Wire.Default)
	parsed = parse_shape({ cbor: start.cbor, reader: start.reader, handles })?
	parsed.rest.reader.finish()?
	Ok(parsed.value)
}

doc : Doc
doc = { docs: [Handle.("a.txt"), Handle.("b.txt")] }

## {"docs": [0, 1]}, and the two handles beside it.
expect send(doc) == Ok({ bytes: [0xa1, 0x64, 0x64, 0x6f, 0x63, 0x73, 0x82, 0x00, 0x01], handles: ["a.txt", "b.txt"] })

## The payload reads back with the handles.
expect {
	back : Try(Doc, _)
	back = receive([0xa1, 0x64, 0x64, 0x6f, 0x63, 0x73, 0x82, 0x00, 0x01], ["a.txt", "b.txt"])
	back == Ok(doc)
}

## A place with no handle is an error at the place.
expect {
	back : Try(Doc, _)
	back = receive([0xa1, 0x64, 0x64, 0x6f, 0x63, 0x73, 0x82, 0x00, 0x01], ["a.txt"])
	back == Err(InvalidCbor(8))
}

## Bytes after the item are an error at the first of them.
expect {
	back : Try(Doc, _)
	back = receive([0xa1, 0x64, 0x64, 0x6f, 0x63, 0x73, 0x80, 0x00], [])
	back == Err(InvalidCbor(7))
}

main! = |_args| {
	sent = send(doc) ? |_| Exit(1)
	echo!("payload: ${Str.inspect(sent.bytes)}, handles: ${Str.inspect(sent.handles)}\n")
	back : Try(Doc, _)
	back = receive(sent.bytes, sent.handles)
	match back {
		Ok(d) if d == doc => {
			echo!("read back: the same value\n")
			Ok({})
		}
		_ => {
			echo!("read back: a different value\n")
			Err(Exit(1))
		}
	}
}
