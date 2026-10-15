### Test execution scope

These stage-specific rules take precedence over generic test-suite requirements in development skills.

- While writing or fixing code, run the specific tests that verify the behavior being changed.
- Before completing an implementation task, run only the tests for the changed modules and their directly affected consumers.
- Before completing a plan phase, run the full project checks with `mise run check`.
- Do not launch or require an emulator or physical device to complete an implementation task or plan phase. Verify with automated tests, static analysis, and builds that do not require them, even when an existing task or design calls for device checks.
- The user performs device checks later on their own device. Provide the build artifact and state which manual checks remain unverified; their absence is not a completion blocker and does not prove that a device-specific defect is fixed.
