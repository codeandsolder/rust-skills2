# Source lint policy (Rust/WASI migration)

The policy checker is a portable `wasm32-wasip1` command. The thin Node host
captures Cargo metadata, the exact nightly's Clippy group table and effective
compiler flags, and canonical repository-owned paths. The guest reads the
checkout through its `/workspace` preopen and makes policy decisions in Rust.

The host is responsible for native processes and platform-specific canonical
paths, not lint decisions. The guest requires no ambient environment, network,
or subprocesses. The same module is intended to run on Linux, macOS and Windows.

## Local build and differential validation

Use the repository's dated nightly and mandatory sccache configuration.

```sh
rustup target add --toolchain nightly-2026-11-19 wasm32-wasip1
cargo test --manifest-path policy-wasm/Cargo.toml --locked --target-dir /path/to/build
cargo build --manifest-path policy-wasm/Cargo.toml --locked --release --target wasm32-wasip1 --target-dir /path/to/build
uv run --no-project python checks/compare_source_policy.py /path/to/build/wasm32-wasip1/release/source-policy.wasm --fixtures nightly-2026-11-19
```

From any consuming Cargo workspace:

```sh
node /path/to/rust-skills2/policy-wasm/check.mjs /path/to/source-policy.wasm nightly-2026-11-19
```

The old checker is still the production path on main while the candidate is
being compared. It is a migration oracle, not a compatibility fallback.
Once validated, publish a provider-built module and pin its digest at the
provider invocation; consumers must not rebuild the checker on each run.
