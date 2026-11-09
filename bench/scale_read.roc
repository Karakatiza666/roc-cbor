app [] { pkg: "../src/main.roc" }

# The scaling test of the reader. Usage: scale_read <case> <loops> <items>. scripts/scale.sh builds it
# with --opt=speed, one app for each case, and times each case at 5k, 10k, 20k and 40k items.
# The time for each item must not grow with the count of items (sort cases: not more than log n).
# The input of a case is built once, before the loop, and only the read is in the loop.
# An "item" is the unit that `items` counts: a record, a map entry, a nesting level, 25 bytes, and so on.
# The union inputs are raw bytes (no writer), so the union arms also build on 0.4.1 (the proof in scale.sh).

import pkg.Cbor

Rec : { user_name : Str, id : U64, is_ok : Bool, score : F64, tags : List(Str) }

## A record with 12 more keys than Rec: the reader of Rec skips them.
Wide : { user_name : Str, id : U64, is_ok : Bool, score : F64, tags : List(Str), u1 : U64, u2 : Str, u3 : List(U64), u4 : Bool, u5 : F64, u6 : Str, u7 : U64, u8 : { a : U64, b : Str }, u9 : Str, u10 : U64, u11 : List(Str), u12 : Str }

Pay : [Cash, Card({ last4 : Str }), Check(U64)]

## `{ "kind": "Node", "value": [child] }` or `{ "kind": "Leaf", "value": n }`: a map and an array for each level.
Tree := [Leaf(U64), Node(List(Tree))].{
	parser_for : _
}

## The levels of each tree in union_nested: with the outer list, 1 + 2 * 250 + 1 = 502 nested items (limit 512).
tree_levels : U64
tree_levels = 250

## The list of `n` values from `f`.
make : U64, (U64 -> a) -> List(a)
make = |n, f| (0.U64).until(n).fold(List.with_capacity(n), |acc, i| acc.append(f(i)))

## Runs `work` `loops` times and sums its results.
repeat : U64, (U64 -> U64) -> U64
repeat = |loops, work| {
	var $sum = 0
	for i in (0.U64).until(loops) {
		$sum = $sum + work(i)
	}
	$sum
}

## A CBOR head with the shortest argument (RFC 8949 3), built by hand so that the inputs do not need the writer.
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

## A map of the entries (key and value bytes).
map_of : List((List(U8), List(U8))) -> List(U8)
map_of = |entries| entries.fold(head(5, entries.len()), |acc, (k, v)| acc.concat(k).concat(v))

array_of : List(List(U8)) -> List(U8)
array_of = |items| items.fold(head(4, items.len()), |acc, item| acc.concat(item))

rec : U64 -> Rec
rec = |i| { user_name: "user-${i.to_str()}", id: i, is_ok: i % 2 == 0, score: i.to_f64() * 1.5, tags: ["a", "b${(i % 7).to_str()}"] }

wide : U64 -> Wide
wide = |i| { user_name: "user-${i.to_str()}", id: i, is_ok: i % 2 == 0, score: i.to_f64() * 1.5, tags: ["a"], u1: i, u2: "x", u3: [i, i], u4: Bool.True, u5: 0.5, u6: "yy", u7: 7, u8: { a: i, b: "b" }, u9: "z", u10: 10, u11: ["p", "q"], u12: "w" }

## A Pay as an internal tag, with the tag key first or after the content.
pay_bytes : U64, Bool -> List(U8)
pay_bytes = |i, tag_first| {
	kind = |name| (text("kind"), text(name))
	entries =
		match i % 3 {
			0 => [kind("Cash")]
			1 => [kind("Card"), (text("last4"), text("4242"))]
			_ => [kind("Check"), (text("value"), head(0, i))]
		}
	map_of(if (tag_first) entries else entries.rev())
}

## A Tree of `levels` Node levels, then a Leaf. Tag key first, or after the content: then the "kind"
## of each level comes after its whole subtree.
tree_bytes : U64, U64, Bool -> List(U8)
tree_bytes = |levels, leaf, tag_first| {
	kind_node = text("kind").concat(text("Node"))
	value_one = text("value").concat(head(4, 1))
	leaf_map = map_of([(text("kind"), text("Leaf")), (text("value"), head(0, leaf))])
	if tag_first {
		List.repeat(head(5, 2).concat(kind_node).concat(value_one), levels).join().concat(leaf_map)
	} else {
		List.repeat(head(5, 2).concat(value_one), levels).join().concat(leaf_map).concat(List.repeat(kind_node, levels).join())
	}
}

## A text key of 40 bytes with a common prefix of 32 bytes: each compare of the sort reads most of the key.
long_key : U64 -> List(U8)
long_key = |i| {
	digits = (100_000_000 + i).to_str()
	text("p".repeat(31).concat(digits))
}

## Multi-byte UTF-8 (27 bytes): 2, 3 and 4 byte sequences.
utf8_chunk : Str
utf8_chunk = "é漢🎉 user-é漢🎉-ü"

parse_len : Try(List(a), _) -> U64
parse_len = |r|
	match r {
		Ok(l) => l.len()
		Err(_) => 1_000_000
	}

is_ok_count : Try(a, _) -> U64
is_ok_count = |r| if (r.is_ok()) 1 else 0

## The position of the last item: the bytes end with it.
last_pos : List(U8), List(U8) -> U64
last_pos = |bytes, last| bytes.len() - last.len()

## The items of `chunks` given to `start` one at a time with `push`, each item read as a Rec, then `finish`: the count
## of items, or 1_000_000 for an error. The loop of the README: `$items = r.rest?`.
stream_count : Cbor.Items, List(List(U8)) -> U64
stream_count = |start, chunks| count_items(start, chunks) ?? 1_000_000

count_items : Cbor.Items, List(List(U8)) -> Try(U64, _)
count_items = |start, chunks| {
	var $items = start
	var $count = 0
	for chunk in chunks {
		r : { values : List(Rec), rest : Try(Cbor.Items, _) }
		r = $items.push(chunk)
		$count = $count + r.values.len()
		$items = r.rest?
	}
	$items.finish()?
	Ok($count)
}

## As `stream_count`, for one large item: each item read as a `List(Rec)`, the count of the records of all items.
big_item_count : Cbor.Items, List(List(U8)) -> U64
big_item_count = |start, chunks| big_items(start, chunks) ?? 1_000_000

big_items : Cbor.Items, List(List(U8)) -> Try(U64, _)
big_items = |start, chunks| {
	var $items = start
	var $count = 0
	for chunk in chunks {
		r : { values : List(List(Rec)), rest : Try(Cbor.Items, _) }
		r = $items.push(chunk)
		for l in r.values {
			$count = $count + l.len()
		}
		$items = r.rest?
	}
	$items.finish()?
	Ok($count)
}

## The old trap 2 in the push form: a `match` on `rest`, with `finish` after the loop. The `Err` branch sets `$items` to a
## new decoder before `break`: a branch that leaves the old decoder in `$items` keeps it live at each `push` (it can
## reach the `finish` after the loop), and each chunk of the open item then copies the item (quadratic, measured).
big_item_reset : Cbor.Items, List(List(U8)) -> U64
big_item_reset = |start, chunks| {
	var $items = start
	var $count = 0
	var $failed = Bool.False
	for chunk in chunks {
		r : { values : List(List(Rec)), rest : Try(Cbor.Items, _) }
		r = $items.push(chunk)
		for l in r.values {
			$count = $count + l.len()
		}
		match r.rest {
			Ok(next) => {
				$items = next
			}
			Err(_) => {
				$items = Cbor.Items.sequence({})
				$failed = Bool.True
				break
			}
		}
	}
	if $failed {
		1_000_000
	} else {
		match $items.finish() {
			Ok(_) => $count
			Err(_) => 1_000_000
		}
	}
}

## The old trap 3 in the push form: a function that gives the decoder back after its loop, and `finish` in the caller.
big_item_return : Cbor.Items, List(List(U8)) -> U64
big_item_return = |start, chunks|
	match push_all(start, chunks) {
		Ok({ count, items }) =>
			match items.finish() {
				Ok(_) => count
				Err(_) => 1_000_000
			}
		Err(_) => 1_000_000
	}

push_all : Cbor.Items, List(List(U8)) -> Try({ count : U64, items : Cbor.Items }, _)
push_all = |start, chunks| {
	var $items = start
	var $count = 0
	for chunk in chunks {
		r : { values : List(List(Rec)), rest : Try(Cbor.Items, _) }
		r = $items.push(chunk)
		for l in r.values {
			$count = $count + l.len()
		}
		$items = r.rest?
	}
	Ok({ count: $count, items: $items })
}

## The data bytes that a ByteChunks gives for `chunks`, or 1,000,000 on an error.
bytes_chunks_count : Cbor.ByteChunks, List(List(U8)) -> U64
bytes_chunks_count = |start, chunks| {
	var $d = start
	var $count = 0
	for chunk in chunks {
		r = $d.push(chunk)
		for piece in r.values {
			$count = $count + piece.len()
		}
		match r.rest {
			Ok(next) => {
				$d = next
			}
			Err(_) => return 1_000_000
		}
	}
	match $d.finish() {
		Ok(_) => $count
		Err(_) => 1_000_000
	}
}

## The text bytes that a TextChunks gives for `chunks`, or 1,000,000 on an error.
text_chunks_count : Cbor.TextChunks, List(List(U8)) -> U64
text_chunks_count = |start, chunks| {
	var $d = start
	var $count = 0
	for chunk in chunks {
		r = $d.push(chunk)
		for piece in r.values {
			$count = $count + piece.count_utf8_bytes()
		}
		match r.rest {
			Ok(next) => {
				$d = next
			}
			Err(_) => return 1_000_000
		}
	}
	match $d.finish() {
		Ok(_) => $count
		Err(_) => 1_000_000
	}
}

## The entries of `chunks` given to `start` one at a time, each entry read as a Str key and a Rec value: the count of
## entries, or 1_000_000 for an error.
entries_count : Cbor.Entries, List(List(U8)) -> U64
entries_count = |start, chunks| count_entries(start, chunks) ?? 1_000_000

count_entries : Cbor.Entries, List(List(U8)) -> Try(U64, _)
count_entries = |start, chunks| {
	var $entries = start
	var $count = 0
	for chunk in chunks {
		r : { values : List((Str, Rec)), rest : Try(Cbor.Entries, _) }
		r = $entries.push(chunk)
		$count = $count + r.values.len()
		$entries = r.rest?
	}
	$entries.finish()?
	Ok($count)
}

run : Str, U64, U64, U64 -> Try(U64, [UnknownCase])
run = |case, loops, n, seed|
	match case {
		"rec" => {
			bytes = Cbor.encode(make(n, |i| rec(i + seed)))
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
		"rec_camel" => {
			bytes = Cbor.encode_with(make(n, |i| rec(i + seed)), { fields: Camel }) ?? []
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Rec), _)
						r = Cbor.parse_with(bytes, { fields: Camel })
						parse_len(r)
					},
				),
			)
		}
		"rec_reject" => {
			bytes = Cbor.encode(make(n, |i| rec(i + seed)))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Rec), _)
						r = Cbor.parse_with(bytes, { unknown_fields: Reject })
						parse_len(r)
					},
				),
			)
		}
		"rec_unknown" => {
			bytes = Cbor.encode(make(n, |i| wide(i + seed)))
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
		"val_list" => {
			bytes = Cbor.encode(make(n, |i| rec(i + seed)))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Cbor.Value), _)
						r = Cbor.parse(bytes)
						parse_len(r)
					},
				),
			)
		}
		"val_map" => {
			bytes = map_of(make(n, |i| (text("key-${(i + seed).to_str()}"), head(0, i))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(bytes)
						is_ok_count(r)
					},
				),
			)
		}
		"val_deep" => {
			# n / 500 chains of 500 nested arrays: an item is one level.
			chain = List.repeat(head(4, 1), 500).join().concat(head(0, seed))
			bytes = array_of(List.repeat(chain, n // 500))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(bytes)
						is_ok_count(r)
					},
				),
			)
		}
		"val_deep_wide" => {
			# n items of one array at depth 500: each item opens and closes an array there.
			bottom = array_of(make(n, |i| head(4, 1).concat(head(0, i + seed))))
			bytes = List.repeat(head(4, 1), 500).join().concat(bottom)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(bytes)
						is_ok_count(r)
					},
				),
			)
		}
		"path_array" => {
			last = head(0, n + seed)
			bytes = array_of(make(n - 1, |i| head(0, i)).append(last))
			pos = last_pos(bytes, last)
			Ok(repeat(loops, |_| Cbor.path_at(bytes, pos).map_ok(|p| p.len()) ?? 1_000_000))
		}
		"path_map" => {
			last = head(0, n + seed)
			bytes = map_of(make(n, |i| (text("key-${i.to_str()}"), if (i + 1 == n) last else head(0, i))))
			pos = last_pos(bytes, last)
			Ok(repeat(loops, |_| Cbor.path_at(bytes, pos).map_ok(|p| p.len()) ?? 1_000_000))
		}
		"union_tag" => {
			bytes = array_of(make(n, |i| pay_bytes(i + seed, Bool.True)))
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
		"union_content" => {
			bytes = array_of(make(n, |i| pay_bytes(i + seed, Bool.False)))
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
		"union_nested" => {
			# n / 250 trees of 250 levels: an item is one level.
			bytes = array_of(make(n // tree_levels, |i| tree_bytes(tree_levels, i + seed, Bool.True)))
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
		"union_nested_content" => {
			# The same with the content key first: the tag key of each level is after its subtree.
			bytes = array_of(make(n // tree_levels, |i| tree_bytes(tree_levels, i + seed, Bool.False)))
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
		"union_depth" => {
			# One tree of n levels, content key first: the depth grows with n, so scale.sh gives it
			# the sizes of DEPTH_CASES (up to 240 levels, under the depth limit).
			bytes = tree_bytes(n, seed, Bool.False)
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Tree, _)
						r = Cbor.parse_with(bytes, { unions: Internal({ tag: "kind", content: "value" }) })
						if (r.is_ok()) 1 else 0
					},
				),
			)
		}
		"dup_record" => {
			# One map: the field "a", then n distinct unknown keys.
			bytes = map_of([(text("a"), head(0, seed))].concat(make(n, |i| (text("key-${i.to_str()}"), head(0, i)))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try({ a : U64 }, _)
						r = Cbor.parse(bytes)
						r.map_ok(|v| v.a + 1) ?? 1_000_000
					},
				),
			)
		}
		"dup_value" => {
			bytes = map_of(make(n, |i| (long_key(i + seed), head(0, i))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(bytes)
						is_ok_count(r)
					},
				),
			)
		}
		"dup_prefix" => {
			# The record path with 40-byte keys that differ only at the end.
			bytes = map_of([(text("a"), head(0, seed))].concat(make(n, |i| (long_key(i), head(0, i)))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try({ a : U64 }, _)
						r = Cbor.parse(bytes)
						r.map_ok(|v| v.a + 1) ?? 1_000_000
					},
				),
			)
		}
		"sorted_keys" => {
			# The input of dup_prefix (its keys are in order), read with key_order: Sorted: the duplicate check is
			# one compare with the key before, so the case is linear (dup_prefix sorts the keys).
			bytes = map_of([(text("a"), head(0, seed))].concat(make(n, |i| (long_key(i), head(0, i)))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try({ a : U64 }, _)
						r = Cbor.parse_with(bytes, { key_order: Sorted })
						r.map_ok(|v| v.a + 1) ?? 1_000_000
					},
				),
			)
		}
		"dup_first" => {
			# n entries, all with the key "a": First reads the first one.
			bytes = map_of(make(n, |i| (text("a"), head(0, i + seed))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try({ a : U64 }, _)
						r = Cbor.parse_with(bytes, { duplicate_keys: First })
						r.map_ok(|v| v.a + 1) ?? 1_000_000
					},
				),
			)
		}
		"dup_last" => {
			bytes = map_of(make(n, |i| (text("a"), head(0, i + seed))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse_with(bytes, { duplicate_keys: Last })
						is_ok_count(r)
					},
				),
			)
		}
		"text_list" => {
			bytes = array_of(make(n, |i| text(utf8_chunk.concat((i + seed).to_str()))))
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
		"text_one" => {
			# One text of n chunks of 27 bytes.
			bytes = text(utf8_chunk.repeat(n).concat(seed.to_str()))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Str, _)
						r = Cbor.parse(bytes)
						r.map_ok(|s| s.count_utf8_bytes()) ?? 1_000_000
					},
				),
			)
		}
		"bytes_one" => {
			# One byte string of 25 bytes for each item: 1 MB at 40k.
			bytes = head(2, 25 * n).concat(List.repeat(0xab, 25 * n - 1)).append(seed.to_u8_wrap())
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Bytes, _)
						r = Cbor.parse(bytes)
						r.map_ok(|b| b.to_list().len()) ?? 1_000_000
					},
				),
			)
		}
		"u8list_one" => {
			bytes = head(2, 25 * n).concat(List.repeat(0xab, 25 * n - 1)).append(seed.to_u8_wrap())
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
		"b64_bytes" => {
			# One base64 text of 32 characters (24 bytes) for each item, read with BytesFromBase64.
			bytes = text((if (seed == 0) "q6ur" else "AAAA").repeat(8 * n))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Bytes, _)
						r = Cbor.parse_with(bytes, { allow: [BytesFromBase64] })
						r.map_ok(|b| b.to_list().len()) ?? 1_000_000
					},
				),
			)
		}
		"b64_list" => {
			bytes = text((if (seed == 0) "q6ur" else "AAAA").repeat(8 * n))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(U8), _)
						r = Cbor.parse_with(bytes, { allow: [BytesFromBase64] })
						parse_len(r)
					},
				),
			)
		}
		"dict" => {
			bytes = map_of(make(n, |i| (text("key-${(i + seed).to_str()}"), head(0, i))))
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Dict(Str, U64), _)
						r = Cbor.parse(bytes)
						r.map_ok(|d| d.len()) ?? 1_000_000
					},
				),
			)
		}
		"stream_items" => {
			# Cbor.Items: a top-level array of records in chunks of 4 KiB, each record read with push. A decoder
			# that walks its buffer from the start at each push is quadratic here.
			bytes = Cbor.encode(make(n, |i| rec(i + seed)))
			chunks = bytes.chunks_of(4096)
			Ok(repeat(loops, |_| stream_count(Cbor.Items.array({}), chunks)))
		}
		"stream_bytes" => {
			# Cbor.ByteChunks: one byte string of 64 bytes for each item (2.5 MB at 40k) in chunks of 1000 bytes. A decoder
			# that keeps or copies all of its input at each push is quadratic here.
			bytes = head(2, 64 * n).concat(List.repeat(0xab, 64 * n - 1)).append(seed.to_u8_wrap())
			chunks = bytes.chunks_of(1000)
			Ok(repeat(loops, |_| bytes_chunks_count(Cbor.ByteChunks.new({}), chunks)))
		}
		"stream_text" => {
			# Cbor.TextChunks: one text of 27 bytes for each item in chunks of 1000 bytes, so most chunks cut a code
			# point, and the decoder keeps its bytes for the next chunk.
			bytes = text(utf8_chunk.repeat(n).concat(seed.to_str()))
			chunks = bytes.chunks_of(1000)
			Ok(repeat(loops, |_| text_chunks_count(Cbor.TextChunks.new({}), chunks)))
		}
		"stream_entries" => {
			# Cbor.Entries: a top-level map of n entries (keys in order, record values) in chunks of 4 KiB, read with
			# key_order: Sorted (one key kept): linear. A decoder that walks its buffer from the start at each push,
			# or a key check against each key before, is quadratic here.
			# The record values are written with key_order: Sorted too: each map of the input is read with the rule.
			bytes = map_of(make(n, |i| (long_key(i), Cbor.encode_with(rec(i + seed), { key_order: Sorted }) ?? [])))
			chunks = bytes.chunks_of(4096)
			Ok(repeat(loops, |_| entries_count(Cbor.Entries.map({ key_order: Sorted }), chunks)))
		}
		"stream_keys" => {
			# Cbor.Entries with key_order: Any: the KeySet of sorted runs holds the canonical bytes of each key, n log n
			# (a lookup in each run, the merges). Keys that differ only at the end, in a reversed order.
			bytes = map_of(make(n, |i| (long_key(n - i + seed), Cbor.encode(rec(i)))))
			chunks = bytes.chunks_of(4096)
			Ok(repeat(loops, |_| entries_count(Cbor.Entries.map({}), chunks)))
		}
		"stream_big_item" => {
			# Cbor.Items with no adapter: an array of one item, a list of n records (about 60 bytes each), in chunks of
			# 1 KiB. The item is open for each chunk: the walk goes on from its Cut state, so each byte is walked one
			# time. A walk of the open item from its start at each chunk is quadratic here.
			bytes = Cbor.encode([make(n, |i| rec(i + seed))])
			chunks = bytes.chunks_of(1024)
			Ok(repeat(loops, |_| big_item_count(Cbor.Items.array({ max_buffer: 1_000_000_000 }), chunks)))
		}
		"stream_trap_reset" => {
			# stream_big_item with the loop of the old trap 2: a `match` on `rest`, `break` in its `Err` branch (which sets
			# `$items` to a new decoder), and `finish` after the loop.
			bytes = Cbor.encode([make(n, |i| rec(i + seed))])
			chunks = bytes.chunks_of(1024)
			Ok(repeat(loops, |_| big_item_reset(Cbor.Items.array({ max_buffer: 1_000_000_000 }), chunks)))
		}
		"stream_trap_return" => {
			# stream_big_item with the old trap 3: a function gives the decoder back after its loop, and the caller
			# calls `finish`.
			bytes = Cbor.encode([make(n, |i| rec(i + seed))])
			chunks = bytes.chunks_of(1024)
			Ok(repeat(loops, |_| big_item_return(Cbor.Items.array({ max_buffer: 1_000_000_000 }), chunks)))
		}
		"stream_keys_dup" => {
			# Cbor.Entries with duplicate_keys: First: n distinct keys (as stream_keys), then the same n keys again in
			# the other order, each one a duplicate that is skipped. Each key is a lookup in the KeySet (a binary search
			# in each sorted run), n log^2 n at most. A lookup that scans each key is quadratic here.
			first = make(n, |i| (long_key(n - i + seed), Cbor.encode(rec(i))))
			again = make(n, |i| (long_key(i + 1 + seed), Cbor.encode(rec(i))))
			bytes = map_of(first.concat(again))
			chunks = bytes.chunks_of(4096)
			Ok(repeat(loops, |_| entries_count(Cbor.Entries.map({ duplicate_keys: First }), chunks)))
		}
		_ => Err(UnknownCase)
	}

main! = |args| {
	case = args.get(0) ?? ""
	loops = U64.from_str(args.get(1) ?? "0") ?? 0
	n = U64.from_str(args.get(2) ?? "0") ?? 0
	# The seed is 0 (3 args), but the compiler cannot know it.
	seed = args.len() // 8
	match run(case, loops, n, seed) {
		Ok(sum) => {
			echo!("${case} ${loops.to_str()} ${n.to_str()} ${sum.to_str()}\n")
			Ok({})
		}
		Err(_) => {
			echo!("unknown case: ${case}\n")
			Err(Exit(2))
		}
	}
}
