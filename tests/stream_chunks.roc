app [] { pkg: "../src/main.roc" }

# The stream decoders Cbor.ByteChunks and Cbor.TextChunks (0.5.0), through the public API of the package. Each one
# reads one top-level byte string or text from bytes that come in chunks, and gives its data as chunks.
# The property of most tests: for each split of the input into chunks (chunks of 1 byte, each split in 2 parts and
# each split in 3 parts, empty chunks between bytes), the chunks joined are the value of `parse_with` as a `List(U8)`
# or a `Str`, or the stream gives the same error at the same position. Error positions are in the whole stream.

import pkg.Cbor

# Helpers

hex_digit : U8 -> U8
hex_digit = |c| if (c >= 97) c - 87 else c - 48

hex : Str -> List(U8)
hex = |s|
	s.to_utf8().chunks_of(2).map(
		|pair|
			match pair {
				[hi, lo] => hex_digit(hi) * 16 + hex_digit(lo)
				_ => crash "odd hex"
			},
	)

## The errors of each read in this file: a closed union, so that results compare with `==`.
Errs : Cbor.Error

## An empty chunk of output: never given. A test that sees one gives this error.
empty_piece : Errs
empty_piece = InvalidCbor(999_999)

## The most parts of one drive: each test input gives far fewer. The loop of a drive is bounded by its chunks, and a
## decoder that gives more parts than this fails the test.
step_limit : U64
step_limit = 100_000

## The parts that `start` gives when it gets `chunks` one at a time with `push`, then `finish`. `end` is `Ok` after
## `finish`, else the error.
drive_bytes : Cbor.ByteChunks, List(List(U8)) -> { pieces : List(List(U8)), end : Try({}, Errs) }
drive_bytes = |start, chunks| {
	var $d = start
	var $pieces = []
	var $end = Ok({})
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r = $d.push(chunk)
			$pieces = $pieces.concat(r.values)
			match r.rest {
				Ok(next) => {
					$d = next
				}
				Err(e) => {
					$d = Cbor.ByteChunks.new({})
					$end = Err(e)
					$going = Bool.False
				}
			}
			if $pieces.len() > step_limit {
				$end = Err(InvalidCbor(888_888))
				$going = Bool.False
			}
		}
	}
	if $going {
		$end = $d.finish()
	}
	{ pieces: $pieces, end: $end }
}

drive_text : Cbor.TextChunks, List(List(U8)) -> { pieces : List(Str), end : Try({}, Errs) }
drive_text = |start, chunks| {
	var $d = start
	var $pieces = []
	var $end = Ok({})
	var $going = Bool.True
	for chunk in chunks {
		if $going {
			r = $d.push(chunk)
			$pieces = $pieces.concat(r.values)
			match r.rest {
				Ok(next) => {
					$d = next
				}
				Err(e) => {
					$d = Cbor.TextChunks.new({})
					$end = Err(e)
					$going = Bool.False
				}
			}
			if $pieces.len() > step_limit {
				$end = Err(InvalidCbor(888_888))
				$going = Bool.False
			}
		}
	}
	if $going {
		$end = $d.finish()
	}
	{ pieces: $pieces, end: $end }
}

## The chunks joined, or the error. An empty chunk is the error `empty_piece`.
bytes_of : Cbor.ByteChunks, List(List(U8)) -> Try(List(U8), Errs)
bytes_of = |start, chunks| {
	r = drive_bytes(start, chunks)
	if r.pieces.any(|p| p.is_empty()) {
		Err(empty_piece)
	} else {
		r.end.map_ok(|_| r.pieces.join())
	}
}

text_of : Cbor.TextChunks, List(List(U8)) -> Try(Str, Errs)
text_of = |start, chunks| {
	r = drive_text(start, chunks)
	if r.pieces.any(|p| p.is_empty()) {
		Err(empty_piece)
	} else {
		r.end.map_ok(|_| r.pieces.fold("", |acc, p| acc.concat(p)))
	}
}

## The splits of `bytes`: one chunk, chunks of 1 byte, 1 byte chunks with an empty chunk after each, each split in
## 2 parts and each split in 3 parts.
splits : List(U8) -> List(List(List(U8)))
splits = |bytes| {
	n = bytes.len()
	var $out = [[bytes], bytes.chunks_of(1)]
	var $spaced = []
	for b in bytes {
		$spaced = $spaced.append([b]).append([])
	}
	$out = $out.append($spaced)
	for i in 0..=n {
		$out = $out.append([bytes.take_first(i), bytes.drop_first(i)])
		for j in i..=n {
			$out = $out.append([bytes.take_first(i), bytes.sublist({ start: i, len: j - i }), bytes.drop_first(j)])
		}
	}
	$out
}

## `ByteChunks` agrees with `parse_with` as a `List(U8)` for each split of `bytes`.
bytes_agree : List(U8), Cbor.Options -> Bool
bytes_agree = |bytes, options| {
	want : Try(List(U8), Errs)
	want = Cbor.parse_with(bytes, options)
	splits(bytes).all(|chunks| bytes_of(Cbor.ByteChunks.new(options), chunks) == want)
}

## `TextChunks` agrees with `parse_with` as a `Str` for each split of `bytes`.
text_agrees : List(U8), Cbor.Options -> Bool
text_agrees = |bytes, options| {
	want : Try(Str, Errs)
	want = Cbor.parse_with(bytes, options)
	splits(bytes).all(|chunks| text_of(Cbor.TextChunks.new(options), chunks) == want)
}

## The same for `bytes` and for each prefix of it (a cut input).
bytes_prefixes_agree : List(U8), Cbor.Options -> Bool
bytes_prefixes_agree = |bytes, options| {
	var $all = Bool.True
	for n in 0..=bytes.len() {
		if !bytes_agree(bytes.take_first(n), options) {
			$all = Bool.False
		}
	}
	$all
}

text_prefixes_agree : List(U8), Cbor.Options -> Bool
text_prefixes_agree = |bytes, options| {
	var $all = Bool.True
	for n in 0..=bytes.len() {
		if !text_agrees(bytes.take_first(n), options) {
			$all = Bool.False
		}
	}
	$all
}

## Each split of `bytes` gives `want`, from `ByteChunks` and as the error of `parse_with`.
bytes_give : List(U8), Cbor.Options, Try(List(U8), Errs) -> Bool
bytes_give = |bytes, options, want| bytes_agree(bytes, options) and bytes_of(Cbor.ByteChunks.new(options), [bytes]) == want

text_gives : List(U8), Cbor.Options, Try(Str, Errs) -> Bool
text_gives = |bytes, options, want| text_agrees(bytes, options) and text_of(Cbor.TextChunks.new(options), [bytes]) == want

indefinite : Cbor.Options
indefinite = { allow: [IndefiniteLength] }

# Splits against parse_with

## Byte strings with heads of 1 and 2 bytes, each cut.
expect bytes_prefixes_agree(hex("4401020304"), {}) and bytes_prefixes_agree([0x58, 0x18].concat(List.repeat(7, 24)), {})

## Heads of 3, 5 and 9 bytes (padded: with PaddedNumbers), and their errors without it.
expect {
	data = hex("0102")
	three = [0x59, 0x00, 0x02].concat(data)
	five = [0x5a, 0x00, 0x00, 0x00, 0x02].concat(data)
	nine = [0x5b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02].concat(data)
	padded : Cbor.Options
	padded = { allow: [PaddedNumbers] }
	bytes_prefixes_agree(nine, padded) and bytes_give(three, padded, Ok(data)) and bytes_give(five, padded, Ok(data)) and bytes_give(nine, {}, Err(InvalidCbor(0)))
}

## A text of 256 bytes (a 3-byte head) in the splits of 2 parts.
expect {
	body = List.repeat(0x61, 256)
	bytes = [0x79, 0x01, 0x00].concat(body)
	want = Str.from_utf8(body) ?? ""
	var $all = Bool.True
	for i in 0..=bytes.len() {
		if text_of(Cbor.TextChunks.new({}), [bytes.take_first(i), bytes.drop_first(i)]) != Ok(want) {
			$all = Bool.False
		}
	}
	$all
}

## Text with code points of 1, 2, 3 and 4 bytes, cut at each byte by each split, and each cut of the input.
expect text_prefixes_agree(hex("6a61c3a9e282acf09f9880"), {})

## Each chunk of the output ends at a code point boundary: with chunks of 1 byte, one chunk for each code point.
expect {
	r = drive_text(Cbor.TextChunks.new({}), hex("6a61c3a9e282acf09f9880").chunks_of(1))
	r.pieces == ["a", "\u(e9)", "\u(20ac)", "\u(1f600)"] and r.end == Ok({})
}

## A 3-byte code point cut after its first and its second byte: the bytes wait, the next chunk starts with it.
expect {
	a = drive_text(Cbor.TextChunks.new({}), [hex("6561e2"), hex("82ac62")])
	b = drive_text(Cbor.TextChunks.new({}), [hex("6561e282"), hex("ac62")])
	c = drive_text(Cbor.TextChunks.new({}), [hex("6561e282"), hex("ac"), hex("62")])
	a.pieces == ["a", "\u(20ac)b"] and b.pieces == ["a", "\u(20ac)b"] and c.pieces == ["a", "\u(20ac)", "b"] and a.end == Ok({})
}

## The output is the data of each chunk of push, with no copy: a byte string in one chunk gives one part.
expect {
	r = drive_bytes(Cbor.ByteChunks.new({}), [hex("4401"), hex("02"), hex("0304")])
	r.pieces == [[0x01], [0x02], [0x03, 0x04]] and r.end == Ok({})
}

# Invalid UTF-8

## A bad continuation byte, an overlong form of 2 and 3 bytes, a surrogate, a lead byte with no continuation at the end
## of the text, and a continuation byte with no lead: the error at the text head, for each split.
expect
	text_gives(hex("62c328"), {}, Err(InvalidCbor(0)))
		and text_gives(hex("62c080"), {}, Err(InvalidCbor(0)))
		and text_gives(hex("63e08080"), {}, Err(InvalidCbor(0)))
		and text_gives(hex("63eda080"), {}, Err(InvalidCbor(0)))
		and text_gives(hex("636162e2"), {}, Err(InvalidCbor(0)))
		and text_gives(hex("63616280"), {}, Err(InvalidCbor(0)))
		and text_gives(hex("61f8"), {}, Err(InvalidCbor(0)))

## A code point cut by the end of the input: the error of a cut text, at its head. Each cut of a text with a bad byte.
expect text_gives(hex("646162e282"), {}, Err(InvalidCbor(0))) and text_prefixes_agree(hex("6661626364c32865"), {})

## A text that ends with a cut code point is an error when its last byte comes, with no wait for more input.
expect {
	r = Cbor.TextChunks.new({}).push(hex("6261e2"))
	r.values == [] and r.rest.map_ok(|_| {}) == Err(InvalidCbor(0))
}

## The chunks before the bad bytes come out, then the error at the head, in the whole stream (after tags).
expect {
	r = drive_text(Cbor.TextChunks.new({ ignore_tags: [6] }), [hex("c666616263"), hex("ff6465")])
	r.pieces == ["abc"] and r.end == Err(InvalidCbor(1)) and text_agrees(hex("c666616263ff6465"), { ignore_tags: [6] })
}

# Indefinite length

## Chunks of a byte string and of a text with their heads cut, an empty chunk, and each cut of the input.
expect bytes_prefixes_agree(hex("5f4201024043030405ff"), indefinite) and text_prefixes_agree(hex("7f62c3a96063e282acff"), indefinite)

## The CBOR chunk heads are not given; an empty CBOR chunk gives no output; an empty indefinite string gives none.
expect {
	r = drive_bytes(Cbor.ByteChunks.new(indefinite), [hex("5f4201024043030405ff")])
	e = drive_text(Cbor.TextChunks.new(indefinite), [hex("7f6060ff")])
	r.pieces == [[1, 2], [3, 4, 5]] and e.pieces == [] and e.end == Ok({})
}

## Without IndefiniteLength: an error at the head.
expect bytes_give(hex("5f4101ff"), {}, Err(InvalidCbor(0))) and text_gives(hex("7f6161ff"), {}, Err(InvalidCbor(0)))

## A chunk of another type, a nested indefinite chunk, a tag or an integer as a chunk: an error at the string head.
## A chunk head that is not well formed (reserved, padded): an error at the chunk head.
expect
	bytes_give(hex("5f4101616161ff"), indefinite, Err(InvalidCbor(0)))
		and text_gives(hex("7f41616161ff"), indefinite, Err(InvalidCbor(0)))
		and bytes_give(hex("5f5f4101ffff"), indefinite, Err(InvalidCbor(0)))
		and bytes_give(hex("5fc64101ff"), indefinite, Err(InvalidCbor(0)))
		and bytes_give(hex("5f5cff"), indefinite, Err(InvalidCbor(1)))
		and bytes_give(hex("5f41015c00ff"), indefinite, Err(InvalidCbor(3)))
		and bytes_give(hex("5f58010aff"), indefinite, Err(InvalidCbor(1)))
		and bytes_give(hex("5f58010aff"), { allow: [IndefiniteLength, PaddedNumbers] }, Ok([0x0a]))

## A nested indefinite chunk gives no data before the error: its bytes are not read as data.
expect {
	r = drive_bytes(Cbor.ByteChunks.new(indefinite), [hex("5f5f4101ffff")])
	r.pieces == [] and r.end == Err(InvalidCbor(0))
}

## Each CBOR chunk of a text is valid UTF-8 by itself: a code point across two CBOR chunks is an error at the head.
expect text_gives(hex("7f6261e26282acff"), indefinite, Err(InvalidCbor(0))) and text_gives(hex("7f616162c328ff"), indefinite, Err(InvalidCbor(0)))

## A break with no open string, and a break in a definite string's place: an error at it.
expect bytes_give(hex("ff"), indefinite, Err(InvalidCbor(0))) and bytes_give(hex("ff"), {}, Err(InvalidCbor(0)))

# Root of another type, tags, bytes after the root

## An integer, a text, an array at the root of ByteChunks; a byte string at the root of TextChunks: an error at the head.
## A `List(U8)` of `parse_with` also reads an empty array (`80`): ByteChunks reads only a byte string.
expect {
	empty_array = bytes_of(Cbor.ByteChunks.new({}), [[0x80]])
	bytes_give([0x01], {}, Err(InvalidCbor(0))) and bytes_give(hex("6161"), {}, Err(InvalidCbor(0))) and bytes_give(hex("820101"), {}, Err(InvalidCbor(0))) and text_gives(hex("4161"), {}, Err(InvalidCbor(0))) and empty_array == Err(InvalidCbor(0))
}

## ignore_tags: the tags before the root are skipped, in each cut. A tag not in the list is an error at the tag.
expect bytes_prefixes_agree(hex("c6d865420102"), { ignore_tags: [6, 101] }) and text_prefixes_agree(hex("c66161"), { ignore_tags: [6] })

## An unlisted tag 7 after the skipped tag 6 (c6 c7 41 01) is an error at byte 1; tag 6 with no ignore_tags is an error at byte 0.
expect bytes_give(hex("c6c74101"), { ignore_tags: [6] }, Err(InvalidCbor(1))) and bytes_give(hex("c64101"), {}, Err(InvalidCbor(0)))

## Bytes after the root: an error at the first extra byte, also when they come in a later chunk.
expect bytes_give(hex("410000"), {}, Err(InvalidCbor(2))) and bytes_give(hex("5fff00"), indefinite, Err(InvalidCbor(2))) and text_gives(hex("616161"), {}, Err(InvalidCbor(2)))

## The chunks 41 01, then an empty chunk, then 02: the part [1] comes, then an error at byte 2.
expect {
	r = drive_bytes(Cbor.ByteChunks.new({}), [hex("4101"), [], hex("02")])
	r.pieces == [[1]] and r.end == Err(InvalidCbor(2))
}

## The parts before an error come back in `values`, with the error in `rest`: the extra byte in the same chunk.
expect {
	r = Cbor.ByteChunks.new({}).push([0x41, 0x07, 0x00])
	t = Cbor.TextChunks.new({}).push([0x61, 0x61, 0x61])
	r.values == [[0x07]] and r.rest.map_ok(|_| {}) == Err(InvalidCbor(2)) and t.values == ["a"] and t.rest.map_ok(|_| {}) == Err(InvalidCbor(2))
}

# Empty strings, empty input, no finish, positions

## An empty byte string and an empty text: no part, then the end. An empty input: the error of parse_with, at 0.
expect {
	a = drive_bytes(Cbor.ByteChunks.new({}), [[0x40]])
	b = drive_text(Cbor.TextChunks.new({}), [[0x60]])
	a.pieces == [] and a.end == Ok({}) and b.pieces == [] and b.end == Ok({}) and bytes_give([], {}, Err(InvalidCbor(0))) and text_gives([], {}, Err(InvalidCbor(0))) and bytes_agree([0x40], {}) and text_agrees([0x60], {})
}

## The end of the input is only `finish`: a whole string is Ok, a cut one the error at its head (a cut code point too).
expect {
	a = Cbor.ByteChunks.new({}).push([0x42, 0x01])
	b = Cbor.TextChunks.new({}).push([0x61, 0x61])
	c = Cbor.TextChunks.new({}).push([0x63, 0x61, 0xe2])
	match (a.rest, b.rest, c.rest) {
		(Ok(x), Ok(y), Ok(z)) => a.values == [[0x01]] and x.finish() == Err(InvalidCbor(0)) and y.finish() == Ok({}) and b.values == ["a"] and c.values == ["a"] and z.finish() == Err(InvalidCbor(0))
		_ => Bool.False
	}
}

## position: after each head and part that `push` read; the bytes of a cut code point come after it. An empty chunk
## changes nothing.
expect {
	r1 = Cbor.TextChunks.new({ ignore_tags: [6] }).push(hex("c6666162e2"))
	match r1.rest {
		Ok(wait) => {
			r2 = wait.push([])
			match r2.rest {
				Ok(same) => {
					r3 = same.push(hex("82ac63"))
					match r3.rest {
						Ok(last) => r1.values == ["ab"] and r2.values == [] and wait.position() == 4 and same.position() == 4 and r3.values == ["\u(20ac)c"] and last.position() == 8
						Err(_) => Bool.False
					}
				}
				Err(_) => Bool.False
			}
		}
		Err(_) => Bool.False
	}
}

## An indefinite byte string of N chunks of 1 byte in one chunk of input: N parts from one push.
expect {
	n = 3000
	var $bytes = [0x5f]
	for _ in (0.U64).until(n) {
		$bytes = $bytes.append(0x41).append(0x09)
	}
	r = Cbor.ByteChunks.new({ allow: [IndefiniteLength] }).push($bytes.append(0xff))
	match r.rest {
		Ok(d) => r.values.len() == n and r.values.all(|p| p == [0x09]) and d.position() == 2 * n + 2 and d.finish() == Ok({})
		Err(_) => Bool.False
	}
}

## A 9-byte head of 5,000,000,000 bytes: the chunks come out as the input comes; no allocation of the length.
expect {
	head = hex("5b000000012a05f200")
	r = drive_bytes(Cbor.ByteChunks.new({}), [head.concat([1, 2]), [3]])
	r.pieces == [[1, 2], [3]] and r.end == Err(InvalidCbor(0))
}

# max_depth and max_items

## Each tag before the string is one level, and the string none: the error at the head that goes over, as in parse_with.
expect {
	bytes = hex("c6c64100")
	bytes_give(bytes, { ignore_tags: [6], max_depth: 1 }, Err(InvalidCbor(1))) and bytes_give(bytes, { ignore_tags: [6], max_depth: 2 }, Ok([0])) and bytes_give(hex("4100"), { max_depth: 0 }, Ok([0]))
}

## Each tag and the string count for max_items; the chunks of an indefinite string do not.
expect {
	bytes_give(hex("c6c64100"), { ignore_tags: [6], max_items: 2 }, Err(InvalidCbor(2))) and bytes_give(hex("c6c64100"), { ignore_tags: [6], max_items: 3 }, Ok([0])) and bytes_give(hex("5f41014102ff"), { allow: [IndefiniteLength], max_items: 1 }, Ok([1, 2])) and bytes_give(hex("c64100"), { ignore_tags: [6], max_items: 1 }, Err(InvalidCbor(1)))
}

# A large string

## 3 MB of text with 3-byte code points in chunks of 64 KiB (each cuts a code point): the text comes back.
expect {
	n = 1_000_000
	body = List.repeat(0, n).fold([], |acc, _| acc.concat([0xe2, 0x82, 0xac]))
	bytes = [0x7a, 0x00, 0x2d, 0xc6, 0xc0].concat(body)
	r = drive_text(Cbor.TextChunks.new({}), bytes.chunks_of(65536))
	total = r.pieces.fold(0, |acc, p| acc + p.count_utf8_bytes())
	r.end == Ok({}) and total == 3 * n and r.pieces.len() == 46
}
