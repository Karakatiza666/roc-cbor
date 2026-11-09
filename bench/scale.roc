app [] { pkg: "../src/main.roc" }

# The scaling test of the writer. Usage: scale <case> <loops> <items>. scripts/scale.sh builds it with
# --opt=speed, one app for each case, and times each case at 5k, 10k, 20k and 40k items. The time for each item must not grow
# with the count of items: an output list that is copied at an append makes the encode quadratic.
# Each case is a list of `items` values of one container shape. HEAD only: the hand-written encoders
# use Cbor.Writer, which 0.4.1 does not have.

import pkg.Cbor

## A user id under the tag 6, written by hand (encode_tagged).
User := U64.{
	encoder_for : Cbor -> (User, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |User.(n), w| Cbor.encode_tagged(6, { user_id: n }, w)
}

## A list of a U8 then text: the writer writes the byte string again as an array.
Mixed := U8.{
	encoder_for : Cbor -> (Mixed, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Mixed.(b), w| Cbor.encode_list(w, 3, |c, add| add(add(add(c, |v| Cbor.encode_u8(b, v))?, |v| Cbor.encode_u8(b, v))?, |v| Cbor.encode_str("a", v)))
}

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

## Streams `rows` into one indefinite array with Cbor.StreamWriter, one step for each row. Gives the count of bytes.
stream_array : List({ id : U64, name : Str }) -> U64
stream_array = |rows| {
	opened = Cbor.StreamWriter.new({}).open_array(Indefinite) ?? crash "open_array"
	var $w = opened.writer
	var $total = opened.bytes.len()
	for row in rows {
		s = $w.item(row) ?? crash "item"
		$total = $total + s.bytes.len()
		$w = s.writer
	}
	closed = $w.close() ?? crash "close"
	$total + closed.bytes.len()
}

## Streams `n` entries into one indefinite map with key_order: Sorted: each key is checked against the key before it.
stream_sorted : U64, U64 -> U64
stream_sorted = |n, seed| {
	opened = Cbor.StreamWriter.new({ key_order: Sorted }).open_map(Indefinite) ?? crash "open_map"
	var $w = opened.writer
	var $total = opened.bytes.len()
	for i in (0.U64).until(n) {
		s = $w.entry(i + seed, "v") ?? crash "entry"
		$total = $total + s.bytes.len()
		$w = s.writer
	}
	closed = $w.close() ?? crash "close"
	$total + closed.bytes.len()
}

run : Str, U64, U64, U64 -> Try(U64, [UnknownCase])
run = |case, loops, n, seed|
	match case {
		"u64" => {
			v = make(n, |i| i + seed)
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"records" => {
			v = make(n, |i| { name: "user-${(i + seed).to_str()}", id: i + seed, ok: i % 2 == 0, score: (i + seed).to_f64() * 1.5, tags: ["a", "b${(i % 7).to_str()}"] })
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"lists" => {
			v = make(n, |i| ["a", "b${(i + seed).to_str()}"])
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"tuples" => {
			v = make(n, |i| (i + seed, [i, i]))
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"tags" => {
			v : List([A(List(U64)), B(U64, Str), C])
			v = make(n, |i| if (i % 3 == 0) A([i + seed]) else if (i % 3 == 1) B(i, "x") else C)
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"nested" => {
			v = make(n, |i| { a: { b: [{ c: [i + seed] }] }, t: (i, [Ok(i), Err(Null)]) })
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"absent" => {
			v : List({ a : U64, b : Try(U64, [Missing]), c : List(U64) })
			v = make(n, |i| { a: i + seed, b: if (i % 2 == 0) Err(Missing) else Ok(i), c: [i] })
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"u8lists" => {
			v = make(n, |i| { b: [(i + seed).to_u8_wrap(), 1, 2, 3] })
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"bytes" => {
			v = make(n, |i| { b: Cbor.Bytes.from_list([(i + seed).to_u8_wrap(), 1, 2, 3]) })
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"tagged" => {
			v = make(n, |i| User.(i + seed))
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"fallback" => {
			v = make(n, |i| Mixed.((i + seed).to_u8_wrap()))
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"dict_encode" => {
			v = Dict.from_list(make(n, |i| (i + seed, { w: (i + seed).to_u128().shl_wrap(70), s: "x" })))
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"sorted_records" => {
			# key_order: Sorted: each record is a map of 5 entries to sort.
			v = make(n, |i| { name: "user-${(i + seed).to_str()}", id: i + seed, ok: i % 2 == 0, score: (i + seed).to_f64() * 1.5, tags: ["a", "b${(i % 7).to_str()}"] })
			Ok(repeat(loops, |_| (Cbor.encode_with(v, { key_order: Sorted }) ?? []).len()))
		}
		"sorted_map" => {
			# key_order: Sorted: one map of n entries, in the order of the Dict (not sorted).
			v = Dict.from_list(make(n, |i| ("k${((i * 7919 + seed) % n).to_str()}", i)))
			Ok(repeat(loops, |_| (Cbor.encode_with(v, { key_order: Sorted }) ?? []).len()))
		}
		"value" => {
			v = Cbor.Value.Array(make(n, |i| Cbor.Value.Array([Cbor.Value.Int(Cbor.IntValue.from_u64(i + seed)), Cbor.Value.Text("x")])))
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"stream_array" => {
			# Cbor.StreamWriter: n records streamed into one indefinite array. The writer keeps no output.
			v = make(n, |i| { id: i + seed, name: "user-${i.to_str()}" })
			Ok(repeat(loops, |_| stream_array(v)))
		}
		"stream_sorted" => {
			# Cbor.StreamWriter with key_order: Sorted: n entries streamed into one indefinite map, one key compare each.
			Ok(repeat(loops, |_| stream_sorted(n, seed)))
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
