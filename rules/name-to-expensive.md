# name-to-expensive

> Use `to_` for ad-hoc conversions that do nontrivial work without consuming a non-Copy receiver

## Why It Matters

Rust's `to_` convention says that an ad-hoc conversion performs nontrivial work. Allocation and cloning are common examples, but `to_` is not limited to conversions that produce an owned value: an expensive borrowed-to-borrowed conversion can also use `to_`.

The Rust API Guidelines distinguish the three conversion prefixes this way:

| Prefix | Expected cost | Ownership shape |
|--------|---------------|-----------------|
| `as_` | Free | borrowed → borrowed |
| `to_` | Expensive | borrowed → borrowed, borrowed → owned, or Copy owned → owned |
| `into_` | Variable | non-Copy owned → owned |

For non-Copy values, `to_*` generally borrows while `into_*` consumes. For Copy values, taking the value itself may be natural even for a `to_*` conversion.

## Bad

<!-- rust-check: compile -->
```rust
struct Name(String);

impl Name {
    // BAD: `as_` promises a free borrowed conversion, but Unicode uppercasing
    // scans the string and allocates a new String.
    fn as_uppercase(&self) -> String {
        self.0.to_uppercase()
    }

    // BAD: `get_` is not the ad-hoc conversion convention and hides the clone.
    fn get_string(&self) -> String {
        self.0.clone()
    }
}
```

## Good

<!-- rust-check: compile -->
```rust
struct Name(String);

impl Name {
    // `to_` = work is required; this allocates and performs Unicode casing.
    fn to_uppercase(&self) -> String {
        self.0.to_uppercase()
    }

    // `to_` = creates a new owned representation.
    fn to_owned_string(&self) -> String {
        self.0.clone()
    }

    // `as_` = free borrowed view.
    fn as_str(&self) -> &str {
        &self.0
    }

    // `into_` = consumes the wrapper and transfers ownership.
    fn into_string(self) -> String {
        self.0
    }
}
```

## Standard Library Shapes

```rust
use std::path::Path;

let bytes: Vec<u8> = [1_u8, 2, 3].as_slice().to_vec();
let owned: String = "hello".to_string();
let lower: String = "HELLO".to_lowercase();

// Expensive borrowed -> borrowed is also a `to_` shape: this validates that
// the platform path is UTF-8 before returning the borrowed `&str`.
let path = Path::new("example");
let text: Option<&str> = path.to_str();

// Copy owned -> owned: there is no reason to borrow a cheap Copy scalar.
let radians: f64 = 180.0_f64.to_radians();

assert_eq!(bytes, vec![1, 2, 3]);
assert_eq!(owned, "hello");
assert_eq!(lower, "hello");
assert_eq!(text, Some("example"));
assert_eq!(radians, std::f64::consts::PI);
```

## `into_` Does Not Mean Cheap

The `into_` prefix communicates ownership transfer, while its cost is variable. Some ownership-consuming conversions are free, while others may need work before returning the inner value.

```rust
struct Wrapper(String);

impl Wrapper {
    fn into_inner(self) -> String {
        self.0
    }
}
```

Do not choose between `to_` and `into_` solely by benchmarking cost; the receiver ownership is part of the convention.

## Custom Type Example

```rust
struct Email(String);

impl Email {
    fn as_str(&self) -> &str {
        &self.0
    }

    fn to_lowercase(&self) -> Email {
        Email(self.0.to_lowercase())
    }

    fn to_display_format(&self) -> String {
        format!("<{}>", self.0)
    }

    fn into_string(self) -> String {
        self.0
    }
}
```

## `to_owned()` Pattern

`ToOwned` is the standard trait for producing an owned form of borrowed data:

```rust
let borrowed_str: &str = "hello";
let owned_string: String = borrowed_str.to_owned();

let borrowed_slice: &[i32] = &[1, 2, 3];
let owned_vec: Vec<i32> = borrowed_slice.to_owned();
```

## Abstraction Level

`as_` and `into_` conversions **typically** expose or extract a lower-level representation, while `to_` conversions typically stay at the same abstraction level and do work to change representation. Treat that as a useful pattern, not a type-system law; ownership and cost are the primary naming signals.

## See Also

- [name-as-free](./name-as-free.md) - Free borrowed conversions
- [name-into-ownership](./name-into-ownership.md) - Ownership-consuming conversions
- [own-cow-conditional](./own-cow-conditional.md) - Avoiding unnecessary allocations
