# perf-chain-avoid

> Use `Iterator::chain` when it expresses the traversal clearly; split or materialize only when measurement shows the chained iterator is a bottleneck

## Why It Matters

`Iterator::chain` represents two iterators as one lazy iterator. At the abstract API level it must know whether the first iterator still has items, but source-level descriptions such as “exactly one extra branch per item” are not reliable descriptions of optimized machine code. LLVM may inline, specialize, simplify, or restructure the iterator state.

Do not ban `.chain()` from hot code by rule. Benchmark the actual loop. Separate loops can sometimes generate better code, but they can also duplicate logic or make short-circuiting and composition less clear.

## Idiomatic Chaining

For one pass over two collections, `.chain()` is concise and allocation-free:

```rust
fn sum_both(a: &[i32], b: &[i32]) -> i64 {
    a.iter()
        .chain(b)
        .map(|&value| i64::from(value))
        .sum()
}

fn main() {
    assert_eq!(sum_both(&[1, 2], &[3, 4]), 10);
}
```

The chained iterator itself does not concatenate the inputs or allocate a new collection.

## Separate Loops Are a Valid Measured Alternative

If a profile or code-generation inspection shows the chained state matters in a very hot loop, separate loops are easy to compare:

```rust
fn sum_separate(a: &[i32], b: &[i32]) -> i64 {
    let mut sum = 0_i64;

    for &value in a {
        sum += i64::from(value);
    }
    for &value in b {
        sum += i64::from(value);
    }

    sum
}

fn main() {
    assert_eq!(sum_separate(&[1, 2], &[3, 4]), 10);
}
```

Do not call the separate version “branch-free” as a language-level fact. Loop control still exists, and optimized code depends on the compiler, target, and surrounding operations.

## `chain` Works Well with Short-Circuiting

Lazy composition is especially useful when later operations may stop early:

```rust
#[derive(Debug)]
struct Item {
    id: u32,
}

fn find_in_either<'a>(a: &'a [Item], b: &'a [Item], target: u32) -> Option<&'a Item> {
    a.iter().chain(b).find(|item| item.id == target)
}

fn main() {
    let a = [Item { id: 1 }];
    let b = [Item { id: 2 }];
    assert_eq!(find_in_either(&a, &b, 2).map(|item| item.id), Some(2));
}
```

Materializing `a` and `b` into a third collection would add work and memory without helping this use case.

## Stable API Status

`Iterator::chain` has long been stable. The separate free function `std::iter::chain(a, b)` / `core::iter::chain(a, b)` is **still nightly-only in Rust 1.98** under the `iter_chain` feature. On stable Rust, use the method form:

```rust
fn collect_all(a: &[u8], b: &[u8]) -> Vec<u8> {
    a.iter().copied().chain(b.iter().copied()).collect()
}

fn main() {
    assert_eq!(collect_all(&[1, 2], &[3]), [1, 2, 3]);
}
```

Do not attach a stable-version claim to the free function until it actually stabilizes.

## Materialize Once Only When Repeated Traversal Needs It

If the same combined sequence is traversed repeatedly and owning a combined buffer fits the semantics, materializing once can be reasonable:

```rust
fn merge(a: &[u8], b: &[u8]) -> Vec<u8> {
    let mut merged = Vec::with_capacity(a.len() + b.len());
    merged.extend_from_slice(a);
    merged.extend_from_slice(b);
    merged
}

fn main() {
    let merged = merge(&[1, 2], &[3, 4]);
    assert_eq!(merged.iter().sum::<u8>(), 10);
    assert_eq!(merged.len(), 4);
}
```

This trades an allocation/copy for a simpler contiguous representation. It is not automatically faster than chaining; the answer depends on reuse count, data size, cache effects, and the work done per element.

## `Vec::append` Has Capacity-Dependent Allocation Behavior

When ownership of two vectors is available, `append` moves elements from one vector into the other:

```rust
fn combine_vecs(mut a: Vec<i32>, mut b: Vec<i32>) -> Vec<i32> {
    a.append(&mut b);
    a
}

fn main() {
    assert_eq!(combine_vecs(vec![1, 2], vec![3, 4]), [1, 2, 3, 4]);
}
```

`append` may need to grow `a` if its capacity is insufficient. Do not promise “no reallocation” without knowing the capacity.

## Do Not Replace `chain` with Unrelated Iterator APIs

`array_windows`, `chunk_by`, and `flat_map` solve different traversal problems. They are not generic performance replacements for chaining two sequences. Choose them when their **semantics** match the operation, not to avoid the word `chain`.

Likewise, replacing a simple chain with `flat_map` can produce equivalent semantics but is not inherently faster.

## Benchmark the Actual Kernel

If chained traversal appears in a hot kernel, compare:

- `.chain()`;
- two explicit loops;
- one pre-materialized contiguous collection if it will be reused;
- any domain-specific representation that avoids repeated traversal entirely.

Use representative sizes and targets. Inspect generated assembly if the claimed win depends on branch elimination or vectorization.

## Practical Guidance

- Prefer `.chain()` when it clearly expresses one lazy traversal over multiple sequences.
- Keep `.chain()` for short-circuiting pipelines unless measurement says otherwise.
- Use separate loops when they are clearer or benchmark better in a critical kernel.
- Materialize only when ownership/reuse semantics justify the allocation and copy.
- Remember that the free `iter::chain` function remains nightly-only on Rust 1.98.
- Never assign fixed branch counts or performance rankings from source syntax alone.

## See Also

- [perf-iter-over-index](./perf-iter-over-index.md) - Iterator traversal guidance
- [perf-extend-batch](./perf-extend-batch.md) - Extending collections efficiently
- [perf-profile-first](./perf-profile-first.md) - Measure before optimizing
