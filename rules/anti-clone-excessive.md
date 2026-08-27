# anti-clone-excessive

> Do not clone merely to satisfy ownership when borrowing, moving, or deliberate sharing better matches the API

## Why It Matters

`Clone` is an ownership operation, not a synonym for “heap allocation.” Its cost is entirely type-dependent:

- cloning a small plain value may be just a copy;
- cloning `String` or `Vec<T>` generally duplicates owned contents and may allocate;
- cloning `Arc<T>` increments a reference count rather than duplicating `T`;
- clone-on-write types can share heap storage until mutation.

The right question is therefore not “can I eliminate every `.clone()`?” but **what ownership relationship does this code need, and what does cloning this concrete type cost?**

## Borrow When the Callee Only Needs a View

```rust
fn print_name(name: &str) {
    println!("{name}");
}

fn main() {
    let name = String::from("Alice");
    print_name(&name);
    print_name(name.as_str());
    assert_eq!(name, "Alice");
}
```

Taking `String` by value would force callers that still need their string to move or clone it. A borrowed API is clearer when the function only reads the text during the call.

## Iterate by Reference When Ownership Is Not Needed

```rust
fn total_lengths(items: &[String]) -> usize {
    items.iter().map(String::len).sum()
}

fn main() {
    let items = vec![String::from("a"), String::from("rust")];
    assert_eq!(total_lengths(&items), 5);
    assert_eq!(items.len(), 2);
}
```

Cloning the entire vector just to traverse it would duplicate ownership without changing the algorithm.

## Move When the Source Is Finished

Sometimes the best clone is no clone because ownership can simply move:

```rust
fn consume(value: String) -> usize {
    value.len()
}

fn main() {
    let value = String::from("owned");
    let len = consume(value);
    assert_eq!(len, 5);
}
```

Do not borrow reflexively either. Moving is often simpler when the caller is done with the value.

## Clone When Independent Ownership Is Actually Required

```rust
fn retain_original_and_make_copy(value: &String) -> (String, usize) {
    let copy = value.clone();
    (copy, value.len())
}

fn main() {
    let original = String::from("data");
    let (copy, len) = retain_original_and_make_copy(&original);
    assert_eq!(copy, original);
    assert_eq!(len, 4);
}
```

This clone is not a bug: the result needs independent owned text while the original remains usable.

## Shared Ownership Is a Different Contract

When multiple owners should refer to the **same** allocation/value, a reference-counted pointer may express the intent better than deep cloning:

```rust
use std::sync::Arc;

fn main() {
    let shared = Arc::new(String::from("configuration"));
    let another_owner = Arc::clone(&shared);

    assert_eq!(shared.as_str(), "configuration");
    assert_eq!(another_owner.as_str(), "configuration");
    assert_eq!(Arc::strong_count(&shared), 2);
}
```

`Arc` adds atomic reference-counting and shared-ownership semantics. It is not automatically better merely because deep cloning is frequent; choose it only when shared lifetime/identity fits the design.

## Async and Spawned Work Often Needs Ownership

A spawned task generally must own or otherwise receive data that outlives the current stack frame. Cloning can be the simplest correct boundary:

```rust
use std::sync::Arc;

async fn length(value: Arc<String>) -> usize {
    value.len()
}

#[tokio::main]
async fn main() {
    let value = Arc::new(String::from("hello"));
    let task_value = Arc::clone(&value);

    let task = tokio::spawn(async move { length(task_value).await });
    assert_eq!(task.await.unwrap(), 5);
    assert_eq!(value.as_str(), "hello");
}
```

The ownership boundary is real here; trying to force a short-lived borrow into a `'static` spawned future would be the wrong abstraction.

## `clone_from` Is an Optional Reuse Opportunity

`Clone::clone_from` replaces an existing value from another value of the same type. The trait permits implementations to reuse resources, but does **not** guarantee allocation reuse for every `Clone` type.

```rust
fn main() {
    let source = String::from("new contents");
    let mut destination = String::with_capacity(64);
    destination.push_str("old");

    destination.clone_from(&source);
    assert_eq!(destination, source);
}
```

Use `clone_from` when you already have a destination and the concrete implementation can profit from reuse. See [mem-clone-from](./mem-clone-from.md) for the detailed contract.

## Clone-on-Write Can Fit Conditional Ownership

```rust
use std::borrow::Cow;

fn normalized(input: &str) -> Cow<'_, str> {
    if input.bytes().all(|byte| !byte.is_ascii_uppercase()) {
        Cow::Borrowed(input)
    } else {
        Cow::Owned(input.to_ascii_lowercase())
    }
}

fn main() {
    assert!(matches!(normalized("rust"), Cow::Borrowed(_)));
    assert_eq!(normalized("RUST"), "rust");
}
```

`Cow` is useful when borrowing is common but some paths truly need an owned transformed value. It is not a universal replacement for `Clone`.

## Avoid Both Extremes

“Never clone” creates lifetime and ownership contortions. “Clone first, optimize later” can hide expensive accidental copies in APIs or hot loops. A better process is:

1. model the ownership you need;
2. inspect the concrete clone cost when it matters;
3. keep the simplest correct design;
4. profile/refactor expensive cloning if workload evidence justifies it.

## Clippy Can Catch Mechanical Mistakes

```toml
[lints.clippy]
clone_on_copy = "warn"
clone_on_ref_ptr = "warn"
redundant_clone = "warn"
```

These lints catch some obviously unnecessary clones. They cannot decide whether a semantically necessary deep clone should instead become shared ownership or a different API.

## Practical Guidance

- Borrow when the callee only needs temporary read access.
- Move when the source no longer needs the value.
- Clone when independent ownership is genuinely required.
- Use `Arc`/`Rc` when shared ownership is the intended model, not merely as a generic clone optimization.
- Treat clone cost as type-specific; `Clone` itself promises no allocation behavior.
- Use `clone_from` only as a concrete-type reuse opportunity, not a universal guarantee.
- Prefer clear ownership over lifetime gymnastics, then measure expensive copies in representative workloads.

## See Also

- [own-borrow-over-clone](./own-borrow-over-clone.md) - Borrowing patterns
- [own-cow-conditional](./own-cow-conditional.md) - Conditional ownership
- [own-arc-shared](./own-arc-shared.md) - Shared ownership
- [mem-clone-from](./mem-clone-from.md) - `clone_from` resource reuse
