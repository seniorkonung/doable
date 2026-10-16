#!/usr/bin/env bash

set -euo pipefail

readonly project_root="$(git rev-parse --show-toplevel)"
readonly helper="$project_root/tool/check_ci_scope.sh"
readonly workflow="$project_root/.github/workflows/ci.yml"

if [[ ! -f "$helper" ]]; then
  echo "Не найден проверяемый helper: $helper" >&2
  exit 1
fi

if [[ ! -f "$workflow" ]]; then
  echo "Не найден проверяемый workflow: $workflow" >&2
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

workflow_disables_mise_auto_install() {
  local count
  count="$(awk '$0 == "  MISE_AUTO_INSTALL: \"false\"" { count += 1 } END { print count + 0 }' "$workflow")"
  [[ "$count" == 1 ]]
}

project_mise_tasks_skip_tool_installation() {
  awk '
    /^  project_checks:/ {
      in_project_checks = 1
      next
    }
    in_project_checks && /^  [[:alnum:]_]+:/ {
      exit
    }
    in_project_checks && /run: mise run / {
      found_task = 1
      if ($0 !~ /run: mise run --skip-tools /) {
        invalid_task = 1
      }
    }
    END {
      exit !(found_task && !invalid_task)
    }
  ' "$workflow"
}

openspec_validation_avoids_mise_exec() {
  awk '
    /^  openspec_checks:/ {
      in_openspec_checks = 1
      next
    }
    in_openspec_checks && /^  [[:alnum:]_]+:/ {
      exit
    }
    in_openspec_checks && /run: mise exec / {
      invalid_command = 1
    }
    in_openspec_checks && /run: openspec validate --all --strict --no-interactive/ {
      found_direct_validation = 1
    }
    END {
      exit !(found_direct_validation && !invalid_command)
    }
  ' "$workflow"
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

check_boolean \
  "workflow отключает автоматическую установку mise-инструментов" \
  true \
  workflow_disables_mise_auto_install
check_boolean \
  "проектные mise-задачи не устанавливают полный toolchain" \
  true \
  project_mise_tasks_skip_tool_installation
check_boolean \
  "OpenSpec-валидация не запускает mise exec" \
  true \
  openspec_validation_avoids_mise_exec

for path in \
  android/app/src/main/AndroidManifest.xml \
  pubspec.yaml \
  pubspec.lock \
  mise.toml \
  .github/workflows/ci.yml \
  tool/check_ci_scope.sh \
  tool/check_android_privacy_manifest.dart
do
  check_value \
    "Android-impacting путь $path" \
    android \
    path_classification \
    "$path"
done

check_value \
  "неизвестный путь классифицируется fail-closed" \
  unknown \
  path_classification \
  scripts/new_tool.sh

for path in \
  lib/src/example.dart \
  test/example_test.dart \
  analysis_options.yaml \
  dart_test.yaml \
  l10n.yaml \
  build.yaml \
  drift_schemas/schema_v1.json
do
  check_value \
    "проектный путь $path" \
    project \
    path_classification \
    "$path"
done

for path in \
  README.md \
  AGENTS.md \
  docs/architecture.md \
  notes/nested/review.md
do
  check_value \
    "документационный путь $path" \
    documentation \
    path_classification \
    "$path"
done

check_value \
  "OpenSpec Markdown требует OpenSpec-валидации" \
  openspec \
  path_classification \
  openspec/changes/example/spec.md
check_value \
  "OpenSpec-конфигурация требует OpenSpec-валидации" \
  openspec \
  path_classification \
  openspec/config.yaml

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
  "доказанно пустой diff пропускает Android artifact" \
  false \
  paths_require_android
check_boolean \
  "небезопасный относительный путь требует artifact" \
  true \
  paths_require_android \
  ../README.md

check_boolean \
  "только документация пропускает проектные проверки" \
  false \
  paths_require_project \
  README.md \
  docs/architecture.md
check_boolean \
  "OpenSpec-only изменение пропускает проектные проверки" \
  false \
  paths_require_project \
  README.md \
  openspec/changes/example/spec.md
check_boolean \
  "Dart-изменение требует проектные проверки" \
  true \
  paths_require_project \
  lib/src/example.dart
check_boolean \
  "Android-изменение требует проектные проверки" \
  true \
  paths_require_project \
  android/app/build.gradle.kts
check_boolean \
  "неизвестный путь требует проектные проверки" \
  true \
  paths_require_project \
  scripts/new_tool.sh
check_boolean \
  "доказанно пустой diff пропускает проектные проверки" \
  false \
  paths_require_project

check_boolean \
  "только документация пропускает OpenSpec-валидацию" \
  false \
  paths_require_openspec \
  README.md \
  docs/architecture.md
check_boolean \
  "OpenSpec-изменение требует OpenSpec-валидацию" \
  true \
  paths_require_openspec \
  README.md \
  openspec/changes/example/spec.md
check_boolean \
  "Dart-изменение не требует OpenSpec-валидацию" \
  false \
  paths_require_openspec \
  lib/src/example.dart
check_boolean \
  "неизвестный путь требует OpenSpec-валидацию fail-closed" \
  true \
  paths_require_openspec \
  scripts/new_tool.sh
check_boolean \
  "доказанно пустой diff пропускает OpenSpec-валидацию" \
  false \
  paths_require_openspec

check_value \
  "решение публикует все три независимых gate-выхода" \
  $'project_required=false\nopenspec_required=true\nandroid_required=false\nreason=OpenSpec-only diff' \
  write_decision \
  false \
  true \
  false \
  'OpenSpec-only diff'

scheduled_decision() {
  GITHUB_EVENT_NAME=schedule GITHUB_OUTPUT='' main
}

check_value \
  "еженедельный запуск требует все проверки" \
  $'project_required=true\nopenspec_required=true\nandroid_required=true\nreason=полный ручной или еженедельный запуск' \
  scheduled_decision

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
