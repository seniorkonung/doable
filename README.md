# doable

A new Flutter project.

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
