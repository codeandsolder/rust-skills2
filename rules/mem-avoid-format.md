# mem-avoid-format

> Avoid `format!()` when string literals work

## Why It Matters

`format!()` always allocates a new String, even for constant text. In hot paths, these allocations add up. Use string literals, `write!()`, or pre-allocated buffers instead. For clone-heavy workloads, `EcoString` (from `ecow` 0.3.0) makes `clone()` O(1), reducing the cost of defensive copies.

## Bad

```rust
// Allocates every time, even for static text
fn get_error_message() -> String {
    format!("An error occurred")  // Unnecessary allocation!
}

// Allocates in a loop
for item in items {
    log::info!("{}", format!("Processing item: {}", item));  // Double work!
}

// format! in hot path
fn classify(n: i32) -> String {
    if n > 0 {
        format!("positive")  // Allocates!
    } else if n < 0 {
        format!("negative")  // Allocates!
    } else {
        format!("zero")      // Allocates!
    }
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
// Return &'static str for constants
fn get_error_message() -> &'static str {
    "An error occurred"  // No allocation
}

// Use format args directly
for item in items {
    log::info!("Processing item: {}", item);  // No intermediate String
}

// Return Cow for mixed static/dynamic
use std::borrow::Cow;

fn classify(n: i32) -> Cow<'static, str> {
    if n > 0 {
        Cow::Borrowed("positive")  // No allocation
    } else if n < 0 {
        Cow::Borrowed("negative")  // No allocation
    } else {
        Cow::Borrowed("zero")      // No allocation
    }
}

// Or just &'static str if always static
fn classify_str(n: i32) -> &'static str {
    if n > 0 { "positive" }
    else if n < 0 { "negative" }
    else { "zero" }
}
```

## Use write!() for Output

```rust
use std::io::Write;

// Bad: Allocate then write
fn bad_log(writer: &mut impl Write, msg: &str, code: u32) {
    let formatted = format!("[ERROR {}] {}", code, msg);  // Allocation!
    writer.write_all(formatted.as_bytes()).unwrap();
}

// Good: Write directly
fn good_log(writer: &mut impl Write, msg: &str, code: u32) {
    write!(writer, "[ERROR {}] {}", code, msg).unwrap();  // No allocation!
}
```

## Pre-allocate for Multiple Appends

```rust
// Bad: Multiple allocations
fn build_message(parts: &[&str]) -> String {
    let mut result = String::new();
    for part in parts {
        result = format!("{}{}\n", result, part);  // Allocates each iteration!
    }
    result
}

// Good: Pre-allocate
fn build_message(parts: &[&str]) -> String {
    let total_len: usize = parts.iter().map(|p| p.len() + 1).sum();
    let mut result = String::with_capacity(total_len);
    for part in parts {
        result.push_str(part);
        result.push('\n');
    }
    result
}

// Good: Use join
fn build_message(parts: &[&str]) -> String {
    parts.join("\n")
}
```

## CompactString for Small Strings

```rust
use compact_str::{CompactString, ToCompactString, format_compact};

// Stack-allocated for strings <= 24 bytes (compact_str 0.9.0+ branchless)
fn format_code(code: u32) -> CompactString {
    format_compact!("ERR-{:04}", code)
    // Stack-allocated if result is small enough
}

// ToCompactString trait for any Display type
let s: CompactString = 42.to_compact_string();
let t: CompactString = format_compact!("value: {}", 42);
```

## EcoString for Clone-Heavy Workloads

```rust
use ecow::EcoString;

// 16 bytes, O(1) clone — ideal for caches, templates, shared config
fn build_template(values: &[&str]) -> Vec<EcoString> {
    values.iter().map(|&v| EcoString::from(v)).collect()
}

fn process(items: Vec<EcoString>) {
    for item in &items {
        let cloned = item.clone();  // O(1) — just bump refcount
        spawn_worker(cloned);
    }
}
```

## When format!() Is Fine

```rust
// Rare/cold paths - clarity over micro-optimization
fn log_startup_message() {
    println!("{}", format!("Starting {} v{}", APP_NAME, VERSION));
}

// When you need an owned String anyway
fn create_user_greeting(name: &str) -> String {
    format!("Hello, {}!", name)  // Need owned String
}

// Error messages (already on error path)
return Err(format!("Invalid value: {}", value).into());
```

## See Also

- [mem-write-over-format](mem-write-over-format.md) - Use write!() instead of format!()
- [mem-with-capacity](mem-with-capacity.md) - Pre-allocate strings
- [mem-compact-string](mem-compact-string.md) — Compact string alternatives
- [mem-ecow-clone-heavy](mem-ecow-clone-heavy.md) — EcoString for clone-heavy workloads
- [own-cow-conditional](own-cow-conditional.md) - Use Cow for mixed static/dynamic
