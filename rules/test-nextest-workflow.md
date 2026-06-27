# test-nextest-workflow

> Use `cargo-nextest` for faster execution and CI partitioning

## Why It Matters

`cargo-nextest` runs tests up to 3× faster than `cargo test` by using a per-process test model: each test runs in its own process (no shared state corruption), with pipelined output, structured reporting, and built-in CI partitioning. It's the recommended test runner for CI, with native support in RustRover and most CI platforms.

## Setup

```bash
# Install
cargo install cargo-nextest
```

```toml
# .config/nextest.toml
[profile.default]
# Fail fast — stop after first failure
fail-fast = true

# Retry flaky tests
retries = 2

# Display output per test
status-level = "pass,fail"

[store]
# Separate snapshot directory from cargo test
dir = "target/nextest"
```

## Basic Usage

```bash
# Run all tests
cargo nextest run

# Run with specific profile
cargo nextest run --profile ci

# List tests without running
cargo nextest list

# Show slowest tests
cargo nextest run --slow-timeout 60s
```

## Expression Filtering

```bash
# Run only integration tests
cargo nextest run -E 'test(type = integration)'

# Run tests by name pattern
cargo nextest run -E 'test(//my_test)'
cargo nextest run -E 'test(/parse_invalid/)'

# Combine filters
cargo nextest run -E 'test(/api/) and test(type = integration)'

# Exclude flaky tests
cargo nextest run -E 'not test(/flaky/)'
```

## CI Partitioning

```bash
# Split tests into 4 equal partitions (run each on separate CI job)
cargo nextest run --partition hash:1/4  # Job 1
cargo nextest run --partition hash:2/4  # Job 2
cargo nextest run --partition hash:3/4  # Job 3
cargo nextest run --partition hash:4/4  # Job 4

# Count-based partitioning (more balanced)
cargo nextest run --partition count:1/4

# Each job takes ~25% of tests, running in parallel
```

## JUnit Output

```toml
# .config/nextest.toml
[profile.ci]
fail-fast = false
retries = 0

[profile.ci.junit]
path = "junit.xml"
report-name = "nextest-ci"
```

```bash
cargo nextest run --profile ci
# Produces junit.xml for CI dashboards
```

## Integration Test Focus

```bash
# Run only integration tests in tests/ directory
cargo nextest run -E 'test(type = integration)'

# Run a specific test file
cargo nextest run -E 'test(/my_integration_test/)'

# Combine with crate filter
cargo nextest run -p my-crate -E 'test(type = integration)'
```

## With insta Snapshots

```toml
# .config/nextest.toml
[store]
dir = "target/nextest"  # Keep nextest artifacts separate
```

```bash
cargo nextest run && cargo insta test --accept
```

## Configuration Profiles

```toml
# .config/nextest.toml
[profile.default]
fail-fast = true
status-level = "pass,fail"
failure-output = "immediate"

[profile.ci]
fail-fast = false
retries = 0
status-level = "skip,pass,fail"
failure-output = "final"

# JUnit for CI
[profile.ci.junit]
path = "junit.xml"
report-name = "nextest-ci"

# Test partitioning for CI matrix
# Used with: cargo nextest run --profile ci --partition hash:1/4
```

## See Also

- [test-cfg-test-module](./test-cfg-test-module.md) — Unit test module conventions
- [test-integration-dir](./test-integration-dir.md) — Integration test structure
- [test-rstest-fixtures](./test-rstest-fixtures.md) — Parameterized tests and fixtures

## References

- [cargo-nextest documentation](https://nexte.st/)
- [Nextest with RustRover](https://blog.jetbrains.com/rust/2026/05/01/faster-rust-tests-with-cargo-nextest/)
- [test-integration-dir](./test-integration-dir.md) — Integration test structure
- [test-insta-snapshot](./test-insta-snapshot.md) — Snapshot testing with nextest
