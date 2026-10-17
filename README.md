# Doable

Doable is an Android-first Flutter application for preserving intentions and,
through the planned intention graph, connecting them to meaningful daily
actions. The current implementation provides the complete local lifecycle of
an intention: creation, bounded catalog browsing, editing, explicit action
readiness, archiving, restoration, deletion, Russian and English localization,
and persistence within one application installation.

The product model is maintained in
[`docs/discussions/action-centered-goal-system.md`](docs/discussions/action-centered-goal-system.md).

## Local data before launch and rollback

The SQLite schema is version 3 (`user_version = 3`), a new baseline that a fresh
installation creates in one step. Pre-release builds created schema versions 1
and 2. No data migration from them is provided: the app reports such a database
as damaged local data and does not change, delete, or recreate it.

Before first launching this build over a pre-release installation, stop Doable
and manually clear its local app data. On Android, clear Doable's storage
through the system app settings. This permanently deletes the installation's
local data; the next launch creates a fresh database with schema version 3.

Before rolling back to a build without schema version 3, stop Doable and
manually clear local app data again if this build has created a database: the
earlier builds do not open schema version 3. Rolling back the build cannot
restore data already deleted during either cleanup.

## Reproducible generation

The project toolchain is pinned in `mise.toml`: Flutter 3.47.1 (including
Dart 3.13.1), Node.js 26.4.0, OpenSpec 1.12.0, APM 0.28.0, and Lefthook
2.1.9. Dart and Flutter package versions are locked by the committed
`pubspec.lock`.

From a clean checkout, install the declared tools and verify every committed
generated artifact:

```sh
mise install
mise run codegen-check
```

The check resolves Flutter packages without updating the lockfile, regenerates
localizations, Riverpod, AutoRoute, Drift code, the Drift schema snapshot, and
migration helpers, then rejects any tracked diff or untracked file. Ignored
build and cache outputs are excluded by Git. The command does not run project
setup, install local hooks, or read a user-owned `apm_modules` directory.

To update generated artifacts intentionally, run `mise run codegen`, review the
diff, and commit it. The detector itself has an isolated Git-fixture check:

```sh
mise run codegen-check-test
```

## Pull request checks

`mise run --skip-tools check` runs formatting, analysis and functional tests.
CI runs the same parts as parallel jobs: `check:static`, four `check:tests`
shards and `check:process-tests`. To reproduce one shard locally, pass its
zero-based index and the shard count, for example
`mise run --skip-tools check:tests -- 1 4`.

Benchmarks are separate from this command and from automatic test discovery:

```sh
mise run --skip-tools benchmark
```

The single benchmark command discovers all `benchmark/**/*_benchmark.dart`
files, including intention catalog and statistics measurements. The runner
uses Flutter's test engine for the native database and
isolate environment. Its files live under `benchmark/`. By default, each series
runs once without warmups; timings are reported as `smoke`, while incorrect
results still fail the run. This is the normal verification mode.

Only run repeated p95 measurements when explicitly requested. They use 3 warmups
and 40 samples per series, report `withinBudget` or `exceeded`, and can take
several hours:

```sh
mise run --skip-tools benchmark -- \
  --dart-define=BENCHMARK_SAMPLES=40 \
  --dart-define=BENCHMARK_WARMUPS=3
```

Select a profile with the runner's `--plain-name` and a series with the
`BENCHMARK_CASE` regular expression. Case names contain the profile,
`active`/`archived`, `month`/`year`, the view (where applicable), and the series
or saved-path page offset. For example:

```sh
mise run --skip-tools benchmark -- \
  --plain-name 'бенчмарк раздела: longPaths' \
  --dart-define=BENCHMARK_CASE=longPaths/archived/year/throughRelations/computeRace
```

The fact log benchmark (`--plain-name 'бенчмарк лога фактов'`) builds graphs of
up to 1,000,000 entities and measures memory in separate Flutter processes; its
resident set size measurement reads Linux `/proc`. Its timed series are
`profile/compaction` and `profile/<command>`. The measurement method, results
and budgets are recorded in decision 15 of the `add-graph-export-import` design.

Timing measurements live only in benchmarks. Regular tests have no elapsed-time
measurements or budgets and use the smallest fixtures their assertions need,
such as a few portions beyond the page size instead of production-scale
volumes.

Every pull request must pass the single `Full checks` status. Jobs are selected
from the changed paths:

- project checks — static checks, four test shards and the `flutter_process`
  suites — run for every change except documentation-only or OpenSpec-only
  ones;
- the release APK and packaged Android privacy-manifest check run for
  artifact-impacting changes;
- unclassified paths run every job.

A pull request is classified by its whole diff. A later push is classified by
its own changes only on the first run attempt, when the push extends the
preceding pull request commit and that commit has a trusted successful
`Full checks` run. Re-runs, rewritten history and reopened pull requests use
the whole diff again. Manual and weekly runs always run every job.
