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
imports_granularity = "Module"    # Works on stable rustfmt 1.11 (Rust 1.100)
group_imports = "StdExternalCrate"  # Works on stable rustfmt 1.11
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

## Toolchain-Specific Options

The following options were exercised on **stable rustfmt 1.11.0** bundled
with Rust 1.100.0. Import grouping and granularity (including `Crate` and
`Item`) no longer require nightly on this baseline; comment wrapping is also
available.

```toml
imports_granularity = "Crate"
group_imports = "StdExternalCrate"
wrap_comments = true
```

Do not infer that every rustfmt option works on an older stable toolchain or
that every future formatter option is stable. Check the actual formatter's
version and test options on representative input. Use `cargo +nightly fmt`
when the project requires nightly syntax or formatting options, and pin a
date when reproducible output is required.

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
