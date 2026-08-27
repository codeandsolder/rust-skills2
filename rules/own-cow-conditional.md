# own-cow-conditional

> Use `Cow<'a, B>` when an API can usually borrow data but sometimes needs an owned value

## Why It Matters

`std::borrow::Cow` represents either borrowed data (`Cow::Borrowed`) or the corresponding owned form (`Cow::Owned`). It is useful when the common path can return or carry a borrow while an uncommon path must allocate/own.

`Cow` does not magically remove allocations: producing an owned variant still has the owned type's cost, and mutating a borrowed value through `to_mut()` clones it first. Use it when those semantics match the API, not merely because an allocation might exist somewhere.

## Good: Borrow on the Common Path, Own When Needed

```rust
use std::borrow::Cow;

fn normalize_path(path: &str) -> Cow<'_, str> {
    if path.contains("//") {
        Cow::Owned(path.replace("//", "/"))
    } else {
        Cow::Borrowed(path)
    }
}

fn main() {
    assert!(matches!(normalize_path("a/b"), Cow::Borrowed(_)));
    assert_eq!(normalize_path("a//b"), "a/b");
}
```

The unchanged path performs no new string allocation. The replacement path returns an owned `String` because replacement necessarily constructs new contents.

## Static-or-Formatted Results

`Cow<'static, str>` is useful when known cases can be string literals but fallback cases are formatted dynamically.

```rust
use std::borrow::Cow;

fn error_message(code: u32) -> Cow<'static, str> {
    match code {
        404 => Cow::Borrowed("not found"),
        500 => Cow::Borrowed("internal error"),
        _ => Cow::Owned(format!("error {code}")),
    }
}

fn main() {
    assert!(matches!(error_message(404), Cow::Borrowed(_)));
    assert!(matches!(error_message(418), Cow::Owned(_)));
}
```

Here `'static` describes the lifetime of the borrowed variant. Owned variants are self-contained and can inhabit the same `Cow<'static, str>` type.

## Clone-on-Write Mutation

`to_mut()` returns mutable access to the owned representation. If the `Cow` is borrowed, it clones into the owned form first; if it is already owned, it mutates that allocation directly.

```rust
use std::borrow::Cow;

fn uppercase_if_needed(mut text: Cow<'_, str>) -> Cow<'_, str> {
    if text.bytes().any(|byte| byte.is_ascii_lowercase()) {
        text.to_mut().make_ascii_uppercase();
    }
    text
}

fn main() {
    let unchanged = uppercase_if_needed(Cow::Borrowed("123"));
    assert!(matches!(unchanged, Cow::Borrowed(_)));

    let changed = uppercase_if_needed(Cow::Borrowed("hello"));
    assert_eq!(changed, "HELLO");
    assert!(matches!(changed, Cow::Owned(_)));
}
```

Use `into_owned()` when you actually want to leave the `Cow` abstraction and obtain the owned value. For a borrowed `Cow`, that conversion clones even if no mutation follows.

## `Cow` Works for More Than `str`

The borrowed type must implement `ToOwned`; common examples include `str`/`String` and `[T]`/`Vec<T>`.

```rust
use std::borrow::Cow;

fn ensure_trailing_zero(bytes: &[u8]) -> Cow<'_, [u8]> {
    if bytes.last() == Some(&0) {
        Cow::Borrowed(bytes)
    } else {
        let mut owned = bytes.to_vec();
        owned.push(0);
        Cow::Owned(owned)
    }
}

fn main() {
    assert!(matches!(ensure_trailing_zero(&[1, 0]), Cow::Borrowed(_)));
    assert_eq!(ensure_trailing_zero(&[1]), &[1, 0]);
}
```

## When `Cow` Is the Wrong Shape

| Situation | Prefer |
|---|---|
| Always returns owned data | `String`, `Vec<T>`, or the actual owned type |
| Always returns a borrow | `&str`, `&[T]`, or another reference |
| Caller must share ownership independently of the source borrow | `Arc<T>` / `Rc<T>` as appropriate |
| Mutation almost always occurs | Taking/returning the owned type may be simpler |
| Performance-sensitive path | Benchmark the real borrowed/owned distribution |

`Cow` itself introduces a branch on which representation is active, and a borrowed value may clone on first mutation. “Hot path” is not by itself a reason to use `Cow`.

## Edition 2024 RPIT Does Not Change Direct `Cow` Returns

A signature such as this is a direct concrete return type:

```rust
use std::borrow::Cow;

struct Greeter {
    name: String,
}

impl Greeter {
    fn greeting(&self) -> Cow<'_, str> {
        if self.name == "world" {
            Cow::Borrowed("hello world")
        } else {
            Cow::Owned(format!("hello {}", self.name))
        }
    }
}

fn main() {
    let greeter = Greeter { name: "Ada".into() };
    assert_eq!(greeter.greeting(), "hello Ada");
}
```

There is no `impl Trait` in that signature, so Edition-2024 RPIT capture rules are not what make the lifetime work. Ordinary lifetime elision/inference ties the placeholder lifetime to the receiver borrow.

Edition 2024 matters when the function instead returns an opaque `impl Trait` whose hidden concrete type contains a borrow. See `own-cow-rpit-edition2024` for that specific case.

## `LazyCell::from` Is Unrelated to Clone-on-Write

Rust 1.96 added `From<T>` for `LazyCell<T, F>` and `LazyLock<T, F>`, but those conversions construct a lazy container that starts **already initialized** with the supplied value. They are not equivalent to `LazyCell::new(|| value)`, which stores an initializer to be run on first access.

That API belongs in lazy-initialization guidance, not in a `Cow` ownership rule.

## Diagnostic Attributes Are Also Unrelated

`#[diagnostic::do_not_recommend]` is a hint on trait implementations that affects compiler diagnostics. It does not change `Cow`, `From`, ownership, or coherence rules, and it cannot make an otherwise illegal foreign-trait implementation legal.

Keep diagnostic customization in the dedicated diagnostic rule rather than attaching arbitrary `From<T> for Cow<...>` examples here.

## Practical Guidance

- Use `Cow` when “borrow most of the time, own sometimes” is the real data model.
- Prefer `Borrowed` when the output can safely reference existing data.
- Use `to_mut()` when mutation should clone a borrowed value on demand.
- Use `into_owned()` only when the caller truly needs the owned representation.
- Do not attribute direct `Cow<'_, T>` lifetime elision to Edition-2024 RPIT capture.
- Benchmark when `Cow` is justified primarily by performance rather than API semantics.

## See Also

- [own-borrow-over-clone](./own-borrow-over-clone.md) - Prefer borrowing over cloning
- [own-cow-rpit-edition2024](./own-cow-rpit-edition2024.md) - Cow hidden behind RPIT in Edition 2024
- [own-lifetime-elision](./own-lifetime-elision.md) - Elision versus RPIT capture
- [own-lazy-init](./own-lazy-init.md) - LazyCell and LazyLock semantics
