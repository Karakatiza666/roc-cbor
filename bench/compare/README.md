# bench/compare

A diagnostic for development: roc-cbor and CBOR libraries of other languages read and write the same fixtures,
so that a slow path or a compiler issue shows up (time per op, throughput, CPU, peak RSS). The other libraries are
reference points, not a contest, and no result is committed.

```sh
ROC=/path/to/roc python3 bench/compare/run.py              # measure Roc, reuse the cached results of the others
ROC=/path/to/roc python3 bench/compare/run.py --refresh    # measure all again (needs cargo, go, zig, cc, pip)
python3 bench/compare/run.py --only roc go-fxamacker --cases records_parse dict_parse --runs 9
```

The report is printed and written to `.cache/compare/report.md`.

## Implementations

| Impl | Library | Typed read and write | Dynamic value | Source |
| --- | --- | --- | --- | --- |
| `roc` | roc-cbor (this repository) | derived from the Roc type | `Cbor.Value` | `roc/compare.roc` |
| `rust-ciborium` | [ciborium](https://crates.io/crates/ciborium) 0.2 | serde derive | `ciborium::Value` | `rust/src/main.rs` |
| `rust-cbor4ii` | [cbor4ii](https://crates.io/crates/cbor4ii) 1.2 | serde derive | `cbor4ii::core::Value` | `rust/src/main.rs` |
| `go-fxamacker` | [fxamacker/cbor](https://github.com/fxamacker/cbor) v2 | struct tags (reflection) | `interface{}` | `go/main.go` |
| `python-cbor2` | [cbor2](https://pypi.org/project/cbor2/) 6 (compiled) | `loads` + a slotted class for each record | `loads` | `python/bench.py` |
| `zig-zbor` | [zbor](https://github.com/r4gus/zbor) 0.23 | comptime reflection | none (n/a) | `zig/main.zig` |

Versions are pinned by `rust/Cargo.lock`, `go/go.sum`, `python/requirements.txt` and `zig/build.zig.zon`.

## Method

1. `bench/bench.roc dump <fixture>` writes each input as hex. `run.py` writes them to `.cache/compare/fixtures/`.
   Each implementation parses these bytes, so each side reads the same input (Roc embeds them with
   `import "…" as x : List(U8)` in `roc/compare.roc`; the others read the file at start).
2. Each implementation is a program `<impl> <case> <loops> [fixture_dir]` that prints `case loops checksum`.
   The setup (the fixture; for an encode case, the parse of the fixture into the value to encode) is not
   timed. Exit 3 means the library cannot do the case (n/a).
3. Each run goes through `rusage.c` (fork, exec, `wait4`): wall time, user + sys CPU, peak RSS.
   Not `os.wait4` from Python: Linux keeps the peak RSS of the forked parent in the child across `exec`.
4. A run with 1 loop checks the checksum (the item count of a parse, or the output length of an encode).
   Then: the median of `--runs` runs with 0 loops, a loop count for about `--ms` of work, and the median
   of `--runs` runs with that count.

| Metric | Definition |
| --- | --- |
| ms per op | (median wall of N loops - median wall of 0 loops) / N |
| MB/s | fixture bytes / ms per op (1 MB = 10^6 bytes; for an encode case, the bytes of the fixture) |
| CPU per op | the same with user + sys CPU. Above ms per op: work on other threads (the GC of Go). |
| Memory of one op | peak RSS of 1 loop - peak RSS of 0 loops: the memory of one parse or encode at its peak. For Roc it also counts the fixture (embedded in the binary, so its pages come in when the op reads them; the others read the file at start): up to 1.4 MiB. |
| Peak RSS after N loops | the peak RSS of the timed run: growth above one op is a GC heap or a leak |
| Base RSS, Start | the peak RSS and the wall time of a run with 0 loops: runtime and setup |

## Cases

| Case | Fixture | What |
| --- | --- | --- |
| `bytes_encode`, `bytes_parse` | `bytes` | a byte string of 1 MB |
| `records_encode`, `records_parse` | `records` | 10k records `{id, name, ok, score, tags}`, typed |
| `records_value` | `records` | the same into the dynamic value |
| `unknown_parse` | `wide` | 10k records with 12 more fields each, read as the 5-field record (skip unknown fields) |
| `dict_parse` | `dict` | a map of 100k text keys into a hash map of text to integer |
| `map_value` | `dict` | the same into the dynamic value |
| `text_parse` | `texts` | 10k texts of multi-byte UTF-8 into a list of strings |
| `deep_encode`, `deep_parse` | `deep` | 500 nested arrays, dynamic value |

## Caching

`.cache/compare/results/<impl>.json` holds the last measurement of each other language (local, not committed),
so that a later run of `run.py` measures only Roc. A cached result is used when its `key` matches: a hash of the
fixtures, of the source and lock files of the implementation, and of the CPU model. A change of the
fixtures (a change of `bench/bench.roc` or of the writer), of the code of that language, or another CPU
measures it again. Roc writes its result to `.cache/compare/roc.json`. Cached numbers are of one machine
(the `cpu` field): compare Roc with them only on that machine, or run `--refresh`.

## Differences between the libraries

These hold for the inputs here. They are the reasons a column is not the same work as another column.

| Difference | Effect |
| --- | --- |
| roc-cbor checks each item before the typed parse (well-formed, UTF-8, shortest heads, no duplicate keys, depth) | Work the others do in part. None checks shortest heads. Go (`DupMapKeyQuiet`) and cbor2 allow duplicate keys by default. zbor checks well-formedness, but not the UTF-8 of a text it reads. ciborium, cbor4ii, Go and cbor2 check UTF-8. |
| `Cbor.Bytes` of `bytes_parse` is a slice of the input (no copy) | Roc does almost no work; the others copy 1 MB. |
| Python has no typed reader | `records_parse` is `loads` and a slotted object for each record; `dict_parse` and `text_parse` are `loads`. |
| zbor has no dynamic value tree (its `DataItem` is a checked view of the bytes), no hash map target, and a fixed depth limit of 128 | `*_value`, `deep_*`: n/a. `dict_parse` walks zbor's map iterator into a `std.StringHashMap`. Each parse uses an arena that is freed after the op. |
| Depth limits | Raised so that `deep` (500) reads: ciborium 1024 (default 256), cbor4ii 1024 (a reader with its own limit; the default is 256), Go `MaxNestedLevels` 1024 (default 32), cbor2 `max_depth` 1024 (default 400). roc-cbor: 512. |
| cbor4ii reads an `f64` only from an 8-byte float | A record with the f16 `score` of preferred serialization fails. `Rec.score` uses `deserialize_with` that takes each float width. |
| Float width on write | roc-cbor, ciborium and Go (`ShortestFloat16`) write the shortest float (474,635 bytes for `records_encode`). cbor4ii, cbor2 and zbor write 8-byte floats (518,613 bytes). |
| Garbage collection | Go and Python free with a GC; their CPU per op can be above the wall time, and their peak RSS grows with N. |
