# own-refcell-interior

> Use `RefCell<T>` when thread-local shared access genuinely needs runtime-checked interior mutability

## Why It Matters

`RefCell<T>` lets code mutate a value through a shared reference by moving Rust's usual borrow checks from compile time to runtime. A shared borrow comes from `borrow()` and an exclusive borrow from `borrow_mut()`; violating the same aliasing rules that ordinary references enforce causes a panic (or a `BorrowError` / `BorrowMutError` with the `try_` methods).

This is useful for caches, graph-like ownership, test doubles, callbacks, and other cases where the program can uphold borrowing discipline but the static borrow checker cannot conveniently express it.

`RefCell<T>` is not `Sync`, so it is not a shared cross-thread synchronization primitive. Use `Mutex`, `RwLock`, atomics, or message passing for concurrently shared state.

## Bad: Forcing Exclusive Access to the Whole Owner

```rust
use std::collections::HashMap;

struct Cache {
    data: HashMap<String, String>,
}

impl Cache {
    fn get_or_compute(&mut self, key: &str) -> String {
        self.data
            .entry(key.to_owned())
            .or_insert_with(|| format!("computed:{key}"))
            .clone()
    }
}
```

This requires `&mut Cache` even if the cache is otherwise logically shared.

## Good: Keep the Runtime Borrow Small

```rust
use std::cell::RefCell;
use std::collections::HashMap;

struct Cache {
    data: RefCell<HashMap<String, String>>,
}

impl Cache {
    fn new() -> Self {
        Self {
            data: RefCell::new(HashMap::new()),
        }
    }

    fn get_or_compute(&self, key: &str) -> String {
        let mut data = self.data.borrow_mut();
        data.entry(key.to_owned())
            .or_insert_with(|| format!("computed:{key}"))
            .clone()
    }
}

fn main() {
    let cache = Cache::new();
    let a = &cache;
    let b = &cache;

    assert_eq!(a.get_or_compute("one"), "computed:one");
    assert_eq!(b.get_or_compute("two"), "computed:two");
}
```

Prefer to finish the `Ref` / `RefMut` borrow before calling unrelated code. Holding runtime borrows for large scopes makes re-entrant callbacks and nested operations more likely to panic.

## Common Pattern: `Rc<RefCell<T>>`

```rust
use std::cell::RefCell;
use std::rc::Rc;

#[derive(Default)]
struct Counter(i32);

type SharedCounter = Rc<RefCell<Counter>>;

fn incrementer(counter: SharedCounter) -> impl Fn() {
    move || counter.borrow_mut().0 += 1
}

fn main() {
    let counter = Rc::new(RefCell::new(Counter::default()));
    let inc_a = incrementer(Rc::clone(&counter));
    let inc_b = incrementer(Rc::clone(&counter));

    inc_a();
    inc_b();
    assert_eq!(counter.borrow().0, 2);
}
```

This is appropriate when ownership is shared within one thread. It is not a substitute for `Arc<Mutex<T>>` when the state must be shared concurrently across threads.

## Runtime Borrow Failures

```rust
use std::cell::RefCell;

fn main() {
    let cell = RefCell::new(5);
    let shared = cell.borrow();

    assert!(cell.try_borrow_mut().is_err());
    drop(shared);

    *cell.borrow_mut() += 1;
    assert_eq!(*cell.borrow(), 6);
}
```

Use `try_borrow()` / `try_borrow_mut()` when contention in the runtime borrow state is an expected condition rather than a programming bug.

## `Cell::update` Is Not Atomic

For `Copy` values, `Cell::update` (stable since Rust 1.88) is convenient syntax for a single-threaded read-transform-write:

```rust
use std::cell::Cell;

fn main() {
    let counter = Cell::new(0u32);
    counter.update(|x| x + 1);
    assert_eq!(counter.get(), 1);
}
```

This operation is **not atomic or synchronizing**. `Cell` is `!Sync`; for cross-thread atomic read-modify-write operations use the appropriate type from `std::sync::atomic`.

See [own-cell-update](./own-cell-update.md) for the dedicated rule.

## Edition 2024: `if let` Temporaries Are Shorter on the `else` Path

Rust 2024 narrows the temporary scope of an `if let` scrutinee. When the pattern **does not match**, scrutinee temporaries are dropped before entering `else`. This can matter for `RefCell`, locks, and other guard-like temporaries.

```rust
use std::cell::RefCell;

fn main() {
    let cell = RefCell::new(None::<String>);

    if let Some(value) = cell.borrow().as_ref() {
        println!("{value}");
    } else {
        // In Edition 2024, the failed-pattern scrutinee borrow has been dropped
        // before this branch starts, so an exclusive borrow is available.
        *cell.borrow_mut() = Some("filled".to_owned());
    }

    assert_eq!(cell.borrow().as_deref(), Some("filled"));
}
```

The change does **not** mean the temporary is dropped before the successful `then` branch. If a successful pattern binds a reference derived from `cell.borrow()`, the `Ref` must remain alive while that reference is used. Attempting `borrow_mut()` in that branch can still panic.

In Edition 2021, `if let` scrutinee temporaries could live through the entire `if let` expression, including `else`; the 2024 rule specifically shortens that lifetime when control enters `else`.

## Edition 2024: Tail-Expression Temporaries Are Dropped Earlier

The other relevant Edition 2024 change is also a **narrowing**, not an extension: temporaries created by a block's tail expression are dropped at the end of that block, before local variables in the block are dropped.

```rust
use std::cell::RefCell;

fn len_of_local() -> usize {
    let text = RefCell::new(String::from("hello"));
    text.borrow().len()
}

fn main() {
    assert_eq!(len_of_local(), 5);
}
```

This pattern could fail borrow checking in Edition 2021 because the `Ref` temporary from the tail expression was scheduled to outlive the local `RefCell`. Edition 2024 drops the `Ref` first, allowing the local to be dropped afterward.

Do not describe this as extending a temporary to cover the caller's use—the edition deliberately makes these temporary scopes shorter.

## Choosing an Interior-Mutability Primitive

| Need | Typical choice |
|------|----------------|
| `Copy` value, thread-local shared mutation | `Cell<T>` |
| General value, thread-local runtime-checked borrowing | `RefCell<T>` |
| Shared mutation across threads | `Mutex<T>` / `RwLock<T>` |
| Cross-thread scalar/flag/counter | atomic type when its memory-ordering model fits |

Prefer ordinary `&mut T` whenever ownership already gives you exclusive access; runtime borrow checking is useful when it solves an actual ownership shape, not as a default replacement for normal borrowing.

## See Also

- [own-cell-update](./own-cell-update.md) — `Cell::update` for `Copy` types
- [own-rc-single-thread](./own-rc-single-thread.md) — shared single-thread ownership
- [own-mutex-interior](./own-mutex-interior.md) — synchronized shared mutation
- [own-rwlock-readers](./own-rwlock-readers.md) — read-heavy synchronized state

## References

- [std::cell::RefCell](https://doc.rust-lang.org/std/cell/struct.RefCell.html)
- [Rust 2024 Edition Guide: if-let temporary scope](https://doc.rust-lang.org/edition-guide/rust-2024/temporary-if-let-scope.html)
- [Rust 2024 Edition Guide: tail-expression temporary scope](https://doc.rust-lang.org/edition-guide/rust-2024/temporary-tail-expr-scope.html)
