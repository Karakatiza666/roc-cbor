app [] { pkg: "../src/main.roc" }

# The checked reader (0.5.0), through the public API of the package. One notion of a valid item: a skipped
# unknown field, a map of an internal tag, `Cbor.path_at` and `Cbor.Value` have the same checks. The depth
# limit is 512 arrays, maps and tags, for each reader.

import pkg.Cbor

# Helpers

R : { a : U64 }

## The bytes of `{"a": 1, "x": item}`. The item starts at 6.
with_x : List(U8) -> List(U8)
with_x = |item| [0xa2, 0x61, 0x61, 0x01, 0x61, 0x78].concat(item)

## The result of three readers for the same bytes: a record that skips `x`, a `Cbor.Value`, `path_at` of the item.
Agree : { record : Try(R, Cbor.Error), value : Try(Cbor.Value, Cbor.Error), path : Try(List(Cbor.Step), [NotFound]) }

readers : List(U8) -> Agree
readers = |item| {
	bytes = with_x(item)
	record : Try(R, _)
	record = Cbor.parse(bytes)
	value : Try(Cbor.Value, _)
	value = Cbor.parse(bytes)
	{ record, value, path: Cbor.path_at(bytes, 6) }
}

## Each reader gives an error at `pos`, and `path_at` gives `NotFound`.
rejected : List(U8), U64 -> Bool
rejected = |item, pos| {
	r = readers(item)
	r.record == Err(InvalidCbor(pos)) and r.value == Err(InvalidCbor(pos)) and r.path == Err(NotFound)
}

## Each reader gives Ok.
accepted : List(U8) -> Bool
accepted = |item| {
	r = readers(item)
	r.record == Ok({ a: 1 }) and r.value.is_ok() and r.path == Ok([Key("x")])
}

internal : Cbor.Options
internal = { unions: Internal({ tag: "kind", content: "value" }) }

Pay : [Cash, Card({ last4 : Str }), Check(U64)]

## A recursive type of the app: each `Link` is a map of one entry (6 bytes), `End` is text.
Chain := [End, Link(Chain)].{
	parser_for : _
}

## `n` nested `Link` maps, then `End`.
chain_bytes : U64 -> List(U8)
chain_bytes = |n| List.repeat([0xa1, 0x64, 'L', 'i', 'n', 'k'], n).join().concat([0x63, 'E', 'n', 'd'])

parse_chain : List(U8) -> Try(Chain, Cbor.Error)
parse_chain = |bytes| Cbor.parse(bytes)

## A recursive type with an internal tag: `{ "kind": "Node", "value": [child] }` or `{ "kind": "Leaf", "value": n }`.
Tree := [Leaf(U64), Node(List(Tree))].{
	parser_for : _
}

parse_tree : List(U8) -> Try(Tree, Cbor.Error)
parse_tree = |bytes| Cbor.parse_with(bytes, internal)

kind_node : List(U8)
kind_node = [0x64, 'k', 'i', 'n', 'd', 0x64, 'N', 'o', 'd', 'e']

value_key : List(U8)
value_key = [0x65, 'v', 'a', 'l', 'u', 'e']

leaf : List(U8)
leaf = [0xa2, 0x64, 'k', 'i', 'n', 'd', 0x64, 'L', 'e', 'a', 'f', 0x65, 'v', 'a', 'l', 'u', 'e', 0x07]

## `n` levels of Node with the tag key first, then a Leaf.
tree_tag_first : U64 -> List(U8)
tree_tag_first = |n| List.repeat([0xa2].concat(kind_node).concat(value_key).append(0x81), n).join().concat(leaf)

## `n` levels of Node with the content key first: the tag key comes after the subtree.
tree_content_first : U64 -> List(U8)
tree_content_first = |n| List.repeat([0xa2].concat(value_key).append(0x81), n).join().concat(leaf).concat(List.repeat(kind_node, n).join())

## The leaf value at the bottom of a tree, and the count of Node levels.
bottom : Tree -> (U64, U64)
bottom = |tree| {
	var $t = tree
	var $levels = 0
	var $out = (0, 0)
	var $more = Bool.True
	while $more {
		match $t {
			Tree.(Leaf(v)) => {
				$out = (v, $levels)
				$more = Bool.False
			}
			Tree.(Node([child])) => {
				$t = child
				$levels = $levels + 1
			}
			Tree.(Node(_)) => {
				$more = Bool.False
			}
		}
	}
	$out
}

# F1: a skipped unknown field has the checks of Cbor.Value

## Invalid UTF-8, an overlong form, a surrogate.
expect rejected([0x61, 0xff], 6)

## The overlong form c0 80 in skipped text is an error at the text, byte 6.
expect rejected([0x62, 0xc0, 0x80], 6)

## The surrogate ed a0 80 in skipped text is an error at the text, byte 6.
expect rejected([0x63, 0xed, 0xa0, 0x80], 6)

## The ASCII scan of the UTF-8 check: a bad byte after ASCII bytes, in text of 3, 32 and 33 bytes.
expect rejected([0x63, 'a', 'b', 0xff], 6)

## Text of 32 bytes, 31 'a' then ff, is an error at the text, byte 6.
expect rejected([0x78, 32].concat(List.repeat('a', 31)).append(0xff), 6)

## Text of 33 bytes, 32 'a' then ff, is an error at the text, byte 6.
expect rejected([0x78, 33].concat(List.repeat('a', 32)).append(0xff), 6)

## Text of 3 bytes, 'a' then the two bytes c3 a9, is valid in each reader.
expect accepted([0x63, 'a', 0xc3, 0xa9])

## Text of 33 'a' bytes is valid in each reader.
expect accepted([0x78, 33].concat(List.repeat('a', 33)))

## A simple value of 2 bytes below 32 (`f8 00`, `f8 1f`). `f8 20` is valid.
expect rejected([0xf8, 0x00], 6)

## The simple value f8 1f is an error at byte 6.
expect rejected([0xf8, 0x1f], 6)

## The simple value f8 20 is valid in each reader.
expect accepted([0xf8, 0x20])

## Reserved info, a lone break.
expect rejected([0x1c], 6)

## A lone break (ff) is an error at byte 6.
expect rejected([0xff], 6)

## An indefinite length: an error in the strict readers. It is well formed, so `path_at` walks it (IndefiniteLength).
expect {
	r = readers([0x9f, 0xff])
	r.record == Err(InvalidCbor(6)) and r.value == Err(InvalidCbor(6)) and r.path == Ok([Key("x")])
}

## In a nested map key, a nested array, a tagged item: the error is at the bad text.
expect rejected([0xa1, 0x61, 0xff, 0x01], 7)

## Invalid UTF-8 in text in a nested array (81 61 ff) is an error at the text, byte 7.
expect rejected([0x81, 0x61, 0xff], 7)

## Invalid UTF-8 in text in a tagged item (c0 61 ff) is an error at the text, byte 7.
expect rejected([0xc0, 0x61, 0xff], 7)

## A map key of any type and any tag stay valid in a skipped item.
expect accepted([0xa1, 0x01, 0x02])

## A tagged item (c1 00) is valid in a skipped field.
expect accepted([0xc1, 0x00])

## The record itself still needs text keys.
expect {
	r : Try(R, _)
	r = Cbor.parse([0xa2, 0x61, 0x61, 0x01, 0x01, 0x02])
	r == Err(InvalidCbor(4))
}

# F2: the map of an internal tag has the same checks

## A key that is not text, after or before the tag key: an error at the map.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with([0xa3, 0x64, 'k', 'i', 'n', 'd', 0x65, 'C', 'h', 'e', 'c', 'k', 0x65, 'v', 'a', 'l', 'u', 'e', 0x07, 0x01, 0x02], internal)
	r == Err(InvalidCbor(0))
}

## A key that is not text (01) before the tag key is an error at the map, byte 0.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with([0xa3, 0x01, 0x02, 0x64, 'k', 'i', 'n', 'd', 0x65, 'C', 'h', 'e', 'c', 'k', 0x65, 'v', 'a', 'l', 'u', 'e', 0x07], internal)
	r == Err(InvalidCbor(0))
}

## Invalid UTF-8 in another value or key, and `f8 00` in another value: an error at the bad item.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with([0xa3, 0x64, 'k', 'i', 'n', 'd', 0x65, 'C', 'h', 'e', 'c', 'k', 0x65, 'v', 'a', 'l', 'u', 'e', 0x07, 0x61, 'x', 0x61, 0xff], internal)
	r == Err(InvalidCbor(21))
}

## Invalid UTF-8 in another key (61 ff) is an error at that key, byte 19.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with([0xa3, 0x64, 'k', 'i', 'n', 'd', 0x65, 'C', 'h', 'e', 'c', 'k', 0x65, 'v', 'a', 'l', 'u', 'e', 0x07, 0x61, 0xff, 0x01], internal)
	r == Err(InvalidCbor(19))
}

## The simple value f8 00 in another value is an error at that value, byte 13.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with([0xa2, 0x64, 'k', 'i', 'n', 'd', 0x64, 'C', 'a', 's', 'h', 0x61, 'x', 0xf8, 0x00], internal)
	r == Err(InvalidCbor(13))
}

## A valid map with other keys reads.
expect {
	r : Try(Pay, _)
	r = Cbor.parse_with([0xa3, 0x64, 'k', 'i', 'n', 'd', 0x65, 'C', 'h', 'e', 'c', 'k', 0x65, 'v', 'a', 'l', 'u', 'e', 0x07, 0x61, 'x', 0xa1, 0x01, 0x02], internal)
	r == Ok(Check(7))
}

# F6: path_at gives Ok only for one valid item

## Trailing bytes.
expect Cbor.path_at([0x01, 0xff], 0) == Err(NotFound)

## The item 01 followed by the extra byte 00 gives NotFound.
expect Cbor.path_at([0x01, 0x00], 0) == Err(NotFound)

## An invalid item before `pos`: `f8 00`, invalid UTF-8, a break with no indefinite length.
expect Cbor.path_at([0x82, 0xf8, 0x00, 0x01], 3) == Err(NotFound)

## Invalid UTF-8 (61 ff) in an item before `pos` gives NotFound.
expect Cbor.path_at([0x82, 0x61, 0xff, 0x01], 3) == Err(NotFound)

## A break (ff) with no indefinite length before `pos` gives NotFound.
expect Cbor.path_at([0x82, 0xff, 0x01], 2) == Err(NotFound)

## An item of indefinite length is well formed: `path_at` walks it, as for a parse with IndefiniteLength.
expect Cbor.path_at([0x82, 0x9f, 0xff, 0x01], 3) == Ok([Index(1)])

## An invalid item after `pos`.
expect Cbor.path_at([0x82, 0x01, 0x61, 0xff], 1) == Err(NotFound)

## A map with a key that is not text: Ok next to it, NotFound through it.
expect Cbor.path_at([0x82, 0xa1, 0x01, 0x02, 0x03], 4) == Ok([Index(1)])

## A position in a map with the key 01 that is not text gives NotFound.
expect Cbor.path_at([0x82, 0xa1, 0x01, 0x02, 0x03], 3) == Err(NotFound)

# The depth limit: 512 arrays, maps and tags

## Cbor.Value: 512 nested arrays read, 513 are an error at the 513th head.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0x81, 512).append(0x00))
	r.is_ok()
}

## Cbor.Value: 513 nested arrays are an error at byte 512.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0x81, 513).append(0x00))
	r == Err(InvalidCbor(512))
}

## An empty array is an array: 512 in all read, 513 do not.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0x81, 511).append(0x80))
	r.is_ok()
}

## Cbor.Value: 512 nested arrays around an empty array are an error at byte 512.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0x81, 512).append(0x80))
	r == Err(InvalidCbor(512))
}

## Tags count: 511 tags around 1 array read, 512 do not.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0xc1, 511).append(0x80))
	r.is_ok()
}

## Cbor.Value: 512 tags around an empty array are an error at byte 512.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0xc1, 512).append(0x80))
	r == Err(InvalidCbor(512))
}

## A skipped field: the record is 1 level, so 511 arrays in the field read, 512 do not.
expect {
	r : Try(R, _)
	r = Cbor.parse(with_x(List.repeat(0x81, 511).append(0x00)))
	r == Ok({ a: 1 })
}

## A record with 512 nested arrays in the skipped field is an error at byte 6 + 511.
expect {
	r : Try(R, _)
	r = Cbor.parse(with_x(List.repeat(0x81, 512).append(0x00)))
	r == Err(InvalidCbor(6 + 511))
}

## path_at has no depth limit (a loop), so it finds the item of a depth error: 513 levels give a path.
expect Cbor.path_at(List.repeat(0x81, 512).append(0x00), 512) == Ok(List.repeat(Index(0), 512))

## path_at of the inner item of 513 nested arrays gives a path of 513 Index(0) steps.
expect Cbor.path_at(List.repeat(0x81, 513).append(0x00), 513) == Ok(List.repeat(Index(0), 513))

## A recursive type of the app: 512 levels read, 513 are an error at the 513th map.
expect parse_chain(chain_bytes(512)).is_ok()

## A Chain of 513 Link maps is an error at the 513th map, byte 512 * 6.
expect parse_chain(chain_bytes(513)).map_ok(|_| {}) == Err(InvalidCbor(512 * 6))

## 1,000,000 levels: an error, no crash (D1, D2).
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0x81, 1_000_000).append(0x00))
	r == Err(InvalidCbor(512))
}

## Cbor.Value: 1,000,000 nested tags are an error at byte 512, with no crash.
expect {
	r : Try(Cbor.Value, _)
	r = Cbor.parse(List.repeat(0xc1, 1_000_000).append(0x00))
	r == Err(InvalidCbor(512))
}

## path_at of byte 0 in 1,000,000 nested arrays gives the empty path, with no crash.
expect Cbor.path_at(List.repeat(0x81, 1_000_000).append(0x00), 0) == Ok([])

## A Chain of 1,000,000 Link maps is an error at byte 512 * 6, with no crash.
expect parse_chain(chain_bytes(1_000_000)).map_ok(|_| {}) == Err(InvalidCbor(512 * 6))

## A record with 1,000,000 nested arrays in the skipped field is an error at byte 6 + 511, with no crash.
expect {
	r : Try(R, _)
	r = Cbor.parse(with_x(List.repeat(0x81, 1_000_000).append(0x00)))
	r == Err(InvalidCbor(6 + 511))
}

# Internal tags in depth (D3): one scan of each map

## 255 levels (a map and an array each), with the tag key first and with the content key first.
expect parse_tree(tree_tag_first(255)).map_ok(bottom) == Ok((7, 255))

## 255 Node levels with the content key first read, with the leaf 7 at the bottom.
expect parse_tree(tree_content_first(255)).map_ok(bottom) == Ok((7, 255))

## 256 levels and the leaf map: 513 levels, an error at the leaf map.
expect parse_tree(tree_tag_first(256)).map_ok(|_| {}) == Err(InvalidCbor(256 * 18))

# A reader past the walked item (P25)

## Two items read as one by a parser of your own. `parse_prefix` walks only the first item, so the second one is
## not walked: each check of the text must still be in the reader of `Cbor.Value` and of `Str`.
TwoItems := (Cbor.Value, Cbor.Value).{
	parser_for : Cbor -> (Cbor.Reader -> Try({ value : TwoItems, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		first : { value : Cbor.Value, rest : Cbor.Reader }
		first = Cbor.parse_item(encoding, state)?
		second : { value : Cbor.Value, rest : Cbor.Reader }
		second = Cbor.parse_item(encoding, first.rest)?
		Ok({ value: TwoItems.((first.value, second.value)), rest: second.rest })
	}
}

TwoTexts := (Str, Str).{
	parser_for : Cbor -> (Cbor.Reader -> Try({ value : TwoTexts, rest : Cbor.Reader }, Cbor.Error))
	parser_for = |encoding| |state| {
		first = Cbor.parse_str(encoding, state)?
		second = Cbor.parse_str(encoding, first.rest)?
		Ok({ value: TwoTexts.((first.value, second.value)), rest: second.rest })
	}
}

## Invalid UTF-8 in the item that is not walked: an error at that text, in a `Cbor.Value` (also as a map key) and in a `Str`.
expect {
	r : Try({ value : TwoItems, rest : List(U8) }, _)
	r = Cbor.parse_prefix([0x01, 0x61, 0xff])
	r.map_ok(|_| {}) == Err(InvalidCbor(1))
}

## Invalid UTF-8 in a map key of the second item, which is not walked, is an error at that key, byte 2.
expect {
	r : Try({ value : TwoItems, rest : List(U8) }, _)
	r = Cbor.parse_prefix([0x01, 0xa1, 0x61, 0xff, 0x01])
	r.map_ok(|_| {}) == Err(InvalidCbor(2))
}

## Invalid UTF-8 in the second Str of TwoTexts is an error at that text, byte 2.
expect {
	r : Try({ value : TwoTexts, rest : List(U8) }, _)
	r = Cbor.parse_prefix([0x61, 'a', 0x61, 0xff])
	r.map_ok(|_| {}) == Err(InvalidCbor(2))
}

## Valid text past the walked item: an error at the end of the walked item.
expect {
	r : Try({ value : TwoItems, rest : List(U8) }, _)
	r = Cbor.parse_prefix([0x01, 0x61, 'a'])
	r.map_ok(|_| {}) == Err(InvalidCbor(3))
}

## `path_at` through a map key with invalid UTF-8: NotFound (the walk of `path_at` rejects it).
expect Cbor.path_at([0xa1, 0x61, 0xff, 0x01], 3) == Err(NotFound)

## path_at through an indefinite-length map key with invalid UTF-8 in a chunk gives NotFound.
expect Cbor.path_at([0xa1, 0x7f, 0x61, 0xff, 0xff, 0x01], 5) == Err(NotFound)

## path_at through an indefinite-length map key of the chunks "a" and "b" gives Key("ab").
expect Cbor.path_at([0xa1, 0x7f, 0x61, 'a', 0x61, 'b', 0xff, 0x01], 7) == Ok([Key("ab")])
