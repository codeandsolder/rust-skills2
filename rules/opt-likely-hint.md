# opt-likely-hint

> Use measured branch-probability hints when ordinary code and profiles do not already convey the useful information

## Why It Matters

A branch-probability hint describes an expected workload, not an invariant
of program execution. The optimizer may use it for block layout or other
decisions. It does not force the CPU's dynamic branch predictor or guarantee
an instruction sequence.

## Good: Stable Cold Path

Since Rust 1.95, `core::hint::cold_path()` marks the path reaching the call
as unlikely. It is often sufficient without defining Boolean hint wrappers.

```rust
fn parse_port(value: &str) -> Result<u16, std::num::ParseIntError> {
    let result = value.parse();
    if result.is_err() {
        core::hint::cold_path();
    }
    result
}
```

Only mark the error path cold if the real workload makes it rare.

## Nightly: Direct Boolean Hints

On Rust 1.102.0-nightly the direct `core::hint::likely` and
`core::hint::unlikely` functions require `likely_unlikely`. Use the native
API when the project already accepts nightly and a Boolean hint improves the
code. Do not add custom compatibility wrappers solely to mimic it.

<!-- rust-check: nightly(likely_unlikely); reason=native Boolean branch hints are unstable -->
```rust
#![feature(likely_unlikely)]

fn first_occurrence(data: &[u8], target: u8) -> Option<usize> {
    for (index, &item) in data.iter().enumerate() {
        // Appropriate only when matching is rare across iterations.
        if core::hint::unlikely(item == target) {
            return Some(index);
        }
    }
    None
}

fn main() {
    assert_eq!(first_occurrence(&[], 9), None);
    assert_eq!(first_occurrence(&[1, 9, 9], 9), Some(1));
    assert_eq!(first_occurrence(&[1, 2], 9), None);
}
```

## Unpredictable Is Not Unlikely

A mostly-false condition is often predictable. A nearly balanced condition
may be hard to predict, depending on its correlation and history.
For the latter, `select_unpredictable` is stable since Rust 1.88;
see [opt-select-unpredictable](./opt-select-unpredictable.md) for a tested
search example and the limits of the hint.

## Avoid Guessing From Control-Flow Shape

Early returns do not mean unlikely; putting a branch first does not
guarantee that the compiler marks it hot. Reordering match arms can even
change semantics when patterns overlap. Order arms for correctness and
clarity, not presumed branch prediction.

When important branch behavior is unknown, measure it with representative
inputs. Profile-guided optimization can provide richer information than
handwritten hints. Preserve hints only if the measured effect is useful.

## See Also

- [opt-cold-path](./opt-cold-path.md) — inline cold paths
- [opt-cold-unlikely](./opt-cold-unlikely.md) — cold helpers
- [opt-select-unpredictable](./opt-select-unpredictable.md) — value selection
- [perf-hint-apis](./perf-hint-apis.md) — hint API contracts
- [perf-profile-first](./perf-profile-first.md) — measurement
