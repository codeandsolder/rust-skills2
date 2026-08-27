# perf-collect-into

> Reuse an existing destination with `clear()` + `extend()` on stable Rust; nightly `Iterator::collect_into` appends like `Extend::extend` and does not clear for you

## Why It Matters

`collect::<Vec<_>>()` creates a new destination collection. In a repeated workload where one scratch buffer can be reused, stable Rust already has the essential operation: clear the existing collection and extend it from the new iterator.

Nightly `Iterator::collect_into` is an ergonomic inversion of `Extend::extend`: the method is called on the iterator and adds items to a supplied collection. It **appends to the collection's current contents**. It does not mean “replace this collection with the iterator output,” and it does not implicitly call `clear()`.

## Bad: Allocate a Fresh Scratch Destination Every Iteration

```rust
fn sums_of_positive_values(batches: &[Vec<i32>]) -> Vec<i32> {
    let mut sums = Vec::with_capacity(batches.len());

    for batch in batches {
        let positive: Vec<_> = batch.iter().copied().filter(|x| *x > 0).collect();
        sums.push(positive.iter().sum());
    }

    sums
}

fn main() {
    let batches = vec![vec![-1, 2, 3], vec![4, -5, 6]];
    assert_eq!(sums_of_positive_values(&batches), [5, 10]);
}
```

If this loop is hot and a downstream API genuinely requires the temporary `Vec`, rebuilding the destination collection each iteration may be unnecessary allocator work.

## Good: Stable `clear()` + `extend()`

```rust
fn sums_of_positive_values(batches: &[Vec<i32>]) -> Vec<i32> {
    let mut sums = Vec::with_capacity(batches.len());
    let mut positive = Vec::new();

    for batch in batches {
        positive.clear();
        positive.extend(batch.iter().copied().filter(|x| *x > 0));
        sums.push(positive.iter().sum());
    }

    sums
}

fn main() {
    let batches = vec![vec![-1, 2, 3], vec![4, -5, 6]];
    assert_eq!(sums_of_positive_values(&batches), [5, 10]);
}
```

If all you need is the sum, an even better design is to avoid the intermediate collection entirely and sum the filtered iterator. Buffer reuse should not preserve a temporary collection that the algorithm does not need.

## Nightly: `collect_into` Appends

<!-- rust-check: nightly(iter_collect_into); reason=Iterator::collect_into remains a nightly-only experimental API -->
```rust
#![feature(iter_collect_into)]

fn main() {
    let mut values = vec![10];

    [1, 2, 3]
        .into_iter()
        .map(|x| x * 2)
        .collect_into(&mut values);

    // Existing contents remain; collect_into appends through Extend.
    assert_eq!(values, [10, 2, 4, 6]);
}
```

For replacement semantics on nightly, clear explicitly first:

<!-- rust-check: nightly(iter_collect_into); reason=Iterator::collect_into remains a nightly-only experimental API -->
```rust
#![feature(iter_collect_into)]

fn main() {
    let mut buffer = vec![99, 100];

    buffer.clear();
    (0..4).map(|x| x * x).collect_into(&mut buffer);

    assert_eq!(buffer, [0, 1, 4, 9]);
}
```

The current standard-library documentation describes `collect_into` as a convenience method for `Extend::extend`. Treat it as syntax, not a stronger allocation or replacement primitive.

## `extend()` Works Beyond `Vec`

```rust
use std::collections::{HashSet, VecDeque};

fn main() {
    let mut vec = vec![1];
    vec.extend([2, 3]);
    assert_eq!(vec, [1, 2, 3]);

    let mut deque = VecDeque::from([1]);
    deque.extend([2, 3]);
    assert_eq!(deque.into_iter().collect::<Vec<_>>(), [1, 2, 3]);

    let mut set = HashSet::from([1]);
    set.extend([1, 2, 3]);
    assert_eq!(set.len(), 3);
}
```

The exact allocation strategy belongs to the destination's `Extend` implementation and the iterator being supplied. Do not promise a fixed number of allocations merely because `extend` or `collect_into` is used.

## Reuse vs Append vs Replace

| Intent | Stable pattern | Nightly `collect_into` equivalent |
|---|---|---|
| Append new iterator items | `dst.extend(iter)` | `iter.collect_into(&mut dst)` |
| Replace current contents while retaining capacity | `dst.clear(); dst.extend(iter)` | `dst.clear(); iter.collect_into(&mut dst)` |
| Create independent owned result | `iter.collect::<Vec<_>>()` | usually still `collect()` |

Choose from ownership semantics first. A fresh collection is correct when each result must outlive the next iteration independently.

## Capacity Reuse Has a High-Water-Mark Cost

A scratch `Vec` that once grows very large may retain that allocation after `clear()`. If batch sizes vary dramatically, retained memory can matter more than saved allocator calls. See [mem-reuse-collections](./mem-reuse-collections.md) for that tradeoff.

## See Also

- [mem-reuse-collections](./mem-reuse-collections.md) — when retaining capacity helps
- [perf-extend-batch](./perf-extend-batch.md) — batch insertion semantics
- [perf-drain-reuse](./perf-drain-reuse.md) — consuming elements while retaining allocation

## References

- [Iterator::collect_into](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.collect_into)
- [std::iter::Extend](https://doc.rust-lang.org/std/iter/trait.Extend.html)
