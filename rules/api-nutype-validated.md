# api-nutype-validated

> Use `nutype` when generated sanitization, validation, and invariant-preserving trait impls materially simplify a public newtype API

**Rule**: `api-nutype-validated`

## Why It Matters

A validated newtype makes an invariant part of the type: once construction succeeds, downstream code receives a `Username`, `Port`, or other domain type instead of repeatedly re-validating a primitive.

The `nutype` proc macro can generate constructors, validation errors, sanitization, and selected trait impls while keeping the inner field private. This can remove substantial boilerplate, but it also adds a proc-macro dependency and compile-time cost. Use it when the invariant-bearing type is worth that tradeoff; a small hand-written newtype remains perfectly reasonable.

This rule follows the `nutype` 0.7 API. In particular, **a type with validation uses `try_new`, not `new`**.

## Bad: Repeated Validation at Call Sites

```rust
fn send_welcome(raw_username: &str) {
    if raw_username.trim().is_empty() {
        return;
    }

    // Every caller must remember the same checks and normalization.
    println!("welcome {}", raw_username.trim().to_lowercase());
}

fn main() {
    send_welcome(" Alice42 ");
}
```

The problem is not that manual validation is inherently bad; it is that the program continues to pass around an unvalidated primitive after the boundary.

## Good: Parse Once Into a Validated Type

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim, lowercase),
    validate(not_empty, len_char_max = 20),
    derive(Debug, Clone, PartialEq, Eq, Display, AsRef, Deref, FromStr, TryFrom, Into),
)]
pub struct Username(String);

fn main() {
    let username = Username::try_new("  Alice42  ").unwrap();
    assert_eq!(username.as_ref(), "alice42");

    assert_eq!(
        Username::try_new("   "),
        Err(UsernameError::NotEmptyViolated),
    );
}
```

With validation present, `try_new(...)` returns `Result<Username, UsernameError>`. If a `nutype` has sanitization but **no validation**, its constructor is `new(...)` and returns the newtype directly.

The generated error variants follow the validators. For example, `not_empty` yields `NotEmptyViolated`, `len_char_max` yields `LenCharMaxViolated`, and a predicate validator yields `PredicateViolated` in the current 0.7 API. Do not invent error names such as `Empty`, `TooLong`, or `Invalid` without checking the crate version you actually use.

## Regex Validation Requires Two Opt-Ins

`nutype`'s `regex` validator requires the crate's `regex` feature **and** a direct `regex` dependency in the consuming crate.

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim, lowercase),
    validate(regex = "^[a-z][a-z0-9_]*$"),
    derive(Debug, Clone, PartialEq, Eq, AsRef),
)]
pub struct Handle(String);

fn main() {
    let handle = Handle::try_new(" Alice_123 ").unwrap();
    assert_eq!(handle.as_ref(), "alice_123");
    assert!(Handle::try_new("123alice").is_err());
}
```

A matching dependency setup is:

```toml
[dependencies]
nutype = { version = "0.7", features = ["regex"] }
regex = "1"
```

Use a predicate instead when pulling in regex machinery is unnecessary.

## Serde Integration Uses `derive`, Not `serde(...)`

Enable `nutype`'s `serde` feature and request the supported traits through `derive(...)`:

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim),
    validate(not_empty),
    derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize),
)]
pub struct Label(String);

fn main() {
    let label = Label::try_new(" hello ").unwrap();
    let json = serde_json::to_string(&label).unwrap();
    let decoded: Label = serde_json::from_str(&json).unwrap();
    assert_eq!(label, decoded);
}
```

With validated types, deserialization goes through the generated invariant checks; it does not provide a public back door to construct an invalid value.

Do not use the old-looking `serde(Serialize, Deserialize)` syntax—the current 0.7 API exposes these as supported entries in `derive(...)` when the feature is enabled.

## Custom Sanitizers and Validators

```rust
use nutype::nutype;

fn strip_spaces(value: String) -> String {
    value.chars().filter(|c| !c.is_whitespace()).collect()
}

#[nutype(
    sanitize(with = strip_spaces),
    validate(predicate = |value: &str| value.len() >= 3),
    derive(Debug, Clone, PartialEq, Eq),
)]
pub struct Slug(String);

fn main() {
    assert!(Slug::try_new("a b c").is_ok());
    assert!(Slug::try_new("a b").is_err());
}
```

For domain-specific error detail, `nutype` also supports a custom validation function returning your own error type via `validate(with = ..., error = ...)`.

## `const_fn` Has Real Restrictions

`const_fn` can make generated constructors `const`, but the operations performed by sanitization/validation and the inner type must themselves be usable in const evaluation. The crate documentation specifically notes that heap-allocated types such as `String` are not the intended case.

A numeric example is a better fit:

```rust
use nutype::nutype;

#[nutype(
    const_fn,
    validate(greater_or_equal = -273.15),
    derive(Debug, Clone, Copy, PartialEq),
)]
pub struct Celsius(f64);

const FREEZING: Celsius = match Celsius::try_new(0.0) {
    Ok(value) => value,
    Err(_) => panic!("constant is invalid"),
};

fn main() {
    assert_eq!(FREEZING.into_inner(), 0.0);
}
```

Do not advertise `const_fn` on a `String` newtype as though it made arbitrary heap-backed construction const-evaluable.

## Trait Derivation Is Deliberately Restricted

`nutype`'s normal `derive(...)` accepts a curated set of traits whose generated implementations preserve the type's invariants. Arbitrary third-party derives require the separate `derive_unchecked` feature and should be treated as an explicit escape hatch: a trait that exposes mutable access to the inner value can invalidate the guarantee the type is supposed to provide.

Likewise, `new_unchecked` is an unsafe opt-in for bypassing sanitization and validation. It should be rare and justified at the same level as any other unsafe invariant boundary.

## When Not to Use `nutype`

Prefer a hand-written newtype when:

- the invariant is tiny and the generated API would be more machinery than value;
- you need unusual construction/error semantics not well represented by the macro;
- compile-time/proc-macro dependency cost matters;
- the type is public and you want complete long-term control of its API surface.

The goal is to make invalid states hard to represent, not to maximize macro usage.

## See Also

- [type-nutype-validated](./type-nutype-validated.md) — type-system rationale and a compact numeric example
- [api-parse-dont-validate](./api-parse-dont-validate.md) — parse at boundaries
- [api-newtype-safety](./api-newtype-safety.md) — semantic newtypes
- [type-newtype-validated](./type-newtype-validated.md) — manual validated newtypes
- [api-serde-optional](./api-serde-optional.md) — optional serde dependencies in libraries

## References

- [nutype 0.7 documentation](https://docs.rs/nutype/latest/nutype/)
- [nutype feature flags](https://docs.rs/crate/nutype/latest/features)
- [Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
