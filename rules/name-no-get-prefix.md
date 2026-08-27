# name-no-get-prefix

> Omit `get_` for ordinary named getters; reserve `get` for APIs where “get the one obvious value” or validated/indexed access is the established operation

## Why It Matters

Rust's API Guidelines normally name a getter after the thing it returns:

- `first()` rather than `get_first()`;
- `first_mut()` rather than `get_first_mut()`;
- `name()` rather than `get_name()`.

But `get` is not reserved for “methods that do extra work.” The standard convention also uses plain `get()` when there is one obvious thing to retrieve, such as `Cell::get`, and uses the `get` family for checked/indexed lookup such as slice or map access.

Choose names from the semantic shape of the API, not from a simplistic “Option means get” rule.

## Ordinary Named Getters

```rust
struct User {
    name: String,
    age: u32,
}

impl User {
    fn name(&self) -> &str {
        &self.name
    }

    fn age(&self) -> u32 {
        self.age
    }

    fn is_adult(&self) -> bool {
        self.age >= 18
    }
}

fn main() {
    let user = User { name: "Ada".to_owned(), age: 37 };
    assert_eq!(user.name(), "Ada");
    assert_eq!(user.age(), 37);
    assert!(user.is_adult());
}
```

`get_name()` and `get_age()` would add a word without clarifying the contract.

## Mutable Getter: Put `_mut` Last

```rust
struct Buffer {
    bytes: Vec<u8>,
}

impl Buffer {
    fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    fn bytes_mut(&mut self) -> &mut [u8] {
        &mut self.bytes
    }
}

fn main() {
    let mut buffer = Buffer { bytes: vec![1, 2] };
    buffer.bytes_mut()[0] = 9;
    assert_eq!(buffer.bytes(), &[9, 2]);
}
```

The mutability qualifier belongs at the end of the full getter name: `bytes_mut`, `first_mut`, `value_mut`.

## `get()` for One Obvious Contained Value

The API Guidelines call out `Cell::get` as a canonical case: the type contains one obvious value, so there is no useful noun to put before or after `get`.

```rust
use std::cell::Cell;

fn main() {
    let value = Cell::new(42_u32);
    assert_eq!(value.get(), 42);
}
```

This is a simple getter despite using the word `get`, so “never use get for field-like access” would also be wrong.

## `get` Family for Checked or Keyed Access

Slices and maps use `get` when the caller supplies an index/key and the operation may fail to find an element:

```rust
use std::collections::HashMap;

fn main() {
    let values = [10, 20, 30];
    assert_eq!(values.get(1), Some(&20));
    assert_eq!(values.get(99), None);

    let map = HashMap::from([("port", 8080)]);
    assert_eq!(map.get("port"), Some(&8080));
    assert_eq!(map.get("missing"), None);
}
```

Common related names are:

```text
get(...)
get_mut(...)
get_unchecked(...)
get_unchecked_mut(...)
```

An unsafe `_unchecked` form is appropriate only when the abstraction genuinely supports a safe checked operation plus a caller-verified unchecked counterpart. Do not add one merely to complete a naming table.

## Name Computations and Lookups by What They Mean

A method that selects configuration for an environment need not be called `get_config` merely because it performs a lookup:

```rust
use std::collections::HashMap;

struct Context {
    current_env: String,
    configs: HashMap<String, String>,
}

impl Context {
    fn current_config(&self) -> Option<&str> {
        self.configs.get(&self.current_env).map(String::as_str)
    }
}

fn main() {
    let context = Context {
        current_env: "prod".to_owned(),
        configs: HashMap::from([("prod".to_owned(), "safe".to_owned())]),
    };
    assert_eq!(context.current_config(), Some("safe"));
}
```

`current_config()` communicates the domain meaning better than a generic `get_config()`.

## Getter Versus Conversion

A borrowed view is not always a getter. Conversion naming (`as_`, `to_`, `into_`) communicates a representation change:

```rust
use std::path::{Path, PathBuf};

struct TempLike {
    path: PathBuf,
}

impl TempLike {
    fn path(&self) -> &Path {
        &self.path
    }

    fn into_path(self) -> PathBuf {
        self.path
    }
}

fn main() {
    let value = TempLike { path: PathBuf::from("tmp") };
    assert_eq!(value.path(), Path::new("tmp"));
    assert_eq!(value.into_path(), PathBuf::from("tmp"));
}
```

The noun getter describes a property; the `into_` conversion describes ownership transfer.

## Setters and Builders

Setter methods conventionally use `set_`:

```rust
use std::time::Duration;

struct Config {
    timeout: Duration,
}

impl Config {
    fn timeout(&self) -> Duration {
        self.timeout
    }

    fn set_timeout(&mut self, timeout: Duration) {
        self.timeout = timeout;
    }
}

fn main() {
    let mut config = Config { timeout: Duration::from_secs(1) };
    config.set_timeout(Duration::from_secs(5));
    assert_eq!(config.timeout(), Duration::from_secs(5));
}
```

Consuming builder methods commonly use the bare property name (`timeout(...)`) because they are configuration operations rather than setters on an already-built value.

## Clippy

Clippy has lints such as `misnamed_getters` that can catch a getter returning the wrong field, but it does not generally enforce the API Guidelines' “omit `get_`” naming convention for you. This remains primarily an API-review convention.

## Practical Guidance

- Name ordinary property getters `name()`, `value()`, `first()`, etc.
- Name mutable counterparts `name_mut()`, `value_mut()`, `first_mut()`.
- Use plain `get()` when there is one obvious contained value or when the abstraction has an established checked/keyed access operation.
- Use `get_mut` / `_unchecked` families only when those operation families actually exist semantically.
- Name domain lookups for what they select (`current_config`, `user_by_id`) instead of blindly prefixing `get_`.
- Distinguish getters from representation conversions such as `as_` / `into_`.

## See Also

- [name-is-has-bool](./name-is-has-bool.md) - Predicate naming
- [name-funcs-snake](./name-funcs-snake.md) - Function naming
- [api-builder-pattern](./api-builder-pattern.md) - Builder pattern
- [name-into-ownership](./name-into-ownership.md) - Consuming conversions
