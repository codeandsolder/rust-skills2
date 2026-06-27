# own-cow-rpit-edition2024

**Rule**: `own-cow-rpit-edition2024`

> Edition 2024 RPIT lifetime capture makes `Cow<'_, T>` returns from methods borrowing `&self` dramatically more ergonomic

## Why It Matters

Before Edition 2024, returning `Cow<'_, str>` (or any type containing a borrowed lifetime) from a method that takes `&self` required either explicit lifetime annotations or clone-for-lifetime workarounds. Edition 2024's automatic RPIT lifetime capture eliminates the friction, making `Cow` returns practical in many new contexts.

## Bad (Edition 2021 / pre-2024)

```rust
use std::borrow::Cow;

struct NameFormatter {
    prefix: String,
    name: String,
}

impl NameFormatter {
    // Must explicitly name the lifetime or use clone workarounds
    fn format(&self) -> Cow<'_, str> {
        if self.prefix.is_empty() {
            Cow::Borrowed(&self.name)
        } else {
            Cow::Owned(format!("{} {}", self.prefix, self.name))
        }
    }

    // With impl Trait return: explicit '_ required
    fn display(&self) -> impl std::fmt::Display + '_ {
        if self.prefix.is_empty() {
            Cow::Borrowed(&self.name)
        } else {
            Cow::Owned(format!("{} {}", self.prefix, self.name))
        }
    }
}
```

## Good (Edition 2024)

```rust
impl NameFormatter {
    // Lifetime is automatically captured from &self
    fn format(&self) -> Cow<'_, str> {
        if self.prefix.is_empty() {
            Cow::Borrowed(&self.name)
        } else {
            Cow::Owned(format!("{} {}", self.prefix, self.name))
        }
    }

    // No need for + '_ — automatically captured
    fn display(&self) -> impl std::fmt::Display {
        if self.prefix.is_empty() {
            Cow::Borrowed(&self.name)
        } else {
            Cow::Owned(format!("{} {}", self.prefix, self.name))
        }
    }
}
```

## Eliminates Clone-for-Lifetime Workarounds

The most common workaround for lifetime issues with `Cow` was cloning data to escape the borrow:

```rust
// Edition 2021: must clone to satisfy lifetime requirements
fn get_config_value_cow<'a>(&'a self, key: &'a str) -> Cow<'a, str> {
    // Fine — lifetime explicitly connected
}

// But when collecting into a Vec<Cow<'_, str>>:
fn get_config_keys(&self) -> Vec<Cow<'_, str>> {
    self.config.keys().map(|k| Cow::Borrowed(k.as_str())).collect()
    // Edition 2021: compiles, but the lifetime may be more restrictive
    // than needed, forcing callers to clone
}

// Edition 2024: the lifetime is captured, and callers benefit from
// the precise borrowing relationship
fn get_config_keys(&self) -> Vec<Cow<'_, str>> {
    self.config.keys().map(|k| Cow::Borrowed(k.as_str())).collect()
    // Works naturally, lifetimes handled automatically
}
```

## Impact on API Design

With Edition 2024 RPIT capture, `Cow<'_, T>` becomes a more practical return type for methods that conditionally allocate:

```rust
struct Cache {
    entries: HashMap<String, String>,
}

impl Cache {
    // Returns borrowed if found, owned if created
    fn get_or_create(&self, key: &str) -> Cow<'_, str> {
        if let Some(v) = self.entries.get(key) {
            Cow::Borrowed(v)
        } else {
            Cow::Owned(compute_default(key))
        }
    }
}
```

Previously, this pattern either:
1. Required explicit lifetime annotations everywhere.
2. Forced callers to clone unnecessarily.
3. Required `Arc` or `Rc` sharing to avoid lifetime issues.

## When Not to Use Cow with RPIT

| Situation | Alternative |
|-----------|-------------|
| Always returns owned | Just return `String` |
| Always returns borrowed | Just return `&str` |
| Hot path micro-optimization | Profile both approaches |
| Multi-threaded with borrowing | Consider `Arc<str>` |

## Cross-Reference

- [own-lifetime-elision](own-lifetime-elision.md) — Full lifetime elision guide including Edition 2024
- [own-cow-conditional](own-cow-conditional.md) — General Cow usage patterns
- [own-borrow-over-clone](own-borrow-over-clone.md) — Avoiding unnecessary clones

## See Also

- [own-cow-conditional](./own-cow-conditional.md) — General Cow usage patterns
- [own-lifetime-elision](./own-lifetime-elision.md) — Lifetime elision rules
- [doc-test-edition-2024](./doc-test-edition-2024.md) — Edition 2024 doc test changes

## References

- [Edition 2024 RPIT lifetime capture guide](https://doc.rust-lang.org/edition-guide/rust-2024/rpit-lifetime-capture.html)
- [Rust 1.85.0 release notes](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/)
- [Rust 2024 Annotated](https://bertptrs.nl/2025/02/23/rust-edition-2024-annotated.html)
