# doc-cfg-patterns

> Use real `#[cfg(...)]` attributes for availability; when nightly rustdoc's `doc_cfg` is enabled, let `doc(auto_cfg)` surface those conditions and use `doc(cfg)` only when you need to override the displayed condition

## Why It Matters

Conditionally compiled APIs need two separate things:

1. a real `#[cfg(...)]` that controls whether the item exists; and
2. documentation that tells readers which feature or target makes it available.

On current nightly rustdoc, the unstable `doc_cfg` feature also enables `#[doc(auto_cfg)]` at the crate level by default. Rustdoc can therefore derive availability badges from ordinary `#[cfg(...)]` attributes without manually duplicating the condition as `#[doc(cfg(...))]` on every item.

`#[doc(cfg(...))]` remains useful when the condition that is best for readers should deliberately differ from the exact implementation `cfg`. It is documentation only: `#[cfg(...)]` is still what actually includes or excludes the item.

Because `doc_cfg` is unstable on stable Rust 1.98, crates that use this behavior on docs.rs should isolate the feature gate to that nightly documentation build.

## Bad: Treating `doc(cfg)` as the Availability Gate

```rust
// BAD: this describes a condition only on a compiler where doc(cfg) is
// enabled. It does not make the module feature-gated.
#[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
pub mod cuda_accel {}
```

The API exists regardless of the `cuda` feature because there is no real `#[cfg(feature = "cuda")]`.

## Good: Let the Real `cfg` Drive Availability and Documentation

```rust
/// CUDA-accelerated tensor operations.
#[cfg(feature = "cuda")]
pub mod cuda_accel {}

/// Linux-specific filesystem utilities.
#[cfg(target_os = "linux")]
pub mod linux_fs {}

fn main() {}
```

With `doc_cfg` enabled, rustdoc's crate-level default `doc(auto_cfg)` can display those `cfg` conditions automatically. On ordinary stable builds, the source still uses only stable `cfg` attributes.

## Crate-Root Setup for docs.rs

Gate the unstable rustdoc feature to the docs.rs build:

<!-- rust-check: compile -->
```rust
#![cfg_attr(docsrs, feature(doc_cfg))]
```

docs.rs builds documentation with a nightly compiler and sets `cfg(docsrs)` for the final rustdoc invocation. On stable builds where that cfg is absent, the unstable feature attribute is not emitted.

If the items you want to document are behind Cargo features, configure docs.rs to build the relevant feature set. For a crate where every public feature is safe to combine, that can be:

```toml
[package.metadata.docs.rs]
all-features = true
```

For crates with mutually exclusive, internal, or otherwise unsuitable features, list only the documentation feature set you actually want instead of blindly enabling everything.

## Declare the Custom `docsrs` cfg for `unexpected_cfgs`

Modern Cargo/rustc can warn about unknown custom cfg names. If your lint configuration checks cfg names, declare `docsrs` explicitly:

```toml
[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(docsrs)'] }
```

This is separate from enabling the cfg. docs.rs supplies `docsrs`; the lint declaration simply tells rustc that the name is intentional.

## Override the Displayed Condition Only When Useful

Sometimes the implementation condition is more detailed than the public compatibility statement you want readers to see. In that case an explicit `doc(cfg)` can override auto-generated presentation:

```rust
#[cfg(all(unix, feature = "io-uring"))]
#[cfg_attr(docsrs, doc(cfg(feature = "io-uring")))]
pub fn io_uring_backend() {}

fn main() {}
```

Here the real availability requirement remains `all(unix, feature = "io-uring")`; the explicit documentation badge is a deliberate presentation choice. Do not use this to conceal a platform requirement callers actually need to know.

## Platform-Specific Items

```rust
#[cfg(windows)]
pub fn windows_only_hook() {}

#[cfg(target_os = "linux")]
pub fn inotify_watch() {}

fn main() {}
```

With `doc_cfg` enabled, these conditions can be surfaced automatically. A docs build for one target still cannot document an item that has been completely cfg'd out unless the build configuration arranges for that item to exist; `doc(auto_cfg)` and `doc(cfg)` label items that rustdoc is actually documenting.

## Enum Variants Behind Features

```rust
#[non_exhaustive]
pub enum Backend {
    Cpu,

    #[cfg(feature = "cuda")]
    Cuda,

    #[cfg(feature = "metal")]
    Metal,
}

fn main() {
    let _ = Backend::Cpu;
}
```

The same principle applies to methods, trait impls, modules, variants, and other conditionally compiled public items: write the real `cfg` first and let documentation tooling derive it when possible.

## Direct `#[doc(cfg(...))]` Is Nightly-Only on Rust 1.98

The direct attribute and `doc(auto_cfg)` are part of the unstable `doc_cfg` feature. Do not present this as stable source that can be enabled on stable Rust:

<!-- rust-check: nightly(doc_cfg); reason=direct doc(cfg) requires the unstable doc_cfg feature -->
```rust
#![feature(doc_cfg)]

#[cfg(feature = "cuda")]
#[doc(cfg(feature = "cuda"))]
pub mod cuda_accel {}
```

That direct form is appropriate only in a nightly build with `doc_cfg` enabled, and under current rustdoc it is usually redundant when it exactly repeats the real `cfg` because `doc(auto_cfg)` is enabled by default. Use an explicit `doc(cfg)` when you intentionally want to override the automatically displayed condition.

## Avoid Over-Tagging

Do not mechanically repeat the same feature badge on every item. Current `doc(auto_cfg)` already derives ordinary availability conditions, and inherited module-level context may make further manual annotation unnecessary.

When an explicit override is warranted, put it at the public boundary readers actually need and make sure it remains truthful about the usable API surface.

## CI for Documentation Builds

Once a crate relies on docs.rs-specific configuration, test that path deliberately. At minimum, make sure ordinary stable `cargo check` / `cargo doc` still work with `docsrs` unset. For projects that depend heavily on docs.rs behavior, add a nightly documentation job that enables `cfg(docsrs)` and the same feature set used by docs.rs.

Do not make every normal stable build enable `doc_cfg`; keeping the unstable feature isolated to documentation builds reduces toolchain coupling.

## See Also

- [doc-cargo-metadata](./doc-cargo-metadata.md) — docs.rs metadata setup
- [doc-module-inner](./doc-module-inner.md) — module-level documentation
- [doc-include-str](./doc-include-str.md) — conditional documentation includes

## References

- [Rustdoc unstable features: `doc(cfg)` and `doc(auto_cfg)`](https://doc.rust-lang.org/rustdoc/unstable-features.html#doccfg-and-docauto_cfg)
- [Rust Unstable Book: `doc_cfg`](https://doc.rust-lang.org/beta/unstable-book/language-features/doc-cfg.html)
- [docs.rs build environment](https://docs.rs/about/builds)
- [docs.rs metadata](https://docs.rs/about/metadata)
