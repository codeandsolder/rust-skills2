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
node --test policy-wasm/token-golden.test.mjs
cargo test --locked --manifest-path policy-wasm/Cargo.toml --test source_policy_golden
```

Frozen independent source-token expectations are checked by Rust unit tests
against the native implementation and by a Node test that runs the bundled
WASI scanner over all 213 cases; no Python or Zipp reference runtime is needed.
Workspace policy is checked against 21 frozen decisions from real Cargo fixtures,
including independent Cargo unit-graph evidence for `--workspace`/`-p` precedence.
Native-source policy acceptance fixtures use ordinary Rust integration tests
against the bundled policy-WASI artifact; all fixture statuses and diagnostics
are explicit, reviewed expectations.
The original independent Python oracle was retired after freezing its decisions across every source-policy fixture. `tests/golden/source-policy.json` contains reviewed expected exit statuses, counts and diagnostics. The Rust integration test calls the real bundled policy-WASI module and rejects missing/new fixture cases. It deliberately retains the extra forbidden `#[allow]` diagnostics the old oracle omitted for invalid generated boundaries.

## Native intrinsic policy

Handwritten Rust must use portable SIMD (`core::simd`/`std::simd`) or ordinary
Rust rather than target-specific vector intrinsics. The same source gate checks
inactive cfg branches, qualified paths, grouped imports and explicit aliases.
Architecture-specific module and wildcard imports are rejected because they
hide the specific operations being used. Feature detection and assembly macros
are not SIMD operations and remain available.

The centrally reviewed, exact-name exception set in
`src/native_intrinsics.rs` initially includes SHA and AES hardware operations,
CRC instructions and their native
register boundary types. These operations have no direct portable SIMD API;
prefer portable Rust when it lowers to equivalent instructions. Use portable
SIMD for loads, stores, lane shuffles, arithmetic, bit operations, masks and
other ordinary vector operations, including surrounding crypto glue. New
exceptions require a central policy change documenting why portable Rust
cannot produce a suitable operation; there is no per-project override.

Carry-less multiplication is deliberately not exempt: Rust integer
`carryless_mul` and `widening_carryless_mul` lower to hardware CLMUL with
the appropriate target feature. See zlib-rs-fast commit
`8343c6e31013b438ac2bf92c09e139e71021c4ac` for the narrow and wide
vector implementations. Imports from external crates are not restricted,
and the existing first-party inventory excludes Cargo registry/git
dependencies, vendor directories and registered Git submodules.

The additional exact-name exception table separates architecture-specific
machine operations (CPU identification, counters, entropy, explicit
cache/barrier and processor-state management, hardware transactions, memory
tagging, privileged operations, and WebAssembly memory/wait operations)
from specialized cryptography (SHA-512, SM3/SM4, RISC-V AES/SM4, Intel Key
Locker) and stateful AMX tile operations. Use standard timing, RNG, atomics
and spin hints for ordinary software requirements. Architecture-specific
system intrinsics are appropriate only when their actual hardware semantics
are required. There is no general escape for native arithmetic.

GFNI, PEXT/PDEP, ordinary VNNI dot products, vector compress/expand and
approximate reciprocal/rsqrt remain prohibited pending portable codegen
evidence. PEXT/PDEP have nightly integer methods, even though equivalent
instruction lowering for arbitrary masks is not yet verified.
