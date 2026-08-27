# mem-clone-from

> Use `Clone::clone_from` when repeatedly replacing an existing value and the concrete type can profitably reuse its resources

## Why It Matters

`Clone::clone_from(&mut self, source)` is semantically equivalent to replacing `self` with `source.clone()`, but the `Clone` trait explicitly permits implementors to override it and reuse resources already owned by `self`.

That makes it useful in reuse-heavy loops and buffers, but the optimization is **type-specific**. The trait does not guarantee allocation reuse for every `Clone` type, and a default `clone_from` implementation may be little different from assignment from `clone()`.

Use it where the destination already exists and resource reuse matters; do not treat it as a universal faster spelling of `clone`.

## Basic Pattern

```rust
fn copy_into_reusable_buffer(sources: &[String]) -> usize {
    let mut buffer = String::with_capacity(1024);
    let mut total = 0;

    for source in sources {
        buffer.clone_from(source);
        total += buffer.len();
    }

    total
}

fn main() {
    let sources = vec!["abc".to_owned(), "hello".to_owned()];
    assert_eq!(copy_into_reusable_buffer(&sources), 8);
}
```

This expresses the intent to replace an existing `String` while allowing its implementation to reuse capacity. Whether a particular iteration allocates still depends on the source/destination capacities and implementation.

## `Vec<T>::clone_from` Explicitly Reuses Allocation When Possible

The standard library documents `Vec<T>::clone_from` as avoiding reallocation when possible, and it can also reuse resources of existing elements when `T::clone_from` does so.

```rust
fn main() {
    let source = vec![1_u32, 2, 3];
    let mut destination = Vec::with_capacity(16);
    destination.extend([9, 9, 9]);

    let old_ptr = destination.as_ptr();
    destination.clone_from(&source);

    assert_eq!(destination, source);
    assert_eq!(destination.as_ptr(), old_ptr);
}
```

This example keeps enough existing capacity for the source. Do not generalize the exact pointer-reuse result to arbitrary types or arbitrary vector capacity changes.

## The Trait Contract Is About Equivalence, Not Performance

For a custom type, overriding `clone_from` is optional:

```rust
#[derive(Debug, PartialEq)]
struct Buffer {
    bytes: Vec<u8>,
    label: String,
}

impl Clone for Buffer {
    fn clone(&self) -> Self {
        Self {
            bytes: self.bytes.clone(),
            label: self.label.clone(),
        }
    }

    fn clone_from(&mut self, source: &Self) {
        self.bytes.clone_from(&source.bytes);
        self.label.clone_from(&source.label);
    }
}

fn main() {
    let source = Buffer {
        bytes: vec![1, 2, 3],
        label: "source".to_owned(),
    };
    let mut destination = Buffer {
        bytes: Vec::with_capacity(32),
        label: String::with_capacity(32),
    };

    destination.clone_from(&source);
    assert_eq!(destination, source);
}
```

The implementation delegates resource-reuse opportunities to its fields rather than manually reproducing their internals.

Do not write pseudo-implementations of `Clone` for standard-library types in examples: Rust's orphan rules forbid implementing a foreign trait for a foreign type, and the library's internal implementation is not an API contract you should copy.

## Some Types Benefit Less

For cheap reference-counted or inline representations, cloning may already be inexpensive:

```rust
use ecow::EcoString;

fn main() {
    let source = EcoString::from("shared string that is long enough for heap storage");
    let mut destination = EcoString::from("old value");

    destination.clone_from(&source);
    assert_eq!(destination, source);
}
```

For `EcoString`, clones use clone-on-write semantics; heap-backed clones share storage and inline clones copy a small inline representation. `clone_from` remains correct, but allocation reuse is no longer the same central advantage as it is for a reusable `Vec` buffer.

Likewise, `Copy` values do not need this pattern at all:

```rust
fn main() {
    let source = 42_u32;
    let mut destination = 0_u32;
    destination = source;
    assert_eq!(destination, 42);
}
```

## Do Not Assume Every Collection Reuses the Same Way

The `Clone` trait only says that `clone_from` **can** be overridden to reuse resources. Do not claim, without checking the concrete implementation, that `HashMap`, `PathBuf`, third-party containers, or custom types preserve allocations/buckets in a particular way.

If a specific allocation-reuse guarantee matters to correctness or performance, verify that type's current documentation/source and benchmark the workload.

## When It Helps

Good candidates:

- a destination value already exists;
- replacements happen repeatedly;
- the type owns reusable heap capacity or other reusable resources;
- profiling shows allocation/copy traffic matters;
- the concrete `clone_from` implementation actually takes advantage of reuse.

Less useful candidates:

- one-off clones where there is no existing destination resource to reuse;
- `Copy` values;
- cheap shared/clone-on-write handles;
- code where clarity matters more than an unmeasured micro-optimization.

## Benchmark the Real Pattern

Avoid universal claims such as “`clone_from` is 2–3× faster.” Results depend on source sizes, capacity history, element clone behavior, allocator, target, and optimization level.

Benchmark the repeated replacement pattern your program actually performs, and measure allocations as well as elapsed time when allocator pressure is the reason for the change.

## Practical Guidance

- Reach for `clone_from` when replacing an existing reusable value, not for every clone.
- Remember that reuse is an implementor optimization, not a blanket trait guarantee.
- `Vec<T>::clone_from` is specifically documented to avoid reallocation when possible.
- Delegate custom `clone_from` implementations to fields that already know how to reuse themselves.
- Verify concrete third-party/std implementations before promising allocation behavior.
- Measure instead of quoting fixed speedup numbers.

## See Also

- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocating capacity
- [mem-reuse-collections](./mem-reuse-collections.md) - Reusing collection allocations
- [mem-ecow-clone-heavy](./mem-ecow-clone-heavy.md) - Clone-on-write strings
- [own-clone-explicit](./own-clone-explicit.md) - When cloning is appropriate
