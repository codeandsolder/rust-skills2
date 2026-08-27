# anti-format-hot-path

> Avoid unnecessary intermediate formatting allocations in measured hot paths; keep `format!` when a new owned `String` is the actual result you need

## Why It Matters

`format!(...)` constructs an owned `String`. That allocation is avoidable when formatted output is immediately copied into an existing `String`, byte buffer, logger, file, socket, or other sink. In a high-frequency path, eliminating those intermediates can reduce allocator and copy traffic.

But “never use `format!` in a hot path” is too broad. If the API fundamentally needs a new owned string, some owned storage is required. The relevant questions are:

- can formatting target the real destination directly?
- can an existing buffer be reused safely?
- can a logging/diagnostic API accept formatting arguments without first building a string?
- does profiling show formatting allocation is material at all?

## Build Into One Existing String

```rust
use std::fmt::Write as _;

struct Item<'a> {
    name: &'a str,
    value: u32,
}

fn build(items: &[Item<'_>]) -> String {
    let mut output = String::new();
    for item in items {
        writeln!(&mut output, "{}={}", item.name, item.value).unwrap();
    }
    output
}

fn main() {
    let items = [
        Item { name: "a", value: 1 },
        Item { name: "b", value: 2 },
    ];
    assert_eq!(build(&items), "a=1\nb=2\n");
}
```

This avoids creating one temporary `String` per item just to append it to another `String`.

## Reuse a Buffer When the Lifetime Contract Allows It

```rust
use std::fmt::Write as _;

struct Formatter {
    buffer: String,
}

impl Formatter {
    fn new() -> Self {
        Self { buffer: String::with_capacity(128) }
    }

    fn render<'a>(&'a mut self, level: &str, message: &str) -> &'a str {
        self.buffer.clear();
        write!(&mut self.buffer, "[{level}] {message}").unwrap();
        &self.buffer
    }
}

fn main() {
    let mut formatter = Formatter::new();
    assert_eq!(formatter.render("INFO", "ready"), "[INFO] ready");
    assert_eq!(formatter.render("WARN", "slow"), "[WARN] slow");
}
```

This works because callers consume each borrowed result before mutably reusing the formatter. If callers need to retain independent results, they need independent owned storage and this reuse contract no longer fits.

## Write Directly to I/O

```rust
use std::io::{self, Write};

fn write_event(output: &mut impl Write, id: u64, message: &str) -> io::Result<()> {
    writeln!(output, "[{id}] {message}")
}

fn main() -> io::Result<()> {
    let mut output = Vec::new();
    write_event(&mut output, 7, "ready")?;
    assert_eq!(output, b"[7] ready\n");
    Ok(())
}
```

For real I/O, buffering and syscall behavior may matter more than the formatting allocation itself. Measure end-to-end behavior rather than ranking formatting macros in isolation.

## Implement `Display` When the Value Has a Natural Text Representation

A `Display` implementation lets callers choose the final destination:

```rust
use std::fmt::{self, Write as _};

struct Event<'a> {
    level: &'a str,
    message: &'a str,
}

impl fmt::Display for Event<'_> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "[{}] {}", self.level, self.message)
    }
}

fn main() {
    let event = Event { level: "INFO", message: "ready" };

    let mut output = String::new();
    write!(&mut output, "{event}").unwrap();
    assert_eq!(output, "[INFO] ready");
}
```

This does not promise zero allocation in every caller; it simply avoids forcing the representation to be materialized as a `String` before the caller decides what to do with it.

## `format_args!` Is Borrowed Formatting State

`format_args!` produces `fmt::Arguments` without heap allocation. The value borrows its formatting arguments and, except for argument-free cases, may also borrow temporaries.

```rust
use std::fmt;

fn main() {
    let name = String::from("Ada");
    let args = format_args!("hello {name}");
    let rendered = fmt::format(args);
    assert_eq!(rendered, "hello Ada");
}
```

Current Rust extends relevant temporary lifetimes in some `let` initializer forms so an `Arguments` value like this can be stored locally, but it is still borrowed formatting state—not an owned deferred string you can freely move beyond the values it references.

This is useful for formatting-aware APIs that can consume `fmt::Arguments` directly.

## Logging Macros Can Avoid Eager String Construction

Prefer passing formatting arguments directly to a logging API instead of allocating first when the API supports it:

```rust
fn main() {
    let user_id = 42;
    log::info!("loaded user {user_id}");
}
```

Whether a particular logging implementation performs work before or after level filtering is crate-specific. Do not promise that every logging macro defers all formatting or allocation in every configuration.

## When `format!` Is Fine—even in Frequently Called Code

If the function's contract is to produce an owned `String`, `format!` is often the clearest implementation:

```rust
fn greeting(name: &str) -> String {
    format!("Hello, {name}!")
}

fn main() {
    assert_eq!(greeting("Ada"), "Hello, Ada!");
}
```

A frequently called function is not automatically an optimization problem. If profiling shows this allocation matters, consider whether callers can accept a destination buffer, `Display`, `fmt::Arguments`, a structured value, or another representation without making the API worse.

## Capacity Estimates Must Be Defensible

`String::with_capacity` can avoid growth reallocations when you have a useful bound or estimate. Avoid magic formulas like `params.len() * 20` unless the input format actually makes that estimate meaningful.

```rust
fn join_pair(left: &str, right: &str) -> String {
    let mut output = String::with_capacity(left.len() + 1 + right.len());
    output.push_str(left);
    output.push('/');
    output.push_str(right);
    output
}

fn main() {
    assert_eq!(join_pair("api", "users"), "api/users");
}
```

Here the capacity is exact because all appended byte lengths are known.

## Do Not Publish Universal Performance Rankings

Tables such as “`push_str` = fastest, reused `write!` = fast, `format!` = slow” are not portable performance facts. Results depend on format complexity, destination growth, optimizer, allocator, target, and surrounding work.

If formatting is hot enough to matter, benchmark representative operations and inspect allocation counts/bytes as well as wall-clock throughput.

## Practical Guidance

- Use `format!` when a new owned formatted `String` is the desired result.
- Use `write!`/`writeln!` when a destination buffer or I/O sink already exists.
- Reuse buffers only when result lifetimes/ownership make reuse possible.
- Implement `Display` for values with a natural textual representation so callers control allocation.
- Treat `format_args!` as borrowed formatting arguments, not owned storage.
- Pass formatting directly to logging APIs when supported instead of pre-building a `String`.
- Reserve capacity from meaningful bounds, not arbitrary constants.
- Profile before claiming a formatting optimization matters.

## See Also

- [mem-avoid-format](./mem-avoid-format.md) - Avoiding unnecessary intermediate strings
- [mem-write-over-format](./mem-write-over-format.md) - Writing into existing destinations
- [mem-reuse-collections](./mem-reuse-collections.md) - Buffer reuse
- [perf-profile-first](./perf-profile-first.md) - Measure before optimizing
