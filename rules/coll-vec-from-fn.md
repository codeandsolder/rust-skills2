# coll-vec-from-fn

> Prefer Rust 1.100 `Vec::from_fn` for an indexed, fixed-length vector constructor with no intermediate collection

**Rule**: `coll-vec-from-fn`

## Why It Matters

`Vec::from_fn` builds a vector from a length and per-index initializer. It communicates indexed construction more directly than `(0..n).map(f).collect()` or a manual push loop. Use it when each element is derived from its index and output length is known.

## Good

```rust
fn main() {
    let squares = Vec::from_fn(5, |i| i * i);
    assert_eq!(squares, [0, 1, 4, 9, 16]);
}
```

Construction is not automatically fallible: a closure returning `Result` creates a `Vec<Result<_, _>>`, not a `Result<Vec<_>, _>`. For fallible initialization with early error propagation, use `(0..n).map(f).collect::<Result<Vec<_>, _>>()` instead.

Do not use it to hide expensive indexing, side effects that depend on scheduling, or unwanted capacity assumptions. An indexed loop remains appropriate when construction needs nontrivial state or early termination.

## See Also

- [mem-with-capacity](./mem-with-capacity.md) — preallocation
- [anti-collect-intermediate](./anti-collect-intermediate.md) — eliminating temporary collections
