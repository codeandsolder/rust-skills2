# perf-drain-reuse

> Use `drain` or `extract_if` when you need to remove owned elements while retaining the source collection's allocation; do not introduce an intermediate collection unless ownership requires one

## Why It Matters

`drain` removes elements and yields them by value while the collection keeps its backing allocation. `extract_if` conditionally removes matching elements and yields those owned values. These operations are useful when the caller wants to reuse the source container rather than consume it wholesale.

They are ownership tools first. Whether they improve performance depends on the surrounding algorithm, retained capacity, element movement, and whether the removed values must be stored elsewhere.

## Reuse a Scratch Destination When a Separate Batch Is Required

```rust
fn sums_in_chunks(mut values: Vec<u32>, chunk_size: usize) -> Vec<u32> {
    assert!(chunk_size > 0);

    let mut sums = Vec::new();
    let mut chunk = Vec::with_capacity(chunk_size);

    while !values.is_empty() {
        chunk.clear();
        let take = chunk_size.min(values.len());
        chunk.extend(values.drain(..take));
        sums.push(chunk.iter().sum());
    }

    sums
}

fn main() {
    assert_eq!(sums_in_chunks(vec![1, 2, 3, 4, 5], 2), [3, 7, 5]);
}
```

Here `chunk.clear()` retains the scratch allocation. If the downstream operation can consume the drained iterator directly, the scratch `Vec` may be unnecessary.

## `Vec::extract_if` Takes a Range and a Predicate

Since Rust 1.87, `Vec::extract_if` considers only elements inside the supplied range. Use `..` to inspect the whole vector.

```rust
fn main() {
    let mut numbers = vec![1, 2, 3, 4, 5, 6];
    let evens: Vec<_> = numbers.extract_if(.., |n| *n % 2 == 0).collect();

    assert_eq!(numbers, [1, 3, 5]);
    assert_eq!(evens, [2, 4, 6]);
}
```

A subrange can be useful when only part of the vector is eligible:

```rust
fn main() {
    let mut values = vec![10, 11, 12, 13, 14, 15];
    let removed: Vec<_> = values.extract_if(2..5, |n| *n % 2 == 0).collect();

    assert_eq!(removed, [12, 14]);
    assert_eq!(values, [10, 11, 13, 15]);
}
```

The range is part of the API. Writing `vec.extract_if(|...|)` is not the `Vec` method signature.

## Other Collections Have Different `extract_if` Signatures

Do not generalize the `Vec` range argument to every collection. Collection APIs are intentionally shaped around their storage model.

```rust
use std::collections::HashMap;

fn main() {
    let mut map = HashMap::from([("low", 1), ("mid", 5), ("high", 9)]);
    let removed: HashMap<_, _> = map.extract_if(|_, value| *value >= 5).collect();

    assert_eq!(map.get("low"), Some(&1));
    assert_eq!(removed.len(), 2);
}
```

For `HashMap`/`HashSet`, `extract_if` operates over the collection rather than a positional range. Check the exact collection's current signature instead of assuming all `extract_if` methods are interchangeable.

## `drain`, `clear`, `extract_if`, and `mem::take` Express Different Ownership

| Operation | Removes | Yields removed values | Keeps source allocation |
|---|---|---|---|
| `clear()` | all | no | yes |
| `drain(range)` | range/all | yes | yes |
| `extract_if(...)` | matching | yes | yes |
| `mem::take(&mut collection)` | whole collection | returns the collection itself | no; source is replaced by default value |

Example:

```rust
fn main() {
    let mut values = vec![1, 2, 3, 4];
    let capacity = values.capacity();

    let tail: Vec<_> = values.drain(2..).collect();
    assert_eq!(values, [1, 2]);
    assert_eq!(tail, [3, 4]);
    assert_eq!(values.capacity(), capacity);

    values.clear();
    assert!(values.is_empty());
    assert_eq!(values.capacity(), capacity);
}
```

`drain(..)` is useful when you need ownership of removed elements. If you only want an empty container, `clear()` is simpler.

## Avoid Intermediate Collections When Moving Between Destinations

```rust
fn move_even(src: &mut Vec<u32>, dst: &mut Vec<u32>) {
    dst.extend(src.extract_if(.., |value| *value % 2 == 0));
}

fn main() {
    let mut src = vec![1, 2, 3, 4, 5];
    let mut dst = vec![10];

    move_even(&mut src, &mut dst);
    assert_eq!(src, [1, 3, 5]);
    assert_eq!(dst, [10, 2, 4]);
}
```

Collecting the extracted elements into a temporary `Vec` before extending `dst` would allocate storage that this ownership flow does not need.

## Conditional Deque Pops Are a Different Tool

For `VecDeque`, `pop_front_if` / `pop_back_if` conditionally remove only an end element. They do not scan/extract arbitrary matching elements.

```rust
use std::collections::VecDeque;

fn main() {
    let mut queue = VecDeque::from([1, 2, 3, 9]);

    assert_eq!(queue.pop_front_if(|x| *x < 2), Some(1));
    assert_eq!(queue.pop_front_if(|x| *x < 2), None);
    assert_eq!(queue.pop_back_if(|x| *x > 8), Some(9));
    assert_eq!(queue, [2, 3]);
}
```

Choose these when only the front/back is relevant; `extract_if` and `drain` solve different removal patterns.

## Retained Capacity Has a Cost

Reusing a collection also retains its high-water allocation. If one iteration grows to an exceptional size, keeping that allocation indefinitely can cost more memory than repeated allocation would have cost CPU time.

Measure long-lived scratch buffers, especially in services with highly variable request sizes. Reuse is useful when the working set is recurrent and allocation behavior actually matters.

## See Also

- [mem-reuse-collections](./mem-reuse-collections.md) — retained-capacity tradeoffs
- [perf-extend-batch](./perf-extend-batch.md) — extending destinations
- [perf-collect-into](./perf-collect-into.md) — collecting into an existing destination

## References

- [`Vec::drain`](https://doc.rust-lang.org/std/vec/struct.Vec.html#method.drain)
- [`Vec::extract_if`](https://doc.rust-lang.org/std/vec/struct.Vec.html#method.extract_if)
- [`HashMap::extract_if`](https://doc.rust-lang.org/std/collections/struct.HashMap.html#method.extract_if)
