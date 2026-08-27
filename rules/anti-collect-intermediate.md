# anti-collect-intermediate

> Keep iterator pipelines lazy when materialization adds no semantic value; collect only when you need owned storage, reordering, repeated access, or another collection operation

## Why It Matters

An intermediate collection can add allocation, copying/moving, memory traffic, and an additional traversal boundary. When the next operation can consume the iterator directly, staying lazy is often simpler and cheaper.

But `.collect()` is not inherently wrong, and the `Iterator` trait does not guarantee that every possible collection performs a heap allocation. Materialization can be exactly what the algorithm requires—for sorting, indexing, ownership, reuse, or separating phases.

The useful rule is semantic: **do not materialize merely to immediately iterate the same data again.**

## Fuse Simple Filtering and Mapping

```rust
fn process(data: Vec<i32>) -> Vec<i32> {
    data.into_iter()
        .filter(|value| *value > 0)
        .map(|value| value * 2)
        .filter(|value| *value < 100)
        .collect()
}

fn main() {
    assert_eq!(process(vec![-1, 2, 60, 20]), vec![4, 40]);
}
```

There is no reason here to create separate vectors between the filter and map steps.

## Use Iterator Consumers for Questions About the Stream

```rust
struct Item {
    valid: bool,
    value: i64,
}

fn has_valid(items: &[Item]) -> bool {
    items.iter().any(|item| item.valid)
}

fn sum_valid(items: &[Item]) -> i64 {
    items.iter()
        .filter(|item| item.valid)
        .map(|item| item.value)
        .sum()
}

fn main() {
    let items = [
        Item { valid: false, value: 10 },
        Item { valid: true, value: 7 },
    ];
    assert!(has_valid(&items));
    assert_eq!(sum_valid(&items), 7);
}
```

`any`, `all`, `find`, `position`, `count`, `sum`, `min`, `max`, and related consumers often express the actual question without an intermediate collection. Some short-circuit, which can also avoid processing the rest of the input.

## Materialize When the Next Operation Requires It

Sorting is an obvious example:

```rust
fn sorted_positive(values: &[i32]) -> Vec<i32> {
    let mut result: Vec<_> = values.iter().copied().filter(|value| *value > 0).collect();
    result.sort_unstable();
    result
}

fn main() {
    assert_eq!(sorted_positive(&[3, -1, 1, 2]), vec![1, 2, 3]);
}
```

Random access, mutation of the selected subset, storing results beyond the source lifetime, or passing them to a collection-specific API can likewise justify collection.

## Repeated Traversal Does Not Automatically Require Collection

If the source operation is cheap and repeatable, running it twice can be clearer than allocating storage. If it is expensive, stateful, or cannot be repeated, materializing once may be better.

```rust
fn statistics(values: &[i32]) -> (usize, i32) {
    let positive = || values.iter().copied().filter(|value| *value > 0);
    (positive().count(), positive().sum())
}

fn main() {
    assert_eq!(statistics(&[-1, 2, 3]), (2, 5));
}
```

Do not convert “need two consumers” into an automatic “must collect” rule. Compare recomputation cost with materialization cost.

## Reuse a Stable Collection with `Extend`

On stable Rust 1.98, `Iterator::collect_into()` is still a nightly-only experimental API (`iter_collect_into`). For a caller-provided reusable `Vec`, use stable collection operations instead:

```rust
struct Item {
    active: bool,
}

fn active_items<'a>(items: &'a [Item], output: &mut Vec<&'a Item>) {
    output.clear();
    output.extend(items.iter().filter(|item| item.active));
}

fn main() {
    let items = [Item { active: true }, Item { active: false }];
    let mut buffer = Vec::new();

    active_items(&items, &mut buffer);
    assert_eq!(buffer.len(), 1);

    active_items(&items, &mut buffer);
    assert_eq!(buffer.len(), 1);
}
```

Existing capacity can be reused when sufficient, but do not promise “zero allocations after the first call” without knowing future lengths/capacity behavior. Reserve from a defensible bound if one exists.

## Returning an Iterator Can Defer the Decision

```rust
struct Item {
    valid: bool,
}

fn valid_items(items: &[Item]) -> impl Iterator<Item = &Item> {
    items.iter().filter(|item| item.valid)
}

fn main() {
    let items = [Item { valid: true }, Item { valid: false }];
    assert_eq!(valid_items(&items).count(), 1);
    let selected: Vec<_> = valid_items(&items).collect();
    assert_eq!(selected.len(), 1);
}
```

This is useful when the function's natural output is a traversal and callers should choose whether to count, search, stream, or materialize it.

Returning `impl Iterator` also commits the function to one hidden concrete iterator type per function body; if callers need runtime heterogeneous iterator implementations, another abstraction may be required.

## Collection Boundaries Can Improve Design

An intermediate collection can deliberately separate phases:

- validate/normalize data before handing it to another subsystem;
- snapshot mutable state before releasing a lock;
- detach owned results from a borrowed source;
- sort/deduplicate once and reuse the result;
- bound memory or work at an interface boundary.

Those are semantic reasons to collect, not performance mistakes.

## Avoid Universal Allocation/Pass Tables

A table claiming “N collects = N allocations” or “reuse = zero allocations” is too strong. Allocation depends on target collection, capacity, item count, allocator, and `FromIterator`/`Extend` implementation. Likewise, lazy iterator chains can still perform multiple logical operations per element.

Measure the workload if allocation traffic or cache behavior is material.

## Practical Guidance

- Keep filter/map/etc. lazy when the next operation can consume the iterator directly.
- Prefer direct consumers such as `any`, `find`, `count`, and `sum` for stream questions.
- Collect when you need ownership, sorting, indexing, mutation, phase separation, or durable reuse.
- Recompute a cheap repeatable iterator when that is simpler than storing it; materialize expensive/nonrepeatable work when appropriate.
- On stable Rust 1.98, reuse caller-provided collections with `clear` + `extend`; `collect_into` remains nightly-only.
- Do not promise fixed allocation counts without measuring the concrete collection and workload.

## See Also

- [perf-collect-once](./perf-collect-once.md) - Materialization decisions
- [perf-iter-lazy](./perf-iter-lazy.md) - Lazy evaluation
- [perf-iter-over-index](./perf-iter-over-index.md) - Iterator traversal
- [mem-reuse-collections](./mem-reuse-collections.md) - Reusing collection capacity
