#!/usr/bin/env bash
# L1: builds each fuzz target in fuzz/ with roc-fuzz and runs a fixed count of inputs.
# Usage: ROC=/path/to/roc scripts/fuzz.sh [runs]. Default: 1,000,000 runs of each target, seed 1.
# roc-fuzz runs on Linux x86-64 and macOS arm64 only. A failure is saved in .cache/fuzz/art-<target>/.
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
	code=0
	"$ROC" build --fuzz "$f" --output="$work/$name" >"$work/$name.build.log" 2>&1 || code=$?
	# roc build exits with 1 for errors and 2 for warnings only. roc-fuzz 0.6.1 has a warning in its platform
	# (a shadowed name), so 2 is a build.
	if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
		echo "$name: build failed"
		tail -n 30 "$work/$name.build.log"
		exit 1
	fi
	rm -rf "$work/art-$name" "$work/corpus-$name"
	mkdir -p "$work/art-$name" "$work/corpus-$name"
	# roc-fuzz 0.6.1: `run` checks the declared examples, then explores. --time=0 leaves the bound to --runs.
	if "$work/$name" run "$work/corpus-$name" --runs="$runs" --time=0 --seed=1 --max-input-size=4096 \
		--dictionary=fuzz/cbor.dict --report-dir="$work/art-$name" >"$work/$name.log" 2>&1; then
		echo "$name: pass, $runs runs"
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
