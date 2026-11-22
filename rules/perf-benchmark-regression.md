# perf-benchmark-regression

> Define representative performance contracts and detect regressions using reproducible, complementary measurements rather than a single timing or arbitrary threshold

## Why It Matters

Performance is a property of an implementation, workload, target, compiler and operating conditions together. One small microbenchmark or isolated wall-clock sample can miss an important regression in memory, scaling, latency or resource consumption.

## Establish the Contract

Select a small suite of representative workloads with known inputs, an independent correctness oracle, and explicit measurement boundaries. Include ordinary, edge and stress cases where cost changes with input shape. Separate initialization, parsing, data movement and the hot kernel when those costs matter separately; also measure the complete operation.

Record the toolchain, target, optimization profile, relevant features, input versions, allocator, concurrency and hardware. Check correctness before accepting comparative performance results.

## Choose Metrics That Answer the Question

| Metric | Useful for | Limit |
|---|---|---|
| Instructions / simulated cache costs | Repeatable algorithmic and code-generation regressions | Not actual elapsed time or all microarchitectural effects |
| Allocation count / peak bytes | Ownership and representation changes | May exclude external buffers or allocator overhead |
| Throughput | Bulk processing capacity | Can hide long individual delays |
| Latency distribution | User-visible response and tail behavior | Sensitive to scheduling, load and queueing |
| CPU time, RSS, I/O bytes | System resource efficiency | Attribute costs carefully across threads and processes |

Use controlled wall-clock benchmarking for target-realistic performance.
Complement it with instruction counts (e.g. Callgrind where supported) and
allocation measurements when they explain a regression. Do not assume an
instruction-count improvement implies a matching speed improvement.

## CI and Regression Investigation

- Use stable workload data and a reproducible baseline from the intended reference revision. Keep changes in hardware or compiler explicit.
- Establish noise by repeated baseline runs before choosing any threshold. For noisy measurements, report distributions or confidence intervals; use repeated paired comparisons where practical.
- Test release builds with the same flags and semantics. Keep checks, error paths and accuracy requirements consistent.
- Archive small machine-readable results and input identifiers in the project's artifact location; avoid large unbounded per-commit output.
- For an unexpected change, isolate the affected benchmark, inspect profiles or generated code, and reproduce before altering policy. Run the broader suite for final regressions.
- Use hard regression gates only where the metric and execution environment are reliable enough for the required budget. A threshold is a project decision, not a universal percentage.

Benchmark construction and destruction deliberately. A benchmark that creates
a runtime, allocates a buffer or generates input each iteration measures
that work too. If it is not part of the contract, separate it from the
timed operation. Do not benchmark a different algorithm just because it
is easier to invoke.

## See Also

- [test-criterion-bench](./test-criterion-bench.md)
- [perf-black-box-bench](./perf-black-box-bench.md)
- [perf-profile-first](./perf-profile-first.md)
- [test-independent-oracle](./test-independent-oracle.md)
- [Rust Performance Book](https://nnethercote.github.io/perf-book/)
