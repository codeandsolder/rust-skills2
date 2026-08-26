# checks — compile-verify the rule examples

This dev tool type-checks Rust blocks in `../rules/*.md`. Its primary invariant is
that recommended examples compile unless the rule explicitly says why they are a
fragment, compile-fail example, ignored snippet, or nightly-only example.

## Run

```bash
bash checks/check.sh
```

The command runs structural/link/index checks, extracts examples, compiles them
with the pinned Rust 1.98 toolchain, and enforces both explicit expectations and
the remaining legacy baseline.

## Example expectations

A Rust block under a heading beginning with `Good` defaults to **`compile`**.
Other existing sections keep the legacy classifier during migration.

Override an example by placing a hidden marker immediately above the fence:

```markdown
<!-- rust-check: fragment; reason=uses domain types defined elsewhere -->
```rust
use crate::domain::Request;
```
```

Supported expectations:

- `compile` — must produce zero compiler errors.
- `fragment` — may fail only because surrounding names/context are absent.
- `compile_fail` — must fail to compile.
- `ignore` — not compiled; requires a reason.
- `nightly(feature_name)` — not checked by the stable harness; records the required feature.

Examples:

```markdown
<!-- rust-check: compile -->
<!-- rust-check: compile_fail; reason=demonstrates ownership error -->
<!-- rust-check: ignore; reason=requires a proc-macro crate -->
<!-- rust-check: nightly(portable_simd); reason=nightly-only API -->
```

## Two debt files, two meanings

`baseline.txt` is only for **legacy `auto` examples**. It no longer has authority
to bless a failing recommended (`compile`) example.

`good-exceptions.txt` is a temporary migration ledger for exact known failures of
recommended examples. Every entry has a reason. Error signatures are exact, so a
new or changed failure is rejected, and stale entries fail CI so fixed examples
must be removed from the ledger.

To inspect current state:

```bash
cd checks
python3 gen.py
cargo check --examples --target x86_64-unknown-linux-gnu --keep-going \
  --message-format=json > check.json 2> check.err || true
python3 analyze.py check.json
```

Migration helpers (review their output before committing it):

```bash
python3 analyze.py check.json --emit-baseline > baseline.txt
python3 analyze.py check.json --emit-good-exceptions > good-exceptions.generated.txt
```

Do **not** regenerate either file merely to make CI green. Fix real example bugs
or add explicit metadata first; debt entries are for acknowledged existing cases.

## Notes

- The harness is pinned by `checks/rust-toolchain.toml` to Rust 1.98.0.
- Generated `examples/`, `check.json`, `check.err`, and `manifest.json` are ignored.
- `gen.py` still auto-skips legacy `Bad`, placeholder, proc-macro, ellipsis, and
  nightly snippets outside `Good`; new/edited rules should prefer explicit markers.
