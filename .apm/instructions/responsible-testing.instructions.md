### Responsible testing

A test is a cost until it earns its place: it adds runtime, review effort, and friction to every future refactor. Write a test only when its absence would let a plausible, costly regression go unnoticed. Coverage, symmetry with neighboring tests, and the existence of a spec scenario are not reasons on their own. Before adding a test, name the regression it catches; if you cannot, do not write it.

#### Test behavior, not state

- Drive the code through its public interface — user actions, public API, repository contract — and assert what a user or consumer can observe: visible text and semantics, persisted and read data, returned results and failures.
- Do not assert widget keys or tree shape, pixel geometry without a stated layout requirement, object identity, internal fields of view-model or snapshot state, revision, epoch, or claim tokens, call counts or order, SQL text, or statement counts.
- A test that breaks on a behavior-preserving refactor checks implementation. Rewrite it against behavior, or delete it when the behavior is covered elsewhere; do not adjust it to the new internals.

#### Test each behavior once

- Test a behavior at the cheapest level where it is observable. Do not repeat a scenario across view-model, page, and app tests; add a higher-level test only for wiring that lower levels cannot show, and keep one end-to-end path per user flow.
- Test a shared mechanism — diagnostics sink, command coordinator, shared widget, error classifier — once at its own boundary, not again at every call site or for every command kind.
- Prove durability, crash safety, and rollback once per storage mechanism, not once per operation.
- A spec scenario needs one test that shows it, not one per layer.

#### Do not write tests that

- Restate what the compiler, the language, or a framework guarantees: constructors, getters, equality, `hashCode`, `toString`, sealed or enum exhaustiveness, unmodifiable collections, constants.
- Exercise fakes, fixtures, or test helpers instead of product code.
- Build states the product cannot reach, such as rows written with schema constraints disabled or a repository breaking its own contract. When such a state is real, for example on-disk corruption, test recovery from it once.
- Enumerate combinatorial matrices — locale, text scale, screen size, timing, failure point — whose dimensions do not change the code path. Pick representative cases: the default, the boundary, and the case that actually differs.
- Chase race or timing orders that the architecture already rules out, for example commands serialized by one executor.
- Measure performance without asserting a threshold. When a cost requirement exists, assert the user-relevant bound, such as page size or a time budget, not the query shape.

This rule decides what to test; `test-driven-development` decides how. Its red-green-refactor cycle applies to tests that pass this rule, and this rule overrides that skill's advice to test simple code because it may grow complicated.
