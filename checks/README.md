# checks — compile-verify the rule examples

This dev tool type-checks Rust blocks in `../rules/*.md`. Its primary invariant is
that recommended examples compile unless the rule explicitly says why they are a
fragment, compile-fail example, ignored snippet, or nightly-only example.

## Run

```bash
bash checks/check.sh
```

The command runs structural/link/index checks, regression-tests the expectation
extractor, extracts examples, compiles them with the pinned Rust 1.99 toolchain,
and enforces both explicit expectations and the remaining legacy baseline. It also
runs fixture contracts and runtime regressions for the recommended cancellation
example (partial reads, frame contents, EOF, and a closed message channel).
Set `CARGO_TARGET_DIR` to keep all ordinary and fixture build outputs in a chosen
disposable directory. Relative values are resolved once against the directory
from which `check.sh` is invoked, before the harness changes working directory;
compiler-wrapper preservation follows `check.sh`.

## Example expectations

A Rust block under a heading beginning with `Good` or `Bad` defaults to **`compile`**.
Other existing sections keep the legacy classifier during migration.

Override an example by placing a hidden marker immediately above the fence:

````markdown
<!-- rust-check: fragment; reason=uses domain types defined elsewhere -->
```rust
use crate::domain::Request;
```
````

Supported expectations:

- `compile` — must produce zero compiler errors.
- `fragment` — may fail only because surrounding names/context are absent.
- `compile_fail` — must fail to compile.
- `ignore` — not compiled; an explicit `rust-check` marker requires a reason.
- `nightly(feature_name)` — not checked by the stable harness; records the required feature.
- `fixture(name)` — checked by `fixtures/<name>/verify.sh` instead of the ordinary example harness.

Examples:

```markdown
<!-- rust-check: compile -->
<!-- rust-check: compile_fail; reason=demonstrates ownership error -->
<!-- rust-check: ignore; reason=requires a proc-macro crate -->
<!-- rust-check: nightly(portable_simd); reason=nightly-only API -->
```

### Native rustdoc fence attributes

The extractor also honors rustdoc's native fence attributes when they directly
state compile expectations:

````markdown
```rust,compile_fail
let x: u8 = "wrong type";
```

```rust,ignore
code_that_requires_an_external_environment();
```
````

`compile_fail` becomes the verifier's `compile_fail` expectation and plain
`ignore` skips generation. `no_run` and `should_panic` still have to type-check,
so they retain the section/default compile expectation. If an explicit
`rust-check` marker and a native `compile_fail`/`ignore` attribute contradict one
another, generation fails instead of silently choosing one.

The Cargo harness itself is Edition 2024. Native rustdoc edition selectors are
not currently separate Cargo compilation modes; use explicit metadata when an
example genuinely requires a different harness environment rather than assuming
the fence changes this package's edition.

## Compiler evidence

The analyzer requires a complete Cargo JSON stream with one `build-finished`
record. Every generated example must have either a matching `compiler-artifact`
(including fresh/cache-hit artifacts) or an error diagnostic for that example's
source path. Warnings alone do not prove compilation. Missing examples, malformed
JSON, and errors in dependencies or build scripts fail validation instead of
being mistaken for successful examples. Cargo may exit unsuccessfully because
the corpus intentionally includes compile-fail examples; inspect `check.err` for
infrastructure failures before changing example expectations or debt files.

## Two debt files, two meanings

`baseline.txt` is only for **legacy `auto` examples**. It has no authority to
bless a failing recommended (`compile`) example. Each baseline entry now names an
exact file, section, **code-block ordinal**, and compiler-error signature. New,
changed, and stale baseline entries all fail CI, so the file is an exact snapshot
of acknowledged legacy suspects rather than an append-only suppression list.

`good-exceptions.txt` is the migration ledger for exact known failures of strict
recommended/explicit examples. It uses the same exact block identity plus a
human-readable reason. New or changed failures are rejected, and stale entries
fail CI. The goal is to keep this file empty.

To inspect current state:

```bash
cd checks
uv run --no-project python gen.py
cargo check --examples --target x86_64-unknown-linux-gnu --keep-going \
  --message-format=json > check.json 2> check.err || true
uv run --no-project python analyze.py check.json
```

Migration helpers (review their output before committing it):

```bash
uv run --no-project python analyze.py check.json --emit-baseline > baseline.generated.txt
uv run --no-project python analyze.py check.json --emit-good-exceptions > good-exceptions.generated.txt
```

Do **not** regenerate either debt file merely to make CI green. Fix real example
bugs or add explicit metadata first. Regenerating `baseline.txt` is appropriate
when intentionally migrating its signature format or after reviewing/removing
stale legacy debt; the generated diff should be treated as code-review material.

## Notes

- The harness is pinned by `checks/rust-toolchain.toml` to Rust 1.99.0.
- Generated `examples/`, `check.json`, `check.err`, and `manifest.json` are ignored.
- Outside strict `Good`/`Bad` sections, `gen.py` keeps legacy examples as
  `auto` except `#![feature(...)]` snippets, which remain nightly-only. Special
  environments and non-default expectations should use explicit metadata.
- `test_gen_metadata.py` creates a temporary rule file, verifies native fence
  parsing, removes it, and restores the generated manifest/examples before the
  real corpus compile begins.
