#!/usr/bin/env bash
# The speed benchmark: bench/bench.roc, built with --opt=speed. Three modes:
#
#   ROC=/path/to/roc scripts/bench.sh [runs]            0.4.1 (BENCH_REF) against HEAD, no thresholds
#   ROC=/path/to/roc scripts/bench.sh --check [runs]    HEAD against bench/baseline.txt; exit 1 on a slowdown
#   ROC=/path/to/roc scripts/bench.sh --update [runs]   measure HEAD and write bench/baseline.txt
#
# runs: the runs of each measurement (default 5); the median is used.
# BENCH_CASES: the cases to run (default: all). BENCH_MS: the target time of the timed work in one run
# (default 400). BENCH_REF: the old version of the compare mode (a git ref). BENCH_OLD_DIR: its worktree
# (removed at the end). BENCH_RATIO: the limit of --check (default 1.5).
#
# Timing: the echo host has no clock, so the shell times each run of the binary. A run with 0 loops is
# the base (start and input build). ms per loop = (median(loops) - median(0)) / loops. The loop count is
# set so that the timed work takes about BENCH_MS (--check uses the loop count of the baseline).
#
# The rule of --check: each time is divided by the time of `calib` (plain Roc work with no CBOR,
# measured at the start and at the end of the same run; the mean of the two). This removes most of the
# speed of the machine and its load. A case fails when
#     (ms / calib ms now) / (ms / calib ms in the baseline) > BENCH_RATIO (1.5).
# Why 1.5: on a busy machine the same build moves up to about 1.2x between runs (medians of 5), and the
# P25 work must not lose more than a third of the speed of any case without a decision. A complexity bug
# gives much more (see scripts/scale.sh). A case under 1 / BENCH_RATIO is reported as "faster": update
# the baseline after a speed gain, so that the gain is kept.
# The baseline is of one machine. On another machine (CI) calib removes the clock speed, not the
# differences of cache and memory, so CI runs --check as a report only.
#
# A normalized time under 0.005 counts as 0.005 (bytes_parse is a sublist: about 0.3 microseconds).
# How to read a failure: the row gives the case, the baseline and the new normalized time and the ratio.
# Run the case again alone (BENCH_CASES=name scripts/bench.sh --check 9) to rule out noise. If it stays,
# compare with the commit of the baseline (its first line) in the compare mode (BENCH_REF=<commit>).
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
root="$PWD"
mode=compare
case "${1:-}" in
--check) mode=check; shift ;;
--update) mode=update; shift ;;
esac
runs="${1:-5}"
ref="${BENCH_REF:-0.4.1}"
target_ms="${BENCH_MS:-400}"
limit="${BENCH_RATIO:-1.5}"
baseline="$root/bench/baseline.txt"
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$root/.cache/roc}"
# roc build stops with PathOutsideWorkspace when this path has `..` in it.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$root/.cache/xdg}"
work="$root/.cache/bench"
old="${BENCH_OLD_DIR:-$work/old}"
mkdir -p "$work"
all_cases="bytes_encode bytes_parse u8list_encode u8list_parse records_encode records_parse records_value camel_parse reject_parse unknown_parse unions_parse unions_content trees_parse deep_encode deep_parse dict_parse map_value path_map text_parse"
read -r -a cases <<<"${BENCH_CASES:-$all_cases}"

build() { # dir, output
	(cd "$1" && "$ROC" build --opt=speed bench/bench.roc --output="$2" >"$2.build.log" 2>&1) || {
		echo "build failed in $1"
		tail -n 30 "$2.build.log"
		exit 1
	}
}

# The median time in ns of `runs` runs of: binary case loops.
median_ns() {
	local bin="$1" case="$2" loops="$3" t0 t1 i
	local times=()
	for ((i = 0; i < runs; i++)); do
		t0=$(date +%s%N)
		"$bin" "$case" "$loops" >/dev/null
		t1=$(date +%s%N)
		times+=($((t1 - t0)))
	done
	printf '%s\n' "${times[@]}" | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'
}

# The loop count for about target_ms of timed work.
find_loops() {
	local bin="$1" case="$2" base="$3" loops=1 t t0
	while :; do
		t0=$(date +%s%N)
		"$bin" "$case" "$loops" >/dev/null
		t=$(($(date +%s%N) - t0 - base))
		if [ "$t" -ge $((target_ms * 250000)) ] || [ "$loops" -ge 1000000 ]; then
			[ "$t" -gt 0 ] || t=1
			awk -v l="$loops" -v t="$t" -v m="$target_ms" 'BEGIN { n = int(l * m * 1e6 / t); print (n < 1 ? 1 : n) }'
			return
		fi
		loops=$((loops * 4))
	done
}

# Prints "loops ms_per_loop". With a loop count as the 3rd argument, no search.
per_loop() {
	local bin="$1" case="$2" loops="${3:-}" base full
	base=$(median_ns "$bin" "$case" 0)
	[ -n "$loops" ] || loops=$(find_loops "$bin" "$case" "$base")
	full=$(median_ns "$bin" "$case" "$loops")
	awk -v b="$base" -v f="$full" -v n="$loops" 'BEGIN { printf "%d %.4f", n, (f - b) / n / 1e6 }'
}

head_desc() { echo "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- src bench || echo '+dirty')"; }

if [ "$mode" = compare ]; then
	cleanup() {
		if [ -d "$old" ]; then git -C "$root" worktree remove --force "$old" || true; fi
	}
	trap cleanup EXIT
	# The old version in its own worktree, with the bench app and the adapter of its API.
	cleanup
	git -C "$root" worktree add --detach "$old" "$ref" >/dev/null 2>&1
	mkdir -p "$old/bench"
	# 0.4.1: Cbor.Bytes is the byte string, a List(U8) writes an array (the u8list cases), there is
	# no `unknown_fields` option, and Value.Int holds an I128.
	awk '
		/# ADAPTER BEGIN/ { print; print "Blob : Cbor.Bytes\n\nto_blob : List(U8) -> Blob\nto_blob = |l| Cbor.Bytes.from_list(l)\n\nblob_len : Blob -> U64\nblob_len = |b| b.to_list().len()\n\nreject_options : Cbor.Options\nreject_options = {}\n\nvalue_int : U64 -> Cbor.Value\nvalue_int = |n| Cbor.Value.Int(n.to_i128())\n"; skip = 1; next }
		/# ADAPTER END/ { skip = 0 }
		!skip { print }
	' bench/bench.roc >"$old/bench/bench.roc"
	build "$old" "$work/old.bin"
	build "$root" "$work/head.bin"
	echo "runs=$runs old=$ref ($(git -C "$root" rev-parse --short "$ref")) head=$(head_desc)"
	printf '| %-14s | %9s | %10s | %9s | %10s | %8s |\n' case "old loops" "old ms" "loops" "HEAD ms" "HEAD/old"
	printf '| %-14s | %9s | %10s | %9s | %10s | %8s |\n' --- ---: ---: ---: ---: ---:
	for name in "${cases[@]}"; do
		read -r la a <<<"$(per_loop "$work/old.bin" "$name")"
		read -r lb b <<<"$(per_loop "$work/head.bin" "$name")"
		r=$(awk -v a="$a" -v b="$b" 'BEGIN { if (a > 0.0005) printf "%.2f", b / a; else print "-" }')
		printf '| %-14s | %9s | %10s | %9s | %10s | %8s |\n' "$name" "$la" "$a" "$lb" "$b" "$r"
	done
	exit 0
fi

# --check and --update: HEAD only.
build "$root" "$work/head.bin"
bin="$work/head.bin"
if [ "$mode" = check ] && [ ! -f "$baseline" ]; then
	echo "no $baseline: run scripts/bench.sh --update first"
	exit 2
fi
base_field() { # case, field number (2 loops, 3 ms, 4 norm). --update searches the loop counts again.
	if [ "$mode" = update ] && [ "$2" = 2 ]; then return; fi
	[ -f "$baseline" ] && awk -v c="$1" -v f="$2" '$1 == c { print $f }' "$baseline" || true
}
read -r cl1 c1 <<<"$(per_loop "$bin" calib "$(base_field calib 2)")"
results=()
for name in "${cases[@]}"; do
	results+=("$name $(per_loop "$bin" "$name" "$(base_field "$name" 2)")")
done
read -r _ c2 <<<"$(per_loop "$bin" calib "$cl1")"
calib_ms=$(awk -v a="$c1" -v b="$c2" 'BEGIN { printf "%.4f", (a + b) / 2 }')
drift=$(awk -v a="$c1" -v b="$c2" 'BEGIN { printf "%.2f", (a > b ? a / b : b / a) }')
echo "mode=$mode runs=$runs head=$(head_desc) calib ms: start $c1, end $c2 (drift ${drift}x)"

if [ "$mode" = update ]; then
	{
		echo "# bench/baseline.txt: written by scripts/bench.sh --update. Do not edit by hand."
		echo "# head=$(head_desc) date=$(date -u +%Y-%m-%d) machine=$(uname -m) cpus=$(nproc) runs=$runs"
		echo "# case loops ms_per_loop normalized (ms / calib ms)"
		echo "calib $cl1 $calib_ms 1.0000"
		for row in "${results[@]}"; do
			read -r name loops ms <<<"$row"
			awk -v n="$name" -v l="$loops" -v m="$ms" -v c="$calib_ms" 'BEGIN { printf "%s %d %.4f %.4f\n", n, l, m, m / c }'
		done
	} >"$baseline"
	cat "$baseline"
	exit 0
fi

echo "baseline: $(sed -n 2p "$baseline" | sed 's/^# //')"
printf '| %-14s | %10s | %10s | %10s | %6s | %-7s |\n' case "ms now" "norm base" "norm now" ratio verdict
printf '| %-14s | %10s | %10s | %10s | %6s | %-7s |\n' --- ---: ---: ---: ---: ---
fail=0
slow=()
for row in "${results[@]}"; do
	read -r name _ ms <<<"$row"
	b=$(base_field "$name" 4)
	if [ -z "$b" ]; then
		printf '| %-14s | %10s | %10s | %10s | %6s | %-7s |\n' "$name" "$ms" - - - "new"
		continue
	fi
	read -r now r v <<<"$(awk -v m="$ms" -v c="$calib_ms" -v b="$b" -v l="$limit" 'BEGIN {
		# A normalized time under 0.005 (a few microseconds) is noise: both sides count as 0.005.
		n = m / c; fn = (n < 0.005 ? 0.005 : n); fb = (b < 0.005 ? 0.005 : b); r = fn / fb
		v = (r > l ? "SLOWER" : (r < 1 / l ? "faster" : "ok"))
		printf "%.4f %.2f %s", n, r, v
	}')"
	printf '| %-14s | %10s | %10s | %10s | %6s | %-7s |\n' "$name" "$ms" "$b" "$now" "$r" "$v"
	if [ "$v" = SLOWER ]; then
		fail=1
		slow+=("$name")
	fi
done
echo "(norm: ms per loop / calib ms per loop; ratio: norm now / norm base; limit $limit)"
if [ "$fail" -ne 0 ]; then
	echo "FAIL: slower than the baseline by more than ${limit}x: ${slow[*]}"
	exit 1
fi
