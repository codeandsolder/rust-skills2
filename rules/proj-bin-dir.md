# proj-bin-dir

> Use `src/bin/` for conventionally discovered additional binary targets

## Why It Matters

Cargo automatically discovers binary targets in `src/bin/`. For packages with several executables, this often avoids repetitive `[[bin]]` entries and makes the target boundaries obvious.

Explicit `[[bin]]` entries are still appropriate when you need a custom path, name, `required-features`, test/bench settings, or other target configuration.

## Conventional Layout

```text
my-project/
├── Cargo.toml
└── src/
    ├── lib.rs
    ├── main.rs          # optional package-default binary
    └── bin/
        ├── server.rs    # binary target `server`
        └── cli.rs       # binary target `cli`
```

Each top-level `.rs` file in `src/bin/` is inferred as a separate binary target named after the file stem. Cargo also supports directory-form targets such as `src/bin/server/main.rs`.

## Running Binaries

```bash
cargo run --bin server
cargo run --bin cli
cargo build --bin server
cargo build --bins
```

If several binaries exist and `cargo run` would be ambiguous, select one with `--bin` or configure `package.default-run`.

## Binary with Multiple Source Files

Use a directory when a binary has its own modules:

```text
src/
├── lib.rs
└── bin/
    ├── server/
    │   ├── main.rs
    │   ├── config.rs
    │   └── handlers.rs
    └── cli/
        ├── main.rs
        └── commands.rs
```

Only `main.rs` is the binary root in each directory; the neighboring files are ordinary modules included by that target.

## Shared Code Belongs in the Library Target

When multiple binaries share substantial logic, put that logic in `src/lib.rs` (or modules reachable from it) and keep binary roots thin:

```text
// src/lib.rs
pub mod config;
pub mod database;
pub mod models;

// src/bin/server.rs
use package_library::{config, database};

fn main() {
    let config = config::load();
    let _db = database::connect(&config);
}

// src/bin/cli.rs
use package_library::config;

fn main() {
    let _config = config::load();
}
```

This is deliberately a multi-file sketch rather than one Rust compilation unit. Replace `package_library` with the actual library target name; by default Cargo derives that name from the package name with dashes converted to underscores.

## Binary Naming

| File path | Inferred binary name |
|---|---|
| `src/main.rs` | package name by default |
| `src/bin/server.rs` | `server` |
| `src/bin/my-cli.rs` | `my-cli` |
| `src/bin/server/main.rs` | `server` |

A file in `src/bin/server.rs` does **not** automatically become `my-project-server`; its inferred target name is `server`.

## Explicit Configuration

Use `[[bin]]` when convention is not enough:

```toml
[[bin]]
name = "my-server"
path = "src/bin/server.rs"
required-features = ["server"]

[[bin]]
name = "my-cli"
path = "src/bin/cli.rs"
```

A package-level default can be selected with:

```toml
[package]
name = "my-tool"
default-run = "my-tool"
```

## Workspace Context

Use `-p`/`--package` to choose a workspace member and `--bin` to choose one of that member's binary targets:

```bash
cargo run -p app-tools --bin server
cargo run -p app-tools --bin cli
```

## See Also

- [proj-lib-main-split](./proj-lib-main-split.md) - Keep binary entry points small
- [proj-workspace-large](./proj-workspace-large.md) - Workspaces for larger projects
- [proj-flat-small](./proj-flat-small.md) - Avoid needless structure in small packages

## References

- [Cargo Book: package layout](https://doc.rust-lang.org/cargo/guide/project-layout.html)
- [Cargo Book: targets](https://doc.rust-lang.org/cargo/reference/cargo-targets.html)
