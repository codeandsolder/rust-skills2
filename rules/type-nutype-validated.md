# type-nutype-validated

> Use validated newtypes to make invalid states unrepresentable; `nutype` is useful when generated constructors and invariant-preserving trait impls justify a proc macro

**Rule**: `type-nutype-validated`

## Why It Matters

A validated newtype moves a check from “remember to validate this primitive everywhere” to “construction is the only place an invalid value can enter.” Downstream APIs can then accept the domain type directly and rely on its invariant.

The important design pattern is the type boundary, not any particular macro. A hand-written private-field newtype is often ideal. `nutype` is useful when sanitization, several validators, parsing/conversion traits, or serde support would otherwise produce repetitive code.

This rule focuses on **type design**. See [api-nutype-validated](./api-nutype-validated.md) for the current `nutype` 0.7 constructor, regex, serde, `const_fn`, and feature-flag details.

## Bad: Primitive Obsession

```rust
fn connect(port: u16) {
    // Every caller and callee must remember that zero is invalid.
    assert!(port > 0);
    println!("connecting to port {port}");
}

fn main() {
    connect(8080);
}
```

The signature does not communicate or enforce the domain invariant.

## Good: Put the Invariant in the Type

```rust
use nutype::nutype;

#[nutype(
    validate(greater = 0),
    derive(Debug, Clone, Copy, PartialEq, Eq, Display, TryFrom),
)]
pub struct Port(u16);

fn connect(port: Port) {
    println!("connecting to port {port}");
}

fn main() {
    let port = Port::try_new(8080).unwrap();
    connect(port);

    assert!(Port::try_new(0).is_err());
}
```

Once a `Port` exists through the safe API, code receiving it does not need to repeat `port > 0` checks.

With validation present, `nutype` 0.7 generates `try_new`, not `new`. The public tuple field is not exposed, so ordinary safe construction cannot bypass the validator.

## The Same Pattern Without a Macro

For a small invariant, hand-written code may be clearer and cheaper to compile:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Percentage(u8);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PercentageOutOfRange;

impl Percentage {
    pub fn new(value: u8) -> Result<Self, PercentageOutOfRange> {
        if value <= 100 {
            Ok(Self(value))
        } else {
            Err(PercentageOutOfRange)
        }
    }

    pub fn get(self) -> u8 {
        self.0
    }
}

fn main() {
    assert_eq!(Percentage::new(75).unwrap().get(), 75);
    assert!(Percentage::new(101).is_err());
}
```

Do not add a proc macro merely to avoid ten straightforward lines. Use one when it meaningfully improves consistency or removes repetitive surface area across many domain types.

## Validate at Boundaries, Not Repeatedly Inside the Domain

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim, lowercase),
    validate(not_empty),
    derive(Debug, Clone, PartialEq, Eq, AsRef, FromStr),
)]
pub struct Username(String);

fn parse_request(raw: &str) -> Result<Username, UsernameError> {
    raw.parse()
}

fn greet(username: &Username) -> String {
    // No second emptiness/normalization check: Username already carries it.
    format!("hello {}", username.as_ref())
}

fn main() {
    let username = parse_request("  Alice  ").unwrap();
    assert_eq!(greet(&username), "hello alice");
}
```

This is the useful interpretation of “parse, don't validate”: convert untrusted or weakly typed input into a stronger type at the boundary, then keep using that stronger type.

## Sanitization Changes the Meaning of Construction

Sanitization is not validation. It transforms the input before validation and storage. That can be exactly what a domain wants—trimming user-entered labels, canonicalizing case-insensitive identifiers—but should be an explicit semantic choice.

Do not silently lowercase, truncate, clamp, or otherwise normalize values merely because the macro makes it easy. Ask whether callers expect rejection or canonicalization.

## Preserve the Invariant Through the Whole API

A validated newtype loses much of its value if safe APIs expose unrestricted mutation of the inner value.

Prefer:

- immutable accessors such as `as_ref`, `Deref`, or `into_inner` when appropriate;
- domain methods that preserve the invariant;
- re-validation when an operation can produce a new value.

Be cautious with escape hatches such as arbitrary mutable dereferencing, unchecked constructors, deserialization hooks, or third-party derives that can mutate/expose the representation. `nutype` intentionally restricts ordinary derives for this reason; its unchecked features should be treated as explicit invariant boundaries.

## Error Types Are Part of the Boundary

A validation error should be useful at the input boundary but usually should not leak throughout the core domain model.

For example:

```rust
use nutype::nutype;

#[nutype(
    validate(greater_or_equal = 1, less_or_equal = 65535),
    derive(Debug, Clone, Copy, PartialEq, Eq),
)]
pub struct ServicePort(u32);

fn parse_port(raw: &str) -> Result<ServicePort, String> {
    let value: u32 = raw
        .parse()
        .map_err(|_| "port is not an integer".to_owned())?;

    ServicePort::try_new(value).map_err(|err| err.to_string())
}

fn main() {
    assert!(parse_port("443").is_ok());
    assert!(parse_port("0").is_err());
}
```

At an HTTP/CLI/configuration boundary you may map the generated validation error into a user-facing error type. Internal functions can simply accept `ServicePort`.

## Newtypes Also Give Semantic Type Separation

Validation is only one benefit. Distinct wrapper types prevent accidental interchange of primitives with identical representation:

```rust
struct UserId(u64);
struct OrderId(u64);

fn load_user(id: UserId) {
    let _ = id.0;
}

fn main() {
    load_user(UserId(7));
    // load_user(OrderId(7)); // compile-time type mismatch
}
```

If no runtime validation is necessary, a simple semantic newtype may be enough; do not force every wrapper into the validated-newtype pattern.

## When `nutype` Fits

Use it when several of these are true:

- many domain types repeat the same constructor/error/trait boilerplate;
- sanitization and validation should occur in one canonical constructor;
- `FromStr`, `TryFrom`, serde, display, or borrowing traits are useful;
- keeping the inner representation private is important;
- the proc-macro dependency and compile-time cost are acceptable.

Prefer a hand-written type when the invariant or API is small, highly custom, performance/build constraints matter, or public API stability calls for tighter control over generated surface area.

## See Also

- [api-nutype-validated](./api-nutype-validated.md) — current `nutype` 0.7 API details
- [type-newtype-validated](./type-newtype-validated.md) — hand-written validated newtypes
- [type-newtype-ids](./type-newtype-ids.md) — semantic identifier types
- [api-parse-dont-validate](./api-parse-dont-validate.md) — boundary parsing
- [api-newtype-safety](./api-newtype-safety.md) — general newtype API design

## References

- [nutype 0.7 documentation](https://docs.rs/nutype/latest/nutype/)
- [Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
