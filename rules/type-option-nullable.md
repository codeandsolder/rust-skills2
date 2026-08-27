# type-option-nullable

> Use `Option<T>` when absence is an ordinary state; use `Result<T, E>` when callers need failure information

**Rule**: `type-option-nullable`

## Why It Matters

`Option<T>` makes “present or absent” explicit in the type system. It avoids sentinel values and nullable raw-pointer conventions, and it lets APIs distinguish ordinary absence from an operation that failed for a reason.

Use `Option` when `None` is sufficient information. If callers need to know *why* a value is missing, return `Result` or another domain-specific type instead.

## Good: Model Ordinary Absence Directly

```rust
use std::collections::HashMap;

fn find_name(users: &HashMap<u64, String>, id: u64) -> Option<&str> {
    users.get(&id).map(String::as_str)
}

fn main() {
    let users = HashMap::from([(1, String::from("Ada"))]);
    assert_eq!(find_name(&users, 1), Some("Ada"));
    assert_eq!(find_name(&users, 2), None);
}
```

Returning an empty string or synthetic “missing user” object would make absence indistinguishable from a legitimate value unless every caller remembered a convention.

## Match When Both Cases Matter

```rust
fn describe(value: Option<u32>) -> String {
    match value {
        Some(value) => format!("value={value}"),
        None => "missing".to_owned(),
    }
}

fn main() {
    assert_eq!(describe(Some(7)), "value=7");
    assert_eq!(describe(None), "missing");
}
```

Use `if let` when only the `Some` branch is interesting, and combinators when they make a simple transformation clearer.

## Propagate Absence With `?`

```rust
#[derive(Debug)]
struct User {
    email: Option<String>,
}

fn email_domain(user: Option<&User>) -> Option<&str> {
    let user = user?;
    let email = user.email.as_deref()?;
    email.split_once('@').map(|(_, domain)| domain)
}

fn main() {
    let user = User {
        email: Some("ada@example.test".into()),
    };
    assert_eq!(email_domain(Some(&user)), Some("example.test"));
    assert_eq!(email_domain(None), None);
}
```

The `?` operator on `Option` returns `None` from the enclosing `Option`-returning function when the operand is `None`.

## Transform and Chain Without Unwrapping

```rust
fn normalized_length(value: Option<&str>) -> Option<usize> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::len)
}

fn main() {
    assert_eq!(normalized_length(Some("  rust  ")), Some(4));
    assert_eq!(normalized_length(Some("   ")), None);
    assert_eq!(normalized_length(None), None);
}
```

Prefer a direct `match` when a long combinator chain obscures control flow; combinators are not a goal by themselves.

## `Option::zip`

Use `zip` when a result exists only if both options are present.

```rust
fn main() {
    let width = Some(1920u32);
    let height = Some(1080u32);
    let missing: Option<u32> = None;

    assert_eq!(width.zip(height), Some((1920, 1080)));
    assert_eq!(width.zip(missing), None);
}
```

If either side's absence needs a distinct explanation, `Result` or an explicit match is a better fit.

## `Option::as_slice` / `as_mut_slice` (Rust 1.75+)

`as_slice` views `Some(value)` as a one-element slice and `None` as an empty slice. The API stabilized in Rust **1.75**, not 1.81.

```rust
fn main() {
    let present = Some(42);
    let absent: Option<i32> = None;

    assert_eq!(present.as_slice(), &[42]);
    assert!(absent.as_slice().is_empty());
}
```

This is convenient when one optional item should feed an API or iterator that already works on slices.

```rust
fn strings(items: &[Option<String>]) -> Vec<&str> {
    items
        .iter()
        .flat_map(Option::as_slice)
        .map(String::as_str)
        .collect()
}

fn main() {
    let items = [Some("a".into()), None, Some("b".into())];
    assert_eq!(strings(&items), ["a", "b"]);
}
```

The explicit `String::as_str` mapping matters: iterating `Option<String>::as_slice()` yields `&String`; collection does not generally insert the `&String` → `&str` coercion for you.

The mutable view works similarly:

```rust
fn main() {
    let mut value = Some(String::from("hello"));
    if let Some(text) = value.as_mut_slice().first_mut() {
        text.push_str(" world");
    }
    assert_eq!(value.as_deref(), Some("hello world"));
}
```

## Let Chains (Rust 1.88+, Edition 2024)

Rust 1.88 stabilized `let` chains for the 2024 edition. They let several pattern checks and boolean conditions share one `if`/`while` condition.

```rust
#[derive(Debug)]
struct User {
    email: Option<String>,
    active: bool,
}

fn company_email(user: Option<&User>) -> Option<&str> {
    if let Some(user) = user
        && user.active
        && let Some(email) = user.email.as_deref()
        && email.ends_with("@company.test")
    {
        Some(email)
    } else {
        None
    }
}

fn main() {
    let user = User {
        email: Some("ada@company.test".into()),
        active: true,
    };
    assert_eq!(company_email(Some(&user)), Some("ada@company.test"));
}
```

Do not label let-chains as a Rust 1.85 feature merely because Rust 2024 itself shipped in 1.85; let-chains stabilized later in 1.88 and are edition-gated to 2024.

For a pure sequence of `Option` extraction where each `None` should simply propagate, `?` is often shorter than a let-chain.

## Optional Fields

```rust
#[derive(Debug)]
struct Profile {
    display_name: String,
    phone: Option<String>,
}

impl Profile {
    fn phone_or_placeholder(&self) -> &str {
        self.phone.as_deref().unwrap_or("not provided")
    }
}

fn main() {
    let profile = Profile {
        display_name: "Ada".into(),
        phone: None,
    };
    assert_eq!(profile.phone_or_placeholder(), "not provided");
    assert_eq!(profile.display_name, "Ada");
}
```

Optionality belongs in the field type when absence is valid state, rather than in an undocumented magic value.

## `Option` vs `Result`

```rust
fn lookup(values: &[u32], index: usize) -> Option<u32> {
    values.get(index).copied()
}

fn parse_number(raw: &str) -> Result<u32, std::num::ParseIntError> {
    raw.parse()
}

fn main() {
    assert_eq!(lookup(&[10, 20], 5), None);
    assert!(parse_number("not-a-number").is_err());
}
```

A missing index needs no additional explanation here; malformed numeric text does.

Convert deliberately when crossing API boundaries:

```rust
fn first(values: &[u32]) -> Result<u32, &'static str> {
    values.first().copied().ok_or("empty input")
}

fn main() {
    assert_eq!(first(&[9]), Ok(9));
    assert_eq!(first(&[]), Err("empty input"));
}
```

Calling `.ok()` on a `Result` discards error information, so do that only when the distinction is genuinely irrelevant.

## See Also

- [type-result-fallible](./type-result-fallible.md) — failures with error information
- [type-enum-states](./type-enum-states.md) — explicit state modeling
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — handling optional/fallible values

## References

- [`Option`](https://doc.rust-lang.org/std/option/enum.Option.html)
- [Rust 1.88 let-chains](https://blog.rust-lang.org/2025/06/26/Rust-1.88.0/)
