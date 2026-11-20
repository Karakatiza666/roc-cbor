"""The Python side of bench/compare. Usage: python -I bench.py <case> <loops> <fixture_dir>

Library: cbor2 (its compiled decoder and encoder). Python has no typed reader: a "typed" parse case is
cbor2.loads plus the build of the Python objects a program would use (a slotted Rec for each record).
The contract of each case is in bench/compare/README.md.
"""

import sys

import cbor2


class Rec:
    __slots__ = ("id", "name", "ok", "score", "tags")

    def __init__(self, d):
        self.id = d["id"]
        self.name = d["name"]
        self.ok = d["ok"]
        self.score = d["score"]
        self.tags = d["tags"]


FIXTURE = {
    "bytes_encode": "bytes", "bytes_parse": "bytes",
    "records_encode": "records", "records_parse": "records", "records_value": "records",
    "unknown_parse": "wide", "dict_parse": "dict", "map_value": "dict", "text_parse": "texts",
    "deep_encode": "deep", "deep_parse": "deep",
}


def main():
    case, loops, fixture_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    if case not in FIXTURE:
        print(f"unknown case: {case}", file=sys.stderr)
        sys.exit(2)
    with open(f"{fixture_dir}/{FIXTURE[case]}.cbor", "rb") as f:
        data = f.read()
    dumps = cbor2.dumps

    def loads(b):
        # max_depth: the default is 400; `deep` has 500 levels (the limit of roc-cbor is 512).
        return cbor2.loads(b, max_depth=1024)

    total = 0
    if case in ("bytes_encode", "records_encode", "deep_encode"):
        value = loads(data)
        for _ in range(loops):
            total += len(dumps(value))
    elif case in ("records_parse", "unknown_parse"):
        for _ in range(loops):
            total += len([Rec(d) for d in loads(data)])
    elif case in ("bytes_parse", "dict_parse", "text_parse"):
        for _ in range(loops):
            total += len(loads(data))
    else:  # records_value, map_value, deep_parse: the dynamic value
        for _ in range(loops):
            loads(data)
            total += 1
    print(f"{case} {loops} {total}")


if __name__ == "__main__":
    sys.setrecursionlimit(10_000)
    main()
