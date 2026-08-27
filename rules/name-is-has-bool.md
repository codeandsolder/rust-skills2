# name-is-has-bool

> Name boolean methods as clear predicates; use `is_`, `has_`, `can_`, and similar prefixes when they match the question being answered

## Why It Matters

A boolean-returning API should read like a predicate at the call site. `is_empty()`, `has_permission()`, and `can_retry()` make their intent obvious, but Rust does **not** require every boolean method to begin with one of these prefixes. Standard APIs also use verbs and verb phrases such as `contains`, `starts_with`, `ends_with`, and `eq_ignore_ascii_case`.

Choose the name that describes the question naturally rather than mechanically adding `is_` to every `bool` return.

## State Predicates: `is_`

`is_` is a strong convention for state or property checks:

```rust
struct User {
    active: bool,
    admin: bool,
}

impl User {
    fn is_active(&self) -> bool {
        self.active
    }

    fn is_admin(&self) -> bool {
        self.admin
    }
}

fn main() {
    let user = User { active: true, admin: false };
    assert!(user.is_active());
    assert!(!user.is_admin());
}
```

## Possession and Capability

Use semantic prefixes when they genuinely fit the domain:

```rust
#[derive(Clone, Copy, PartialEq, Eq)]
enum Permission {
    Read,
    Write,
}

struct User {
    permissions: Vec<Permission>,
}

impl User {
    fn has_permission(&self, permission: Permission) -> bool {
        self.permissions.contains(&permission)
    }

    fn can_edit(&self) -> bool {
        self.has_permission(Permission::Write)
    }
}

fn main() {
    let user = User { permissions: vec![Permission::Read] };
    assert!(user.has_permission(Permission::Read));
    assert!(!user.can_edit());
}
```

`should_`, `needs_`, and `will_` can likewise be useful when they express policy, requirements, or predicted behavior, but they are domain vocabulary rather than mandated Rust prefixes.

## Boolean Methods Need Not Use a Prefix

Many good predicates are already verb phrases:

```rust
fn main() {
    let text = "hello.rs";
    assert!(text.contains("lo"));
    assert!(text.starts_with("he"));
    assert!(text.ends_with(".rs"));
    assert!("Rust".eq_ignore_ascii_case("rust"));
}
```

Names such as `is_contains`, `is_starts_with`, or `has_contains` would be worse.

## Standard-Library Predicate Shapes

Use real calls when learning the convention:

```rust
use std::path::Path;

fn main() {
    let values = Vec::<u8>::new();
    assert!(values.is_empty());

    let option = Some(42);
    assert!(option.is_some());
    assert!(!option.is_none());

    let result: Result<u32, &str> = Ok(42);
    assert!(result.is_ok());
    assert!(!result.is_err());

    assert!('a'.is_alphabetic());
    assert!("abc".is_ascii());

    let path = Path::new(".");
    let _is_file = path.is_file();
    let _is_dir = path.is_dir();
}
```

Do not invent nonexistent “conceptual standard-library examples” such as `iterator.has_next()` and present them as if they were APIs.

## Receiver Shape and `clippy::wrong_self_convention`

Clippy permits `is_*` methods with `&self`, `&mut self`, or no receiver. That is a receiver-shape rule, **not** an endorsement of surprising mutation inside a predicate.

A mutating predicate can be legitimate when checking requires advancing or normalizing state, but the side effect should be inherent and documented. Do not write an `is_empty(&mut self)` that secretly clears the collection merely because Clippy permits `&mut self`.

```rust
struct Cursor {
    remaining: usize,
}

impl Cursor {
    fn is_finished(&self) -> bool {
        self.remaining == 0
    }
}

fn main() {
    let cursor = Cursor { remaining: 0 };
    assert!(cursor.is_finished());
}
```

## Prefer Positive Predicates

Positive names compose better with caller-side negation:

```rust
struct Connection {
    active: bool,
}

impl Connection {
    fn is_active(&self) -> bool {
        self.active
    }
}

fn main() {
    let connection = Connection { active: false };
    if !connection.is_active() {
        // reconnect
    }
}
```

Avoid awkward names such as `is_not_active()` unless the negative state is genuinely a first-class domain concept. Established negative predicates like `is_empty()` or `is_none()` are perfectly idiomatic because “empty” and “none” are meaningful states in their own right.

## Boolean Fields Are Different

Fields do not need method-style predicate prefixes:

```rust
struct Config {
    enabled: bool,
    verbose: bool,
}

impl Config {
    fn is_enabled(&self) -> bool {
        self.enabled
    }
}

fn main() {
    let config = Config { enabled: true, verbose: false };
    assert!(config.is_enabled());
    assert!(!config.verbose);
}
```

## Practical Guidance

- Use `is_foo` for state/property predicates when it reads naturally.
- Use `has_foo`, `can_foo`, `should_foo`, or `needs_foo` only when those verbs match the domain meaning.
- Keep natural verb predicates such as `contains` and `starts_with` as verbs; do not prefix them mechanically.
- Prefer positive predicate names unless the negative condition is itself a meaningful state.
- Do not hide surprising side effects behind a predicate-sounding name.
- Treat Clippy's receiver convention as a syntactic convention, not a complete API-design rule.

## See Also

- [name-no-get-prefix](./name-no-get-prefix.md) - Getter naming
- [name-funcs-snake](./name-funcs-snake.md) - Function naming
- [api-must-use](./api-must-use.md) - Important return values
