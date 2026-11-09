"""P24: a differential test of roc-cbor (Cbor.Value) against Python cbor2.

Usage: python -I differential.py --roc-bin BIN [--corpus DIR ...] [--rfc FILE] [--count N] [--seed S]

For each input, both sides say: valid or not, and the value as a canonical dump (see value_dump.roc).
cbor2 runs with no semantic decoders, so each tag stays a tag (CBORTag), the same as Cbor.Value.

Expected differences. Each one has a check of the input, so that it does not hide another difference:

| Class | Roc | cbor2 | Reason |
| --- | --- | --- | --- |
| depth | rejects | accepts | roc-cbor limits nesting to 512 arrays, maps and tags |
| nonshortest | rejects (strict) | accepts | strict roc-cbor (no PaddedNumbers) rejects a padded number: a head that is not the shortest |
| duplicate_keys | keeps all entries (strict: rejects) | keeps the last | cbor2 makes a dict. Python also merges keys that are equal as Python values: 1, 1.0 and true. The rest of such an input is not compared. |
| nan | both `fnan` | | Roc F64.to_bits gives one bit pattern for each NaN, so NaN payloads are not compared |
| tags | | | Not a difference here: cbor2 runs with no semantic decoders, so tags 2 and 3 (bignums), 0, 1 and others stay tags |

Each other difference is a finding. The script prints it with the hex of the input and exits with 1.
"""

import argparse
import io
import math
import os
import random
import re
import struct
import subprocess
import sys

import cbor2

# Each tag number that cbor2 decodes (all below 1100, and 55799) gives the tag back as it is.
SEMANTIC = {t: (lambda t: lambda v, _imm: cbor2.CBORTag(t, v))(t) for t in list(range(1100)) + [55799]}
MAX_DEPTH = 512


# The cbor2 side

def py_decode(data, strict_keys=False):
    """The value, or raises. The whole input must be one item."""
    fp = io.BytesIO(data)
    dec = cbor2.CBORDecoder(fp, semantic_decoders=SEMANTIC, max_depth=100_000, allow_indefinite=True,
                            allow_duplicate_keys=not strict_keys)
    value = dec.decode()
    if fp.tell() != len(data):
        raise ValueError("trailing bytes")
    return value


def has_duplicates(data):
    """cbor2 finds two keys of one map that are equal as Python values."""
    try:
        py_decode(data, strict_keys=True)
        return False
    except Exception:
        return True


def dump(x):
    """The canonical dump of a cbor2 value. The same format as value_dump.roc."""
    if x is True:
        return "true"
    if x is False:
        return "false"
    if x is None:
        return "null"
    if x is cbor2.undefined:
        return "undef"
    if isinstance(x, cbor2.CBORSimpleValue):
        return "s%d" % x.value
    if isinstance(x, int):
        return "i%d" % x
    if isinstance(x, float):
        return "fnan" if math.isnan(x) else "f" + struct.pack(">d", x).hex()
    if isinstance(x, (bytes, bytearray)):
        return "b" + bytes(x).hex()
    if isinstance(x, str):
        return "t" + x.encode("utf-8", "surrogatepass").hex()
    if isinstance(x, (list, tuple)):
        return "[" + ",".join(dump(i) for i in x) + "]"
    if isinstance(x, cbor2.CBORTag):
        return "c%d(%s)" % (x.tag, dump(x.value))
    if hasattr(x, "items"):
        return "{" + ",".join(dump(k) + ":" + dump(v) for k, v in x.items()) + "}"
    raise TypeError("no dump for %r" % type(x))


# A scan of the heads, independent of both decoders: the features that explain an expected difference.

def scan(data):
    """Flags of the input: indefinite, nonshortest, depth (max). Stops at the first error."""
    flags = {"indefinite": False, "nonshortest": False, "depth": 0}
    pos = 0

    def head():
        nonlocal pos
        ib = data[pos]
        pos += 1
        major, ai = ib >> 5, ib & 31
        if ai < 24:
            return major, ai, ai
        if ai > 27:
            if ai == 31:
                flags["indefinite"] = True
            return major, ai, None
        size = 1 << (ai - 24)
        if pos + size > len(data):
            raise IndexError
        arg = int.from_bytes(data[pos:pos + size], "big")
        pos += size
        if major != 7:
            limit = {24: 24, 25: 256, 26: 65536, 27: 1 << 32}[ai]
            if arg < limit:
                flags["nonshortest"] = True
        return major, ai, arg

    def item(depth):
        nonlocal pos
        major, ai, arg = head()
        if major in (4, 5, 6):
            flags["depth"] = max(flags["depth"], depth + 1)
        if arg is None:
            if ai != 31:
                raise ValueError
            if major in (2, 3, 4, 5):
                while data[pos] != 0xFF:
                    item(depth + 1)
                    if major == 5:
                        item(depth + 1)
                pos += 1
            return
        if major in (2, 3):
            pos += arg
        elif major == 4:
            for _ in range(arg):
                item(depth + 1)
        elif major == 5:
            for _ in range(2 * arg):
                item(depth + 1)
        elif major == 6:
            item(depth + 1)

    try:
        sys.setrecursionlimit(max(sys.getrecursionlimit(), 50_000))
        item(0)
    except (IndexError, ValueError, RecursionError):
        pass
    return flags


# The Roc side

def roc_run(roc_bin, inputs):
    """'ok <dump>' or 'err' for each input. Runs the binary on batches of hex args."""
    out = []
    batch, size = [], 0
    for data in inputs:
        h = data.hex() or ""
        if batch and (size + len(h) > 900_000 or len(batch) >= 2000):
            out += roc_batch(roc_bin, batch)
            batch, size = [], 0
        batch.append(h)
        size += len(h) + 1
    if batch:
        out += roc_batch(roc_bin, batch)
    return out


def roc_batch(roc_bin, batch):
    r = subprocess.run([roc_bin] + batch, capture_output=True, text=True)
    lines = r.stdout.splitlines()
    if r.returncode != 0 or len(lines) != len(batch):
        # A crash: run one at a time, so that the crash has its input.
        if len(batch) == 1:
            return ["crash (exit %d) %s" % (r.returncode, r.stderr.strip()[:200])]
        res = []
        for h in batch:
            res += roc_batch(roc_bin, [h])
        return res
    return lines


# Inputs

def head_bytes(major, n, width=None):
    """A head with argument n. width: None for the shortest, else 0 (in ai), 1, 2, 4 or 8 bytes."""
    if width is None:
        width = 0 if n < 24 else 1 if n < 256 else 2 if n < 65536 else 4 if n < 1 << 32 else 8
    if width == 0:
        return bytes([major << 5 | n])
    ai = {1: 24, 2: 25, 4: 26, 8: 27}[width]
    return bytes([major << 5 | ai]) + n.to_bytes(width, "big")


def rand_text(rng):
    pools = ["abc", "äöü", "日本", "\U0001f600", "\x00\x7f", "kind", "value"]
    n = rng.choice([0, 1, 2, 3, 3, 3, 10, 40])
    return "".join(rng.choice(pools) for _ in range(n))


def gen_item(rng, depth, wide=False):
    """Random well-formed CBOR bytes, definite lengths. wide: some heads are not the shortest."""
    def h(major, n):
        if wide and rng.random() < 0.3:
            need = 0 if n < 24 else 1 if n < 256 else 2 if n < 65536 else 4 if n < 1 << 32 else 8
            return head_bytes(major, n, rng.choice([w for w in (0, 1, 2, 4, 8) if w >= need]))
        return head_bytes(major, n)

    kinds = ["uint", "nint", "bytes", "text", "float", "simple"]
    if depth < 4:
        kinds += ["array", "map", "tag"] * 2
    k = rng.choice(kinds)
    if k == "uint":
        n = rng.choice([0, 1, 23, 24, 255, 256, 65535, 65536, (1 << 32) - 1, 1 << 32, (1 << 64) - 1, rng.randrange(1 << 64)])
        return h(0, n)
    if k == "nint":
        n = rng.choice([0, 23, 24, 255, (1 << 64) - 1, rng.randrange(1 << 64)])
        return h(1, n)
    if k == "bytes":
        b = bytes(rng.randrange(256) for _ in range(rng.choice([0, 1, 5, 23, 24, 30, 300])))
        return h(2, len(b)) + b
    if k == "text":
        t = rand_text(rng).encode()
        return h(3, len(t)) + t
    if k == "float":
        v = rng.choice([0.0, -0.0, 1.0, 1.5, -4.1, 65504.0, 1e300, 5.960464477539063e-8, float("inf"), float("-inf"), float("nan"), rng.uniform(-1e6, 1e6)])
        w = rng.choice(["e", "f", "d"])
        try:
            body = struct.pack(">" + w, v)
        except (OverflowError, struct.error):
            w, body = "d", struct.pack(">d", v)
        return bytes([{"e": 0xF9, "f": 0xFA, "d": 0xFB}[w]]) + body
    if k == "simple":
        n = rng.choice([0, 1, 19, 20, 21, 22, 23, 32, 100, 255])
        return bytes([0xE0 | n]) if n < 24 else bytes([0xF8, n])
    if k == "array":
        items = [gen_item(rng, depth + 1, wide) for _ in range(rng.randrange(0, 4))]
        return h(4, len(items)) + b"".join(items)
    if k == "map":
        n = rng.randrange(0, 4)
        out = h(5, n)
        for _ in range(n):
            key = h(3, len(t := rand_text(rng).encode())) + t if rng.random() < 0.7 else gen_item(rng, depth + 1, wide)
            out += key + gen_item(rng, depth + 1, wide)
        return out
    tag = rng.choice([0, 1, 2, 3, 4, 21, 24, 28, 29, 32, 37, 55799, 256, rng.randrange(1 << 64)])
    return h(6, tag) + gen_item(rng, depth + 1, wide)


def rand_py(rng, depth):
    """A random Python value for cbor2.dumps."""
    k = rng.randrange(9 if depth < 3 else 6)
    if k == 0:
        return rng.randrange(-(1 << 64), 1 << 64)
    if k == 1:
        return rng.choice([True, False, None])
    if k == 2:
        return rng.uniform(-1e9, 1e9)
    if k == 3:
        return rand_text(rng)
    if k == 4:
        return bytes(rng.randrange(256) for _ in range(rng.randrange(4)))
    if k == 5:
        return rng.randrange(-30, 30)
    if k == 6:
        return [rand_py(rng, depth + 1) for _ in range(rng.randrange(4))]
    if k == 7:
        return {rand_text(rng): rand_py(rng, depth + 1) for _ in range(rng.randrange(4))}
    return cbor2.CBORTag(rng.randrange(6, 1 << 32), rand_py(rng, depth + 1))


def mutate(rng, data):
    """One mutation of valid bytes: a name and the new bytes."""
    m = rng.choice(["flip", "set", "truncate", "length", "insert", "delete", "trailing"])
    b = bytearray(data)
    if not b:
        return m, bytes([rng.randrange(256)])
    i = rng.randrange(len(b))
    if m == "flip":
        b[i] ^= 1 << rng.randrange(8)
    elif m == "set":
        b[i] = rng.choice([0x00, 0x18, 0x1F, 0x3F, 0x5F, 0x7F, 0x9F, 0xBF, 0xDF, 0xF8, 0xFF, 0x1C, rng.randrange(256)])
    elif m == "truncate":
        del b[i:]
    elif m == "length":
        # A change of the argument of a head in its low bits.
        if b[i] & 31 < 24:
            b[i] = (b[i] & 0xE0) | (((b[i] & 31) + rng.choice([-1, 1])) % 24)
        else:
            b[i] ^= 1
    elif m == "insert":
        b.insert(i, rng.randrange(256))
    elif m == "delete":
        del b[i]
    else:
        b += bytes([rng.randrange(256)])
    return m, bytes(b)


def special_inputs():
    """Hand-made inputs: invalid UTF-8, duplicate keys, deep nesting, indefinite lengths, simple values."""
    out = []
    for t in [b"\xff", b"\xc3\x28", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xc0\xaf", b"\xe2\x82", b"a\x00b"]:
        out.append(("utf8", head_bytes(3, len(t)) + t))
        out.append(("utf8", b"\xa1" + head_bytes(3, len(t)) + t + b"\x01"))
    out += [
        ("dup", bytes.fromhex("a2616101616102")),
        ("dup", bytes.fromhex("a2010201f5")[:-1] + bytes.fromhex("03")),
        ("dup", bytes.fromhex("a201f5f503")),  # 1 and true: equal in Python
        ("dup", bytes.fromhex("a201f5f93c0003")),  # 1 and 1.0
        ("dup", bytes.fromhex("a2810101810102")),  # [1] two times
        ("dup", bytes.fromhex("a2a1010201a1010202")),  # {1: 2} two times
    ]
    for n in [1, 100, 511, 512, 513, 600, 2000]:
        for start, end in [(b"\x81", b"\x00"), (b"\xa1\x00", b"\x00"), (b"\xc1", b"\x00"), (b"\x9f", b"\xff")]:
            out.append(("deep", start * n + end + (end * n if end == b"\xff" else b"")))
    out += [("indef", bytes.fromhex(h)) for h in ["5f42010243030405ff", "7f657374726561646d696e67ff", "9fff", "9f018202039f0405ffff",
                                                  "bf61610161629f0203ffff", "5fff", "7fff", "5f4100ff", "bfff", "ff", "1f", "3f", "df00"]]
    out += [("simple", bytes([0xF8, n])) for n in (0, 19, 20, 23, 24, 31, 32, 255)]
    out += [("simple", bytes([0xE0 | n])) for n in range(24)] + [("simple", bytes([0xFC])), ("simple", bytes([0xFD])), ("simple", bytes([0xFE]))]
    out += [("reserved", bytes([m << 5 | ai])) for m in range(7) for ai in (28, 29, 30)]
    out += [("float", bytes.fromhex(h)) for h in ["f97e00", "f97e01", "f9fc00", "fa7fc00000", "fa7f800001", "fb7ff8000000000001", "fbfff8000000000000", "f90001", "f98000"]]
    out += [("empty", b"")]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--roc-bin", required=True)
    ap.add_argument("--corpus", action="append", default=[])
    ap.add_argument("--rfc")
    ap.add_argument("--count", type=int, default=4000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--strict", action="store_true", help="roc-cbor rejects padded numbers (no PaddedNumbers)")
    args = ap.parse_args()
    rng = random.Random(args.seed)

    inputs = []  # (source, bytes)
    for d in args.corpus:
        for name in sorted(os.listdir(d)):
            with open(os.path.join(d, name), "rb") as f:
                inputs.append(("corpus", f.read()))
    if args.rfc:
        text = open(args.rfc).read()
        inputs += [("rfc", bytes.fromhex(h)) for h in sorted(set(re.findall(r'"([0-9a-f]{2,})"', text))) if len(h) % 2 == 0]
    inputs += special_inputs()
    valid = []
    for _ in range(args.count // 2):
        valid.append(("gen", gen_item(rng, 0)))
    for _ in range(args.count // 8):
        valid.append(("gen-wide", gen_item(rng, 0, wide=True)))
    for _ in range(args.count // 8):
        valid.append(("cbor2", cbor2.dumps(rand_py(rng, 0))))
    inputs += valid
    pool = valid + [i for i in inputs if i[0] == "corpus"]
    for _ in range(args.count):
        _, data = rng.choice(pool)
        name, b = mutate(rng, data)
        inputs.append(("mut-" + name, b))

    roc = roc_run(args.roc_bin, [b for _, b in inputs])
    counts = {}
    findings = []
    for (source, data), r in zip(inputs, roc):
        try:
            py = "ok " + dump(py_decode(data))
        except Exception:
            py = "err"
        flags = scan(data)
        if r == py:
            cls = "same-valid" if r.startswith("ok") else "same-invalid"
        elif r.startswith("crash"):
            cls = None
        elif r == "err" and py.startswith("ok"):
            # Indefinite lengths are compared: the Roc side reads with IndefiniteLength.
            cls = ("depth" if flags["depth"] > MAX_DEPTH
                   else "nonshortest" if flags["nonshortest"] and args.strict
                   else "duplicate_keys" if args.strict and has_duplicates(data) else None)
        elif r.startswith("ok") and py.startswith("ok"):
            cls = "duplicate_keys" if has_duplicates(data) else None
        else:
            cls = None
        if cls is None:
            findings.append((source, data, r, py))
            cls = "FINDING"
        counts[cls] = counts.get(cls, 0) + 1

    print("inputs: %d (corpus %d, rfc %d)" % (len(inputs), sum(s == "corpus" for s, _ in inputs), sum(s == "rfc" for s, _ in inputs)))
    print("| class | count |")
    print("| --- | ---: |")
    for k in sorted(counts):
        print("| %s | %d |" % (k, counts[k]))
    for source, data, r, py in findings:
        print("FINDING %s hex=%s\n  roc:   %s\n  cbor2: %s" % (source, data.hex()[:400], r[:300], py[:300]))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
