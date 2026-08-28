# proj-build-rs-minimal

> Keep `build.rs` deterministic, narrow its declared inputs, and write generated artifacts under `OUT_DIR`.

## Why It Matters

Cargo compiles and runs a package build script before building the package when that script needs to run. If a build script emits **no** `rerun-if-*` instructions, Cargo conservatively reruns it when any file in the package changes. Emitting narrow `cargo::rerun-if-changed` / `cargo::rerun-if-env-changed` instructions lets Cargo avoid unrelated rebuilds.

Build scripts also run as **host** programs. `cfg!(target_os = ...)` inside `build.rs` describes the host that executes the script, not necessarily the target being compiled. For target configuration, read Cargo's `CARGO_CFG_*` environment variables.

Finally, build output belongs in `OUT_DIR`. Writing generated files back into `src/` or elsewhere in the package makes builds mutate source trees and behaves badly with read-only sources, packaging, caching, and concurrent target directories.

## Bad

<!-- rust-check: compile -->
```rust
use std::fs;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    // BAD: no rerun-if directives, so any package-file change may rerun us.

    // BAD: this is the build-script HOST configuration, not necessarily the
    // target configuration when cross-compiling.
    let target_is_windows = cfg!(target_os = "windows");

    // BAD: fragile capability detection by parsing a display string.
    let rustc = Command::new("rustc")
        .arg("--version")
        .output()
        .expect("rustc must run");
    let version = String::from_utf8(rustc.stdout).expect("rustc output is UTF-8");

    // BAD: embeds wall-clock nondeterminism in generated source.
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // BAD: mutates the source tree instead of Cargo's output directory.
    let generated = format!(
        "pub const HOST_WINDOWS: bool = {target_is_windows};\n\
         pub const RUSTC: &str = {version:?};\n\
         pub const BUILT_AT: u64 = {timestamp};\n"
    );
    fs::write("src/build_info.rs", generated).unwrap();
}
```

Every line above is legal Rust. The problem is the build contract: over-broad invalidation, host/target confusion, nondeterministic output, and source-tree mutation.

## Good

<!-- rust-check: compile -->
```rust
use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    // These are the actual non-Cargo inputs this script reads.
    println!("cargo::rerun-if-changed=schema/api.txt");
    println!("cargo::rerun-if-env-changed=MY_CODEGEN_MODE");

    // Cargo exposes TARGET configuration through CARGO_CFG_* variables.
    let target_os = env::var("CARGO_CFG_TARGET_OS")
        .expect("Cargo sets CARGO_CFG_TARGET_OS for build scripts");

    let mode = env::var("MY_CODEGEN_MODE").unwrap_or_else(|_| String::from("default"));
    let schema = fs::read_to_string("schema/api.txt")
        .expect("schema/api.txt must be packaged with the crate");

    let out_dir = PathBuf::from(
        env::var_os("OUT_DIR").expect("Cargo sets OUT_DIR for build scripts"),
    );

    let generated = format!(
        "pub const TARGET_OS: &str = {target_os:?};\n\
         pub const MODE: &str = {mode:?};\n\
         pub const SCHEMA: &str = {schema:?};\n"
    );

    fs::write(out_dir.join("generated.rs"), generated)
        .expect("write generated source to OUT_DIR");
}
```

A crate can then include the generated file from Rust source with `include!(concat!(env!("OUT_DIR"), "/generated.rs"));` when that is the appropriate code-generation interface.

## `rerun-if-*` Details

Cargo's current behavior matters here:

- With **no** `rerun-if-*` instructions, Cargo scans the package for changes and may rerun the script after any package-file change.
- Once the script emits `rerun-if-*`, those declared values become the change-detection inputs.
- Cargo separately tracks the build script's own source and dependencies. If the script is recompiled, Cargo runs the new build script.
- Therefore, if a script already declares real inputs, adding `cargo::rerun-if-changed=build.rs` is redundant.
- If the script has **no external inputs at all**, `cargo::rerun-if-changed=build.rs` is a convenient sentinel that prevents unrelated package files from causing reruns.

Declare every file/environment input whose change should alter the output. Missing an input risks stale generated state; declaring a large directory or unrelated file set causes unnecessary rebuilds.

## Host vs Target

Build scripts execute for the host toolchain. This is wrong when you meant the compilation target:

<!-- rust-check: compile -->
```rust
fn host_check_is_not_target_check() -> bool {
    cfg!(target_arch = "x86_64")
}
```

For target properties use variables such as `CARGO_CFG_TARGET_ARCH`, `CARGO_CFG_TARGET_OS`, and other `CARGO_CFG_*` values that Cargo passes to the script.

## Capability Detection

Do not infer compiler capabilities from ad-hoc string matching such as `rustc --version` containing some substring. Prefer one of these approaches:

- use stable language/library APIs when your crate's MSRV already guarantees them;
- probe the capability by compiling a small snippet (tools such as `autocfg` exist for this pattern);
- use a purpose-built version/capability helper when a probe is not suitable.

If a dependency is needed only by `build.rs`, put it under `[build-dependencies]`; build scripts do not automatically have access to normal `[dependencies]`.

## Determinism and External Inputs

Build scripts legitimately inspect the local build environment—for example to find native libraries or invoke a C compiler. The important rule is to make inputs and outputs understandable and reproducible enough for the package's build contract.

Avoid making ordinary crate builds depend on live network fetches. Network availability, remote content changes, credentials, and rate limits make offline/reproducible builds unreliable. Prefer vendored/package inputs, package-manager/system discovery, or an explicit pre-build fetch step when remote assets are unavoidable.

Avoid embedding timestamps, random IDs, current working-tree state, or other volatile values unless that nondeterminism is an intentional product requirement.

## Output Discipline

Cargo provides `OUT_DIR` for build-script outputs. Do not assume it starts empty; its contents can persist across rebuilds. If your generator needs a clean subdirectory, manage that subdirectory explicitly.

Do not write generated artifacts into `src/` during normal compilation. If generated source is intended to be committed, generate/update it in an explicit developer task and let `build.rs` consume the committed result instead of mutating it.

## Keep the Script Small Enough to Audit

A short `build.rs` that wires together inputs, environment, and a generator is easier to reason about than a second application hidden inside the build. If generation logic becomes substantial, put it in a normal library/tool that can be unit-tested and call that from the build script.

Also remember that a build script inherits one Cargo jobserver slot. Tools that create their own parallel work should cooperate with Cargo's jobserver rather than oversubscribing CPUs blindly.

## See Also

- [proj-feature-additive](./proj-feature-additive.md) - Feature design
- [lint-cfg-check](./lint-cfg-check.md) - Checking custom cfg names
