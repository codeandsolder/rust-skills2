# test-independent-oracle

> Derive expected behavior from an independent specification, reference implementation, known result, or meaningful property rather than duplicating the implementation under test

## Why It Matters

A passing test is evidence only if it would fail when the behavior is wrong. Copying a formula, parser branch, or table from the implementation into the expected-value calculation can preserve the same mistake on both sides. Coverage and round-trip tests alone do not establish semantic correctness.

## Bad: Shared Logic Disguised as a Test

Testing an optimized search against another copy of its midpoint update will reproduce its off-by-one or duplicate-element bugs. Likewise, a codec can round-trip successfully while both encoder and decoder disagree with the external format.

## Good: Use a Simpler Independent Oracle

<!-- rust-check: run -->
```rust
fn lower_bound(sorted: &[i32], needle: i32) -> usize {
    sorted.partition_point(|&value| value < needle)
}

fn main() {
    for length in 0..=64 {
        let data: Vec<i32> = (0..length).map(|i| i / 3 - 8).collect();
        for needle in -10..=16 {
            let expected = data.iter().position(|&value| value >= needle)
                .unwrap_or(data.len());
            let actual = lower_bound(&data, needle);
            assert_eq!(actual, expected, "{data:?}, needle={needle}");
            assert!(data[..actual].iter().all(|&value| value < needle));
            assert!(data[actual..].iter().all(|&value| value >= needle));
        }
    }
}
```

The reference traverses linearly and shares neither the search algorithm nor
its boundary calculations. The additional partition property is derived
from the contract. Empty slices, duplicates, exact hits and both out-of-range
directions are exercised. For an actual optimized implementation, call it
directly rather than reproducing it in the test.

## Choose Evidence by Domain

- Use published vectors and independent decoders for formats and protocols; round-trip tests are supplemental.
- For numerical code, compare a higher-precision or independently formulated reference with a justified tolerance and nonfinite-value policy. Test difficult inputs, not only uniformly random values.
- For rewrites, use an independently maintained original implementation plus specification cases; historical behavior is evidence, not an obligation to preserve known defects.
- For state machines, test observable state transitions and side effects against an independent model, including failed and cancelled operations.
- For regression tests, demonstrate that the original defect causes failure; avoid assertions that only check that execution reached the end.

An invariant may itself be wrong or insufficient. Use multiple complementary
properties and explicit counterexamples. A fixed expected value is useful
when derived from an external contract; testing a private constant against
its own value is not.

## See Also

- [test-proptest-properties](./test-proptest-properties.md)
- [test-fuzzing-minimal](./test-fuzzing-minimal.md)
- [test-mutation-testing](./test-mutation-testing.md)
- [Microsoft Rust Guidelines changelog](https://microsoft.github.io/rust-guidelines/changelog/index.html)
