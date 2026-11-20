"""bench/compare: a diagnostic for roc-cbor, with CBOR libraries of Rust, Go, Python and Zig as reference points.

It is a tool to find slow paths and compiler issues, not a claim: its results are not committed.

Usage: ROC=/path/to/roc python3 bench/compare/run.py [--refresh] [--only IMPL ...] [--cases CASE ...]
       [--runs N] [--ms MS] [--no-build]

Each implementation is a program `<impl> <case> <loops>` that prints "case loops checksum". The input of
each case is a fixture written by the Roc bench (bench/bench.roc `dump`), so each side reads the same
bytes. The runner times each program from the outside, the same way for each language (scripts/bench.sh
does the same for Roc alone):

    ms per op   = (median wall time of runs with N loops - median of runs with 0 loops) / N
    cpu per op  = the same with user + sys CPU time (more than ms per op when a GC runs on other threads)
    MB/s        = fixture bytes / ms per op (decimal MB: 1e6 bytes)
    base RSS    = peak RSS of a run with 0 loops (runtime + the fixture + the setup of the case)
    op RSS      = peak RSS of a run with 1 loop - base RSS (the memory of one op at its peak)
    peak RSS N  = peak RSS of the run with N loops (growth over op RSS: a GC heap or a leak)

The results of the other languages are cached in .cache/compare/results/<impl>.json (not committed), since
they do not change with roc-cbor. A cached result is used when its key matches: the hash of the fixtures, of the
source and lock files of the implementation, and the CPU model. --refresh measures them again. Roc is
measured on each run; its result goes to .cache/compare/roc.json. The report (Markdown) is printed and
written to .cache/compare/report.md.
"""

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "bench", "compare")
WORK = os.path.join(ROOT, ".cache", "compare")
FIX = os.path.join(WORK, "fixtures")
RESULTS = os.path.join(WORK, "results")
ROC = os.environ.get("ROC", "roc")

# case: (fixture, kind, expected checksum of one loop: None for an encode case, its output length)
CASES = {
    "bytes_encode": ("bytes", "encode", None),
    "bytes_parse": ("bytes", "typed", 1_000_000),
    "records_encode": ("records", "encode", None),
    "records_parse": ("records", "typed", 10_000),
    "records_value": ("records", "value", 1),
    "unknown_parse": ("wide", "typed", 10_000),
    "dict_parse": ("dict", "typed", 100_000),
    "map_value": ("dict", "value", 1),
    "text_parse": ("texts", "typed", 10_000),
    "deep_encode": ("deep", "encode", None),
    "deep_parse": ("deep", "value", 1),
}
FIXTURES = sorted({f for f, _, _ in CASES.values()})

CASE_DOC = {
    "bytes_encode": "a 1 MB byte string",
    "bytes_parse": "a 1 MB byte string",
    "records_encode": "10k records {id, name, ok, score, tags}",
    "records_parse": "10k records into a typed list",
    "records_value": "10k records into a dynamic value",
    "unknown_parse": "10k records with 12 unknown fields each (skipped)",
    "dict_parse": "a map of 100k text keys into a hash map",
    "map_value": "a map of 100k text keys into a dynamic value",
    "text_parse": "10k multi-byte UTF-8 texts",
    "deep_encode": "500 nested arrays (dynamic value)",
    "deep_parse": "500 nested arrays (dynamic value)",
}


def sh(cmd, cwd=ROOT, env=None, quiet=True):
    e = dict(os.environ)
    e.update(env or {})
    r = subprocess.run(cmd, cwd=cwd, env=e, capture_output=quiet, text=True)
    if r.returncode != 0:
        if quiet:
            sys.stderr.write(r.stdout[-4000:] + r.stderr[-4000:])
        raise SystemExit(f"failed: {' '.join(cmd)}")
    return r.stdout if quiet else ""


def cpu_model():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or platform.machine()


def first_line(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True).stdout.strip().splitlines()[0]
    except (OSError, IndexError):
        return "?"


# The implementations ---------------------------------------------------------------------------

ROC_ENV = {
    "ROC_CACHE_DIR": os.environ.get("ROC_CACHE_DIR", os.path.join(ROOT, ".cache", "roc")),
    # roc build stops with PathOutsideWorkspace when this path has `..` in it.
    "XDG_CACHE_HOME": os.environ.get("XDG_CACHE_HOME", os.path.join(ROOT, ".cache", "xdg")),
}
PYLIB = os.path.join(WORK, "pylib")
ZIG_ENV = {"ZIG_GLOBAL_CACHE_DIR": os.path.join(WORK, "zig-global")}


def lock_version(path, name, pattern):
    try:
        with open(path) as f:
            m = re.search(pattern.format(re.escape(name)), f.read())
        return m.group(1) if m else "?"
    except OSError:
        return "?"


class Impl:
    def __init__(self, name, lang, lib, sources, build, argv, version, toolchain, env=None):
        self.name, self.lang, self.lib = name, lang, lib
        self.sources, self.build, self.argv = sources, build, argv
        self.version, self.toolchain, self.env = version, toolchain, env or {}

    def key(self, fixtures_sha, cpu):
        h = hashlib.sha256()
        for s in self.sources:
            with open(os.path.join(HERE, s), "rb") as f:
                h.update(s.encode() + b"\0" + f.read())
        h.update(fixtures_sha.encode() + cpu.encode())
        return h.hexdigest()[:16]


def build_rust():
    sh(["cargo", "build", "--release", "--quiet"], cwd=os.path.join(HERE, "rust"),
       env={"CARGO_TARGET_DIR": os.path.join(WORK, "rust-target")})


def build_go():
    sh(["go", "build", "-o", os.path.join(WORK, "go-bench"), "."], cwd=os.path.join(HERE, "go"))


def build_python():
    if not os.path.isdir(os.path.join(PYLIB, "cbor2")):
        sh([sys.executable, "-m", "pip", "install", "--quiet", "--target", PYLIB,
            "-r", os.path.join(HERE, "python", "requirements.txt")])


def build_zig():
    sh(["zig", "build", "--prefix", os.path.join(WORK, "zig-out"), "--cache-dir", os.path.join(WORK, "zig-cache")],
       cwd=os.path.join(HERE, "zig"), env=ZIG_ENV)


def build_roc_dump():
    """bench/bench.roc: its `dump` mode writes the fixtures."""
    sh([ROC, "build", "--opt=speed", "bench/bench.roc", f"--output={os.path.join(WORK, 'roc-dump.bin')}"], env=ROC_ENV)


def build_roc():
    """bench/compare/roc/compare.roc: the cases, with the fixtures embedded (build after write_fixtures)."""
    sh([ROC, "build", "--opt=speed", "bench/compare/roc/compare.roc", f"--output={os.path.join(WORK, 'roc-compare.bin')}"],
       env=ROC_ENV)


RUST_BIN = os.path.join(WORK, "rust-target", "release", "cbor-bench")
CARGO_LOCK = os.path.join(HERE, "rust", "Cargo.lock")
CARGO_V = r'name = "{}"\nversion = "([^"]+)"'

IMPLS = [
    Impl("roc", "Roc", "roc-cbor", [], build_roc,
         lambda c, n: [os.path.join(WORK, "roc-compare.bin"), c, str(n)],
         lambda: first_line(["git", "-C", ROOT, "describe", "--tags", "--always", "--dirty"]),
         lambda: first_line([ROC, "version"])),
    Impl("rust-ciborium", "Rust", "ciborium", ["rust/src/main.rs", "rust/Cargo.lock"], build_rust,
         lambda c, n: [RUST_BIN, "ciborium", c, str(n), FIX],
         lambda: lock_version(CARGO_LOCK, "ciborium", CARGO_V), lambda: first_line(["rustc", "--version"])),
    Impl("rust-cbor4ii", "Rust", "cbor4ii", ["rust/src/main.rs", "rust/Cargo.lock"], build_rust,
         lambda c, n: [RUST_BIN, "cbor4ii", c, str(n), FIX],
         lambda: lock_version(CARGO_LOCK, "cbor4ii", CARGO_V), lambda: first_line(["rustc", "--version"])),
    Impl("go-fxamacker", "Go", "fxamacker/cbor", ["go/main.go", "go/go.sum"], build_go,
         lambda c, n: [os.path.join(WORK, "go-bench"), c, str(n), FIX],
         lambda: lock_version(os.path.join(HERE, "go", "go.mod"), "github.com/fxamacker/cbor/v2", r"{} (\S+)"),
         lambda: first_line(["go", "version"])),
    Impl("python-cbor2", "Python", "cbor2", ["python/bench.py", "python/requirements.txt"], build_python,
         lambda c, n: [sys.executable, "-s", os.path.join(HERE, "python", "bench.py"), c, str(n), FIX],
         lambda: lock_version(os.path.join(HERE, "python", "requirements.txt"), "cbor2", r"{}==(\S+)"),
         lambda: "Python " + platform.python_version(), env={"PYTHONPATH": PYLIB}),
    Impl("zig-zbor", "Zig", "zbor", ["zig/main.zig", "zig/build.zig", "zig/build.zig.zon"], build_zig,
         lambda c, n: [os.path.join(WORK, "zig-out", "bin", "cbor-bench"), c, str(n), FIX],
         lambda: lock_version(os.path.join(HERE, "zig", "build.zig.zon"), "zbor", r"zbor/archive/refs/tags/([^/]+)\.tar"),
         lambda: "Zig " + first_line(["zig", "version"]), env=ZIG_ENV),
]


# Measurement -----------------------------------------------------------------------------------

class Unsupported(Exception):
    pass


RUSAGE = os.path.join(WORK, "rusage")


def build_rusage():
    src = os.path.join(HERE, "rusage.c")
    if not os.path.exists(RUSAGE) or os.path.getmtime(RUSAGE) < os.path.getmtime(src):
        sh([os.environ.get("CC", "cc"), "-O2", "-o", RUSAGE, src])


def run_once(impl, case, loops):
    """One run through bench/compare/rusage.c: (wall ns, cpu ns, max RSS KiB, checksum)."""
    env = dict(os.environ)
    env.update(impl.env)
    p = subprocess.run([RUSAGE] + impl.argv(case, loops), capture_output=True, env=env, cwd=ROOT)
    err = p.stderr.decode()
    m = re.search(r"rusage wall_ns=(\d+) cpu_ns=(\d+) maxrss_kib=(\d+) status=(\d+)\s*$", err)
    if not m:
        raise RuntimeError(f"{impl.name} {case} {loops}: no rusage line: {err[-500:]}")
    wall, cpu, rss, code = map(int, m.groups())
    if code == 3:
        raise Unsupported(err[: m.start()].strip())
    if code != 0:
        raise RuntimeError(f"{impl.name} {case} {loops}: exit {code}: {err[-500:]}")
    return wall, cpu, rss, int(p.stdout.decode().split()[2])


def medians(impl, case, loops, runs):
    rs = [run_once(impl, case, loops) for _ in range(runs)]
    return (statistics.median(r[0] for r in rs), statistics.median(r[1] for r in rs),
            statistics.median(r[2] for r in rs), rs[0][3])


def find_loops(impl, case, base_ns, target_ms):
    loops = 1
    while True:
        wall, _, _, _ = run_once(impl, case, loops)
        t = wall - base_ns
        if t >= target_ms * 250_000 or loops >= 1_000_000:
            return max(1, int(loops * target_ms * 1e6 / max(t, 1)))
        loops *= 4


def measure_case(impl, case, runs, target_ms):
    fixture, kind, expected = CASES[case]
    try:
        _, _, rss1, check = medians(impl, case, 1, 3)
    except Unsupported as e:
        return {"status": "n/a", "note": str(e)}
    if expected is not None and check != expected:
        return {"status": "wrong", "note": f"checksum {check}, expected {expected}"}
    wall0, cpu0, rss0, _ = medians(impl, case, 0, runs)
    loops = find_loops(impl, case, wall0, target_ms)
    walln, cpun, rssn, _ = medians(impl, case, loops, runs)
    ms = max(walln - wall0, 0) / loops / 1e6
    cpu_ms = max(cpun - cpu0, 0) / loops / 1e6
    size = os.path.getsize(os.path.join(FIX, fixture + ".cbor"))
    return {
        "status": "ok",
        "loops": loops,
        "ms_per_op": round(ms, 5),
        "cpu_ms_per_op": round(cpu_ms, 5),
        "mb_per_s": round(size / (ms * 1e3), 1) if ms > 0 else None,
        "base_rss_kib": rss0,
        "op_rss_kib": max(rss1 - rss0, 0),
        "peak_rss_kib": rssn,
        "start_ms": round(wall0 / 1e6, 2),
        "out_bytes": check if expected is None else None,
    }


def measure(impl, cases, runs, target_ms, key):
    print(f"measure {impl.name} ...", file=sys.stderr, flush=True)
    res = {}
    for c in cases:
        res[c] = measure_case(impl, c, runs, target_ms)
        r = res[c]
        info = f"{r['ms_per_op']:.3f} ms" if r["status"] == "ok" else r["status"]
        print(f"  {c:<15} {info}", file=sys.stderr, flush=True)
    return {
        "impl": impl.name, "lang": impl.lang, "lib": impl.lib, "version": impl.version(),
        "toolchain": impl.toolchain(), "key": key, "cpu": cpu_model(), "date": time.strftime("%Y-%m-%d"),
        "runs": runs, "target_ms": target_ms, "cases": res,
    }


# Fixtures --------------------------------------------------------------------------------------

def write_fixtures():
    os.makedirs(FIX, exist_ok=True)
    for name in FIXTURES:
        hexs = subprocess.run([os.path.join(WORK, "roc-dump.bin"), "dump", name], capture_output=True, text=True,
                              check=True).stdout.strip()
        data = bytes.fromhex(hexs)
        with open(os.path.join(FIX, name + ".cbor"), "wb") as f:
            f.write(data)
    return fixtures_hash()


def fixtures_hash():
    h = hashlib.sha256()
    for name in FIXTURES:
        with open(os.path.join(FIX, name + ".cbor"), "rb") as f:
            h.update(name.encode() + b"\0" + hashlib.sha256(f.read()).digest())
    return h.hexdigest()[:16]


# The report ------------------------------------------------------------------------------------

def fmt(v, spec):
    return "-" if v is None else format(v, spec)


def report(results, cases):
    order = [r for r in results]
    roc = next((r for r in order if r["impl"] == "roc"), None)
    lines = []
    lines.append("# roc-cbor against other CBOR libraries\n")
    lines.append(f"CPU: {cpu_model()}. Runs: medians of {order[0]['runs']} runs of about {order[0]['target_ms']} ms.\n")
    lines.append("| Impl | Library | Version | Toolchain | Measured | Cache key |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for r in order:
        lines.append(f"| {r['impl']} | {r['lib']} | {r['version']} | {r['toolchain']} | {r['date']} | {r['key']} |")
    lines.append("")

    def table(title, field, spec, unit, better):
        lines.append(f"## {title}\n")
        lines.append(f"{unit}. {better}. The ratio column is roc / the best of the others.\n")
        lines.append("| Case | " + " | ".join(r["impl"] for r in order) + " | roc / best other |")
        lines.append("| --- | " + " | ".join("---:" for _ in order) + " | ---: |")
        for c in cases:
            row, others = [], []
            for r in order:
                x = r["cases"].get(c, {})
                if x.get("status") != "ok":
                    row.append(x.get("status", "-"))
                    continue
                v = field(x)
                row.append(fmt(v, spec))
                if r["impl"] != "roc" and v is not None:
                    others.append(v)
            ratio = "-"
            rv = roc and roc["cases"].get(c, {})
            if rv and rv.get("status") == "ok" and others and field(rv) is not None:
                best = max(others) if better.lower().startswith("higher") else min(others)
                ratio = f"{field(rv) / best:.2f}" if best else "-"
            lines.append(f"| {c} | " + " | ".join(row) + f" | {ratio} |")
        lines.append("")

    table("Time per op", lambda x: x["ms_per_op"], ".3f", "ms per op (wall)", "Lower is better")
    table("Throughput", lambda x: x["mb_per_s"], ".0f", "MB/s of the CBOR fixture (1 MB = 1e6 bytes)",
          "Higher is better")
    table("CPU per op", lambda x: x["cpu_ms_per_op"], ".3f",
          "ms of user + sys CPU per op (above wall time: work on other threads, such as a GC)", "Lower is better")
    table("Memory of one op", lambda x: x["op_rss_kib"] / 1024, ".1f",
          "MiB: peak RSS of 1 loop - peak RSS of 0 loops", "Lower is better")
    table("Peak RSS after N loops", lambda x: x["peak_rss_kib"] / 1024, ".1f",
          "MiB: peak RSS of the timed run (runtime + input + the heap after N ops)", "Lower is better")
    table("Base RSS", lambda x: x["base_rss_kib"] / 1024, ".1f",
          "MiB: peak RSS with 0 loops (runtime + fixture + setup)", "Lower is better")
    table("Start", lambda x: x["start_ms"], ".1f", "ms: wall time of a run with 0 loops", "Lower is better")
    lines.append("## Output size of the encode cases\n")
    lines.append("| Case | " + " | ".join(r["impl"] for r in order) + " |")
    lines.append("| --- | " + " | ".join("---:" for _ in order) + " |")
    for c in cases:
        if CASES[c][1] != "encode":
            continue
        lines.append(f"| {c} | " + " | ".join(
            str(r["cases"].get(c, {}).get("out_bytes") or r["cases"].get(c, {}).get("status", "-")) for r in order) + " |")
    lines.append("")
    lines.append("## Cases\n")
    lines.append("| Case | Input | Fixture bytes |")
    lines.append("| --- | --- | ---: |")
    for c in cases:
        lines.append(f"| {c} | {CASE_DOC[c]} | {os.path.getsize(os.path.join(FIX, CASES[c][0] + '.cbor'))} |")
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--refresh", action="store_true", help="measure the other languages again (ignore the cache)")
    ap.add_argument("--only", nargs="*", help="implementations to run (default: all)")
    ap.add_argument("--cases", nargs="*", default=list(CASES), help="cases (default: all)")
    ap.add_argument("--runs", type=int, default=int(os.environ.get("COMPARE_RUNS", 5)))
    ap.add_argument("--ms", type=int, default=int(os.environ.get("COMPARE_MS", 300)), help="target ms of a timed run")
    ap.add_argument("--no-build", action="store_true", help="use the Roc binary of the last run")
    a = ap.parse_args()
    for c in a.cases:
        if c not in CASES:
            raise SystemExit(f"unknown case: {c}")
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(RESULTS, exist_ok=True)
    impls = [i for i in IMPLS if not a.only or i.name in a.only]

    build_rusage()
    roc_bin = os.path.join(WORK, "roc-compare.bin")
    if a.no_build and os.path.exists(roc_bin):
        fixtures_sha = fixtures_hash()
    else:
        print("build roc (fixtures, then the cases) ...", file=sys.stderr, flush=True)
        build_roc_dump()
        fixtures_sha = write_fixtures()
        build_roc()
    cpu = cpu_model()

    results = []
    for impl in impls:
        if impl.name == "roc":
            key = fixtures_sha
            r = measure(impl, a.cases, a.runs, a.ms, key)
            with open(os.path.join(WORK, "roc.json"), "w") as f:
                json.dump(r, f, indent=1)
            results.append(r)
            continue
        key = impl.key(fixtures_sha, cpu)
        path = os.path.join(RESULTS, impl.name + ".json")
        cached = None
        if os.path.exists(path) and not a.refresh:
            with open(path) as f:
                cached = json.load(f)
            if cached.get("key") != key or any(c not in cached["cases"] for c in a.cases):
                why = "key" if cached.get("key") != key else "cases"
                print(f"{impl.name}: cache is stale ({why}), measure again", file=sys.stderr)
                cached = None
        if cached:
            print(f"{impl.name}: cached ({cached['date']}, key {key})", file=sys.stderr)
            results.append(cached)
            continue
        print(f"build {impl.name} ...", file=sys.stderr, flush=True)
        impl.build()
        r = measure(impl, list(CASES), a.runs, a.ms, key)
        with open(path, "w") as f:
            json.dump(r, f, indent=1, sort_keys=True)
            f.write("\n")
        results.append(r)

    text = report(results, a.cases)
    with open(os.path.join(WORK, "report.md"), "w") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main()
