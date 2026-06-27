# anti-deref-overuse

> Don't use `Deref<Target = InnerType>` for newtype method delegation

## Why It Matters

`Deref` is meant for smart pointer types (`Box`, `Arc`, `Cow`), not for emulating inheritance or leaking inner APIs. Using `Deref` on newtypes:

- **Leaks the inner type's full public API** — callers can use `&Email` where `&str` is expected, bypassing validation.
- **Hides the newtype's semantics** — it's no longer an `Email`, it's a `String` in disguise.
- **Prevents adding custom methods** without ambiguity.
- **Confuses trait resolution** — inherent methods on the inner type shadow your own.

## Bad

```rust
struct Email(String);

impl std::ops::Deref for Email {
    type Target = str;
    fn deref(&self) -> &str {
        &self.0
    }
}

// Now &Email coerces to &str EVERYWHERE — unintended
fn send_to(address: &str) { /* ... */ }

let email = Email("test@example.com".to_string());
send_to(&email);  // Compiles — may bypass validation
// Any String method also works on Email via Deref

// Email has no custom validation interface exposed
// — the Deref leaks raw string access
```

```rust
// Even worse: Deref on a generic newtype
struct Wrapper<T>(T);

impl<T> std::ops::Deref for Wrapper<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &self.0
    }
}
// This is a code smell — you're hiding the wrapper entirely
```

## Good

```rust
struct Email(String);

impl Email {
    /// Parse and validate on construction.
    pub fn new(s: &str) -> Result<Self, ValidationError> {
        if is_valid_email(s) {
            Ok(Email(s.to_string()))
        } else {
            Err(ValidationError::InvalidEmail)
        }
    }

    /// Explicit accessor — not automatic via Deref.
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Custom validation method that doesn't conflict.
    pub fn domain(&self) -> &str {
        self.0.split('@').nth_back(0).unwrap_or("")
    }
}

// Callers use explicit methods
let email = Email::new("test@example.com").unwrap();
send_to(email.as_str());  // Explicit: reader sees the conversion
```

## Pattern: Explicit Delegation

```rust
#[derive(Debug, Clone)]
struct UserId(u64);

impl UserId {
    pub fn new(id: u64) -> Self {
        Self(id)
    }

    pub fn as_u64(&self) -> u64 {
        self.0
    }

    // Only expose what makes sense for UserId
    pub fn is_system(&self) -> bool {
        self.0 < 1000
    }
}

// No Deref — callers can't accidentally use UserId as u64
fn lookup_user(id: UserId) { /* ... */ }
// lookup_user(42);  // Compile error — type-safe!
lookup_user(UserId::new(42));  // Explicit — correct
```

## When Deref Is Appropriate

| Use case | Example | OK? |
|----------|---------|-----|
| Smart pointers | `Box<T>`, `Arc<T>`, `Cow<T>` | ✅ Intended use |
| Newtypes for API safety | `Email(String)`, `UserId(u64)` | ❌ Use explicit methods |
| Thin wrapper delegation | — | ❌ Use explicit delegation |

## Decision Guide

| Goal | Approach |
|------|----------|
| Expose inner value | `fn as_inner(&self) -> &Inner` |
| Expose specific methods | Write delegation methods |
| Smart pointer semantics | `Deref` is correct |
| FFI wrapper | `#[repr(transparent)]` without Deref |

## See Also

- [type-repr-transparent](./type-repr-transparent.md) — FFI-safe single-field newtypes
- [api-newtype-safety](./api-newtype-safety.md) — Type-safe newtype pattern
- [type-display-vs-debug](./type-display-vs-debug.md) — Proper trait implementations for newtypes

## References

- [Rust Anti-patterns: Deref polymorphism](https://rust-unofficial.github.io/patterns/anti_patterns/deref.html)
- [Rust API Guidelines: Deref](https://rust-lang.github.io/api-guidelines/predictability.html#smart-pointers-behave-like-smart-pointers-c-smart-ptr)
