### Timing belongs to benchmarks

- Measure elapsed time, latency, or throughput only in `benchmark/**/*_benchmark.dart`. Regular tests contain no stopwatches, timing output, or time budgets, even when a plan, task, or specification asks for a measurement inside a test.
- Keep regular tests fast. Size fixtures for the assertion, not for realism: use the smallest data that crosses the boundary under test, such as a few portions beyond the page size or one item past a limit. Heavy workloads belong in benchmarks.
- A regular test must not need an extended timeout. If it does, shrink its data or move the workload to a benchmark.
