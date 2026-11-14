app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.6.1/GDoZFRDnzMRiVk9nE8wdWn52btGsM1GhcY9VDKqy9f1Y.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Arbitrary
import fuzz.Fuzz
import pkg.Cbor

# L1 target: the stream decoders Cbor.Items, Cbor.Entries, Cbor.ByteChunks and Cbor.TextChunks, for any bytes, with
# each option set of `sets` (also key_order: Sorted). The splits of the input into chunks come from the fuzz input.
#
# P1 split independence: 4 random splits (with empty chunks) and the split into 1-byte chunks give the same items
# and the same end (Ok after `finish`, or the error at its position) as one chunk. For ByteChunks and TextChunks: the same
# concatenation of the chunks and the same end, and no chunk is empty. Also with a small max_buffer (TooLarge).
# P2 agreement: Items.array and parse_with of a List(a) (Cbor.Value, a record, U128, Dict(U64, Str), an internal
# tag union), Items.sequence and parse_sequence_with, Entries and parse_with of a Dict(k, v), TextChunks and Str,
# ByteChunks and List(U8): Ok with the same values, or both Err. The known differences: an empty byte string root of
# Items.array, a root of ByteChunks that is not a byte string, a root of Entries that is not a map, and Entries with
# duplicate_keys: Last and key_order: Any (NotStreamable). max_buffer is above the input size.
# P3 reference model: the stream equals a slow model of the root head, then parse_prefix_with for each item with
# max_depth and max_items reduced, and for Entries the order and the duplicates of the Cbor.Value of each root key.
# The same items and the same error position.
# Roots made from the input are checked too: the input as valid text with code points of 2, 3 and 4 bytes (definite,
# and indefinite with chunks), for ByteChunks and TextChunks; maps with keys that repeat, in input order and sorted,
# for Entries with each option set (duplicate_keys, key_order: Sorted). Each property can be turned off (`run`).

## The errors of each read: a closed union, so that results compare with `==`.
Errs : [InvalidCbor(U64), TooLarge(U64), NotStreamable, MissingRequiredField(Str)]

## The errors of ByteChunks and TextChunks.
ChunkErrs : Cbor.Error

## The properties that run: all of them. A check of the target against a planted bug turns the others off.
run : { p1 : Bool, p2 : Bool, p3 : Bool }
run = { p1: Bool.True, p2: Bool.True, p3: Bool.True }

## The most values of one drive: a decoder that gives values forever must fail the target, not fill the memory.
step_limit : U64
step_limit = 100_000

Row : { id : U64, name : Str, tags : List(Str), note : Try(Str, [Missing]), flag : Bool }

## A union with each kind of payload, read with an internal tag.
Shape := [Dot, Box({ w : U32, label : Try(Str, [Missing]) }), Size(U64), Span(I64, Str), Nest(List(Shape))].{
	parser_for : _
	is_eq : _
}

# Option sets

## Each option field, with no optional field: `to_options` gives the `Cbor.Options`.
OptSet : { allow : List(Cbor.Leniency), duplicate_keys : [Reject, First, Last], key_order : [Any, Sorted], unknown_fields : [Skip, Reject], max_depth : U64, max_items : U64, ignore_tags : List(U64), unions : Cbor.Unions, max_buffer : U64 }

to_options : OptSet -> Cbor.Options
to_options = |s| { fields: Snake, allow: s.allow, duplicate_keys: s.duplicate_keys, key_order: s.key_order, unknown_fields: s.unknown_fields, max_depth: s.max_depth, max_items: s.max_items, ignore_tags: s.ignore_tags, unions: s.unions, max_buffer: s.max_buffer }

## The defaults of `parse_with`, with a max_buffer far above the largest input (4096 bytes).
base : OptSet
base = { allow: [], duplicate_keys: Reject, key_order: Any, unknown_fields: Skip, max_depth: 512, max_items: U64.highest, ignore_tags: [], unions: External, max_buffer: 1_000_000 }

internal : Cbor.Unions
internal = Internal({ tag: "kind", content: "value" })

## The option sets of P1, P2 and P3: the sets of fuzz/parse_never_crashes.roc, key_order: Sorted with each
## duplicate_keys, and small limits.
sets : List(OptSet)
sets = [
	base,
	{ ..base, allow: [IndefiniteLength] },
	{ ..base, allow: [IndefiniteLength], duplicate_keys: First, unions: internal },
	{ ..base, duplicate_keys: Last, allow: [PaddedNumbers], unions: internal },
	{ ..base, ignore_tags: [6, 10, 4], allow: [DecFromText] },
	{ ..base, allow: Cbor.sql_rows, unknown_fields: Reject, max_items: 200 },
	{ ..base, key_order: Sorted },
	{ ..base, key_order: Sorted, duplicate_keys: First, allow: [IndefiniteLength, PaddedNumbers] },
	{ ..base, key_order: Sorted, duplicate_keys: Last, allow: [IndefiniteLength], ignore_tags: [6] },
	{ ..base, max_depth: 3, max_items: 12, allow: [IndefiniteLength], ignore_tags: [6] },
]

## A small max_buffer: P1 only (TooLarge is the same for each split).
small_buffers : List(OptSet)
small_buffers = [
	{ ..base, max_buffer: 6 },
	{ ..base, max_buffer: 24, allow: [IndefiniteLength], key_order: Sorted, duplicate_keys: Last },
]

# Splits

## One step of splitmix64: a random value and the next state.
next_rand : U64 -> (U64, U64)
next_rand = |s| {
	z0 = s.plus_wrap(0x9e3779b97f4a7c15)
	z1 = z0.bitwise_xor(z0.shr_zf_wrap(30)).times_wrap(0xbf58476d1ce4e5b9)
	z2 = z1.bitwise_xor(z1.shr_zf_wrap(27)).times_wrap(0x94d049bb133111eb)
	(z2.bitwise_xor(z2.shr_zf_wrap(31)), z0)
}

## A random split of `bytes` from `seed`: up to 12 cuts, at random positions (a cut can repeat: an empty chunk).
random_split : List(U8), U64 -> List(List(U8))
random_split = |bytes, seed| {
	n = bytes.len()
	(r0, s0) = next_rand(seed)
	cuts_count = r0 % 13
	var $s = s0
	var $cuts = []
	for _ in 0.U64..<cuts_count {
		(r, s) = next_rand($s)
		$s = s
		$cuts = $cuts.append(r % (n + 1))
	}
	sorted = $cuts.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same)
	var $chunks = []
	var $at = 0
	for c in sorted {
		$chunks = $chunks.append(bytes.sublist({ start: $at, len: c - $at }))
		$at = c
	}
	$chunks.append(bytes.drop_first($at))
}

## The splits of P1: chunks of 1 byte, and 4 random splits.
splits : List(U8), U64 -> List(List(List(U8)))
splits = |bytes, seed| {
	var $out = [bytes.chunks_of(1)]
	var $s = seed
	for _ in 0.U64..<4 {
		(r, s) = next_rand($s)
		$s = s
		$out = $out.append(random_split(bytes, r))
	}
	$out
}

# Drivers

## The items that `start` gives with `chunks` one at a time (`push`), then `finish`: the items, or the error. The loop
## is bounded by the chunks; more than `step_limit` values is a crash.
stream_items : Cbor.Items, List(List(U8)) -> Try(List(a), Errs) where [a.Cbor.Parseable(Cbor.Error)]
stream_items = |start, chunks| {
	var $d = start
	var $values = []
	for chunk in chunks {
		r : { values : List(a), rest : Try(Cbor.Items, Errs) }
		r = $d.push(chunk)
		$values = $values.concat(r.values)
		if $values.len() > step_limit {
			crash "a stream decoder gave more than 100,000 values"
		}
		$d = r.rest?
	}
	match $d.finish() {
		Ok(_) => Ok($values)
		Err(InvalidCbor(p)) => Err(InvalidCbor(p))
		Err(MissingRequiredField(f)) => Err(MissingRequiredField(f))
		Err(TooLarge(p)) => Err(TooLarge(p))
	}
}

## The entries that `start` gives with `chunks`, then `finish`.
stream_entries : Cbor.Entries, List(List(U8)) -> Try(List((k, v)), Errs) where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error)]
stream_entries = |start, chunks| {
	var $d = start
	var $entries = []
	for chunk in chunks {
		r : { values : List((k, v)), rest : Try(Cbor.Entries, Errs) }
		r = $d.push(chunk)
		$entries = $entries.concat(r.values)
		if $entries.len() > step_limit {
			crash "a stream decoder gave more than 100,000 values"
		}
		$d = r.rest?
	}
	match $d.finish() {
		Ok(_) => Ok($entries)
		Err(InvalidCbor(p)) => Err(InvalidCbor(p))
		Err(MissingRequiredField(f)) => Err(MissingRequiredField(f))
		Err(TooLarge(p)) => Err(TooLarge(p))
		Err(NotStreamable) => Err(NotStreamable)
	}
}

## The data that a ByteChunks gives with `chunks`, then `finish`: the parts joined, or the error. An empty part is a
## crash.
stream_bytes : Cbor.ByteChunks, List(List(U8)) -> Try(List(U8), ChunkErrs)
stream_bytes = |start, chunks| {
	var $d = start
	var $data = []
	var $parts = 0
	for chunk in chunks {
		r = $d.push(chunk)
		for piece in r.values {
			if piece.is_empty() {
				crash "P1: ByteChunks gives an empty chunk"
			}
			$data = $data.concat(piece)
		}
		$parts = $parts + r.values.len()
		if $parts > step_limit {
			crash "a stream decoder gave more than 100,000 values"
		}
		$d = r.rest?
	}
	$d.finish()?
	Ok($data)
}

## The text that a TextChunks gives with `chunks`, then `finish`.
stream_text : Cbor.TextChunks, List(List(U8)) -> Try(Str, ChunkErrs)
stream_text = |start, chunks| {
	var $d = start
	var $text = ""
	var $parts = 0
	for chunk in chunks {
		r = $d.push(chunk)
		for piece in r.values {
			if piece.is_empty() {
				crash "P1: TextChunks gives an empty chunk"
			}
			$text = $text.concat(piece)
		}
		$parts = $parts + r.values.len()
		if $parts > step_limit {
			crash "a stream decoder gave more than 100,000 values"
		}
		$d = r.rest?
	}
	$d.finish()?
	Ok($text)
}

# The model of P3

## A head at `p`, with the checks of the walk: no reserved info (28 to 30), the shortest head unless `padded`.
## A cut head is an error too. Floats and simple values are not root heads, so they have no special case.
head_at : List(U8), U64, Bool -> Try({ major : U8, info : U8, arg : U64, next : U64 }, [Bad])
head_at = |bytes, p, padded| {
	b = bytes.get(p) ? |_| Bad
	major = b.shr_zf_wrap(5)
	info = b.bitwise_and(31)
	size =
		if info < 24 or info == 31 {
			0
		} else if info <= 27 {
			(1.U64).shl_wrap((info - 24).to_u8())
		} else {
			return Err(Bad)
		}
	if p + 1 + size > bytes.len() {
		return Err(Bad)
	}
	arg = (0.U64).until(size).fold(if (info < 24) info.to_u64() else 0, |n, i| n.shl_wrap(8).bitwise_or((bytes.get(p + 1 + i) ?? 0).to_u64()))
	least = if (info == 24) 24 else if (info == 25) 256 else if (info == 26) 65536 else if (info == 27) 4294967296 else 0
	if !padded and arg < least {
		return Err(Bad)
	}
	Ok({ major, info, arg, next: p + 1 + size })
}

## The root head: the tags of `ignore_tags`, then a head of `major`. Each one counts for max_items and max_depth.
## The error is at the head, or for no head at the innermost tag (0 with no tag). `left`: the count, or `Until` a break.
RootHead : { at : U64, left : [Count(U64), Until], depth : U64, count : U64, root : U64 }

root_model : List(U8), OptSet, U8 -> Try(RootHead, U64)
root_model = |bytes, set, major| {
	padded = set.allow.contains(PaddedNumbers)
	indefinite = set.allow.contains(IndefiniteLength)
	var $p = 0
	var $depth = 0
	var $count = 0
	var $last = 0
	while $p <= bytes.len() {
		if $p >= bytes.len() {
			return Err($last)
		}
		h = head_at(bytes, $p, padded) ? |_| $p
		if $count >= set.max_items or $depth >= set.max_depth {
			return Err($p)
		}
		$count = $count + 1
		if h.major == 6 and h.info != 31 and set.ignore_tags.contains(h.arg) {
			$depth = $depth + 1
			$last = $p
			$p = h.next
		} else if h.major == major and (h.info != 31 or indefinite) {
			return Ok({ at: h.next, left: if (h.info == 31) Until else Count(h.arg), depth: $depth + 1, count: $count, root: $p })
		} else {
			return Err($p)
		}
	}
	Err($p)
}

## The major type of the root after the tags of `ignore_tags`.
root_major : List(U8), OptSet -> U8
root_major = |bytes, set| {
	var $p = 0
	while $p < bytes.len() {
		match head_at(bytes, $p, Bool.True) {
			Ok(h) if h.major == 6 and set.ignore_tags.contains(h.arg) => {
				$p = h.next
			}
			Ok(h) => return h.major
			Err(_) => return 8
		}
	}
	8
}

## The options of an item in the root: `depth` levels of the root above it, `count` items of the root so far.
item_options : OptSet, U64, U64 -> Cbor.Options
item_options = |set, depth, count| to_options({ ..set, max_depth: set.max_depth - depth, max_items: set.max_items.minus_saturated(count) })

## The items that count for max_items in the whole item `bytes`: the least limit that reads it.
items_in : List(U8), OptSet -> U64
items_in = |bytes, set| {
	if set.max_items == U64.highest {
		return 0
	}
	var $lo = 1
	var $hi = bytes.len()
	while $lo < $hi {
		mid = ($lo + $hi) // 2
		r : Try(Cbor.Value, Errs)
		r = Cbor.parse_with(bytes, to_options({ ..set, max_depth: U64.highest, max_items: mid }))
		if r.is_ok() {
			$hi = mid
		} else {
			$lo = mid + 1
		}
	}
	$lo
}

## One whole item at `at` as a Cbor.Value (the walk), with the root limits: its value, its end and the count after it.
walk_value : List(U8), U64, OptSet, U64, U64 -> Try({ value : Cbor.Value, end : U64, count : U64 }, Errs)
walk_value = |bytes, at, set, depth, count| {
	r : Try({ value : Cbor.Value, rest : List(U8) }, Errs)
	r = Cbor.parse_prefix_with(bytes.drop_first(at), item_options(set, depth, count))
	match r {
		Ok(one) => {
			end = bytes.len() - one.rest.len()
			Ok({ value: one.value, end, count: count + items_in(bytes.sublist({ start: at, len: end - at }), set) })
		}
		Err(InvalidCbor(p)) => Err(InvalidCbor(at + p))
		Err(e) => Err(e)
	}
}

## The typed item from `start` to `end`, with the positions in all of `bytes`.
typed_at : List(U8), U64, U64, OptSet, U64, U64 -> Try(a, Errs) where [a.Cbor.Parseable(Cbor.Error)]
typed_at = |bytes, start, end, set, depth, count| {
	r : Try({ value : a, rest : List(U8) }, Errs)
	r = Cbor.parse_prefix_with(bytes.sublist({ start, len: end - start }), item_options(set, depth, count))
	match r {
		Ok(one) => Ok(one.value)
		Err(InvalidCbor(p)) => Err(InvalidCbor(start + p))
		Err(e) => Err(e)
	}
}

## After the root: no more bytes, else the error at the first extra byte.
after_root : List(U8), U64, b -> Try(b, Errs)
after_root = |bytes, at, value| if (at < bytes.len()) Err(InvalidCbor(at)) else Ok(value)

## The model of `Items.array`: the root head, then parse_prefix_with for each item.
array_model : List(U8), OptSet -> Try(List(a), Errs) where [a.Cbor.Parseable(Cbor.Error)]
array_model = |bytes, set| {
	root = root_model(bytes, set, 4) ? |p| InvalidCbor(p)
	var $at = root.at
	var $count = root.count
	var $left = root.left
	var $values = []
	while $at <= bytes.len() {
		match $left {
			Count(0) => return after_root(bytes, $at, $values)
			Until if bytes.get($at) == Ok(0xff) => return after_root(bytes, $at + 1, $values)
			_ => {}
		}
		if $at >= bytes.len() {
			return Err(InvalidCbor(root.root))
		}
		w = walk_value(bytes, $at, set, root.depth, $count)?
		value = typed_at(bytes, $at, w.end, set, root.depth, $count)?
		$values = $values.append(value)
		$at = w.end
		$count = w.count
		$left =
			match $left {
				Count(n) => Count(n - 1)
				Until => Until
			}
	}
	Err(InvalidCbor($at))
}

## The model of `Items.sequence` and `parse_sequence_with`: parse_prefix_with for each root item.
sequence_model : List(U8), OptSet -> Try(List(a), Errs) where [a.Cbor.Parseable(Cbor.Error)]
sequence_model = |bytes, set| {
	var $at = 0
	var $values = []
	while $at < bytes.len() {
		w = walk_value(bytes, $at, set, 0, 0)?
		value = typed_at(bytes, $at, w.end, set, 0, 0)?
		$values = $values.append(value)
		$at = w.end
	}
	Ok($values)
}

## `x` comes before `y` in bytewise order.
before : List(U8), List(U8) -> Bool
before = |x, y| {
	var $i = 0
	while $i < x.len() and $i < y.len() {
		a = x.get($i) ?? 0
		b = y.get($i) ?? 0
		if a != b {
			return a < b
		}
		$i = $i + 1
	}
	x.len() < y.len()
}

## One entry of the model: the start and end of its key and value.
Span : { key : U64, value : U64, end : U64, count : U64 }

## The typed key and value of an entry. The key reads only in the form that `Cbor.encode` writes for it.
typed_entry : List(U8), Span, Cbor.Value, OptSet, U64 -> Try((k, v), Errs) where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error)]
typed_entry = |bytes, span, key_value, set, depth| {
	key : k
	key = typed_at(bytes, span.key, span.value, set, depth, span.count)?
	if Cbor.encode(key) != Cbor.encode(key_value) {
		return Err(InvalidCbor(span.key))
	}
	value : v
	value = typed_at(bytes, span.value, span.end, set, depth, span.count)?
	Ok((key, value))
}

## The model of `Entries.map`: the root head, then for each entry the walk of its key, the order and the duplicates of
## the Cbor.Value of the key (the encode bytes of `key_order: Sorted`, or the encode bytes for `Any`), the walk of its
## value, and the typed key and value. With `Sorted` and `Last`, an entry waits for a greater key or the end.
entries_model : List(U8), OptSet -> Try(List((k, v)), Errs) where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error)]
entries_model = |bytes, set| {
	sorted = set.key_order == Sorted
	if set.duplicate_keys == Last and !sorted {
		return Err(NotStreamable)
	}
	root = root_model(bytes, set, 5) ? |p| InvalidCbor(p)
	depth = root.depth
	var $at = root.at
	var $count = root.count
	var $left = root.left
	var $out = []
	var $seen = []
	var $prev = []
	var $first = Bool.True
	var $held = Err(NoEntry)
	while $at <= bytes.len() {
		ended =
			match $left {
				Count(0) => Bool.True
				Until => bytes.get($at) == Ok(0xff)
				_ => Bool.False
			}
		if ended {
			match $held {
				Ok((span, kv)) => {
					$out = $out.append(typed_entry(bytes, span, kv, set, depth)?)
				}
				Err(_) => {}
			}
			return after_root(bytes, if ($left == Until) $at + 1 else $at, $out)
		}
		if $at >= bytes.len() {
			return Err(InvalidCbor(root.root))
		}
		key_at = $at
		k = walk_value(bytes, key_at, set, depth, $count)?
		var $later = Bool.False
		if sorted {
			det = Cbor.encode_with(k.value, { key_order: Sorted }) ?? []
			if !$first and before(det, $prev) {
				return Err(InvalidCbor(key_at))
			} else if !$first and det == $prev {
				match set.duplicate_keys {
					First => {
						$later = Bool.True
					}
					Last => {
						$held = Err(NoEntry)
					}
					Reject => return Err(InvalidCbor(key_at))
				}
			} else {
				match $held {
					Ok((span, kv)) => {
						$out = $out.append(typed_entry(bytes, span, kv, set, depth)?)
					}
					Err(_) => {}
				}
				$held = Err(NoEntry)
				$prev = det
				$first = Bool.False
			}
		} else {
			canon = Cbor.encode(k.value)
			if $seen.contains(canon) {
				if set.duplicate_keys == First {
					$later = Bool.True
				} else {
					return Err(InvalidCbor(key_at))
				}
			} else {
				$seen = $seen.append(canon)
			}
		}
		if k.end >= bytes.len() {
			return Err(InvalidCbor(root.root))
		}
		x = walk_value(bytes, k.end, set, depth, k.count)?
		span = { key: key_at, value: k.end, end: x.end, count: $count }
		if !$later {
			if sorted and set.duplicate_keys == Last {
				$held = Ok((span, k.value))
			} else {
				$out = $out.append(typed_entry(bytes, span, k.value, set, depth)?)
			}
		}
		$at = x.end
		$count = x.count
		$left =
			match $left {
				Count(n) => Count(n - 1)
				Until => Until
			}
	}
	Err(InvalidCbor($at))
}

# The properties

## P1 for one result: each split gives `whole`.
p1 : Str, b, List(b) -> {} where [b.is_eq : b, b -> Bool]
p1 = |name, whole, others|
	if run.p1 and !others.all(|o| o == whole) {
		crash "P1 split independence fails: ${name}"
	}

## P1, P2 and P3 for `Items.array` and `Items.sequence` with items of type `a`. `read` is `parse_with` of a `List(a)`.
check_items : Str, List(U8), List(List(List(U8))), OptSet, (List(U8), Cbor.Options -> Try(List(a), Errs)) -> {} where [a.Cbor.Parseable(Cbor.Error), a.is_eq : a, a -> Bool]
check_items = |name, bytes, chunkings, set, read| {
	options = to_options(set)
	got : Try(List(a), Errs)
	got = stream_items(Cbor.Items.array(options), [bytes])
	p1("Items.array ${name}", got, chunkings.map(|chunks| stream_items(Cbor.Items.array(options), chunks)))
	seq : Try(List(a), Errs)
	seq = stream_items(Cbor.Items.sequence(options), [bytes])
	p1("Items.sequence ${name}", seq, chunkings.map(|chunks| stream_items(Cbor.Items.sequence(options), chunks)))
	if run.p2 and set.max_buffer > 1_000 {
		# P2: the known difference is an empty byte string root, which a List(a) reads.
		agree =
			match (read(bytes, options), got) {
				(Ok(a), Ok(b)) => a == b
				(Err(_), Err(_)) => Bool.True
				(Ok(_), Err(_)) => root_major(bytes, set) == 2
				(Err(_), Ok(_)) => Bool.False
			}
		if !agree {
			crash "P2 Items.array does not agree with parse_with: ${name}"
		}
		whole_seq : Try(List(a), Errs)
		whole_seq = Cbor.parse_sequence_with(bytes, options)
		if whole_seq != seq {
			crash "P2 Items.sequence does not agree with parse_sequence_with: ${name}"
		}
	}
	if run.p3 and set.max_buffer > 1_000 {
		model : Try(List(a), Errs)
		model = array_model(bytes, set)
		if model != got {
			crash "P3 Items.array is not the model: ${name}"
		}
		seq_model : Try(List(a), Errs)
		seq_model = sequence_model(bytes, set)
		if seq_model != seq {
			crash "P3 Items.sequence is not the model: ${name}"
		}
	}
}

## P1, P2 and P3 for `Entries.map` with keys `k` and values `v`. `read` is `parse_with` of a `Dict(k, v)`.
check_entries : Str, List(U8), List(List(List(U8))), OptSet, (List(U8), Cbor.Options -> Try(Dict(k, v), Errs)) -> {} where [k.Cbor.Parseable(Cbor.Error), k.Cbor.Encodable([]), v.Cbor.Parseable(Cbor.Error), k.is_eq : k, k -> Bool, k.to_hash : k, Hasher -> Hasher, v.is_eq : v, v -> Bool]
check_entries = |name, bytes, chunkings, set, read| {
	options = to_options(set)
	got : Try(List((k, v)), Errs)
	got = stream_entries(Cbor.Entries.map(options), [bytes])
	p1("Entries ${name}", got, chunkings.map(|chunks| stream_entries(Cbor.Entries.map(options), chunks)))
	if run.p2 and set.max_buffer > 1_000 {
		# P2: the known differences are a root that is not a map, and Last with Any (NotStreamable).
		agree =
			match (read(bytes, options), got) {
				(Ok(a), Ok(b)) => Dict.from_list(b) == a and a.len() == b.len()
				(Err(_), Err(_)) => Bool.True
				(Ok(_), Err(NotStreamable)) => set.duplicate_keys == Last and set.key_order == Any
				(Ok(_), Err(_)) => root_major(bytes, set) != 5
				(Err(_), Ok(_)) => Bool.False
			}
		if !agree {
			crash "P2 Entries does not agree with parse_with of a Dict: ${name}"
		}
	}
	if run.p3 and set.max_buffer > 1_000 {
		model : Try(List((k, v)), Errs)
		model = entries_model(bytes, set)
		if model != got {
			crash "P3 Entries is not the model: ${name}"
		}
	}
}

## P1 and P2 for ByteChunks and TextChunks. The error positions agree with parse_with too.
check_chunks : List(U8), List(List(List(U8))), OptSet -> {}
check_chunks = |bytes, chunkings, set| {
	options = to_options(set)
	data = stream_bytes(Cbor.ByteChunks.new(options), [bytes])
	p1("ByteChunks", data, chunkings.map(|chunks| stream_bytes(Cbor.ByteChunks.new(options), chunks)))
	text = stream_text(Cbor.TextChunks.new(options), [bytes])
	p1("TextChunks", text, chunkings.map(|chunks| stream_text(Cbor.TextChunks.new(options), chunks)))
	# max_buffer does not apply to ByteChunks and TextChunks: the small buffer sets add nothing here.
	if run.p2 and set.max_buffer > 1_000 {
		want_data : Try(List(U8), ChunkErrs)
		want_data = Cbor.parse_with(bytes, options)
		# A List(U8) also reads an empty array (and an array of bytes with BytesFromArray): ByteChunks reads only a byte string,
		# and another root is an error at its head. With a byte string root, the same result and error position.
		data_ok = if (root_major(bytes, set) == 2) want_data == data else data.is_err()
		if !data_ok {
			crash "P2 ByteChunks does not agree with parse_with of a List(U8)"
		}
		want_text : Try(Str, ChunkErrs)
		want_text = Cbor.parse_with(bytes, options)
		# Another root (after the tags of ignore_tags) is an error at its head in TextChunks, and parse_with walks it first:
		# then only both Err. With a text root, the same error position.
		text_ok =
			match (want_text, text) {
				(Err(_), Err(_)) => root_major(bytes, set) != 3 or want_text == text
				_ => want_text == text
			}
		if !text_ok {
			crash "P2 TextChunks does not agree with parse_with of a Str"
		}
	}
}

## `parse_with` of a List(a) for each item type: a List(a) cannot be parsed in a generic function.
values : List(U8), Cbor.Options -> Try(List(Cbor.Value), Errs)
values = |b, o| Cbor.parse_with(b, o)

rows : List(U8), Cbor.Options -> Try(List(Row), Errs)
rows = |b, o| Cbor.parse_with(b, o)

wides : List(U8), Cbor.Options -> Try(List(U128), Errs)
wides = |b, o| Cbor.parse_with(b, o)

dicts : List(U8), Cbor.Options -> Try(List(Dict(U64, Str)), Errs)
dicts = |b, o| Cbor.parse_with(b, o)

shapes : List(U8), Cbor.Options -> Try(List(Shape), Errs)
shapes = |b, o| Cbor.parse_with(b, o)

text_keys : List(U8), Cbor.Options -> Try(Dict(Str, U64), Errs)
text_keys = |b, o| Cbor.parse_with(b, o)

int_keys : List(U8), Cbor.Options -> Try(Dict(U64, Cbor.Value), Errs)
int_keys = |b, o| Cbor.parse_with(b, o)

## Each decoder and each item type with one option set.
check_set : List(U8), List(List(List(U8))), OptSet -> {}
check_set = |bytes, chunkings, set| {
	check_items("Cbor.Value", bytes, chunkings, set, values)
	check_items("Row", bytes, chunkings, set, rows)
	check_items("U128", bytes, chunkings, set, wides)
	check_items("Dict(U64, Str)", bytes, chunkings, set, dicts)
	check_items("Shape", bytes, chunkings, set, shapes)
	check_entries("Dict(Str, U64)", bytes, chunkings, set, text_keys)
	check_entries("Dict(U64, Cbor.Value)", bytes, chunkings, set, int_keys)
	check_chunks(bytes, chunkings, set)
}

## The input as valid text (each bad byte sequence is U+FFFD) with code points of 2, 3 and 4 bytes after it, as one text and as a text of indefinite length with a
## chunk at each cut of `seed` (moved to a code point boundary): roots that ByteChunks and TextChunks read whole.
text_roots : List(U8), U64 -> List(List(U8))
text_roots = |bytes, seed| {
	text = Str.from_utf8_lossy(bytes).concat("é€😀")
	utf8 = text.to_utf8()
	var $s = seed
	var $cuts = []
	for _ in 0.U64..<4 {
		(r, s) = next_rand($s)
		$s = s
		var $c = r % (utf8.len() + 1)
		while $c < utf8.len() and (utf8.get($c) ?? 0).bitwise_and(0xc0) == 0x80 {
			$c = $c + 1
		}
		$cuts = $cuts.append($c)
	}
	sorted = $cuts.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same)
	var $indefinite = [0x7f]
	var $at = 0
	for c in sorted.append(utf8.len()) {
		$indefinite = $indefinite.concat(Cbor.encode(Str.from_utf8_lossy(utf8.sublist({ start: $at, len: c - $at }))))
		$at = c
	}
	[Cbor.encode(text), $indefinite.append(0xff)]
}

## A head of `major` with the argument `n` (the shortest head, `n` below 2^16).
head : U8, U64 -> List(U8)
head = |major, n| {
	m = major.shl_wrap(5)
	if n < 24 {
		[m.bitwise_or(n.to_u8_wrap())]
	} else if n < 256 {
		[m.bitwise_or(24), n.to_u8_wrap()]
	} else {
		[m.bitwise_or(25), n.shr_zf_wrap(8).to_u8_wrap(), n.bitwise_and(255).to_u8_wrap()]
	}
}

## Maps from the input: an entry for each byte `b` (up to 64), with the key `b % 5` (a text of one letter, or an
## integer) and the value `b // 5`, so keys repeat. Text keys in input order (definite length); integer keys in
## sorted order, so equal keys are runs (indefinite length); text keys sorted (definite length). Roots that Entries
## reads whole, for duplicate_keys and key_order: Sorted.
map_roots : List(U8) -> List(List(U8))
map_roots = |bytes| {
	pairs = bytes.take_first(64).map(|b| ((b % 5).to_u64(), (b // 5).to_u64()))
	text_key = |k| Cbor.encode(Str.from_utf8_lossy([97 + k.to_u8_wrap()]))
	entry = |key, (_, v)| key.concat(Cbor.encode(v))
	by_key = pairs.sort_with(|(a, _), (b, _)| if (a < b) Before else if (a > b) After else Same)
	n = pairs.len()
	texts = pairs.fold(head(5, n), |out, (k, v)| out.concat(entry(text_key(k), (k, v))))
	ints = by_key.fold([0xbf], |out, (k, v)| out.concat(entry(Cbor.encode(k), (k, v)))).append(0xff)
	sorted_texts = by_key.fold(head(5, n), |out, (k, v)| out.concat(entry(text_key(k), (k, v))))
	[texts, ints, sorted_texts]
}

test! : { seed : U64, bytes : List(U8) } => Fuzz.Outcome
test! = |input| {
	chunkings = splits(input.bytes, input.seed)
	for set in sets {
		check_set(input.bytes, chunkings, set)
	}
	for set in small_buffers {
		check_set(input.bytes, chunkings, set)
	}
	for root in text_roots(input.bytes, input.seed) {
		root_chunks = splits(root, input.seed.bitwise_xor(5))
		check_chunks(root, root_chunks, base)
		check_chunks(root, root_chunks, { ..base, allow: [IndefiniteLength] })
	}
	for root in map_roots(input.bytes) {
		root_chunks = splits(root, input.seed.bitwise_xor(9))
		for set in sets {
			check_entries("Dict(Str, U64)", root, root_chunks, set, text_keys)
			check_entries("Dict(U64, Cbor.Value)", root, root_chunks, set, int_keys)
		}
	}
	Fuzz.keep
}

## The seed of the splits comes from the end of the input (8 bytes), the bytes to decode are the rest.
input : Fuzz.Generator({ seed : U64, bytes : List(U8) })
input = Fuzz.map2(Fuzz.u64, Fuzz.raw_bytes, |seed, bytes| { seed, bytes })

## The property's value, from the input bytes: the generator reads them as its entropy, as roc-fuzz's own
## typed inputs do. The value type holds `Cbor` encoders, so it cannot have roc-fuzz's derived input format.
input_of : List(U8) -> { seed : U64, bytes : List(U8) }
input_of = |bytes| (input)(Arbitrary.new(bytes)).value

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
	name: "stream",
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || [] }),
		Fuzz.example({ name: "short", revision: "1", make: || [0x01, 0x82, 0x18, 0x2a, 0xa1, 0x61, 0x61, 0x00] }),
		Fuzz.example({ name: "ramp", revision: "1", make: || ramp }),
	],
	generator: Fuzz.raw_bytes,
	test!: |bytes| test!(input_of(bytes)),
	show: |bytes| Str.inspect(input_of(bytes)),
})
