app [] { pkg: "../src/main.roc" }

# The scaling test of the adapters to the builtin `Stream`. Usage: scale_stream <case> <loops> <items>. scripts/scale.sh
# builds it as it builds bench/scale_read.roc: with --opt=speed, one app for each case. A `Stream` is effectful, so
# `run!` and each arm are effectful, and this file is apart from bench/scale_read.roc (where `run` is pure).
# The source is a list of chunks, lifted with `Stream.from_iter`. The time for each item must not grow with the count.

import pkg.Cbor

Rec : { user_name : Str, id : U64, is_ok : Bool, score : F64, tags : List(Str) }

## The list of `n` values from `f`.
make : U64, (U64 -> a) -> List(a)
make = |n, f| (0.U64).until(n).fold(List.with_capacity(n), |acc, i| acc.append(f(i)))

rec : U64 -> Rec
rec = |i| { user_name: "user-${i.to_str()}", id: i, is_ok: i % 2 == 0, score: i.to_f64() * 1.5, tags: ["a", "b${(i % 7).to_str()}"] }

## The sum of `work!` for each loop.
repeat! : U64, (U64 => U64) => U64
repeat! = |loops, work!| {
	var $sum = 0
	for i in (0.U64).until(loops) {
		$sum = $sum + work!(i)
	}
	$sum
}

## A source of the chunks.
source : List(List(U8)) -> Stream(Try(List(U8), [Never]))
source = |chunks| Stream.from_iter(chunks.map(|c| Ok(c)).iter())

## The memory cases (scripts/scale.sh measures the maximum RSS of one run): the chunks are made one at a time, so the
## input is never in memory at once.

## A chunk of the memory cases: 1 MiB.
mib : U64
mib = 1_048_576

## The counter of stream_5gb: the byte at stream position i of the data is i % 251. `pattern` has the bytes of each
## chunk, from position i % 251 on: a chunk and the expected bytes are `sublist`s of it, with no copy.
pattern : List(U8)
pattern = (0.U64).until(mib + 251).fold(List.with_capacity(mib + 251), |acc, i| acc.append((i % 251).to_u8_wrap()))

## Chunk k of `total` data bytes (chunks of 1 MiB, the last one shorter).
counter_chunk : U64, U64 -> List(U8)
counter_chunk = |k, total| {
	start = k * mib
	len = if (total - start < mib) total - start else mib
	pattern.sublist({ start: start % 251, len })
}

## The item of stream_memory: a byte string of 98 bytes, 100 bytes with its head.
memory_item : List(U8)
memory_item = [0x58, 98].concat(List.repeat(0x5a, 98))

## The items of one chunk of stream_memory (62,500 bytes).
memory_block : U64
memory_block = 625

## The head of an array of n items, with the shortest argument (an array of indefinite length needs an option).
array_head : U64 -> List(U8)
array_head = |n| {
	be = |count| (0.U64).until(count).fold([], |acc, i| acc.append(n.shr_zf_wrap(8 * (count - 1 - i).to_u8_wrap()).to_u8_wrap()))
	if n < 24 {
		[0x80 + n.to_u8_wrap()]
	} else if n < 0x100 {
		[0x98].concat(be(1))
	} else if n < 0x1_0000 {
		[0x99].concat(be(2))
	} else if n < 0x1_0000_0000 {
		[0x9a].concat(be(4))
	} else {
		[0x9b].concat(be(8))
	}
}

## Chunk k of stream_memory for n items: the head of the array, the blocks of items, then the items left.
memory_chunk : U64, U64, List(U8) -> List(U8)
memory_chunk = |k, n, block| {
	full = n // memory_block
	if k == 0 {
		array_head(n)
	} else if k <= full {
		block
	} else {
		List.repeat(memory_item, n % memory_block).join()
	}
}

run! : Str, U64, U64, U64 => Try(U64, [UnknownCase])
run! = |case, loops, n, seed|
	match case {
		"stream_adapter" => {
			# Cbor.Items.from_stream: an array of one item, a list of n records, in chunks of 256 bytes. The item is open
			# for each chunk: an adapter that keeps a second reference to the decoder makes each chunk copy all of
			# the open item, quadratic here.
			chunks = Cbor.encode([make(n, |i| rec(i + seed))]).chunks_of(256)
			Ok(
				repeat!(
					loops,
					|_| {
						items : Stream(Try(List(Rec), _))
						items = Cbor.Items.array({ max_buffer: 1_000_000_000 }).from_stream(source(chunks))
						items.fold!(0, |acc, r| acc + (r.map_ok(|l| l.len()) ?? 1_000_000))
					},
				),
			)
		}
		"stream_adapter_items" => {
			# Cbor.Items.from_stream: an array of n records in chunks of 4 KiB, one step for each record.
			chunks = Cbor.encode(make(n, |i| rec(i + seed))).chunks_of(4096)
			Ok(
				repeat!(
					loops,
					|_| {
						items : Stream(Try(Rec, _))
						items = Cbor.Items.array({}).from_stream(source(chunks))
						items.fold!(0, |acc, r| acc + (if (r.is_ok()) 1 else 1_000_000))
					},
				),
			)
		}
		"stream_adapter_write" => {
			# Cbor.StreamWriter.array_stream of n records: the count of output bytes.
			rows = make(n, |i| rec(i + seed))
			Ok(
				repeat!(
					loops,
					|_| {
						rows_source : Stream(Try(Rec, [Never]))
						rows_source = Stream.from_iter(rows.map(|r| Ok(r)).iter())
						Cbor.StreamWriter.array_stream(rows_source, Indefinite, {}).fold!(0, |acc, p| acc + (p.map_ok(|b| b.len()) ?? 1_000_000))
					},
				),
			)
		}
		"stream_memory" => {
			# Not timed: scale.sh runs it one time at two counts and compares the maximum RSS. Cbor.Items.from_stream
			# of an array of n byte strings of 100 bytes, in chunks of 62,500 bytes made one at a time. The sum is n
			# when each item has its 98 bytes. A decoder that keeps all of its input grows with n.
			block = List.repeat(memory_item, memory_block).join()
			Ok(
				repeat!(
					loops,
					|_| {
						chunks : Stream(Try(List(U8), [Never]))
						chunks = Stream.from_iter((0.U64).until(n // memory_block + 2 + seed).map(|k| Ok(memory_chunk(k, n, block))))
						items : Stream(Try(List(U8), _))
						items = Cbor.Items.array({}).from_stream(chunks)
						items.fold!(0, |acc, r| acc + (if (r.map_ok(|l| l.len()) == Ok(98)) 1 else 1_000_000_000))
					},
				),
			)
		}
		"stream_5gb" => {
			# Not timed: scale.sh runs it one time (SCALE_BIG=1, n = 5,000,000,000 bytes) and reads the maximum RSS.
			# Cbor.StreamWriter.bytes_stream writes one byte string of n bytes from chunks of 1 MiB made one at a time,
			# and Cbor.ByteChunks.from_stream reads it back. The sum is n when each byte matches the counter.
			Ok(
				repeat!(
					loops,
					|_| {
						data : Stream(Try(List(U8), [Never]))
						data = Stream.from_iter((0.U64).until((n + mib - 1) // mib + seed).map(|k| Ok(counter_chunk(k, n))))
						cbor = Cbor.StreamWriter.bytes_stream(data, Length(n))
						out = Cbor.ByteChunks.new({}).from_stream(cbor)
						got = out.fold!(
							{ pos: 0, ok: Bool.True },
							|acc, r|
								match r {
									Ok(piece) => {
										len = piece.len()
										same = len <= mib and piece == pattern.sublist({ start: acc.pos % 251, len })
										{ pos: acc.pos + len, ok: acc.ok and same }
									}
									Err(_) => { pos: acc.pos, ok: Bool.False }
								},
						)
						if (got.ok) got.pos else 0
					},
				),
			)
		}
		_ => Err(UnknownCase)
	}

main! = |args| {
	case = args.get(0) ?? ""
	loops = U64.from_str(args.get(1) ?? "0") ?? 0
	n = U64.from_str(args.get(2) ?? "0") ?? 0
	# The seed is 0 (3 args), but the compiler cannot know it.
	seed = args.len() // 8
	match run!(case, loops, n, seed) {
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
