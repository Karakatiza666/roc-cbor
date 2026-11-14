app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.6.1/GDoZFRDnzMRiVk9nE8wdWn52btGsM1GhcY9VDKqy9f1Y.tar.zst",
	pkg: "../src/main.roc",
}

import fuzz.Arbitrary
import fuzz.Fuzz
import pkg.Cbor

# L1 target: the stream writer Cbor.StreamWriter. The random choices come from a seed in the fuzz input.
#
# P4 writer round trip: random Cbor.Value items (from the fuzz input, and two from the seed) written through StreamWriter (each array, map, byte string and text
# streamed or as one item, a random Count or Indefinite, random chunk sizes for bytes and text, map entries as
# `entry`, as two items, or with the value streamed) read back with parse_with (IndefiniteLength only when used) as
# the same values. With key_order: Sorted the entries go in the order of their key bytes, and the bytes read with
# key_order: Sorted. The same for a sequence of the items (`sequence`, `parse_sequence_with`). Also: the bytes of
# `encode_with(v, { key_order: Sorted })` read with key_order: Sorted.
# P5 writer refuses: a random sequence of writer steps, then steps that close the open levels. A step that gives Err
# is dropped (the writer before it stays usable). When `finish` gives Ok, the bytes of the Ok steps are one valid item
# (or a valid sequence), and with key_order: Sorted they read with key_order: Sorted.

WErr : [CountMismatch, DuplicateMapKey, KeyOutOfOrder]

## The writer, the bytes so far, the random state, and whether an indefinite length was written.
WState : { w : Cbor.StreamWriter, out : List(U8), rng : U64, indefinite : Bool }

## The most steps of one P5 run.
step_limit : U64
step_limit = 400

## One step of splitmix64: a random value and the next state.
next_rand : U64 -> (U64, U64)
next_rand = |s| {
	z0 = s.plus_wrap(0x9e3779b97f4a7c15)
	z1 = z0.bitwise_xor(z0.shr_zf_wrap(30)).times_wrap(0xbf58476d1ce4e5b9)
	z2 = z1.bitwise_xor(z1.shr_zf_wrap(27)).times_wrap(0x94d049bb133111eb)
	(z2.bitwise_xor(z2.shr_zf_wrap(31)), z0)
}

rand : WState -> (U64, WState)
rand = |st| {
	(r, s) = next_rand(st.rng)
	(r, { ..st, rng: s })
}

## The state after one writer step: its bytes after the bytes so far.
step : WState, Try({ bytes : List(U8), writer : Cbor.StreamWriter }, WErr) -> Try(WState, WErr)
step = |st, r| {
	x = r?
	Ok({ ..st, w: x.writer, out: st.out.concat(x.bytes) })
}

## A level step, with the error union of the other steps.
level : Try({ bytes : List(U8), writer : Cbor.StreamWriter }, [CountMismatch]) -> Try({ bytes : List(U8), writer : Cbor.StreamWriter }, WErr)
level = |r| r.map_err(|CountMismatch| CountMismatch)

## Random cuts of `n` bytes, sorted: up to 5. A cut can repeat (an empty chunk).
cuts : WState, U64 -> (List(U64), WState)
cuts = |st, n| {
	(r, s0) = rand(st)
	var $st = s0
	var $out = []
	for _ in 0.U64..<(r % 6) {
		(c, s) = rand($st)
		$st = s
		$out = $out.append(c % (n + 1))
	}
	($out.sort_with(|a, b| if (a < b) Before else if (a > b) After else Same), $st)
}

## The parts of `bytes` at `points`.
parts : List(U8), List(U64) -> List(List(U8))
parts = |bytes, points| {
	var $out = []
	var $at = 0
	for c in points {
		$out = $out.append(bytes.sublist({ start: $at, len: c - $at }))
		$at = c
	}
	$out.append(bytes.drop_first($at))
}

## A cut moved forward to the start of a code point.
boundary : List(U8), U64 -> U64
boundary = |bytes, c| {
	var $c = c
	while $c < bytes.len() and (bytes.get($c) ?? 0).bitwise_and(0xc0) == 0x80 {
		$c = $c + 1
	}
	$c
}

## The key bytes of key_order: Sorted.
sorted_key : Cbor.Value -> List(U8)
sorted_key = |k| Cbor.encode_with(k, { key_order: Sorted }) ?? []

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

## Writes `v` through the writer: a container, a byte string or a text streamed (2 times of 3) or as one item.
write_value : WState, Cbor.Value, Bool -> Try(WState, WErr)
write_value = |st0, v, sorted| {
	(r, st) = rand(st0)
	streamed = r % 3 != 0
	definite = r // 3 % 2 == 0
	match v {
		Array(items) if streamed => {
			var $st = step({ ..st, indefinite: st.indefinite or !definite }, level(st.w.open_array(if (definite) Count(items.len()) else Indefinite)))?
			for x in items {
				$st = write_value($st, x, sorted)?
			}
			step($st, level($st.w.close()))
		}
		Map(m) if streamed => {
			pairs =
				if sorted {
					m.to_list().sort_with(|(a, _), (b, _)| if (before(sorted_key(a), sorted_key(b))) Before else if (sorted_key(a) == sorted_key(b)) Same else After)
				} else {
					m.to_list()
				}
			var $st = step({ ..st, indefinite: st.indefinite or !definite }, level(st.w.open_map(if (definite) Count(pairs.len()) else Indefinite)))?
			for (k, x) in pairs {
				(how, s) = rand($st)
				match how % 3 {
					0 => {
						$st = step(s, s.w.entry(k, x))?
					}
					1 => {
						keyed = step(s, s.w.item(k))?
						$st = write_value(keyed, x, sorted)?
					}
					_ => {
						# With Given, the key can be streamed too. With Sorted a level at a key place is CountMismatch.
						keyed = if (sorted) step(s, s.w.item(k))? else write_value(s, k, sorted)?
						$st = write_value(keyed, x, sorted)?
					}
				}
			}
			step($st, level($st.w.close()))
		}
		Bytes(data) if streamed => {
			var $st = step({ ..st, indefinite: st.indefinite or !definite }, level(st.w.open_bytes(if (definite) Length(data.len()) else Indefinite)))?
			(points, s) = cuts($st, data.len())
			$st = s
			for piece in parts(data, points) {
				$st = step($st, level($st.w.bytes_chunk(piece)))?
			}
			step($st, level($st.w.close()))
		}
		Text(text) if streamed => {
			utf8 = text.to_utf8()
			var $st = step({ ..st, indefinite: st.indefinite or !definite }, level(st.w.open_text(if (definite) Length(utf8.len()) else Indefinite)))?
			(points, s) = cuts($st, utf8.len())
			$st = s
			for piece in parts(utf8, points.map(|c| boundary(utf8, c))) {
				chunk = Str.from_utf8(piece) ?? crash "a cut inside a code point"
				$st = step($st, level($st.w.text_chunk(chunk)))?
			}
			step($st, level($st.w.close()))
		}
		_ => step(st, st.w.item(v))
	}
}

## A map key that is an array or a map: two such keys can be different values with the same sorted bytes.
has_container_key : Cbor.Value -> Bool
has_container_key = |v|
	match v {
		Array(items) => items.any(has_container_key)
		Map(m) =>
			m.to_list().any(
				|(k, x)|
					match k {
						Array(_) | Map(_) => Bool.True
						_ => has_container_key(k) or has_container_key(x)
					},
			)
		Tag(_, inner) => has_container_key(inner)
		_ => Bool.False
	}

## The read options for bytes that the writer wrote.
read_options : Bool, Bool -> Cbor.Options
read_options = |sorted, indefinite| { allow: if (indefinite) [IndefiniteLength] else [], key_order: if (sorted) Sorted else Any }

## The same value: with Sorted, the map entries can come in another order, so the bytes of the Sorted encode compare.
same : Cbor.Value, Cbor.Value, Bool -> Bool
same = |a, b, sorted| if (sorted) sorted_key(a) == sorted_key(b) else a == b

## P4 for each value and for the sequence of the values, with one write option.
p4 : List(Cbor.Value), U64, Bool -> {}
p4 = |vs, seed, sorted| {
	options : Cbor.WriteOptions
	options = if (sorted) { key_order: Sorted } else { key_order: Given }
	if sorted and vs.any(has_container_key) {
		# A DuplicateMapKey is possible: the round trip of fuzz/round_trip.roc checks those values.
		return {}
	}
	var $rng = seed
	for v in vs {
		start = { w: Cbor.StreamWriter.new(options), out: [], rng: $rng, indefinite: Bool.False }
		match write_value(start, v, sorted) {
			Ok(st) => {
				$rng = st.rng
				if st.w.finish() != Ok({}) {
					crash "P4: finish gives Err after one whole item"
				}
				back : Try(Cbor.Value, Cbor.Error)
				back = Cbor.parse_with(st.out, read_options(sorted, st.indefinite))
				match back {
					Ok(b) if same(b, v, sorted) => {}
					_ => crash "P4: the streamed item does not read back as the same value"
				}
			}
			Err(_) => crash "P4: the writer refuses a valid step"
		}
		if sorted {
			sorted_back : Try(Cbor.Value, Cbor.Error)
			sorted_back = Cbor.parse_with(sorted_key(v), { key_order: Sorted })
			if sorted_back.map_ok(|b| same(b, v, sorted)) != Ok(Bool.True) {
				crash "P4: encode_with key_order: Sorted does not read with key_order: Sorted"
			}
		}
	}
	# The values as one sequence.
	var $st = { w: Cbor.StreamWriter.sequence(options), out: [], rng: $rng, indefinite: Bool.False }
	for v in vs {
		$st =
			match write_value($st, v, sorted) {
				Ok(s) => s
				Err(_) => crash "P4: the sequence writer refuses a valid step"
			}
	}
	if $st.w.finish() != Ok({}) {
		crash "P4: finish of a sequence gives Err"
	}
	back : Try(List(Cbor.Value), Cbor.Error)
	back = Cbor.parse_sequence_with($st.out, read_options(sorted, $st.indefinite))
	ok =
		match back {
			Ok(bs) => bs.len() == vs.len() and bs.map_with_index(|b, i| same(b, vs.get(i) ?? b, sorted)).all(|t| t)
			Err(_) => Bool.False
		}
	if !ok {
		crash "P4: the streamed sequence does not read back as the same values"
	}
}

## A small value for P5: an integer, a text, an empty array or map, a null, a nested array.
small_value : U64 -> Cbor.Value
small_value = |r|
	match r % 6 {
		0 => Cbor.Value.Int(Cbor.IntValue.from_u64(r // 6 % 40))
		1 => Cbor.Value.Text(if (r // 6 % 2 == 0) "k" else "é")
		2 => Cbor.Value.Array([])
		3 => Cbor.Value.Null
		4 => Cbor.Value.Array([Cbor.Value.Int(Cbor.IntValue.from_u64(r // 6 % 3))])
		_ => Cbor.Value.Bytes([1, 2])
	}

## One random writer step. A step that gives Err is dropped.
random_step : WState -> WState
random_step = |st0| {
	(r, st) = rand(st0)
	pick = r % 11
	r2 = r // 11
	indefinite = r2 % 4 == 0
	n = r2 // 4 % 5
	tried =
		match pick {
			0 => step({ ..st, indefinite: st.indefinite or indefinite }, level(st.w.open_array(if (indefinite) Indefinite else Count(n))))
			1 => step({ ..st, indefinite: st.indefinite or indefinite }, level(st.w.open_map(if (indefinite) Indefinite else Count(n % 3))))
			2 => step({ ..st, indefinite: st.indefinite or indefinite }, level(st.w.open_bytes(if (indefinite) Indefinite else Length(n))))
			3 => step({ ..st, indefinite: st.indefinite or indefinite }, level(st.w.open_text(if (indefinite) Indefinite else Length(n))))
			4 | 5 => step(st, st.w.item(small_value(r2)))
			6 => step(st, st.w.entry(small_value(r2), small_value(r2 // 7)))
			7 => step(st, level(st.w.bytes_chunk(List.repeat(7, n % 4))))
			8 => step(st, level(st.w.text_chunk(if (n % 3 == 0) "é" else if (n % 3 == 1) "ab" else "")))
			_ => step(st, level(st.w.close()))
		}
	tried ?? st
}

## Steps that close the open levels: close, an item, a byte, a character. The first one that gives Ok.
## An item key grows, so that it comes after the keys before it.
closing_step : WState, U64 -> WState
closing_step = |st, i| {
	tries = [
		|s| step(s, level(s.w.close())),
		|s| step(s, s.w.item(Cbor.Value.Int(Cbor.IntValue.from_u64(1000 + i)))),
		|s| step(s, level(s.w.bytes_chunk([0]))),
		|s| step(s, level(s.w.text_chunk("a"))),
	]
	tries.fold_until(
		st,
		|s, f|
			match f(s) {
				Ok(next) => Break(next)
				Err(_) => Continue(s)
			},
	)
}

## P5 with one root kind and one write option.
p5 : U64, Bool, Bool -> {}
p5 = |seed, sorted, sequence| {
	options : Cbor.WriteOptions
	options = if (sorted) { key_order: Sorted } else { key_order: Given }
	w = if (sequence) Cbor.StreamWriter.sequence(options) else Cbor.StreamWriter.new(options)
	(r, s0) = next_rand(seed)
	var $st = { w, out: [], rng: s0, indefinite: Bool.False }
	for _ in 0.U64..<(r % 40) {
		$st = random_step($st)
	}
	var $i = 0
	while $st.w.finish() != Ok({}) and $i < step_limit {
		$st = closing_step($st, $i)
		$i = $i + 1
	}
	if $st.w.finish() == Ok({}) {
		# With Given, the keys of a streamed map are not checked: the first instance of a key reads.
		read : Cbor.Options
		read = { allow: [IndefiniteLength], key_order: if (sorted) Sorted else Any, duplicate_keys: if (sorted) Reject else First }
		valid =
			if sequence {
				all : Try(List(Cbor.Value), Cbor.Error)
				all = Cbor.parse_sequence_with($st.out, read)
				all.is_ok()
			} else {
				one : Try(Cbor.Value, Cbor.Error)
				one = Cbor.parse_with($st.out, read)
				one.is_ok()
			}
		if !valid {
			crash "P5: the steps that gave Ok, and finish Ok, wrote bytes that are not one valid item"
		}
	} else if !sorted {
		crash "P5: the closing steps did not close the writer"
	}
}

## The characters of the random texts: code points of 1, 2, 3 and 4 bytes of UTF-8.
letters : List(Str)
letters = ["a", "é", "€", "😀", "z", "b"]

## A random Cbor.Value from the state `s0`, of a depth of `depth` or less: also from a short fuzz input, so that P4
## has texts with code points of each size, longer byte strings and nested containers in each run.
rand_value : U64, U64 -> (Cbor.Value, U64)
rand_value = |s0, depth| {
	(r, s1) = next_rand(s0)
	pick = if (depth == 0) r % 6 else r % 9
	n = r.shr_zf_wrap(8) % 12
	match pick {
		0 => (Cbor.Value.Int(Cbor.IntValue.from_u64(r.shr_zf_wrap(8) % 100_000)), s1)
		1 => {
			text = (0.U64).until(n).fold("", |t, i| t.concat(letters.get(r.shr_zf_wrap((16 + 3 * i).to_u8_wrap()) % 6) ?? "a"))
			(Cbor.Value.Text(text), s1)
		}
		2 => (Cbor.Value.Bytes((0.U64).until(n + 8).fold([], |l, i| l.append(r.shr_zf_wrap((i % 8 * 8).to_u8_wrap()).plus_wrap(i).to_u8_wrap()))), s1)
		3 => (Cbor.Value.Float(F64.from_bits(r)), s1)
		4 => (Cbor.Value.Null, s1)
		5 => (Cbor.Value.Bool(r % 2 == 0), s1)
		6 => {
			var $s = s1
			var $items = []
			for _ in 0.U64..<(n % 5) {
				(v, s) = rand_value($s, depth - 1)
				$items = $items.append(v)
				$s = s
			}
			(Cbor.Value.Array($items), $s)
		}
		7 => {
			var $s = s1
			var $m = Cbor.ValueMap.empty()
			for _ in 0.U64..<(n % 5) {
				(k, sk) = rand_value($s, 0)
				(v, sv) = rand_value(sk, depth - 1)
				$m = $m.insert(k, v)
				$s = sv
			}
			(Cbor.Value.Map($m), $s)
		}
		_ => {
			(v, s) = rand_value(s1, depth - 1)
			(Cbor.Value.Tag(r.shr_zf_wrap(8) % 30, v), s)
		}
	}
}

test! : { seed : U64, values : List(Cbor.Value) } => Fuzz.Outcome
test! = |g| {
	(extra, _) = rand_value(g.seed.bitwise_xor(4), 3)
	(other, _) = rand_value(g.seed.bitwise_xor(5), 3)
	values = g.values.concat([extra, other])
	p4(values, g.seed, Bool.False)
	p4(values, g.seed, Bool.True)
	# P5: 4 random step sequences for each root kind and write option.
	for i in 0.U64..<4 {
		s = g.seed.plus_wrap(i.shl_wrap(8))
		p5(s, Bool.False, Bool.False)
		p5(s.bitwise_xor(1), Bool.True, Bool.False)
		p5(s.bitwise_xor(2), Bool.False, Bool.True)
		p5(s.bitwise_xor(3), Bool.True, Bool.True)
	}
	Fuzz.keep
}

## A Cbor.Value with no container (the leaves of fuzz/round_trip.roc, with valid ranges only).
leaf : Fuzz.Generator(Cbor.Value)
leaf = Fuzz.map(
	{ pick: Fuzz.u8, n: Fuzz.u64, s: Fuzz.str }.Fuzz,
	|g|
		match g.pick % 9 {
			0 => Cbor.Value.Int(Cbor.IntValue.from_u64(g.n))
			1 => Cbor.Value.Int(Cbor.IntValue.from_i64(g.n.to_i64_wrap()))
			2 => Cbor.Value.Float(F64.from_bits(g.n))
			3 | 4 => Cbor.Value.Text(g.s)
			5 | 6 => Cbor.Value.Bytes(g.s.to_utf8().append(g.n.to_u8_wrap()))
			7 => Cbor.Value.Bool(g.pick > 128)
			_ => if (g.pick > 128) Cbor.Value.Null else Cbor.Value.Undefined
		},
)

## A Cbor.Value of a depth of `depth` or less: a leaf, an array, a map with any keys, or a tag.
any_value : U8 -> Fuzz.Generator(Cbor.Value)
any_value = |depth|
	if depth == 0 {
		leaf
	} else {
		Fuzz.map(
			{ pick: Fuzz.u8, keys: Fuzz.list(leaf, 3), items: Fuzz.list(any_value(depth - 1), 3) }.Fuzz,
			|g| {
				one = g.keys.first() ?? Cbor.Value.Null
				match g.pick % 6 {
					0 => one
					1 => Cbor.Value.Array(g.items)
					2 => Cbor.Value.Tag((g.pick // 6).to_u64(), g.items.first() ?? one)
					pick => {
						base = if (pick == 4) g.items else g.keys
						pairs = base.map_with_index(|k, i| (k, g.items.get(i) ?? one))
						Cbor.Value.Map(pairs.fold(Cbor.ValueMap.empty(), |acc, (key, x)| acc.insert(key, x)))
					}
				}
			},
		)
	}

## The seed comes from the end of the input (8 bytes), the values from the rest.
input : Fuzz.Generator({ seed : U64, values : List(Cbor.Value) })
input = Fuzz.map2(Fuzz.u64, Fuzz.list(any_value(3), 4), |seed, values| { seed, values })

## The property's value, from the input bytes: the generator reads them as its entropy, as roc-fuzz's own
## typed inputs do. The value type holds `Cbor` encoders, so it cannot have roc-fuzz's derived input format.
input_of : List(U8) -> { seed : U64, values : List(Cbor.Value) }
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
	name: "stream-writer",
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || [] }),
		Fuzz.example({ name: "short", revision: "1", make: || [0x01, 0x82, 0x18, 0x2a, 0xa1, 0x61, 0x61, 0x00] }),
		Fuzz.example({ name: "ramp", revision: "1", make: || ramp }),
	],
	generator: Fuzz.raw_bytes,
	test!: |bytes| test!(input_of(bytes)),
	show: |bytes| Str.inspect(input_of(bytes)),
})
