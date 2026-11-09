#!/usr/bin/env bash
# The scaling test of the writer (bench/scale.roc), the reader (bench/scale_read.roc) and the Stream adapters
# (bench/scale_stream.roc).
#
# Usage: ROC=/path/to/roc scripts/scale.sh [runs]
#   runs          the runs of each measurement (default 3). The table gives the median.
#   SCALE_CASES   the cases to run (default: all cases of the three files).
#   SCALE_SIZES   the item counts (default "5000 10000 20000 40000"). The first is the reference.
#   SCALE_ITEMS   the items of one measurement (default 400000): loops = SCALE_ITEMS / size.
#   SCALE_PKG     the package main.roc, relative to .cache/scale (default ../../src/main.roc).
#   SCALE_BIG=1   adds stream_5gb (a few seconds): SCALE_BIG_BYTES (default 5000000000) bytes through the stream adapters.
#   SCALE_MEMORY_SIZES  the item counts of stream_memory (default "250000 1000000").
#   SCALE_VMEM    the virtual memory limit in KiB (ulimit -v) of each run of a memory case (default 524288), so a
#                 memory bug fails fast.
#
# Test of the test (done for P25a): with a copy of src/ where the duplicate-key check compares each key
# with each earlier key, SCALE_PKG=../quad/src/main.roc makes the dup_* cases FAIL. On 0.4.1 the
# union_* cases FAIL.
#
# What it does: each case is built as its own app (--opt=speed), with only its arm of `run`. The copy of
# an output list came and went with the shape of the whole app, so one app for all cases can hide it.
# For each size, time for each item = (median time with loops - median time with 0 loops) / loops / size.
#
# The rule: ratio = (time for each item at a size) / (time for each item at the first size).
#   Linear cases:   FAIL when ratio > 2.5. Linear gives about 1, quadratic gives 8 at 40k.
#   Sort cases (NLOGN_CASES, they sort the keys of one map): the ratio is divided by
#   log2(size) / log2(first size) first, then the same 2.5 limit. n log n gives about 1,
#   quadratic gives 8 / 1.24 = 6.4 at 40k.
#   Depth cases (depth_cases): the size is the depth of one item, SCALE_DEPTH_SIZES (default
#   "30 60 120 240" levels), with the linear rule.
#   Times under SCALE_FLOOR ns for each item (default 50) count as SCALE_FLOOR, so a case that is almost
#   free (a Cbor.Bytes sublist) does not fail on noise. A quadratic case still goes far above the floor.
# After a FAIL the larger sizes of that case are skipped ("-").
#
# Memory cases (memory_cases, bench/scale_stream.roc): not timed. Each one runs one time for each size under
# /usr/bin/time, and the table gives the maximum RSS in KiB. The printed sum must be the size (each item or byte checked).
#   stream_memory: n items of 100 bytes at SCALE_MEMORY_SIZES. FAIL when the RSS at the last size is more than
#     SCALE_MEMORY_GROWTH KiB (default 8192) over the RSS at the first size, or more than 65536 KiB.
#   stream_5gb (SCALE_BIG=1): a byte string of n / 8 and n bytes. FAIL when the RSS is more than 65536 KiB, or the time
#     for each byte at n is more than 2.5 times the time at n / 8.
# Test of the test: SCALE_PKG pointed to a copy of src/ where the decoder keeps all of its input makes both FAIL.
#
# Tests of the stream tests (step 9): a walk of the open item from its start at each chunk (walk_item ignores its
# Open state) makes stream_big_item FAIL at 20k; a KeySet lookup that scans each key makes stream_keys_dup FAIL at 20k.
#
# How to read a failure: the case name tells the shape (see the comment of its arm in the .roc file).
# A ratio that grows with the size (2, 4, 8) is a complexity bug: a list copied at each append, a
# scan from the start for each item, a hash flood. Run the case again alone (SCALE_CASES=name) to
# rule out a busy machine: noise moves one size, a real bug moves each larger size more.
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
root="$PWD"
runs="${1:-3}"
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$root/.cache/roc}"
# roc build stops with PathOutsideWorkspace when this path has `..` in it.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$root/.cache/xdg}"
work="$root/.cache/scale"
mkdir -p "$work"
writer_cases="u64 records lists tuples tags nested absent u8lists bytes tagged fallback value dict_encode sorted_records sorted_map stream_array stream_sorted"
reader_cases="rec rec_camel rec_reject rec_unknown val_list val_map val_deep val_deep_wide path_array path_map union_tag union_content union_nested union_nested_content union_depth dup_record dup_value dup_prefix sorted_keys dup_first dup_last text_list text_one bytes_one u8list_one b64_bytes b64_list dict stream_items stream_entries stream_keys stream_keys_dup stream_big_item stream_trap_reset stream_trap_return stream_bytes stream_text"
# The adapters to the builtin Stream (bench/scale_stream.roc: an effectful `run!`).
adapter_cases="stream_adapter stream_adapter_items stream_adapter_write"
# The memory cases (bench/scale_stream.roc), after the timed cases.
memory_cases=" stream_memory stream_5gb "
big_cases=""
if [ "${SCALE_BIG:-0}" = 1 ]; then big_cases="stream_5gb"; fi
nlogn_cases=" sorted_map val_map dup_record dup_value dup_prefix dup_first dup_last dict stream_keys stream_keys_dup "
# The cases where the size is a depth: the depth limit (512) keeps them small.
depth_cases=" union_depth "
read -r -a depth_sizes <<<"${SCALE_DEPTH_SIZES:-30 60 120 240}"
read -r -a cases <<<"${SCALE_CASES:-$writer_cases $reader_cases $adapter_cases stream_memory $big_cases}"
read -r -a sizes <<<"${SCALE_SIZES:-5000 10000 20000 40000}"
items="${SCALE_ITEMS:-400000}"
# The package of the apps, relative to .cache/scale. A test of the test can point it to a changed copy of src/.
pkg="${SCALE_PKG:-../../src/main.roc}"

# The app of one case: the .roc file that has its arm, with the other arms of `run` removed.
build() {
	local src=bench/scale.roc app="$work/scale_$1.roc"
	if ! grep -q "^		\"$1\" => {$" "$src"; then src=bench/scale_read.roc; fi
	if ! grep -q "^		\"$1\" => {$" "$src"; then src=bench/scale_stream.roc; fi
	if ! grep -q "^		\"$1\" => {$" "$src"; then
		echo "unknown case: $1"
		exit 2
	fi
	awk -v keep="$1" '
		/^\t\t"[a-z0-9_]+" => \{$/ { name = $1; gsub(/"/, "", name); skip = (name != keep) }
		skip && /^\t\t\}$/ { skip = 0; next }
		!skip { print }
	' "$src" | sed "s|\"../src/main.roc\"|\"$pkg\"|" >"$app"
	"$ROC" build --opt=speed "$app" --output="$work/scale_$1.bin" >"$work/scale_$1.log" 2>&1 || {
		tail -n 30 "$work/scale_$1.log"
		exit 1
	}
}

# The median time in ns of `runs` runs of: bin case loops items.
median_ns() {
	local t0 t1 i
	local times=()
	for ((i = 0; i < runs; i++)); do
		t0=$(date +%s%N)
		"$work/scale_$1.bin" "$1" "$2" "$3" >/dev/null
		t1=$(date +%s%N)
		times+=($((t1 - t0)))
	done
	printf '%s\n' "${times[@]}" | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'
}

# The time in ns for each item: about `items` items in all, less the run with 0 loops.
per_item() {
	local loops=$((items / $2)) base full
	[ "$loops" -ge 1 ] || loops=1
	base=$(median_ns "$1" 0 "$2")
	full=$(median_ns "$1" "$loops" "$2")
	awk -v b="$base" -v f="$full" -v l="$loops" -v n="$2" 'BEGIN { printf "%.1f", (f - b) / l / n }'
}

# The ratio of the time for each item at size n to the first size, or FAIL.
ratio() { # case, t_first, t_n, first size, n
	local nlogn=0
	case "$nlogn_cases" in *" $1 "*) nlogn=1 ;; esac
	awk -v a="$2" -v b="$3" -v s0="$4" -v s="$5" -v nlogn="$nlogn" -v floor="${SCALE_FLOOR:-50}" 'BEGIN {
		if (a < floor) a = floor
		if (b < floor) b = floor
		r = b / a
		if (nlogn) r = r / (log(s) / log(s0))
		if (r > 2.5) print "FAIL"; else printf "%.2f", r
	}'
}

# One run of: bin case 1 n, as "max RSS in KiB, time in ns", or "FAIL 0" when it fails or the sum is not n.
rss_run() {
	local out t0 t1
	t0=$(date +%s%N)
	out=$( (ulimit -v "${SCALE_VMEM:-524288}"; /usr/bin/time -f %M -o "$work/scale_$1.rss" "$work/scale_$1.bin" "$1" 1 "$2") 2>&1) || {
		echo "$1 at $2: the run failed: $out" >&2
		echo "FAIL 0"
		return
	}
	t1=$(date +%s%N)
	if [ "$out" != "$1 1 $2 $2" ]; then
		echo "$1 at $2: the sum is not $2: $out" >&2
		echo "FAIL 0"
		return
	fi
	echo "$(tail -n 1 "$work/scale_$1.rss") $((t1 - t0))"
}

# The row of one memory case: the max RSS and time at each size, and the check.
memory_case() {
	local msizes r rss ns first_rss="" first_ns="" first_n="" verdict="ok" row=()
	if [ "$1" = stream_5gb ]; then
		local big="${SCALE_BIG_BYTES:-5000000000}"
		msizes=("$((big / 8))" "$big")
	else
		read -r -a msizes <<<"${SCALE_MEMORY_SIZES:-250000 1000000}"
	fi
	for n in "${msizes[@]}"; do
		r=$(rss_run "$1" "$n")
		read -r rss ns <<<"$r"
		if [ "$rss" = FAIL ]; then
			row+=("$n: FAIL")
			verdict=FAIL
			break
		fi
		row+=("$n: $rss KiB, $((ns / 1000000)) ms")
		if [ -z "$first_rss" ]; then
			first_rss=$rss first_ns=$ns first_n=$n
		fi
		if [ "$rss" -gt 65536 ]; then verdict=FAIL; fi
		if [ "$1" = stream_memory ] && [ $((rss - first_rss)) -gt "${SCALE_MEMORY_GROWTH:-8192}" ]; then verdict=FAIL; fi
		if [ "$1" = stream_5gb ] && [ "$n" != "$first_n" ]; then
			verdict=$(awk -v a="$first_ns" -v b="$ns" -v s0="$first_n" -v s="$n" -v v="$verdict" 'BEGIN {
				r = (b / s) / (a / s0)
				if (r > 2.5 || v == "FAIL") print "FAIL"; else printf "ok, time ratio %.2f", r
			}')
		fi
	done
	printf '| %-15s | %s | %s |\n' "$1" "$(IFS=';'; echo "${row[*]}")" "$verdict"
	[ "$verdict" != FAIL ]
}

head_row() { printf '| %-15s |' case; for n in "${sizes[@]}"; do printf ' %8s |' "ns $((n / 1000))k"; done; printf ' %7s | %5s |\n' ratio rule; }
printf '%s\n' "$(head_row)"
printf '| %-15s |' ---; for _ in "${sizes[@]}"; do printf ' %8s |' ---:; done; printf ' %7s | %5s |\n' ---: ---
fail=0
failed=()
mem_run=()
for name in "${cases[@]}"; do
	case "$memory_cases" in *" $name "*)
		mem_run+=("$name")
		continue
		;;
	esac
	build "$name"
	rule=n
	case "$nlogn_cases" in *" $name "*) rule="nlogn" ;; esac
	case_sizes=("${sizes[@]}")
	case "$depth_cases" in *" $name "*) case_sizes=("${depth_sizes[@]}") rule="depth" ;; esac
	t=()
	r="-"
	for n in "${case_sizes[@]}"; do
		if [ "$r" = "FAIL" ]; then
			t+=("-")
			continue
		fi
		t+=("$(per_item "$name" "$n")")
		r=$(ratio "$name" "${t[0]}" "${t[${#t[@]} - 1]}" "${case_sizes[0]}" "$n")
	done
	printf '| %-15s |' "$name"
	printf ' %8s |' "${t[@]}"
	printf ' %7s | %5s |\n' "$r" "$rule"
	if [ "$r" = "FAIL" ]; then
		fail=1
		failed+=("$name")
	fi
done
echo "(ns for each item; ratio: last size against the first, divided by the log factor for nlogn;"
echo " depth: the sizes are ${depth_sizes[*]} levels of one item)"
if [ "${#mem_run[@]}" -gt 0 ]; then
	echo
	echo "| memory case     | size: max RSS, time | check |"
	echo "| --- | --- | --- |"
	for name in "${mem_run[@]}"; do
		build "$name"
		if ! memory_case "$name"; then
			fail=1
			failed+=("$name")
		fi
	done
fi
if [ "$fail" -ne 0 ]; then
	echo "FAIL: not linear (or not n log n), or memory grows: ${failed[*]}"
	exit 1
fi
