# api-extension-trait

> Use a local extension trait when method-call syntax on an external type materially improves an API

## Why It Matters

Rust does not let you add inherent methods to a type defined in another crate, and the orphan rules restrict implementations of foreign traits for foreign types. A local trait avoids both problems: you own the trait, so you may implement it for an external type and callers get method syntax after importing the trait.

Extension traits are useful, but they are still public API surface. Method names can collide with inherent methods or other imported traits, and broad blanket impls can produce surprising method availability and diagnostics.

## Good: Extend an External Type with a Local Trait

```rust
use std::fmt::Write as _;

trait ByteSliceExt {
    fn to_hex(&self) -> String;
    fn is_ascii_printable(&self) -> bool;
}

impl ByteSliceExt for [u8] {
    fn to_hex(&self) -> String {
        let mut out = String::with_capacity(self.len() * 2);
        for byte in self {
            write!(&mut out, "{byte:02x}").unwrap();
        }
        out
    }

    fn is_ascii_printable(&self) -> bool {
        self.iter()
            .all(|byte| byte.is_ascii_graphic() || byte.is_ascii_whitespace())
    }
}

fn main() {
    let bytes: &[u8] = b"Hi";
    assert_eq!(bytes.to_hex(), "4869");
    assert!(bytes.is_ascii_printable());
}
```

Because `ByteSliceExt` is local, implementing it for foreign `[u8]` is coherent. Callers must have the trait in scope for method-call syntax.

## Import Scope Is Part of the Design

Extension methods are available only where the trait is in scope. That is often desirable because it keeps optional API surface opt-in.

```rust
mod text_ext {
    pub trait StrExt {
        fn with_ellipsis(&self, max_chars: usize) -> String;
    }

    impl StrExt for str {
        fn with_ellipsis(&self, max_chars: usize) -> String {
            let count = self.chars().count();
            if count <= max_chars {
                return self.to_owned();
            }
            if max_chars == 0 {
                return String::new();
            }

            let mut out: String = self.chars().take(max_chars - 1).collect();
            out.push('…');
            out
        }
    }
}

use text_ext::StrExt;

fn main() {
    assert_eq!("abcdef".with_ellipsis(4), "abc…");
    assert_eq!("éclair".with_ellipsis(3), "éc…");
}
```

Do not truncate a UTF-8 `str` with an arbitrary byte index such as `&text[..max_len]`; a non-character boundary panics. Define whether a limit means bytes, Unicode scalar values (`char`s), or grapheme clusters and implement that contract deliberately.

## Extension Traits Are Not an Orphan-Rule Loophole for Foreign Traits

This is illegal because both the trait and target type are foreign:

<!-- rust-check: compile_fail; reason=demonstrates the orphan rule that motivates a local extension trait -->
```rust
use std::fmt::Display;

impl Display for Vec<u8> {
    fn fmt(&self, _: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        Ok(())
    }
}
```

The solution is to define a local trait (or a local newtype when you need implementations of existing foreign traits), not to try to bypass coherence.

## Prefer Narrow Implementations Over Gratuitous Blanket Impl Surface

A blanket implementation can be appropriate when the extension is truly defined for every type satisfying a stable bound:

```rust
trait IsBlankExt {
    fn is_blank(&self) -> bool;
}

impl<T: AsRef<str>> IsBlankExt for T {
    fn is_blank(&self) -> bool {
        self.as_ref().trim().is_empty()
    }
}

fn main() {
    assert!("   ".is_blank());
    assert!(String::new().is_blank());
}
```

But a blanket impl means every future type satisfying the bound also gets the method, and it can overlap conceptually with methods from other traits. Implement the narrowest useful receiver when broad availability is not part of the API contract.

## Method Collisions Are Possible

If two imported traits define the same method for a receiver, normal method-call syntax can become ambiguous. Fully qualified syntax disambiguates deliberately.

```rust
trait ShortName {
    fn label(&self) -> &'static str;
}
trait LongName {
    fn label(&self) -> &'static str;
}

impl ShortName for u8 {
    fn label(&self) -> &'static str { "u8" }
}
impl LongName for u8 {
    fn label(&self) -> &'static str { "unsigned byte" }
}

fn main() {
    assert_eq!(ShortName::label(&1), "u8");
    assert_eq!(LongName::label(&1), "unsigned byte");
}
```

Choose method names and module/prelude exports with collision risk in mind.

## Ecosystem Pattern

Many ecosystem traits follow this model: `Iterator`-like extension traits add methods to types they do not own. For example, current `itertools::Itertools` is implemented for iterators and supplies methods such as `chunk_by`; Tokio's `AsyncReadExt` adds convenience methods to async readers.

Do not freeze third-party examples to deprecated method names. For example, current itertools deprecates `group_by` in favor of `chunk_by`.

## `#[diagnostic::do_not_recommend]` Is Optional Diagnostic Tuning

A broad extension-trait blanket impl may sometimes produce a misleading trait-bound diagnostic. If real compiler errors show that problem, `#[diagnostic::do_not_recommend]` can be placed on the legal trait impl as a diagnostic hint.

It does not guarantee rustc will suggest a particular alternative trait, and it does not change trait resolution or coherence. Keep the extension trait correct without the attribute first.

## Trait Object Upcasting Is a Separate Feature

Rust 1.86 trait-object upcasting concerns coercing `dyn Sub` to a dyn-compatible supertrait object. It is not a special extension-trait mechanism and does not make sealed/private supertraits automatically usable as public trait objects.

Keep upcasting guidance in the dedicated trait-object rule rather than treating it as an extension-trait feature.

## When a Newtype Is Better

Use a local newtype instead of an extension trait when you need:

- implementations of existing foreign traits (`Display`, `From`, etc.);
- a distinct type/invariant, not merely convenience methods;
- control over construction or representation semantics.

Extension traits add behavior without creating a new type; newtypes create a new type that can own trait implementations and invariants.

## Practical Guidance

- Define a local extension trait when method-call syntax materially improves use of an external type.
- Keep the receiver implementation as narrow as the abstraction allows.
- Remember callers need the trait in scope.
- Design for method-name collisions, especially when exporting traits in a prelude.
- Make string extension methods Unicode-safe according to an explicit unit (bytes/chars/graphemes).
- Use a newtype when you need foreign trait implementations or new invariants.
- Treat third-party method names and diagnostic wording as versioned details, not permanent contracts.

## See Also

- [api-do-not-recommend](./api-do-not-recommend.md) - Diagnostic hints for trait impls
- [api-sealed-trait](./api-sealed-trait.md) - Controlling downstream implementations
- [api-impl-into](./api-impl-into.md) - Conversion bounds
- [trait-upcasting](./trait-upcasting.md) - Trait-object supertrait coercion
