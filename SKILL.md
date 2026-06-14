---
name: rust-skills
description: >
  Comprehensive Rust coding guidelines with 251 rules across 23 categories.
  Use when writing, reviewing, or refactoring Rust code. Covers ownership,
  error handling, async patterns, concurrency, unsafe code, API design, memory
  optimization, performance, numeric safety, conversions, serde, pattern
  matching, macros, closures, observability, testing, and common anti-patterns.
  Invoke with /rust-skills.
license: MIT
metadata:
  author: leonardomso
  version: "1.4.0"
  sources:
    - Rust API Guidelines
    - Rust Performance Book
    - Rust 2024 Edition Guide
    - The Rustonomicon
    - ripgrep, tokio, serde, polars, axum, cargo codebases
---

# Rust Best Practices

Comprehensive guide for writing high-quality, idiomatic, and highly optimized Rust code. Contains 251 rules across 23 categories, prioritized by impact to guide LLMs in code generation and refactoring. Current for Rust 1.96 (2024 edition).

## When to Apply

Reference these guidelines when:
- Writing new Rust functions, structs, or modules
- Implementing error handling or async code
- Writing concurrent, parallel, or `unsafe` code
- Designing public APIs for libraries
- Reviewing code for ownership/borrowing issues
- Optimizing memory usage or reducing allocations
- Tuning performance for hot paths
- Refactoring existing Rust code

## Rule Categories by Priority

| Priority | Category | Impact | Prefix | Rules |
|----------|----------|--------|--------|-------|
| 1 | Ownership & Borrowing | CRITICAL | `own-` | 12 |
| 2 | Error Handling | CRITICAL | `err-` | 12 |
| 3 | Memory Optimization | CRITICAL | `mem-` | 17 |
| 4 | Unsafe Code | CRITICAL | `unsafe-` | 7 |
| 5 | API Design | HIGH | `api-` | 17 |
| 6 | Async/Await | HIGH | `async-` | 18 |
| 7 | Concurrency | HIGH | `conc-` | 4 |
| 8 | Compiler Optimization | HIGH | `opt-` | 12 |
| 9 | Numeric & Arithmetic | HIGH | `num-` | 5 |
| 10 | Type Safety | MEDIUM | `type-` | 13 |
| 11 | Conversions | MEDIUM | `conv-` | 3 |
| 12 | Serde | MEDIUM | `serde-` | 8 |
| 13 | Pattern Matching | MEDIUM | `pat-` | 5 |
| 14 | Macros | MEDIUM | `macro-` | 8 |
| 15 | Closures | MEDIUM | `closure-` | 5 |
| 16 | Naming Conventions | MEDIUM | `name-` | 16 |
| 17 | Testing | MEDIUM | `test-` | 15 |
| 18 | Documentation | MEDIUM | `doc-` | 12 |
| 19 | Observability | MEDIUM | `obs-` | 7 |
| 20 | Performance Patterns | MEDIUM | `perf-` | 13 |
| 21 | Project Structure | LOW | `proj-` | 14 |
| 22 | Clippy & Linting | LOW | `lint-` | 13 |
| 23 | Anti-patterns | REFERENCE | `anti-` | 15 |

---

## Quick Reference

### 1. Ownership & Borrowing (CRITICAL)

- [`own-borrow-over-clone`](rules/own-borrow-over-clone.md) - Prefer `&T` borrowing over `.clone()`
- [`own-slice-over-vec`](rules/own-slice-over-vec.md) - Accept `&[T]` not `&Vec<T>`, `&str` not `&String`
- [`own-cow-conditional`](rules/own-cow-conditional.md) - Use `Cow<'a, T>` for conditional ownership
- [`own-arc-shared`](rules/own-arc-shared.md) - Use `Arc<T>` for thread-safe shared ownership
- [`own-rc-single-thread`](rules/own-rc-single-thread.md) - Use `Rc<T>` for single-threaded sharing
- [`own-refcell-interior`](rules/own-refcell-interior.md) - Use `RefCell<T>` for interior mutability (single-thread)
- [`own-mutex-interior`](rules/own-mutex-interior.md) - Use `Mutex<T>` for interior mutability (multi-thread)
- [`own-rwlock-readers`](rules/own-rwlock-readers.md) - Use `RwLock<T>` when reads dominate writes
- [`own-copy-small`](rules/own-copy-small.md) - Derive `Copy` for small, trivial types
- [`own-clone-explicit`](rules/own-clone-explicit.md) - Make `Clone` explicit, avoid implicit copies
- [`own-move-large`](rules/own-move-large.md) - Move large data instead of cloning
- [`own-lifetime-elision`](rules/own-lifetime-elision.md) - Rely on lifetime elision when possible

### 2. Error Handling (CRITICAL)

- [`err-thiserror-lib`](rules/err-thiserror-lib.md) - Use `thiserror` for library error types
- [`err-anyhow-app`](rules/err-anyhow-app.md) - Use `anyhow` for application error handling
- [`err-result-over-panic`](rules/err-result-over-panic.md) - Return `Result`, don't panic on expected errors
- [`err-context-chain`](rules/err-context-chain.md) - Add context with `.context()` or `.with_context()`
- [`err-no-unwrap-prod`](rules/err-no-unwrap-prod.md) - Never use `.unwrap()` in production code
- [`err-expect-bugs-only`](rules/err-expect-bugs-only.md) - Use `.expect()` only for programming errors
- [`err-question-mark`](rules/err-question-mark.md) - Use `?` operator for clean propagation
- [`err-from-impl`](rules/err-from-impl.md) - Use `#[from]` for automatic error conversion
- [`err-source-chain`](rules/err-source-chain.md) - Use `#[source]` to chain underlying errors
- [`err-lowercase-msg`](rules/err-lowercase-msg.md) - Error messages: lowercase, no trailing punctuation
- [`err-doc-errors`](rules/err-doc-errors.md) - Document errors with `# Errors` section
- [`err-custom-type`](rules/err-custom-type.md) - Create custom error types, not `Box<dyn Error>`

### 3. Memory Optimization (CRITICAL)

- [`mem-with-capacity`](rules/mem-with-capacity.md) - Use `with_capacity()` when size is known
- [`mem-smallvec`](rules/mem-smallvec.md) - Use `SmallVec` for usually-small collections
- [`mem-arrayvec`](rules/mem-arrayvec.md) - Use `ArrayVec` for bounded-size collections
- [`mem-box-large-variant`](rules/mem-box-large-variant.md) - Box large enum variants to reduce type size
- [`mem-boxed-slice`](rules/mem-boxed-slice.md) - Use `Box<[T]>` instead of `Vec<T>` when fixed
- [`mem-thinvec`](rules/mem-thinvec.md) - Use `ThinVec` for often-empty vectors
- [`mem-clone-from`](rules/mem-clone-from.md) - Use `clone_from()` to reuse allocations
- [`mem-reuse-collections`](rules/mem-reuse-collections.md) - Reuse collections with `clear()` in loops
- [`mem-avoid-format`](rules/mem-avoid-format.md) - Avoid `format!()` when string literals work
- [`mem-write-over-format`](rules/mem-write-over-format.md) - Use `write!()` instead of `format!()`
- [`mem-arena-allocator`](rules/mem-arena-allocator.md) - Use arena allocators for batch allocations
- [`mem-zero-copy`](rules/mem-zero-copy.md) - Use zero-copy patterns with slices and `Bytes`
- [`mem-compact-string`](rules/mem-compact-string.md) - Use `CompactString` for small string optimization
- [`mem-smaller-integers`](rules/mem-smaller-integers.md) - Use smallest integer type that fits
- [`mem-assert-type-size`](rules/mem-assert-type-size.md) - Assert hot type sizes to prevent regressions
- [`mem-take-replace`](rules/mem-take-replace.md) - Use `mem::take`/`mem::replace` to move out of `&mut` without cloning
- [`mem-drop-order`](rules/mem-drop-order.md) - Know and control field/local drop order

### 4. Unsafe Code (CRITICAL)

- [`unsafe-safety-comment`](rules/unsafe-safety-comment.md) - Write a `// SAFETY:` comment above every `unsafe` block
- [`unsafe-minimize-scope`](rules/unsafe-minimize-scope.md) - Keep `unsafe` blocks as small as possible
- [`unsafe-miri-ci`](rules/unsafe-miri-ci.md) - Run `cargo miri test` in CI for crates with `unsafe`
- [`unsafe-maybeuninit`](rules/unsafe-maybeuninit.md) - Use `MaybeUninit<T>`, never `mem::uninitialized()`
- [`unsafe-extern-block`](rules/unsafe-extern-block.md) - Use `unsafe extern { }` blocks in Rust 2024
- [`unsafe-send-sync-manual`](rules/unsafe-send-sync-manual.md) - Document invariants for manual `Send`/`Sync`
- [`unsafe-no-mangle-unsafe`](rules/unsafe-no-mangle-unsafe.md) - Use `#[unsafe(no_mangle)]` in Rust 2024

### 5. API Design (HIGH)

- [`api-builder-pattern`](rules/api-builder-pattern.md) - Use Builder pattern for complex construction
- [`api-builder-must-use`](rules/api-builder-must-use.md) - Add `#[must_use]` to builder types
- [`api-newtype-safety`](rules/api-newtype-safety.md) - Use newtypes for type-safe distinctions
- [`api-typestate`](rules/api-typestate.md) - Use typestate for compile-time state machines
- [`api-sealed-trait`](rules/api-sealed-trait.md) - Seal traits to prevent external implementations
- [`api-extension-trait`](rules/api-extension-trait.md) - Use extension traits to add methods to foreign types
- [`api-parse-dont-validate`](rules/api-parse-dont-validate.md) - Parse into validated types at boundaries
- [`api-impl-into`](rules/api-impl-into.md) - Accept `impl Into<T>` for flexible string inputs
- [`api-impl-asref`](rules/api-impl-asref.md) - Accept `impl AsRef<T>` for borrowed inputs
- [`api-must-use`](rules/api-must-use.md) - Add `#[must_use]` to `Result` returning functions
- [`api-non-exhaustive`](rules/api-non-exhaustive.md) - Use `#[non_exhaustive]` for future-proof enums/structs
- [`api-from-not-into`](rules/api-from-not-into.md) - Implement `From`, not `Into` (auto-derived)
- [`api-default-impl`](rules/api-default-impl.md) - Implement `Default` for sensible defaults
- [`api-common-traits`](rules/api-common-traits.md) - Implement `Debug`, `Clone`, `PartialEq` eagerly
- [`api-serde-optional`](rules/api-serde-optional.md) - Gate `Serialize`/`Deserialize` behind feature flag
- [`api-impl-fromiterator`](rules/api-impl-fromiterator.md) - Implement `FromIterator`/`Extend` for collection types
- [`api-operator-overload`](rules/api-operator-overload.md) - Overload operators only when semantics are natural

### 6. Async/Await (HIGH)

- [`async-tokio-runtime`](rules/async-tokio-runtime.md) - Use Tokio for production async runtime
- [`async-no-lock-await`](rules/async-no-lock-await.md) - Never hold `Mutex`/`RwLock` across `.await`
- [`async-spawn-blocking`](rules/async-spawn-blocking.md) - Use `spawn_blocking` for CPU-intensive work
- [`async-tokio-fs`](rules/async-tokio-fs.md) - Use `tokio::fs` not `std::fs` in async code
- [`async-cancellation-token`](rules/async-cancellation-token.md) - Use `CancellationToken` for graceful shutdown
- [`async-join-parallel`](rules/async-join-parallel.md) - Use `tokio::join!` for parallel operations
- [`async-try-join`](rules/async-try-join.md) - Use `tokio::try_join!` for fallible parallel ops
- [`async-select-racing`](rules/async-select-racing.md) - Use `tokio::select!` for racing/timeouts
- [`async-bounded-channel`](rules/async-bounded-channel.md) - Use bounded channels for backpressure
- [`async-mpsc-queue`](rules/async-mpsc-queue.md) - Use `mpsc` for work queues
- [`async-broadcast-pubsub`](rules/async-broadcast-pubsub.md) - Use `broadcast` for pub/sub patterns
- [`async-watch-latest`](rules/async-watch-latest.md) - Use `watch` for latest-value sharing
- [`async-oneshot-response`](rules/async-oneshot-response.md) - Use `oneshot` for request/response
- [`async-joinset-structured`](rules/async-joinset-structured.md) - Use `JoinSet` for dynamic task groups
- [`async-clone-before-await`](rules/async-clone-before-await.md) - Clone data before await, release locks
- [`async-fn-in-trait`](rules/async-fn-in-trait.md) - Use native `async fn` in traits (1.75+), not `async_trait`
- [`async-async-fn-bounds`](rules/async-async-fn-bounds.md) - Use `AsyncFn` bounds for higher-order async functions
- [`async-cancel-safety`](rules/async-cancel-safety.md) - Ensure `select!` branch futures are cancellation-safe

### 7. Concurrency (HIGH)

- [`conc-rayon-par-iter`](rules/conc-rayon-par-iter.md) - Use rayon's `par_iter()` for CPU-bound data parallelism
- [`conc-scoped-threads`](rules/conc-scoped-threads.md) - Use `std::thread::scope` to borrow stack data across threads
- [`conc-atomic-ordering`](rules/conc-atomic-ordering.md) - Use the weakest correct memory `Ordering`
- [`conc-thread-local`](rules/conc-thread-local.md) - Prefer `thread_local!` over `static mut`

### 8. Compiler Optimization (HIGH)

- [`opt-inline-small`](rules/opt-inline-small.md) - Use `#[inline]` for small hot functions
- [`opt-inline-always-rare`](rules/opt-inline-always-rare.md) - Use `#[inline(always)]` sparingly
- [`opt-inline-never-cold`](rules/opt-inline-never-cold.md) - Use `#[inline(never)]` for cold paths
- [`opt-cold-unlikely`](rules/opt-cold-unlikely.md) - Use `#[cold]` for error/unlikely paths
- [`opt-likely-hint`](rules/opt-likely-hint.md) - Use `likely()`/`unlikely()` for branch hints
- [`opt-lto-release`](rules/opt-lto-release.md) - Enable LTO in release builds
- [`opt-codegen-units`](rules/opt-codegen-units.md) - Use `codegen-units = 1` for max optimization
- [`opt-pgo-profile`](rules/opt-pgo-profile.md) - Use PGO for production builds
- [`opt-target-cpu`](rules/opt-target-cpu.md) - Set `target-cpu=native` for local builds
- [`opt-bounds-check`](rules/opt-bounds-check.md) - Use iterators to avoid bounds checks
- [`opt-simd-portable`](rules/opt-simd-portable.md) - Use portable SIMD for data-parallel ops
- [`opt-cache-friendly`](rules/opt-cache-friendly.md) - Design cache-friendly data layouts (SoA)

### 9. Numeric & Arithmetic Safety (HIGH)

- [`num-overflow-explicit`](rules/num-overflow-explicit.md) - Handle overflow with `checked`/`saturating`/`wrapping`/`overflowing`
- [`num-cast-try-from`](rules/num-cast-try-from.md) - Avoid `as`; use `From` (widening) / `TryFrom` (narrowing)
- [`num-float-compare`](rules/num-float-compare.md) - Don't `==` floats; use tolerance and `total_cmp`
- [`num-saturating-clamp`](rules/num-saturating-clamp.md) - Bound values with `clamp` and saturating ops
- [`num-nonzero`](rules/num-nonzero.md) - Use `NonZero*` to forbid zero and enable the niche

### 10. Type Safety (MEDIUM)

- [`type-newtype-ids`](rules/type-newtype-ids.md) - Wrap IDs in newtypes: `UserId(u64)`
- [`type-newtype-validated`](rules/type-newtype-validated.md) - Newtypes for validated data: `Email`, `Url`
- [`type-enum-states`](rules/type-enum-states.md) - Use enums for mutually exclusive states
- [`type-option-nullable`](rules/type-option-nullable.md) - Use `Option<T>` for nullable values
- [`type-result-fallible`](rules/type-result-fallible.md) - Use `Result<T, E>` for fallible operations
- [`type-phantom-marker`](rules/type-phantom-marker.md) - Use `PhantomData<T>` for type-level markers
- [`type-never-diverge`](rules/type-never-diverge.md) - Use `!` type for functions that never return
- [`type-generic-bounds`](rules/type-generic-bounds.md) - Add trait bounds only where needed
- [`type-no-stringly`](rules/type-no-stringly.md) - Avoid stringly-typed APIs, use enums/newtypes
- [`type-repr-transparent`](rules/type-repr-transparent.md) - Use `#[repr(transparent)]` for FFI newtypes
- [`type-deref-coercion`](rules/type-deref-coercion.md) - Implement `Deref` only for smart-pointer types
- [`type-display-vs-debug`](rules/type-display-vs-debug.md) - `Display` for users, `Debug` for diagnostics
- [`type-numeric-fmt`](rules/type-numeric-fmt.md) - Implement `LowerHex`/`Octal`/`Binary` for numeric newtypes

### 11. Conversions (MEDIUM)

- [`conv-tryfrom-fallible`](rules/conv-tryfrom-fallible.md) - Implement `TryFrom` for fallible conversions
- [`conv-fromstr-parsing`](rules/conv-fromstr-parsing.md) - Implement `FromStr` to enable `.parse()`
- [`conv-asmut-mutable`](rules/conv-asmut-mutable.md) - Accept `impl AsMut<T>` for mutable borrowed inputs

### 12. Serde (MEDIUM)

- [`serde-rename-all`](rules/serde-rename-all.md) - Match external naming with `#[serde(rename_all = ...)]`
- [`serde-default-compat`](rules/serde-default-compat.md) - Use `#[serde(default)]` for optional/back-compat fields
- [`serde-skip-empty`](rules/serde-skip-empty.md) - Omit empty fields with `skip_serializing_if`
- [`serde-flatten`](rules/serde-flatten.md) - Inline structs / capture extras with `#[serde(flatten)]`
- [`serde-enum-representation`](rules/serde-enum-representation.md) - Choose enum tagging deliberately
- [`serde-deny-unknown-fields`](rules/serde-deny-unknown-fields.md) - Reject unexpected keys with `deny_unknown_fields`
- [`serde-custom-with`](rules/serde-custom-with.md) - Customize a field with `with`/`serialize_with`/`deserialize_with`
- [`serde-try-from-validate`](rules/serde-try-from-validate.md) - Validate on deserialize via `#[serde(try_from)]`

### 13. Pattern Matching (MEDIUM)

- [`pat-let-else`](rules/pat-let-else.md) - Use `let ... else` for early-return extraction
- [`pat-matches-macro`](rules/pat-matches-macro.md) - Use `matches!()` for boolean pattern tests
- [`pat-if-let-chains`](rules/pat-if-let-chains.md) - Use `if let` chains (2024 edition)
- [`pat-exhaustive-enum`](rules/pat-exhaustive-enum.md) - Match owned enums exhaustively, avoid catch-all `_`
- [`pat-at-bindings`](rules/pat-at-bindings.md) - Use `@` bindings to capture while matching

### 14. Macros (MEDIUM)

- [`macro-prefer-functions`](rules/macro-prefer-functions.md) - Reach for a macro only when a function/generic can't express it
- [`macro-rules-hygiene`](rules/macro-rules-hygiene.md) - Rely on hygiene; use `$crate` for crate-local paths
- [`macro-fragment-specifiers`](rules/macro-fragment-specifiers.md) - Use precise fragment specifiers, not raw `:tt`
- [`macro-export-crate-path`](rules/macro-export-crate-path.md) - Export with `#[macro_export]` and a clean import path
- [`macro-private-helpers`](rules/macro-private-helpers.md) - Hide macro internals in a `#[doc(hidden)] __private` module
- [`macro-proc-two-crate`](rules/macro-proc-two-crate.md) - Put proc-macros in a dedicated `proc-macro = true` crate
- [`macro-proc-syn-quote`](rules/macro-proc-syn-quote.md) - Build proc-macros with `syn`, `quote`, `proc-macro2`
- [`macro-proc-error-spans`](rules/macro-proc-error-spans.md) - Report proc-macro errors as spanned compile errors

### 15. Closures (MEDIUM)

- [`closure-fn-trait-bounds`](rules/closure-fn-trait-bounds.md) - Require the least restrictive `Fn`/`FnMut`/`FnOnce` bound
- [`closure-impl-fn-return`](rules/closure-impl-fn-return.md) - Return `impl Fn` for static dispatch, not `Box<dyn Fn>`
- [`closure-move-capture`](rules/closure-move-capture.md) - Use `move` for escaping closures; clone before moving
- [`closure-static-vs-dyn`](rules/closure-static-vs-dyn.md) - Generic `impl Fn` for hot paths; `dyn Fn` to store/shrink
- [`closure-disjoint-capture`](rules/closure-disjoint-capture.md) - Capture only the fields you use (2021 edition)

### 16. Naming Conventions (MEDIUM)

- [`name-types-camel`](rules/name-types-camel.md) - Use `UpperCamelCase` for types, traits, enums
- [`name-variants-camel`](rules/name-variants-camel.md) - Use `UpperCamelCase` for enum variants
- [`name-funcs-snake`](rules/name-funcs-snake.md) - Use `snake_case` for functions, methods, modules
- [`name-consts-screaming`](rules/name-consts-screaming.md) - Use `SCREAMING_SNAKE_CASE` for constants/statics
- [`name-lifetime-short`](rules/name-lifetime-short.md) - Use short lowercase lifetimes: `'a`, `'de`, `'src`
- [`name-type-param-single`](rules/name-type-param-single.md) - Use single uppercase for type params: `T`, `E`, `K`, `V`
- [`name-as-free`](rules/name-as-free.md) - `as_` prefix: free reference conversion
- [`name-to-expensive`](rules/name-to-expensive.md) - `to_` prefix: expensive conversion
- [`name-into-ownership`](rules/name-into-ownership.md) - `into_` prefix: ownership transfer
- [`name-no-get-prefix`](rules/name-no-get-prefix.md) - No `get_` prefix for simple getters
- [`name-is-has-bool`](rules/name-is-has-bool.md) - Use `is_`, `has_`, `can_` for boolean methods
- [`name-iter-convention`](rules/name-iter-convention.md) - Use `iter`/`iter_mut`/`into_iter` for iterators
- [`name-iter-method`](rules/name-iter-method.md) - Name iterator methods consistently
- [`name-iter-type-match`](rules/name-iter-type-match.md) - Iterator type names match method
- [`name-acronym-word`](rules/name-acronym-word.md) - Treat acronyms as words: `Uuid` not `UUID`
- [`name-crate-no-rs`](rules/name-crate-no-rs.md) - Crate names: no `-rs` suffix

### 17. Testing (MEDIUM)

- [`test-cfg-test-module`](rules/test-cfg-test-module.md) - Use `#[cfg(test)] mod tests { }`
- [`test-use-super`](rules/test-use-super.md) - Use `use super::*;` in test modules
- [`test-integration-dir`](rules/test-integration-dir.md) - Put integration tests in `tests/` directory
- [`test-descriptive-names`](rules/test-descriptive-names.md) - Use descriptive test names
- [`test-arrange-act-assert`](rules/test-arrange-act-assert.md) - Structure tests as arrange/act/assert
- [`test-proptest-properties`](rules/test-proptest-properties.md) - Use `proptest` for property-based testing
- [`test-mockall-mocking`](rules/test-mockall-mocking.md) - Use `mockall` for trait mocking
- [`test-mock-traits`](rules/test-mock-traits.md) - Use traits for dependencies to enable mocking
- [`test-fixture-raii`](rules/test-fixture-raii.md) - Use RAII pattern (Drop) for test cleanup
- [`test-tokio-async`](rules/test-tokio-async.md) - Use `#[tokio::test]` for async tests
- [`test-should-panic`](rules/test-should-panic.md) - Use `#[should_panic]` for panic tests
- [`test-criterion-bench`](rules/test-criterion-bench.md) - Use `criterion` for benchmarking
- [`test-doctest-examples`](rules/test-doctest-examples.md) - Keep doc examples as executable tests
- [`test-loom-concurrency`](rules/test-loom-concurrency.md) - Use `loom` to exhaustively test concurrent code
- [`test-snapshot-testing`](rules/test-snapshot-testing.md) - Use `insta` for snapshot testing of complex output

### 18. Documentation (MEDIUM)

- [`doc-all-public`](rules/doc-all-public.md) - Document all public items with `///`
- [`doc-module-inner`](rules/doc-module-inner.md) - Use `//!` for module-level documentation
- [`doc-examples-section`](rules/doc-examples-section.md) - Include `# Examples` with runnable code
- [`doc-errors-section`](rules/doc-errors-section.md) - Include `# Errors` for fallible functions
- [`doc-panics-section`](rules/doc-panics-section.md) - Include `# Panics` for panicking functions
- [`doc-safety-section`](rules/doc-safety-section.md) - Include `# Safety` for unsafe functions
- [`doc-question-mark`](rules/doc-question-mark.md) - Use `?` in examples, not `.unwrap()`
- [`doc-hidden-setup`](rules/doc-hidden-setup.md) - Use `# ` prefix to hide example setup code
- [`doc-intra-links`](rules/doc-intra-links.md) - Use intra-doc links: `[Vec]`
- [`doc-link-types`](rules/doc-link-types.md) - Link related types and functions in docs
- [`doc-cargo-metadata`](rules/doc-cargo-metadata.md) - Fill `Cargo.toml` metadata
- [`doc-crate-readme`](rules/doc-crate-readme.md) - Unify README and crate docs with `include_str!`

### 19. Observability (MEDIUM)

- [`obs-tracing-over-log`](rules/obs-tracing-over-log.md) - Use `tracing` for structured, span-aware diagnostics
- [`obs-library-facade`](rules/obs-library-facade.md) - Libraries emit via the facade; only binaries install a subscriber
- [`obs-structured-fields`](rules/obs-structured-fields.md) - Record structured key-value fields, not interpolated messages
- [`obs-instrument-spans`](rules/obs-instrument-spans.md) - Use `#[instrument]`/spans; never hold a span guard across `.await`
- [`obs-levels-filter`](rules/obs-levels-filter.md) - Use meaningful levels and filter with `EnvFilter`/`RUST_LOG`
- [`obs-error-chain`](rules/obs-error-chain.md) - Log the full error source chain, once at the handling boundary
- [`obs-no-sensitive-data`](rules/obs-no-sensitive-data.md) - Never log secrets or PII; redact or skip

### 20. Performance Patterns (MEDIUM)

- [`perf-iter-over-index`](rules/perf-iter-over-index.md) - Prefer iterators over manual indexing
- [`perf-iter-lazy`](rules/perf-iter-lazy.md) - Keep iterators lazy, collect() only when needed
- [`perf-collect-once`](rules/perf-collect-once.md) - Don't `collect()` intermediate iterators
- [`perf-entry-api`](rules/perf-entry-api.md) - Use `entry()` API for map insert-or-update
- [`perf-drain-reuse`](rules/perf-drain-reuse.md) - Use `drain()` to reuse allocations
- [`perf-extend-batch`](rules/perf-extend-batch.md) - Use `extend()` for batch insertions
- [`perf-chain-avoid`](rules/perf-chain-avoid.md) - Avoid `chain()` in hot loops
- [`perf-collect-into`](rules/perf-collect-into.md) - Use `collect_into()` for reusing containers
- [`perf-black-box-bench`](rules/perf-black-box-bench.md) - Use `black_box()` in benchmarks
- [`perf-release-profile`](rules/perf-release-profile.md) - Optimize release profile settings
- [`perf-profile-first`](rules/perf-profile-first.md) - Profile before optimizing
- [`perf-ahash`](rules/perf-ahash.md) - Use `ahash`/`FxHashMap` when DoS resistance isn't needed
- [`perf-io-buffering`](rules/perf-io-buffering.md) - Wrap I/O in `BufReader`/`BufWriter`

### 21. Project Structure (LOW)

- [`proj-lib-main-split`](rules/proj-lib-main-split.md) - Keep `main.rs` minimal, logic in `lib.rs`
- [`proj-mod-by-feature`](rules/proj-mod-by-feature.md) - Organize modules by feature, not type
- [`proj-flat-small`](rules/proj-flat-small.md) - Keep small projects flat
- [`proj-mod-rs-dir`](rules/proj-mod-rs-dir.md) - Use `mod.rs` for multi-file modules
- [`proj-pub-crate-internal`](rules/proj-pub-crate-internal.md) - Use `pub(crate)` for internal APIs
- [`proj-pub-super-parent`](rules/proj-pub-super-parent.md) - Use `pub(super)` for parent-only visibility
- [`proj-pub-use-reexport`](rules/proj-pub-use-reexport.md) - Use `pub use` for clean public API
- [`proj-prelude-module`](rules/proj-prelude-module.md) - Create `prelude` module for common imports
- [`proj-bin-dir`](rules/proj-bin-dir.md) - Put multiple binaries in `src/bin/`
- [`proj-workspace-large`](rules/proj-workspace-large.md) - Use workspaces for large projects
- [`proj-workspace-deps`](rules/proj-workspace-deps.md) - Use workspace dependency inheritance
- [`proj-feature-additive`](rules/proj-feature-additive.md) - Design Cargo features to be strictly additive
- [`proj-msrv-declare`](rules/proj-msrv-declare.md) - Declare `rust-version` (MSRV) and test it in CI
- [`proj-build-rs-minimal`](rules/proj-build-rs-minimal.md) - Keep `build.rs` minimal and deterministic

### 22. Clippy & Linting (LOW)

- [`lint-deny-correctness`](rules/lint-deny-correctness.md) - `#![deny(clippy::correctness)]`
- [`lint-warn-suspicious`](rules/lint-warn-suspicious.md) - `#![warn(clippy::suspicious)]`
- [`lint-warn-style`](rules/lint-warn-style.md) - `#![warn(clippy::style)]`
- [`lint-warn-complexity`](rules/lint-warn-complexity.md) - `#![warn(clippy::complexity)]`
- [`lint-warn-perf`](rules/lint-warn-perf.md) - `#![warn(clippy::perf)]`
- [`lint-pedantic-selective`](rules/lint-pedantic-selective.md) - Enable `clippy::pedantic` selectively
- [`lint-missing-docs`](rules/lint-missing-docs.md) - `#![warn(missing_docs)]`
- [`lint-unsafe-doc`](rules/lint-unsafe-doc.md) - `#![warn(clippy::undocumented_unsafe_blocks)]`
- [`lint-cargo-metadata`](rules/lint-cargo-metadata.md) - `#![warn(clippy::cargo)]` for published crates
- [`lint-rustfmt-check`](rules/lint-rustfmt-check.md) - Run `cargo fmt --check` in CI
- [`lint-workspace-lints`](rules/lint-workspace-lints.md) - Configure lints at workspace level
- [`lint-cfg-check`](rules/lint-cfg-check.md) - Enable `unexpected_cfgs` to catch cfg typos
- [`lint-clippy-nursery-selected`](rules/lint-clippy-nursery-selected.md) - Enable high-value `clippy::nursery` lints selectively

### 23. Anti-patterns (REFERENCE)

- [`anti-unwrap-abuse`](rules/anti-unwrap-abuse.md) - Don't use `.unwrap()` in production code
- [`anti-expect-lazy`](rules/anti-expect-lazy.md) - Don't use `.expect()` for recoverable errors
- [`anti-clone-excessive`](rules/anti-clone-excessive.md) - Don't clone when borrowing works
- [`anti-lock-across-await`](rules/anti-lock-across-await.md) - Don't hold locks across `.await`
- [`anti-string-for-str`](rules/anti-string-for-str.md) - Don't accept `&String` when `&str` works
- [`anti-vec-for-slice`](rules/anti-vec-for-slice.md) - Don't accept `&Vec<T>` when `&[T]` works
- [`anti-index-over-iter`](rules/anti-index-over-iter.md) - Don't use indexing when iterators work
- [`anti-panic-expected`](rules/anti-panic-expected.md) - Don't panic on expected/recoverable errors
- [`anti-empty-catch`](rules/anti-empty-catch.md) - Don't use empty `if let Err(_) = ...` blocks
- [`anti-over-abstraction`](rules/anti-over-abstraction.md) - Don't over-abstract with excessive generics
- [`anti-premature-optimize`](rules/anti-premature-optimize.md) - Don't optimize before profiling
- [`anti-type-erasure`](rules/anti-type-erasure.md) - Don't use `Box<dyn Trait>` when `impl Trait` works
- [`anti-format-hot-path`](rules/anti-format-hot-path.md) - Don't use `format!()` in hot paths
- [`anti-collect-intermediate`](rules/anti-collect-intermediate.md) - Don't `collect()` intermediate iterators
- [`anti-stringly-typed`](rules/anti-stringly-typed.md) - Don't use strings for structured data

---

## Recommended Cargo.toml Settings

```toml
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = true

[profile.bench]
inherits = "release"
debug = true
strip = false

[profile.dev]
opt-level = 0
debug = true

[profile.dev.package."*"]
opt-level = 3  # Optimize dependencies in dev
```

---

## How to Use

This skill provides rule identifiers for quick reference. When generating or reviewing Rust code:

1. **Check relevant category** based on task type
2. **Apply rules** with matching prefix
3. **Prioritize** CRITICAL > HIGH > MEDIUM > LOW
4. **Read rule files** in `rules/` for detailed examples

### Rule Application by Task

| Task | Primary Categories |
|------|-------------------|
| New function | `own-`, `err-`, `name-`, `pat-` |
| New struct/API | `api-`, `type-`, `conv-`, `doc-` |
| Async code | `async-`, `own-` |
| Concurrency / parallelism | `conc-`, `async-`, `own-` |
| Unsafe code | `unsafe-`, `type-`, `test-` |
| Error handling | `err-`, `api-`, `pat-` |
| Type conversions | `conv-`, `api-` |
| Serialization (serde) | `serde-`, `type-`, `api-` |
| Numeric / arithmetic | `num-`, `type-` |
| Macros / code generation | `macro-`, `anti-` |
| Closures / callbacks | `closure-`, `type-` |
| Logging / observability | `obs-`, `err-` |
| Memory optimization | `mem-`, `own-`, `perf-` |
| Performance tuning | `opt-`, `mem-`, `perf-` |
| Code review | `anti-`, `lint-` |

---

## Sources & Attribution

This skill is an independent synthesis of official Rust guidance, well-known books, and patterns from widely-used crates. It is not affiliated with or endorsed by the Rust project or any crate author; the text and code examples are original.

**Official Rust documentation**
- [The Rust Reference](https://doc.rust-lang.org/reference/)
- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- [The Rustonomicon](https://doc.rust-lang.org/nomicon/) (unsafe code)
- [Rust 2024 Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/)
- [The Cargo Book](https://doc.rust-lang.org/cargo/)
- [Standard library docs](https://doc.rust-lang.org/std/) and [release notes](https://doc.rust-lang.org/releases.html)

**Books & guides**
- [The Rust Performance Book](https://nnethercote.github.io/perf-book/) — Nicholas Nethercote
- [Rust Design Patterns](https://rust-unofficial.github.io/patterns/) — rust-unofficial
- [Rust Atomics and Locks](https://marabos.nl/atomics/) — Mara Bos
- [Effective Rust](https://effective-rust.com/) — David Drysdale

**Tooling**
- [Clippy lint documentation](https://rust-lang.github.io/rust-clippy/)
- [Miri](https://github.com/rust-lang/miri)

**Real-world codebases studied for idioms**
- ripgrep, tokio, serde, clap, polars, axum, cargo, hyper, bevy, rayon, and dtolnay's crates (thiserror, anyhow, syn)

This project is MIT-licensed. Referenced upstream materials remain under their own licenses (the official Rust docs and API Guidelines are dual MIT / Apache-2.0).
