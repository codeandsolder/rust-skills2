# lint-dylint-custom

> Use Dylint for compiler-resolved project-specific lints when existing Clippy and simpler static checks cannot express the contract

## Why It Matters

Clippy covers general Rust quality, correctness and performance. A project may
need to recognize a particular resolved API, type, call site or architectural
boundary that is not covered by those lints. Dylint lets a workspace load
custom compiler lint libraries without maintaining a Clippy fork.

## Good: Start from a Real Lint Library

Use the upstream [Dylint generator](https://github.com/trailofbits/dylint#writing-lints)
rather than copying a version-specific private rustc API example:

```bash
cargo install --locked cargo-dylint dylint-link
cargo dylint new my_custom_lint
cd my_custom_lint
cargo build --locked
cargo dylint list --path .
```

Commit the library's generated toolchain configuration, lockfile and tests.
If its template does not yet have a lockfile, generate one before the locked
build. The lint runs against compiler internals, so match its driver and library
to the supported dated nightly and required components. A project under review
can have a separate stable build baseline.

Implement the actual early or late lint pass in the generated library. For a
ban on a resolved function, use the definition ID rather than matching a
method name string: imports, aliases, inherent methods and trait methods can
otherwise change what the code means without changing its spelling. Test
positive cases, same-named unrelated functions, macro expansion, cfgs and
generic instantiations as appropriate.

## Run Project-Owned Lints

At the workspace root, declare the lint libraries using the documented Dylint
workspace metadata:

```toml
[workspace.metadata.dylint]
libraries = [{ path = "lint-libraries/my_custom_lint" }]
```

Then run `cargo dylint --all` in a distinct check alongside ordinary Clippy.
Pin external lint sources to reviewed releases or commits. Do not enable a
project-wide lint until its false-positive boundaries and diagnostic semantics
are understood.

## Marker

[Marker](https://github.com/rust-marker/marker) is an experimental custom
lint-interface project intended to insulate lint authors from compiler
internals. Its own compiler driver still depends on nightly rustc; it is not
a stable-only analysis backend. Verify activity, supported compiler versions
and API coverage before choosing it.

## When to Use a Custom Lint

- Prefer an existing compiler/Clippy lint when its semantics match.
- Use a lightweight source or manifest check for purely syntactic/configuration
  constraints.
- Use a compiler-resolved pass for type, symbol or control-flow requirements.
  Keep the invariant separate from the version-specific compiler adapter.
- Maintain independent positive and negative fixtures and keep the normal
  production build, Clippy and tests in CI.

## See Also

- [lint-deny-correctness](./lint-deny-correctness.md) — common correctness policy
- [Dylint repository and quick start](https://github.com/trailofbits/dylint)
- [Dylint template](https://github.com/trailofbits/dylint-template)
- [Marker repository](https://github.com/rust-marker/marker)
