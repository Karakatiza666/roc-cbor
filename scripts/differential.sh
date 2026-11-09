#!/usr/bin/env bash
# P24: the differential test of Cbor.Value against Python cbor2. The table of expected differences is in
# differential/differential.py. A difference that is not expected is a FINDING and the exit code is 1.
# Usage: ROC=/path/to/roc PYTHON=/path/to/venv/bin/python scripts/differential.sh [count] [seed]
# Setup (one time, needs network): python3 -m venv .cache/venv && .cache/venv/bin/pip install cbor2==6.2.1
# Inputs: the fuzz corpus (.cache/fuzz/corpus-*, after scripts/fuzz.sh) when it is there, the vectors of
# tests/rfc8949.roc, special inputs, `count` random items (default 10000) and `count` mutations of them.
# DIFF_STRICT=1: roc-cbor rejects padded numbers (no PaddedNumbers), so that is an expected difference.
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
PYTHON="${PYTHON:-$PWD/.cache/venv/bin/python}"
count="${1:-10000}"
seed="${2:-1}"
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
# roc build stops with PathOutsideWorkspace when this path has `..` in it.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$PWD/.cache/xdg}"
work="$PWD/.cache/differential"
mkdir -p "$work"

if ! "$PYTHON" -I -c "import cbor2" 2>/dev/null; then
	echo "no cbor2 for $PYTHON. Setup: python3 -m venv .cache/venv && .cache/venv/bin/pip install cbor2==6.2.1"
	exit 2
fi
if ! "$ROC" build --opt=speed differential/value_dump.roc --output="$work/value_dump" >"$work/build.log" 2>&1; then
	echo "build failed"
	tail -n 30 "$work/build.log"
	exit 1
fi

corpus=()
for d in .cache/fuzz/corpus-*; do
	[ -d "$d" ] && corpus+=(--corpus "$d")
done
strict=()
[ "${DIFF_STRICT:-0}" = 1 ] && strict=(--strict)
"$PYTHON" -I differential/differential.py --roc-bin "$work/value_dump" --rfc tests/rfc8949.roc \
	--count "$count" --seed "$seed" "${corpus[@]}" "${strict[@]}"
