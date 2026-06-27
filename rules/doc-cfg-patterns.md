# doc-cfg-patterns

> Use `#[doc(cfg(...))]` to annotate platform/feature-gated items

## Why It Matters

When an item is gated behind a feature flag or platform target, users need to know why it's not available. `#[doc(cfg(...))]` renders a prominent badge ("Available on crate feature `foo` only" / "Available on Unix only") in the generated docs, helping users understand compile-time requirements without trial and error.

## Bad

```rust
// Users see the module but not what gates it
#[cfg(feature = "cuda")]
pub mod cuda_accel;
```

## Good

```rust
/// CUDA-accelerated tensor operations.
#[doc(cfg(feature = "cuda"))]
pub mod cuda_accel;

/// Unix-specific file system utilities.
#[doc(cfg(target_os = "linux"))]
pub mod linux_fs;
```

Users see a badge: **Available on crate feature `cuda` only**.

## Setup

Enable `doc_cfg` annotations on docs.rs by configuring `Cargo.toml`:

```toml
[package.metadata.docs.rs]
all-features = true
rustdoc-args = ["--cfg", "docsrs"]
```

Then in your crate root, enable the nightly `doc_cfg` feature on docs.rs:

```rust
#![cfg_attr(docsrs, feature(doc_cfg))]
```

And guard annotations with `#[cfg_attr(docsrs, doc(cfg(...)))]`:

```rust
/// Async HTTP client.
#[cfg_attr(docsrs, doc(cfg(feature = "async")))]
pub mod async_client;
```

### Using `#[doc(cfg(...))]` Directly

When `doc_cfg` is fully stabilized (nightly tracking, PR #150055),
you can write `#[doc(cfg(feature = "..."))]` directly without
`cfg_attr` wrapping:

```rust
#[doc(cfg(feature = "cuda"))]
pub mod cuda_accel;
```

## Common Patterns

### Feature-Gated Modules

```rust
#[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
pub mod cuda_accel {
    // ...
}
```

### Platform-Specific Items

```rust
#[cfg_attr(docsrs, doc(cfg(windows)))]
pub fn windows_only_hook() { /* ... */ }

#[cfg_attr(docsrs, doc(cfg(target_os = "linux")))]
pub fn inotify_watch() { /* ... */ }
```

### Enum Variants Behind a Feature

```rust
#[non_exhaustive]
pub enum Backend {
    /// CPU-based computation (always available).
    Cpu,
    /// CUDA GPU acceleration.
    #[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
    Cuda,
    /// Apple Metal acceleration.
    #[cfg_attr(docsrs, doc(cfg(feature = "metal")))]
    Metal,
}
```

### Methods on a Feature-Gated Impl Block

```rust
impl Tensor {
    /// Creates a tensor on the GPU device.
    #[cfg_attr(docsrs, doc(cfg(feature = "cuda")))]
    pub fn to_cuda(&self) -> CudaTensor { /* ... */ }
}
```

## Anti-Pattern: Over-Tagging

Don't annotate internal trivial gates or every single item:

```rust
// Bad: overly verbose, adds visual noise
#[doc(cfg(feature = "serde"))]
impl Serialize for MyType {}

#[doc(cfg(feature = "serde"))]
impl Deserialize for MyType {}

// Good: tag only the module or feature entry-point
#[doc(cfg(feature = "serde"))]
pub mod serde_impls;
```

## Lints

There is no built-in lint for missing `doc(cfg)` annotations yet. Review
feature-gated items manually or with a custom CI check:

```bash
# Search for items gated behind #[cfg] without matching doc(cfg)
grep -rn '#\[cfg' src/ | grep -v 'doc(cfg)' | grep -v 'test'
```

## See Also

- [doc-cargo-metadata](./doc-cargo-metadata.md) - docs.rs metadata setup
- [doc-module-inner](./doc-module-inner.md) - Feature flags in module docs
- [doc-include-str](./doc-include-str.md) - Conditional doc includes with cfg_attr
