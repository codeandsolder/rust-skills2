# unsafe-miri-ci

> Exercise unsafe abstractions and their safe callers with Miri; combine dynamic checks with invariant review and native integration tests

## Why It Matters

Miri interprets Rust MIR and detects many instances of undefined behavior
on executed paths, including invalid memory access, uninitialized reads,
aliasing-model violations and data races. A crate with no handwritten unsafe
code can still expose bugs in its dependencies or in generated code.

Miri does not prove soundness, cover all schedules or validate arbitrary
native FFI. AddressSanitizer, ThreadSanitizer, model checking, fuzzing and
native tests can provide complementary evidence.

## Good: Run the Relevant Tests

Install Miri for a supported, dated nightly selected by the project.
Run the suite with that toolchain (replace the example channel with the
project's actual pin):

```bash
rustup toolchain install nightly-2026-11-21 --component miri
cargo +nightly-2026-11-21 miri setup
cargo +nightly-2026-11-21 miri test
```

Use the repository's actual supported feature/target configurations and
central CI cache setup. Miri's sysroot and interpreter are not ordinary
native builds; do not bypass the configured compiler wrapper for native
builds. Test primitive unsafe operations, safe API adversarial cases,
partial initialization and error/unwind paths.

## Stronger Coverage Where Useful

- Use multiple seeds for varied allocation addresses, nondeterminism and
  scheduling (`-Zmiri-many-seeds` on supporting toolchains); this is not an
  exhaustive concurrency search.
- Check the exact nightly's aliasing model defaults and flags; Stacked
  Borrows and Tree Borrows are operational models, not complete finalized
  Rust language specifications. Use the supported alternative model when
  investigating aliasing-sensitive code.
- Strict provenance checking can help detect reliance on exposed
  provenance. Select supported Miri flags deliberately for the test job;
  do not embed a hidden runtime configuration in library code.
- Keep native tests for foreign libraries, real device I/O, SIMD assembly
  and target-specific behavior that Miri cannot exercise.

## Scope

Prefer focused Miri tests for expensive or unsupported integration suites.
For a pure-safe application with no unsafe-sensitive boundary, a dedicated
lane may have lower value, but safe-only source is not a reason to claim
there is no benefit. Document any excluded configurations and why.
Rerun when changing unsafe abstractions or relevant dependencies.

## See Also

- [unsafe-untrusted-safe-code](./unsafe-untrusted-safe-code.md)
- [unsafe-unwind-safety](./unsafe-unwind-safety.md)
- [test-loom-concurrency](./test-loom-concurrency.md)
- [Miri documentation](https://github.com/rust-lang/miri)
