# anti-deref-overuse

> Implement `Deref` only when transparent target-like behavior is part of the type's intended API

## Why It Matters

`Deref` is more than a convenience delegation hook. A `Deref<Target = T>` implementation participates in deref coercion and method lookup, so callers can often use `&Wrapper` where `&T` is expected and can call methods from `T` through the wrapper.

That is appropriate when the wrapper is intended to behave transparently like its target and dereferencing is cheap and unsurprising. It is usually a poor fit for an invariant-bearing domain newtype whose abstraction is meant to remain visible.

Do not describe deref coercion as bypassing construction validation: if an `Email` was already constructed through a checked constructor, obtaining `&str` from that valid value does not retroactively bypass the constructor. The concern is API design: implicit coercion and target methods become part of the wrapper's public behavior.

## Bad: Incidental Delegation Through `Deref`

<!-- rust-check: compile -->
```rust
use std::ops::Deref;

#[derive(Debug, Clone)]
struct Email(String);

impl Deref for Email {
    type Target = str;

    fn deref(&self) -> &str {
        &self.0
    }
}

fn send_to(address: &str) -> usize {
    address.len()
}

fn main() {
    let email = Email("test@example.com".to_owned());

    // These compile because Deref makes transparent string-like behavior
    // part of Email's API, whether or not that was the design intent.
    assert!(email.ends_with("example.com"));
    assert_eq!(send_to(&email), email.len());
}
```

This code is type-correct. The anti-pattern is choosing `Deref` merely to avoid writing the domain API you actually want.

## Good: Explicit Access for an Invariant-Bearing Newtype

<!-- rust-check: compile -->
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Email(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ValidationError;

impl Email {
    pub fn parse(raw: &str) -> Result<Self, ValidationError> {
        let valid = raw
            .split_once('@')
            .is_some_and(|(local, domain)| !local.is_empty() && !domain.is_empty());

        if valid {
            Ok(Self(raw.to_owned()))
        } else {
            Err(ValidationError)
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn domain(&self) -> &str {
        self.0
            .split_once('@')
            .map_or("", |(_, domain)| domain)
    }
}

fn send_to(address: &str) -> usize {
    address.len()
}

fn main() {
    let email = Email::parse("test@example.com").unwrap();
    assert_eq!(email.domain(), "example.com");
    assert_eq!(send_to(email.as_str()), 16);
    assert!(Email::parse("not-an-email").is_err());
}
```

The conversion to `&str` is now visible at the call site and the wrapper controls which domain-specific operations it exposes.

## `Deref` Can Be Correct Beyond `Box`

The standard library guidance is broader than “only implement this for smart pointers.” A custom type can reasonably implement `Deref` when all of these are true:

- it transparently behaves like the target type;
- dereferencing is cheap;
- exposing the target's methods and coercions is unsurprising;
- that relationship is stable enough to become part of the public API.

Pointer-like owners are the common case, but the semantic test matters more than a hardcoded whitelist.

<!-- rust-check: compile -->
```rust
use std::ops::Deref;

struct ReadOnlyBuffer(Vec<u8>);

impl Deref for ReadOnlyBuffer {
    type Target = [u8];

    fn deref(&self) -> &[u8] {
        &self.0
    }
}

fn checksum(bytes: &[u8]) -> u64 {
    bytes.iter().map(|&b| u64::from(b)).sum()
}

fn main() {
    let buffer = ReadOnlyBuffer(vec![1, 2, 3]);
    assert_eq!(checksum(&buffer), 6);
}
```

Whether this particular wrapper *should* be transparent is still an API decision; the example only shows the kind of relationship for which `Deref` can be coherent.

## `AsRef` Is a Separate Contract

If callers genuinely benefit from generic borrowed conversion, `AsRef<str>` can be intentional:

<!-- rust-check: compile -->
```rust
struct Name(String);

impl AsRef<str> for Name {
    fn as_ref(&self) -> &str {
        &self.0
    }
}

fn measure(value: impl AsRef<str>) -> usize {
    value.as_ref().len()
}

fn main() {
    assert_eq!(measure(Name("alice".to_owned())), 5);
}
```

Do not implement `AsRef` mechanically either. It advertises a generic conversion contract; an inherent `as_str()` method is often the smaller API for a domain newtype.

## Decision Guide

| Intent | Typical choice |
|---|---|
| Transparent pointer/target-like wrapper | Consider `Deref` |
| Domain newtype with visible semantics/invariants | Explicit inherent methods |
| Generic borrowed conversion is useful | Consider `AsRef<T>` |
| Expose one or two inner operations | Delegate those methods explicitly |
| FFI layout guarantee | `#[repr(transparent)]` is separate from `Deref` |

## See Also

- [type-repr-transparent](./type-repr-transparent.md) — representation/layout, not delegation
- [api-newtype-safety](./api-newtype-safety.md) — type-safe newtypes
- [type-display-vs-debug](./type-display-vs-debug.md) — semantic trait implementations

## References

- [Rust `Deref` documentation](https://doc.rust-lang.org/std/ops/trait.Deref.html)
- [Rust API Guidelines: smart pointer behavior](https://rust-lang.github.io/api-guidelines/predictability.html#smart-pointers-behave-like-smart-pointers-c-smart-ptr)
