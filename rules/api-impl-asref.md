# api-impl-asref

> Use `AsRef<T>` for cheap generic borrowed views when accepting several source types is genuinely useful

## Why It Matters

`AsRef<T>` represents a cheap, infallible conversion from `&Self` to `&T`. It is useful when an API wants a borrowed view such as `&str`, `&[u8]`, or `&Path` and several input types naturally provide that view.

Do not turn every `&T` parameter into `impl AsRef<T>`. A concrete borrow is simpler, avoids extra generic surface area, and communicates exactly what the function needs.

Also distinguish the trait's borrowing operation from the **function parameter's ownership**: a function taking `value: impl AsRef<T>` by value still moves an owned argument into the function.

## Good: Generic Borrowed View When It Improves the Call Sites

```rust
use std::path::{Path, PathBuf};

fn component_count(path: impl AsRef<Path>) -> usize {
    path.as_ref().components().count()
}

fn main() {
    assert_eq!(component_count("a/b/c"), 3);
    assert_eq!(component_count(PathBuf::from("a/b")), 2);
}
```

The conversion performed by `as_ref()` is a borrow; it should not allocate or otherwise perform a costly conversion.

The `PathBuf` argument above is nevertheless **moved** because the function parameter is by value. If callers should retain ownership and you only need one view, `&Path` is often the cleaner API.

## Plain References Are Often Better

```rust
use std::path::{Path, PathBuf};

fn file_name(path: &Path) -> Option<&str> {
    path.file_name()?.to_str()
}

fn main() {
    let path = PathBuf::from("dir/file.txt");
    assert_eq!(file_name(&path), Some("file.txt"));
    // `path` is still owned by the caller.
    assert_eq!(path.components().count(), 2);
}
```

Deref coercions already make common owned/smart-pointer types ergonomic to borrow. Use `AsRef` when the additional accepted representations are part of the intended API, not merely to avoid writing `&value`.

## `AsRef` Is a Cheap Reference-to-Reference Conversion

A custom wrapper can expose one of its fields as a borrowed view:

```rust
struct Name(String);

impl AsRef<str> for Name {
    fn as_ref(&self) -> &str {
        &self.0
    }
}

fn starts_with_a(name: impl AsRef<str>) -> bool {
    name.as_ref().starts_with('A')
}

fn main() {
    assert!(starts_with_a(Name("Ada".into())));
    assert!(starts_with_a("Alice"));
}
```

If producing the target would allocate, parse, validate, or otherwise do substantial work, `AsRef` is the wrong abstraction. Use `From`/`TryFrom` or a named method that makes the work/failure explicit.

## `AsRef` Is Not Universally Reflexive

There is no blanket `impl<T: ?Sized> AsRef<T> for T` for every type. The standard library documents historical overlap restrictions that prevent such a universal reflexive implementation.

Many common standard types provide the specific implementations users expect—such as `String: AsRef<str>`—but generic code should not assume every `T` automatically implements `AsRef<T>`.

For a local type where a reflexive view is useful, you may implement it explicitly:

```rust
struct Token(u64);

impl AsRef<Token> for Token {
    fn as_ref(&self) -> &Token {
        self
    }
}

fn main() {
    let token = Token(7);
    assert_eq!(token.as_ref().0, 7);
}
```

## `Borrow` Has a Stronger Semantic Contract

`Borrow<T>` has a similar method signature, but for key-like borrowing it requires borrowed and owned forms to behave equivalently for `Eq`, `Ord`, and `Hash` where those traits are implemented. That is why collections such as `HashMap<String, V>` can be queried with `&str`.

```rust
use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;

fn lookup<'a, Q: ?Sized>(
    map: &'a HashMap<String, u32>,
    key: &Q,
) -> Option<&'a u32>
where
    String: Borrow<Q>,
    Q: Eq + Hash,
{
    map.get(key)
}

fn main() {
    let map = HashMap::from([(String::from("answer"), 42)]);
    assert_eq!(lookup(&map, "answer"), Some(&42));
}
```

Use `AsRef` when you want a cheap view without that equality/hash consistency promise; use `Borrow` when that promise is part of the abstraction.

## `AsRef` Is Not a Deref Spelling

For ordinary smart-pointer dereferencing, prefer deref coercion rather than calling `as_ref()` solely to obtain `&T`.

```rust
fn increment(value: &i32) -> i32 {
    value + 1
}

fn main() {
    let boxed = Box::new(41);
    assert_eq!(increment(&boxed), 42);
}
```

A smart pointer may also implement `AsRef`, but `Deref` and `AsRef` communicate different API relationships.

## Choosing the Parameter Shape

| Need | Typical parameter |
|---|---|
| Exactly a borrowed `T` | `&T` |
| Several cheap borrowed representations | `impl AsRef<T>` or `P: AsRef<T>` |
| Consume/own a converted value | `impl Into<T>` |
| Fallible consuming conversion | `TryInto<T>` / named constructor |
| Key-like equivalent borrowed representation | `Borrow<Q>` bounds |
| Smart-pointer dereferencing | ordinary `&value` / deref coercion |

Generic convenience has costs: more monomorphizations, more complicated signatures, and sometimes worse type inference. Prefer it when callers actually benefit.

## Practical Guidance

- Use `AsRef<T>` only for cheap, infallible borrowed views.
- Remember that a by-value `impl AsRef<T>` parameter still moves owned arguments.
- Prefer `&T` when one borrowed target type already gives ergonomic call sites.
- Do not assume `AsRef<T>` is blanket-reflexive for every `T`.
- Use `Borrow` instead when equality/hash/order equivalence of owned and borrowed forms matters.
- Use deref coercion, not `AsRef`, merely to dereference smart pointers.

## See Also

- [api-impl-into](./api-impl-into.md) - Ownership-taking generic conversions
- [own-slice-over-vec](./own-slice-over-vec.md) - Prefer borrowed slice/string/path types
- [own-borrow-over-clone](./own-borrow-over-clone.md) - Borrowing versus ownership
