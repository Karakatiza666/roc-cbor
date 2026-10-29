app [] { pkg: "../src/main.roc" }

# Tag unions with an internal tag, and the options of one union type (0.4.0), through the public API of the package.
# The option `unions: Internal({ tag, content })` reads `{ tag: "Card", ..payload }`. `Cbor.parse_union` gives
# one union type its own layout and the case of its tag names. The writer writes the external form only.
# The bytes of each input come from a Cbor.Value, so that the order of the keys is exact.

import pkg.Cbor

# Helpers

t : Str -> Cbor.Value
t = |s| Text(s)

n : I128 -> Cbor.Value
n = |i| Int(i)

## The bytes of a map with text keys.
map : List((Str, Cbor.Value)) -> List(U8)
map = |pairs| Cbor.encode(Cbor.Value.Map(pairs.map(|(k, v)| (t(k), v))))

## A map with text keys, as a Cbor.Value.
obj : List((Str, Cbor.Value)) -> Cbor.Value
obj = |pairs| Cbor.Value.Map(pairs.map(|(k, v)| (t(k), v)))

kind : Cbor.Unions
kind = Internal({ tag: "kind", content: "value" })

internal : Cbor.Options
internal = { unions: kind }

# Types of an app

Card : { last4 : Str }

Pay : [Cash, Card(Card), Check(U64), Wire(Str, U64)]

Row : { id : Str, pay : Pay }

# The four shapes of a payment in a row

## No payload: the text.
expect {
	r : Try(Row, _)
	r = Cbor.parse_with(map([("id", t("a")), ("pay", t("Cash"))]), internal)
	r == Ok({ id: "a", pay: Cash })
}

## No payload: a map with the tag key only, and with other keys.
expect {
	r : Try(List(Pay), _)
	r = Cbor.parse_with(Cbor.encode(Cbor.Value.Array([obj([("kind", t("Cash"))]), obj([("note", n(1)), ("kind", t("Cash"))])])), internal)
	r == Ok([Cash, Cash])
}

## One record payload: the map itself. The tag key is not a field of the record.
expect {
	r : Try(Row, _)
	r = Cbor.parse_with(map([("id", t("a")), ("pay", obj([("kind", t("Card")), ("last4", t("4242"))]))]), internal)
	r == Ok({ id: "a", pay: Card({ last4: "4242" }) })
}

## One payload of another type: the item at the content key.
expect {
	r : Try(Row, _)
	r = Cbor.parse_with(map([("id", t("a")), ("pay", obj([("kind", t("Check")), ("value", n(7))]))]), internal)
	r == Ok({ id: "a", pay: Check(7) })
}

## Two payloads: an array at the content key. The keys can be in any order.
expect {
	r : Try(Row, _)
	r = Cbor.parse_with(map([("id", t("a")), ("pay", obj([("value", Array([t("eu"), n(9)])), ("kind", t("Wire"))]))]), internal)
	r == Ok({ id: "a", pay: Wire("eu", 9) })
}

## Another key in the map of a payload is skipped.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with(map([("kind", t("Check")), ("at", t("x")), ("value", n(7)), ("more", Array([n(1)]))]), internal)
	r == Ok(Check(7))
}

## The type of the payload decides: the same bytes read as a record with a field `value`, and as a U64.
expect {
	bytes = map([("kind", t("Check")), ("value", n(7))])
	as_record : Try([Check({ value : U64 })], _)
	as_record = Cbor.parse_with(bytes, internal)
	as_number : Try([Check(U64)], _)
	as_number = Cbor.parse_with(bytes, internal)
	as_record == Ok(Check({ value: 7 })) and as_number == Ok(Check(7))
}

## Other names for the keys.
expect {
	r : Try(List([Point({ x : I64 }), Size(U64), Pair(Str, Str)]), _)
	r = Cbor.parse_with(
		Cbor.encode(Cbor.Value.Array([obj([("type", t("Point")), ("x", n(-3))]), obj([("type", t("Size")), ("data", n(4))]), obj([("data", Array([t("a"), t("b")])), ("type", t("Pair"))])])),
		{ unions: Internal({ tag: "type", content: "data" }) },
	)
	r == Ok([Point({ x: -3 }), Size(4), Pair("a", "b")])
}

# One payload that is not a record: each reader goes to the content key

## A Dict is not a record: it is at the content key, not the map itself.
expect {
	r : Try([Counts(Dict(Str, U64))], _)
	r = Cbor.parse_with(map([("kind", t("Counts")), ("value", obj([("a", n(1)), ("b", n(2))]))]), internal)
	r == Ok(Counts(Dict.from_list([("a", 1), ("b", 2)])))
}

## A list, a tuple, text, a Bool, a Dec and a Try(a, [Null]).
expect {
	r : Try(List([Tags(List(Str)), Pos((I64, I64)), Name(Str), On(Bool), Price(Dec), Maybe(Try(U64, [Null]))]), _)
	r = Cbor.parse_with(
		Cbor.encode(
			Cbor.Value.Array([
				obj([("kind", t("Tags")), ("value", Array([t("x"), t("y")]))]),
				obj([("kind", t("Pos")), ("value", Array([n(1), n(-2)]))]),
				obj([("kind", t("Name")), ("value", t("ann"))]),
				obj([("kind", t("On")), ("value", n(1))]),
				obj([("kind", t("Price")), ("value", n(5))]),
				obj([("kind", t("Maybe")), ("value", Null)]),
			]),
		),
		internal,
	)
	r == Ok([Tags(["x", "y"]), Pos((1, -2)), Name("ann"), On(Bool.True), Price(5), Maybe(Err(Null))])
}

## A Cbor.Value and Cbor.Bytes.
expect {
	r : Try(List([Any(Cbor.Value), Blob(Cbor.Bytes)]), _)
	r = Cbor.parse_with(
		Cbor.encode(Cbor.Value.Array([obj([("kind", t("Any")), ("value", Tag(6, n(1)))]), obj([("kind", t("Blob")), ("value", Bytes([1, 2]))])])),
		internal,
	)
	r == Ok([Any(Tag(6, n(1))), Blob(Cbor.Bytes.([1, 2]))])
}

## A type of an app that reads a tag (Cbor.parse_cbor_tag) or picks its reader (Cbor.peek).
Id := U64.{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Id, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state| {
		tag = Cbor.parse_cbor_tag(encoding, state)?
		if tag.value != 37 {
			return Err(Cbor.invalid_value(encoding, state))
		}
		number = Cbor.parse_u64(encoding, tag.rest)?
		Ok({ value: Id.(number.value), rest: number.rest })
	}
}

Cell := [Number(I64), Word(Str)].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Cell, rest : Cbor.State }, [InvalidCbor(U64)]))
	parser_for = |encoding| |state|
		match Cbor.peek(encoding, state)? {
			Int => {
				i = Cbor.parse_i64(encoding, state)?
				Ok({ value: Cell.Number(i.value), rest: i.rest })
			}
			Text => {
				s = Cbor.parse_str(encoding, state)?
				Ok({ value: Cell.Word(s.value), rest: s.rest })
			}
			_ => Err(Cbor.invalid_value(encoding, state))
		}
}

expect {
	r : Try(List([Ref(Id), Put(Cell)]), _)
	r = Cbor.parse_with(
		Cbor.encode(Cbor.Value.Array([obj([("kind", t("Ref")), ("value", Tag(37, n(9)))]), obj([("kind", t("Put")), ("value", t("w"))]), obj([("value", n(-4)), ("kind", t("Put"))])])),
		internal,
	)
	r == Ok([Ref(Id.(9)), Put(Cell.Word("w")), Put(Cell.Number(-4))])
}

# Nested unions

## A union in the payload of a union: the inner map is at the content key. A union in a record payload.
expect {
	r : Try(List([Wrap(Pay), Box({ inner : Pay, n : U64 })]), _)
	r = Cbor.parse_with(
		Cbor.encode(
			Cbor.Value.Array([
				obj([("kind", t("Wrap")), ("value", obj([("kind", t("Check")), ("value", n(3))]))]),
				obj([("kind", t("Box")), ("inner", obj([("kind", t("Card")), ("last4", t("1"))])), ("n", n(2))]),
				obj([("kind", t("Wrap")), ("value", t("Cash"))]),
			]),
		),
		internal,
	)
	r == Ok([Wrap(Check(3)), Box({ inner: Card({ last4: "1" }), n: 2 }), Wrap(Cash)])
}

## A recursive type of an app.
Tree := [Leaf(U64), Node(List(Tree))].{
	is_eq : _
	parser_for : _
}

expect {
	r : Try(Tree, _)
	r = Cbor.parse_with(map([("kind", t("Node")), ("value", Array([obj([("kind", t("Leaf")), ("value", n(1))]), obj([("kind", t("Node")), ("value", Array([]))])]))]), internal)
	r == Ok(Tree.Node([Tree.Leaf(1), Tree.Node([])]))
}

## No content key in the map of a recursive union is an error, not a loop.
expect {
	r : Try(Tree, _)
	r = Cbor.parse_with(map([("kind", t("Node"))]), internal)
	r == Err(InvalidCbor(0))
}

# The options of the parse

## A tag of ignore_tags before the map, and before the item at the content key.
expect {
	r : Try(List(Pay), _)
	r = Cbor.parse_with(
		Cbor.encode(Cbor.Value.Array([Tag(6, obj([("kind", t("Check")), ("value", Tag(6, n(7)))])), Tag(6, obj([("kind", t("Card")), ("last4", Tag(6, t("9")))]))])),
		{ unions: kind, ignore_tags: [6] },
	)
	r == Ok([Check(7), Card({ last4: "9" })])
}

## Camel field names and integers from text, also in a record payload.
expect {
	r : Try([Card({ last_four : U64 })], _)
	r = Cbor.parse_with(map([("kind", t("Card")), ("lastFour", t("42"))]), { unions: kind, fields: Camel, int_from_text: Bool.True })
	r == Ok(Card({ last_four: 42 }))
}

## A null value in a record payload is no key (rule N1).
expect {
	r : Try([Card({ last4 : Try(Str, [Missing]) })], _)
	r = Cbor.parse_with(map([("kind", t("Card")), ("last4", Null)]), internal)
	r == Ok(Card({ last4: Err(Missing) }))
}

# Errors

## No tag key: an error at the map. The external form does not read with Internal.
expect {
	r : Try(Row, _)
	r = Cbor.parse_with(map([("id", t("a")), ("pay", obj([("Check", n(7))]))]), internal)
	# a2 62 69 64 61 61 63 70 61 79: the map of the payment is at 10.
	r == Err(InvalidCbor(10))
}

## The tag key is not text.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with(map([("kind", n(1))]), internal)
	r == Err(InvalidCbor(6))
}

## A tag name that the type does not have.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with(map([("kind", t("Gold"))]), internal)
	r == Err(InvalidCbor(0))
}

## One payload of another type with no content key: an error at the map.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with(map([("kind", t("Check"))]), internal)
	r == Err(InvalidCbor(0))
}

## A Cbor.Value or a Dict with no content key: an error at the map, not the map itself.
expect {
	r1 : Try([Any(Cbor.Value)], _)
	r1 = Cbor.parse_with(map([("kind", t("Any"))]), internal)
	r2 : Try([Counts(Dict(Str, Str))], _)
	r2 = Cbor.parse_with(map([("kind", t("Counts"))]), internal)
	r1 == Err(InvalidCbor(0)) and r2 == Err(InvalidCbor(0))
}

## Two payloads: no content key, an item that is not an array, an array of another length.
expect {
	r1 : Try(Pay, _)
	r1 = Cbor.parse_with(map([("kind", t("Wire"))]), internal)
	r2 : Try(Pay, _)
	r2 = Cbor.parse_with(map([("kind", t("Wire")), ("value", t("eu"))]), internal)
	r3 : Try(Pay, _)
	r3 = Cbor.parse_with(map([("kind", t("Wire")), ("value", Array([t("eu")]))]), internal)
	# a2 64 6b 69 6e 64 64 57 69 72 65 65 76 61 6c 75 65: the content is at 17.
	r1 == Err(InvalidCbor(0)) and r2 == Err(InvalidCbor(17)) and r3 == Err(InvalidCbor(17))
}

## Text for a tag with payloads.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with(Cbor.encode(t("Check")), internal)
	r == Err(InvalidCbor(6))
}

## A key that is not text in the map, before the tag key: an error at the map.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with(Cbor.encode(Cbor.Value.Map([(n(1), n(2)), (t("kind"), t("Cash"))])), internal)
	r == Err(InvalidCbor(0))
}

## path_at gives the path to the error in the content.
expect {
	bytes = map([("id", t("a")), ("pay", obj([("kind", t("Check")), ("value", t("x"))]))])
	r : Try(Row, _)
	r = Cbor.parse_with(bytes, internal)
	match r {
		Err(InvalidCbor(pos)) => Cbor.path_at(bytes, pos) == Ok([Key("pay"), Key("value")])
		_ => Bool.False
	}
}

# External, the default, does not change

expect {
	r : Try(List(Pay), _)
	r = Cbor.parse(Cbor.encode([Cash, Card({ last4: "1" }), Check(7), Wire("eu", 9)]))
	r == Ok([Cash, Card({ last4: "1" }), Check(7), Wire("eu", 9)])
}

## The internal form is an error with External.
expect {
	r : Try(Pay, _)
	r = Cbor.parse(map([("kind", t("Check")), ("value", n(7))]))
	r == Err(InvalidCbor(0))
}

## The writer writes the external form, also when the reader of the peer reads the internal form.
expect Cbor.encode(Check(7)) == map([("Check", n(7))])

# Cbor.parse_union: the options of one union type

## The actions of a peer, in upper snake case.
Action := [Create, Update, NotFound, V2].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Action, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { tags: Upper }, state)?
		Ok({ value: Action.(parsed.value), rest: parsed.rest })
	}
}

## The operations of a patch, in lower snake case, with an internal tag `op`. The payloads are records.
Op := [Add({ path : Str, value : I64 }), Remove({ path : Str }), MoveTo({ from : Str, path : Str })].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Op, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { unions: Internal({ tag: "op", content: "value" }), tags: Lower }, state)?
		Ok({ value: Op.(parsed.value), rest: parsed.rest })
	}
}

expect {
	r : Try(List(Action), _)
	r = Cbor.parse(Cbor.encode(["CREATE", "UPDATE", "NOT_FOUND", "V2"]))
	r == Ok([Action.Create, Action.Update, Action.NotFound, Action.V2])
}

## A wire name that is not in upper snake case: the Roc name, small letters, two `_`, a `_` at an end.
expect {
	bad : List(Str)
	bad = ["Create", "create", "NOT__FOUND", "_CREATE", "CREATE_", "NOT-FOUND", ""]
	bad.all(
		|wire| {
			r : Try(Action, _)
			r = Cbor.parse(Cbor.encode(wire))
			r == Err(InvalidCbor(0))
		},
	)
}

expect {
	r : Try(List(Op), _)
	r = Cbor.parse(
		Cbor.encode(
			Cbor.Value.Array([
				obj([("op", t("add")), ("path", t("/a")), ("value", n(1))]),
				obj([("op", t("remove")), ("path", t("/b"))]),
				obj([("from", t("/c")), ("op", t("move_to")), ("path", t("/d"))]),
			]),
		),
	)
	r == Ok([Op.Add({ path: "/a", value: 1 }), Op.Remove({ path: "/b" }), Op.MoveTo({ from: "/c", path: "/d" })])
}

## Lower: a capital letter is an error.
expect {
	r : Try(Op, _)
	r = Cbor.parse(map([("op", t("Remove")), ("path", t("/b"))]))
	r == Err(InvalidCbor(0))
}

## The options are for the one union. A sibling union and a union in the payload keep the options of the parse.
Notice : { action : Action, inner : [Create, Other], op : Op, ops : List(Op), pay : Pay }

expect {
	bytes = map([
		("action", t("NOT_FOUND")),
		("inner", t("Create")),
		("op", obj([("op", t("add")), ("path", t("/a")), ("value", n(1))])),
		("ops", Array([obj([("op", t("remove")), ("path", t("/x"))])])),
		("pay", obj([("Check", n(7))])),
	])
	r : Try(Notice, _)
	r = Cbor.parse(bytes)
	r == Ok({ action: Action.NotFound, inner: Create, op: Op.Add({ path: "/a", value: 1 }), ops: [Op.Remove({ path: "/x" })], pay: Check(7) })
}

## A sibling union does not get the case of Action.
expect {
	r : Try({ action : Action, inner : [Create, Other] }, _)
	r = Cbor.parse(map([("action", t("CREATE")), ("inner", t("CREATE"))]))
	# a2 66 61 63 74 69 6f 6e 66 43 52 45 41 54 45 65 69 6e 6e 65 72: the value of inner is at 21.
	r == Err(InvalidCbor(21))
}

## A union of one type with its own layout in a parse with another: the payload of Op reads with the parse.
Step := [Run(Pay), Stop].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Step, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { unions: External, tags: Upper }, state)?
		Ok({ value: Step.(parsed.value), rest: parsed.rest })
	}
}

expect {
	r : Try(List(Step), _)
	r = Cbor.parse_with(
		Cbor.encode(Cbor.Value.Array([obj([("RUN", obj([("kind", t("Check")), ("value", n(7))]))]), t("STOP")])),
		internal,
	)
	r == Ok([Step.Run(Check(7)), Step.Stop])
}

## When the type is not a tag union, the options have no effect: the union in the record keeps the parse.
Wrapper := { a : [Create, Delete] }.{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Wrapper, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { tags: Upper }, state)?
		Ok({ value: Wrapper.(parsed.value), rest: parsed.rest })
	}
}

expect {
	r1 : Try(Wrapper, _)
	r1 = Cbor.parse(map([("a", t("Delete"))]))
	r2 : Try(Wrapper, _)
	r2 = Cbor.parse(map([("a", t("DELETE"))]))
	r1 == Ok(Wrapper.{ a: Delete }) and r2 == Err(InvalidCbor(3))
}

## An omitted `unions` keeps the layout of the parse.
Mode := [Fast, SlowDown(U64)].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Mode, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { tags: Lower }, state)?
		Ok({ value: Mode.(parsed.value), rest: parsed.rest })
	}
}

expect {
	r1 : Try(Mode, _)
	r1 = Cbor.parse_with(map([("kind", t("slow_down")), ("value", n(3))]), internal)
	r2 : Try(Mode, _)
	r2 = Cbor.parse(map([("slow_down", n(3))]))
	r1 == Ok(Mode.SlowDown(3)) and r2 == Ok(Mode.SlowDown(3))
}

## A type with Cbor.parse_union as the one payload of an internal tag: it reads the item at the content key.
expect {
	r : Try([Did(Action)], _)
	r = Cbor.parse_with(map([("kind", t("Did")), ("value", t("UPDATE"))]), internal)
	r == Ok(Did(Action.Update))
}

## An annotated record of union options in a let.
expect {
	opts : Cbor.UnionOptions
	opts = { tags: Upper }
	opts.?tags == Ok(Upper)
}
