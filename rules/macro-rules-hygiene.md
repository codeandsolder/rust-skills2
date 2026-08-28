# macro-rules-hygiene

> Understand `macro_rules!` mixed-site hygiene and use `$crate` for defining-crate paths

## Why It Matters

`macro_rules!` does not use one simple “definition-site” or “call-site” rule for every name. It has **mixed-site hygiene**:

- loop labels, block labels, and local variables are looked up at the macro definition site;
- most other symbols are looked up at the macro invocation site;
- metavariables such as `$name:ident` deliberately carry syntax supplied by the caller;
- `$crate` is the special way for a declarative macro to refer to the crate that defined it.

That last point is essential for exported macros. A path beginning with `crate::` is interpreted in the crate containing the expansion, so exported code that intends to call back into its defining crate should use `$crate::...` instead.

## Bad: `crate::` in an Exported Macro

This example compiles while used inside its own crate, which is exactly why the bug is easy to miss. If another crate invokes `log!`, `crate::log_value` refers to the **consumer crate**, not the crate that defined the macro.

<!-- rust-check: compile -->
```rust
pub fn log_value(value: &str) {
    println!("[log] {value}");
}

#[macro_export]
macro_rules! log {
    ($value:expr) => {
        crate::log_value(&format!("{:?}", $value))
    };
}

fn main() {
    log!(42);
}
```

## Good: `$crate` for Defining-Crate Items

<!-- rust-check: compile -->
```rust
#[doc(hidden)]
pub fn log_value(value: &str) {
    println!("[log] {value}");
}

#[macro_export]
macro_rules! log {
    ($value:expr) => {
        $crate::log_value(&format!("{:?}", $value))
    };
}

mod consumer_like_scope {
    use crate::log;

    pub fn run() {
        log!(42);
    }
}

fn main() {
    consumer_like_scope::run();
}
```

A downstream crate would import `mylib::log` instead of `crate::log`, but `$crate::log_value` inside the expansion still resolves to `mylib`.

## Mixed-Site Lookup

The Reference’s distinction is observable: a local variable in the macro body is resolved from the definition site, while an ordinary function name is resolved from the invocation site.

<!-- rust-check: compile -->
```rust
fn main() {
    let x = 1;

    macro_rules! check {
        () => {
            assert_eq!(x, 1); // local variable from the definition site
            helper();         // ordinary item from the invocation site
        };
    }

    {
        let x = 2;
        fn helper() {}
        check!();
        assert_eq!(x, 2);
    }
}
```

Locals introduced by separate macro expansions are not a shared hidden namespace. A binding emitted by one invocation cannot be referred to by another invocation merely because the token spelling matches.

## Caller-Supplied Identifiers

Metavariables are different from identifiers written literally inside the transcriber. When the caller supplies an identifier, the macro is intentionally operating on that caller-selected name:

<!-- rust-check: compile -->
```rust
macro_rules! make_and_read {
    ($name:ident, $value:expr) => {{
        let $name = $value;
        $name
    }};
}

fn main() {
    let answer = make_and_read!(temporary, 42);
    assert_eq!(answer, 42);
}
```

Do not describe this as “hygiene failing”; caller-provided syntax is part of the macro interface.

## `$crate` Does Not Bypass Visibility

`$crate` fixes **which crate** a path names. It does not make a private item externally accessible. If an exported macro expands to a non-macro helper used from downstream code, that helper must still have visibility compatible with the expansion site.

A common pattern is:

<!-- rust-check: compile -->
```rust
#[doc(hidden)]
pub mod __private {
    pub fn helper(value: u32) -> u32 {
        value + 1
    }
}

#[macro_export]
macro_rules! increment {
    ($value:expr) => {
        $crate::__private::helper($value)
    };
}

fn main() {
    assert_eq!(increment!(41), 42);
}
```

`#[doc(hidden)]` affects normal rustdoc presentation; it does not make the helper private or remove it from the compatibility surface.

## Key Points

- `macro_rules!` uses mixed-site hygiene, not one universal lookup rule.
- Use `$crate::...` for paths back into the crate defining an exported declarative macro.
- Do not use `crate::...` for those defining-crate paths in macros intended for downstream use.
- Metavariables deliberately refer to syntax supplied by the caller.
- Separate macro invocations do not share expansion-created local bindings.
- `$crate` does not bypass visibility checks.

## See Also

- [macro-export-crate-path](macro-export-crate-path.md) - public declarative macro paths
- [macro-private-helpers](macro-private-helpers.md) - helper APIs used by expansions
- [macro-prefer-functions](macro-prefer-functions.md) - when a macro is unnecessary
