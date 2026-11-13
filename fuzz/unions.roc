app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.6.1/GDoZFRDnzMRiVk9nE8wdWn52btGsM1GhcY9VDKqy9f1Y.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Arbitrary
import fuzz.Fuzz
import pkg.Cbor

# L1 target: tag unions in the internal form (the option unions) and a type with Cbor.parse_union.
# For random values of tag unions with each kind of payload, and a random layout of the keys:
# the internal form of the value reads the value back with `unions: Internal`, and the external form
# (the form of the writer) reads it back with the default options. A type with Cbor.parse_union reads
# its tag names in upper snake case, and keeps the layout of the parse for its payloads.
# A decoy tag key before the tag key: an error with the default duplicate_keys (Reject), the real tag with
# duplicate_keys: Last. Cbor.sql_rows changes nothing.

Kind : [Empty, One(U32), Two(Str, I16)]

## A union with each kind of payload: none, a record, one item, two items, a union, a list of unions.
Shape : [Dot, Box({ w : U32, label : Str }), Size(U64), Span(I64, Str), Nest(Kind), Many(List(Kind))]

## A type with its own tag names: upper snake case, read with Cbor.parse_union and written by hand.
Act := [Create, NotFound, SetMode(Kind), V2].{
	is_eq : _

	parser_for : Cbor -> (Cbor.Reader -> Try({ value : Act, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		parsed = Cbor.parse_union(encoding, { tags: Upper }, state)?
		Ok({ value: Act.(parsed.value), rest: parsed.rest })
	}

	encoder_for : Cbor -> (Act, Cbor.Writer -> Try(Cbor.Writer, []))
	encoder_for = |_| |act, w| Cbor.encode_item(act_value(External, act), w)
}

Sample : { shape : Shape, shapes : List(Shape), act : Act, acts : List(Act) }

## The keys of an internal tag, and the order of the keys in a map: the tag key first or last, with another key or not,
## and with a decoy instance of the tag key before it or not.
Layout : { tag : Str, content : Str, last : Bool, extra : Bool, decoy : Bool }

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
	{ pick: Fuzz.u8, last: Fuzz.u8, extra: Fuzz.u8, decoy: Fuzz.u8 }.Fuzz,
	|g| {
		tag: ["kind", "t", "type"].get((g.pick % 3).to_u64()) ?? "kind",
		content: ["value", "c", "data"].get((g.pick // 3 % 3).to_u64()) ?? "value",
		last: g.last % 2 == 0,
		extra: g.extra % 2 == 0,
		decoy: g.decoy % 4 == 0,
	},
)

## Items with maps of text keys that can repeat (a decoy tag key). A Cbor.Value map has no duplicate key,
## so this type writes its maps with Cbor.encode_record.
Doc := [Obj(List((Str, Doc))), Arr(List(Doc)), Leaf(Cbor.Value)].{
	encoder_for : Cbor -> (Doc, Cbor.Writer -> Try(Cbor.Writer, []))
	encoder_for = |_| |doc, w|
		match doc {
			Obj(pairs) =>
				Cbor.encode_record(
					w,
					pairs.len(),
					|start, add| {
						var $c = start
						for (k, v) in pairs {
							$c = add($c, k, |inner| Cbor.encode_item(v, inner))?
						}
						Ok($c)
					},
				)
			Arr(items) =>
				Cbor.encode_list(
					w,
					items.len(),
					|start, add| {
						var $c = start
						for v in items {
							$c = add($c, |inner| Cbor.encode_item(v, inner))?
						}
						Ok($c)
					},
				)
			Leaf(v) => Cbor.encode_item(v, w)
		}
}

## A map with text keys.
obj : List((Str, Doc)) -> Doc
obj = |pairs| Doc.Obj(pairs)

text : Str -> Doc
text = |s| Doc.Leaf(Text(s))

int : I64 -> Doc
int = |i| Doc.Leaf(Int(Cbor.IntValue.from_i64(i)))

## A tag in the layout. External: text with no payload, else a map of one entry. Internal: text with no
## payload (a map with `extra`), else a map with the tag key, the entries of `fields` and maybe another key.
tag_value : [External, Internal(Layout)], Str, List((Str, Doc)) -> Doc
tag_value = |unions, name, fields|
	match unions {
		External =>
			match fields {
				[] => text(name)
				[(_, v), ..] => obj([(name, v)])
			}
		Internal(l) => {
			others = (if (l.extra) fields.append(("zz", Doc.Leaf(Null))) else fields).concat(if (l.decoy) [(l.tag, text("Decoy"))] else [])
			if fields.is_empty() and !l.extra and !l.decoy {
				text(name)
			} else if l.last {
				obj(others.append((l.tag, text(name))))
			} else {
				obj(others.prepend((l.tag, text(name))))
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

kind_value : [External, Internal(Layout)], Kind -> Doc
kind_value = |u, k|
	match k {
		Empty => tag_value(u, "Empty", [])
		One(n) => tag_value(u, "One", [(content(u), int(n.to_i64()))])
		Two(s, i) => tag_value(u, "Two", [(content(u), Doc.Arr([text(s), int(i.to_i64())]))])
	}

## A record payload is the map itself in the internal form, and one item in the external form.
shape_value : [External, Internal(Layout)], Shape -> Doc
shape_value = |u, v|
	match v {
		Dot => tag_value(u, "Dot", [])
		Box(r) => {
			fields = [("w", int(r.w.to_i64())), ("label", text(r.label))]
			match u {
				External => obj([("Box", obj(fields))])
				Internal(_) => tag_value(u, "Box", fields)
			}
		}
		Size(n) => tag_value(u, "Size", [(content(u), Doc.Leaf(Int(Cbor.IntValue.from_u64(n))))])
		Span(i, s) => tag_value(u, "Span", [(content(u), Doc.Arr([int(i), text(s)]))])
		Nest(k) => tag_value(u, "Nest", [(content(u), kind_value(u, k))])
		Many(ks) => tag_value(u, "Many", [(content(u), Doc.Arr(ks.map(|k| kind_value(u, k))))])
	}

act_value : [External, Internal(Layout)], Act -> Doc
act_value = |u, a|
	match a {
		Act.Create => tag_value(u, "CREATE", [])
		Act.NotFound => tag_value(u, "NOT_FOUND", [])
		Act.SetMode(k) => tag_value(u, "SET_MODE", [(content(u), kind_value(u, k))])
		Act.V2 => tag_value(u, "V2", [])
	}

sample_value : [External, Internal(Layout)], Sample -> Doc
sample_value = |u, s|
	obj([
		("shape", shape_value(u, s.shape)),
		("shapes", Doc.Arr(s.shapes.map(|x| shape_value(u, x)))),
		("act", act_value(u, s.act)),
		("acts", Doc.Arr(s.acts.map(|x| act_value(u, x)))),
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
	# A decoy tag key is before the tag key (`last`), or after the other keys: `Last` reads the tag key when it is last.
	internal_bytes = Cbor.encode(sample_value(Internal(g.layout), value))
	unions = Internal({ tag: g.layout.tag, content: g.layout.content })
	internal : Try(Sample, _)
	internal = Cbor.parse_with(internal_bytes, { unions: unions })
	rows : Try(Sample, _)
	rows = Cbor.parse_with(internal_bytes, { unions, allow: Cbor.sql_rows })
	last : Try(Sample, _)
	last = Cbor.parse_with(internal_bytes, { unions, duplicate_keys: Last })
	ok =
		if g.layout.decoy {
			internal.is_err() and (if (g.layout.last) last == back else last.is_err())
		} else {
			internal == back and last == back
		}
	if (back == Ok(value) and external == back and ok and rows == internal) Fuzz.keep else crash "a union did not read back"
}

## The property's value, from the input bytes: the generator reads them as its entropy, as roc-fuzz's own
## typed inputs do. The value type holds `Cbor` encoders, so it cannot have roc-fuzz's derived input format.
input_of : List(U8) -> { sample : Sample, layout : Layout }
input_of = |bytes| ({ sample: { shape, shapes: Fuzz.list(shape, 3), act, acts: Fuzz.list(act, 3) }.Fuzz, layout }.Fuzz)(Arbitrary.new(bytes)).value

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
	name: "unions",
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || [] }),
		Fuzz.example({ name: "short", revision: "1", make: || [0x01, 0x82, 0x18, 0x2a, 0xa1, 0x61, 0x61, 0x00] }),
		Fuzz.example({ name: "ramp", revision: "1", make: || ramp }),
	],
	generator: Fuzz.raw_bytes,
	test!: |bytes| test!(input_of(bytes)),
	show: |bytes| Str.inspect(input_of(bytes)),
})
