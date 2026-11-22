#!/usr/bin/env bash
# L1: builds each fuzz target in fuzz/ with roc-fuzz and runs a fixed count of inputs.
# Usage: ROC=/path/to/roc scripts/fuzz.sh [runs]. Default: 1,000,000 runs of each target, seed 1.
# roc-fuzz runs on Linux x86-64 and macOS arm64 only. The report of each run (with a failing input) is in
# .cache/fuzz/art-<target>/. The count of runs is the limit, and for `stream` also a time limit: see time_of.
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
runs="${1:-1000000}"

# The time limit of a target in seconds (0: none, the count of runs only). `stream` checks 5 chunkings and many
# decoders for each input, and its examples soon lead to large inputs: 1,000,000 runs took more than 5.4 h on CI.
# So it stops at 30 minutes, or at the count of runs if that comes first. The seed is fixed, but the count of
# runs in 30 minutes changes with the machine; the log gives it ("attempted").
time_of() {
	case "$1" in
	stream) echo "${FUZZ_STREAM_TIME:-1800}" ;;
	*) echo 0 ;;
	esac
}
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
# roc build stops with PathOutsideWorkspace when this path has `..` in it.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$PWD/.cache/xdg}"
work="$PWD/.cache/fuzz"
mkdir -p "$work"

status=0
for f in fuzz/*.roc; do
	name=$(basename "$f" .roc)
	code=0
	"$ROC" build --fuzz "$f" --output="$work/$name" >"$work/$name.build.log" 2>&1 || code=$?
	# roc build exits with 1 for errors and 2 for warnings only. roc-fuzz 0.6.2 has a warning in its platform
	# (a shadowed name), so 2 is a build.
	if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
		echo "$name: build failed"
		tail -n 30 "$work/$name.build.log"
		exit 1
	fi
	rm -rf "$work/art-$name" "$work/corpus-$name"
	mkdir -p "$work/art-$name" "$work/corpus-$name"
	# roc-fuzz 0.6.2: `run` checks the declared examples, then explores until --runs or --time (0: no time limit).
	secs=$(time_of "$name")
	if "$work/$name" run "$work/corpus-$name" --runs="$runs" --time="$secs" --seed=1 --max-input-size=4096 \
		--dictionary=fuzz/cbor.dict --report-dir="$work/art-$name" >"$work/$name.log" 2>&1; then
		tried=$(sed -n 's/.*(attempted \([0-9]*\),.*/\1/p' "$work/$name.log" | tail -n 1)
		limit="$runs runs"
		[ "$secs" -ne 0 ] && limit="$limit or $secs s"
		echo "$name: pass, ${tried:-?} runs (limit: $limit)"
	else
		status=1
		echo "$name: FAIL"
		tail -n 30 "$work/$name.log"
		for a in "$work/art-$name"/failures/*; do
			[ -e "$a" ] && "$work/$name" show "$a" || true
		done
	fi
done
exit "$status"
