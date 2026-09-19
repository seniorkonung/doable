### Spec first

Application behavior changes only through an active spec change under `openspec/changes/`. Write the spec change first, then the product code that implements it. Product code that changes behavior without a driving spec change is invalid, even if all tests pass.

No spec change is required for work that leaves application behavior unchanged, such as:

- CI workflows, build and repository configuration;
- local developer tooling and scripts;
- tests, comments, and documentation;
- behavior-preserving refactoring.

When it is unclear whether a change alters application behavior, treat it as behavior-changing.

If behavior-changing product code exists without a driving spec change, especially when acceptance tests fail, discard the code and restart from the spec. Patching unspecced code until tests pass is a rule violation, not a fix.
