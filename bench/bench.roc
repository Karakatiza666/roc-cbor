app [] { pkg: "../src/main.roc" }

# P25: the benchmark cases. Usage: bench <case> <loops>. scripts/bench.sh builds it with --opt=speed and
# times each case from the shell, because the echo host has no clock. A run with 0 loops is the baseline:
# it builds the input and does no timed work. The output is a checksum, so that the work is not removed.
# The case `calib` does plain Roc work with no CBOR: `bench.sh --check` divides each time by its time.
# The inputs of the parse cases are raw bytes (no Cbor.Value), so the cases build on 0.4.1 and on HEAD.

import pkg.Cbor

# ADAPTER BEGIN: the API of this version. scripts/bench.sh replaces this block for 0.4.1.
# Both versions have Cbor.Bytes (a byte string). A List(U8) (the u8list cases) is a byte string on HEAD,
# and an array of integers on 0.4.1. 0.4.1 has no `unknown_fields` option and builds Value.Int from an I128.
Blob : Cbor.Bytes

to_blob : List(U8) -> Blob
to_blob = |l| Cbor.Bytes.from_list(l)

blob_len : Blob -> U64
blob_len = |b| b.to_list().len()

reject_options : Cbor.Options
reject_options = { unknown_fields: Reject }

value_int : U64 -> Cbor.Value
value_int = |n| Cbor.Value.Int(Cbor.IntValue.from_u64(n))

# ADAPTER END

Rec : { name : Str, id : U64, ok : Bool, score : F64, tags : List(Str) }

CamelRec : { user_name : Str, id : U64, is_ok : Bool, score : F64, tags : List(Str) }

## Rec with 12 more fields: the reader of Rec skips them.
Wide : { name : Str, id : U64, ok : Bool, score : F64, tags : List(Str), u1 : U64, u2 : Str, u3 : List(U64), u4 : Bool, u5 : F64, u6 : Str, u7 : U64, u8 : { a : U64, b : Str }, u9 : Str, u10 : U64, u11 : List(Str), u12 : Str }

Pay : [Cash, Card({ last4 : Str }), Check(U64)]

## `{ "kind": "Node", "value": [child] }` or `{ "kind": "Leaf", "value": n }`.
Tree := [Leaf(U64), Node(List(Tree))].{
	parser_for : _
}

## A CBOR head with the shortest argument (RFC 8949 3).
head : U8, U64 -> List(U8)
head = |major, n| {
	m = major.shl_wrap(5)
	if n < 24 {
		[m + n.to_u8_wrap()]
	} else if n < 0x100 {
		[m + 24, n.to_u8_wrap()]
	} else if n < 0x1_0000 {
		[m + 25, n.shr_zf_wrap(8).to_u8_wrap(), n.to_u8_wrap()]
	} else {
		[m + 26, n.shr_zf_wrap(24).to_u8_wrap(), n.shr_zf_wrap(16).to_u8_wrap(), n.shr_zf_wrap(8).to_u8_wrap(), n.to_u8_wrap()]
	}
}

text : Str -> List(U8)
text = |s| head(3, s.count_utf8_bytes()).concat(s.to_utf8())

map_of : List((List(U8), List(U8))) -> List(U8)
map_of = |entries| entries.fold(head(5, entries.len()), |acc, (k, v)| acc.concat(k).concat(v))

array_of : List(List(U8)) -> List(U8)
array_of = |items| items.fold(head(4, items.len()), |acc, item| acc.concat(item))

## The list of `n` values from `f`.
make : U64, (U64 -> a) -> List(a)
make = |n, f| (0.U64).until(n).fold(List.with_capacity(n), |acc, i| acc.append(f(i)))

## The 10k records. `seed` comes from the args, so the values are not known at compile time.
records : U64 -> List(Rec)
records = |seed| make(10_000, |i| { name: "user-${(i + seed).to_str()}", id: i + seed, ok: i % 2 == 0, score: (i + seed).to_f64() * 1.5, tags: ["a", "b${(i % 7).to_str()}"] })

## 10k records with camelCase keys, as raw bytes: 0.4.1 has no camelCase writer.
camel_bytes : U64 -> List(U8)
camel_bytes = |seed|
	array_of(
		make(
			10_000,
			|i| map_of([
				(text("userName"), text("user-${(i + seed).to_str()}")),
				(text("id"), head(0, i + seed)),
				(text("isOk"), [if (i % 2 == 0) 0xf5 else 0xf4]),
				(text("score"), [0xfb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0]),
				(text("tags"), array_of([text("a"), text("b${(i % 7).to_str()}")])),
			]),
		),
	)

wides : U64 -> List(Wide)
wides = |seed| make(10_000, |i| { name: "user-${(i + seed).to_str()}", id: i + seed, ok: i % 2 == 0, score: 1.5, tags: ["a"], u1: i, u2: "x", u3: [i, i], u4: Bool.True, u5: 0.5, u6: "yy", u7: 7, u8: { a: i, b: "b" }, u9: "z", u10: 10, u11: ["p", "q"], u12: "w" })

## 10k internal-tag unions, tag key first or content key first.
unions_bytes : U64, Bool -> List(U8)
unions_bytes = |seed, tag_first| {
	kind = |name| (text("kind"), text(name))
	item = |i| {
		entries =
			match i % 3 {
				0 => [kind("Cash")]
				1 => [kind("Card"), (text("last4"), text("4242"))]
				_ => [kind("Check"), (text("value"), head(0, i + seed))]
			}
		map_of(if (tag_first) entries else entries.rev())
	}
	array_of(make(10_000, item))
}

## 40 trees of 250 levels, content key first: the tag key of each level is after its subtree.
trees_bytes : U64 -> List(U8)
trees_bytes = |seed| {
	kind_node = text("kind").concat(text("Node"))
	value_one = text("value").concat(head(4, 1))
	tree = |leaf| List.repeat(head(5, 2).concat(value_one), 250).join().concat(map_of([(text("kind"), text("Leaf")), (text("value"), head(0, leaf))])).concat(List.repeat(kind_node, 250).join())
	array_of(make(40, |i| tree(i + seed)))
}

## A Cbor.Value of 500 nested arrays.
deep : U64 -> Cbor.Value
deep = |seed| (0.U64).until(500).fold(value_int(seed), |v, _| Cbor.Value.Array([v]))

## The bytes of 500 nested arrays.
deep_bytes : U64 -> List(U8)
deep_bytes = |seed| List.repeat(head(4, 1), 500).join().concat(head(0, seed))

## A map of 100k text keys.
dict_bytes : U64 -> List(U8)
dict_bytes = |seed| map_of(make(100_000, |i| (text("key-${(i + seed).to_str()}"), head(0, i))))

## 10k text items of multi-byte UTF-8.
texts_bytes : U64 -> List(U8)
texts_bytes = |seed| array_of(make(10_000, |i| text("é漢🎉 user-é漢🎉-ü${(i + seed).to_str()}")))

## Plain Roc work with no CBOR, for the calibration of --check: list appends, integer math, a sort, text.
calib : U64 -> U64
calib = |seed| {
	xs = make(20_000, |i| (i + seed).times_wrap(0x9E37_79B9_7F4A_7C15).shr_zf_wrap(17))
	sorted = xs.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same)
	strs = make(2_000, |i| "item-${(i + seed).to_str()}")
	sorted.fold(0, |acc, x| acc.bitwise_xor(x)) + strs.fold(0, |acc, s| acc + s.count_utf8_bytes())
}

## Runs `work` `loops` times and sums its results.
repeat : U64, (U64 -> U64) -> U64
repeat = |loops, work| {
	var $sum = 0
	for i in (0.U64).until(loops) {
		$sum = $sum.plus_wrap(work(i))
	}
	$sum
}

parse_len : Try(List(a), _) -> U64
parse_len = |r|
	match r {
		Ok(l) => l.len()
		Err(_) => 1_000_000
	}

run : Str, U64, U64 -> Try(U64, [UnknownCase])
run = |case, loops, seed|
	match case {
		"bytes_encode" => {
			b = to_blob(List.repeat(0xab.U8, 1_000_000 + seed))
			Ok(repeat(loops, |_| Cbor.encode(b).len()))
		}
		"bytes_parse" => {
			bytes = Cbor.encode(to_blob(List.repeat(0xab.U8, 1_000_000 + seed)))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Blob, _)
						r = Cbor.parse(bytes)
						r.map_ok(blob_len) ?? 0
					},
				),
			)
		}
		"u8list_encode" => {
			b = List.repeat(0xab.U8, 1_000_000 + seed)
			Ok(repeat(loops, |_| Cbor.encode(b).len()))
		}
		"u8list_parse" => {
			bytes = Cbor.encode(List.repeat(0xab.U8, 1_000_000 + seed))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(U8), _)
						r = Cbor.parse(bytes)
						parse_len(r)
					},
				),
			)
		}
		"records_encode" => {
			rs = records(seed)
			Ok(repeat(loops, |_| Cbor.encode(rs).len()))
		}
		"records_parse" => {
			bytes = Cbor.encode(records(seed))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Rec), _)
						r = Cbor.parse(bytes)
						parse_len(r)
					},
				),
			)
		}
		"records_value" => {
			bytes = Cbor.encode(records(seed))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(bytes)
						if (r.is_ok()) 1 else 0
					},
				),
			)
		}
		"unions_parse" => {
			bytes = unions_bytes(seed, Bool.True)
			options : Cbor.Options
			options = { unions: Internal({ tag: "kind", content: "value" }) }
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Pay), _)
						r = Cbor.parse_with(bytes, options)
						parse_len(r)
					},
				),
			)
		}
		"deep_encode" => {
			v = deep(seed)
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"deep_parse" => {
			bytes = deep_bytes(seed)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(bytes)
						if (r.is_ok()) 1 else 0
					},
				),
			)
		}
		"dict_parse" => {
			bytes = dict_bytes(seed)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Dict(Str, U64), _)
						r = Cbor.parse(bytes)
						match r {
							Ok(d) => d.len()
							Err(_) => 0
						}
					},
				),
			)
		}
		"calib" => Ok(repeat(loops, |i| calib(seed + i)))
		"camel_parse" => {
			bytes = camel_bytes(seed)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(CamelRec), _)
						r = Cbor.parse_with(bytes, { fields: Camel })
						parse_len(r)
					},
				),
			)
		}
		"reject_parse" => {
			bytes = Cbor.encode(records(seed))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Rec), _)
						r = Cbor.parse_with(bytes, reject_options)
						parse_len(r)
					},
				),
			)
		}
		"unknown_parse" => {
			bytes = Cbor.encode(wides(seed))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Rec), _)
						r = Cbor.parse(bytes)
						parse_len(r)
					},
				),
			)
		}
		"unions_content" => {
			bytes = unions_bytes(seed, Bool.False)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Pay), _)
						r = Cbor.parse_with(bytes, { unions: Internal({ tag: "kind", content: "value" }) })
						parse_len(r)
					},
				),
			)
		}
		"trees_parse" => {
			bytes = trees_bytes(seed)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Tree), _)
						r = Cbor.parse_with(bytes, { unions: Internal({ tag: "kind", content: "value" }) })
						parse_len(r)
					},
				),
			)
		}
		"map_value" => {
			bytes = dict_bytes(seed)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(bytes)
						if (r.is_ok()) 1 else 0
					},
				),
			)
		}
		"text_parse" => {
			bytes = texts_bytes(seed)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Str), _)
						r = Cbor.parse(bytes)
						parse_len(r)
					},
				),
			)
		}
		"path_map" => {
			# The path of the last value of a map of 100k keys: the value is the last byte.
			bytes = dict_bytes(seed)
			pos = bytes.len() - head(0, 99_999).len()
			Ok(repeat(loops, |_| Cbor.path_at(bytes, pos).map_ok(|p| p.len()) ?? 1_000_000))
		}
		_ => Err(UnknownCase)
	}

## The input bytes of a fixture for bench/compare (the other languages parse the same bytes).
fixture : Str, U64 -> Try(List(U8), [UnknownCase])
fixture = |name, seed|
	match name {
		"bytes" => Ok(Cbor.encode(to_blob(List.repeat(0xab.U8, 1_000_000 + seed))))
		"records" => Ok(Cbor.encode(records(seed)))
		"wide" => Ok(Cbor.encode(wides(seed)))
		"dict" => Ok(dict_bytes(seed))
		"texts" => Ok(texts_bytes(seed))
		"deep" => Ok(deep_bytes(seed))
		_ => Err(UnknownCase)
	}

## Lower-case hex of the bytes.
to_hex : List(U8) -> Str
to_hex = |bytes| {
	digit = |n| if (n < 10) n + 0x30 else n + 0x57
	out = bytes.fold(List.with_capacity(bytes.len() * 2), |acc, b| acc.append(digit(b.shr_zf_wrap(4))).append(digit(b.bitwise_and(0xf))))
	Str.from_utf8(out) ?? ""
}

main! = |args| {
	case = args.get(0) ?? ""
	if case == "dump" {
		match fixture(args.get(1) ?? "", args.len() // 8) {
			Ok(bytes) => {
				echo!(to_hex(bytes))
				return Ok({})
			}
			Err(_) => {
				echo!("unknown fixture\n")
				return Err(Exit(2))
			}
		}
	}
	loops = U64.from_str(args.get(1) ?? "0") ?? 0
	# The seed is 0 (2 args), but the compiler cannot know it.
	seed = args.len() // 8
	match run(case, loops, seed) {
		Ok(sum) => {
			echo!("${case} ${loops.to_str()} ${sum.to_str()}\n")
			Ok({})
		}
		Err(_) => {
			echo!("unknown case: ${case}\n")
			Err(Exit(2))
		}
	}
}
