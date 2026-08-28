# test-snapshot-testing

> Use snapshot tests for complex output that humans should review as a whole

## Why It Matters

Large structured output—rendered diagnostics, pretty-printed state, generated code, CLI output, or serialized documents—can be awkward to maintain as long hand-written literals. Snapshot testing stores the approved output separately and presents diffs when it changes.

The value is reviewability, not avoiding assertions. A snapshot is still a test oracle and should represent output that the project intentionally wants to keep stable enough to review.

## Bad: Large Inline Golden String

<!-- rust-check: compile -->
```rust
#[derive(Debug)]
struct AppError {
    id: u64,
}

fn render(error: &AppError) -> String {
    format!("resource {} was not found", error.id)
}

fn main() {
    let error = AppError { id: 42 };
    assert_eq!(render(&error), "resource 42 was not found");
}
```

For a tiny value this is perfectly fine. The pattern becomes painful when the expected value is large, multi-line, or structurally rich.

## Good: Snapshot Structured Output

`insta` is already sufficient for debug/string snapshots without extra serialization features:

```toml
[dev-dependencies]
insta = "1"
```

<!-- rust-check: compile -->
```rust
use insta::assert_debug_snapshot;

#[derive(Debug)]
enum AppError {
    NotFound { id: u64 },
}

#[derive(Debug, Default)]
struct Config {
    timeout_secs: u64,
    retries: u8,
}

#[test]
fn render_error() {
    let error = AppError::NotFound { id: 42 };
    assert_debug_snapshot!(error);
}

#[test]
fn default_config() {
    let config = Config {
        timeout_secs: 30,
        retries: 3,
    };
    assert_debug_snapshot!("default_config", config);
}

fn main() {}
```

Feature-specific macros such as JSON/YAML snapshots require the corresponding insta feature in the project that uses them:

```toml
[dev-dependencies]
insta = { version = "1", features = ["json", "yaml"] }
```

Do not add serialization features merely to snapshot a type that already has a useful `Debug` or textual representation.

## Local Review Workflow

With insta's normal local update behavior, a new or changed snapshot is written as a pending `.snap.new` file rather than silently replacing the approved `.snap` file.

A typical workflow is:

1. Run the tests.
2. Inspect pending snapshot diffs.
3. Accept or reject them with `cargo insta review` (or another deliberate review workflow).
4. Commit the approved `.snap` files with the code change.

`cargo-insta` is the optional CLI that provides the interactive review command.

## CI Must Not Auto-Accept Changes

Insta's default `auto` update mode behaves conservatively in detected CI: unapproved snapshots fail instead of being accepted. You can make the policy explicit with:

```bash
INSTA_UPDATE=no cargo test
```

When using `cargo-insta`, `cargo insta test --check` is another explicit checking workflow.

Do **not** recommend `INSTA_UPDATE=unseen` as strict CI mode. `unseen` is an update mode that permits creating snapshots that do not yet exist; it is therefore the opposite of “fail on any new snapshot.”

## Normalize Nondeterminism

Snapshots become noisy when they contain timestamps, random IDs, temporary paths, unordered output, machine-specific addresses, or other values that are irrelevant to the contract.

Prefer deterministic producers when practical. Otherwise use insta redactions or normalize the value before snapshotting so reviewers see meaningful changes rather than churn.

<!-- rust-check: compile -->
```rust
use insta::assert_debug_snapshot;

#[derive(Debug)]
struct JobSummary {
    id: &'static str,
    state: &'static str,
}

fn stable_summary(_runtime_id: u128) -> JobSummary {
    JobSummary {
        id: "<job-id>",
        state: "complete",
    }
}

#[test]
fn job_summary() {
    assert_debug_snapshot!(stable_summary(123456));
}

fn main() {}
```

## Snapshots vs Direct Assertions

| Situation | Prefer |
|---|---|
| Short scalar / exact semantic value | `assert_eq!` / focused assertion |
| Large multi-line output humans review holistically | snapshot |
| Structured debug representation | `assert_debug_snapshot!` |
| JSON/YAML contract and feature enabled | format-specific snapshot macro |
| Critical individual invariants inside a large object | focused assertions, possibly alongside a snapshot |
| Highly nondeterministic output with no useful normalization | usually not a snapshot |

A snapshot does not replace property tests or focused assertions when those express the real invariant more precisely.

## Snapshot Stability Is an API Choice

Snapshots make changes visible, but they can also accidentally freeze irrelevant formatting. Before snapshotting, ask whether reviewers should care when that output changes.

Good snapshot targets are outputs whose whole representation is intentionally reviewable: user-facing diagnostics, code generation, protocol fixtures, formatted reports, or stable serialized forms.

## See Also

- [test-arrange-act-assert](test-arrange-act-assert.md) - test structure
- [test-proptest-properties](test-proptest-properties.md) - property-based testing
- [test-doctest-examples](test-doctest-examples.md) - executable documentation
