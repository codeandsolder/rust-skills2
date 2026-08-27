# anti-vec-for-slice

> Accept slices when an API only needs element access; accept `Vec` references when vector-specific capacity or length-changing operations are genuinely part of the contract

## Why It Matters

`&[T]` and `&mut [T]` describe borrowed contiguous elements without requiring a particular owning container. A function that only reads or mutates existing elements can therefore work with vectors, arrays, boxed slices, subslices, and other slice-producing storage.

`&Vec<T>` / `&mut Vec<T>` are appropriate when the function actually needs vector-specific state or operations such as capacity, `push`, `reserve`, or changing the logical length.

Choose the **least specific capability the function really needs**, not a blanket ban on `&Vec<T>`.

## Read-Only Element Access: Prefer `&[T]`

```rust
fn sum(numbers: &[i32]) -> i32 {
    numbers.iter().sum()
}

fn main() {
    let array = [1, 2, 3, 4];
    let vector = vec![5, 6, 7];

    assert_eq!(sum(&array), 10);
    assert_eq!(sum(&vector), 18);
    assert_eq!(sum(&vector[1..]), 13);
}
```

The function needs a sequence of `i32`, not a `Vec<i32>` owner.

## Deref Coercion Makes `&Vec<T>` Callers Work Naturally

`Vec<T>` dereferences to `[T]`, so callers do not need to write `.as_slice()` merely to call a slice API:

```rust
fn first(numbers: &[i32]) -> Option<i32> {
    numbers.first().copied()
}

fn main() {
    let values = vec![10, 20, 30];
    assert_eq!(first(&values), Some(10));
}
```

Explicit `.as_slice()` can still be useful for type inference or readability, but it is normally unnecessary at a simple function-call boundary.

## Mutating Existing Elements: Prefer `&mut [T]`

```rust
fn double_elements(numbers: &mut [i32]) {
    for number in numbers {
        *number *= 2;
    }
}

fn main() {
    let mut array = [1, 2, 3];
    double_elements(&mut array);
    assert_eq!(array, [2, 4, 6]);

    let mut vector = vec![4, 5];
    double_elements(&mut vector);
    assert_eq!(vector, vec![8, 10]);
}
```

The function changes values but never changes the number of elements, so a mutable slice is sufficient.

## Length-Changing Operations Need `&mut Vec<T>`

```rust
fn append_marker(values: &mut Vec<u8>) {
    values.push(0xff);
}

fn main() {
    let mut values = vec![1, 2, 3];
    append_marker(&mut values);
    assert_eq!(values, vec![1, 2, 3, 0xff]);
}
```

A slice has a fixed length. If the operation must `push`, `pop`, `truncate`, `reserve`, or otherwise manage vector length/capacity, `&mut Vec<T>` communicates that requirement.

## Read-Only Vector Metadata Can Also Justify `&Vec<T>`

Capacity is a property of the vector allocation, not of its slice view:

```rust
fn spare_capacity(values: &Vec<u8>) -> usize {
    values.capacity() - values.len()
}

fn main() {
    let values = Vec::<u8>::with_capacity(16);
    assert!(spare_capacity(&values) >= 16);
}
```

If capacity is genuinely part of the operation, accepting `&Vec<T>` is not an anti-pattern.

## Similar Borrowed-View Choices

The same principle applies to other owner/view pairs:

| If you only need... | Usually accept... | More specific owner only when you need... |
|---|---|---|
| string contents | `&str` | `String` capacity/ownership mutation |
| filesystem path view | `&Path` | `PathBuf` growth/ownership operations |
| boxed value contents | `&T` | the `Box<T>` allocation/ownership itself |
| contiguous elements | `&[T]` | `Vec<T>` capacity/length mutation |

These are capability choices, not absolute replacement rules. Sometimes the owner identity or allocation metadata is exactly what an API manages.

## `AsRef<[T]>` Is a Different API Trade-Off

A generic `AsRef<[u8]>` parameter can accept many representations, but it introduces a generic parameter and—if taken by value—may consume owned inputs:

```rust
fn checksum(data: impl AsRef<[u8]>) -> u64 {
    data.as_ref().iter().map(|byte| u64::from(*byte)).sum()
}

fn main() {
    assert_eq!(checksum([1_u8, 2, 3]), 6);
    assert_eq!(checksum(vec![4_u8, 5]), 9);
    assert_eq!(checksum(b"AB"), 131);
}
```

This can be ergonomic for conversion-style/public APIs that intentionally accept multiple owned/borrowed forms. It is not automatically better than `fn checksum(data: &[u8])`: the slice form is simpler, avoids monomorphizing over caller types, and makes the borrowing contract explicit.

Choose generic `AsRef` because the wider input API is useful, not merely because it can accept a slice.

## Slices Preserve Subrange Flexibility

```rust
fn clear(values: &mut [u8]) {
    values.fill(0);
}

fn main() {
    let mut values = vec![1, 2, 3, 4];
    clear(&mut values[1..3]);
    assert_eq!(values, vec![1, 0, 0, 4]);
}
```

An API requiring `&mut Vec<u8>` could not operate directly on this borrowed subrange.

## Clippy Detection

Clippy's `ptr_arg` lint warns about pointer-to-owner arguments such as `&Vec<T>` or `&String` when a borrowed view is sufficient:

```toml
[lints.clippy]
ptr_arg = "warn"
```

Treat the lint as a prompt to inspect required capabilities. If the function really uses `Vec`-specific behavior, keep the vector parameter.

## Practical Guidance

- Accept `&[T]` for read-only access to existing contiguous elements.
- Accept `&mut [T]` when mutating elements without changing length.
- Accept `&Vec<T>` when vector-specific metadata such as capacity is part of the operation.
- Accept `&mut Vec<T>` for length/capacity-changing operations such as `push`, `pop`, `truncate`, or `reserve`.
- Rely on deref coercion so `&Vec<T>` callers naturally satisfy slice parameters.
- Use generic `AsRef<[T]>` only when accepting a wider family of representations is an intentional API benefit.
- Choose the least specific abstraction that still exposes every operation the implementation legitimately needs.

## See Also

- [anti-string-for-str](./anti-string-for-str.md) - `String` versus `str` views
- [own-slice-over-vec](./own-slice-over-vec.md) - Slice-oriented APIs
- [api-impl-asref](./api-impl-asref.md) - `AsRef` API trade-offs
