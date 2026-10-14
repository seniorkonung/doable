### Test execution scope

These stage-specific rules take precedence over generic test-suite requirements in development skills.

- While writing or fixing code, run the specific tests that verify the behavior being changed.
- Before completing an implementation task, run only the tests for the changed modules and their directly affected consumers.
- Before completing a plan phase, run the full project checks with `mise run check`.
