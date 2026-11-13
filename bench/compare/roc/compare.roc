app [] { pkg: "../../../src/main.roc" }

# The Roc side of bench/compare. Usage: compare <case> <loops>
# The inputs are the fixtures of bench/compare/run.py (written by bench/bench.roc `dump`), embedded at
# build time, so that Roc parses the same bytes as the other languages and builds no input at setup.
# The setup of an encode case parses the fixture into the value to encode (the same as the others).
# The output is "case loops checksum"; the contract of each case is in bench/compare/README.md.

import pkg.Cbor
import "../../../.cache/compare/fixtures/bytes.cbor" as bytes_cbor_c : List(U8)
import "../../../.cache/compare/fixtures/records.cbor" as records_cbor_c : List(U8)
import "../../../.cache/compare/fixtures/wide.cbor" as wide_cbor_c : List(U8)
import "../../../.cache/compare/fixtures/dict.cbor" as dict_cbor_c : List(U8)
import "../../../.cache/compare/fixtures/texts.cbor" as texts_cbor_c : List(U8)
import "../../../.cache/compare/fixtures/deep.cbor" as deep_cbor_c : List(U8)

Rec : { name : Str, id : U64, ok : Bool, score : F64, tags : List(Str) }

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

is_ok : Try(a, _) -> U64
is_ok = |r| if (r.is_ok()) 1 else 0

## The fixture, through a value the compiler cannot know (seed is 0 at run time). Without it, the
## compiler evaluates a parse of a constant fixture at build time.
at_runtime : U64, List(U8) -> List(U8)
at_runtime = |seed, l| if (seed > 1000) [] else l

run : Str, U64, U64 -> Try(U64, [UnknownCase, BadFixture])
run = |case, loops, seed| {
	bytes_cbor = at_runtime(seed, bytes_cbor_c)
	records_cbor = at_runtime(seed, records_cbor_c)
	wide_cbor = at_runtime(seed, wide_cbor_c)
	dict_cbor = at_runtime(seed, dict_cbor_c)
	texts_cbor = at_runtime(seed, texts_cbor_c)
	deep_cbor = at_runtime(seed, deep_cbor_c)
	match case {
		"bytes_encode" => {
			b : Cbor.Bytes
			b = Cbor.parse(bytes_cbor) ? |_| BadFixture
			Ok(repeat(loops, |_| Cbor.encode(b).len()))
		}
		"bytes_parse" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Bytes, _)
						r = Cbor.parse(bytes_cbor)
						r.map_ok(|b| b.to_list().len()) ?? 1_000_000
					},
				),
			)
		"records_encode" => {
			rs : List(Rec)
			rs = Cbor.parse(records_cbor) ? |_| BadFixture
			Ok(repeat(loops, |_| Cbor.encode(rs).len()))
		}
		"records_parse" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Rec), _)
						r = Cbor.parse(records_cbor)
						parse_len(r)
					},
				),
			)
		"records_value" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(records_cbor)
						is_ok(r)
					},
				),
			)
		"unknown_parse" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Rec), _)
						r = Cbor.parse(wide_cbor)
						parse_len(r)
					},
				),
			)
		"dict_parse" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Dict(Str, U64), _)
						r = Cbor.parse(dict_cbor)
						r.map_ok(|d| d.len()) ?? 1_000_000
					},
				),
			)
		"map_value" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(dict_cbor)
						is_ok(r)
					},
				),
			)
		"text_parse" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(List(Str), _)
						r = Cbor.parse(texts_cbor)
						parse_len(r)
					},
				),
			)
		"deep_encode" => {
			v : Cbor.Value
			v = Cbor.parse(deep_cbor) ? |_| BadFixture
			Ok(repeat(loops, |_| Cbor.encode(v).len()))
		}
		"deep_parse" =>
			Ok(
				repeat(
					loops,
					|_| {
						r : Try(Cbor.Value, _)
						r = Cbor.parse(deep_cbor)
						is_ok(r)
					},
				),
			)
		_ => Err(UnknownCase)
	}
}

main! = |args| {
	case = args.get(0) ?? ""
	loops = U64.from_str(args.get(1) ?? "0") ?? 0
	# The seed is 0 (2 args), but the compiler cannot know it.
	seed = args.len() // 8
	match run(case, loops, seed) {
		Ok(sum) => {
			echo!("${case} ${loops.to_str()} ${sum.to_str()}\n")
			Ok({})
		}
		Err(_) => {
			echo!("unknown case or bad fixture: ${case}\n")
			Err(Exit(2))
		}
	}
}
