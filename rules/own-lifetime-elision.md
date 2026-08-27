# own-lifetime-elision

> Rely on ordinary lifetime elision where it applies; treat Edition-2024 RPIT capture as a separate rule

## Why It Matters

Rust has several different mechanisms that can make lifetimes disappear from source code. Two of the most commonly confused are:

- **lifetime elision in reference types**, which assigns omitted lifetimes in function and method signatures; and
- **generic capture by return-position `impl Trait` (RPIT)**, which controls which in-scope generic parameters the hidden return type may use.

Edition 2024 changed RPIT capture. It did **not** replace the ordinary reference-elision rules, and it does not turn borrowed values into `'static` data.

## Good: Let Ordinary Elision Handle Simple Borrows

```rust
fn first_word(input: &str) -> &str {
    input.split_whitespace().next().unwrap_or("")
}

fn first<T>(values: &[T]) -> Option<&T> {
    values.first()
}

fn main() {
    assert_eq!(first_word("hello world"), "hello");
    assert_eq!(first(&[10, 20, 30]), Some(&10));
}
```

Writing explicit names such as `fn first_word<'a>(input: &'a str) -> &'a str` is correct but adds no information here.

## The Function Elision Rules

For ordinary function and method signatures, the important rules are:

1. Every elided lifetime in an input position becomes a distinct lifetime parameter.
2. If exactly one lifetime appears among the inputs, that lifetime is assigned to all elided output lifetimes.
3. For methods, if the receiver is `&Self` or `&mut Self`, the receiver's lifetime is assigned to elided output lifetimes.

That means this works without naming a lifetime:

```rust
struct Person {
    name: String,
}

impl Person {
    fn name(&self) -> &str {
        &self.name
    }
}

fn main() {
    let person = Person { name: "Ada".into() };
    assert_eq!(person.name(), "Ada");
}
```

But two unrelated borrowed inputs do not tell the compiler which lifetime an output should use:

```rust
fn longest<'a>(left: &'a str, right: &'a str) -> &'a str {
    if left.len() >= right.len() { left } else { right }
}

fn main() {
    assert_eq!(longest("long", "x"), "long");
}
```

The explicit `'a` states the relationship: whichever input is returned, both inputs must be usable for the output lifetime.

## Reference-Holding Types Still Need Lifetime Parameters

Elision in function signatures does not remove lifetime parameters from types that store references.

```rust
struct Parser<'input> {
    source: &'input str,
    position: usize,
}

impl Parser<'_> {
    fn remaining(&self) -> &str {
        &self.source[self.position..]
    }
}

fn main() {
    let parser = Parser { source: "abcdef", position: 2 };
    assert_eq!(parser.remaining(), "cdef");
}
```

`'_` is useful when a lifetime parameter exists but naming it would add no value in that particular type use.

## Edition 2024 RPIT Capture Is Different

An RPIT such as `-> impl Iterator<...>` has a hidden concrete return type. That hidden type may need to mention generic parameters from the surrounding function.

In Edition 2024, RPIT automatically captures all in-scope type, const, and lifetime parameters unless a precise-capture `use<...>` bound says otherwise.

```rust
fn words(input: &str) -> impl Iterator<Item = &str> {
    input.split_whitespace()
}

fn main() {
    let text = String::from("one two");
    let mut words = words(&text);
    assert_eq!(words.next(), Some("one"));
    assert_eq!(words.next(), Some("two"));
}
```

The returned iterator borrows `input`. Edition 2024 lets the opaque return type capture that lifetime without an explicit `+ '_` bound.

Pre-2024 editions had narrower automatic lifetime capture for free functions and inherent methods. Code written for an older edition may therefore contain `+ '_`, named lifetime bounds, or precise-capture syntax that is redundant after migrating to Edition 2024.

## Automatic Capture Does Not Satisfy `'static`

RPIT capture allows a hidden type to borrow an input. It does not make that borrow live forever.

```rust
fn borrowed_len(text: &str) -> impl Fn() -> usize + '_ {
    move || text.len()
}

fn main() {
    let text = String::from("hello");
    let len = borrowed_len(&text);
    assert_eq!(len(), 5);
}
```

If an API genuinely requires a `'static` value—for example because work may outlive the current borrow—you still need ownership or another lifetime-safe design. Edition 2024 does not eliminate clones that are required to satisfy a real `'static` contract; it only removes some clones or annotations that existed solely because the opaque return type could not previously capture a borrow ergonomically.

## Precise Capture with `use<...>`

Sometimes Edition 2024 captures **more** generic parameters than the hidden type actually needs. A precise-capture bound can opt out of that overcapture.

```rust
fn first_value<'a>(values: &'a [u32]) -> impl Copy + use<> {
    values[0]
}

fn main() {
    let values = vec![10, 20];
    let first = first_value(&values);
    drop(values);
    assert_eq!(first, 10);
}
```

The hidden type is just `u32`, so it does not need to capture `'a`. `use<>` makes that explicit.

When a hidden type really does borrow a named lifetime, include it in the capture set:

```rust
use std::fmt::Display;

fn displayed<'a>(text: &'a str) -> impl Display + use<'a> {
    text
}

fn main() {
    let text = String::from("hello");
    assert_eq!(displayed(&text).to_string(), "hello");
}
```

In Edition 2024, a `use<...>` list that captures exactly everything the default would already capture can be redundant. Use precise capture to express a real restriction or edition-compatibility need, not as routine decoration.

## Edition Migration Can Reveal Overcapture

Because Edition 2024 captures more lifetime parameters by default, migration can make an opaque return type appear to keep a borrow alive longer than it did before. Rust provides migration lints for this situation, including `impl_trait_overcaptures`.

If the hidden type does not actually depend on a lifetime, `use<>` or another precise capture list can preserve the narrower relationship explicitly.

This is the opposite of “Edition 2024 always eliminates lifetime problems”: broader automatic capture is ergonomic when the hidden type needs the borrow, but sometimes needs to be narrowed when it does not.

## `mismatched_lifetime_syntaxes` (Rust 1.89+)

Rust 1.89 added the warn-by-default `mismatched_lifetime_syntaxes` lint. It detects signatures where the same lifetime is referred to using visibly different lifetime syntax in related input/output positions, which can make the borrowing relationship harder to read.

A simple consistent signature avoids that ambiguity:

```rust
fn identity<'a>(value: &'a str) -> &'a str {
    value
}

fn main() {
    assert_eq!(identity("hello"), "hello");
}
```

Do not interpret the lint as “explicit lifetimes and `'_` may never coexist.” Its purpose is to flag confusing mismatches in how the same lifetime relationship is presented.

## Closures Have Their Own Inference Rules

Do not invent release-specific “lifetime normalization” rules for closures unless an actual language change requires them. A closure returning one of its borrowed arguments can still run into lifetime constraints that differ from a normal generic function, and adding an explicit `-> &T` annotation is not a universal fix.

When the relationship matters in an API, a normal function or a higher-ranked trait bound can often express it more clearly than relying on closure inference folklore.

## Practical Guidance

- Omit lifetime names for straightforward one-input/one-output borrows and ordinary receiver-based methods.
- Name lifetimes when you need to state a relationship among multiple borrows or store references in a type.
- Treat `'_` as an anonymous lifetime placeholder, not a magic lifetime extension.
- Treat Edition-2024 RPIT capture separately from reference lifetime elision.
- Do not claim automatic RPIT capture satisfies genuine `'static` requirements.
- Use `use<...>` when you need precise opaque-type capture, especially to avoid Edition-2024 overcapture.
- Prefer compiler/reference-backed rules over version folklore about closure lifetime inference.

## See Also

- [own-cow-rpit-edition2024](./own-cow-rpit-edition2024.md) — RPIT capture and `Cow`
- [own-borrow-over-clone](./own-borrow-over-clone.md) — borrowing versus ownership
- [api-impl-asref](./api-impl-asref.md) — generic borrowing with `AsRef`
