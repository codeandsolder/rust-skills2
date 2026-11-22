# Source lint policy (Rust/WASI)

The policy checker is a portable `wasm32-wasip1` command. The thin Node host
captures Cargo metadata, the exact nightly's Clippy group table and effective
compiler flags, and canonical repository-owned paths. The guest reads the
checkout through its `/workspace` preopen and makes policy decisions in Rust.
The host handles native processes and platform-specific paths, not lint
decisions. The guest requires no ambient environment, network or subprocesses.

Both shared source lint gates run the same digest-verified bundled module,
using Node's built-in WASI runtime. There is no per-consumer compilation,
dependency installation or separate artifact download. The single
`module.wasm.gz` file is the intentional deploy artifact, not a build cache.

## Local invocation

From any consuming Rust workspace, with the selected nightly and Clippy installed:

```sh
node /path/to/rust-skills2/policy-wasm/check.mjs /path/to/rust-skills2/policy-wasm/module.json nightly-2026-11-19
```

## Updating the module

Use the repository's dated nightly and mandatory sccache configuration.
Build outside the checkout, then pack the canonical module:

```sh
rustup target add --toolchain nightly-2026-11-19 wasm32-wasip1
cargo test --manifest-path policy-wasm/Cargo.toml --locked --target-dir /path/to/build
cargo build --manifest-path policy-wasm/Cargo.toml --locked --release --target wasm32-wasip1 --target-dir /path/to/build
node policy-wasm/package.mjs pack /path/to/build/wasm32-wasip1/release/source-policy.wasm nightly-2026-11-19
```

Prefer the exact approved provider CI build artifact if local and hosted
build paths produce different bytes. Commit the compressed module and JSON
manifest together with guest-source changes. The manifest fingerprints the
guest source tree and uncompressed module; the runtime verifies the latter.
Provider CI verifies the source fingerprint and byte-identical rebuild when
the build compiler matches. A nightly promotion alone does not require
repackaging an unchanged portable module. Both the rebuilt and bundled
modules must pass the same policy regressions.

```sh
node policy-wasm/package.mjs verify /path/to/build/wasm32-wasip1/release/source-policy.wasm nightly-2026-11-19
uv run --no-project python -B checks/compare_source_policy.py policy-wasm/module.json . --fixtures nightly-2026-11-19
```

The prior Python implementation is a test-only differential oracle in
`checks/source_policy_oracle.py`, not an alternative consumer code path.
