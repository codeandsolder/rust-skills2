# own-borrow-over-clone

> Borrow when a callee only needs temporary access; clone when the API genuinely needs an independent owned value

## Why It Matters

A clone is an ownership operation, not merely a performance smell. For types such as `String`, `Vec<T>`, or `Arc<T>`, cloning can allocate, copy elements, or update shared-ownership state. A borrow states a different contract: the callee may access the caller's value for a limited lifetime but does not become an owner.

Prefer the contract the operation actually needs. Avoiding every clone at all costs can make APIs harder to use, lengthen borrows, or force awkward lifetime plumbing.

## Good: Borrow Read-Only Inputs

```rust
fn word_count(text: &str) -> usize {
    text.split_whitespace().count()
}

fn checksum(bytes: &[u8]) -> u64 {
    bytes.iter().map(|&byte| u64::from(byte)).sum()
}

fn main() {
    let text = String::from("borrow instead of clone");
    let bytes = vec![1u8, 2, 3];

    assert_eq!(word_count(&text), 4);
    assert_eq!(checksum(&bytes), 6);

    // The owners remain usable because neither function consumed them.
    assert_eq!(text.len(), 23);
    assert_eq!(bytes.len(), 3);
}
```

Prefer `&str` over `&String` and `&[T]` over `&Vec<T>` when the function only needs the borrowed view. That accepts more callers without changing ownership.

## Clone When Ownership Must Outlive the Borrow

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct Config {
    endpoint: String,
}

fn spawn_worker(config: &Config) -> std::thread::JoinHandle<Config> {
    let owned = config.clone();
    std::thread::spawn(move || owned)
}

fn main() {
    let config = Config {
        endpoint: "https://example.test".into(),
    };

    let worker = spawn_worker(&config);
    assert_eq!(worker.join().unwrap(), config);
}
```

The spawned thread needs an owned `'static` value. Cloning is part of the intended ownership transfer here, not a mistake to hide.

## Prefer Moving When the Caller No Longer Needs the Value

```rust
fn normalize(mut value: String) -> String {
    value.make_ascii_lowercase();
    value
}

fn main() {
    let value = String::from("HELLO");
    let value = normalize(value);
    assert_eq!(value, "hello");
}
```

Do not clone merely to preserve a value the caller is about to stop using anyway. Moving transfers ownership without requiring a semantic copy of the allocation.

## Clone the Smallest Thing That Must Become Owned

```rust
#[derive(Debug)]
struct User {
    name: String,
    roles: Vec<String>,
}

fn detached_name(user: &User) -> String {
    user.name.clone()
}

fn main() {
    let user = User {
        name: "Ada".into(),
        roles: vec!["admin".into(), "author".into()],
    };

    let name = detached_name(&user);
    assert_eq!(name, "Ada");
    assert_eq!(user.roles.len(), 2);
}
```

If only one field must be owned independently, cloning the whole aggregate usually expresses the wrong boundary.

## `Vec::pop_if` (Rust 1.86+)

`pop_if` conditionally removes the last element and passes a mutable reference to that element to the predicate. The predicate can inspect or mutate the candidate before deciding whether it is removed.

```rust
fn main() {
    let mut values = vec![1, 2, 3, 4];

    let popped = values.pop_if(|value| *value % 2 == 0);
    assert_eq!(popped, Some(4));
    assert_eq!(values, [1, 2, 3]);

    // The new last item is odd, so it remains in the Vec.
    assert_eq!(values.pop_if(|value| *value % 2 == 0), None);
    assert_eq!(values, [1, 2, 3]);
}
```

This can avoid a pop-then-reinsert ownership dance when the decision only concerns the last element. It is not a general filtering API.

## `slice::get_disjoint_mut` (Rust 1.86+)

When several non-overlapping locations must be mutably borrowed at once, `get_disjoint_mut` performs the overlap/bounds check and returns all references together.

```rust
fn main() {
    let mut values = [10, 20, 30, 40];

    let [first, third] = values.get_disjoint_mut([0, 2]).unwrap();
    *first += 1;
    *third += 3;

    assert_eq!(values, [11, 20, 33, 40]);
    assert!(values.get_disjoint_mut([1, 1]).is_err());
    assert!(values.get_disjoint_mut([0, 99]).is_err());
}
```

The method returns `Result<[&mut _; N], GetDisjointMutError>`, distinguishing overlapping indices from out-of-bounds inputs. It does not return an `Option` that can be destructured with `let ... else` directly.

## Interior Mutability Does Not Make Updates Atomic

`Cell<T>` is a single-threaded interior-mutability primitive. `Cell::update` is convenient read-transform-write syntax for suitable values; it is **not** an atomic synchronization operation.

```rust
use std::cell::Cell;

fn main() {
    let counter = Cell::new(0u32);
    counter.update(|value| value + 1);
    assert_eq!(counter.get(), 1);
}
```

For cross-thread atomic read-modify-write, use the appropriate `Atomic*` operation or another synchronization primitive instead.

## Edition 2024 RPIT Capture Can Simplify Some Borrowing APIs

Rust 2024 changed return-position `impl Trait` capture rules so in-scope generic parameters and lifetimes are captured by default. That can remove some explicit capture annotations that older editions required.

Do not turn that into “cloning is no longer needed for lifetimes.” Whether a returned value can borrow from an input still depends on the returned type and the API's lifetime relationships. Express those relationships directly and clone only when independent ownership is actually required.

## Review Questions

Before calling `.clone()`, ask:

- Does the recipient need ownership, or only temporary read/write access?
- Could the caller move the value instead because it is done with it?
- If ownership is required, can a smaller field/subvalue be cloned?
- Is the clone needed to cross a thread/task/storage lifetime boundary?
- Would avoiding the clone create an awkward long-lived borrow that harms the API?

The goal is clear ownership, not a zero-clone score.

## See Also

- [own-slice-over-vec](./own-slice-over-vec.md) — borrow general views
- [own-cow-conditional](./own-cow-conditional.md) — conditionally borrowed/owned data
- [own-cell-update](./own-cell-update.md) — `Cell::update` semantics
- [mem-clone-from](./mem-clone-from.md) — reuse allocations when copying state

## References

- [`Vec::pop_if`](https://doc.rust-lang.org/std/vec/struct.Vec.html#method.pop_if)
- [`slice::get_disjoint_mut`](https://doc.rust-lang.org/std/primitive.slice.html#method.get_disjoint_mut)
- [Rust 2024 precise capture rules](https://doc.rust-lang.org/edition-guide/rust-2024/rpit-lifetime-capture.html)
