# perf-iter-lazy

> Keep iterator pipelines lazy when streaming or short-circuiting is useful; collect only when ownership, reuse, sorting, indexing, or another concrete requirement needs a collection

## Why It Matters

Iterator adapters such as `map`, `filter`, and `take` normally produce another lazy iterator. Work happens as a consumer requests items. This can avoid intermediate allocations and can stop early for consumers such as `find`, `any`, or `take`.

Laziness is not automatically faster. A collection is the right representation when values must be stored, sorted, indexed repeatedly, shared independently from the source, or traversed multiple times.

## Avoid Intermediate Collections That Carry No Ownership Need

```rust
fn first_positive_squares(values: &[i32], count: usize) -> Vec<i32> {
    values
        .iter()
        .copied()
        .filter(|x| *x > 0)
        .map(|x| x * x)
        .take(count)
        .collect()
}

fn main() {
    assert_eq!(first_positive_squares(&[-1, 2, 3, 4], 2), [4, 9]);
}
```

Collecting after `filter`, then collecting again after `map`, would create temporary allocations without changing the ownership semantics of this function.

## Short-Circuit Directly

```rust
fn has_negative(values: &[i32]) -> bool {
    values.iter().any(|value| *value < 0)
}

fn first_even(values: &[i32]) -> Option<i32> {
    values.iter().copied().find(|value| value % 2 == 0)
}

fn main() {
    assert!(has_negative(&[4, -1, 9]));
    assert_eq!(first_even(&[1, 7, 8, 10]), Some(8));
}
```

`any` and `find` stop once the answer is known. Collecting all matching elements first would force work the caller does not need.

## Adapters vs Consumers

Typical lazy adapters include:

- `map`, `filter`, `filter_map`;
- `take`, `skip`;
- `chain`, `zip`, `enumerate`;
- `flat_map`, `flatten`, `scan`.

Typical consumers include:

- `collect`;
- `fold`, `reduce`, `sum`, `product`;
- `count`, `for_each`;
- `find`, `position`, `any`, `all`.

Some iterator methods do not fit neatly into “adapter” or “terminal consumer.” `Peekable::next_if` and `next_if_map`, for example, conditionally consume the **next item of an existing iterator**; they do not return a new iterator.

## `Peekable::next_if`

`next_if` consumes the next item only when the predicate accepts a reference to it. If the predicate rejects the item, it remains available to `peek`/`next`.

```rust
fn main() {
    let mut values = [0, 0, 2, 3].into_iter().peekable();

    while values.next_if(|value| *value == 0).is_some() {}

    assert_eq!(values.next(), Some(2));
    assert_eq!(values.next(), Some(3));
}
```

`next_if` has been stable much longer than the newer mapping variant; do not label both as a Rust 1.94 addition.

## `Peekable::next_if_map` (Rust 1.94+)

`next_if_map` takes ownership of the next `I::Item`. The closure returns `Ok(mapped)` to consume the item and produce a mapped result, or `Err(item)` to put an item back into the iterator.

```rust
fn main() {
    let mut values = [2, 4, 11, 6].into_iter().peekable();
    let mut doubled = Vec::new();

    while let Some(value) = values.next_if_map(|item| {
        if item < 10 {
            Ok(item * 2)
        } else {
            Err(item)
        }
    }) {
        doubled.push(value);
    }

    assert_eq!(doubled, [4, 8]);
    assert_eq!(values.next(), Some(11));
    assert_eq!(values.next(), Some(6));
}
```

It does **not** take `&I::Item` and it does **not** use `Option` as the closure result. Returning `Err(item)` is what preserves an unaccepted owned item for the next iteration step.

Use `next_if_map_mut` when mutably inspecting the next item without taking ownership is a better fit for the transformation.

## Fixed-Size Slice Views

When an algorithm naturally consumes fixed-size chunks or overlapping windows, slice APIs can expose array references without creating temporary vectors.

```rust
fn pair_sums(values: &[u32]) -> Vec<u32> {
    let (pairs, remainder) = values.as_chunks::<2>();
    let mut sums: Vec<_> = pairs.iter().map(|&[a, b]| a + b).collect();
    sums.extend(remainder.iter().copied());
    sums
}

fn main() {
    assert_eq!(pair_sums(&[1, 2, 3, 4, 9]), [3, 7, 9]);
}
```

For overlapping fixed-size windows, use `array_windows` when the toolchain version targeted by the project provides it. These APIs solve indexing/layout problems; they are not themselves “lazy iterators.”

## Collection Is Sometimes the Point

```rust
fn sorted_unique(values: impl IntoIterator<Item = i32>) -> Vec<i32> {
    let mut values: Vec<_> = values.into_iter().collect();
    values.sort_unstable();
    values.dedup();
    values
}

fn main() {
    assert_eq!(sorted_unique([3, 1, 3, 2]), [1, 2, 3]);
}
```

Sorting requires materialized storage, so collecting here is not an anti-pattern. The useful question is whether the collection enables an operation or ownership boundary the pipeline actually needs.

## Review Questions

Before adding `.collect()` in the middle of a pipeline, ask:

- Does the next operation require a slice/collection rather than an iterator?
- Must these values outlive the source iterator independently?
- Will they be sorted, indexed, mutated, or traversed multiple times?
- Is collection needed for parallelism or an external API boundary?
- Would a short-circuiting consumer avoid most of the work?

If there is a real answer, collect. If not, keeping the iterator lazy is usually simpler.

## See Also

- [perf-collect-once](./perf-collect-once.md) — avoid gratuitous repeated collection
- [perf-iter-over-index](./perf-iter-over-index.md) — iterator-oriented traversal
- [anti-collect-intermediate](./anti-collect-intermediate.md) — unnecessary intermediates

## References

- [`Iterator`](https://doc.rust-lang.org/std/iter/trait.Iterator.html)
- [`Peekable`](https://doc.rust-lang.org/std/iter/struct.Peekable.html)
