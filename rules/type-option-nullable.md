# type-option-nullable

> Use `Option<T>` for values that might not exist

**Rule**: `type-option-nullable`

## Why It Matters

`Option<T>` explicitly represents "value or nothing" in the type system. Unlike null pointers or sentinel values, you can't accidentally use a missing value — the compiler forces you to handle the `None` case. This eliminates null pointer exceptions at compile time.

## Bad

```rust
// Sentinel values — easy to forget to check
fn find_user(id: u64) -> User {
    users.get(&id).cloned().unwrap_or(User::empty())
    // Returns "empty" user if not found — caller might not check
}

// Nullable-style with raw pointers
fn find_user(id: u64) -> *const User {
    // Null if not found — unsafe, no compiler help
}

// Error-prone usage
let user = find_user(42);
println!("{}", user.name);  // Might be empty user — silent bug
```

## Good

```rust
// Option makes absence explicit
fn find_user(id: u64) -> Option<User> {
    users.get(&id).cloned()
}

// Must handle the None case
let user = find_user(42);
match user {
    Some(u) => println!("{}", u.name),
    None => println!("User not found"),
}

// Or use combinators
let name = find_user(42)
    .map(|u| u.name)
    .unwrap_or_else(|| "Unknown".to_string());
```

## Common Option Patterns

```rust
// if let for single case
if let Some(user) = find_user(id) {
    process(user);
}

// Chaining with map
let upper_name = find_user(id)
    .map(|u| u.name)
    .map(|n| n.to_uppercase());

// Providing defaults
let user = find_user(id).unwrap_or_default();
let user = find_user(id).unwrap_or_else(|| User::guest());

// ? operator for propagation
fn get_user_email(id: u64) -> Option<String> {
    let user = find_user(id)?;
    Some(user.email)
}

// and_then for chained optionals
fn get_user_country(id: u64) -> Option<String> {
    find_user(id)
        .and_then(|u| u.address)
        .and_then(|a| a.country)
}
```

## `Option::zip` (Rust 1.71+)

Combine two `Option` values into an `Option` of a tuple:

```rust
let a: Option<i32> = Some(1);
let b: Option<i32> = Some(2);
let c: Option<i32> = None;

// Before zip: manual match or if let
let combined = match (a, b) {
    (Some(x), Some(y)) => Some((x, y)),
    _ => None,
};

// After zip: concise
let combined: Option<(i32, i32)> = a.zip(b);  // Some((1, 2))
let combined: Option<(i32, i32)> = a.zip(c);  // None

// Zip with function via zip_with (nightly) or manual map
let sum = a.zip(b).map(|(x, y)| x + y);  // Some(3)
```

## `Option::as_slice()` (Rust 1.81+)

Convert `Option<T>` to a zero-or-one-element slice — useful for iteration and APIs that expect slices:

```rust
let opt = Some(42);
let slice: &[i32] = opt.as_slice();
assert_eq!(slice, &[42]);

let none: Option<i32> = None;
let slice: &[i32] = none.as_slice();
assert!(slice.is_empty());

// Useful for building collections
fn collect_options(items: &[Option<String>]) -> Vec<&str> {
    items.iter().flat_map(Option::as_slice).collect()
}

// Mutable version
let mut opt = Some(String::from("hello"));
if let Some(s) = opt.as_mut_slice().first_mut() {
    s.push_str(" world");
}
```

## `let_chains` for Multiple Option Checks (Edition 2024, Rust 1.85+)

Chain multiple `Option` checks without deep nesting:

```rust
// Before let_chains: deeply nested
fn get_user_country(id: u64) -> Option<String> {
    let user = find_user(id)?;
    let address = user.address?;
    let country = address.country?;
    Some(country)
}

// After let_chains (Edition 2024, Rust 1.85+): flat and readable
fn get_user_country(id: u64) -> Option<String> {
    if let Some(user) = find_user(id)
        && let Some(address) = user.address
        && let Some(country) = address.country
    {
        Some(country)
    } else {
        None
    }
}

// With extra condition checks
if let Some(user) = find_user(id)
    && let Some(email) = &user.email
    && email.ends_with("@company.com")
{
    // Only process company users with confirmed emails
    process_company_user(user);
}
```

## Struct Fields

```rust
struct User {
    name: String,
    email: String,
    phone: Option<String>,        // Optional field
    avatar_url: Option<Url>,      // Optional field
}

impl User {
    fn display_phone(&self) -> &str {
        self.phone.as_deref().unwrap_or("Not provided")
    }
}
```

## Option vs Result

```rust
// Option: value might not exist (no error context)
fn find(key: &str) -> Option<Value> { todo!() }

// Result: operation might fail (with error context)
fn parse(input: &str) -> Result<Value, ParseError> { todo!() }

// Convert Option to Result
let value = find("key").ok_or(Error::NotFound)?;

// Convert Result to Option
let value = parse("input").ok();  // Discards error
```

## Option References

```rust
// Option<&T> for optional borrows
fn get(&self, key: &str) -> Option<&Value> {
    self.map.get(key)
}

// as_ref() to borrow Option contents
let opt: Option<String> = Some("hello".to_string());
let opt_ref: Option<&String> = opt.as_ref();
let opt_str: Option<&str> = opt.as_deref();

// as_mut() for mutable borrow
let mut opt = Some(vec![1, 2, 3]);
if let Some(v) = opt.as_mut() {
    v.push(4);
}
```

## See Also

- [Rust Book: Option](https://doc.rust-lang.org/book/ch06-01-defining-an-enum.html#the-option-enum)
- [Option in std docs](https://doc.rust-lang.org/std/option/enum.Option.html)
- [type-result-fallible](./type-result-fallible.md) — `Result` for errors
- [type-enum-states](./type-enum-states.md) — Enums for states
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — Handling `Option` safely
