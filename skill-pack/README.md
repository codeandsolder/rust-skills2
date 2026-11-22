# Portable Rust skill packaging

The release workflow compiles the pinned nightly Rust packer to
`wasm32-wasip1` once, runs it on Linux, then verifies identical ZIP, skill and
checksum bytes with the same module on Windows and macOS. ZIP creation and
verification use zip-rs with the pure Rust zlib-rs DEFLATE backend. SHA-256 is
computed in the guest and independently verified by the host before
publication. No Python or host compression tools are required.

To build locally, use the repository's selected nightly and managed sccache
configuration; keep the target directory outside the source tree:

```sh
cargo build --locked --release --target wasm32-wasip1 --manifest-path skill-pack/Cargo.toml --target-dir /path/to/build
node skill-pack/run.mjs /path/to/build/wasm32-wasip1/release/skill-pack.wasm . dist
node skill-pack/test.mjs /path/to/build/wasm32-wasip1/release/skill-pack.wasm
```

The host enumerates only SKILL.md, LICENSE and rules (including nested files),
rejects symlinks, and supplies explicit file paths to the guest. The guest
sorts entries, uses fixed DOS timestamps of 1980-01-01 00:00:00 and Unix
permissions 0644, validates the skill name and path inventory, and reads the
resulting ZIP back to verify all entry metadata and bytes before writing the
two identical archives. The host stages outputs and verifies both copies and
their checksums before replacing any published file. Failed guest execution
leaves previously published archives unchanged.
