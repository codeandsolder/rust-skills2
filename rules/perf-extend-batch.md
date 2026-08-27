# perf-extend-batch

> Use `extend`, `extend_from_slice`, or `append` when adding a batch expresses the ownership you want; reserve explicitly when the final size is cheaply known

## Why It Matters

Batch-oriented APIs are often clearer than hand-written element loops, and `Vec` implementations can use iterator information and specialization to grow efficiently. But `extend()` is not a contractual promise of “one allocation,” nor is it universally faster than a `push` loop.

Choose the operation from ownership and source shape first. If the final length is known cheaply and allocations matter, reserving capacity explicitly gives the intent a much firmer footing than relying on an iterator's size hint.

## Good: Extend From an Iterator

```rust
fn positives(chunks: &[Vec<i32>]) -> Vec<i32> {
    let mut output = Vec::new();

    for chunk in chunks {
        output.extend(chunk.iter().copied().filter(|x| *x > 0));
    }

    output
}

fn main() {
    let chunks = vec![vec![-1, 2, 3], vec![4, -5]];
    assert_eq!(positives(&chunks), [2, 3, 4]);
}
```

This says directly that each iterator contributes a batch of values. A nested loop with `push` is also correct; prefer whichever is clearer unless measurement shows a performance difference.

## Reserve When the Total Size Is Known

```rust
fn flatten(chunks: Vec<Vec<u32>>) -> Vec<u32> {
    let total: usize = chunks.iter().map(Vec::len).sum();
    let mut output = Vec::with_capacity(total);

    for chunk in chunks {
        output.extend(chunk);
    }

    output
}

fn main() {
    assert_eq!(flatten(vec![vec![1, 2], vec![3, 4, 5]]), [1, 2, 3, 4, 5]);
}
```

The initial capacity request is at least `total`; `Vec` may receive more capacity from the allocator. The point is to avoid growth caused by knowingly starting below the final element count, not to promise an exact allocator behavior.

## Pick the API That Matches the Source

```rust
fn main() {
    // Generic iterator source.
    let mut a = vec![1, 2];
    a.extend((3..=5).map(|x| x * 10));
    assert_eq!(a, [1, 2, 30, 40, 50]);

    // Borrowed slice: clones elements into the destination.
    let source = [6, 7, 8];
    let mut b = vec![1, 2];
    b.extend_from_slice(&source);
    assert_eq!(b, [1, 2, 6, 7, 8]);

    // Another Vec whose values should be moved out and whose length becomes 0.
    let mut tail = vec![9, 10];
    let mut c = vec![1, 2];
    c.append(&mut tail);
    assert_eq!(c, [1, 2, 9, 10]);
    assert!(tail.is_empty());
}
```

Important distinctions:

- `extend(iter)` consumes any suitable iterator;
- `extend_from_slice(&[T])` clones the slice elements and therefore requires `T: Clone`, not specifically `Copy`;
- `append(&mut other)` moves all elements out of another `Vec<T>`;
- `extend_from_within(range)` clones a range already inside the same `Vec`.

## `extend_from_within` Avoids an Intermediate Source Collection

```rust
fn main() {
    let mut values = vec![1, 2, 3];
    values.extend_from_within(0..2);
    assert_eq!(values, [1, 2, 3, 1, 2]);
}
```

This is preferable to cloning the selected range into a temporary `Vec` solely so it can then be appended back.

## Strings: Capacity Planning and Direct Appends

```rust
fn concatenate(parts: &[&str]) -> String {
    let total_len: usize = parts.iter().map(|part| part.len()).sum();
    let mut output = String::with_capacity(total_len);

    for part in parts {
        output.push_str(part);
    }

    output
}

fn main() {
    assert_eq!(concatenate(&["ab", "cd", "ef"]), "abcdef");
}
```

`parts.concat()` is also clear and is often a good standard-library choice. Do not rank one version as universally “better” without a workload reason.

## Size Hints Are Useful, Not Allocation Contracts

An iterator may provide lower/upper bounds through `size_hint()`, and collection implementations can use those hints. The hint can be inexact, and even an exact element count does not force a particular allocator growth strategy.

Avoid tables claiming:

- `N` pushes imply a particular number of reallocations;
- `extend(iter)` always allocates once;
- a precise size hint guarantees exact capacity.

`Vec::push` has amortized constant-time growth; if allocation count matters, reserve the amount you know and measure the real workload.

## Hash Collections

`HashMap` and `HashSet` also implement `Extend`, but duplicate keys/elements and hashing change the semantics:

```rust
use std::collections::{HashMap, HashSet};

fn main() {
    let mut map = HashMap::from([("a", 1)]);
    map.extend([("b", 2), ("a", 3)]);
    assert_eq!(map["a"], 3);

    let mut set = HashSet::from([1]);
    set.extend([1, 2, 3]);
    assert_eq!(set.len(), 3);
}
```

Batch syntax does not remove hashing or duplicate-handling costs; it simply expresses the insertion source naturally.

## See Also

- [mem-with-capacity](./mem-with-capacity.md) — explicit capacity planning
- [perf-collect-into](./perf-collect-into.md) — reusing an existing destination
- [mem-reuse-collections](./mem-reuse-collections.md) — retained-capacity tradeoffs

## References

- [Vec::extend_from_slice](https://doc.rust-lang.org/std/vec/struct.Vec.html#method.extend_from_slice)
- [Vec::append](https://doc.rust-lang.org/std/vec/struct.Vec.html#method.append)
- [Extend](https://doc.rust-lang.org/std/iter/trait.Extend.html)
