#!/usr/bin/env bash

set -euo pipefail

assert_clean_tree() {
  local context="$1"
  local status

  if ! git diff --exit-code --no-ext-diff; then
    echo "Рабочая копия содержит изменённые tracked-файлы: $context" >&2
    return 1
  fi

  status="$(git status --porcelain --untracked-files=all)"
  if [[ -n "$status" ]]; then
    echo "Рабочая копия содержит незакоммиченные файлы: $context" >&2
    printf '%s\n' "$status" >&2
    return 1
  fi
}

readonly project_root="$(git rev-parse --show-toplevel)"
cd "$project_root"

case "${1:-}" in
  --verify-only)
    assert_clean_tree "проверка generated artifacts"
    exit 0
    ;;
  "") ;;
  *)
    echo "Использование: $0 [--verify-only]" >&2
    exit 2
    ;;
esac

assert_clean_tree "до повторной генерации"

flutter pub get
if ! git diff --exit-code --no-ext-diff -- pubspec.lock; then
  echo "flutter pub get изменил committed pubspec.lock" >&2
  exit 1
fi

flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump \
  lib/src/data/local/app_database.dart \
  drift_schemas/
dart run drift_dev schema steps \
  drift_schemas/ \
  lib/src/data/local/migrations/generated_schema.dart

assert_clean_tree "после повторной генерации"
