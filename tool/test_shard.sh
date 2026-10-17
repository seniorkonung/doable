#!/usr/bin/env bash

set -euo pipefail

# Печатает тестовые файлы части [shard] из [shards]. Файлы раздаются частям
# по очереди в порядке путей, поэтому вместе части покрывают каждый файл,
# который находит `flutter test`, ровно один раз.
shard_files() {
  local shard="$1"
  local shards="$2"

  find test -name '*_test.dart' -type f |
    LC_ALL=C sort |
    awk -v shard="$shard" -v shards="$shards" '(NR - 1) % shards == shard'
}

main() {
  if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[1-9][0-9]*$ ]] ||
    ((10#$1 >= 10#$2)); then
    echo "Использование: $0 <номер части от 0> <число частей>" >&2
    exit 2
  fi

  cd "$(git rev-parse --show-toplevel)"
  local files
  mapfile -t files < <(shard_files "$1" "$2")
  # Вложенный Flutter в наборах flutter_process пересоздаёт нативные
  # артефакты SQLite в общей сборке, поэтому они запускаются отдельно.
  # Число параллельных наборов по умолчанию — половина ядер машины.
  exec flutter test --exclude-tags=flutter_process "${files[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
