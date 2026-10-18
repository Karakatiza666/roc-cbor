app [] { pkg: "../src/main.roc" }

# The short where aliases Cbor.Readable and Cbor.Writable, used in generic helpers
# through the public API of the package, as an app of a peer uses them.

import pkg.Cbor

Row : { id : U64, name : Str }

## A type of your own with a hand-written reader. Its error type is closed.
Id := U64.{
	is_eq : _
	encoder_for : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Id, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| {
		inner = U64.parser_for(encoding)
		|state| {
			parsed = inner(state)?
			Ok({ value: Id.(parsed.value), rest: parsed.rest })
		}
	}
}

## A function with Readable. It matches MissingRequiredField(field) and InvalidCbor(pos) in the generic code.
read_text : List(U8) -> Try(a, Str) where [a.Cbor.Readable(errs)]
read_text = |bytes|
	match Cbor.parse(bytes) {
		Ok(v) => Ok(v)
		Err(MissingRequiredField(field)) => Err("missing ${field}")
		Err(InvalidCbor(pos)) => Err("invalid at ${pos.to_str()}")
		Err(_) => Err("other")
	}

## A function with Writable.
write_all : List(a) -> List(List(U8)) where [a.Cbor.Writable]
write_all = |items| items.map(|item| Cbor.encode(item))

## Readable and Writable in one function: the round trip of a value.
round_trips : a -> Bool where [a.is_eq : a, a -> Bool, a.Cbor.Writable, a.Cbor.Readable(errs)]
round_trips = |value| {
	back : Try(a, _)
	back = Cbor.parse(Cbor.encode(value))
	match back {
		Ok(v) => v == value
		Err(_) => Bool.False
	}
}

## A function with Parseable, and a function with Readable that calls it.
parseable_inner : List(U8) -> Try(a, [InvalidCbor(U64), ..errs]) where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]
parseable_inner = |bytes| Cbor.parse(bytes)

via_parseable : List(U8) -> Try(a, [InvalidCbor(U64), MissingRequiredField(Str), ..errs]) where [a.Cbor.Readable(errs)]
via_parseable = |bytes| parseable_inner(bytes)

# Readable works for a record (MissingRequiredField and InvalidCbor)
expect {
	ok : Try(Row, Str)
	ok = read_text(Cbor.encode({ id: 7.U64, name: "a" }))
	absent : Try(Row, Str)
	absent = read_text(Cbor.encode({ id: 7.U64 }))
	wrong : Try(Row, Str)
	wrong = read_text([0x01])
	ok == Ok({ id: 7, name: "a" }) and absent == Err("missing name") and wrong == Err("invalid at 0")
}

# Readable works for List(Row), List(I64), Cbor.Bytes and a closed custom parser
expect {
	rows : Try(List(Row), Str)
	rows = read_text(Cbor.encode([{ id: 1.U64, name: "a" }]))
	missing_in_list : Try(List(Row), Str)
	missing_in_list = read_text(Cbor.encode([{ id: 1.U64 }]))
	nums : Try(List(I64), Str)
	nums = read_text(Cbor.encode([1.I64, -2]))
	bytes : Try(Cbor.Bytes, Str)
	bytes = read_text(Cbor.encode(Cbor.Bytes.([1, 2])))
	id : Try(Id, Str)
	id = read_text(Cbor.encode(5.U64))
	bad_id : Try(Id, Str)
	bad_id = read_text([0x61, 0x61])
	rows == Ok([{ id: 1, name: "a" }]) and missing_in_list == Err("missing name") and nums == Ok([1, -2]) and bytes == Ok(Cbor.Bytes.([1, 2])) and id == Ok(Id.(5)) and bad_id == Err("invalid at 0")
}

# Writable works for a record, a list, Cbor.Bytes and a custom type
expect {
	rows = write_all([{ id: 1.U64, name: "a" }])
	nums = write_all([[1.I64, 2]])
	bytes = write_all([Cbor.Bytes.([1, 2])])
	ids = write_all([Id.(5)])
	rows == [Cbor.encode({ id: 1.U64, name: "a" })] and nums == [[0x82, 0x01, 0x02]] and bytes == [[0x42, 0x01, 0x02]] and ids == [[0x05]]
}

# Writable and Readable in one function
expect round_trips({ id: 7.U64, name: "a" }) and round_trips([1.I64, -2]) and round_trips(Cbor.Bytes.([9])) and round_trips(Id.(3))

# a function with Readable calls a function with Parseable
expect {
	ok : Try(Row, _)
	ok = via_parseable(Cbor.encode({ id: 7.U64, name: "a" }))
	absent : Try(Row, _)
	absent = via_parseable(Cbor.encode({ id: 7.U64 }))
	ok == Ok({ id: 7, name: "a" }) and absent == Err(MissingRequiredField("name"))
}
