#!/usr/bin/env bash
# L1: builds each fuzz target in fuzz/ with roc-fuzz and runs a fixed count of inputs.
# Usage: ROC=/path/to/roc scripts/fuzz.sh [runs]. Default: 1,000,000 runs of each target, seed 1.
# roc-fuzz runs on Linux x86-64 and macOS arm64 only. The report of each run (with a failing input) is in
# .cache/fuzz/report-<target>/. The count of runs is the only limit (--time=0).
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
runs="${1:-1000000}"
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
# roc build stops with PathOutsideWorkspace when this path has `..` in it.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$PWD/.cache/xdg}"
work="$PWD/.cache/fuzz"
mkdir -p "$work"

status=0
for f in fuzz/*.roc; do
	name=$(basename "$f" .roc)
	if ! "$ROC" build --fuzz "$f" --output="$work/$name" >"$work/$name.build.log" 2>&1; then
		echo "$name: build failed"
		tail -n 30 "$work/$name.build.log"
		exit 1
	fi
	rm -rf "$work/report-$name" "$work/corpus-$name"
	mkdir -p "$work/report-$name" "$work/corpus-$name"
	if "$work/$name" run "$work/corpus-$name" --runs="$runs" --time=0 --seed=1 --max-input-size=4096 \
		--dictionary=fuzz/cbor.dict --report-dir="$work/report-$name" >"$work/$name.log" 2>&1; then
		echo "$name: pass, $runs runs"
	else
		status=1
		echo "$name: FAIL"
		tail -n 30 "$work/$name.log"
		ls -R "$work/report-$name"
	fi
done
exit "$status"
