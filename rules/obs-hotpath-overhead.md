# obs-hotpath-overhead

> Measure both enabled and disabled telemetry costs; aggregate bounded, high-rate observations without hiding necessary diagnostic or audit information

## Why It Matters

Structured events can be much easier AND cheaper to consume than allocating
formatted messages, but they are not free. Enabled spans and events may
format values, take locks, allocate, enqueue data or perform I/O. Even
disabled events can incur work if expensive fields are computed before
the logging call.

## Good: Report One Bounded Batch

<!-- rust-check: compile -->
```rust
fn summarize_batch(batch: &[u32]) -> u64 {
    let total: u64 = batch.iter().map(|&value| u64::from(value)).sum();
    tracing::debug!(items = batch.len(), total, "batch processed");
    total
}
```

When per-item tracing is actually required, keep it at an appropriate level,
avoid eagerly building a separate formatted string, and use a deliberately
configured subscriber. Put expensive diagnostic-only preparation behind
an appropriate enabled check, while recognizing that a subscriber may
apply further field/event filtering. Do not use a logging filter to guard
business logic or required side effects.

## Design and Measure

- Choose cheap numeric counters, useful distributions and bounded-cardinality dimensions for aggregate metrics.
- Preserve correlation and individual causal events where they are necessary to diagnose errors, audit operations or meet the actual contract. Sampling is a deliberate loss policy, not a default for required records.
- Bound asynchronous telemetry queues and state what happens on overload: dropping, backpressure, synchronous delivery or another explicit strategy. Do not introduce an unbounded allocation path merely to keep a producer fast.
- Avoid logging arbitrarily long payloads and sensitive values. Dynamic labels and span fields can retain considerable memory.
- Compare with telemetry disabled and enabled at realistic production levels, using the real subscriber, formatter, sink and concurrency. Measure CPU, allocations, throughput, latency and missed/dropped events.

## See Also

- [obs-structured-fields](./obs-structured-fields.md)
- [obs-instrument-spans](./obs-instrument-spans.md)
- [obs-no-sensitive-data](./obs-no-sensitive-data.md)
- [perf-benchmark-regression](./perf-benchmark-regression.md)
- [tracing::enabled](https://docs.rs/tracing/latest/tracing/macro.enabled.html)
