# test-insta-snapshot

> Use `insta` for snapshot/approval testing

## Why It Matters

Snapshot testing compares output against a stored reference ("snapshot"). When the output changes intentionally, you review and update the snapshot. This is ideal for serialization, rendering, complex assertion outputs, and regression prevention. `insta` (72M+ downloads, v1.48.0) is the standard Rust snapshot testing crate with inline snapshots, review workflow, and CI integration.

## Setup

```toml
# Cargo.toml
[dev-dependencies]
insta = "1.48"
```

```bash
# Install the companion CLI
cargo install cargo-insta
```

## Basic Snapshot Test

```rust
use insta::assert_snapshot;

#[test]
fn test_serialize_user() {
    let user = User {
        id: 1,
        name: "Alice".into(),
        email: "alice@example.com".into(),
    };
    let json = serde_json::to_string_pretty(&user).unwrap();
    assert_snapshot!(json);
}
```

Run `cargo test` — the first run creates a snapshot file. Run `cargo insta review` to accept/reject pending snapshots.

## Inline Snapshots

```rust
use insta::assert_snapshot;

#[test]
fn test_greeting() {
    let greeting = format!("Hello, {}!", "World");
    // Stores the value inline in the source file
    assert_snapshot!(greeting, @"Hello, World!");
}
```

Inline snapshots are stored directly in the source code — no separate files needed.

## Debug Snapshots

```rust
use insta::assert_debug_snapshot;

#[test]
fn test_debug_output() {
    let data = complex_data_structure();
    // Uses Debug formatting
    assert_debug_snapshot!(data);
}

// With expressions
assert_debug_snapshot!(data, @r###"
User {
    id: 1,
    name: "Alice",
    address: Address {
        city: "Berlin",
    },
}
"###);
```

## JSON Snapshots

```rust
use insta::assert_json_snapshot;

#[test]
fn test_json_output() {
    let response = api_response();
    // Serializes with serde, sorts keys for deterministic output
    assert_json_snapshot!(response);
}

// Scrub dynamic fields (IDs, timestamps)
assert_json_snapshot!(response, {
    ".id" => "[id]",
    ".created_at" => "[timestamp]",
});
```

## Snapshot Filters

```rust
use insta::{assert_snapshot, with_settings};

#[test]
fn test_with_dynamic_data() {
    let output = render_page(User { id: 42, name: "Alice".into() });

    with_settings!({
        filters => vec![
            (r"id: \d+", "id: [ID]"),
            (r"\d{4}-\d{2}-\d{2}", "[DATE]"),
        ],
    }, {
        assert_snapshot!(output);
    });
}
```

## Redactions

```rust
use insta::assert_json_snapshot;

#[test]
fn test_api_response() {
    let response = json!({
        "id": "a1b2c3",
        "name": "Alice",
        "created_at": "2026-06-27T12:00:00Z",
        "nested": {
            "token": "secret-123",
        }
    });

    // Replace dynamic values with stable placeholders
    assert_json_snapshot!(response, {
        ".id" => "[uuid]",
        ".created_at" => "[timestamp]",
        ".nested.token" => "[secret]",
    });
}
```

## Workflow

```bash
# Run tests — creates/updates pending snapshots
cargo test

# Review snapshots interactively
cargo insta review

# Accept all pending snapshots (CI)
cargo insta accept

# Reject all pending snapshots
cargo insta reject

# Show pending snapshot diff
cargo insta show
```

## CI Integration

```bash
# Fail CI on un-reviewed snapshots
cargo test
cargo insta test --accept  # Only if changes are intentional

# Or use --check to verify committed snapshots match
cargo insta test --check
```

## Limitations

```rust
// ❌ insta does NOT work in doctests (filesystem access conflicts)
/// ```should_panic
/// // insta::assert_snapshot!("test");  // Will fail!
/// ```
pub fn my_fn() {}

// ✅ Use regular asserts in doctests
/// ```
/// assert_eq!(format!("{:?}", data), "Data(42)");
/// ```
```

```bash
# For deterministic snapshot ordering in CI
cargo test -- --test-threads=1
```

## With cargo-nextest

```toml
# .config/nextest.toml
[store]
dir = "target/nextest"  # Separate from cargo test
```

```bash
cargo nextest run
cargo insta test --accept  # Review and accept after nextest run
```

## See Also

- [test-doctest-examples](./test-doctest-examples.md) — Doctest limitations with snapshots
- [test-nextest-workflow](./test-nextest-workflow.md) — Running snapshot tests with nextest
- [test-rstest-fixtures](./test-rstest-fixtures.md) — Parameterized tests and fixtures

## References

- [insta crate](https://crates.io/crates/insta) — v1.48.0
- [cargo-insta CLI](https://crates.io/crates/cargo-insta)
- [test-doctest-examples](./test-doctest-examples.md) — Doctest limitations
- [test-nextest-workflow](./test-nextest-workflow.md) — Running with nextest
