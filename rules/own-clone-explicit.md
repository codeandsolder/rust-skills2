# own-clone-explicit

> Use `Clone` to make non-`Copy` duplication explicit, but do not infer a universal allocation or cost model from `.clone()`

## Why It Matters

`Copy` and `Clone` primarily describe **semantics**, not a performance tier.

- `Copy` means assignment and argument passing may duplicate the value implicitly instead of moving it.
- `Clone` provides an explicit duplication operation through `.clone()`.
- Every `Copy` type is also `Clone`, but many `Clone` types are not `Copy`.

A clone may allocate and copy a large buffer (`String`, `Vec<T>`), may merely increment a reference count (`Arc<T>`), or may duplicate a small non-`Copy` value. Conversely, a `Copy` can still be large enough that repeated implicit copies matter to performance. Do not describe `Copy` as literally “free” or `Clone` as synonymous with allocation.

## Move When the Caller Is Done With the Value

If ownership is no longer needed by the caller, move the value instead of cloning it:

```rust
fn normalize(mut values: Vec<u32>) -> Vec<u32> {
    values.sort_unstable();
    values
}

fn main() {
    let values = vec![3, 1, 2];
    let sorted = normalize(values);
    assert_eq!(sorted, [1, 2, 3]);
}
```

The move is intentional Rust ownership, not a hidden expensive copy.

## Clone When You Need Two Owned Values

If the original must remain available and the callee needs ownership, an explicit clone makes that decision visible:

```rust
fn normalize(mut values: Vec<u32>) -> Vec<u32> {
    values.sort_unstable();
    values
}

fn main() {
    let original = vec![3, 1, 2];
    let sorted = normalize(original.clone());

    assert_eq!(original, [3, 1, 2]);
    assert_eq!(sorted, [1, 2, 3]);
}
```

For `Vec<u32>`, this particular clone duplicates the elements into separately owned storage. That is a fact about `Vec`'s implementation/semantics, not about the `Clone` trait in general.

## Borrow When Ownership Is Unnecessary

If the operation only reads the data, accepting a borrow often removes the need for duplication entirely:

```rust
fn sum(values: &[u32]) -> u32 {
    values.iter().sum()
}

fn main() {
    let values = vec![1, 2, 3];
    assert_eq!(sum(&values), 6);
    assert_eq!(values.len(), 3);
}
```

Do not contort an API solely to eliminate every clone; choose borrowing, moving, or cloning according to the ownership semantics first, then optimize measured costs.

## Cheap Clones Exist

Reference-counted ownership is the obvious counterexample to “clone means deep copy”:

```rust
use std::sync::Arc;

fn main() {
    let data = Arc::new(vec![1_u8, 2, 3]);
    let shared = Arc::clone(&data);

    assert!(Arc::ptr_eq(&data, &shared));
    assert_eq!(Arc::strong_count(&data), 2);
}
```

`Arc::clone` shares the same allocation and updates a reference count. That is usually much cheaper than cloning the inner `Vec`, but it is still not “zero cost”: atomic reference-count operations and eventual destruction have a cost.

## `Copy` Is an Implicit-Duplication Contract

Small plain values are natural `Copy` types:

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct UserId(u64);

fn main() {
    let first = UserId(7);
    let second = first;
    assert_eq!(first, second);
}
```

A type that owns resources requiring destruction, such as `String`, cannot simply be made `Copy`; duplicating its bits would create multiple owners of the same allocation. Such types use moves and may implement `Clone` to define a valid explicit duplication operation.

## Derive `Clone` When Field-Wise Cloning Is the Right Semantics

```rust
#[derive(Clone, Debug, PartialEq)]
struct Document {
    title: String,
    bytes: Vec<u8>,
}

fn main() {
    let document = Document {
        title: "guide".into(),
        bytes: vec![1, 2, 3],
    };
    let copy = document.clone();
    assert_eq!(document, copy);
}
```

A manual implementation is useful only when field-wise derived cloning is not the intended behavior or when a type-specific `clone_from` optimization is worthwhile.

## Manual `Clone` Can Deliberately Rebuild Ephemeral State

```rust
use std::cell::RefCell;

#[derive(Debug)]
struct CachedValue {
    value: i32,
    cached_text: RefCell<Option<String>>,
}

impl Clone for CachedValue {
    fn clone(&self) -> Self {
        Self {
            value: self.value,
            cached_text: RefCell::new(None),
        }
    }
}

fn main() {
    let original = CachedValue {
        value: 5,
        cached_text: RefCell::new(Some("five".into())),
    };
    let copy = original.clone();
    assert_eq!(copy.value, 5);
    assert!(copy.cached_text.borrow().is_none());
}
```

Document non-obvious clone semantics: callers generally expect a clone to represent the same logical value even if caches or other derived state are rebuilt.

## `clone_from` Is Type-Specific

The `Clone` trait permits implementations to specialize `clone_from(&mut self, source)` and reuse resources, but the trait itself does not promise allocation reuse.

For types such as `String` and `Vec<T>`, the standard library implementation can reuse destination storage when possible:

```rust
fn main() {
    let mut destination = String::with_capacity(128);
    let source = String::from("hello");

    destination.clone_from(&source);
    assert_eq!(destination, "hello");
}
```

Use `clone_from` in repeated-update code when the concrete type documents useful reuse and profiling shows allocation pressure. Do not claim the same optimization for every `Clone` implementation.

## Avoid Unrelated “Clone Avoidance” Tricks

APIs such as `Cell::update` are about interior mutation of `Copy` values, not a general replacement for cloning. Keep them in their own rule rather than presenting them as part of the `Clone` cost model.

## Practical Guidance

- Move when the caller no longer needs the original value.
- Borrow when the callee does not need ownership.
- Clone when two valid owned values are actually required.
- Treat clone cost as type-specific: inspect the concrete type and workload.
- Use `Arc::clone`/`Rc::clone` to express shared ownership, not as generic “cheap clone” replacements.
- Derive `Clone` when field-wise cloning matches the logical semantics; implement it manually only for a reason.
- Use `clone_from` optimizations only where the concrete implementation supports them meaningfully.

## See Also

- [own-copy-small](./own-copy-small.md) - When implicit `Copy` is appropriate
- [own-cow-conditional](./own-cow-conditional.md) - Borrow-or-own patterns
- [mem-clone-from](./mem-clone-from.md) - Reusing destination resources during repeated cloning
