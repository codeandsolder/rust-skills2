# api-impl-into

> Accept `Into<T>` when the API intentionally takes ownership and useful caller types can convert into `T`

## Why It Matters

A parameter such as `impl Into<String>` lets callers provide `String` itself or another type with an infallible consuming conversion to `String`. This is useful for constructors, setters, builders, and other APIs that need to own the resulting value.

It is not a free abstraction. The conversion may allocate, a generic function may be monomorphized for multiple input types, and type inference/error messages can become more complex. Prefer an exact `T` when flexibility does not materially improve the API.

## Good: Ownership-Taking Convenience

```rust
fn make_label(label: impl Into<String>) -> String {
    label.into()
}

fn main() {
    assert_eq!(make_label("ready"), "ready");

    let owned = String::from("owned");
    assert_eq!(make_label(owned), "owned");
}
```

Passing an `&str` to `Into<String>` allocates a `String`; passing an existing `String` moves it without cloning. The call-site syntax does not imply a zero-cost conversion.

## `impl Into<T>` Uses Static Dispatch

`impl Trait` in argument position is a generic parameter. Calls are statically dispatched/monomorphized; there is no virtual trait-object dispatch merely because the signature mentions `Into`.

The relevant performance tradeoffs are instead:

- the actual conversion performed by `into()`;
- possible code-size/compile-time cost from multiple monomorphizations;
- whether the generic boundary prevents or enables useful inlining/optimization.

Do not tell callers to replace `impl Into<T>` with `T` to avoid “trait dispatch.” Measure code-size or runtime effects if they matter.

## Implement `From`, Usually Accept `Into`

For a conversion you own, implement `From<Source> for Destination`. The standard library's blanket implementation then provides `Into<Destination> for Source` automatically.

```rust
#[derive(Debug, PartialEq, Eq)]
struct UserId(u64);

impl From<u64> for UserId {
    fn from(value: u64) -> Self {
        Self(value)
    }
}

fn lookup(id: impl Into<UserId>) -> UserId {
    id.into()
}

fn main() {
    assert_eq!(UserId::from(7), UserId(7));
    assert_eq!(lookup(42_u64), UserId(42));
}
```

The standard docs recommend `Into<T>` rather than `From<T>` as an input bound because it also accepts types that happen to implement `Into` directly.

## Exact Owned Types Are Often Clearer

If callers already have the exact owned type, adding a conversion bound may create generic complexity without improving ergonomics.

```rust
struct Request {
    body: Vec<u8>,
}

fn send(request: Request) -> usize {
    request.body.len()
}

fn main() {
    let request = Request { body: vec![1, 2, 3] };
    assert_eq!(send(request), 3);
}
```

A public API can always add named constructors/conversions where the domain has meaningful alternate representations.

## `Into` Is for Infallible Consuming Conversion

`Into<T>` must not fail. If validating/converting can fail, use `TryInto<T>`/`TryFrom` or a named fallible constructor.

```rust
use std::num::NonZeroU32;

fn require_nonzero<T>(value: T) -> Result<NonZeroU32, T::Error>
where
    T: TryInto<NonZeroU32>,
{
    value.try_into()
}

fn main() {
    assert_eq!(require_nonzero(5_u32).unwrap().get(), 5);
    assert!(require_nonzero(0_u32).is_err());
}
```

If a conversion is lossy, domain-dependent, or surprising, a named method can be clearer even when it cannot fail.

## Trait Objects Are Not a Reason to Reject an `Into` Bound

This signature is legal Rust:

```rust
trait Handler {
    fn handle(&self) -> u32;
}

struct BoxedHandler(Box<dyn Handler>);

fn install(handler: impl Into<BoxedHandler>) -> BoxedHandler {
    handler.into()
}

fn main() {}
```

`Into` itself is `Sized` and not dyn-compatible, but the bound above is on a statically known generic input type. A trait object nested inside the destination type does not turn the `Into` call into dynamic dispatch.

Whether such a bound is *useful* depends on which conversions actually exist. If only `BoxedHandler` converts to itself, accepting `BoxedHandler` directly is simpler.

## Where `impl Trait` Can Appear

Argument-position `impl Into<T>` is shorthand for a generic function parameter. You cannot put `impl Into<Node>` directly in an ordinary struct field type on stable Rust.

```rust
struct Node {
    children: Vec<Node>,
}

impl Node {
    fn push(&mut self, child: impl Into<Node>) {
        self.children.push(child.into());
    }
}

fn main() {
    let mut root = Node { children: Vec::new() };
    root.push(Node { children: Vec::new() });
    assert_eq!(root.children.len(), 1);
}
```

Keep the stored representation concrete even when a constructor/setter accepts flexible inputs.

## `AsRef` Versus `Into`

Use the trait that matches ownership:

```rust
use std::path::{Path, PathBuf};

fn inspect(path: impl AsRef<Path>) -> usize {
    path.as_ref().components().count()
}

fn store(path: impl Into<PathBuf>) -> PathBuf {
    path.into()
}

fn main() {
    assert_eq!(inspect("a/b"), 2);
    assert_eq!(store("a/b"), PathBuf::from("a/b"));
}
```

`AsRef<Path>` only needs a borrowed view during the call. `Into<PathBuf>` deliberately produces an owned path.

## Builders

Opt-in conversion setters can be a good fit when a builder's field is owned and common caller types convert naturally. Whether written manually or generated by a builder crate, the conversion should remain intentional and visible in the builder definition.

Do not assume every setter benefits from `Into`; exact numeric/enumerated/domain types are often clearer and produce better inference.

## Practical Guidance

- Use `Into<T>` for infallible consuming conversion into an owned representation.
- Implement `From<Source> for Destination` for conversions you own; the blanket impl supplies `Into`.
- Do not claim `impl Into<T>` incurs virtual trait dispatch—it is statically dispatched.
- Consider monomorphization, inference, and actual conversion cost when making public APIs generic.
- Use `TryInto`/`TryFrom` or named constructors for fallible conversion.
- Keep stored field types concrete even if constructor/setter parameters are flexible.

## See Also

- [api-impl-asref](./api-impl-asref.md) - Borrowed generic views
- [api-from-not-into](./api-from-not-into.md) - Implementing conversion traits
- [api-bon-builder](./api-bon-builder.md) - Builder conversion opt-ins
- [err-from-impl](./err-from-impl.md) - Error conversions
