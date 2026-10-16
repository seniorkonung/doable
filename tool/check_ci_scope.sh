#!/usr/bin/env bash

set -euo pipefail

readonly ci_workflow_path='.github/workflows/ci.yml'
readonly github_api_version='2026-03-10'

path_classification() {
  local path="${1:-}"

  if [[ -z "$path" ||
    "$path" == /* ||
    "$path" == ./* ||
    "$path" == *\\* ||
    "$path" == *$'\n'* ||
    "$path" == '..' ||
    "$path" == ../* ||
    "$path" == */../* ||
    "$path" == */.. ]]; then
    printf '%s\n' unknown
    return
  fi

  case "$path" in
    openspec/*)
      printf '%s\n' openspec
      ;;
    *.md|docs/*)
      printf '%s\n' documentation
      ;;
    android/*|pubspec.yaml|pubspec.lock|mise.toml|.github/workflows/*|tool/check_ci_scope.sh|tool/check_android_privacy_manifest.dart)
      printf '%s\n' android
      ;;
    lib/*|test/*|analysis_options.yaml|dart_test.yaml|l10n.yaml|build.yaml|drift_schemas/*)
      printf '%s\n' project
      ;;
    *)
      printf '%s\n' unknown
      ;;
  esac
}

paths_require_android() {
  local path
  for path in "$@"; do
    case "$(path_classification "$path")" in
      android | unknown) return 0 ;;
      documentation | openspec | project) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

paths_require_project() {
  local path
  for path in "$@"; do
    case "$(path_classification "$path")" in
      project | android | unknown) return 0 ;;
      documentation | openspec) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

paths_require_openspec() {
  local path
  for path in "$@"; do
    case "$(path_classification "$path")" in
      openspec | unknown) return 0 ;;
      documentation | project | android) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

is_valid_commit_sha() {
  [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]
}

previous_gate_is_trusted() {
  local workflow_runs_json="${1:-}"
  local check_runs_json="${2:-}"
  local expected_sha="${3:-}"
  local pull_request_number="${4:-}"

  if ! is_valid_commit_sha "$expected_sha" ||
    [[ ! "$pull_request_number" =~ ^[1-9][0-9]*$ ]]; then
    return 1
  fi

  jq -e -n \
    --argjson workflowEvidence "$workflow_runs_json" \
    --argjson checkEvidence "$check_runs_json" \
    --arg expectedSha "$expected_sha" \
    --arg workflowPath "$ci_workflow_path" \
    --argjson pullRequestNumber "$pull_request_number" '
      ($workflowEvidence.workflow_runs | arrays) as $workflowRuns
      | ($checkEvidence.check_runs | arrays) as $checkRuns
      | any(
          $workflowRuns[];
          . as $workflowRun
          | ($workflowRun.id | type == "number")
            and ($workflowRun.head_sha == $expectedSha)
            and ($workflowRun.event == "pull_request")
            and ($workflowRun.status == "completed")
            and ($workflowRun.conclusion == "success")
            and (($workflowRun.check_suite_id | type) == "number")
            and (
              ($workflowRun.path | type) == "string"
              and (
                $workflowRun.path == $workflowPath
                or ($workflowRun.path | startswith($workflowPath + "@"))
              )
            )
            and (
              ($workflowRun.pull_requests | arrays)
              and any(
                $workflowRun.pull_requests[];
                .number == $pullRequestNumber
              )
            )
            and any(
              $checkRuns[];
              .name == "Full checks"
              and .head_sha == $expectedSha
              and .status == "completed"
              and .conclusion == "success"
              and .app.slug == "github-actions"
              and .check_suite.id == $workflowRun.check_suite_id
            )
        )
    ' >/dev/null 2>&1
}

can_use_incremental_diff() {
  local action="${1:-}"
  local before_sha="${2:-}"
  local after_sha="${3:-}"
  local head_sha="${4:-}"
  local run_attempt="${5:-}"
  local is_ancestor="${6:-}"
  local workflow_runs_json="${7:-}"
  local check_runs_json="${8:-}"
  local pull_request_number="${9:-}"

  [[ "$action" == synchronize ]] || return 1
  [[ "$run_attempt" == 1 ]] || return 1
  [[ "$is_ancestor" == true ]] || return 1
  is_valid_commit_sha "$before_sha" || return 1
  is_valid_commit_sha "$after_sha" || return 1
  is_valid_commit_sha "$head_sha" || return 1
  [[ "$before_sha" != "$head_sha" ]] || return 1
  [[ "$after_sha" == "$head_sha" ]] || return 1
  previous_gate_is_trusted \
    "$workflow_runs_json" \
    "$check_runs_json" \
    "$before_sha" \
    "$pull_request_number"
}

write_decision() {
  local project_required="$1"
  local openspec_required="$2"
  local android_required="$3"
  local reason="$4"
  local output_file="${GITHUB_OUTPUT:-}"

  printf 'project_required=%s\n' "$project_required"
  printf 'openspec_required=%s\n' "$openspec_required"
  printf 'android_required=%s\n' "$android_required"
  printf 'reason=%s\n' "$reason"
  if [[ -n "$output_file" ]]; then
    printf 'project_required=%s\nopenspec_required=%s\nandroid_required=%s\nreason=%s\n' \
      "$project_required" \
      "$openspec_required" \
      "$android_required" \
      "$reason" >>"$output_file"
  fi
}

read_required_event_string() {
  local event_path="$1"
  local expression="$2"

  jq -er "$expression | select(type == \"string\")" "$event_path"
}

read_required_event_integer() {
  local event_path="$1"
  local expression="$2"

  jq -er "$expression | select(type == \"number\" and floor == .)" \
    "$event_path"
}

github_api_get() {
  local url="$1"
  local output_file="$2"
  local token="${GITHUB_TOKEN:-}"

  [[ -n "$token" ]] || return 1
  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --connect-timeout 10 \
    --max-time 30 \
    --retry 2 \
    --retry-all-errors \
    --proto '=https' \
    --header 'Accept: application/vnd.github+json' \
    --header "Authorization: Bearer $token" \
    --header "X-GitHub-Api-Version: $github_api_version" \
    --output "$output_file" \
    "$url"
}

changed_paths_for_range() {
  local range="$1"
  local output_file="$2"

  git diff --no-renames --name-only -z "$range" -- >"$output_file"
}

main() {
  local event_name="${GITHUB_EVENT_NAME:-}"

  case "$event_name" in
    schedule | workflow_dispatch)
      write_decision true true true 'полный ручной или еженедельный запуск'
      return
      ;;
    pull_request) ;;
    *)
      write_decision true true true 'неизвестный тип запуска'
      return
      ;;
  esac

  local event_path="${GITHUB_EVENT_PATH:-}"
  if [[ -z "$event_path" || ! -f "$event_path" ]]; then
    write_decision true true true 'отсутствует pull request event evidence'
    return
  fi

  local action pull_request_number base_sha head_sha
  if ! action="$(read_required_event_string "$event_path" '.action')" ||
    ! pull_request_number="$(read_required_event_integer "$event_path" '.number')" ||
    ! base_sha="$(read_required_event_string "$event_path" '.pull_request.base.sha')" ||
    ! head_sha="$(read_required_event_string "$event_path" '.pull_request.head.sha')" ||
    ! is_valid_commit_sha "$base_sha" ||
    ! is_valid_commit_sha "$head_sha" ||
    [[ ! "$pull_request_number" =~ ^[1-9][0-9]*$ ]]; then
    write_decision true true true 'pull request event evidence имеет неверный формат'
    return
  fi

  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  local diff_range="$base_sha...$head_sha"
  local diff_mode=full
  local run_attempt="${GITHUB_RUN_ATTEMPT:-}"
  local before_sha=''
  local after_sha=''
  local is_ancestor=false
  local workflow_runs_json='{}'
  local check_runs_json='{}'

  if [[ "$action" == synchronize && "$run_attempt" == 1 ]]; then
    before_sha="$(jq -er '.before | select(type == "string")' "$event_path" 2>/dev/null || true)"
    after_sha="$(jq -er '.after | select(type == "string")' "$event_path" 2>/dev/null || true)"

    if is_valid_commit_sha "$before_sha" &&
      is_valid_commit_sha "$after_sha" &&
      git merge-base --is-ancestor "$before_sha" "$head_sha"; then
      is_ancestor=true

      local repository="${GITHUB_REPOSITORY:-}"
      local api_url="${GITHUB_API_URL:-}"
      if [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ &&
        "$api_url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^?#]*)?$ ]]; then
        api_url="${api_url%/}"
        local workflow_runs_file="$temp_dir/workflow-runs.json"
        local check_runs_file="$temp_dir/check-runs.json"
        if github_api_get \
          "$api_url/repos/$repository/actions/workflows/ci.yml/runs?event=pull_request&head_sha=$before_sha&per_page=100" \
          "$workflow_runs_file" &&
          github_api_get \
            "$api_url/repos/$repository/commits/$before_sha/check-runs?check_name=Full%20checks&filter=all&per_page=100" \
            "$check_runs_file"; then
          workflow_runs_json="$(<"$workflow_runs_file")"
          check_runs_json="$(<"$check_runs_file")"
        fi
      fi
    fi
  fi

  if can_use_incremental_diff \
    "$action" \
    "$before_sha" \
    "$after_sha" \
    "$head_sha" \
    "$run_attempt" \
    "$is_ancestor" \
    "$workflow_runs_json" \
    "$check_runs_json" \
    "$pull_request_number"; then
    diff_mode=incremental
    diff_range="$before_sha..$head_sha"
  fi

  local changed_paths_file="$temp_dir/changed-paths"
  if ! changed_paths_for_range "$diff_range" "$changed_paths_file"; then
    write_decision true true true 'не удалось получить полный change evidence'
    return
  fi

  local -a changed_paths=()
  while IFS= read -r -d '' path; do
    changed_paths+=("$path")
  done <"$changed_paths_file"

  local project_required=false
  local openspec_required=false
  local android_required=false
  if paths_require_project "${changed_paths[@]}"; then
    project_required=true
  fi
  if paths_require_openspec "${changed_paths[@]}"; then
    openspec_required=true
  fi
  if paths_require_android "${changed_paths[@]}"; then
    android_required=true
  fi
  write_decision \
    "$project_required" \
    "$openspec_required" \
    "$android_required" \
    "$diff_mode diff: project=$project_required, openspec=$openspec_required, android=$android_required"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
