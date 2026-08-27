# perf-collect-once

> Keep iterator pipelines lazy until you actually need an owned collection; materialize intermediate results when their semantics justify it

## Why It Matters

Collecting an iterator into `Vec`, `String`, `HashMap`, or another owned collection can require allocation and an additional materialized data structure. Avoiding an intermediate collection can reduce memory traffic when the next operation can consume the iterator directly.

But `.collect()` is not synonymous with “exactly one allocation,” and intermediate materialization is not inherently wrong. Allocation behavior depends on the destination collection and iterator size hints, while sorting, indexing, repeated traversal, ownership boundaries, or API requirements may make a concrete collection exactly the right tool.

## Fuse Simple One-Pass Transformations

When every step can remain streaming, one lazy pipeline is usually clearer and avoids temporary vectors:

```rust
#[derive(Debug)]
struct User {
    name: String,
    active: bool,
    verified: bool,
}

fn active_verified_names(users: Vec<User>) -> Vec<String> {
    users
        .into_iter()
        .filter(|user| user.active)
        .filter(|user| user.verified)
        .map(|user| user.name)
        .collect()
}

fn main() {
    let users = vec![
        User { name: "Ada".into(), active: true, verified: true },
        User { name: "Bob".into(), active: true, verified: false },
    ];
    assert_eq!(active_verified_names(users), ["Ada"]);
}
```

This avoids separate `active` and `verified` vectors because neither is needed as a value in its own right.

## Use Iterator Consumers Instead of Collecting Just to Ask a Question

```rust
fn count_even(values: &[i32]) -> usize {
    values.iter().filter(|value| **value % 2 == 0).count()
}

fn any_negative(values: &[i32]) -> bool {
    values.iter().any(|value| *value < 0)
}

fn main() {
    assert_eq!(count_even(&[1, 2, 4]), 2);
    assert!(any_negative(&[1, -1, 2]));
}
```

`count`, `any`, `all`, `find`, `sum`, `fold`, and similar consumers can often answer the real question without building a temporary collection.

## Intermediate Collections Are Correct When You Need Their Capabilities

Sorting requires mutable owned storage:

```rust
fn sorted_positive(values: &[i32]) -> Vec<i32> {
    let mut result: Vec<_> = values.iter().copied().filter(|value| *value > 0).collect();
    result.sort_unstable();
    result
}

fn main() {
    assert_eq!(sorted_positive(&[3, -1, 1, 2]), [1, 2, 3]);
}
```

Likewise, materialize when you need random access, stable ownership independent of the source, mutation, deduplication, repeated traversal, or an API that requires a slice/collection.

## Directly Iterate Map Views When No Snapshot Is Needed

Collecting a `HashMap` view only to immediately loop over it adds a temporary vector with no semantic benefit:

```rust
use std::collections::HashMap;

fn total_values(map: &HashMap<&str, i32>) -> i32 {
    map.values().copied().sum()
}

fn main() {
    let map = HashMap::from([("a", 2), ("b", 3)]);
    assert_eq!(total_values(&map), 5);
}
```

By contrast, collecting values is reasonable if you need a snapshot that can be sorted or retained independently of the iterator traversal.

## Allocation Counts Are Not a Source-Level Guarantee

Do not write tables claiming:

- every `.collect::<Vec<_>>()` performs exactly one allocation;
- a lazy iterator always uses `O(1)` memory in the entire algorithm;
- `N` intermediate collects imply exactly `N` allocations;
- `Vec::with_capacity(n)` guarantees the final operation will never reallocate.

A `Vec` may reserve based on iterator size hints and may grow if the estimate is insufficient. Other collection types have different representations and allocation strategies.

## Pre-Allocate When You Have a Useful Bound

If an upper bound is cheap and useful, explicit capacity can reduce growth:

```rust
fn copy_nonzero(values: &[u8]) -> Vec<u8> {
    let mut result = Vec::with_capacity(values.len());
    result.extend(values.iter().copied().filter(|value| *value != 0));
    result
}

fn main() {
    assert_eq!(copy_nonzero(&[0, 1, 0, 2]), [1, 2]);
}
```

`with_capacity(values.len())` requests space for **at least** that many elements. Here it is an upper bound on the filtered result, but reserving the full input size can waste memory if very few elements survive. Measure important cases.

## Fixed-Size Slice APIs Avoid Temporary Collections When Their Semantics Fit

Rust 1.88 stabilized `slice::as_chunks`, which exposes non-overlapping const-sized arrays plus a remainder:

```rust
fn pair_sums(values: &[i32]) -> (Vec<i32>, &[i32]) {
    let (pairs, remainder) = values.as_chunks::<2>();
    let sums = pairs.iter().map(|&[a, b]| a + b).collect();
    (sums, remainder)
}

fn main() {
    let (sums, remainder) = pair_sums(&[1, 2, 3, 4, 5]);
    assert_eq!(sums, [3, 7]);
    assert_eq!(remainder, [5]);
}
```

Rust 1.94 stabilized `slice::array_windows` for overlapping const-sized windows. These APIs are useful because of their fixed-array semantics, not because Rust promises “zero bounds-check overhead” for every surrounding computation.

## Deferred Collection Keeps the Caller Flexible

When the lifetime/ownership model permits it, returning an iterator can let callers choose whether to collect:

```rust
fn nonzero(values: &[u8]) -> impl Iterator<Item = u8> + '_ {
    values.iter().copied().filter(|value| *value != 0)
}

fn main() {
    let values = [0, 1, 2, 0];
    assert_eq!(nonzero(&values).sum::<u8>(), 3);
    let owned: Vec<_> = nonzero(&values).collect();
    assert_eq!(owned, [1, 2]);
}
```

Do not force an iterator return when a concrete collection is part of the API contract or the iterator would make lifetimes/implementation evolution unnecessarily awkward.

## Practical Guidance

- Avoid temporary collections that exist only to feed the next one-pass iterator operation.
- Use terminal iterator methods directly when they answer the question.
- Materialize when sorting, indexing, mutation, repeated traversal, ownership, or an API boundary requires it.
- Treat allocation counts as implementation/workload details, not syntax-level guarantees.
- Reserve capacity only when you have a useful estimate and the memory trade-off is acceptable.
- Use fixed-size slice APIs when their semantics match the problem, not as generic “faster iterator” replacements.

## See Also

- [perf-iter-lazy](./perf-iter-lazy.md) - Lazy iterator evaluation
- [mem-with-capacity](./mem-with-capacity.md) - Capacity reservation
- [anti-collect-intermediate](./anti-collect-intermediate.md) - Avoiding unnecessary intermediate collections
