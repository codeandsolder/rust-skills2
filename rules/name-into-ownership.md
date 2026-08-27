# name-into-ownership

> Use `into_` for ad-hoc conversions that consume an owned value and produce another owned representation

## Why It Matters

Rust's API Guidelines use `as_`, `to_`, and `into_` to communicate both ownership and approximate cost shape:

| Prefix | Typical ownership | Cost |
|---|---|---|
| `as_` | borrowed → borrowed | free / trivial view |
| `to_` | borrowed → owned, or a nontrivial borrowed conversion | potentially expensive |
| `into_` | owned → owned for non-`Copy` values | variable |

The defining signal of `into_` is that the receiver is consumed. It does **not** promise that the conversion is free, infallible, or non-panicking.

## Wrapper Extraction

When a wrapper owns one underlying value, `into_inner()` is the conventional consuming accessor:

```rust
struct Wrapper<T> {
    inner: T,
}

impl<T> Wrapper<T> {
    fn new(inner: T) -> Self {
        Self { inner }
    }

    fn into_inner(self) -> T {
        self.inner
    }
}

fn main() {
    let wrapper = Wrapper::new(String::from("hello"));
    let inner = wrapper.into_inner();
    assert_eq!(inner, "hello");
}
```

The original `wrapper` is moved by the call and cannot be used afterward.

## Standard-Library Examples

These calls consume their owner and expose another owned representation:

```rust
use std::ffi::OsString;
use std::path::PathBuf;

fn main() {
    let string = String::from("hello");
    let bytes: Vec<u8> = string.into_bytes();
    assert_eq!(bytes, b"hello");

    let path = PathBuf::from("example");
    let os_string: OsString = path.into_os_string();
    assert_eq!(os_string, OsString::from("example"));

    let boxed: Box<[i32]> = vec![1, 2, 3].into_boxed_slice();
    let values: Vec<i32> = boxed.into_vec();
    assert_eq!(values, vec![1, 2, 3]);
}
```

## `into_` Does Not Mean “Free”

Some consuming conversions can perform significant work. `BufWriter::into_inner`, for example, attempts to flush buffered data before returning the underlying writer and can fail.

Likewise, a consuming conversion can validate or transform data and return a `Result`. The prefix communicates ownership transfer, not an infallibility guarantee.

```rust
use std::ffi::CString;

fn main() {
    let c = CString::new("hello").unwrap();
    let string = c.into_string().unwrap();
    assert_eq!(string, "hello");
}
```

Do not replace every fallible consuming method with a generic name like `try_into()`. `TryInto`/`TryFrom` are standard conversion traits when the source and target types naturally define the conversion; an ad-hoc method may still appropriately be named `into_string`, `into_inner`, or `try_into_parts` depending on its semantics and surrounding API.

## `IntoIterator` Is the Collection Convention

For collection-like types, consuming iteration is expressed through `IntoIterator` and commonly surfaced as `into_iter()`:

```rust
fn main() {
    let values = vec![1, 2, 3];
    let collected: Vec<_> = values.into_iter().map(|x| x * 2).collect();
    assert_eq!(collected, vec![2, 4, 6]);
}
```

Contrast this with `iter()` and `iter_mut()`, which borrow the collection.

## Implement `IntoIterator`, Not Merely an Inherent Lookalike

```rust
struct Bag<T> {
    items: Vec<T>,
}

impl<T> IntoIterator for Bag<T> {
    type Item = T;
    type IntoIter = std::vec::IntoIter<T>;

    fn into_iter(self) -> Self::IntoIter {
        self.items.into_iter()
    }
}

fn main() {
    let bag = Bag { items: vec![1, 2, 3] };
    assert_eq!(bag.into_iter().sum::<i32>(), 6);
}
```

This also makes `for item in bag` work naturally.

## Conversion Prefixes Describe Different Contracts

```rust
struct Buffer {
    data: Vec<u8>,
}

impl Buffer {
    fn as_slice(&self) -> &[u8] {
        &self.data
    }

    fn to_vec(&self) -> Vec<u8> {
        self.data.clone()
    }

    fn into_vec(self) -> Vec<u8> {
        self.data
    }
}

fn main() {
    let buffer = Buffer { data: vec![1, 2, 3] };
    assert_eq!(buffer.as_slice(), &[1, 2, 3]);
    assert_eq!(buffer.to_vec(), vec![1, 2, 3]);
    assert_eq!(buffer.into_vec(), vec![1, 2, 3]);
}
```

The `into_` form is appropriate because it consumes the non-`Copy` owner and transfers its owned representation.

## Clippy Enforcement

`clippy::wrong_self_convention` checks that an `into_*` method takes `self` by value. It also checks the conventional receiver shapes of `as_*`, `is_*`, and `to_*` methods.

```toml
[lints.clippy]
wrong_self_convention = "warn"
```

This is a naming/receiver convention lint, not proof that a conversion has a particular performance or failure behavior.

## Practical Guidance

- Use `into_foo(self)` when consuming a non-`Copy` owner to produce owned `foo` data.
- Do not read `into_` as “free”; the cost is intentionally variable.
- Do not read `into_` as “infallible”; consuming conversions may return `Result`.
- Use `From`/`TryFrom` when the conversion naturally belongs in the standard conversion trait ecosystem.
- Implement `IntoIterator` for consuming collection iteration rather than only inventing an inherent method.
- Let the method name describe the semantic target (`into_inner`, `into_bytes`, `into_parts`) rather than only the fact that failure is possible.

## See Also

- [name-as-free](./name-as-free.md) - Borrowed conversions
- [name-to-expensive](./name-to-expensive.md) - `to_` conversions
- [api-from-not-into](./api-from-not-into.md) - `From`/`Into` trait guidance
- [name-iter-convention](./name-iter-convention.md) - Iterator ownership conventions
