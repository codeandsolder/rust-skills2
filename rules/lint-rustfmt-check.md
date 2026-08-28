# lint-rustfmt-check

**Rule**: `lint-rustfmt-check`

> Run cargo fmt --check in CI

## Why It Matters

Consistent formatting eliminates style debates and makes diffs cleaner. Running `cargo fmt --check` in CI ensures all code follows the same format. This catches formatting issues before merge, not after.

## CI Configuration

### GitHub Actions

```yaml
name: CI

on: [push, pull_request]

jobs:
  fmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt
      - run: cargo fmt --all --check
```

### GitLab CI

```yaml
fmt:
  image: rust:latest
  script:
    - rustup component add rustfmt
    - cargo fmt --all --check
```

## Mutating Formatters and Generators

Prefer a tool's non-mutating check mode when it has one. If a formatter or source generator only has a mutating mode, a zero exit status proves only that the command ran successfully. CI must also prove that running the tool did not change the checked-in source contract.

For tools that should only rewrite already tracked files, run the tool and then inspect the diff:

```yaml
- name: Check generated formatting
  run: |
    custom-formatter .
    git diff --exit-code
```

This catches the false-green case where the formatter repairs bad input in the CI checkout and exits successfully, leaving CI green even though the committed source was stale.

`git diff --exit-code` does not report newly-created untracked files. If the tool is also allowed to create files whose presence is part of the repository contract, check the complete worktree state instead:

```bash
custom-generator

test -z "$(git status --porcelain --untracked-files=all)"
```

Scope the check to the files the tool owns when unrelated generated or runtime files are expected. The invariant is not "the command exited zero"; it is "running the canonical formatter/generator leaves the repository in the expected state."

## Pre-commit Hook

```bash
#!/bin/sh
# .git/hooks/pre-commit
cargo fmt --all --check
```

## Configuration

Create `rustfmt.toml` for custom settings:

```toml
# rustfmt.toml
edition = "2024"
max_width = 100
use_small_heuristics = "Max"
imports_granularity = "Module"    # Stable since rustfmt 1.72
# group_imports = "StdExternalCrate"  # Unstable; requires nightly + unstable_features
reorder_imports = true
```

## Common Options

| Option | Default | Description |
|--------|---------|-------------|
| `max_width` | 100 | Maximum line width |
| `tab_spaces` | 4 | Spaces per indent |
| `edition` | "2024" | Rust edition (use workspace default) |
| `use_small_heuristics` | "Default" | Layout heuristics |
| `imports_granularity` | "Preserve" | Import grouping |
| `group_imports` | "Preserve" | Import ordering |

## Running Locally

```bash
# Check formatting (doesn't modify files)
cargo fmt --all --check

# Apply formatting
cargo fmt --all

# Format specific file
cargo fmt -- src/main.rs

# Check with verbose output
cargo fmt --all --check -- --verbose
```

## Workspace Formatting

```bash
# Format all workspace members
cargo fmt --all

# Format specific package
cargo fmt -p my-package
```

## Ignoring Files

In `rustfmt.toml`:

```toml
# Skip generated files
ignore = [
    "src/generated/*",
    "build.rs",
]
```

Or in code:

```rust
#[rustfmt::skip]
mod generated_code;

#[rustfmt::skip]
const MATRIX: [[i32; 4]; 4] = [
    [1, 0, 0, 0],
    [0, 1, 0, 0],
    [0, 0, 1, 0],
    [0, 0, 0, 1],
];
```

## Nightly Features

Some options still require nightly:

```toml
# rustfmt.toml (nightly only)
unstable_features = true
imports_granularity = "Crate"  # "Module" is stable, "Crate" is nightly
group_imports = "StdExternalCrate"  # Unstable; requires nightly + unstable_features
wrap_comments = true
format_code_in_doc_comments = true
```

```bash
# Use nightly rustfmt
cargo +nightly fmt
```

> Note: `imports_granularity = "Module"` has been stable since rustfmt 1.72 (bundled with Rust 1.72+). Only `"Crate"` and `"Item"` levels require nightly. `group_imports` (any value other than the default `"Preserve"`) is also unstable and requires nightly + `unstable_features = true`.

## IDE Integration

Most IDEs format on save. Configure to use project `rustfmt.toml`:

```json
// VS Code settings.json
{
  "rust-analyzer.rustfmt.extraArgs": ["--config-path", "./rustfmt.toml"]
}
```

## See Also

- [lint-warn-style](./lint-warn-style.md) - Style lints
- [lint-pedantic-selective](./lint-pedantic-selective.md) - Pedantic lints
- [name-funcs-snake](./name-funcs-snake.md) - Naming conventions
