# Doable

Doable is an Android-first Flutter application for preserving intentions and,
through the planned intention graph, connecting them to meaningful daily
actions. The current implementation provides the complete local lifecycle of
an intention: creation, bounded catalog browsing, editing, explicit action
readiness, archiving, restoration, deletion, Russian and English localization,
and persistence within one application installation.

The product model is maintained in
[`docs/discussions/action-centered-goal-system.md`](docs/discussions/action-centered-goal-system.md),
and the implementation sequence is maintained in
[`docs/discussions/development-change-sequence.md`](docs/discussions/development-change-sequence.md).

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

Every pull request must pass the single `Full checks` status. Project checks
always run, while the release APK and packaged Android privacy-manifest check
run for artifact-impacting or unclassified changes. A documentation-only,
OpenSpec-only, or isolated Dart/test-only update may skip that Android job only
after the preceding pull request commit has a trusted successful `Full checks`
run; manual and weekly runs always include the Android evidence.
