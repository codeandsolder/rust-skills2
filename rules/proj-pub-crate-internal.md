# proj-pub-crate-internal

> Use the narrowest visibility that matches the intended module boundary; use `pub(crate)` for APIs shared across the crate but not exposed downstream

## Why It Matters

Every `pub` item reachable from a public module can become part of the API downstream users depend on. `pub(crate)` keeps an item available throughout the current crate without making it externally nameable.

Do not replace all private items with `pub(crate)`. Plain private visibility is stronger encapsulation and is preferable when sibling modules do not need the item.

## Bad: Expose Implementation State Downstream

```rust
pub mod internal {
    pub struct InternalState {
        pub buffer: Vec<u8>,
        pub dirty: bool,
    }

    pub fn process_internal(state: &mut InternalState) {
        state.dirty = false;
    }
}

pub struct Widget {
    pub state: internal::InternalState,
}

fn main() {}
```

This makes the representation and internal operation externally reachable.

## Good: Keep the Support API Crate-Local

```rust
pub(crate) mod internal {
    pub(crate) struct InternalState {
        pub(crate) buffer: Vec<u8>,
        pub(crate) dirty: bool,
    }

    pub(crate) fn process_internal(state: &mut InternalState) {
        state.dirty = false;
    }
}

pub struct Widget {
    state: internal::InternalState,
}

impl Widget {
    pub fn new() -> Self {
        Self {
            state: internal::InternalState {
                buffer: Vec::new(),
                dirty: false,
            },
        }
    }

    pub fn do_something(&mut self) {
        internal::process_internal(&mut self.state);
    }
}

fn main() {
    let mut widget = Widget::new();
    widget.do_something();
}
```

## Visibility Levels

| Visibility | Accessible from |
|---|---|
| `pub` | Any crate that can reach the item through public modules/re-exports |
| `pub(crate)` | Anywhere in the current crate |
| `pub(super)` | The parent module and its descendants |
| `pub(in path)` | The specified ancestor module and its descendants |
| private | The current module and its descendants, subject to Rust's privacy rules |

Choose based on the boundary you actually need.

## Internal Modules Can Still Expose Crate-Local Items

```rust
mod internal {
    pub(crate) struct Helper;

    pub(crate) fn helper() -> Helper {
        Helper
    }
}

pub mod api {
    use crate::internal::{helper, Helper};

    pub struct PublicType {
        helper: Helper,
    }

    impl PublicType {
        pub fn new() -> Self {
            Self { helper: helper() }
        }
    }
}

fn main() {
    let _ = api::PublicType::new();
}
```

The module itself need not be `pub(crate)` merely because sibling code uses it; visibility from the crate root already allows descendants of the root to reach the private child according to Rust's privacy model. Use `pub(crate) mod ...` when that spelling communicates the intended boundary or when the module's placement makes the broader visibility necessary.

## Tests: Unit vs Integration Boundaries

Unit tests compiled inside the crate can test private implementation details from an appropriate descendant module. A `#[cfg(test)] pub(crate)` helper can be convenient when several in-crate test modules need the same access:

```rust
#[derive(Debug)]
struct ParserState {
    offset: usize,
}

pub struct Parser {
    state: ParserState,
}

impl Parser {
    pub fn new() -> Self {
        Self {
            state: ParserState { offset: 0 },
        }
    }

    #[cfg(test)]
    pub(crate) fn debug_state(&self) -> &ParserState {
        &self.state
    }
}

#[cfg(test)]
mod tests {
    use super::Parser;

    #[test]
    fn starts_at_zero() {
        assert_eq!(Parser::new().debug_state().offset, 0);
    }
}

fn main() {}
```

Cargo integration tests in `tests/` are separate crates, so they **cannot** access `pub(crate)` items. Prefer testing the public API there. If integration tooling genuinely needs a support interface, expose that interface deliberately (for example through a documented feature or dedicated test-support crate) rather than pretending `#[doc(hidden)] pub` is private.

## Feature Module Internals

```rust
mod user {
    mod repository {
        pub(crate) fn load_name() -> &'static str {
            "Ada"
        }
    }

    mod service {
        use super::repository;

        pub struct UserService;

        impl UserService {
            pub fn name(&self) -> &'static str {
                repository::load_name()
            }
        }
    }

    pub use self::service::UserService;
}

fn main() {
    let service = user::UserService;
    assert_eq!(service.name(), "Ada");
}
```

The feature exposes one public type while its repository implementation remains private to the feature/crate.

## See Also

- [proj-pub-super-parent](./proj-pub-super-parent.md) - Parent-only visibility
- [proj-pub-use-reexport](./proj-pub-use-reexport.md) - Curated re-exports
- [api-non-exhaustive](./api-non-exhaustive.md) - Evolving intentionally public types
