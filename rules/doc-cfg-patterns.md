# doc-cfg-patterns

> Use real `#[cfg(...)]` attributes for availability; on docs.rs, optionally add `doc(cfg)` badges behind `cfg(docsrs)` because `doc_cfg` is still unstable on stable Rust

## Why It Matters

Conditionally compiled APIs need two separate things:

1. a real `#[cfg(...)]` that controls whether the item exists; and
2. documentation that tells readers which feature or target makes it available.

`#[doc(cfg(...))]` provides a useful availability badge in rustdoc, but on stable Rust it is still part of the unstable `doc_cfg` feature. docs.rs builds crates with a nightly compiler and exposes the `docsrs` cfg, so a common pattern is to enable `doc_cfg` only there and gate the annotation with `cfg_attr`.

Do not use `doc(cfg)` as though it were the availability gate itself: it documents a condition, but `#[cfg(...)]` is what actually includes or excludes the item.

## Bad: Documentation Attribute Without the Real Gate

```rust
// BAD: this would only describe a condition; it would not make the module
// feature-gated even on a compiler where doc(cfg) is enabled.
#[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
pub mod cuda_accel {}
```

## Good: Pair the Real Gate With a docs.rs Badge

```rust
/// CUDA-accelerated tensor operations.
#[cfg(feature = "cuda")]
#[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
pub mod cuda_accel {}

/// Linux-specific filesystem utilities.
#[cfg(target_os = "linux")]
#[cfg_attr(docsrs, doc(cfg(target_os = "linux")))]
pub mod linux_fs {}

fn main() {}
```

On an ordinary stable build where `docsrs` is not set, the unstable documentation attribute is not emitted. On docs.rs, the annotation can render an availability badge while the actual `cfg` still controls the API.

## Crate-Root Setup for docs.rs

Because `doc_cfg` remains unstable, enable it only for the docs.rs build:

<!-- rust-check: compile -->
```rust
#![cfg_attr(docsrs, feature(doc_cfg))]
```

docs.rs currently builds documentation with nightly Rust and sets `cfg(docsrs)` for the final rustdoc invocation. You therefore do not need to invent a different feature flag just for this purpose.

If the items you want to document are behind Cargo features, configure docs.rs to build the relevant features. For a crate where every public feature is safe to combine, that can be:

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

## Feature-Gated Modules

```rust
#[cfg(feature = "cuda")]
#[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
pub mod cuda_accel {
    pub fn device_count() -> usize {
        1
    }
}

fn main() {}
```

If docs.rs should show this module, make sure the `cuda` feature is enabled in the docs.rs build metadata.

## Platform-Specific Items

```rust
#[cfg(windows)]
#[cfg_attr(docsrs, doc(cfg(windows)))]
pub fn windows_only_hook() {}

#[cfg(target_os = "linux")]
#[cfg_attr(docsrs, doc(cfg(target_os = "linux")))]
pub fn inotify_watch() {}

fn main() {}
```

A docs build for one target cannot automatically document an item that was completely cfg'd out for that target unless the build configuration also arranges for the item to exist. `doc(cfg)` only labels an item that rustdoc is actually documenting.

## Enum Variants Behind Features

```rust
#[non_exhaustive]
pub enum Backend {
    Cpu,

    #[cfg(feature = "cuda")]
    #[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
    Cuda,

    #[cfg(feature = "metal")]
    #[cfg_attr(docsrs, doc(cfg(feature = "metal")))]
    Metal,
}

fn main() {
    let _ = Backend::Cpu;
}
```

The same pairing applies to methods, trait impls, modules, variants, and other conditionally compiled public items.

## Direct `#[doc(cfg(...))]` Is Still Unstable on Stable Rust 1.98

Do not write a rule that presents this as stable today:

```rust,ignore
#![feature(doc_cfg)]

#[doc(cfg(feature = "cuda"))]
pub mod cuda_accel {}
```

That form is appropriate only in a nightly build with the feature enabled. The stable-compatible source pattern is to hide both the feature gate and the `doc(cfg)` attribute behind `cfg(docsrs)`.

## Avoid Over-Tagging

If an entire public module is already clearly feature-gated, repeating the same badge on every private helper or every implementation detail adds noise. Put availability documentation at the public boundary readers actually need.

Conversely, do not omit a badge merely because the source has a `cfg`: users browsing generated docs should not have to inspect source code to learn why an API is unavailable.

## CI for Documentation Builds

Once a crate relies on docs.rs-specific configuration, test that path deliberately. At minimum, make sure ordinary stable `cargo check` / `cargo doc` still work with `docsrs` unset. For projects that depend heavily on docs.rs behavior, add a nightly documentation job that enables `cfg(docsrs)` and the same feature set used by docs.rs.

Do not make every normal stable build enable `doc_cfg`; keeping the unstable feature isolated to documentation builds reduces toolchain coupling.

## See Also

- [doc-cargo-metadata](./doc-cargo-metadata.md) — docs.rs metadata setup
- [doc-module-inner](./doc-module-inner.md) — module-level documentation
- [doc-include-str](./doc-include-str.md) — conditional documentation includes

## References

- [Rustdoc unstable features: `doc(cfg)`](https://doc.rust-lang.org/rustdoc/unstable-features.html#doccfg-and-docauto_cfg)
- [Rust Unstable Book: `doc_cfg`](https://doc.rust-lang.org/beta/unstable-book/language-features/doc-cfg.html)
- [docs.rs build environment](https://docs.rs/about/builds)
- [docs.rs metadata](https://docs.rs/about/metadata)
