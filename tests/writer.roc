app [] { pkg: "../src/main.roc" }

# The writer (0.5.0), through the public API of the package: item counts, shortest heads,
# null in a record, List(U8) as a byte string, encode_tagged, and the option fields of encode_with.
# The IDs W1 to W15 are the findings of the audit of 0.4.1.

import pkg.Cbor

## An encoder_for of an app that writes what the test asks for, also a wrong count of items.
Probe := [
	Nothing,
	TwoRoot,
	List(U64, U64),
	Slot(U64),
	Tag(U64, U64),
	Record(U64, U64),
	Mixed,
	Tagged(U64, Probe),
].{
	encoder_for : Cbor -> (Probe, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |probe, w|
		match probe {
			Nothing => Ok(w)
			TwoRoot => Cbor.encode_u64(2, Cbor.encode_u64(1, w)?)
			List(declared, written) => Cbor.encode_list(w, declared, |c, add| items(c, add, written))
			Slot(n) => Cbor.encode_list(w, 1, |c, add| add(c, |v| sevens(v, n)))
			Tag(declared, written) => Cbor.encode_tag(w, "T", declared, |c, add| items(c, add, written))
			Record(declared, written) =>
				Cbor.encode_record(
					w,
					declared,
					|c, add| {
						var $c = c
						for i in (0.U64).until(written) {
							$c = add($c, "k${i.to_str()}", |v| Cbor.encode_u64(7, v))?
						}
						Ok($c)
					},
				)
			Mixed => Cbor.encode_list(w, 2, |c, add| add(add(c, |v| Cbor.encode_u8(1, v))?, |v| Cbor.encode_str("a", v)))
			Tagged(number, inner) => Cbor.encode_tagged(number, inner, w)
		}
}

## A user id under the tag 6, written by hand.
User := U64.{
	encoder_for : Cbor -> (User, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |User.(id), w| Cbor.encode_tagged(6, { user_id: id }, w)
}

## `n` items, each one 7.
sevens : Cbor.Writer, U64 -> Try(Cbor.Writer, err)
sevens = |w, n| {
	var $w = w
	for _ in (0.U64).until(n) {
		$w = Cbor.encode_u64(7, $w)?
	}
	Ok($w)
}

## `n` calls of `add`, each with one item.
items : c, (c, (Cbor.Writer -> Try(Cbor.Writer, err)) -> Try(c, err)), U64 -> Try(c, err)
items = |c, add, n| {
	var $c = c
	for _ in (0.U64).until(n) {
		$c = add($c, |v| Cbor.encode_u64(7, v))?
	}
	Ok($c)
}

# Count mismatch: 0 items, 2 items, a wrong declared count, nested in a record (W2 to W5)

## The root gets exactly one item.
expect Cbor.encode_try(Probe.Nothing) == Err(CountMismatch)

## Two items at the root (1, then 2) is an error CountMismatch.
expect Cbor.encode_try(Probe.TwoRoot) == Err(CountMismatch)

## W3: one value slot writes 0 or 2 items.
expect Cbor.encode_try(Probe.Slot(0)) == Err(CountMismatch)

## A value slot that writes 2 items is an error CountMismatch.
expect Cbor.encode_try(Probe.Slot(2)) == Err(CountMismatch)

## A value slot that writes 1 item is fine: [7] writes 81 07.
expect Cbor.encode_try(Probe.Slot(1)) == Ok([0x81, 0x07])

## W2: the declared count of a list differs from the items written.
expect Cbor.encode_try(Probe.List(3, 1)) == Err(CountMismatch)

## A list declared with 1 item that writes 2 is an error CountMismatch.
expect Cbor.encode_try(Probe.List(1, 2)) == Err(CountMismatch)

## A list declared with 2 items that writes 2 writes 82 07 07.
expect Cbor.encode_try(Probe.List(2, 2)) == Ok([0x82, 0x07, 0x07])

## W1: 32 items with a declared count of 0. 0.4.1 wrote `a0 01 ..` (an empty map and stray bytes).
expect Cbor.encode_try(Probe.List(0, 32)) == Err(CountMismatch)

## W4: the payloads of a tag.
expect Cbor.encode_try(Probe.Tag(2, 1)) == Err(CountMismatch)

## A tag declared with 1 payload that writes 2 is an error CountMismatch.
expect Cbor.encode_try(Probe.Tag(1, 2)) == Err(CountMismatch)

## A tag declared with 2 payloads that writes 2 writes {"T": [7, 7]} (a1 61 54 82 07 07).
expect Cbor.encode_try(Probe.Tag(2, 2)) == Ok([0xa1, 0x61, 0x54, 0x82, 0x07, 0x07])

## A record gets fewer fields than declared (an absent optional field), but not more.
expect Cbor.encode_try(Probe.Record(1, 2)) == Err(CountMismatch)

## A record declared with 2 fields that writes 1 writes {"k0": 7} with a head for 1 (a1 62 6b 30 07).
expect Cbor.encode_try(Probe.Record(2, 1)) == Ok([0xa1, 0x62, 0x6b, 0x30, 0x07])

## W5: a field value that writes nothing, nested in a derived record and list.
expect Cbor.encode_try({ a: 1.U64, b: Probe.Slot(0) }) == Err(CountMismatch)

## A record with a list that holds a value that writes nothing is an error CountMismatch.
expect Cbor.encode_try({ a: [Probe.Nothing] }) == Err(CountMismatch)

## A field value that writes 1 item is fine: { a: 1, b: [7] } writes a2 61 61 01 61 62 81 07.
expect Cbor.encode_try({ a: 1.U64, b: Probe.Slot(1) }) == Ok([0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x81, 0x07])

# A writer or a container of another level, captured by a closure, is not accepted

## A slot gives back the writer of the level above.
Sneak := U64.{
	encoder_for : Cbor -> (Sneak, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Sneak.(n), w| Cbor.encode_list(w, 1, |c, add| add(c, |_inner| Cbor.encode_u64(n, w)))
}

## The first of three slots gives back the writer of the level above (0.5.0 review: the list head was lost).
Sneak3 := U64.{
	encoder_for : Cbor -> (Sneak3, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Sneak3.(n), w|
		Cbor.encode_list(
			w,
			3,
			|c, add| {
				c1 = add(c, |_inner| Cbor.encode_u64(n, w))?
				c2 = add(c1, |x| Cbor.encode_u64(6, x))?
				add(c2, |x| Cbor.encode_u64(7, x))
			},
		)
}

## An inner list gives back the container of the outer list, with the counts right: the inner list head was lost.
Climb := U64.{
	encoder_for : Cbor -> (Climb, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Climb.(n), w|
		Cbor.encode_list(
			w,
			2,
			|c, add| {
				c1 = add(c, |x| Cbor.encode_u64(n, x))?
				add(c1, |v| Cbor.encode_list(v, 1, |_inner, _add| add(c1, |x| Cbor.encode_u64(9, x))))
			},
		)
}

## A value that holds a writer and gives it back in place of its own.
Hold := Cbor.Writer.{
	encoder_for : Cbor -> (Hold, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |Hold.(held), _own| Ok(Cbor.encode_u64(5, held)?)
}

## The tagged item gives back the writer of the level above (the place of the tag).
SneakTag := U64.{
	encoder_for : Cbor -> (SneakTag, Cbor.Writer -> Try(Cbor.Writer, err))
	encoder_for = |_| |SneakTag.(_), w| Cbor.encode_list(w, 1, |c, add| add(c, |v| Cbor.encode_tagged(6, Hold.(v), v)))
}

## A slot that writes with the writer of the level above (Sneak) is an error CountMismatch.
expect Cbor.encode_try(Sneak.(5)) == Err(CountMismatch)

## Sneak3 in a record field (its first slot writes with the writer of the level above) is an error CountMismatch.
expect Cbor.encode_try({ a: Sneak3.(5), b: 1.U64 }) == Err(CountMismatch)

## An inner list that adds to the outer list (Climb) is an error CountMismatch.
expect Cbor.encode_try(Climb.(5)) == Err(CountMismatch)

## A tagged item that writes with the writer of the level above (SneakTag) is an error CountMismatch.
expect Cbor.encode_try(SneakTag.(5)) == Err(CountMismatch)

# W6: encode_tagged writes the tag and its one item

## encode_tagged with the tag 6 and a list of one 7 writes c6 81 07.
expect Cbor.encode_try(Probe.Tagged(6, Probe.Slot(1))) == Ok([0xc6, 0x81, 0x07])

## encode_tagged of a value that writes nothing, in a list, is an error CountMismatch.
expect Cbor.encode_try([Probe.Tagged(6, Probe.Nothing)]) == Err(CountMismatch)

## encode_tagged of a value that writes 2 items is an error CountMismatch.
expect Cbor.encode_try(Probe.Tagged(6, Probe.TwoRoot)) == Err(CountMismatch)

# Shortest heads (W1, W7, W15)

## 24 items: a 1-byte argument (0.4.1 wrote `99 00 18`).
expect {
	xs : List(U64)
	xs = List.repeat(0, 24)
	Cbor.encode(xs) == [0x98, 0x18].concat(xs.map(|_| 0x00))
}

## 2^16 items: a 4-byte argument. 2^16 - 1 items: a 2-byte argument.
expect {
	xs : List(U64)
	xs = List.repeat(1, 65536)
	bytes = Cbor.encode(xs)
	back : Try(List(U64), _)
	back = Cbor.parse(bytes)
	bytes.take_first(5) == [0x9a, 0x00, 0x01, 0x00, 0x00] and bytes.len() == 65541 and back == Ok(xs)
}

## 2^16 - 1 items: a 2-byte argument (99 ff ff).
expect Cbor.encode(List.repeat(1.U64, 65535)).take_first(3) == [0x99, 0xff, 0xff]

## W7: a record of 24 fields with one absent: the head is written again, shortest, for 23.
Wide : {
	a0 : U8,
	a1 : U8,
	a2 : U8,
	a3 : U8,
	a4 : U8,
	a5 : U8,
	a6 : U8,
	a7 : U8,
	a8 : U8,
	a9 : U8,
	b0 : U8,
	b1 : U8,
	b2 : U8,
	b3 : U8,
	b4 : U8,
	b5 : U8,
	b6 : U8,
	b7 : U8,
	b8 : U8,
	b9 : U8,
	c0 : U8,
	c1 : U8,
	c2 : U8,
	c3 ?: U8,
}

## 24 fields write the head b8 18. With c3 absent, 23 fields write the head b7, and the bytes read back.
expect {
	full : Wide
	full = { a0: 0, a1: 0, a2: 0, a3: 0, a4: 0, a5: 0, a6: 0, a7: 0, a8: 0, a9: 0, b0: 0, b1: 0, b2: 0, b3: 0, b4: 0, b5: 0, b6: 0, b7: 0, b8: 0, b9: 0, c0: 0, c1: 0, c2: 0, c3: 0 }
	part : Wide
	part = { a0: 0, a1: 0, a2: 0, a3: 0, a4: 0, a5: 0, a6: 0, a7: 0, a8: 0, a9: 0, b0: 0, b1: 0, b2: 0, b3: 0, b4: 0, b5: 0, b6: 0, b7: 0, b8: 0, b9: 0, c0: 0, c1: 0, c2: 0 }
	back : Try(Wide, _)
	back = Cbor.parse(Cbor.encode(part))
	Cbor.encode(full).take_first(2) == [0xb8, 0x18] and Cbor.encode(part).take_first(2) == [0xb7, 0x62] and back.is_ok()
}

## Several records with absent fields, nested and in a list: each gap of an old head is removed once, at the end.
expect {
	part : Wide
	part = { a0: 0, a1: 0, a2: 0, a3: 0, a4: 0, a5: 0, a6: 0, a7: 0, a8: 0, a9: 0, b0: 0, b1: 0, b2: 0, b3: 0, b4: 0, b5: 0, b6: 0, b7: 0, b8: 0, b9: 0, c0: 0, c1: 0, c2: 0 }
	v : { w : Wide, ws : List(Wide) }
	v = { w: part, ws: [part, part] }
	bytes = Cbor.encode(v)
	one = Cbor.encode(part)
	back : Try({ w : Wide, ws : List(Wide) }, _)
	back = Cbor.parse(bytes)
	bytes == [0xa2, 0x61, 0x77].concat(one).concat([0x62, 0x77, 0x73, 0x82]).concat(one).concat(one) and back.is_ok()
}

## W15: a count of 2^32 or more is not cut to 32 bits. The 9-byte form in a tag number, and a declared count with no items.
expect Cbor.encode_try(Probe.Tagged(4294967296, Probe.Slot(1))) == Ok([0xdb, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x81, 0x07])

## A list declared with 2^32 items that writes none is an error CountMismatch.
expect Cbor.encode_try(Probe.List(4294967296, 0)) == Err(CountMismatch)

# Null in a record (W10, W11)

## W10: a Cbor.Value.Null field writes its key and null (0.4.1 dropped the key).
expect {
	v : { x : Cbor.Value }
	v = { x: Null }
	back : Try(Cbor.Value, _)
	back = Cbor.parse(Cbor.encode(v))
	Cbor.encode(v) == [0xa1, 0x61, 0x78, 0xf6] and back == Ok(Cbor.Value.Map(Cbor.ValueMap.empty().insert(Text("x"), Null)))
}

## W11: a required Try(_, [Null]) field with Err(Null) writes its key and null.
expect {
	v : { x : Try(U64, [Null]), y : U8 }
	v = { x: Err(Null), y: 1 }
	Cbor.encode(v) == [0xa2, 0x61, 0x78, 0xf6, 0x61, 0x79, 0x01]
}

## An absent optional field and Err(Missing) write no key.
expect {
	v : { a : Try(U64, [Missing]), b ?: U64, c : U8 }
	v = { a: Err(Missing), c: 1 }
	Cbor.encode(v) == [0xa1, 0x61, 0x63, 0x01]
}

# W13: a List(U8) is a byte string

## A List(U8) field [de, ad] writes a byte string (42 de ad).
expect Cbor.encode({ k: [0xde.U8, 0xad] }) == [0xa1, 0x61, 0x6b, 0x42, 0xde, 0xad]

## An empty List(U8) is an empty array. A List(List(U8)) is an array of byte strings.
expect {
	empty : List(U8)
	empty = []
	Cbor.encode(empty) == [0x80] and Cbor.encode([[1.U8], [2, 3]]) == [0x82, 0x41, 0x01, 0x42, 0x02, 0x03]
}

## 300 bytes: a 2-byte argument, then the bytes.
expect {
	b : List(U8)
	b = List.repeat(9, 300)
	Cbor.encode(b) == [0x59, 0x01, 0x2c].concat(b)
}

## A tuple, a record and a tag payload of U8 values are not byte strings.
expect Cbor.encode((1.U8, 2.U8)) == [0x82, 0x01, 0x02]

## A record with one U8 field writes a map: a1 61 61 01.
expect Cbor.encode({ a: 1.U8 }) == [0xa1, 0x61, 0x61, 0x01]

## A tag payload of two U8 values writes an array: {"Two": [1, 2]} (a1 63 54 77 6f 82 01 02).
expect {
	v : [Two(U8, U8)]
	v = Two(1, 2)
	Cbor.encode(v) == [0xa1, 0x63, 0x54, 0x77, 0x6f, 0x82, 0x01, 0x02]
}

## A list of a U8 then text (only an encoder_for of an app writes it) falls back to an array.
expect Cbor.encode_try(Probe.Mixed) == Ok([0x82, 0x01, 0x61, 0x61])

## Cbor.U8Array writes an array of integers.
expect Cbor.encode(Cbor.U8Array.([1, 255])) == [0x82, 0x01, 0x18, 0xff]

# encode_with: the option fields

## fields: Camel writes other keys for user_id and display_name, which read back with Camel. With {}, the bytes are those of encode.
expect {
	v = { user_id: 7.U64, display_name: "Ann" }
	bytes = Cbor.encode_with(v, { fields: Camel })
	back : Try({ user_id : U64, display_name : Str }, _)
	back = bytes.map_ok(|b| Cbor.parse_with(b, { fields: Camel })) ?? Err(InvalidCbor(0))
	snake = Cbor.encode_with(v, {})
	back == Ok(v) and snake == Ok(Cbor.encode(v)) and bytes != snake
}

## The option reaches a record in an encoder_for of an app (Cbor.encode_tagged and Cbor.encode_item).
expect Cbor.encode_with(User.(7), { fields: Camel }) == Ok([0xc6, 0xa1, 0x66, 0x75, 0x73, 0x65, 0x72, 0x49, 0x64, 0x07])

# Cbor.Bytes: the fast byte-string type

## A round trip, also as a record field.
expect {
	v : { id : U64, data : Cbor.Bytes }
	v = { id: 7, data: Cbor.Bytes.from_list([0, 255, 16]) }
	back : Try({ id : U64, data : Cbor.Bytes }, _)
	back = Cbor.parse(Cbor.encode(v))
	Cbor.encode(v) == [0xa2, 0x64, 0x64, 0x61, 0x74, 0x61, 0x43, 0x00, 0xff, 0x10, 0x62, 0x69, 0x64, 0x07] and back == Ok(v)
}

## Empty: the head 0x40 only, and it reads back.
expect {
	empty = Cbor.Bytes.from_list([])
	back : Try(Cbor.Bytes, _)
	back = Cbor.parse([0x40])
	Cbor.encode(empty) == [0x40] and back.map_ok(|b| b.to_list()) == Ok([])
}

## The head of each size class: the argument in the head, then 1, 2 and 4 bytes. The bytes
## are the same as the bytes of a List(U8), and each reads back as Cbor.Bytes and as a List(U8).
expect {
	heads = [(23, [0x57]), (24, [0x58, 0x18]), (255, [0x58, 0xff]), (256, [0x59, 0x01, 0x00]), (65_535, [0x59, 0xff, 0xff]), (65_536, [0x5a, 0x00, 0x01, 0x00, 0x00])]
	heads.all(
		|(n, head)| {
			list = List.repeat(0xab, n)
			bytes = Cbor.encode(Cbor.Bytes.from_list(list))
			back : Try(Cbor.Bytes, _)
			back = Cbor.parse(bytes)
			as_list : Try(List(U8), _)
			as_list = Cbor.parse(bytes)
			from_list : Try(Cbor.Bytes, _)
			from_list = Cbor.parse(Cbor.encode(list))
			bytes == head.concat(list) and bytes == Cbor.encode(list) and back.map_ok(|b| b.to_list()) == Ok(list) and as_list == Ok(list) and from_list == back
		},
	)
}

## Cbor.Bytes reads an array of bytes only with BytesFromArray, and an empty array as a List(U8) does.
expect {
	strict : Try(Cbor.Bytes, _)
	strict = Cbor.parse([0x82, 0x01, 0x02])
	lenient : Try(Cbor.Bytes, _)
	lenient = Cbor.parse_with([0x82, 0x01, 0x02], { allow: [BytesFromArray] })
	empty : Try(Cbor.Bytes, _)
	empty = Cbor.parse([0x80])
	text : Try(Cbor.Bytes, _)
	text = Cbor.parse_with([0x61, 0x61], { allow: [BytesFromArray] })
	strict == Err(InvalidCbor(0)) and lenient == Ok(Cbor.Bytes.from_list([1, 2])) and empty == Ok(Cbor.Bytes.from_list([])) and text == Err(InvalidCbor(0))
}

## is_eq, to_list and from_list.
expect Cbor.Bytes.from_list([1, 2]) == Cbor.Bytes.from_list([1, 2]) and Cbor.Bytes.from_list([1, 2]) != Cbor.Bytes.from_list([1]) and Cbor.Bytes.from_list([3]).to_list() == [3]
