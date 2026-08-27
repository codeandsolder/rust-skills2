---
name: rust-skills
description: >
  Comprehensive Rust coding guidelines with 324 rules across 26 categories.
  Use when writing, reviewing, or refactoring Rust code. Covers ownership,
  error handling, async patterns, concurrency, unsafe code, API design, memory
  optimization, performance, numeric safety, conversions, serde, pattern
  matching, macros, closures, observability, testing, and common anti-patterns.
  Modernized for Rust 1.98 (2024 edition). Invoke with /rust-skills.
license: MIT
metadata:
  author: leonardomso
  version: "2.0.0"
  sources:
    - Rust API Guidelines
    - Rust Performance Book
    - Rust 2024 Edition Guide
    - The Rustonomicon
    - ripgrep, tokio, serde, polars, axum, cargo codebases
    - This Week in Rust 2024-2026
    - blog.rust-lang.org release posts 1.85-1.98
---

# Rust Best Practices

Comprehensive guide for writing high-quality, idiomatic, and highly optimized Rust code. Contains 324 rules across 26 categories, prioritized by impact to guide LLMs in code generation and refactoring. Current for Rust 1.98 (2024 edition).

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
| 1 | Ownership & Borrowing | CRITICAL | `own-` | 16 |
| 2 | Error Handling | CRITICAL | `err-` | 17 |
| 3 | Memory Optimization | CRITICAL | `mem-` | 22 |
| 4 | Unsafe Code | CRITICAL | `unsafe-` | 8 |
| 5 | API Design | HIGH | `api-` | 20 |
| 6 | Async/Await | HIGH | `async-` | 21 |
| 7 | Concurrency | HIGH | `conc-` | 4 |
| 8 | Compiler Optimization | HIGH | `opt-` | 14 |
| 9 | Numeric & Arithmetic Safety | HIGH | `num-` | 5 |
| 10 | Type Safety | MEDIUM | `type-` | 17 |
| 11 | Trait & Generics Design | MEDIUM | `trait-` | 7 |
| 12 | Conversions | MEDIUM | `conv-` | 3 |
| 13 | Const & Compile-Time | MEDIUM | `const-` | 4 |
| 14 | Serde | MEDIUM | `serde-` | 8 |
| 15 | Pattern Matching | MEDIUM | `pat-` | 5 |
| 16 | Macros | MEDIUM | `macro-` | 8 |
| 17 | Closures | MEDIUM | `closure-` | 6 |
| 18 | Collections | MEDIUM | `coll-` | 4 |
| 19 | Naming Conventions | MEDIUM | `name-` | 18 |
| 20 | Testing | MEDIUM | `test-` | 21 |
| 21 | Documentation | MEDIUM | `doc-` | 16 |
| 22 | Observability | MEDIUM | `obs-` | 7 |
| 23 | Performance Patterns | MEDIUM | `perf-` | 18 |
| 24 | Project Structure | LOW | `proj-` | 17 |
| 25 | Clippy & Linting | LOW | `lint-` | 18 |
| 26 | Anti-patterns | REFERENCE | `anti-` | 20 |

---

## Quick Reference

### 1. Ownership & Borrowing (CRITICAL)

- [`own-borrow-over-clone`](rules/own-borrow-over-clone.md) - Borrow when a callee only needs temporary access; clone when the API genuinely needs an independent owned value
- [`own-slice-over-vec`](rules/own-slice-over-vec.md) - Accept `&[T]` not `&Vec<T>`, `&str` not `&String`
- [`own-cow-conditional`](rules/own-cow-conditional.md) - Use `Cow<'a, T>` for conditional ownership
- [`own-arc-shared`](rules/own-arc-shared.md) - Use `Arc<T>` when multiple owners may cross thread boundaries; add synchronization only for mutation that actually requires it
- [`own-rc-single-thread`](rules/own-rc-single-thread.md) - Use `Rc<T>` for shared ownership that is confined to one thread
- [`own-refcell-interior`](rules/own-refcell-interior.md) - Use `RefCell<T>` when thread-local shared access genuinely needs runtime-checked interior mutability
- [`own-mutex-interior`](rules/own-mutex-interior.md) - Use the right `Mutex<T>` for the execution model: `std`/`parking_lot` for synchronous code, `tokio::sync::Mutex` for async code
- [`own-rwlock-readers`](rules/own-rwlock-readers.md) - Use the right `RwLock<T>` when reads significantly outnumber writes
- [`own-copy-small`](rules/own-copy-small.md) - Implement `Copy` for small, simple types
- [`own-clone-explicit`](rules/own-clone-explicit.md) - Use explicit `Clone` for types where copying has meaningful cost
- [`own-move-large`](rules/own-move-large.md) - Borrow large values when ownership transfer is unnecessary; use indirection when it solves a real layout, location, or ownership problem—not from a fixed byte threshold
- [`own-lifetime-elision`](rules/own-lifetime-elision.md) - Rely on lifetime elision rules; add explicit lifetimes only when required
- [`own-cell-update`](rules/own-cell-update.md) - Use `Cell::update` (Rust 1.88+) for concise single-threaded read-transform-write updates on `Copy` values
- [`own-cow-rpit-edition2024`](rules/own-cow-rpit-edition2024.md) - Edition 2024 RPIT lifetime capture makes `Cow<'_, T>` returns from methods borrowing `&self` dramatically more ergonomic
- [`own-range-copy`](rules/own-range-copy.md) - Use `core::range::Range` (Rust 1.96+) when `Copy` range values are useful; keep `core::ops::Range` for legacy iterator and API interoperability
- [`own-lazy-init`](rules/own-lazy-init.md) - Use `LazyLock` for thread-safe lazy statics and `LazyCell` for local or thread-local lazy values; use `OnceLock`/`OnceCell` when initialization is imperative rather than tied to one initializer

### 2. Error Handling (CRITICAL)

- [`err-thiserror-lib`](rules/err-thiserror-lib.md) - Use `thiserror` for library error types
- [`err-anyhow-app`](rules/err-anyhow-app.md) - Use `anyhow` for application error handling
- [`err-result-over-panic`](rules/err-result-over-panic.md) - Return `Result<T, E>` instead of panicking for recoverable errors
- [`err-context-chain`](rules/err-context-chain.md) - Add context with `.context()` or `.with_context()`
- [`err-no-unwrap-prod`](rules/err-no-unwrap-prod.md) - Avoid `unwrap()` in production code; use `?`, `expect()`, or handle errors
- [`err-expect-bugs-only`](rules/err-expect-bugs-only.md) - Use `expect()` only for invariants that indicate bugs, not user errors
- [`err-question-mark`](rules/err-question-mark.md) - Use `?` when a fallible operation should short-circuit through the surrounding error context
- [`err-from-impl`](rules/err-from-impl.md) - Implement `From<E>` for error conversions to enable `?` operator
- [`err-source-chain`](rules/err-source-chain.md) - Preserve error chains with `#[source]` or `source()` method
- [`err-lowercase-msg`](rules/err-lowercase-msg.md) - Start error messages lowercase, no trailing punctuation
- [`err-doc-errors`](rules/err-doc-errors.md) - Document meaningful `Err` conditions in a `# Errors` section
- [`err-custom-type`](rules/err-custom-type.md) - Define custom error types for domain-specific failures
- [`err-clippy-unwrap-types`](rules/err-clippy-unwrap-types.md) - Configure `allow-unwrap-types` to whitelist safe `unwrap()` calls while keeping real `unwrap_used` violations
- [`err-diagnostic-do-not-recommend`](rules/err-diagnostic-do-not-recommend.md) - Use `#[diagnostic::do_not_recommend]` on trait impls whose appearance in diagnostics would mislead users
- [`err-expect-not-allow`](rules/err-expect-not-allow.md) - Prefer `#[expect(...)]` over `#[allow(...)]` for suppressing lint warnings
- [`err-no-std-error`](rules/err-no-std-error.md) - Use `core::error::Error` for `no_std` error types with thiserror 2.0+
- [`err-try-block-experimental`](rules/err-try-block-experimental.md) - `try {}` blocks remain nightly-only; prefer stable `Result`/`Option` contexts unless the scoped expression is worth the nightly dependency

### 3. Memory Optimization (CRITICAL)

- [`mem-with-capacity`](rules/mem-with-capacity.md) - Use `with_capacity()` when size is known
- [`mem-smallvec`](rules/mem-smallvec.md) - Use `SmallVec` for usually-small collections
- [`mem-arrayvec`](rules/mem-arrayvec.md) - Use `ArrayVec<T, N>` for fixed-capacity collections that never heap-allocate
- [`mem-box-large-variant`](rules/mem-box-large-variant.md) - Box large enum variants to reduce overall enum size
- [`mem-boxed-slice`](rules/mem-boxed-slice.md) - Use `Box<[T]>` instead of `Vec<T>` for fixed-size heap data
- [`mem-thinvec`](rules/mem-thinvec.md) - Use `ThinVec<T>` for nullable collections with minimal overhead
- [`mem-clone-from`](rules/mem-clone-from.md) - Use `clone_from()` to reuse allocations when repeatedly cloning
- [`mem-reuse-collections`](rules/mem-reuse-collections.md) - Reuse collection capacity across repeated temporary workloads when allocation behavior or profiling shows it is worthwhile
- [`mem-avoid-format`](rules/mem-avoid-format.md) - Avoid `format!()` when string literals work
- [`mem-write-over-format`](rules/mem-write-over-format.md) - Use `write!()` into existing buffers instead of `format!()` allocations
- [`mem-arena-allocator`](rules/mem-arena-allocator.md) - Use arena allocators for batch allocations
- [`mem-zero-copy`](rules/mem-zero-copy.md) - Use zero-copy patterns with slices and `Bytes`
- [`mem-compact-string`](rules/mem-compact-string.md) - Use compact string types for memory-constrained string storage
- [`mem-smaller-integers`](rules/mem-smaller-integers.md) - Use appropriately-sized integers to reduce memory footprint
- [`mem-assert-type-size`](rules/mem-assert-type-size.md) - Assert type size when it is a real ABI, memory-budget, or measured performance constraint; prefer upper bounds when exact layout is not required
- [`mem-take-replace`](rules/mem-take-replace.md) - Use `mem::take` / `mem::replace` to move a value out of a `&mut` without cloning
- [`mem-drop-order`](rules/mem-drop-order.md) - Know and control drop order: struct fields drop top-to-bottom, locals in reverse
- [`mem-arc-str`](rules/mem-arc-str.md) - Prefer `Arc<str>` over `Arc<String>` for thread-shared immutable strings
- [`mem-box-new-uninit`](rules/mem-box-new-uninit.md) - Use `Box::new_uninit()` when you genuinely need deferred or in-place heap initialization; call `assume_init()` only after the allocation contains a valid `T`
- [`mem-ecow-clone-heavy`](rules/mem-ecow-clone-heavy.md) - Use `EcoString` for clone-heavy string workloads
- [`mem-hotpath-profile`](rules/mem-hotpath-profile.md) - Profile memory before optimizing
- [`mem-slotmap-arena`](rules/mem-slotmap-arena.md) - Use `SlotMap` for generation-checked stable keys; use `DenseSlotMap` when densely stored values and fast iteration are important

### 4. Unsafe Code (CRITICAL)

- [`unsafe-safety-comment`](rules/unsafe-safety-comment.md) - Write a `// SAFETY:` comment above every `unsafe` block and a `# Safety` section in every `unsafe fn`.
- [`unsafe-minimize-scope`](rules/unsafe-minimize-scope.md) - Keep `unsafe` blocks as small as possible — mark only the operation that requires unsafety, not the surrounding safe code.
- [`unsafe-miri-ci`](rules/unsafe-miri-ci.md) - Run `cargo miri test` in CI for every crate that contains `unsafe` code.
- [`unsafe-maybeuninit`](rules/unsafe-maybeuninit.md) - Use `MaybeUninit<T>` for uninitialized memory; never use `mem::uninitialized()` or `mem::zeroed()` for types with validity invariants.
- [`unsafe-extern-block`](rules/unsafe-extern-block.md) - In Rust 2024, use `unsafe extern { }` blocks and mark an item `safe` only when every safe Rust caller can satisfy its contract.
- [`unsafe-send-sync-manual`](rules/unsafe-send-sync-manual.md) - Justify manual `Send`/`Sync` from invariants enforced by the type and its dependencies, not from hoped-for caller behavior
- [`unsafe-no-mangle-unsafe`](rules/unsafe-no-mangle-unsafe.md) - In Rust 2024, write `#[unsafe(no_mangle)]`, `#[unsafe(export_name = "...")]`, and `#[unsafe(link_section = "...")]` — not the bare attribute forms.
- [`unsafe-strict-provenance`](rules/unsafe-strict-provenance.md) - Prefer strict provenance APIs (`ptr.addr()`, `ptr.map_addr()`, `ptr.with_addr()`) over integer-pointer round-tripping (`as usize` / `as *const T`); prefer raw borrow syntax (`&raw const x` / `&raw mut x`) over `addr_of!` / `addr_of_mut!`.

### 5. API Design (HIGH)

- [`api-builder-pattern`](rules/api-builder-pattern.md) - Use Builder pattern for complex construction
- [`api-builder-must-use`](rules/api-builder-must-use.md) - Mark consuming builder methods or the builder type `#[must_use]` when ignoring the returned builder is likely a bug
- [`api-newtype-safety`](rules/api-newtype-safety.md) - Use newtypes when identical representation hides meaning the compiler should distinguish
- [`api-typestate`](rules/api-typestate.md) - Use typestate pattern to encode state machine invariants in the type system
- [`api-sealed-trait`](rules/api-sealed-trait.md) - Use sealed traits to prevent external implementations while allowing use
- [`api-extension-trait`](rules/api-extension-trait.md) - Use extension traits to add methods to external types
- [`api-parse-dont-validate`](rules/api-parse-dont-validate.md) - Parse weakly typed input into invariant-bearing domain types at system boundaries instead of repeatedly validating primitives downstream
- [`api-impl-into`](rules/api-impl-into.md) - Accept `impl Into<T>` for flexible APIs, implement `From<T>` for conversions
- [`api-impl-asref`](rules/api-impl-asref.md) - Use `AsRef<T>` when you only need to borrow the inner data
- [`api-must-use`](rules/api-must-use.md) - Add `#[must_use]` when silently discarding a value is plausibly a bug; rely on the built-in `unused_must_use` semantics instead of treating every return value alike
- [`api-non-exhaustive`](rules/api-non-exhaustive.md) - Use `#[non_exhaustive]` on public enums and structs for forward compatibility
- [`api-from-not-into`](rules/api-from-not-into.md) - Implement `From<T>`, not `Into<U>` - From gives you Into for free
- [`api-default-impl`](rules/api-default-impl.md) - Implement `Default` for types with sensible default values
- [`api-common-traits`](rules/api-common-traits.md) - Implement standard traits (Debug, Clone, PartialEq, etc.) for public types
- [`api-serde-optional`](rules/api-serde-optional.md) - Make serde optional in general-purpose libraries when serialization is not part of the core API
- [`api-impl-fromiterator`](rules/api-impl-fromiterator.md) - Implement `FromIterator` and `Extend` for collection types, and `IntoIterator` for all three reference forms
- [`api-operator-overload`](rules/api-operator-overload.md) - Overload operators only when the semantics are natural and unsurprising
- [`api-bon-builder`](rules/api-bon-builder.md) - Use `bon` when typestate builders for structs or functions improve the API; account for proc-macro and typestate compile cost
- [`api-do-not-recommend`](rules/api-do-not-recommend.md) - Use `#[diagnostic::do_not_recommend]` (Rust 1.85.0) to hide blanket impls from compiler diagnostics
- [`api-nutype-validated`](rules/api-nutype-validated.md) - Use `nutype` when generated sanitization, validation, and invariant-preserving trait impls materially simplify a public newtype API

### 6. Async/Await (HIGH)

- [`async-tokio-runtime`](rules/async-tokio-runtime.md) - Start with Tokio's default runtime configuration; choose runtime flavor and tuning from execution requirements and measurements
- [`async-no-lock-await`](rules/async-no-lock-await.md) - Avoid holding blocking mutex guards across `.await`; keep async-lock critical sections small, but hold an async mutex across `.await` when the protected resource invariant genuinely requires it.
- [`async-spawn-blocking`](rules/async-spawn-blocking.md) - Use `spawn_blocking` for blocking synchronous work; bound CPU-heavy work or use a dedicated CPU pool such as Rayon
- [`async-tokio-fs`](rules/async-tokio-fs.md) - Use `tokio::fs` for ordinary filesystem operations from async code; use dedicated async types for pipes/devices and other special files
- [`async-cancellation-token`](rules/async-cancellation-token.md) - Use `CancellationToken` for graceful shutdown and task cancellation
- [`async-join-parallel`](rules/async-join-parallel.md) - Use `join!` / `try_join!` for a fixed set of independent futures; they run concurrently on one task, not in parallel by themselves
- [`async-try-join`](rules/async-try-join.md) - Use `try_join!` for a fixed set of fallible futures that should run concurrently and stop when one returns an error
- [`async-select-racing`](rules/async-select-racing.md) - Use `select!` to race futures and handle the first to complete
- [`async-bounded-channel`](rules/async-bounded-channel.md) - Use bounded channels to apply backpressure and prevent unbounded memory growth
- [`async-mpsc-queue`](rules/async-mpsc-queue.md) - Use `mpsc` channels for async message queues between tasks
- [`async-broadcast-pubsub`](rules/async-broadcast-pubsub.md) - Use `broadcast` channel for pub/sub where all subscribers receive all messages
- [`async-watch-latest`](rules/async-watch-latest.md) - Use `watch` channel for sharing the latest value with multiple observers
- [`async-oneshot-response`](rules/async-oneshot-response.md) - Use `oneshot` channel for request-response patterns
- [`async-joinset-structured`](rules/async-joinset-structured.md) - Use `JoinSet` for managing dynamic collections of spawned tasks with structured concurrency
- [`async-clone-before-await`](rules/async-clone-before-await.md) - Clone Arc/Rc data before await points to avoid holding references across suspension
- [`async-fn-in-trait`](rules/async-fn-in-trait.md) - Use native `async fn` in traits (stable 1.75) instead of the `async_trait` macro
- [`async-async-fn-bounds`](rules/async-async-fn-bounds.md) - Use `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce` bounds instead of `F: Fn() -> Fut, Fut: Future`
- [`async-cancel-safety`](rules/async-cancel-safety.md) - Ensure futures used in `tokio::select!` branches are cancellation-safe
- [`async-blocking-detection`](rules/async-blocking-detection.md) - Detect async worker stalls with latency/console instrumentation; treat blocking-pool metrics as pool pressure, not proof that async workers are blocked
- [`async-runtime-metrics`](rules/async-runtime-metrics.md) - Use `RuntimeMetrics` for task health, blocking thread pressure, and starvation detection
- [`async-structured-concurrency`](rules/async-structured-concurrency.md) - Combine `JoinSet` + `CancellationToken` + `select!` for structured async task management

### 7. Concurrency (HIGH)

- [`conc-rayon-par-iter`](rules/conc-rayon-par-iter.md) - Use rayon's `par_iter()` for CPU-bound data parallelism
- [`conc-scoped-threads`](rules/conc-scoped-threads.md) - Use `std::thread::scope` to borrow stack data across threads
- [`conc-atomic-ordering`](rules/conc-atomic-ordering.md) - Use the weakest correct memory `Ordering` for every atomic operation
- [`conc-thread-local`](rules/conc-thread-local.md) - Prefer `thread_local!` with `Cell`/`RefCell` over `static mut`

### 8. Compiler Optimization (HIGH)

- [`opt-inline-small`](rules/opt-inline-small.md) - Use `#[inline]` for small hot functions
- [`opt-inline-always-rare`](rules/opt-inline-always-rare.md) - Use `#[inline(always)]` sparingly—only for critical hot paths proven by profiling
- [`opt-inline-never-cold`](rules/opt-inline-never-cold.md) - Use `#[inline(never)]` and `#[cold]` for error paths and rarely-executed code
- [`opt-cold-unlikely`](rules/opt-cold-unlikely.md) - Mark unlikely code paths with `#[cold]` to help compiler optimization
- [`opt-likely-hint`](rules/opt-likely-hint.md) - Use `cold_path()` and `select_unpredictable` for branch hints on stable Rust
- [`opt-lto-release`](rules/opt-lto-release.md) - Enable LTO in release builds
- [`opt-codegen-units`](rules/opt-codegen-units.md) - Set `codegen-units = 1` for maximum optimization in release builds
- [`opt-pgo-profile`](rules/opt-pgo-profile.md) - Use Profile-Guided Optimization (PGO) for maximum performance
- [`opt-target-cpu`](rules/opt-target-cpu.md) - Use `target-cpu=native` (or `x86-64-v3`) for maximum performance on known deployment targets
- [`opt-bounds-check`](rules/opt-bounds-check.md) - Use iterators and patterns that eliminate bounds checks in hot paths
- [`opt-simd-portable`](rules/opt-simd-portable.md) - Start with autovectorization; use stable SIMD crates or carefully dispatched `#[target_feature]` code when measurement justifies it.
- [`opt-cache-friendly`](rules/opt-cache-friendly.md) - Organize data for cache-efficient access patterns
- [`opt-cold-path`](rules/opt-cold-path.md) - Use `core::hint::cold_path()` to mark unlikely inline paths (Rust 1.95+)
- [`opt-select-unpredictable`](rules/opt-select-unpredictable.md) - Use `core::hint::select_unpredictable()` for branchless conditional moves (Rust 1.88+)

### 9. Numeric & Arithmetic Safety (HIGH)

- [`num-overflow-explicit`](rules/num-overflow-explicit.md) - Handle integer overflow explicitly: `checked_`/`saturating_`/`wrapping_`/`overflowing_`
- [`num-cast-try-from`](rules/num-cast-try-from.md) - Avoid `as` for narrowing casts; use `From` for widening and `TryFrom` for narrowing
- [`num-float-compare`](rules/num-float-compare.md) - Use approximate comparison when you mean numerical closeness; use exact equality for exact semantics and `total_cmp` for total ordering
- [`num-saturating-clamp`](rules/num-saturating-clamp.md) - Bound values with `clamp` and saturating arithmetic
- [`num-nonzero`](rules/num-nonzero.md) - Use `NonZero*` types to forbid zero and unlock the niche optimization

### 10. Type Safety (MEDIUM)

- [`type-newtype-ids`](rules/type-newtype-ids.md) - Wrap semantically distinct IDs in distinct types, and encode additional invariants such as non-zero values at construction
- [`type-newtype-validated`](rules/type-newtype-validated.md) - Put durable domain invariants behind checked constructors so downstream code can rely on the type instead of re-validating primitives
- [`type-enum-states`](rules/type-enum-states.md) - Use enums for mutually exclusive states
- [`type-option-nullable`](rules/type-option-nullable.md) - Use `Option<T>` when absence is an ordinary state; use `Result<T, E>` when callers need failure information
- [`type-result-fallible`](rules/type-result-fallible.md) - Use `Result<T, E>` for fallible operations
- [`type-phantom-marker`](rules/type-phantom-marker.md) - Use `PhantomData` for zero-cost type markers
- [`type-never-diverge`](rules/type-never-diverge.md) - Use the never type `!` for functions that never return
- [`type-generic-bounds`](rules/type-generic-bounds.md) - Put each trait bound on the API surface that actually requires it
- [`type-no-stringly`](rules/type-no-stringly.md) - Replace durable stringly-typed states and identifiers with enums or domain types, while keeping text parsing at system boundaries
- [`type-repr-transparent`](rules/type-repr-transparent.md) - Use `#[repr(transparent)]` when a wrapper intentionally needs the wrapped field's layout and ABI
- [`type-deref-coercion`](rules/type-deref-coercion.md) - Implement `Deref`/`DerefMut` only for smart-pointer and transparent wrapper types
- [`type-display-vs-debug`](rules/type-display-vs-debug.md) - Use `Display` for user-facing output and `Debug` for diagnostics; never swap them
- [`type-numeric-fmt`](rules/type-numeric-fmt.md) - Implement `LowerHex`, `UpperHex`, `Octal`, and `Binary` for numeric newtypes
- [`type-derive-more-boilerplate`](rules/type-derive-more-boilerplate.md) - Use `derive_more` for newtype boilerplate reduction
- [`type-newtype-repr-transparent`](rules/type-newtype-repr-transparent.md) - Use `#[repr(transparent)]` only when a newtype intentionally promises the wrapped field's layout or ABI
- [`type-nonzero-intrinsics`](rules/type-nonzero-intrinsics.md) - Use `NonZero<T>` when zero is invalid, and use only operations whose result semantics preserve that invariant
- [`type-nutype-validated`](rules/type-nutype-validated.md) - Use validated newtypes to make invalid states unrepresentable; `nutype` is useful when generated constructors and invariant-preserving trait impls justify a proc macro

### 11. Trait & Generics Design (MEDIUM)

- [`trait-associated-type-vs-generic`](rules/trait-associated-type-vs-generic.md) - Use an associated type when each impl has exactly one output type; use a generic parameter when a type can implement the trait for many input types
- [`trait-blanket-impl`](rules/trait-blanket-impl.md) - Use a blanket impl `impl<T: Bound> Trait for T` to give behaviour to every type that satisfies a bound
- [`trait-coherence-newtype`](rules/trait-coherence-newtype.md) - Respect the orphan rule; wrap a foreign type in a newtype to implement a foreign trait on it
- [`trait-default-methods`](rules/trait-default-methods.md) - Define a trait in terms of a few required methods plus defaulted ones built on top of them
- [`trait-dyn-vs-generic`](rules/trait-dyn-vs-generic.md) - Choose static dispatch (generics / `impl Trait`) vs dynamic dispatch (`dyn Trait`) deliberately
- [`trait-object-safety`](rules/trait-object-safety.md) - Keep a trait dyn-compatible (object-safe) when you need `dyn Trait`
- [`trait-upcasting`](rules/trait-upcasting.md) - Prefer implicit trait object upcasting over hand-written `as_supertrait` helpers (Rust 1.86+)

### 12. Conversions (MEDIUM)

- [`conv-tryfrom-fallible`](rules/conv-tryfrom-fallible.md) - Implement `TryFrom` for fallible conversions instead of ad-hoc conversion functions
- [`conv-fromstr-parsing`](rules/conv-fromstr-parsing.md) - Implement `FromStr` to enable `str::parse` for string-to-type conversions
- [`conv-asmut-mutable`](rules/conv-asmut-mutable.md) - Accept `impl AsMut<T>` for flexible mutable borrowed inputs instead of concrete mutable references

### 13. Const & Compile-Time (MEDIUM)

- [`const-block`](rules/const-block.md) - Use inline `const { }` blocks for compile-time evaluation and assertions
- [`const-fn`](rules/const-fn.md) - Make functions `const fn` when they can run at compile time
- [`const-generics`](rules/const-generics.md) - Parameterize over values with const generics `<const N: usize>`
- [`const-vs-static`](rules/const-vs-static.md) - Use `const` for an inlined value and `static` for a single addressed instance

### 14. Serde (MEDIUM)

- [`serde-rename-all`](rules/serde-rename-all.md) - Match the external naming convention with `#[serde(rename_all = ...)]`
- [`serde-default-compat`](rules/serde-default-compat.md) - Use `#[serde(default)]` for optional and backward-compatible fields
- [`serde-skip-empty`](rules/serde-skip-empty.md) - Omit empty fields with `skip_serializing_if`
- [`serde-flatten`](rules/serde-flatten.md) - Inline nested structs or capture extra keys with `#[serde(flatten)]`
- [`serde-enum-representation`](rules/serde-enum-representation.md) - Choose enum tagging deliberately: externally, internally, adjacently tagged, or untagged
- [`serde-deny-unknown-fields`](rules/serde-deny-unknown-fields.md) - Reject unexpected keys with `#[serde(deny_unknown_fields)]`
- [`serde-custom-with`](rules/serde-custom-with.md) - Customize a field's (de)serialization with `with` / `serialize_with` / `deserialize_with`
- [`serde-try-from-validate`](rules/serde-try-from-validate.md) - Validate while deserializing with `#[serde(try_from = "Raw")]`

### 15. Pattern Matching (MEDIUM)

- [`pat-let-else`](rules/pat-let-else.md) - Use `let ... else` for early-return pattern extraction
- [`pat-matches-macro`](rules/pat-matches-macro.md) - Use `matches!()` for boolean pattern tests
- [`pat-if-let-chains`](rules/pat-if-let-chains.md) - Use `if let` / `while let` chains to combine pattern bindings and conditions
- [`pat-exhaustive-enum`](rules/pat-exhaustive-enum.md) - Match owned enums exhaustively; avoid catch-all `_` that hides new variants
- [`pat-at-bindings`](rules/pat-at-bindings.md) - Use `@` bindings to capture a value while matching it against a pattern

### 16. Macros (MEDIUM)

- [`macro-prefer-functions`](rules/macro-prefer-functions.md) - Reach for a macro only when a function or generic cannot express it
- [`macro-rules-hygiene`](rules/macro-rules-hygiene.md) - Rely on `macro_rules!` hygiene and use `$crate` for paths to your crate's items
- [`macro-fragment-specifiers`](rules/macro-fragment-specifiers.md) - Capture with precise fragment specifiers, not raw `:tt`, where you can
- [`macro-export-crate-path`](rules/macro-export-crate-path.md) - Export declarative macros with `#[macro_export]` and a clean import path
- [`macro-private-helpers`](rules/macro-private-helpers.md) - Hide macro-generated helper items behind a `#[doc(hidden)] pub mod __private`
- [`macro-proc-two-crate`](rules/macro-proc-two-crate.md) - Put procedural macros in a dedicated `proc-macro = true` crate and re-export from the facade
- [`macro-proc-syn-quote`](rules/macro-proc-syn-quote.md) - Put proc-macro parsing and generation in testable `syn`/`quote` helpers
- [`macro-proc-error-spans`](rules/macro-proc-error-spans.md) - Turn expected proc-macro input errors into spanned compile errors instead of panics

### 17. Closures (MEDIUM)

- [`closure-fn-trait-bounds`](rules/closure-fn-trait-bounds.md) - Require the least restrictive `Fn` trait a callback needs (`FnOnce` ⊇ `FnMut` ⊇ `Fn`)
- [`closure-impl-fn-return`](rules/closure-impl-fn-return.md) - Return closures as `impl Fn`/`FnMut`/`FnOnce`, not `Box<dyn Fn>`
- [`closure-move-capture`](rules/closure-move-capture.md) - Use `move` for closures that outlive the current scope; clone before `move` to keep the original
- [`closure-static-vs-dyn`](rules/closure-static-vs-dyn.md) - Accept `impl Fn` (generic) for hot callbacks; use `&dyn Fn`/`Box<dyn Fn>` to cut code size or to store them
- [`closure-disjoint-capture`](rules/closure-disjoint-capture.md) - Capture only what you use; lean on edition-2021 disjoint closure captures
- [`closure-async-closures`](rules/closure-async-closures.md) - Use async closures when a callback future needs to borrow from closure captures; use `AsyncFn*` bounds for higher-order async callbacks

### 18. Collections (MEDIUM)

- [`coll-binaryheap`](rules/coll-binaryheap.md) - Use `BinaryHeap` for a priority queue or repeated max-extraction
- [`coll-map-choice`](rules/coll-map-choice.md) - Pick the map by access pattern: `HashMap` (fast, unordered), `BTreeMap` (sorted / range queries), `IndexMap` (insertion order)
- [`coll-seq-choice`](rules/coll-seq-choice.md) - Default to `Vec`; use `VecDeque` for queue/deque behaviour; avoid `LinkedList`
- [`coll-set-membership`](rules/coll-set-membership.md) - Use `HashSet`/`BTreeSet` for membership tests and dedup, not linear `Vec::contains`

### 19. Naming Conventions (MEDIUM)

- [`name-types-camel`](rules/name-types-camel.md) - Use `UpperCamelCase` for structs, enums, traits, type aliases, and other type-level names
- [`name-variants-camel`](rules/name-variants-camel.md) - Use `UpperCamelCase` for enum variants
- [`name-funcs-snake`](rules/name-funcs-snake.md) - Use `snake_case` for functions, methods, variables, and modules
- [`name-consts-screaming`](rules/name-consts-screaming.md) - Use `SCREAMING_SNAKE_CASE` for constants and statics
- [`name-lifetime-short`](rules/name-lifetime-short.md) - Use short, conventional lifetime names: `'a`, `'b`, `'de`, `'src`
- [`name-type-param-single`](rules/name-type-param-single.md) - Use single uppercase letters for type parameters: `T`, `E`, `K`, `V`
- [`name-as-free`](rules/name-as-free.md) - `as_` prefix: free reference conversion
- [`name-to-expensive`](rules/name-to-expensive.md) - Use `to_` prefix for expensive conversions that allocate or compute
- [`name-into-ownership`](rules/name-into-ownership.md) - Use `into_` prefix for ownership-consuming conversions
- [`name-no-get-prefix`](rules/name-no-get-prefix.md) - Omit get_ prefix for simple getters
- [`name-is-has-bool`](rules/name-is-has-bool.md) - Use `is_`, `has_`, `can_`, `should_` prefixes for boolean-returning methods
- [`name-iter-convention`](rules/name-iter-convention.md) - Use iter/iter_mut/into_iter for iterator methods
- [`name-iter-method`](rules/name-iter-method.md) - Implement `IntoIterator` delegation for `for` loop support
- [`name-iter-type-match`](rules/name-iter-type-match.md) - Name iterator types after their source method
- [`name-acronym-word`](rules/name-acronym-word.md) - Treat acronyms as words in identifiers: `HttpServer`, not `HTTPServer`
- [`name-crate-no-rs`](rules/name-crate-no-rs.md) - Don't suffix crate names with `-rs` or `-rust`
- [`name-feature`](rules/name-feature.md) - Name Cargo features without placeholder words like `abc`, `use-abc`, or `with-abc`
- [`name-word-order`](rules/name-word-order.md) - Keep compound names in a consistent, idiomatic word order

### 20. Testing (MEDIUM)

- [`test-cfg-test-module`](rules/test-cfg-test-module.md) - Put unit tests in `#[cfg(test)] mod tests { }` within each module
- [`test-use-super`](rules/test-use-super.md) - Use `use super::*;` in test modules to access parent module items
- [`test-integration-dir`](rules/test-integration-dir.md) - Put integration tests in the `tests/` directory
- [`test-descriptive-names`](rules/test-descriptive-names.md) - Use descriptive test names that explain what is being tested
- [`test-arrange-act-assert`](rules/test-arrange-act-assert.md) - Structure tests with clear Arrange, Act, Assert sections
- [`test-proptest-properties`](rules/test-proptest-properties.md) - Use proptest for property-based testing
- [`test-mockall-mocking`](rules/test-mockall-mocking.md) - Use mockall for trait mocking
- [`test-mock-traits`](rules/test-mock-traits.md) - Put meaningful external dependencies behind replaceable boundaries when that improves testing
- [`test-fixture-raii`](rules/test-fixture-raii.md) - Use RAII for owned test resources; do not confuse cleanup with safe mutation of process-global state
- [`test-tokio-async`](rules/test-tokio-async.md) - Use `#[tokio::test]` for async tests
- [`test-should-panic`](rules/test-should-panic.md) - Use `#[should_panic]` for tests whose success condition is a deliberate panic
- [`test-criterion-bench`](rules/test-criterion-bench.md) - Use `criterion` for benchmarking (or `divan` for simpler workflows)
- [`test-doctest-examples`](rules/test-doctest-examples.md) - Keep documentation examples as executable doctests
- [`test-loom-concurrency`](rules/test-loom-concurrency.md) - Use `loom` to exhaustively test lock-free and concurrent code
- [`test-snapshot-testing`](rules/test-snapshot-testing.md) - Use snapshot testing (insta) for complex or serialized output
- [`test-assert-matches`](rules/test-assert-matches.md) - Use `assert_matches!` / `debug_assert_matches!` (Rust 1.96+) for pattern-based assertions
- [`test-coverage-llvm-cov`](rules/test-coverage-llvm-cov.md) - Use `cargo-llvm-cov` for LLVM-based code coverage
- [`test-fuzzing-minimal`](rules/test-fuzzing-minimal.md) - Use `cargo-fuzz` for fuzz testing critical functions
- [`test-insta-snapshot`](rules/test-insta-snapshot.md) - Use `insta` for snapshot/approval testing
- [`test-nextest-workflow`](rules/test-nextest-workflow.md) - Use `cargo-nextest` for faster execution and CI partitioning
- [`test-rstest-fixtures`](rules/test-rstest-fixtures.md) - Use `rstest` for parameterized tests, fixtures, and async test setup

### 21. Documentation (MEDIUM)

- [`doc-all-public`](rules/doc-all-public.md) - Document all public items with `///` doc comments
- [`doc-module-inner`](rules/doc-module-inner.md) - Use `//!` for module-level documentation
- [`doc-examples-section`](rules/doc-examples-section.md) - Include `# Examples` with runnable code
- [`doc-errors-section`](rules/doc-errors-section.md) - Include `# Errors` section for fallible functions
- [`doc-panics-section`](rules/doc-panics-section.md) - Include `# Panics` section for functions that can panic
- [`doc-safety-section`](rules/doc-safety-section.md) - Include `# Safety` section for unsafe functions
- [`doc-question-mark`](rules/doc-question-mark.md) - Give doctests a `Result`-returning context when demonstrating `?`
- [`doc-hidden-setup`](rules/doc-hidden-setup.md) - Use `# ` prefix to hide example setup code
- [`doc-intra-links`](rules/doc-intra-links.md) - Use intra-doc links to reference types and items
- [`doc-link-types`](rules/doc-link-types.md) - Use intra-doc links to connect related types and functions
- [`doc-cargo-metadata`](rules/doc-cargo-metadata.md) - Fill `Cargo.toml` metadata for published crates
- [`doc-crate-readme`](rules/doc-crate-readme.md) - Unify the README and crate root docs with `#![doc = include_str!("../README.md")]`
- [`doc-cfg-patterns`](rules/doc-cfg-patterns.md) - Use real `#[cfg(...)]` attributes for availability; on docs.rs, optionally add `doc(cfg)` badges behind `cfg(docsrs)` because `doc_cfg` is still unstable on stable Rust
- [`doc-hidden-public`](rules/doc-hidden-public.md) - Use `#[doc(hidden)]` to omit internal impl details from public docs
- [`doc-include-str`](rules/doc-include-str.md) - Use `#[doc = include_str!("...")]` for embedding external content in documentation
- [`doc-test-edition-2024`](rules/doc-test-edition-2024.md) - Edition 2024 changes for doc tests: combined binary, `standalone_crate`, nested includes, and `$crate`

### 22. Observability (MEDIUM)

- [`obs-tracing-over-log`](rules/obs-tracing-over-log.md) - Use `tracing` for structured, span-aware diagnostics instead of `println!` or bare `log`
- [`obs-library-facade`](rules/obs-library-facade.md) - Libraries emit through the tracing/log facade and never install a subscriber
- [`obs-structured-fields`](rules/obs-structured-fields.md) - Record structured key-value fields, not values interpolated into the message string
- [`obs-instrument-spans`](rules/obs-instrument-spans.md) - Use `#[tracing::instrument]` and spans to attach context to async tasks and requests
- [`obs-levels-filter`](rules/obs-levels-filter.md) - Use log levels meaningfully and filter with `EnvFilter` / `RUST_LOG`
- [`obs-error-chain`](rules/obs-error-chain.md) - Log errors with their full source chain, and log each error exactly once
- [`obs-no-sensitive-data`](rules/obs-no-sensitive-data.md) - Never log secrets or PII; redact or skip them

### 23. Performance Patterns (MEDIUM)

- [`perf-iter-over-index`](rules/perf-iter-over-index.md) - Prefer iterators over manual indexing
- [`perf-iter-lazy`](rules/perf-iter-lazy.md) - Keep iterator pipelines lazy when streaming or short-circuiting is useful; collect only when ownership, reuse, sorting, indexing, or another concrete requirement needs a collection
- [`perf-collect-once`](rules/perf-collect-once.md) - Don't collect intermediate iterators
- [`perf-entry-api`](rules/perf-entry-api.md) - Use entry API for map insert-or-update
- [`perf-drain-reuse`](rules/perf-drain-reuse.md) - Use `drain` or `extract_if` when you need to remove owned elements while retaining the source collection's allocation; do not introduce an intermediate collection unless ownership requires one
- [`perf-extend-batch`](rules/perf-extend-batch.md) - Use `extend`, `extend_from_slice`, or `append` when adding a batch expresses the ownership you want; reserve explicitly when the final size is cheaply known
- [`perf-chain-avoid`](rules/perf-chain-avoid.md) - Avoid chain in hot loops
- [`perf-collect-into`](rules/perf-collect-into.md) - Reuse an existing destination with `clear()` + `extend()` on stable Rust; nightly `Iterator::collect_into` appends like `Extend::extend` and does not clear for you
- [`perf-black-box-bench`](rules/perf-black-box-bench.md) - Use black_box in benchmarks
- [`perf-release-profile`](rules/perf-release-profile.md) - Optimize release profile settings
- [`perf-profile-first`](rules/perf-profile-first.md) - Profile before optimizing
- [`perf-ahash`](rules/perf-ahash.md) - Use a faster hasher (`ahash` / `FxHashMap`) when DoS resistance is not needed
- [`perf-io-buffering`](rules/perf-io-buffering.md) - Wrap `Read`/`Write` in `BufReader`/`BufWriter` for many small operations
- [`perf-array-windows`](rules/perf-array-windows.md) - Use `<[T]>::array_windows` and `<[T]>::as_chunks` for compile-time-size windows
- [`perf-atomic-update`](rules/perf-atomic-update.md) - Use `Atomic*::update` and `try_update` for cleaner compare-and-update loops
- [`perf-copy-range`](rules/perf-copy-range.md) - Treat `Copy` ranges as an ownership and ergonomics choice, not an automatic performance optimization
- [`perf-extract-if`](rules/perf-extract-if.md) - Use `extract_if` for conditional extraction when you need to keep both removed and retained elements
- [`perf-hint-apis`](rules/perf-hint-apis.md) - Use compiler hint APIs only when their semantics match a measured hot path; they are advisory optimizations, not code-generation guarantees

### 24. Project Structure (LOW)

- [`proj-lib-main-split`](rules/proj-lib-main-split.md) - Keep `main.rs` minimal, logic in `lib.rs`
- [`proj-mod-by-feature`](rules/proj-mod-by-feature.md) - Organize modules by feature, not type
- [`proj-flat-small`](rules/proj-flat-small.md) - Keep small projects flat
- [`proj-mod-rs-dir`](rules/proj-mod-rs-dir.md) - Use mod.rs for multi-file modules
- [`proj-pub-crate-internal`](rules/proj-pub-crate-internal.md) - Use pub(crate) for internal APIs
- [`proj-pub-super-parent`](rules/proj-pub-super-parent.md) - Use `pub(super)` when an item declared in a child module must be visible in its parent module scope
- [`proj-pub-use-reexport`](rules/proj-pub-use-reexport.md) - Use pub use for clean public API
- [`proj-prelude-module`](rules/proj-prelude-module.md) - Create prelude module for common imports
- [`proj-bin-dir`](rules/proj-bin-dir.md) - Put multiple binaries in src/bin/
- [`proj-workspace-large`](rules/proj-workspace-large.md) - Use workspaces for large projects
- [`proj-workspace-deps`](rules/proj-workspace-deps.md) - Use workspace dependency inheritance for consistent versions across crates
- [`proj-feature-additive`](rules/proj-feature-additive.md) - Design Cargo features to be additive whenever feature unification can combine them
- [`proj-msrv-declare`](rules/proj-msrv-declare.md) - Declare `rust-version` (MSRV) in Cargo.toml and test it in CI
- [`proj-build-rs-minimal`](rules/proj-build-rs-minimal.md) - Keep `build.rs` minimal, deterministic, and idempotent
- [`proj-lints-table`](rules/proj-lints-table.md) - Use `[lints]` / `[workspace.lints]` for centralized lint configuration
- [`proj-workspace-metadata`](rules/proj-workspace-metadata.md) - Use `[workspace.package]` for shared metadata inheritance
- [`proj-workspace-publish`](rules/proj-workspace-publish.md) - Use `cargo publish --workspace` for native workspace publishing (Rust 1.90+)

### 25. Clippy & Linting (LOW)

- [`lint-deny-correctness`](rules/lint-deny-correctness.md) - Deny clippy::correctness and equivalent rustc lints
- [`lint-warn-suspicious`](rules/lint-warn-suspicious.md) - Enable clippy::suspicious for likely bugs
- [`lint-warn-style`](rules/lint-warn-style.md) - Enable clippy::style for idiomatic code
- [`lint-warn-complexity`](rules/lint-warn-complexity.md) - Enable clippy::complexity for simpler code
- [`lint-warn-perf`](rules/lint-warn-perf.md) - Enable clippy::perf for performance improvements
- [`lint-pedantic-selective`](rules/lint-pedantic-selective.md) - Enable clippy::pedantic selectively
- [`lint-missing-docs`](rules/lint-missing-docs.md) - Warn on missing documentation for public items
- [`lint-unsafe-doc`](rules/lint-unsafe-doc.md) - Document every unsafe operation with the invariant that makes it sound
- [`lint-cargo-metadata`](rules/lint-cargo-metadata.md) - Enable clippy::cargo for published crates
- [`lint-rustfmt-check`](rules/lint-rustfmt-check.md) - Run cargo fmt --check in CI
- [`lint-workspace-lints`](rules/lint-workspace-lints.md) - Configure lints at workspace level for consistent enforcement
- [`lint-cfg-check`](rules/lint-cfg-check.md) - Enable `unexpected_cfgs` and declare known cfgs to catch feature-gate typos
- [`lint-clippy-nursery-selected`](rules/lint-clippy-nursery-selected.md) - Enable high-value `clippy::nursery` lints selectively, not the whole group
- [`lint-cargo-unused-features`](rules/lint-cargo-unused-features.md) - Detect unused feature flags declared in Cargo.toml (`[lints.cargo]`, nightly-only)
- [`lint-dylint-custom`](rules/lint-dylint-custom.md) - Use Dylint for project-specific custom lints without forking clippy
- [`lint-edition-2024`](rules/lint-edition-2024.md) - Track Edition 2024 lints (`unsafe_op_in_unsafe_fn`, `keyword_idents`, etc.)
- [`lint-lints-table`](rules/lint-lints-table.md) - Use the `[lints]` table in `Cargo.toml` for canonical lint configuration (Rust 1.74+)
- [`lint-uplifted`](rules/lint-uplifted.md) - Track clippy lints uplifted into rustc (Rust 1.86-1.96)

### 26. Anti-patterns (REFERENCE)

- [`anti-unwrap-abuse`](rules/anti-unwrap-abuse.md) - Avoid `unwrap()` for recoverable production errors; reserve panics for proven invariants and bugs
- [`anti-expect-lazy`](rules/anti-expect-lazy.md) - Don't use expect for recoverable errors
- [`anti-clone-excessive`](rules/anti-clone-excessive.md) - Don't clone when borrowing works
- [`anti-lock-across-await`](rules/anti-lock-across-await.md) - Avoid holding blocking lock guards across `.await`; async mutex guards may cross `.await` when resource serialization requires it
- [`anti-string-for-str`](rules/anti-string-for-str.md) - Don't accept &String when &str works
- [`anti-vec-for-slice`](rules/anti-vec-for-slice.md) - Don't accept &Vec<T> when &[T] works
- [`anti-index-over-iter`](rules/anti-index-over-iter.md) - Don't use indexing when iterators work
- [`anti-panic-expected`](rules/anti-panic-expected.md) - Don't panic on expected or recoverable errors
- [`anti-empty-catch`](rules/anti-empty-catch.md) - Don't silently ignore errors
- [`anti-over-abstraction`](rules/anti-over-abstraction.md) - Don't over-abstract with excessive generics
- [`anti-premature-optimize`](rules/anti-premature-optimize.md) - Don't optimize before profiling
- [`anti-type-erasure`](rules/anti-type-erasure.md) - Don't use Box<dyn Trait> when impl Trait works
- [`anti-format-hot-path`](rules/anti-format-hot-path.md) - Don't use format! in hot paths
- [`anti-collect-intermediate`](rules/anti-collect-intermediate.md) - Don't collect intermediate iterators
- [`anti-stringly-typed`](rules/anti-stringly-typed.md) - Don't use strings where enums or newtypes provide a meaningful domain type
- [`anti-arc-mutex-everything`](rules/anti-arc-mutex-everything.md) - Don't default to `Arc<Mutex<T>>` for every shared state problem
- [`anti-blocking-async-drop`](rules/anti-blocking-async-drop.md) - Don't block or depend on asynchronous work completing from `Drop` of async types
- [`anti-block-on-async`](rules/anti-block-on-async.md) - Don't call `block_on` from code that is already running asynchronously
- [`anti-deref-overuse`](rules/anti-deref-overuse.md) - Don't use `Deref<Target = InnerType>` for newtype method delegation
- [`anti-unsafe-send-sync`](rules/anti-unsafe-send-sync.md) - Don't use `unsafe impl Send` / `Sync` as a thread-safety shortcut

---

## Recommended Cargo.toml Settings

There is no universally optimal Cargo profile. Start from Cargo's defaults and change settings only for a measured goal. `panic = "abort"` changes panic/unwinding semantics, stripping can reduce diagnostic and profiling information, and fat LTO plus `codegen-units = 1` can substantially increase build time.

A conservative starting point for performance-sensitive release builds is:

```toml
[profile.release]
opt-level = 3
```

Then benchmark the relevant tradeoff before adding settings such as `lto = "thin"`/`"fat"` or `codegen-units = 1`. Choose `panic = "abort"` only when abort-on-panic semantics are acceptable, and choose `strip` based on deployment, crash-reporting, and profiling requirements. Keep benchmark symbols when your profiler needs them.

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
