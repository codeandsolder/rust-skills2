# own-lazy-init

> Use `std::sync::LazyLock` / `std::cell::LazyCell` for lazily initialized shared data

## Why It Matters

`LazyLock` (thread-safe) and `LazyCell` (single-threaded) provide deferred initialization — a value is computed exactly once on first access. They replace the `lazy_static!` crate and hand-rolled `OnceLock` / `OnceCell` patterns, giving you clean ownership semantics for lazily initialized data without external dependencies.

## Bad

```rust
// External crate when std already provides what you need
use lazy_static::lazy_static;

lazy_static! {
    static ref CONFIG: Config = Config::load();
}

// Hand-rolled with OnceLock — verbose and error-prone
use std::sync::OnceLock;

fn get_config() -> &'static Config {
    static CONFIG: OnceLock<Config> = OnceLock::new();
    CONFIG.get_or_init(|| Config::load())
}

// thread_local with RefCell — runtime borrow-checking overhead
use std::cell::RefCell;

thread_local! {
    static BUF: RefCell<Vec<u8>> = RefCell::new(Vec::new());
}
```

## Good

```rust
use std::sync::LazyLock;

static CONFIG: LazyLock<Config> = LazyLock::new(Config::load);

// First access triggers init; subsequent accesses are fast reads
fn get_config() -> &'static Config {
    &CONFIG
}
```

## Single-Threaded: LazyCell

For single-threaded contexts, use `LazyCell` for zero atomic overhead:

```rust
use std::cell::LazyCell;

thread_local! {
    static BUF: LazyCell<Vec<u8>> = const { LazyCell::new(Vec::new) };
}
```

## LazyLock with Arc for Shared References

```rust
use std::sync::{Arc, LazyLock};

static GLOBAL_DATA: LazyLock<Arc<[u8]>> = LazyLock::new(|| {
    vec![0u8; 1024 * 1024].into_boxed_slice().into()
});

fn get_data() -> Arc<[u8]> {
    GLOBAL_DATA.clone()  // Cheap Arc clone
}
```

## LazyLock vs LazyCell Decision

| Context | Type | Overhead |
|---------|------|----------|
| Multi-threaded `static` | `sync::LazyLock` | Atomic synchronization |
| Single-threaded `static` | `cell::LazyCell` | No atomic overhead |
| `thread_local!` with lazy init | `cell::LazyCell` | Per-thread storage |

## Recent Additions

### `LazyCell` / `LazyLock` implement `From<T>` (1.96)

Direct construction from an already-initialized value, no closure needed:

```rust
use std::sync::LazyLock;

// 1.96+: construct from value directly
static NAME: LazyLock<String> = LazyLock::from("hello".to_string());

// Equivalent to (but more ergonomic than):
static NAME: LazyLock<String> = LazyLock::new(|| "hello".to_string());
```

### `LazyCell::get` / `LazyLock::get` (1.94)

```rust
use std::sync::LazyLock;

static CACHE: LazyLock<HashMap<String, String>> = LazyLock::new(HashMap::new);

// 1.94+: check if initialized without forcing init
// Returns Some(&T) if initialized, None otherwise
let is_loaded = CACHE.get().is_some();
```

## When Not to Use Lazy Types

| Situation | Alternative |
|-----------|-------------|
| Value is always needed eagerly | `const` or regular `static` |
| Initialization is trivial | `const` (inlined at compile time) |
| Need mutable access | `Mutex<T>` / `RwLock<T>` inside a `LazyLock` |
| Multiple initialization sites | `OnceLock` for imperative initialization |

## See Also

- [own-arc-shared](./own-arc-shared.md) — Arc for thread-safe shared ownership
- [own-rc-single-thread](./own-rc-single-thread.md) — Rc for single-threaded shared ownership
- [own-refcell-interior](./own-refcell-interior.md) — Interior mutability with RefCell
