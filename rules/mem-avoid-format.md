# mem-avoid-format

> Avoid creating an intermediate `String` with `format!` when the caller can use a literal, formatting arguments, or an existing output buffer directly

## Why It Matters

`format!(...)` produces an owned `String`. That is exactly right when you need an owned formatted string. It is unnecessary when the surrounding API can consume a string literal or formatting arguments directly, or when you already have a reusable destination buffer.

The optimization target is the **intermediate owned string**, not formatting syntax itself. Do not replace clear one-off `format!` calls with complicated machinery unless allocation actually matters.

## Static Text: Borrow It When Ownership Is Unnecessary

If every result is static text, return a static string instead of allocating an owned `String`:

```rust
fn classification(value: i32) -> &'static str {
    if value > 0 {
        "positive"
    } else if value < 0 {
        "negative"
    } else {
        "zero"
    }
}

fn main() {
    assert_eq!(classification(-1), "negative");
}
```

If the API requires ownership, an owned string is still required. Changing `format!("positive")` to `"positive".to_owned()` removes formatting overhead but does not remove the allocation required by the return type.

## Pass Formatting Arguments Directly to Formatting-Aware APIs

Logging and printing macros already accept formatting arguments:

```rust
fn main() {
    let item = 7;
    println!("processing item: {item}");
}
```

Avoid this intermediate allocation:

```rust
fn main() {
    let item = 7;
    println!("{}", format!("processing item: {item}"));
}
```

The direct form is both clearer and avoids constructing a temporary `String` solely to format it again.

## Write Into an Existing `String`

When building one output incrementally, reuse the same destination:

```rust
use std::fmt::Write as _;

fn build_message(parts: &[&str]) -> String {
    let capacity: usize = parts.iter().map(|part| part.len() + 1).sum();
    let mut output = String::with_capacity(capacity);

    for part in parts {
        writeln!(&mut output, "{part}").unwrap();
    }

    output
}

fn main() {
    assert_eq!(build_message(&["a", "bb"]), "a\nbb\n");
}
```

The estimated capacity is exact for this specific byte-oriented construction because `str::len()` is a byte length and `\n` is one byte. In less predictable formatting code, reserve only when you have a useful estimate; a bad capacity guess is not automatically better than growing normally.

## `join` Is Not Always Equivalent

For separators **between** items, `join` is concise:

```rust
fn join_lines(parts: &[&str]) -> String {
    parts.join("\n")
}

fn main() {
    assert_eq!(join_lines(&["a", "b"]), "a\nb");
}
```

This deliberately has no trailing newline. It is not equivalent to a loop that appends `\n` after every element. Choose the semantics you actually need.

## Write Directly to an I/O Sink

If the final destination implements `std::io::Write`, avoid formatting into a temporary `String` first:

```rust
use std::io::{self, Write};

fn write_record(output: &mut impl Write, code: u32, message: &str) -> io::Result<()> {
    writeln!(output, "[{code}] {message}")
}

fn main() -> io::Result<()> {
    let mut bytes = Vec::new();
    write_record(&mut bytes, 404, "missing")?;
    assert_eq!(bytes, b"[404] missing\n");
    Ok(())
}
```

This lets the sink own buffering/error behavior instead of forcing an intermediate allocation.

## When `format!` Is the Right Tool

When an API needs an owned `String`, `format!` is direct and idiomatic:

```rust
fn greeting(name: &str) -> String {
    format!("hello, {name}!")
}

fn main() {
    assert_eq!(greeting("Ada"), "hello, Ada!");
}
```

There is no benefit in replacing this with a hand-managed buffer unless profiling shows repeated formatting into reused storage would matter.

Likewise, cold diagnostics and setup code usually favor clarity over allocation micro-optimization.

## Mixed Borrowed and Owned Results

`Cow<'static, str>` is useful when some branches are literals and others genuinely need owned formatting:

```rust
use std::borrow::Cow;

fn describe(value: i32) -> Cow<'static, str> {
    match value {
        0 => Cow::Borrowed("zero"),
        1 => Cow::Borrowed("one"),
        other => Cow::Owned(format!("value {other}")),
    }
}

fn main() {
    assert!(matches!(describe(0), Cow::Borrowed(_)));
    assert_eq!(describe(8), "value 8");
}
```

Do not introduce `Cow` when every branch is static or every branch is owned; use the simpler type.

## Compact String Types Are a Separate Decision

A compact-string crate can change the representation of an **owned** string, but it does not make unnecessary formatting disappear. Whether `CompactString`, `EcoString`, `SmartString`, `Box<str>`, or ordinary `String` is appropriate depends on string lengths, mutation/clone patterns, target layout, and interoperability. See [mem-compact-string](./mem-compact-string.md) rather than mixing that storage decision into every formatting rule.

## Practical Guidance

- Use `&'static str` or `&str` when ownership is not needed.
- Pass formatting arguments directly to logging/printing APIs.
- Use `write!`/`writeln!` when an existing `String` or I/O sink is the real destination.
- Remember that `join("\n")` omits a trailing newline.
- Use `format!` when an owned formatted `String` is exactly the desired result.
- Optimize repeated formatting only after measuring allocation or throughput pressure.

## See Also

- [mem-write-over-format](./mem-write-over-format.md) - Reusing formatting buffers
- [mem-with-capacity](./mem-with-capacity.md) - Reserving destination capacity
- [mem-compact-string](./mem-compact-string.md) - Alternative owned-string representations
- [own-cow-conditional](./own-cow-conditional.md) - Borrow-or-own return values
