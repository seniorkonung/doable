#!/usr/bin/env bash

set -euo pipefail

readonly project_root="$(git rev-parse --show-toplevel)"
readonly helper="$project_root/tool/check_ci_scope.sh"

if [[ ! -f "$helper" ]]; then
  echo "Не найден проверяемый helper: $helper" >&2
  exit 1
fi

# shellcheck source=../../tool/check_ci_scope.sh
source "$helper"

failures=0

check_boolean() {
  local name="$1"
  local expected="$2"
  shift 2

  local actual=false
  if "$@"; then
    actual=true
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $name: ожидалось $expected, получено $actual" >&2
    failures=$((failures + 1))
    return
  fi
  echo "PASS: $name"
}

check_value() {
  local name="$1"
  local expected="$2"
  shift 2

  local actual
  actual="$("$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $name: ожидалось '$expected', получено '$actual'" >&2
    failures=$((failures + 1))
    return
  fi
  echo "PASS: $name"
}

readonly previous_sha=1111111111111111111111111111111111111111
readonly current_sha=2222222222222222222222222222222222222222
readonly fixture_pull_request_number=4

workflow_runs() {
  local status="$1"
  local conclusion="$2"
  local path="${3:-.github/workflows/ci.yml@refs/pull/4/merge}"
  local head_sha="${4:-$previous_sha}"
  local pr_number="${5:-$fixture_pull_request_number}"

  printf \
    '{"total_count":1,"workflow_runs":[{"id":17,"head_sha":"%s","path":"%s","event":"pull_request","status":"%s","conclusion":%s,"check_suite_id":23,"pull_requests":[{"number":%s}]}]}' \
    "$head_sha" \
    "$path" \
    "$status" \
    "$conclusion" \
    "$pr_number"
}

check_runs() {
  local status="$1"
  local conclusion="$2"
  local name="${3:-Full checks}"
  local head_sha="${4:-$previous_sha}"

  printf \
    '{"total_count":1,"check_runs":[{"id":29,"name":"%s","head_sha":"%s","status":"%s","conclusion":%s,"check_suite":{"id":23},"app":{"slug":"github-actions"}}]}' \
    "$name" \
    "$head_sha" \
    "$status" \
    "$conclusion"
}

readonly successful_workflow_runs="$(workflow_runs completed '"success"')"
readonly successful_check_runs="$(check_runs completed '"success"')"

for path in \
  android/app/src/main/AndroidManifest.xml \
  pubspec.yaml \
  pubspec.lock \
  mise.toml \
  .github/workflows/ci.yml \
  tool/check_android_privacy_manifest.dart
do
  check_value \
    "artifact-impacting путь $path" \
    artifact \
    path_classification \
    "$path"
done

check_value \
  "неизвестный путь классифицируется fail-closed" \
  unknown \
  path_classification \
  scripts/new_tool.sh

for path in \
  README.md \
  docs/architecture.md \
  openspec/changes/example/spec.md \
  lib/src/example.dart \
  test/example_test.dart \
  analysis_options.yaml \
  dart_test.yaml \
  l10n.yaml \
  build.yaml \
  drift_schemas/schema_v1.json
do
  check_value \
    "доказанно не влияющий путь $path" \
    safe \
    path_classification \
    "$path"
done

check_boolean \
  "только документация пропускает Android artifact" \
  false \
  paths_require_android \
  README.md \
  docs/architecture.md
check_boolean \
  "Dart и test-only изменения пропускают Android artifact" \
  false \
  paths_require_android \
  lib/src/example.dart \
  test/example_test.dart
check_boolean \
  "Android-изменение требует artifact" \
  true \
  paths_require_android \
  README.md \
  android/app/build.gradle.kts
check_boolean \
  "неизвестный путь требует artifact" \
  true \
  paths_require_android \
  scripts/new_tool.sh
check_boolean \
  "пустое change evidence требует artifact" \
  true \
  paths_require_android
check_boolean \
  "небезопасный относительный путь требует artifact" \
  true \
  paths_require_android \
  ../README.md

check_boolean \
  "успешный Full checks этого workflow считается доверенным" \
  true \
  previous_gate_is_trusted \
  "$successful_workflow_runs" \
  "$successful_check_runs" \
  "$previous_sha" \
  "$fixture_pull_request_number"
check_boolean \
  "отсутствующий предыдущий gate не считается доверенным" \
  false \
  previous_gate_is_trusted \
  '{"total_count":0,"workflow_runs":[]}' \
  '{"total_count":0,"check_runs":[]}' \
  "$previous_sha" \
  "$fixture_pull_request_number"
check_boolean \
  "отменённый предыдущий gate не считается доверенным" \
  false \
  previous_gate_is_trusted \
  "$(workflow_runs completed '"cancelled"')" \
  "$(check_runs completed '"cancelled"')" \
  "$previous_sha" \
  "$fixture_pull_request_number"
check_boolean \
  "выполняющийся предыдущий gate не считается доверенным" \
  false \
  previous_gate_is_trusted \
  "$(workflow_runs in_progress null)" \
  "$(check_runs in_progress null)" \
  "$previous_sha" \
  "$fixture_pull_request_number"
check_boolean \
  "неуспешный предыдущий gate не считается доверенным" \
  false \
  previous_gate_is_trusted \
  "$(workflow_runs completed '"failure"')" \
  "$(check_runs completed '"failure"')" \
  "$previous_sha" \
  "$fixture_pull_request_number"
check_boolean \
  "успех другого workflow не считается доверенным" \
  false \
  previous_gate_is_trusted \
  "$(workflow_runs completed '"success"' '.github/workflows/other.yml@main')" \
  "$successful_check_runs" \
  "$previous_sha" \
  "$fixture_pull_request_number"
check_boolean \
  "успех другого PR не считается доверенным" \
  false \
  previous_gate_is_trusted \
  "$(workflow_runs completed '"success"' '.github/workflows/ci.yml@main' "$previous_sha" 9)" \
  "$successful_check_runs" \
  "$previous_sha" \
  "$fixture_pull_request_number"
check_boolean \
  "malformed API evidence не считается доверенным" \
  false \
  previous_gate_is_trusted \
  '{"workflow_runs":"unexpected"}' \
  '{"check_runs":[]}' \
  "$previous_sha" \
  "$fixture_pull_request_number"

check_boolean \
  "synchronize использует incremental diff после доверенного ancestor gate" \
  true \
  can_use_incremental_diff \
  synchronize \
  "$previous_sha" \
  "$current_sha" \
  "$current_sha" \
  1 \
  true \
  "$successful_workflow_runs" \
  "$successful_check_runs" \
  "$fixture_pull_request_number"
check_boolean \
  "non-ancestor range возвращается к полному PR diff" \
  false \
  can_use_incremental_diff \
  synchronize \
  "$previous_sha" \
  "$current_sha" \
  "$current_sha" \
  1 \
  false \
  "$successful_workflow_runs" \
  "$successful_check_runs" \
  "$fixture_pull_request_number"
check_boolean \
  "повторный запуск возвращается к полному PR diff" \
  false \
  can_use_incremental_diff \
  synchronize \
  "$previous_sha" \
  "$current_sha" \
  "$current_sha" \
  2 \
  true \
  "$successful_workflow_runs" \
  "$successful_check_runs" \
  "$fixture_pull_request_number"
check_boolean \
  "reopened PR возвращается к полному PR diff" \
  false \
  can_use_incremental_diff \
  reopened \
  "$previous_sha" \
  "$current_sha" \
  "$current_sha" \
  1 \
  true \
  "$successful_workflow_runs" \
  "$successful_check_runs" \
  "$fixture_pull_request_number"
check_boolean \
  "несовпадающий after делает change evidence недоверенным" \
  false \
  can_use_incremental_diff \
  synchronize \
  "$previous_sha" \
  3333333333333333333333333333333333333333 \
  "$current_sha" \
  1 \
  true \
  "$successful_workflow_runs" \
  "$successful_check_runs" \
  "$fixture_pull_request_number"
check_boolean \
  "malformed SHA делает change evidence недоверенным" \
  false \
  can_use_incremental_diff \
  synchronize \
  invalid \
  "$current_sha" \
  "$current_sha" \
  1 \
  true \
  "$successful_workflow_runs" \
  "$successful_check_runs" \
  "$fixture_pull_request_number"

if ((failures > 0)); then
  echo "Проверка CI scope detector завершилась с ошибками: $failures" >&2
  exit 1
fi

echo "CI scope detector прошёл focused contract tests"
