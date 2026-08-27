# mem-write-over-format

> Write formatting directly into the real destination when an intermediate owned `String` would only be copied elsewhere

## Why It Matters

`format!(...)` creates an owned `String`. That is exactly right when the desired result is a new string. It is avoidable overhead when the program already has a reusable `String`, byte buffer, file, socket, or another formatting-aware destination.

`write!` and `writeln!` let the formatting machinery target that destination directly. This can reduce temporary allocations and copies, but it does not make formatting itself free and it is not automatically faster for every workload.

## Build One `String` In Place

```rust
use std::fmt::Write as _;

struct Item<'a> {
    name: &'a str,
    value: u32,
}

fn build_response(items: &[Item<'_>]) -> String {
    let mut output = String::new();

    for item in items {
        writeln!(&mut output, "{}: {}", item.name, item.value).unwrap();
    }

    output
}

fn main() {
    let items = [
        Item { name: "a", value: 1 },
        Item { name: "b", value: 2 },
    ];
    assert_eq!(build_response(&items), "a: 1\nb: 2\n");
}
```

This avoids constructing a temporary `String` for every item and then appending it to another `String`.

If you have a useful capacity estimate, reserve it; do not invent an arbitrary multiplier such as `items.len() * 64` and assume that is always beneficial.

## Write Directly to an I/O Destination

`std::io::Write` is the corresponding interface for byte-oriented sinks:

```rust
use std::io::{self, Write};

struct Event<'a> {
    timestamp: u64,
    level: &'a str,
    message: &'a str,
}

fn write_event(output: &mut impl Write, event: &Event<'_>) -> io::Result<()> {
    writeln!(
        output,
        "[{}] {}: {}",
        event.timestamp,
        event.level,
        event.message,
    )
}

fn main() -> io::Result<()> {
    let event = Event {
        timestamp: 123,
        level: "INFO",
        message: "ready",
    };
    let mut bytes = Vec::new();
    write_event(&mut bytes, &event)?;
    assert_eq!(bytes, b"[123] INFO: ready\n");
    Ok(())
}
```

For files, sockets, buffered writers, and other fallible sinks, propagate the `io::Result` rather than unwrapping in library code.

## `std::fmt::Write` and `std::io::Write` Are Different Traits

```rust
use std::fmt::Write as FmtWrite;
use std::io::Write as IoWrite;

fn main() {
    let mut text = String::new();
    FmtWrite::write_fmt(&mut text, format_args!("value={}", 7)).unwrap();
    assert_eq!(text, "value=7");

    let mut bytes = Vec::<u8>::new();
    IoWrite::write_fmt(&mut bytes, format_args!("value={}", 7)).unwrap();
    assert_eq!(bytes, b"value=7");
}
```

Usually importing the relevant trait and using `write!`/`writeln!` is clearer. Alias imports when both traits are needed in the same scope.

A `String`'s formatting sink is effectively infallible for ordinary formatting, but the trait still returns `fmt::Result`. General I/O writers can genuinely fail.

## Reuse a Formatting Buffer Across Calls

When a produced string is consumed before the next iteration, clearing and reusing one buffer can reduce allocator traffic:

```rust
use std::fmt::Write as _;

struct Formatter {
    buffer: String,
}

impl Formatter {
    fn new() -> Self {
        Self {
            buffer: String::with_capacity(128),
        }
    }

    fn render<'a>(&'a mut self, code: u32, message: &str) -> &'a str {
        self.buffer.clear();
        write!(&mut self.buffer, "[{code}] {message}").unwrap();
        &self.buffer
    }
}

fn main() {
    let mut formatter = Formatter::new();
    assert_eq!(formatter.render(200, "ok"), "[200] ok");
    assert_eq!(formatter.render(404, "missing"), "[404] missing");
}
```

The returned `&str` borrows the formatter, so it cannot remain live across a later mutable reuse of the same buffer. If callers need to retain each result independently, they need owned storage and the reuse pattern may no longer fit.

## Prefer `writeln!` for Line Semantics

```rust
use std::fmt::Write as _;

fn main() {
    let mut output = String::new();
    writeln!(&mut output, "first").unwrap();
    writeln!(&mut output, "second").unwrap();
    assert_eq!(output, "first\nsecond\n");
}
```

This makes the trailing-newline behavior explicit and avoids manually embedding `\n` in every format string.

## When `format!` Is Exactly Right

If the API needs a new owned string, use `format!`:

```rust
struct Item<'a> {
    name: &'a str,
    value: u32,
}

fn describe(item: &Item<'_>) -> String {
    format!("{}: {}", item.name, item.value)
}

fn main() {
    let item = Item { name: "port", value: 8080 };
    assert_eq!(describe(&item), "port: 8080");
}
```

Do not replace this with a reusable-buffer abstraction unless measurements show that repeated allocation is important and the ownership/lifetime contract can support reuse.

Likewise, logging APIs often accept formatting arguments directly, so avoid allocating first:

```rust
fn main() {
    let port = 8080;
    println!("starting on port {port}");
}
```

## Avoid Double Formatting

This allocates an intermediate string only to format it again:

```rust
fn main() {
    let value = 42;
    println!("{}", format!("value={value}"));
}
```

Prefer:

```rust
fn main() {
    let value = 42;
    println!("value={value}");
}
```

## Benchmark Allocations, Not Folklore

Do not quote fixed numbers such as “`format!` takes 500 ns and reused `write!` takes 50 ns.” Formatting cost depends on arguments, destination capacity, allocator, target, compiler settings, and whether output dominates the workload.

If this optimization matters, compare representative variants and measure:

- allocations and allocated bytes;
- throughput or latency;
- buffer growth/capacity behavior;
- downstream I/O cost.

In I/O-heavy code, system calls or flushing can dwarf formatting allocation differences; a `BufWriter` may matter more than replacing one `format!`.

## Practical Guidance

- Use `format!` when you need a new owned formatted `String`.
- Use `write!`/`writeln!` when the destination already exists.
- Import `std::fmt::Write` for strings and `std::io::Write` for byte/I/O sinks.
- Propagate errors for genuinely fallible I/O destinations.
- Reuse a cleared buffer only when callers do not need previous results to remain independently owned.
- Reserve capacity from a defensible estimate, not a magic constant.
- Measure allocator and end-to-end effects instead of assuming a fixed speedup.

## See Also

- [mem-avoid-format](./mem-avoid-format.md) - Avoiding unnecessary intermediate formatting
- [mem-reuse-collections](./mem-reuse-collections.md) - Reusing buffers and collections
- [mem-with-capacity](./mem-with-capacity.md) - Capacity planning
- [perf-profile-first](./perf-profile-first.md) - Measure before optimizing
