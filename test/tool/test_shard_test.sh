#!/usr/bin/env bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# shellcheck source=../../tool/test_shard.sh
source tool/test_shard.sh

readonly all_files="$(find test -name '*_test.dart' -type f | LC_ALL=C sort)"

for shards in 1 4; do
  covered="$(
    for ((shard = 0; shard < shards; shard++)); do
      shard_files "$shard" "$shards"
    done | LC_ALL=C sort
  )"
  if [[ "$covered" != "$all_files" ]]; then
    echo "FAIL: $shards частей не покрывают каждый тестовый файл ровно один раз" >&2
    exit 1
  fi
done

echo "Части тестов покрывают каждый тестовый файл ровно один раз"
