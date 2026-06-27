# test-fuzzing-minimal

> Use `cargo-fuzz` for fuzz testing critical functions

## Why It Matters

Fuzz testing generates random inputs to find crashes, panics, or invariant violations in parsing, deserialization, and input-processing functions. `cargo-fuzz` (libFuzzer-based) is significantly faster than naive random testing — it uses coverage guidance to explore new code paths, reaching deep edge cases that property-based testing might miss. Ideal for security-critical and parser code.

## Setup

```bash
# Install
cargo install cargo-fuzz

# Initialize fuzz targets directory
cargo fuzz init
```

Creates `fuzz/Cargo.toml` and `fuzz/fuzz_targets/` directory.

## Basic Fuzz Target

```rust
// fuzz/fuzz_targets/parse_config.rs
#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Convert to string (ignore non-UTF-8 inputs)
    if let Ok(input) = std::str::from_utf8(data) {
        // fuzz_target! catches panics automatically
        let _ = parse_config(input);
    }
});
```

## Running

```bash
# Run fuzzer (infinite until crash found)
cargo fuzz run parse_config

# Run with specific number of iterations
cargo fuzz run parse_config -- -runs=100000

# Run with corpus directory
cargo fuzz run parse_config -- corpus/

# Minimize a crash input
cargo fuzz fmt parse_config crash-<hash>
```

## Structured Input Fuzzing

```rust
// fuzz/fuzz_targets/from_json.rs
#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Fuzz JSON deserialization
    if let Ok(json_str) = std::str::from_utf8(data) {
        // serde_json will panic on malformed input if not handled
        let _ = serde_json::from_str::<Config>(json_str);
    }
});
```

## With Arbitrary

```rust
// fuzz/fuzz_targets/arbitrary_struct.rs
#![no_main]

use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

#[derive(Arbitrary, Debug)]
struct UserInput {
    name: String,
    age: u8,
    email: String,
}

fuzz_target!(|input: UserInput| {
    // Fuzzer generates structured UserInput values
    let _ = process_user(&input);
});
```

## Crash Management

```bash
# Find crash artifacts
ls fuzz/artifacts/parse_config/

# Reproduce a crash
cargo fuzz run parse_config fuzz/artifacts/parse_config/crash-<hash>

# Build release version for faster fuzzing
cargo fuzz build --release
cargo fuzz run parse_config --release
```

## Corpus Management

```bash
# Seed corpus with known valid inputs
mkdir -p fuzz/corpus/parse_config
cp tests/fixtures/*.toml fuzz/corpus/parse_config/

# Merge new findings into corpus
cargo fuzz run parse_config -- -merge=1 fuzz/corpus/parse_config
```

## CI Integration

```yaml
# .github/workflows/fuzz.yml
- name: Fuzz testing
  run: |
    cargo fuzz run parse_config -- -runs=50000
    cargo fuzz run from_json -- -runs=50000
```

## When to Fuzz

```rust
// ✅ Good candidates for fuzzing:
// - Parsers (JSON, XML, custom formats)
// - Deserialization functions
// - Network protocol handlers
// - Input validation logic
// - Cryptographic or security-sensitive code

// ❌ Poor candidates:
// - Business logic without input parsing
// - Functions with constrained input domains
// - Code easily covered by unit tests
```

## See Also

- [test-proptest-properties](./test-proptest-properties.md) — Property-based testing alternative
- [test-tokio-async](./test-tokio-async.md) — Async testing with tokio::test
- [test-nextest-workflow](./test-nextest-workflow.md) — Running tests with nextest

## References

- [cargo-fuzz GitHub](https://github.com/rust-fuzz/cargo-fuzz)
- [libFuzzer documentation](https://llvm.org/docs/LibFuzzer.html)
- [arbitrary crate](https://crates.io/crates/arbitrary)
- [test-proptest-properties](./test-proptest-properties.md) — Property-based testing alternative
