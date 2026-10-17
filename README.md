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

The remaining eight `slow` suites were reviewed when benchmarks were separated:

| Suite | Checks retained in regular tests |
| --- | --- |
| Intention catalog large fixture | Complete keyset traversal, bounded reads, tag filtering and reconciliation; repeated latency measurements moved to `benchmark/` |
| Daily choice read cost | Path preservation, bounded page reads, startup reads and a responsive event loop during worker-isolate SQL |
| Relation group large fixture | Ordering, archive scopes, batched selection and command/revision consistency |
| Tag catalog read cost | Complete snapshot without omissions |
| Tag assignment read cost | Complete assignment and selection snapshots |
| Tagged entities read cost | Complete ordered traversal and bounded materialization |
| Tag assignment widget read cost | Loaded contents and usable scrolling |
| Tag navigation widget read cost | Pagination, bounded mounted rows and consistent refresh after mutations |

These functional checks retain `slow` because of their fixtures or traversal
work. They have no repeated timing measurements or elapsed-time budgets.

Every pull request must pass the single `Full checks` status. Project checks
always run, while the release APK and packaged Android privacy-manifest check
run for artifact-impacting or unclassified changes. A documentation-only,
OpenSpec-only, or isolated Dart/test-only update may skip that Android job only
after the preceding pull request commit has a trusted successful `Full checks`
run; manual and weekly runs always include the Android evidence.
