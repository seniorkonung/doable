#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .dart_tool/statistics-temp
export TMPDIR="$PWD/.dart_tool/statistics-temp"

shopt -s globstar nullglob
benchmarks=(benchmark/**/*_benchmark.dart)
exec mise exec --no-deps -- flutter test --no-pub "${benchmarks[@]}" \
  --concurrency=1 --reporter=expanded "$@"
