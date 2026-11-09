#!/usr/bin/env bash
# The wasm32 dev backend test: tests/wasm_dev/app.roc built with --target=wasm32 --opt=dev, run in node.
#
# Usage: ROC=/path/to/roc scripts/wasm_dev.sh
#   WASM_DEV_STACK          the stack of the build in bytes (default 393216)
#   WASM_DEV_LEVEL_BUDGET   the stack for each nesting level of a value, in bytes (default 30000)
#   WASM_DEV_OPT            the build mode (default dev). `speed` gives the checksums of tests/wasm_dev/expected.txt.
#   WASM_DEV_PKG            the package main.roc, relative to .cache/wasm_dev (default ../../src/main.roc)
# Needs node. With no node, it prints SKIP and exits 0.
#
# What it covers: `Cbor.encode` of the shapes that trapped on the platform (`RuntimeError: memory access out of
# bounds`, a stack overflow). The dev backend copies the code around a closure call into each member of the
# lambda set (each item encoder of the app), each copy with its own stack. So the frame of `slot` grew with the
# number of encoders, and each nesting level of a value used it once. Each case must give the checksum of the
# speed build, and must not trap on the small stack. The case `stream` writes with Cbor.StreamWriter (with the 9-byte head).
# The case `adapter` reads rows with Cbor.Items.from_stream and `for!` from a `Stream`, and writes with
# Cbor.StreamWriter.bytes_stream (the 9-byte head, then a source error) (171 KB of stack on the 11-07 dev build).
# With a nightly that exports __stack_low and __stack_high
# (2026-11-06 or later), the stack for each nesting level must be under the budget.
#
# Test of the test: with the slot of 7ad0ee6 (WASM_DEV_PKG pointing to a copy of that src/), nightly-2026-10-19
# traps in 6 of 7 cases, and nightly-2026-11-06 measures about 52 KB for each level (with the fix: about 15 KB).
#
# The host is node: tests/wasm_dev/run.mjs gives roc_alloc and the other imports. The platform has no host code:
# roc needs a relocatable wasm object, so the script writes an empty one (only a "linking" section).
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
root="$PWD"
if ! command -v node >/dev/null; then
	echo "SKIP wasm_dev: no node"
	exit 0
fi
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$root/.cache/roc}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$root/.cache/xdg}"
work="$root/.cache/wasm_dev"
rm -rf "$work"
mkdir -p "$work/platform/targets/wasm32"
cp tests/wasm_dev/platform/main.roc "$work/platform/main.roc"
# The empty object: the wasm header, then a custom section "linking" with version 2.
printf '\0asm\1\0\0\0\0\011\007linking\002' >"$work/platform/targets/wasm32/host.wasm"
opt="${WASM_DEV_OPT:-dev}"
# Two apps: app.roc (the encode shapes, Cbor.Items, Cbor.StreamWriter, the Stream adapters) and entries.roc (Cbor.Entries, in an app of its
# own: in app.roc its code made `deep` trap on nightly 2026-10-19). Each one with its expected checksums.
status=0
for pair in "app expected" "entries expected_entries"; do
	set -- $pair
	sed "s|cbor: \"../../src/main.roc\"|cbor: \"${WASM_DEV_PKG:-../../src/main.roc}\"|" "tests/wasm_dev/$1.roc" >"$work/$1.roc"
	# Exit code 2: warnings only, the file is written.
	code=0
	"$ROC" build --opt="$opt" --target=wasm32 --wasm-stack-size="${WASM_DEV_STACK:-393216}" --no-cache \
		--output="$work/$1.wasm" "$work/$1.roc" >"$work/build_$1.log" 2>&1 || code=$?
	if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
		cat "$work/build_$1.log"
		exit 1
	fi
	node tests/wasm_dev/run.mjs "$work/$1.wasm" "tests/wasm_dev/$2.txt" || status=1
done
exit "$status"
