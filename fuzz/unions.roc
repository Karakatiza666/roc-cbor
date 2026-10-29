app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Fuzz
import pkg.Cbor

# L1 target: tag unions in the internal form (the option unions) and a type with Cbor.parse_union.
# For random values of tag unions with each kind of payload, and a random layout of the keys:
# the internal form of the value reads the value back with `unions: Internal`, and the external form
# (the form of the writer) reads it back with the default options. A type with Cbor.parse_union reads
# its tag names in upper snake case, and keeps the layout of the parse for its payloads.

Kind : [Empty, One(U32), Two(Str, I16)]

## A union with each kind of payload: none, a record, one item, two items, a union, a list of unions.
Shape : [Dot, Box({ w : U32, label : Str }), Size(U64), Span(I64, Str), Nest(Kind), Many(List(Kind))]

## A type with its own tag names: upper snake case, read with Cbor.parse_union and written by hand.
Act := [Create, NotFound, SetMode(Kind), V2].{
	is_eq : _

	parser_for : Cbor -> (Cbor.State -> Try({ value : Act, rest : Cbor.State }, [InvalidCbor(U64), MissingRequiredField(Str)]))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { tags: Upper }, state)?
		Ok({ value: Act.(parsed.value), rest: parsed.rest })
	}

	encoder_for : Cbor -> (Act, List(U8) -> Try(List(U8), []))
	encoder_for = |_| |act, out| Cbor.encode_item(act_value(External, act), out)
}

Sample : { shape : Shape, shapes : List(Shape), act : Act, acts : List(Act) }

## The keys of an internal tag, and the order of the keys in a map: the tag key first or last, with another key or not.
Layout : { tag : Str, content : Str, last : Bool, extra : Bool }

kind : Fuzz.Generator(Kind)
kind = Fuzz.map(
	{ pick: Fuzz.u8, n: Fuzz.u64, s: Fuzz.str }.Fuzz,
	|g|
		match g.pick % 3 {
			0 => Empty
			1 => One(g.n.to_u32_wrap())
			_ => Two(g.s, g.n.to_i16_wrap())
		},
)

shape : Fuzz.Generator(Shape)
shape = Fuzz.map(
	{ pick: Fuzz.u8, n: Fuzz.u64, s: Fuzz.str, k: kind, ks: Fuzz.list(kind, 3) }.Fuzz,
	|g|
		match g.pick % 6 {
			0 => Dot
			1 => Box({ w: g.n.to_u32_wrap(), label: g.s })
			2 => Size(g.n)
			3 => Span(g.n.to_i64_wrap(), g.s)
			4 => Nest(g.k)
			_ => Many(g.ks)
		},
)

act : Fuzz.Generator(Act)
act = Fuzz.map(
	{ pick: Fuzz.u8, k: kind }.Fuzz,
	|g|
		match g.pick % 4 {
			0 => Act.Create
			1 => Act.NotFound
			2 => Act.SetMode(g.k)
			_ => Act.V2
		},
)

## The tag key and the content key are never equal, and never a field of a record payload.
layout : Fuzz.Generator(Layout)
layout = Fuzz.map(
	{ pick: Fuzz.u8, last: Fuzz.u8, extra: Fuzz.u8 }.Fuzz,
	|g| {
		tag: ["kind", "t", "type"].get((g.pick % 3).to_u64()) ?? "kind",
		content: ["value", "c", "data"].get((g.pick // 3 % 3).to_u64()) ?? "value",
		last: g.last % 2 == 0,
		extra: g.extra % 2 == 0,
	},
)

## A map with text keys.
obj : List((Str, Cbor.Value)) -> Cbor.Value
obj = |pairs| Cbor.Value.Map(pairs.map(|(k, v)| (Cbor.Value.Text(k), v)))

## A tag in the layout. External: text with no payload, else a map of one entry. Internal: text with no
## payload (a map with `extra`), else a map with the tag key, the entries of `fields` and maybe another key.
tag_value : [External, Internal(Layout)], Str, List((Str, Cbor.Value)) -> Cbor.Value
tag_value = |unions, name, fields|
	match unions {
		External =>
			match fields {
				[] => Cbor.Value.Text(name)
				[(_, v), ..] => obj([(name, v)])
			}
		Internal(l) => {
			others = if (l.extra) fields.append(("zz", Cbor.Value.Null)) else fields
			if fields.is_empty() and !l.extra {
				Cbor.Value.Text(name)
			} else if l.last {
				obj(others.append((l.tag, Cbor.Value.Text(name))))
			} else {
				obj(others.prepend((l.tag, Cbor.Value.Text(name))))
			}
		}
	}

## The key of one payload that is not a record. External ignores it.
content : [External, Internal(Layout)] -> Str
content = |unions|
	match unions {
		External => "_"
		Internal(l) => l.content
	}

kind_value : [External, Internal(Layout)], Kind -> Cbor.Value
kind_value = |u, k|
	match k {
		Empty => tag_value(u, "Empty", [])
		One(n) => tag_value(u, "One", [(content(u), Int(n.to_i128()))])
		Two(s, i) => tag_value(u, "Two", [(content(u), Array([Text(s), Int(i.to_i128())]))])
	}

## A record payload is the map itself in the internal form, and one item in the external form.
shape_value : [External, Internal(Layout)], Shape -> Cbor.Value
shape_value = |u, v|
	match v {
		Dot => tag_value(u, "Dot", [])
		Box(r) => {
			fields = [("w", Cbor.Value.Int(r.w.to_i128())), ("label", Cbor.Value.Text(r.label))]
			match u {
				External => obj([("Box", obj(fields))])
				Internal(_) => tag_value(u, "Box", fields)
			}
		}
		Size(n) => tag_value(u, "Size", [(content(u), Int(n.to_i128()))])
		Span(i, s) => tag_value(u, "Span", [(content(u), Array([Int(i.to_i128()), Text(s)]))])
		Nest(k) => tag_value(u, "Nest", [(content(u), kind_value(u, k))])
		Many(ks) => tag_value(u, "Many", [(content(u), Array(ks.map(|k| kind_value(u, k))))])
	}

act_value : [External, Internal(Layout)], Act -> Cbor.Value
act_value = |u, a|
	match a {
		Act.Create => tag_value(u, "CREATE", [])
		Act.NotFound => tag_value(u, "NOT_FOUND", [])
		Act.SetMode(k) => tag_value(u, "SET_MODE", [(content(u), kind_value(u, k))])
		Act.V2 => tag_value(u, "V2", [])
	}

sample_value : [External, Internal(Layout)], Sample -> Cbor.Value
sample_value = |u, s|
	obj([
		("shape", shape_value(u, s.shape)),
		("shapes", Cbor.Value.Array(s.shapes.map(|x| shape_value(u, x)))),
		("act", act_value(u, s.act)),
		("acts", Cbor.Value.Array(s.acts.map(|x| act_value(u, x)))),
	])

test! : { sample : Sample, layout : Layout } => Fuzz.Outcome
test! = |g| {
	value = g.sample
	# The writer gives the external form, and it reads back.
	back : Try(Sample, _)
	back = Cbor.parse(Cbor.encode(value))
	external : Try(Sample, _)
	external = Cbor.parse(Cbor.encode(sample_value(External, value)))
	# The internal form reads back with the option unions.
	internal : Try(Sample, _)
	internal = Cbor.parse_with(Cbor.encode(sample_value(Internal(g.layout), value)), { unions: Internal({ tag: g.layout.tag, content: g.layout.content }) })
	if (back == Ok(value) and external == back and internal == back) Fuzz.keep else crash "a union did not read back"
}

target = Fuzz.target_with!({
	name: "unions",
	generator: {
		sample: { shape, shapes: Fuzz.list(shape, 3), act, acts: Fuzz.list(act, 3) }.Fuzz,
		layout,
	}.Fuzz,
	test!,
	show: |g| Str.inspect(g),
})
