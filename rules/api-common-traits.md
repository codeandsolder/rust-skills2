# api-common-traits

> Implement standard traits when their semantics are useful and appropriate for the public type

## Why It Matters

Trait implementations are part of a public API. They improve interoperability, but they also make semantic promises that downstream code may rely on. Add traits because the type has the corresponding behavior, not because a public type should mechanically derive a standard bundle.

`Debug` is broadly useful for diagnostics, `Clone` promises explicit duplication, and equality/ordering/hash traits define observable semantics. Those promises can affect privacy, cost, compatibility, and future representation changes.

## Good: Derive Traits That Match the Type

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UserId(u64);

fn main() {
    let a = UserId(7);
    let b = a;
    assert_eq!(a, b);
}
```

A small identifier often has natural value semantics. A floating-point point can reasonably support `PartialEq`, but not `Eq` because IEEE floating-point equality is not reflexive for NaN.

## Do Not Derive a Bundle Blindly

```rust
pub struct SecretToken(String);

impl SecretToken {
    pub fn new(value: String) -> Self {
        Self(value)
    }
}

fn main() {
    let _token = SecretToken::new("secret".to_owned());
}
```

A token may deliberately omit `Debug` to reduce accidental disclosure and omit `Clone` if duplication is undesirable. Similar judgment applies to resource handles, capabilities, large buffers, and types whose equality or ordering would be misleading.

## Trait Semantics

| Trait | Implement when |
|-------|----------------|
| `Debug` | Diagnostic formatting is useful and can avoid exposing secrets or unstable internals |
| `Clone` | Explicit duplication is meaningful and its cost/semantics are acceptable |
| `Copy` | Implicit bitwise duplication is appropriate and unlikely to constrain future API evolution |
| `PartialEq` | Equality has useful domain semantics |
| `Eq` | Equality is an equivalence relation |
| `Hash` | Hashing is meaningful and consistent with `Eq`/`PartialEq` |
| `PartialOrd` | Partial ordering is meaningful |
| `Ord` | A total ordering is meaningful and consistent with equality |
| `Default` | There is a sensible canonical default value |

Derive is usually preferable when field-wise semantics are exactly the semantics you want. Write a manual implementation when the public semantics differ from representation.

## Manual Equality and Hashing Must Agree

```rust
use std::hash::{Hash, Hasher};

#[derive(Debug)]
struct CaseInsensitiveString(String);

impl PartialEq for CaseInsensitiveString {
    fn eq(&self, other: &Self) -> bool {
        self.0.eq_ignore_ascii_case(&other.0)
    }
}

impl Eq for CaseInsensitiveString {}

impl Hash for CaseInsensitiveString {
    fn hash<H: Hasher>(&self, state: &mut H) {
        for byte in self.0.bytes() {
            byte.to_ascii_lowercase().hash(state);
        }
    }
}

fn main() {
    let a = CaseInsensitiveString("Rust".to_owned());
    let b = CaseInsensitiveString("RUST".to_owned());
    assert_eq!(a, b);
}
```

If two values compare equal, they must produce the same hash. The same consistency requirement applies when implementing ordering traits alongside equality.

## Redact Sensitive Debug Output

```rust
use std::fmt;

struct Password(String);

impl fmt::Debug for Password {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Password([REDACTED])")
    }
}

fn main() {
    let password = Password("hunter2".to_owned());
    assert_eq!(format!("{password:?}"), "Password([REDACTED])");
}
```

If `Debug` is useful but fields contain secrets, implement a deliberately redacted representation rather than deriving field-wise output.

## `Copy` Is an API Choice, Not a Size Threshold

A type being small is not sufficient reason to implement `Copy`. `Copy` changes move behavior at call sites and can make later representation changes harder if they require non-`Copy` fields. Use it for types with clear value semantics where implicit duplication is desirable.

## Serde and Other Ecosystem Traits

Serialization traits are also public behavior. Derive them when the serialized representation is intended to be part of the API or storage/wire contract; otherwise consider a separate DTO or explicit conversion layer.

## Practical Guidance

- Treat trait impls as semantic API commitments.
- Prefer derive when field-wise behavior matches the public semantics.
- Do not recommend `Debug + Clone + PartialEq` for every public type by default.
- Keep `Eq`, `Hash`, and ordering implementations mutually consistent.
- Redact sensitive `Debug` output or omit `Debug` where disclosure risk outweighs diagnostic value.
- Implement `Copy` for appropriate value semantics, not merely because a type is small.

## See Also

- [own-copy-small](./own-copy-small.md) - When to implement Copy
- [api-default-impl](./api-default-impl.md) - Implementing Default
- [doc-examples-section](./doc-examples-section.md) - Documenting trait implementations
