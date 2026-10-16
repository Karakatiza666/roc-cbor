#!/usr/bin/env bash
# The local and CI checks. Usage: ROC=/path/to/roc scripts/all_tests.sh
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
# Keep the roc cache inside the repository.
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
mkdir -p "$ROC_CACHE_DIR"

"$ROC" version
"$ROC" fmt --check src tests examples
"$ROC" check src/main.roc
# The expects in src/Cbor.roc.
"$ROC" test src/main.roc
# The RFC 8949 Appendix A vectors, through the public API of the package.
"$ROC" test tests/rfc8949.roc
for f in examples/*.roc; do
	"$ROC" check "$f"
	"$ROC" "$f"
done
"$ROC" docs src/main.roc --output="$ROC_CACHE_DIR/docs" >/dev/null
