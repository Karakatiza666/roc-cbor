app [main!] {
	cbor: "../../src/main.roc",
	pf: platform "platform/main.roc",
}

## The second app of scripts/wasm_dev.sh: the stream decoder Cbor.Entries, built with --target=wasm32 --opt=dev.
## A shape in its own app (shape 9, seed 9 * 256 + n): in tests/wasm_dev/app.roc, the code of Cbor.Entries made the
## case `deep` trap on nightly 2026-10-19 (its frames are close to the stack there, roc-lang/roc#12922). On 11-07
## the stack of `deep` does not change with it. The result is a checksum of the output bytes.
import cbor.Cbor

## The entries of a map in `chunks`, read with Cbor.Entries and `push` (key_order: Sorted, duplicate_keys: Last: an
## entry is held until the next key).
read_entries : List(List(U8)) -> List((U64, U64))
read_entries = |chunks| {
	var $entries = Cbor.Entries.map({ key_order: Sorted, duplicate_keys: Last })
	var $out = []
	for chunk in chunks {
		r : { values : List((U64, U64)), rest : Try(Cbor.Entries, _) }
		r = $entries.push(chunk)
		$out = $out.concat(r.values)
		$entries =
			match r.rest {
				Ok(next) => next
				Err(_) => Cbor.Entries.map({})
			}
	}
	$out
}

## { 7: 1, 7: 24 + n % 200, 9: 300 } by hand (see shape 8), read with read_entries: Last gives the second 7.
entries_case : U64 -> List(U8)
entries_case = |n| {
	input = [0xa3, 0x07, 0x01, 0x07, 0x18, (24 + n % 200).to_u8_wrap(), 0x09, 0x19, 0x01, 0x2c]
	var $out = []
	for (k, v) in read_entries(input.chunks_of(3)) {
		$out = $out.append(k.to_u8_wrap()).append(v.to_u8_wrap()).append(v.shr_zf_wrap(8).to_u8_wrap())
	}
	$out
}

main! : U64 => U64
main! = |seed| {
	bytes = if (seed // 256 == 9) entries_case(seed % 256) else []
	bytes.fold(bytes.len(), |acc, x| acc.times_wrap(31).plus_wrap(x.to_u64()))
}
