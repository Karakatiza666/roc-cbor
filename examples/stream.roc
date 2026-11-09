app [] { pkg: "../src/main.roc" }

# Streams of the builtin type `Stream`: data larger than memory, one chunk at a time. Uses Cbor.StreamWriter.array_stream
# and bytes_stream to write, and the `from_stream` of Cbor.Items, Cbor.Entries, Cbor.ByteChunks and Cbor.TextChunks to
# read, with `for!`. A platform gives a `Stream` of chunks (a request body, a file); here a list stands in for it.
# The push loop (`push` of each chunk, then `finish`) reads chunks that come one at a time without a `Stream`.
# Also Cbor.StreamWriter.map_stream, sequence_stream and text_stream. CI runs it on the source and on the bundle.

import pkg.Cbor

Row : { id : U64, name : Str }

## The error of the source here: a platform has its own (a closed union is fine).
ReadErr : [ReadFailed(Str)]

hex : List(U8) -> Str
hex = |bytes| {
	digits = "0123456789abcdef".to_utf8()
	pairs = bytes.map(|b| [digits.get((b // 16).to_u64()) ?? 0, digits.get((b % 16).to_u64()) ?? 0])
	Str.from_utf8(pairs.join()) ?? ""
}

## A stand-in for a platform stream: the chunks of `bytes`, `size` bytes each, then `ReadFailed` when `fail`.
body : List(U8), U64, Bool -> Stream(Try(List(U8), ReadErr))
body = |bytes, size, fail| {
	chunks = bytes.chunks_of(size).map(|c| Ok(c))
	Stream.from_iter((if (fail) chunks.append(Err(ReadFailed("connection reset"))) else chunks).iter())
}

## Writes the rows of `source` as one array of indefinite length: the bytes of the head, of each row, and the break.
export! : Stream(Try(Row, ReadErr)) => Try(List(U8), _)
export! = |source| {
	var $out = []
	for! piece in Cbor.StreamWriter.array_stream(source, Indefinite, {}) {
		$out = $out.concat(piece?)
	}
	Ok($out)
}

## Reads the rows of an array from a stream of chunks, one row at a time: the count of rows and the sum of the ids.
import_rows! : Stream(Try(List(U8), ReadErr)) => Try({ count : U64, sum : U64 }, _)
import_rows! = |source| {
	rows : Stream(Try(Row, _))
	rows = Cbor.Items.array({ allow: [IndefiniteLength] }).from_stream(source)
	var $count = 0
	var $sum = 0
	for! row in rows {
		r = row?
		echo!("  row ${r.id.to_str()}: ${r.name}\n")
		$count = $count + 1
		$sum = $sum + r.id
	}
	Ok({ count: $count, sum: $sum })
}

## The push loop: the sum of the ids of the rows in `chunks`. `push` gives the rows that each chunk completes and the
## next decoder, and `finish` checks that the array ended. The loop sets `$items` to the next decoder each time.
sum_ids : List(List(U8)) -> Try(U64, _)
sum_ids = |chunks| {
	var $items = Cbor.Items.array({ allow: [IndefiniteLength] })
	var $sum = 0
	for chunk in chunks {
		r : { values : List(Row), rest : Try(Cbor.Items, _) }
		r = $items.push(chunk)
		for row in r.values {
			$sum = $sum + row.id
		}
		$items = r.rest?
	}
	$items.finish()?
	Ok($sum)
}

main! = |_args| {
	rows = [{ id: 1, name: "ada" }, { id: 2, name: "grace" }, { id: 3, name: "€uro" }]
	source : Stream(Try(Row, ReadErr))
	source = Stream.from_iter(rows.map(|r| Ok(r)).iter())
	bytes = export!(source)?
	echo!("array_stream: ${hex(bytes)}\n")

	# Chunks of 5 bytes: most rows are cut, and the decoder waits for the next chunk.
	echo!("from_stream in chunks of 5 bytes:\n")
	totals = import_rows!(body(bytes, 5, Bool.False))?
	echo!("  ${totals.count.to_str()} rows, sum of ids ${totals.sum.to_str()}\n")

	# The push loop over the same chunks, and over a cut input.
	echo!("push loop in chunks of 5 bytes: sum of ids ${(sum_ids(bytes.chunks_of(5)) ?? 0).to_str()}\n")
	match sum_ids(bytes.drop_last(1).chunks_of(5)) {
		Ok(_) => echo!("  no error?\n")
		Err(InvalidCbor(p)) => echo!("  cut input: InvalidCbor(${p.to_str()})\n")
		Err(_) => echo!("  another error\n")
	}

	# A source error comes out as Input(e), after the rows before it.
	echo!("from_stream with a source error after 20 bytes:\n")
	match import_rows!(body(bytes.take_first(20), 20, Bool.True)) {
		Ok(_) => echo!("  no error?\n")
		Err(Input(ReadFailed(msg))) => echo!("  Input(ReadFailed(\"${msg}\"))\n")
		Err(_) => echo!("  another error\n")
	}

	# A map, one entry at a time.
	map_source : Stream(Try((Str, U64), ReadErr))
	map_source = Stream.from_iter([Ok(("a", 1)), Ok(("b", 2))].iter())
	var $map = []
	for! piece in Cbor.StreamWriter.map_stream(map_source, Count(2), { key_order: Sorted }) {
		$map = $map.concat(piece?)
	}
	echo!("map_stream: ${hex($map)}\n")
	entries : Stream(Try((Str, U64), _))
	entries = Cbor.Entries.map({ key_order: Sorted }).from_stream(body($map, 3, Bool.False))
	for! entry in entries {
		(key, value) = entry?
		echo!("  ${key} = ${value.to_str()}\n")
	}

	# A byte string of definite length, written from chunks and read back as chunks.
	data : Stream(Try(List(U8), ReadErr))
	data = Stream.from_iter([Ok([1, 2, 3]), Ok([4, 5, 6, 7])].iter())
	var $blob = []
	for! piece in Cbor.StreamWriter.bytes_stream(data, Length(7)) {
		$blob = $blob.concat(piece?)
	}
	echo!("bytes_stream: ${hex($blob)}\n")
	var $got = 0
	for! chunk in Cbor.ByteChunks.new({}).from_stream(body($blob, 2, Bool.False)) {
		$got = $got + chunk?.len()
	}
	echo!("  ByteChunks read ${$got.to_str()} bytes\n")

	# A text in chunks: a chunk of the input can cut a code point; each Str chunk ends at a code point boundary.
	words : Stream(Try(Str, ReadErr))
	words = Stream.from_iter([Ok("stream "), Ok("€")].iter())
	var $text = []
	for! piece in Cbor.StreamWriter.text_stream(words, Indefinite) {
		$text = $text.concat(piece?)
	}
	echo!("text_stream: ${hex($text)}\n")
	var $parts = []
	for! part in Cbor.TextChunks.new({ allow: [IndefiniteLength] }).from_stream(body($text, 4, Bool.False)) {
		$parts = $parts.append(part?)
	}
	echo!("  TextChunks: ${Str.inspect($parts)}\n")

	# An RFC 8742 sequence: one item after the other, with no head.
	nums : Stream(Try(U64, ReadErr))
	nums = Stream.from_iter([Ok(1), Ok(500)].iter())
	var $seq = []
	for! piece in Cbor.StreamWriter.sequence_stream(nums, {}) {
		$seq = $seq.concat(piece?)
	}
	echo!("sequence_stream: ${hex($seq)}\n")
	Ok({})
}
