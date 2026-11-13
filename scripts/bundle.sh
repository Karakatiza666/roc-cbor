#!/usr/bin/env bash
# Writes dist/<hash>.tar.zst, lists its files, and prints its path and its release URL.
# Usage: ROC=/path/to/roc scripts/bundle.sh [version]. The default version is the tag of HEAD.
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
version="${1:-$(git describe --tags --exact-match 2>/dev/null || echo '<version>')}"

rm -rf dist
mkdir dist
"$ROC" bundle src/main.roc --output-dir dist >&2
asset=$(echo dist/*.tar.zst)
zstd -dc "$asset" | tar -t >&2
echo "asset: $asset"
# The repository of the release: GITHUB_REPOSITORY in CI (a fork publishes to itself), else the upstream repository.
repo="${GITHUB_REPOSITORY:-Karakatiza666/roc-cbor}"
echo "url: https://github.com/$repo/releases/download/$version/$(basename "$asset")"
