# anti-string-for-str

> Prefer `&str` over `&String` when the API only needs string contents

## Why It Matters

`&str` is the natural borrowed string-view type. It accepts string literals, slices, and borrowed `String` values through deref coercion. A `&String` parameter unnecessarily requires the caller to possess the specific owned `String` representation even when the function only reads text.

This does **not** mean `&String` is invalid. Use it when the API genuinely needs `String`-specific state such as capacity. The rule is to accept the least restrictive borrowed type that provides the operations the function actually needs.

## Bad

<!-- rust-check: compile -->
```rust
struct Config {
    name: String,
}

fn greet(name: &String) {
    println!("Hello, {name}");
}

impl Config {
    fn set_name(&mut self, name: &String) {
        self.name = name.clone();
    }
}

fn example() {
    let name = String::from("Bob");
    greet(&name);

    // A literal cannot be passed directly because the function demands
    // &String, so this caller constructs an owned String for no semantic need.
    greet(&"Alice".to_string());
}
```

A caller that already has a `String` does not allocate merely because the parameter is `&String`; the problem is that the signature excludes other perfectly suitable string views and can force ownership/construction at some call sites.

## Good

<!-- rust-check: compile -->
```rust
struct Config {
    name: String,
}

fn greet(name: &str) {
    println!("Hello, {name}");
}

impl Config {
    fn set_name(&mut self, name: &str) {
        self.name.clear();
        self.name.push_str(name);
    }

    // If callers often already own a String and ownership transfer is useful,
    // offer an owned form instead of borrowing and cloning it.
    fn set_name_owned(&mut self, name: String) {
        self.name = name;
    }
}

fn example() {
    let name = String::from("Bob");
    let slice: &str = &name[..2];

    greet("Alice");
    greet(&name); // &String coerces to &str
    greet(slice);
}
```

## Deref Coercion

`String` implements `Deref<Target = str>`, so an existing `&String` usually passes to a `&str` parameter without an explicit conversion:

```rust
fn takes_str(text: &str) -> usize {
    text.len()
}

let owned = String::from("hello");
assert_eq!(takes_str(&owned), 5);
```

This is why `&str` improves the callee's API without making normal `String` callers awkward.

## When `&String` Is Actually Appropriate

If the operation depends on owned-string representation state, `&String` can be the honest type:

```rust
fn spare_capacity(text: &String) -> usize {
    text.capacity() - text.len()
}
```

Likewise, code that needs to grow or otherwise mutate the owned allocation may appropriately take `&mut String` rather than `&mut str`:

```rust
fn append_suffix(text: &mut String) {
    text.push_str(".log");
}
```

Do not contort such APIs merely to avoid spelling `String`.

## `impl AsRef<str>` Is a Different Trade-off

A generic `AsRef<str>` parameter can accept both owned and borrowed string-like inputs:

```rust
fn normalized_len(input: impl AsRef<str>) -> usize {
    input.as_ref().trim().len()
}

assert_eq!(normalized_len(" hello "), 5);
assert_eq!(normalized_len(String::from("world")), 5);
```

That is useful when accepting the value by generic parameter is part of the API design. It is not automatically “more flexible” or better than `&str`: generics affect monomorphization, function types, trait-object use, and public API shape. For a function that simply borrows text for the duration of the call, `&str` is usually the simpler contract.

## Related Borrowed Views

The same principle applies to common owned/container types when only their view is required:

| Owned-specific borrow | Prefer when only a view is needed |
|-----------------------|-----------------------------------|
| `&String` | `&str` |
| `&Vec<T>` | `&[T]` |
| `&PathBuf` | `&Path` |
| `&OsString` | `&OsStr` |
| `&Box<T>` | `&T` |

But representation-specific operations can justify the owned-specific borrow.

## Clippy Detection

Clippy's `ptr_arg` lint catches parameters such as `&String`, `&Vec<T>`, and similar owned-container references when a borrowed view is sufficient:

```toml
[lints.clippy]
ptr_arg = "warn"
```

Treat public API changes carefully. Changing `fn(&String)` to `fn(&str)` works for many ordinary call sites through coercion, but it is still a function-signature change and can break function pointers, trait implementations, or other type-level uses. Deprecate/migrate deliberately when semver compatibility matters.

## See Also

- [anti-vec-for-slice](./anti-vec-for-slice.md) — Borrow slices instead of `Vec` when possible
- [own-slice-over-vec](./own-slice-over-vec.md) — Slice-oriented APIs
- [api-impl-asref](./api-impl-asref.md) — `AsRef` trade-offs
