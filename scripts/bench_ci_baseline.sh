#!/usr/bin/env bash
# Writes bench/baseline-ci.txt, the baseline of the CI bench job, from the bench logs of CI runs
# (the median of each case). Use 3 or more runs of the same code: one runner can be much slower
# than another (see scripts/bench.sh).
#
#   scripts/bench_ci_baseline.sh RUN_ID RUN_ID RUN_ID...
#
# RUN_ID: a run of the Tests workflow (`gh run list --workflow Tests`). Needs gh with read access.
# The loop counts are those that the runs used: those of bench/baseline-ci.txt, or of
# bench/baseline.txt when there is no CI baseline yet.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -ge 3 ] || {
	echo "usage: scripts/bench_ci_baseline.sh RUN_ID RUN_ID RUN_ID..." >&2
	exit 2
}
out=bench/baseline-ci.txt
loops_from=$out
[ -f "$loops_from" ] || loops_from=bench/baseline.txt
work=.cache/bench-ci
rm -rf "$work"
mkdir -p "$work"

heads=()
for run in "$@"; do
	job=$(gh run view "$run" --json jobs --jq '.jobs[] | select(.name == "bench") | .databaseId')
	[ -n "$job" ] || {
		echo "run $run has no bench job" >&2
		exit 1
	}
	gh api "repos/{owner}/{repo}/actions/jobs/$job/logs" | sed 's/^[^ ]* //' >"$work/$run.log"
	head=$(sed -n 's/^mode=check .*head=\([^ ]*\) .*/\1/p' "$work/$run.log")
	[ -n "$head" ] || {
		echo "run $run: no bench result in the log" >&2
		exit 1
	}
	case "$head" in *+dirty) echo "run $run measured a dirty tree" >&2 && exit 1 ;; esac
	heads+=("$head")
	# calib: the mean of the start and the end. Cases: "case ms norm" from the table.
	sed -n 's/^mode=check .*calib ms: start \([0-9.]*\), end \([0-9.]*\).*/calib \1 \2/p' "$work/$run.log" |
		awk '{ printf "calib %.4f 1.0000\n", ($2 + $3) / 2 }' >"$work/$run.rows"
	awk -F'|' '/^\| [a-z0-9_]+ +\| +[0-9]/ { gsub(/ /, ""); print $2, $3, $5 }' "$work/$run.log" >>"$work/$run.rows"
done
for h in "${heads[@]}"; do
	# A change of comments only is the same code; the script cannot tell, so it only warns.
	git diff --quiet "${heads[0]}" "$h" -- src bench/bench.roc ||
		echo "warning: ${heads[0]} and $h differ in src or bench/bench.roc; use runs of the same code" >&2
done

{
	echo "# baseline-ci.txt: written by scripts/bench_ci_baseline.sh from CI runs. Do not edit by hand."
	echo "# head=${heads[*]} date=$(date -u +%Y-%m-%d) machine=ubuntu-24.04 (GitHub runner) runs=$* (median)"
	echo "# case loops ms_per_loop normalized (ms / calib ms)"
	cat "$work"/*.rows | awk -v lf="$loops_from" '
		BEGIN { while ((getline l < lf) > 0) { split(l, f, " "); if (l !~ /^#/) loops[f[1]] = f[2] } }
		{ n[$1]++; ms[$1, n[$1]] = $2; nm[$1, n[$1]] = $3; if (!($1 in seen)) { seen[$1] = 1; order[++k] = $1 } }
		function med(a, c, m,   i, j, t, x) {
			for (i = 1; i <= m; i++) x[i] = a[c, i]
			for (i = 2; i <= m; i++) for (j = i; j > 1 && x[j - 1] > x[j]; j--) { t = x[j]; x[j] = x[j - 1]; x[j - 1] = t }
			return (m % 2 ? x[(m + 1) / 2] : (x[m / 2] + x[m / 2 + 1]) / 2)
		}
		END {
			for (i = 1; i <= k; i++) {
				c = order[i]
				if (!(c in loops)) { print "no loop count for " c " in " lf > "/dev/stderr"; exit 1 }
				printf "%s %d %.4f %.4f\n", c, loops[c], med(ms, c, n[c]), med(nm, c, n[c])
			}
		}'
} >"$work/baseline"
mv "$work/baseline" "$out"
cat "$out"
