#!/usr/bin/env bash

set -euo pipefail

readonly project_root="$(git rev-parse --show-toplevel)"
readonly checker_source="$project_root/tool/check_generated.sh"
readonly fixture_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$fixture_dir"
}
trap cleanup EXIT

if [[ ! -f "$checker_source" ]]; then
  echo "Не найден проверяемый helper: $checker_source" >&2
  exit 1
fi

mkdir -p "$fixture_dir/tool" "$fixture_dir/lib"
cp "$checker_source" "$fixture_dir/tool/check_generated.sh"

git -C "$fixture_dir" init --quiet
git -C "$fixture_dir" config user.email "tooling-test@example.invalid"
git -C "$fixture_dir" config user.name "Проверка tooling"
git -C "$fixture_dir" config commit.gpgSign false
printf 'исходный artifact\n' >"$fixture_dir/lib/generated.dart"
git -C "$fixture_dir" add tool/check_generated.sh lib/generated.dart
git -C "$fixture_dir" commit --quiet -m "test: create isolated fixture"

git -C "$fixture_dir" diff --exit-code
(
  cd "$fixture_dir"
  bash tool/check_generated.sh --verify-only
)

printf 'изменённый artifact\n' >"$fixture_dir/lib/generated.dart"
if (
  cd "$fixture_dir"
  bash tool/check_generated.sh --verify-only
) >/dev/null 2>&1; then
  echo "Проверка не обнаружила изменённый tracked artifact" >&2
  exit 1
fi

git -C "$fixture_dir" restore lib/generated.dart
printf 'новый generated artifact\n' >"$fixture_dir/lib/new_file.g.dart"
if (
  cd "$fixture_dir"
  bash tool/check_generated.sh --verify-only
) >/dev/null 2>&1; then
  echo "Проверка не обнаружила новый untracked generated artifact" >&2
  exit 1
fi

echo "Проверка обнаруживает tracked и untracked generated artifacts"
