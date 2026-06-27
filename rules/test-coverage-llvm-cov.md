# test-coverage-llvm-cov

> Use `cargo-llvm-cov` for LLVM-based code coverage

## Why It Matters

LLVM source-based code coverage provides accurate, region-level coverage data across all platforms (Linux, macOS, Windows). It tracks every branch, expression, and line, with color-coded HTML reports. `cargo-llvm-cov` wraps LLVM's native coverage instrumentation — it's faster, more accurate, and better maintained than `tarpaulin` (now Linux-only legacy).

## Setup

```bash
# Install
cargo install cargo-llvm-cov
```

## Basic Usage

```bash
# Generate coverage report
cargo llvm-cov

# Generate HTML report (open in browser)
cargo llvm-cov --open

# Generate lcov.info for CI upload
cargo llvm-cov --lcov --output-path lcov.info

# Generate cobertura XML (GitLab CI)
cargo llvm-cov --cobertura --output-path cobertura.xml
```

## Running with Tests

```bash
# Run all tests with coverage
cargo llvm-cov --all-targets

# Run specific tests with coverage
cargo llvm-cov --test integration_test

# Run with nextest
cargo llvm-cov nextest

# Exclude test code from coverage
cargo llvm-cov --ignore-filename-regex "tests?/"
```

## CI Integration

```yaml
# .github/workflows/ci.yml
- name: Install cargo-llvm-cov
  uses: taiki-e/install-action@cargo-llvm-cov

- name: Generate code coverage
  run: cargo llvm-cov --lcov --output-path lcov.info

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: lcov.info
```

## Coverage Configuration

```toml
# .config/llvm-cov.toml
[lcov]
# Only show coverage for these paths
include = ["src/"]

# Exclude generated code
exclude = ["src/generated/"]

# Set minimum coverage threshold (CI will fail below this)
# Used with: cargo llvm-cov --fail-under-lines 80
```

## HTML Report

```bash
cargo llvm-cov --html --output-dir coverage/

# Open coverage/index.html in browser
# Shows per-file, per-function, per-line coverage
# Color-coded: green (covered), red (uncovered), yellow (partial)
```

## With Workspaces

```bash
# Coverage for entire workspace
cargo llvm-cov --workspace

# Coverage for specific packages
cargo llvm-cov --package my-crate

# Merge coverage from multiple runs
cargo llvm-cov --report --lcov --output-path lcov.info
```

## See Also

- [test-criterion-bench](./test-criterion-bench.md) — Benchmarking with criterion
- [test-nextest-workflow](./test-nextest-workflow.md) — Running tests with nextest
- [test-mockall-mocking](./test-mockall-mocking.md) — Trait mocking with mockall

## References

- [cargo-llvm-cov GitHub](https://github.com/taiki-e/cargo-llvm-cov)
- [LLVM Source-based Code Coverage](https://clang.llvm.org/docs/SourceBasedCodeCoverage.html)
- [test-nextest-workflow](./test-nextest-workflow.md) — Running with nextest
