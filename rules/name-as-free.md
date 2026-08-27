# name-as-free

> Use `as_` for free borrowed conversions

## Why It Matters

Rust's ad-hoc conversion naming convention communicates both ownership and expected cost. An `as_` method is for a **free borrowed-to-borrowed conversion**: it does not consume the receiver and should not perform allocation or other nontrivial work.

The result is often a reference, but not necessarily. For example, the standard library also uses `as_ptr()` for free raw-pointer views.

| Prefix | Expected cost | Ownership shape |
|--------|---------------|-----------------|
| `as_` | Free | borrowed → borrowed |
| `to_` | Expensive | borrowed → borrowed, borrowed → owned, or Copy owned → owned |
| `into_` | Variable | non-Copy owned → owned |

These are conventions for ad-hoc conversion methods, not a claim that every method returning a reference should start with `as_`.

## Examples

```rust
struct MyString {
    inner: String,
}

impl MyString {
    pub fn as_str(&self) -> &str {
        &self.inner
    }

    pub fn as_bytes(&self) -> &[u8] {
        self.inner.as_bytes()
    }

    pub fn as_ptr(&self) -> *const u8 {
        self.inner.as_ptr()
    }
}

struct Wrapper<T> {
    inner: T,
}

impl<T> Wrapper<T> {
    pub fn as_inner(&self) -> &T {
        &self.inner
    }

    pub fn as_inner_mut(&mut self) -> &mut T {
        &mut self.inner
    }
}
```

## Standard Library Examples

```rust
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

let s = String::from("hello");
let bytes: &[u8] = s.as_bytes();
let str_ref: &str = s.as_str();

let v = vec![1, 2, 3];
let slice: &[i32] = v.as_slice();

let p = PathBuf::from("/home");
let path: &Path = p.as_path();

let os = OsString::from("hello");
let os_str: &OsStr = os.as_os_str();
```

## Bad

<!-- rust-check: compile -->
```rust
struct ProcessedData;

struct MyType {
    value: u32,
    source: Vec<u8>,
    processed: ProcessedData,
}

impl MyType {
    // BAD: `as_` suggests a free borrowed conversion, but this allocates.
    pub fn as_string(&self) -> String {
        format!("{}", self.value)
    }

    // BAD: returning a borrow does not make the operation free. This scans
    // the source before returning an existing borrowed result.
    pub fn as_processed(&self) -> &ProcessedData {
        let _checksum = self.source.iter().fold(0u8, |a, b| a.wrapping_add(*b));
        &self.processed
    }
}
```

## Good

<!-- rust-check: compile -->
```rust
struct Inner;

struct MyType {
    inner: String,
    value: u32,
    payload: Inner,
}

impl MyType {
    // GOOD: free borrowed view.
    pub fn as_str(&self) -> &str {
        &self.inner
    }

    // GOOD: `to_` signals that creating the new value does work.
    pub fn to_display_string(&self) -> String {
        format!("{}", self.value)
    }

    // GOOD: `into_` consumes the wrapper and transfers ownership.
    pub fn into_inner(self) -> Inner {
        self.payload
    }
}
```

## `mut` Qualifier Convention

When `mut` describes the conversion's return type, put it where it appears in the type: `as_mut_slice`, not `as_slice_mut`.

```rust
struct MyCollection<T> {
    items: Vec<T>,
}

impl<T> MyCollection<T> {
    pub fn as_mut_slice(&mut self) -> &mut [T] {
        self.items.as_mut_slice()
    }
}
```

## Pointer Views

`as_` is not restricted to Rust references. Raw-pointer access is also commonly a free borrowed conversion:

```rust
struct Buffer(Vec<u8>);

impl Buffer {
    pub fn as_ptr(&self) -> *const u8 {
        self.0.as_ptr()
    }

    pub fn as_mut_ptr(&mut self) -> *mut u8 {
        self.0.as_mut_ptr()
    }
}
```

## Clippy Receiver Convention

`clippy::wrong_self_convention` also checks receiver conventions implied by names such as `as_*`, `to_*`, and `into_*`. The naming convention is still semantic: satisfying the receiver shape does not make an expensive `as_*` implementation appropriate.

```rust
struct Value;

impl Value {
    // This compiles, but Clippy's wrong_self_convention warns because an
    // `as_*` method should borrow rather than consume `self`.
    pub fn as_text(self) -> &'static str {
        "value"
    }
}
```

## See Also

- [name-to-expensive](name-to-expensive.md) - `to_` for conversions that do work
- [name-into-ownership](name-into-ownership.md) - `into_` for ownership-consuming conversions
