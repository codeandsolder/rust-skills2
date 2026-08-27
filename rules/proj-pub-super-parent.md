# proj-pub-super-parent

> Use `pub(super)` when an item declared in a child module must be visible in its parent module scope

## Why It Matters

`pub(super)` is shorthand for `pub(in super)`: it raises an item's visibility to the item's **parent module**. It is useful when a child module owns an implementation detail that its parent or sibling modules need, while the rest of the crate should not see it.

Do not use `pub(super)` on an item merely so that the item's own child modules can access it. Ordinary private items are already visible to the module that defines them and its descendants.

## Bad

```rust
mod parser {
    // This is broader than necessary if Token is only an implementation
    // detail used by parser and parser's descendants: private would suffice.
    pub(super) struct Token(u8);

    mod lexer {
        fn use_token(token: super::Token) -> u8 {
            token.0
        }
    }
}

fn main() {}
```

Because `Token` is declared in `parser`, `pub(super)` makes it visible in `parser`'s parent scope. The nested `lexer` module did not require that visibility increase.

## Good

```rust
mod parser {
    // Parent-owned implementation details can stay private; descendants may
    // use private items defined by their ancestors.
    struct Token(u8);

    mod lexer {
        // This item is declared in the child module. pub(super) exposes it to
        // the parser module's scope, which also makes it usable by siblings.
        pub(super) fn scan_one() -> super::Token {
            super::Token(7)
        }
    }

    mod ast {
        pub(super) fn parse_tag() -> u8 {
            super::lexer::scan_one().0
        }
    }

    pub fn parse_tag() -> u8 {
        ast::parse_tag()
    }
}

fn main() {
    assert_eq!(parser::parse_tag(), 7);
}
```

Here `scan_one` stays hidden from the crate root, but code within the `parser` scope can use it. `Token` needs no visibility modifier because it is defined by the ancestor module whose descendants consume it.

## Choosing a Visibility

| Form | Meaning |
|---|---|
| private | visible in the current module and its descendants |
| `pub(super)` | visible within the parent module's scope |
| `pub(crate)` | visible throughout the current crate |
| `pub(in crate::path)` | visible within a specified ancestor-module scope |
| `pub` | potentially reachable outside the crate, subject to the enclosing path's visibility |

Visibility restrictions can only name ancestor scopes. If several sibling modules need a shared abstraction, consider whether that abstraction belongs in their parent module rather than automatically widening a child item's visibility.

## `pub(super)` for Test Helpers

The same rule applies in test module trees. A helper declared inside a nested test module can use `pub(super)` if its parent test scope needs it. But a helper declared by the parent is already visible to its private child test modules.

```rust
#[cfg(test)]
mod tests {
    mod fixtures {
        pub(super) fn sample_id() -> u64 {
            42
        }
    }

    #[test]
    fn uses_fixture() {
        assert_eq!(fixtures::sample_id(), 42);
    }
}

fn main() {}
```

## See Also

- [proj-pub-crate-internal](./proj-pub-crate-internal.md) - Crate visibility
- [proj-pub-use-reexport](./proj-pub-use-reexport.md) - Re-export patterns
- [proj-mod-by-feature](./proj-mod-by-feature.md) - Feature organization
