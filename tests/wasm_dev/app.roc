app [main!] {
	cbor: "../../src/main.roc",
	pf: platform "platform/main.roc",
}

## The app of scripts/wasm_dev.sh: the shapes that trapped (stack overflow) with `--target=wasm32 --opt=dev`.
## The seed is shape * 256 + n. The value comes from n, so the compiler cannot fold the encode.
## The result is a checksum of the output bytes.
import cbor.Cbor

Curve : [P256, P384, P521]

Material : [
	Rsa({ n : List(U8), e : List(U8) }),
	Ec({ crv : Curve, x : List(U8), y : List(U8) }),
	Okp({ crv : [Ed25519, Ed448], x : List(U8) }),
]

Row : { id : U64, name : Str }

## The rows of an array in `chunks`, read with Cbor.Items and `push`: a stream decoder with a walk that stops and
## goes on.
read_rows : List(List(U8)) -> List(Row)
read_rows = |chunks| {
	var $items = Cbor.Items.array({})
	var $rows = []
	for chunk in chunks {
		r : { values : List(Row), rest : Try(Cbor.Items, _) }
		r = $items.push(chunk)
		$rows = $rows.concat(r.values)
		$items =
			match r.rest {
				Ok(next) => next
				Err(_) => Cbor.Items.sequence({})
			}
	}
	$rows
}

## Six levels: four records and two lists.
Deep : { a : { b : { c : { d : List(List(U8)) } } } }

## Cbor.StreamWriter: an indefinite array with a record item, a definite byte string in two chunks and a map entry,
## then the 9-byte head of a byte string of 5,000,000,000 + n bytes.
stream : U64, U8, Str -> Try(List(U8), _)
stream = |n, b, text| {
	var $w = Cbor.StreamWriter.new({ key_order: Sorted })
	var $out = []
	a = $w.open_array(Indefinite)?
	$out = $out.concat(a.bytes)
	i = a.writer.item({ kid: text, m: A([b]) })?
	$out = $out.concat(i.bytes)
	o = i.writer.open_bytes(Length(2))?
	$out = $out.concat(o.bytes)
	c1 = o.writer.bytes_chunk([b])?
	$out = $out.concat(c1.bytes)
	c2 = c1.writer.bytes_chunk([2])?
	$out = $out.concat(c2.bytes)
	e = c2.writer.close()?
	m = e.writer.open_map(Count(1))?
	$out = $out.concat(m.bytes)
	en = m.writer.entry(text, [n])?
	$out = $out.concat(en.bytes)
	me = en.writer.close()?
	ae = me.writer.close()?
	$out = $out.concat(ae.bytes)
	ae.writer.finish()?
	$w = Cbor.StreamWriter.new({})
	big = $w.open_bytes(Length(5_000_000_000 + n))?
	Ok($out.concat(big.bytes))
}

## A text read with Cbor.TextChunks in chunks of 2 bytes (each cut of the euro sign waits for its next byte), then an
## indefinite byte string read with Cbor.ByteChunks in chunks of 3 bytes. The bytes of each part of the output, joined.
read_chunks : List(U8), List(U8) -> List(U8)
read_chunks = |text_input, bytes_input| {
	var $t = Cbor.TextChunks.new({ ignore_tags: [6] })
	var $out = []
	for chunk in text_input.chunks_of(2) {
		r = $t.push(chunk)
		for piece in r.values {
			$out = $out.concat(piece.to_utf8()).append(0x7c)
		}
		$t =
			match r.rest {
				Ok(next) => next
				Err(_) => Cbor.TextChunks.new({})
			}
	}
	var $b = Cbor.ByteChunks.new({ allow: [IndefiniteLength] })
	for chunk in bytes_input.chunks_of(3) {
		r = $b.push(chunk)
		for piece in r.values {
			$out = $out.concat(piece).append(0x7c)
		}
		$b =
			match r.rest {
				Ok(next) => next
				Err(_) => Cbor.ByteChunks.new({})
			}
	}
	$out
}

## The adapters: the rows of shape 8 read with Cbor.Items.from_stream and `for!` from a `Stream` of chunks of 3 bytes,
## then Cbor.StreamWriter.bytes_stream with the 9-byte head of 5,000,000,000 + n bytes, one chunk, and a source error.
## The bytes of each row and of each piece, joined.
adapter! : List(U8), U64, U8 => List(U8)
adapter! = |input, n, b| {
	chunks : Stream(Try(List(U8), [Cut]))
	chunks = Stream.from_iter(input.chunks_of(3).map(|c| Ok(c)).iter())
	rows : Stream(Try(Row, _))
	rows = Cbor.Items.array({}).from_stream(chunks)
	var $out = []
	for! r in rows {
		match r {
			Ok(row) => {
				$out = $out.concat(row.name.to_utf8()).append(row.id.to_u8_wrap()).append(row.id.shr_zf_wrap(8).to_u8_wrap())
			}
			Err(_) => {
				$out = $out.append(0xee)
			}
		}
	}
	data : Stream(Try(List(U8), [Cut]))
	data = Stream.from_iter([Ok([b, 2]), Err(Cut)].iter())
	for! piece in Cbor.StreamWriter.bytes_stream(data, Length(5_000_000_000 + n)) {
		match piece {
			Ok(bytes) => {
				$out = $out.concat(bytes).append(0x7c)
			}
			Err(Input(Cut)) => {
				$out = $out.append(0xcc)
			}
			Err(CountMismatch) => {
				$out = $out.append(0xdd)
			}
		}
	}
	$out
}

main! : U64 => U64
main! = |seed| {
	n = seed % 256
	b = n.to_u8_wrap()
	text = "k${n.to_str()}"
	bytes =
		match seed // 256 {
			0 => {
				v : { r : { x : List(U8) } }
				v = { r: { x: [b] } }
				Cbor.encode(v)
			}
			1 => {
				v : { r : { x : List(U64) } }
				v = { r: { x: [n] } }
				Cbor.encode(v)
			}
			2 => {
				v : { kid : Str, r : { x : List(U8) } }
				v = { kid: text, r: { x: [b] } }
				Cbor.encode(v)
			}
			3 => {
				v : { kid : Str, m : [A(List(U8))] }
				v = { kid: text, m: A([b]) }
				Cbor.encode(v)
			}
			4 => {
				v : (Str, Material)
				v = (text, Ec({ crv: P256, x: [b], y: [2] }))
				Cbor.encode(v)
			}
			5 => {
				v : List(Material)
				v = [Rsa({ n: [b], e: [1, 0, 1] }), Okp({ crv: Ed25519, x: [b] })]
				Cbor.encode(v)
			}
			6 => {
				v : Deep
				v = { a: { b: { c: { d: [[b]] } } } }
				Cbor.encode(v)
			}
			7 => stream(n, b, text) ?? [0]
			8 => {
				# [{ "id": 24 + n % 200, "name": "a" }, { "id": 300, "name": "bc" }] by hand: an encode here adds item encoders to the
				# app, and the frame of each nesting level grows with them (roc-lang/roc#12922).
				row1 = [0xa2, 0x62, 0x69, 0x64, 0x18, (24 + n % 200).to_u8_wrap(), 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61]
				row2 = [0xa2, 0x62, 0x69, 0x64, 0x19, 0x01, 0x2c, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x62, 0x62, 0x63]
				input = [0x82].concat(row1).concat(row2)
				read_rows(input.chunks_of(3)).fold([], |acc, r| acc.concat(r.name.to_utf8()).append(r.id.to_u8_wrap()).append(r.id.shr_zf_wrap(8).to_u8_wrap()))
			}
			10 => {
				# By hand, as shape 8: 6(text "k€" + a digit + "€"), and (_ h'nn02', h'03').
				digit = 0x30 + (n % 10).to_u8_wrap()
				text_input = [0xc6, 0x68, 0x6b, 0xe2, 0x82, 0xac, digit, 0xe2, 0x82, 0xac]
				bytes_input = [0x5f, 0x42, b, 0x02, 0x40, 0x41, 0x03, 0xff]
				read_chunks(text_input, bytes_input)
			}
			11 => {
				# The rows of shape 8, by hand, through the Stream adapter.
				row1 = [0xa2, 0x62, 0x69, 0x64, 0x18, (24 + n % 200).to_u8_wrap(), 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x61, 0x61]
				row2 = [0xa2, 0x62, 0x69, 0x64, 0x19, 0x01, 0x2c, 0x64, 0x6e, 0x61, 0x6d, 0x65, 0x62, 0x62, 0x63]
				adapter!([0x82].concat(row1).concat(row2), n, b)
			}
			_ => []
		}
	bytes.fold(bytes.len(), |acc, x| acc.times_wrap(31).plus_wrap(x.to_u64()))
}
