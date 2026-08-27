# own-cow-rpit-edition2024

**Rule**: `own-cow-rpit-edition2024`

> Edition 2024 simplifies RPIT returns whose hidden type borrows; it does not change ordinary `Cow<'_, T>` return elision

## Why It Matters

Two independent mechanisms are easy to conflate:

- `fn value(&self) -> Cow<'_, str>` returns the concrete type `Cow`; ordinary lifetime elision/inference handles the placeholder lifetime.
- `fn value(&self) -> impl Display` returns an opaque RPIT type. If the hidden concrete type borrows from `self`, the RPIT must capture that lifetime.

Edition 2024 changed the second mechanism. In Rust 2024, return-position `impl Trait` implicitly captures all in-scope generic parameters, including lifetimes, unless a `use<...>` bound specifies a narrower capture set.

## Direct `Cow` Returns Are Not RPIT

```rust
use std::borrow::Cow;

struct NameFormatter {
    prefix: String,
    name: String,
}

impl NameFormatter {
    fn format(&self) -> Cow<'_, str> {
        if self.prefix.is_empty() {
            Cow::Borrowed(self.name.as_str())
        } else {
            Cow::Owned(format!("{} {}", self.prefix, self.name))
        }
    }
}

fn main() {
    let formatter = NameFormatter {
        prefix: "Dr.".into(),
        name: "Ada".into(),
    };
    assert_eq!(formatter.format(), "Dr. Ada");
}
```

There is no `impl Trait` in this method, so RPIT capture rules do not explain its lifetime. Treat this as ordinary `Cow`/lifetime-elision guidance.

## Good: Edition 2024 RPIT Can Capture the Receiver Borrow

When the same `Cow` is hidden behind `impl Display`, RPIT capture is relevant:

```rust
use std::borrow::Cow;
use std::fmt::Display;

struct NameFormatter {
    prefix: String,
    name: String,
}

impl NameFormatter {
    fn display(&self) -> impl Display {
        if self.prefix.is_empty() {
            Cow::Borrowed(self.name.as_str())
        } else {
            Cow::Owned(format!("{} {}", self.prefix, self.name))
        }
    }
}

fn main() {
    let formatter = NameFormatter {
        prefix: String::new(),
        name: "Ada".into(),
    };
    assert_eq!(formatter.display().to_string(), "Ada");
}
```

In Edition 2024, the opaque return type may implicitly capture the lifetime of `&self`, so the hidden `Cow<'_, str>` can borrow from the formatter without adding `+ '_` merely to make that capture legal.

## Pre-2024 RPIT Often Needed an Explicit Capture Bound

For a comparable inherent method in Rust 2021 and earlier, an RPIT lifetime that did not otherwise appear in the opaque bounds was not automatically captured. A common spelling was:

```rust
use std::borrow::Cow;
use std::fmt::Display;

struct Formatter {
    name: String,
}

impl Formatter {
    fn display_legacy(&self) -> impl Display + '_ {
        Cow::Borrowed::<str>(self.name.as_str())
    }
}

fn main() {
    let formatter = Formatter { name: "Ada".into() };
    assert_eq!(formatter.display_legacy().to_string(), "Ada");
}
```

The `+ '_` outlives/capture spelling is still legal in Edition 2024; it is simply often unnecessary when default capture already expresses the intended relationship. Precise `use<...>` capture is the modern tool when an explicit capture set is needed.

## Capture Is Not Lifetime Extension

Automatic capture lets the hidden type **use** the receiver lifetime. It does not make that borrow `'static` or independent of the source object.

```rust
use std::fmt::Display;

struct Label(String);

impl Label {
    fn borrowed_display(&self) -> impl Display {
        self.0.as_str()
    }

    fn owned_static_display(&self) -> impl Display + 'static {
        self.0.clone()
    }
}

fn main() {
    let label = Label("hello".into());
    assert_eq!(label.borrowed_display().to_string(), "hello");
    assert_eq!(label.owned_static_display().to_string(), "hello");
}
```

The second method genuinely promises `'static`, so it must return owned data (or otherwise satisfy that lifetime independently). Edition 2024 does not remove clones required by a real `'static` API contract.

## Do Not Attribute Ordinary Collections of `Cow` to RPIT

A concrete return such as `Vec<Cow<'_, str>>` also does not use RPIT:

```rust
use std::borrow::Cow;

fn words(input: &str) -> Vec<Cow<'_, str>> {
    input.split_whitespace().map(Cow::Borrowed).collect()
}

fn main() {
    assert_eq!(words("one two"), ["one", "two"]);
}
```

Edition-2024 RPIT capture matters only when `impl Trait` (or another opaque type governed by those capture rules) is involved.

## Overcapture Can Matter Too

Rust 2024's default is broader: all in-scope lifetimes are captured by RPIT unless a precise-capture `use<...>` bound says otherwise. That can occasionally keep a borrow relationship alive even when the hidden type does not use it.

Use `use<...>` when you need a narrower capture set, especially during edition migration. Do not assume “more automatic capture” is always semantically invisible.

See `own-lifetime-elision` for the full capture/overcapture discussion.

## When `Cow` Is Actually Useful

RPIT and `Cow` solve different problems:

- `Cow` chooses between borrowed and owned representations of the same logical data.
- RPIT hides the concrete return type while exposing trait bounds.

Use both together only when you genuinely need both properties. If callers can reasonably know the return type, returning `Cow<'_, str>` directly is often clearer than hiding it behind `impl Display` or another trait.

## Practical Guidance

- Do not say Edition 2024 made direct `Cow<'_, T>` method returns possible; those are not RPIT.
- Use Edition-2024 automatic capture when an RPIT hidden type really borrows an in-scope lifetime.
- Keep `+ '_` or use precise `use<...>` when an explicit capture relationship improves compatibility or clarity.
- Do not claim capture satisfies a genuine `'static` requirement.
- Prefer direct `Cow` returns when hiding the concrete type adds no API value.

## See Also

- [own-cow-conditional](./own-cow-conditional.md) - General conditional ownership with Cow
- [own-lifetime-elision](./own-lifetime-elision.md) - Ordinary elision, RPIT capture, and `use<...>`
- [own-borrow-over-clone](./own-borrow-over-clone.md) - Avoid unnecessary ownership

## References

- [Edition 2024 RPIT lifetime capture guide](https://doc.rust-lang.org/edition-guide/rust-2024/rpit-lifetime-capture.html)
- [Rust Reference: impl Trait capture](https://doc.rust-lang.org/reference/types/impl-trait.html#capturing)
