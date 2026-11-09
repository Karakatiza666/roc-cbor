#!/usr/bin/env bash
# The local and CI checks. Usage: ROC=/path/to/roc scripts/all_tests.sh
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
# Keep the roc cache inside the repository.
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
mkdir -p "$ROC_CACHE_DIR"

"$ROC" version
"$ROC" fmt --check src tests examples fuzz
"$ROC" check src/main.roc
# The expects in src/Cbor.roc.
"$ROC" test src/main.roc
# The RFC 8949 Appendix A vectors, through the public API of the package.
"$ROC" test tests/rfc8949.roc
# The short where aliases Cbor.Readable and Cbor.Writable, through the public API of the package.
"$ROC" test tests/aliases.roc
# SQL rows with `allow: Cbor.sql_rows`: a Bool reads 0 and 1, a null value in a map is no key, through the public API of the package.
"$ROC" test tests/rows.roc
# Tags and dynamic values: Cbor.parse_cbor_tag, Cbor.peek, Cbor.Value, ignore_tags, dec_from_text, through the public API of the package.
"$ROC" test tests/tags.roc
# Tag unions: the option unions (an internal tag) and Cbor.parse_union, through the public API of the package.
"$ROC" test tests/unions.roc
# Small integer types: the range of U8 to I32, and a List(U8) as an array, through the public API of the package.
"$ROC" test tests/ints.roc
# The checked reader: one notion of a valid item for each reader, and the depth limit, through the public API of the package.
"$ROC" test tests/reader.roc
# One truncation rule: the error position when the bytes end in an item, and a count far larger than the input.
"$ROC" test tests/truncation.roc
# The writer: item counts, shortest heads, null in a record, List(U8) as bytes, encode_tagged, encode_with, through the public API of the package.
"$ROC" test tests/writer.roc
# The reader options: each lenient read, null in a record, duplicate_keys in each reader, unknown_fields, max_items, Camel keys, exact floats.
"$ROC" test tests/options.roc
# The read option key_order: Sorted (RFC 8949 4.2.1 order of the keys of each map) in each reader, with duplicate_keys.
"$ROC" test tests/key_order.roc
# The stream writer Cbor.StreamWriter: each kind of level, counts and lengths, the 9-byte head, key_order: Sorted on a streamed map.
"$ROC" test tests/stream_writer.roc
# The stream decoder Cbor.Items: each split of the input into chunks gives the items and the error of parse_with, max_buffer, iter.
"$ROC" test tests/stream.roc
# The stream decoder Cbor.Entries: each split gives the entries and the error of parse_with of a Dict, duplicate keys (KeySet, Sorted), max_buffer, iter.
"$ROC" test tests/stream_entries.roc
# The stream decoders Cbor.ByteChunks and Cbor.TextChunks: each split gives the data and the error of parse_with, the UTF-8 hold back.
"$ROC" test tests/stream_chunks.roc
# The adapters to the builtin Stream: from_stream of each decoder, and the writer adapters. An app, not roc test: a
# Stream is effectful. It prints each failed check and exits with 1.
"$ROC" check tests/stream_adapters.roc
"$ROC" tests/stream_adapters.roc
# A Dict: encode_dict, keys that are not text on read (duplicate_keys, the exact form of a key), U128 and I128 with bignums.
"$ROC" test tests/dict.roc
# Indefinite lengths with the leniency IndefiniteLength: arrays, maps, byte strings and text in each typed reader.
"$ROC" test tests/indefinite.roc
# Dynamic values and protocol support: Cbor.ValueMap, Cbor.IntValue, Cbor.SimpleValue, is_eq and to_hash, parse_prefix, parse_sequence, Cbor.Raw.
"$ROC" test tests/value.roc
# Preferred floats (the shortest of f16, f32, f64) and the deterministic encoding (key_order: Sorted), through the public API of the package.
"$ROC" test tests/deterministic.roc
# The wasm32 dev backend: the shapes that overflowed the stack, built with --opt=dev and run in node (SKIP with no node).
scripts/wasm_dev.sh
for f in examples/*.roc; do
	"$ROC" check "$f"
	"$ROC" "$f"
done
"$ROC" docs src/main.roc --output="$ROC_CACHE_DIR/docs" >/dev/null
