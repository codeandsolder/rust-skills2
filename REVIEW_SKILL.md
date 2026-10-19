# rust-skills2 — single-file review corpus

325 Rust rules across 26 categories, optimized for long-context automatic code review. Generated from `rules/*.md`; edit the source rules, not this file.

## Review contract

Apply only rules whose preconditions are present in the code under review. Treat category priority as review order, not as permission to ignore lower-priority correctness issues. Prefer concrete defects over stylistic churn, and do not invent compatibility, MSRV, performance, or API requirements.

Trace behavior and ownership before style. Check boundary and malformed inputs, overflow, partial I/O, cancellation, shutdown, concurrency, and unsafe invariants when relevant. A rule's conditions and exceptions are part of the rule; do not mechanically apply its headline.

For each finding, identify the rule ID, exact location/trigger, consequence, and smallest robust fix. Do not emit a finding merely to demonstrate that a rule was considered. Distinguish proven defects from hypotheses that need measurement or additional context.

This corpus removes fenced teaching examples, example commentary, `See Also` lists, bibliographies, and tangents explicitly marked as unrelated. It retains every rule ID and summary plus compact rationale, decision criteria, caveats, and normative guidance.

## Category order

| # | Category | Impact | Prefix | Rules |
|---:|---|---|---|---:|
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
| 26 | Anti-patterns | REFERENCE | `anti-` | 21 |

## 1. Ownership & Borrowing (CRITICAL)

### `own-borrow-over-clone` — Borrow when a callee only needs temporary access; clone when the API genuinely needs an independent owned value

A clone is an ownership operation, not merely a performance smell. For types such as `String`, `Vec<T>`, or `Arc<T>`, cloning can allocate, copy elements, or update shared-ownership state. A borrow states a different contract: the callee may access the caller's value for a limited lifetime but does not become an owner.
Prefer the contract the operation actually needs. Avoiding every clone at all costs can make APIs harder to use, lengthen borrows, or force awkward lifetime plumbing.
- Prefer: Borrow Read-Only Inputs
- Clone When Ownership Must Outlive the Borrow
- Prefer Moving When the Caller No Longer Needs the Value
- Clone the Smallest Thing That Must Become Owned
**Review Questions:**
Before calling `.clone()`, ask:
- Does the recipient need ownership, or only temporary read/write access?
- Could the caller move the value instead because it is done with it?
- If ownership is required, can a smaller field/subvalue be cloned?
- Is the clone needed to cross a thread/task/storage lifetime boundary?
- Would avoiding the clone create an awkward long-lived borrow that harms the API?
The goal is clear ownership, not a zero-clone score.

### `own-slice-over-vec` — Accept borrowed views such as `&[T]`, `&str`, and `&Path` when the implementation only needs a view

A parameter typed as `&Vec<T>` unnecessarily requires the caller to own a `Vec<T>`. A parameter typed as `&[T]` accepts a vector, array, boxed slice, subslice, and other sources that can provide a slice. The same principle applies to `&String` versus `&str`, and usually to `&PathBuf` versus `&Path`.
Use the narrowest borrowed interface that expresses what the function actually needs. Accept an owned type when the function needs ownership, capacity-specific operations, or another property that the borrowed view does not provide.
- Prefer: Borrow the View You Need
- Accept Ownership When You Need Ownership
**Decision Guide:**
| Need | Typical parameter |
|---|---|
| Read/write a sequence without owning it | `&[T]` / `&mut [T]` |
| Read text without owning it | `&str` |
| Read a filesystem path | `&Path` |
| Store or consume a vector/string/path | owned `Vec<T>` / `String` / `PathBuf` |
| Need vector-specific capacity/push behavior | `&Vec<T>` / `&mut Vec<T>` only when those semantics are genuinely required |
| Convenience over several path-like input types | sometimes `impl AsRef<Path>` |

### `own-cow-conditional` — Use `Cow<'a, B>` when an API can usually borrow data but sometimes needs an owned value

`std::borrow::Cow` represents either borrowed data (`Cow::Borrowed`) or the corresponding owned form (`Cow::Owned`). It is useful when the common path can return or carry a borrow while an uncommon path must allocate/own.
`Cow` does not magically remove allocations: producing an owned variant still has the owned type's cost, and mutating a borrowed value through `to_mut()` clones it first. Use it when those semantics match the API, not merely because an allocation might exist somewhere.
- Prefer: Borrow on the Common Path, Own When Needed
- When `Cow` Is the Wrong Shape
**Practical Guidance:**
- Use `Cow` when “borrow most of the time, own sometimes” is the real data model.
- Prefer `Borrowed` when the output can safely reference existing data.
- Use `to_mut()` when mutation should clone a borrowed value on demand.
- Use `into_owned()` only when the caller truly needs the owned representation.
- Do not attribute direct `Cow<'_, T>` lifetime elision to Edition-2024 RPIT capture.
- Benchmark when `Cow` is justified primarily by performance rather than API semantics.

### `own-arc-shared` — Use `Arc<T>` when multiple owners may cross thread boundaries; add synchronization only for mutation that actually requires it

`Arc<T>` provides atomic reference-counted shared ownership. Cloning an `Arc` clones the ownership handle, not the underlying `T`, and the allocation remains alive until the last strong owner is dropped.
`Arc` makes ownership thread-safe; it does **not** make arbitrary interior mutation safe. Whether `Arc<T>` is `Send`/`Sync` still depends on `T`, and shared mutation generally needs an appropriate synchronization primitive or an internally thread-safe type.
- Avoid: `Rc` Across Threads
- Prefer: Shared Immutable Data With `Arc`
- Shared Mutation: Choose the Synchronization Semantics
- Mutate Before Sharing When You Still Have Unique Ownership
- Do Not Build Ad-Hoc Atomic `Arc` Containers From Raw Pointers

### `own-rc-single-thread` — Use `Rc<T>` for shared ownership that is confined to one thread

`Rc<T>` provides reference-counted ownership without atomic reference-count operations. It is intentionally `!Send` and `!Sync`, so the type system prevents an `Rc` ownership graph from crossing thread boundaries.
Choose `Rc` when the ownership model is genuinely single-threaded. Choose `Arc` when owners must cross threads. Do not select either solely from a blanket performance rule; the threading and ownership contract comes first.
- Avoid: Pay for Thread-Safe Ownership You Do Not Need
- Prefer: Single-Threaded Shared Ownership
- Interior Mutability When the Graph Needs Mutation

### `own-refcell-interior` — Use `RefCell<T>` when thread-local shared access genuinely needs runtime-checked interior mutability

`RefCell<T>` lets code mutate a value through a shared reference by moving Rust's usual borrow checks from compile time to runtime. A shared borrow comes from `borrow()` and an exclusive borrow from `borrow_mut()`; violating the same aliasing rules that ordinary references enforce causes a panic (or a `BorrowError` / `BorrowMutError` with the `try_` methods).
This is useful for caches, graph-like ownership, test doubles, callbacks, and other cases where the program can uphold borrowing discipline but the static borrow checker cannot conveniently express it.
- Avoid: Forcing Exclusive Access to the Whole Owner
- Prefer: Keep the Runtime Borrow Small
- Edition 2024: `if let` Temporaries Are Shorter on the `else` Path
**Choosing an Interior-Mutability Primitive:**
| Need | Typical choice |
|------|----------------|
| `Copy` value, thread-local shared mutation | `Cell<T>` |
| General value, thread-local runtime-checked borrowing | `RefCell<T>` |
| Shared mutation across threads | `Mutex<T>` / `RwLock<T>` |
| Cross-thread scalar/flag/counter | atomic type when its memory-ordering model fits |
Prefer ordinary `&mut T` whenever ownership already gives you exclusive access; runtime borrow checking is useful when it solves an actual ownership shape, not as a default replacement for normal borrowing.

### `own-mutex-interior` — Use the right `Mutex<T>` for the execution model: `std`/`parking_lot` for synchronous code, `tokio::sync::Mutex` for async code

When you need shared mutable state across threads, `Mutex<T>` provides safe interior mutability with synchronization. Unlike `RefCell`, `Mutex` is `Send + Sync` and ensures only one task or thread mutates the data at a time.
The lock choice depends on where the data is used:
**When to Use What:**
| Type | Threading | Overhead | Use Case |
|------|-----------|----------|----------|
| `RefCell<T>` | Single | Minimal | Interior mutability, same thread |
| `std::sync::Mutex<T>` | Multi | Locking | Shared mutable state in synchronous code |
| `tokio::sync::Mutex<T>` | Async multi-task | Awaitable lock | Shared mutable state in async code |
| `RwLock<T>` | Multi | Locking | Many readers, few writers |
| `parking_lot::Mutex<T>` | Multi | Less (narrowed gap) | Synchronous code with contention-sensitive locks |

### `own-rwlock-readers` — Choose `RwLock<T>` when concurrent readers materially help the measured workload, not from a fixed read/write ratio

A `Mutex<T>` permits one lock holder at a time. An `RwLock<T>` permits multiple readers or one exclusive writer. That can improve throughput when read-side concurrency is valuable, but the extra state and scheduling policy are not free.
There is no portable rule such as “use `RwLock` below 20% writes.” The result depends on contention, critical-section duration, core count, implementation, scheduler policy, cache behavior, and latency requirements. Start from semantics, then measure under representative contention.
- Cached Computation: Avoid Assuming One Computation
**Decision Guide:**
Prefer the simplest primitive that expresses the invariant, then benchmark if contention matters:
| Situation | Start by considering |
|---|---|
| Short exclusive critical sections | `Mutex` |
| Multiple simultaneous readers are measurably valuable | `RwLock` |
| One-time initialization | `OnceLock` / `LazyLock` |
| Async acquisition/guard semantics are required | Tokio async lock |
| Read-mostly snapshots with rare replacement | immutable snapshot / copy-on-write designs may avoid shared lock contention |
Read/write percentage alone is not enough information.

### `own-copy-small` — Implement `Copy` for small, simple types

Types that implement `Copy` are implicitly duplicated on assignment instead of moved. This eliminates the need for explicit `.clone()` calls and makes the code more ergonomic. For small types (generally ≤16 bytes), copying is as fast or faster than moving a pointer.
**Copy Requirements:**
A type can implement `Copy` only if: 1. All fields implement `Copy` 2. No custom `Drop` implementation 3. No heap-allocated data (`String`, `Vec`, `Box`, etc.)

### `own-clone-explicit` — Use `Clone` to make non-`Copy` duplication explicit, but do not infer a universal allocation or cost model from `.clone()`

`Copy` and `Clone` primarily describe **semantics**, not a performance tier.
- `Copy` means assignment and argument passing may duplicate the value implicitly instead of moving it. - `Clone` provides an explicit duplication operation through `.clone()`. - Every `Copy` type is also `Clone`, but many `Clone` types are not `Copy`.
- Move When the Caller Is Done With the Value
- Clone When You Need Two Owned Values
- Borrow When Ownership Is Unnecessary
- Derive `Clone` When Field-Wise Cloning Is the Right Semantics
**Practical Guidance:**
- Move when the caller no longer needs the original value.
- Borrow when the callee does not need ownership.
- Clone when two valid owned values are actually required.
- Treat clone cost as type-specific: inspect the concrete type and workload.
- Use `Arc::clone`/`Rc::clone` to express shared ownership, not as generic “cheap clone” replacements.
- Derive `Clone` when field-wise cloning matches the logical semantics; implement it manually only for a reason.
- Use `clone_from` optimizations only where the concrete implementation supports them meaningfully.

### `own-move-large` — Borrow large values when ownership transfer is unnecessary; use indirection when it solves a real layout, location, or ownership problem—not from a fixed byte threshold

A Rust move transfers ownership. For a non-`Copy` local moved out of a place, the old place becomes deinitialized and cannot be used again until reinitialized. That language rule does **not** promise that every move becomes a runtime `memcpy` of the type's full size: optimization, return-value placement, inlining, and ABI details can eliminate or transform physical copies.
Large inline values can still matter. Passing or rearranging them may increase stack usage, register/memory traffic, enum size, or code-generation pressure in a real program. But boxing purely because a type crosses an arbitrary 128/512/4096-byte threshold can make performance worse by adding allocation, pointer indirection, and poorer locality.
- Prefer Borrowing When Ownership Is Not Needed
- When `Box<T>` Has a Structural Benefit
- Do Not Encode Size Thresholds as Universal Rules
- Prefer Purpose-Specific Rules for Other APIs
**Review Questions:**
Before changing representation, ask:
- Does this function need ownership, or would `&T` / `&mut T` express the contract better?
- Is the problem stack footprint, enum/struct inline size, physical relocation, cache locality, or something else?
- Will boxing add many allocations or pointer chases?
- Does stable heap location itself matter?
- Is there profiler/benchmark evidence that the current representation is a bottleneck?
Change the design for the actual constraint.

### `own-lifetime-elision` — Rely on ordinary lifetime elision where it applies; treat Edition-2024 RPIT capture as a separate rule

Rust has several different mechanisms that can make lifetimes disappear from source code. Two of the most commonly confused are:
- **lifetime elision in reference types**, which assigns omitted lifetimes in function and method signatures; and - **generic capture by return-position `impl Trait` (RPIT)**, which controls which in-scope generic parameters the hidden return type may use.
- Prefer: Let Ordinary Elision Handle Simple Borrows
- Precise Capture with `use<...>`
**Practical Guidance:**
- Omit lifetime names for straightforward one-input/one-output borrows and ordinary receiver-based methods.
- Name lifetimes when you need to state a relationship among multiple borrows or store references in a type.
- Treat `'_` as an anonymous lifetime placeholder, not a magic lifetime extension.
- Treat Edition-2024 RPIT capture separately from reference lifetime elision.
- Do not claim automatic RPIT capture satisfies genuine `'static` requirements.
- Use `use<...>` when you need precise opaque-type capture, especially to avoid Edition-2024 overcapture.
- Prefer compiler/reference-backed rules over version folklore about closure lifetime inference.

### `own-cell-update` — Use `Cell::update` (Rust 1.88+) for concise single-threaded read-transform-write updates on `Copy` values

`Cell::update` expresses the common `get` → transform → `set` pattern directly. It is concise and keeps the transformation in one place.
It is **not an atomic operation** in the concurrency sense. `Cell<T>` provides single-threaded interior mutability and is `!Sync`; use atomic types or synchronization primitives when multiple threads can access the value.
**Key Points:**
- `Cell::update` is a convenience API for single-threaded interior mutation.
- Do not describe it as atomic or synchronizing.
- `Cell` is best for `Copy` values behind shared references in single-threaded code.
- For non-`Copy` interior mutation, consider `RefCell`; for cross-thread mutation, use synchronization designed for that purpose.

### `own-cow-rpit-edition2024` — Edition 2024 simplifies RPIT returns whose hidden type borrows; it does not change ordinary `Cow<'_, T>` return elision

Two independent mechanisms are easy to conflate:
- `fn value(&self) -> Cow<'_, str>` returns the concrete type `Cow`; ordinary lifetime elision/inference handles the placeholder lifetime. - `fn value(&self) -> impl Display` returns an opaque RPIT type. If the hidden concrete type borrows from `self`, the RPIT must capture that lifetime.
- Prefer: Edition 2024 RPIT Can Capture the Receiver Borrow
- Do Not Attribute Ordinary Collections of `Cow` to RPIT
- When `Cow` Is Actually Useful
**Practical Guidance:**
- Do not say Edition 2024 made direct `Cow<'_, T>` method returns possible; those are not RPIT.
- Use Edition-2024 automatic capture when an RPIT hidden type really borrows an in-scope lifetime.
- Keep `+ '_` or use precise `use<...>` when an explicit capture relationship improves compatibility or clarity.
- Do not claim capture satisfies a genuine `'static` requirement.
- Prefer direct `Cow` returns when hiding the concrete type adds no API value.

### `own-range-copy` — Use `core::range::Range` (Rust 1.96+) when `Copy` range values are useful; keep `core::ops::Range` for legacy iterator and API interoperability

The legacy `core::ops::Range<T>` is an iterator whose value itself carries iteration state and deliberately does not implement `Copy`. That is a design choice, not a language rule saying every `Iterator` must be non-`Copy`.
Rust 1.96 stabilized `core::range::Range<T>`, which separates the range value from legacy iterator semantics and can implement `Copy` when `T: Copy`. This is useful when a range is stored as ordinary data inside another `Copy` type.
- Keep Legacy Ranges When Interoperating
**Key Points:**
- `core::ops::Range` being non-`Copy` is deliberate legacy iterator design, not a trait-system impossibility.
- Prefer `core::range::Range` when range values are data and `Copy` semantics are actually useful.
- Prefer compatibility over migration churn when surrounding APIs still use `core::ops` ranges.
- Do not claim a performance win without measurement; the primary benefit is ownership/ergonomics.

### `own-lazy-init` — Use `LazyLock` for thread-safe lazy statics and `LazyCell` for local or thread-local lazy values; use `OnceLock`/`OnceCell` when initialization is imperative rather than tied to one initializer

`LazyLock<T, F>` and `LazyCell<T, F>` pair storage with a single initialization function and run that function on first access. They are convenient when the same value is conceptually “defined here, computed later.”
`LazyLock` is the synchronized form and can be used for ordinary shared statics when its `T`/initializer satisfy the required thread-safety bounds. `LazyCell` is deliberately `!Sync`; it belongs in local or thread-local single-threaded contexts, not as a normal shared `static`.
- Prefer: Thread-Safe Lazy Static
- Prefer: Local `LazyCell`
- When `OnceLock` / `OnceCell` Fits Better
**Decision Guide:**
| Requirement | Typical type |
|---|---|
| Shared thread-safe lazy static | `LazyLock<T>` |
| Local single-threaded lazy value | `LazyCell<T>` |
| Per-thread lazy value | `thread_local!` + `LazyCell<T>` |
| Value provided imperatively once | `OnceLock<T>` / `OnceCell<T>` |
| Value always needed and const-constructible | ordinary `const` / `static` |

## 2. Error Handling (CRITICAL)

### `err-thiserror-lib` — Use `thiserror` to derive typed library errors when it removes boilerplate without hiding the API

Library callers often need structured errors they can match and inspect. `thiserror` derives `Display` and `Error` implementations while leaving the resulting error type as an ordinary enum or struct in your public API.
The crate is a boilerplate tool, not a substitute for error design. Choose meaningful variants, decide which source errors should be exposed, and avoid conversions that erase context.
- Prefer: A Matchable Error Enum

### `err-anyhow-app` — Use `anyhow` at application boundaries when callers need context and reporting more than a stable typed error API

Application code often needs to combine errors from many subsystems and report what operation failed. `anyhow::Result<T>` is useful there because `?` can propagate ordinary error types into one report type, while [`Context`] adds the operation-specific information that low-level errors usually lack.
That does **not** make `anyhow` the right answer for every error boundary. If callers are expected to match variants and recover differently, expose a typed error instead. Public library APIs commonly benefit from typed errors; applications and binaries commonly benefit from `anyhow`, but the architectural requirement matters more than the crate label.
- Avoid: Erasing Errors Without Adding Context
- Prefer: Add Context at the Application Boundary
- `anyhow!`, `bail!`, and `ensure!`
- Choose `context` Versus `with_context`
**Practical Guidance:**
- Use `anyhow` when the main consumer of an error is reporting/logging rather than exhaustive matching.
- Add context at abstraction boundaries: what resource, operation, user/request, or configuration step failed?
- Prefer `with_context` when the message needs formatting or other nontrivial work.
- Keep domain errors typed when callers need stable recovery semantics.
- Do not turn every error into a string before wrapping it; preserving the original error keeps the source chain and downcasting information available.
- When orchestration has already committed durable side effects, pair error propagation with a transaction, delayed publication, compensation, or a durable workflow appropriate to the failure model.
- Before returning an error, neutralize pending mutable state that outer middleware or deferred lifecycle hooks could still persist.

### `err-result-over-panic` — Use `Result<T, E>` for fallible operations; encode invariants explicitly and keep deliberate termination at the application boundary

`Result` makes failure part of the function's contract. Callers can inspect, propagate, retry, substitute a fallback, report, or deliberately terminate.
Panic is appropriate for assertion-style contracts and failures inside code that already has panic semantics, but it should not be the default transport for ordinary errors or a hidden substitute for invariant modeling. In particular, `unwrap()`/`expect()` make panic paths easy to add and hard to audit.
- Avoid: Panic on Runtime Failure
- Prefer: Return the Failure
**Decision Guide:**
| Situation | Usually prefer |
|---|---|
| invalid user/request input | `Result` / validation |
| file, network, service, or parse failure | `Result` |
| optional absence | `Option` or `Result`, depending on semantics |
| internal invariant | encode in type/state; otherwise explicit invariant error |
| caller violates documented precondition | documented assertion/indexing contract |
| test fixture/setup unexpectedly fails | test returns `Result` and uses `?` |
| boundary must contain third-party unwinding | `catch_unwind` when panic strategy permits |
| application cannot start | diagnostic + failure `ExitCode` at outer boundary |
**Practical Guidance:**
- Model fallible operations as return values.
- Do not use `unwrap()`/`expect()` as invariant shorthand.
- Keep process termination policy in the top-level runner.
- Do not use `catch_unwind` as routine error control flow.
- Document intentional public panic contracts.

### `err-context-chain` — Add context at abstraction boundaries so an error says what operation failed as well as why

Low-level errors usually describe the immediate failure, not the application operation that led to it. `No such file or directory` is useful, but `failed to read user record /srv/users/42.json: No such file or directory` is much better.
Context should add **new** information as an error crosses an abstraction boundary. Repeating the same message at every layer only makes reports longer.
- Avoid: Propagate an Opaque Low-Level Error
- Prefer: Describe the Failed Operation
- Avoid Redundant Context
**Practical Guidance:**
- Add context where an error crosses an abstraction boundary.
- Include identifiers and resource names that help diagnose the failure.
- Prefer `with_context` for dynamically constructed messages.
- Preserve the source error instead of flattening it into a string.
- Avoid context layers that merely restate `failed` or duplicate the source message.
- Use typed fields instead of free-form context when callers need programmatic recovery information.

### `err-no-unwrap-prod` — Avoid `unwrap()` and `expect()`; preserve failures explicitly and encode invariants in types

`unwrap()` and `expect()` convert `None` or `Err` into an implicit panic. That is a poor default for user input, I/O, remote services, lookups, parsing, tests, and startup code.
Even when failure would indicate a programmer bug, hidden panic-style extraction makes the failure policy harder to review. For strict AI-maintained code, prefer an explicit error path or a representation that makes the invalid state impossible.

### `err-expect-bugs-only` — Avoid `expect()` even for invariants; encode the invariant, propagate failure, or terminate deliberately at the process boundary

`expect()` is still an implicit panic. A useful message makes the panic easier to diagnose, but it does not make abrupt unwinding a better API or control-flow boundary.
For AI-maintained code, the implementation cost of handling the case explicitly is small. Prefer to make invalid states unrepresentable, preserve failure as `Result`/`Option`, or convert the failure into a clear diagnostic at the application's outer boundary.
- Prefer: Preserve the Failure
- Prefer: Encode the Invariant in the Type
- Prefer: Terminate Deliberately at the Application Boundary
- Prefer: Tests Return Errors Too
**Decision Guide:**
| Situation | Prefer |
|---|---|
| invalid user/request input | validation + `Result` |
| missing/failed external resource | `Result`, retry, or fallback |
| network/service failure | `Result`, retry, or fallback |
| internal invariant | encode it in types/state; otherwise return an explicit invariant error |
| hard-coded source data | infallible constant/constructor where available; otherwise explicit initialization error |
| unsupported startup environment | diagnostic + `ExitCode` at the application boundary |
| test fixture unexpectedly invalid | test returns `Result`, pattern match, or assert on the `Result`/`Option` itself |
**Practical Guidance:**
- Do not mechanically replace `unwrap()` with `expect()`; both hide a panic path.
- Push recoverable failures upward with `?`.
- Push invariant guarantees downward into constructors and types.
- Keep process termination in `main`/the top-level runner where the policy is obvious.
- Prefer returning `ExitCode` from `main` over calling `process::exit` from deep code.
- Tests can return `Result`; benchmarks can print a fatal setup error and return/exit at their harness boundary.

### `err-question-mark` — Use `?` when a fallible operation should short-circuit through the surrounding error context

The `?` operator is Rust's concise syntax for propagating a failure from a compatible return context. For `Result<T, E>`, an `Ok(value)` yields `value`, while an `Err(error)` returns from the surrounding context, converting the error with `From` when needed. `?` also has defined behavior for `Option` and several other standard-library try-like types.
Use it when propagation is the intended control flow. It is not a replacement for handling an error locally, adding context, retrying, or intentionally panicking on an invariant violation.
- Add Context Before Propagating When Needed
**Do Not Duplicate Nightly or Diagnostic Guidance Here:**
Try blocks are still nightly-only; see err-try-block-experimental. Diagnostic shaping with `#[diagnostic::do_not_recommend]` is a separate trait-impl concern; see err-diagnostic-do-not-recommend.

### `err-from-impl` — Implement specific `From<SourceError>` conversions when the conversion is unconditional, unambiguous, and preserves the information callers need

For `Result`, the `?` operator can convert the residual error into the function's return error type. The standard `Result` residual conversion uses `From`, so a suitable `From<SourceError> for AppError` lets `?` propagate the source error without a manual `.map_err(...)` at every call site.
That convenience is valuable only when the conversion has one sensible meaning. Do not add broad `From` implementations merely to make `?` compile: conversions become part of the API and can erase context or make future variants difficult to distinguish.
- Prefer: Specific, Lossless Wrapping
- Avoid Blanket Error Conversions
- `From` Should Be Infallible
**Decision Guide:**
| Conversion shape | Usually prefer |
|---|---|
| one source type maps directly to one error variant | `From` / `#[from]` |
| conversion needs path/request/user context | explicit `map_err` / constructor |
| conversion can fail | `TryFrom` or explicit fallible function |
| arbitrary application errors mainly need reporting | `anyhow`-style report type |
| callers need to distinguish source categories | explicit typed variants |
**Practical Guidance:**
- Add `From` only when the conversion has one unsurprising meaning.
- Preserve the original source error whenever it remains diagnostically useful.
- Use `#[from]` for direct wrappers; use `map_err` when call-site data is required.
- Avoid generic `From<E>` catch-alls for error enums.
- Remember that `?` convenience is a consequence of the error conversion design, not a reason to make the design broader than it should be.

### `err-source-chain` — Preserve underlying causes in the error source chain

Errors often add higher-level context to a lower-level failure. Keeping the original error as a `source()` lets reporters, logs, and callers inspect the chain instead of receiving only a formatted copy of the innermost message.
Converting an error to `String` too early destroys its type, structured fields, and source chain. Keep the error object whenever the underlying cause matters.
- Do Not Invent a Chain for Mere Text

### `err-lowercase-msg` — Keep `Error` display messages concise, usually lowercase, and usually without trailing punctuation so they compose cleanly

Rust's `Error` documentation says error messages are **typically concise lowercase sentences without trailing punctuation**. That convention is useful because error displays are often embedded in larger reports or chained with context.
It is a convention, not a grammar law. Proper nouns, protocol names, acronyms, identifiers, and error codes keep their normal spelling.
- Avoid: Sentence-Style Fragments That Compose Poorly
- Prefer: Concise Error Displays
- Do Not Duplicate the Source in `Display`
**Practical Guidance:**
- Default to concise lowercase phrases without trailing punctuation for error `Display` text.
- Preserve normal spelling for acronyms, proper nouns, identifiers, and codes.
- Describe the current abstraction layer; let `source()` carry the cause chain.
- Avoid rendering the same source both in the outer message and again through a chain-aware reporter unless that duplication is intentional.
- Treat top-level user presentation separately from the composable `Display` text of individual errors.

### `err-doc-errors` — Document meaningful `Err` conditions in a `# Errors` section

Callers need to know which failures an API reports and what they mean. For public fallible functions, a `# Errors` section is the conventional place to describe the conditions that produce `Err`, especially when callers may want to distinguish variants or retry classes.
Document the contract rather than merely restating the return type. If an underlying implementation detail is not part of the API contract, avoid promising its exact error variant unnecessarily.

### `err-custom-type` — Define domain error types when callers benefit from knowing what failed

A custom error type turns failure modes into structured data. Callers can match variants, inspect fields, decide which failures are retryable, and display a human-readable message without parsing strings.
Do not create a bespoke enum merely for ceremony: at a private application boundary, a context-rich dynamic error may be simpler. Typed errors are most valuable where the failure structure is part of an API contract.
- Prefer: Model Distinct Failures
- Preserve Sources When Wrapping Errors
- Choose the Error Shape from the Boundary

### `err-clippy-unwrap-types` — Do not use Clippy's `allow-unwrap-types` to punch type-wide holes in a strict no-unwrap/no-expect policy

Clippy supports an `allow-unwrap-types` configuration list that exempts selected receiver types from `unwrap_used` and `expect_used`.
That is useful in codebases whose policy intentionally permits panic-style extraction for whole classes of values. It is the wrong tradeoff for strict AI-maintained code: a type-wide exemption is easy to grow, hard to review at the call site, and silently preserves hidden panic paths.
- Avoid: Type-Wide Escape Hatch
- Prefer: Keep the Policy Uniform

### `err-diagnostic-do-not-recommend` — Use `#[diagnostic::do_not_recommend]` on trait impls whose appearance in diagnostics would mislead users

Rust 1.85 added `#[diagnostic::do_not_recommend]` as a library-author hint for compiler diagnostics. It tells rustc not to present the annotated **trait implementation** as a suggested path when explaining an unsatisfied trait bound.
This is useful for broad blanket impls, internal adapter impls, or impls whose bounds are usually not something the caller should try to satisfy. It is not specific to errors or `From`, and it does not change trait resolution, coherence, or program semantics.

### `err-expect-not-allow` — Prefer narrow, reasoned `#[expect(...)]` when a suppressible lint reliably fires; use a narrow reasoned `#[allow(...)]` only when lint activation is configuration-dependent and fulfillment semantics cannot work

Rust's `expect` lint level records that a specific lint is supposed to fire. When the lint no longer fires, `unfulfilled_lint_expectations` reports the stale suppression. That makes `#[expect]` the best default for deliberate exceptions to suppressible lints.
There is one important limit: rustc still parses expectations for Clippy lints even when Clippy is not running. A Clippy lint that legitimately fires only under some feature/target configurations can therefore make plain rustc report an unfulfilled expectation. Wrapping the expectation in `cfg(clippy)` is not a clean workaround because Clippy diagnoses that pattern as `unnecessary_clippy_cfg`.
- Keep Stale Expectations Fatal
- Do Not Suppress Whole Groups
- Do Not Suppress High-Signal Categories
**Practical Guidance:**
- Fix before suppressing.
- Never suppress a lint group.
- Never suppress correctness/suspicious/high-risk safety or panic policy lints.
- Prefer `#[expect]` because stale exceptions self-report.
- Use reasoned `#[allow]` only for narrow configuration-dependent exceptions where `#[expect]` cannot have stable fulfillment semantics.
- A reason should describe the API, schema, compatibility, or measured design constraint—not “Clippy complains” or “needed for CI.”

### `err-no-std-error` — Use `core::error::Error` for genuine `no_std` error types; current `thiserror` supports this on Rust 1.81+

`core::error::Error` has been stable since Rust 1.81, so a `no_std` crate can participate in the standard Rust error ecosystem without importing `std`. Current `thiserror` 2.x is itself a `#![no_std]` crate and has an optional `std` feature, enabled by default.
For a genuinely `no_std` dependency configuration on Rust 1.81+, disable that default feature:
- When `alloc` Is Needed

### `err-try-block-experimental` — `try {}` blocks remain nightly-only; prefer stable `Result`/`Option` contexts unless the scoped expression is worth the nightly dependency

A `try { ... }` block creates a local try-propagation context: `?` can short-circuit out of the block rather than out of the enclosing function. This is useful when a function itself should not return the same `Result` or `Option`, but one expression inside it naturally does.
As of Rust 1.98, homogeneous try blocks are still unstable behind `#![feature(try_blocks)]` and are tracked by rust-lang/rust#154391. Do not confuse that feature with RFC 3058 / `try_trait_v2`: the public `Try` and `FromResidual` traits are a separate, still-unstable library API tracked by #84277.
- Prefer: A Scoped Try Context
- When Nightly Try Blocks May Be Worth It

## 3. Memory Optimization (CRITICAL)

### `mem-with-capacity` — Pre-allocate when you have a useful size bound

Growing a `Vec`, `String`, or hash table may require allocating a larger backing store and moving existing contents. When you know a useful lower bound for the final size, reserving it up front can avoid repeated growth work.
Do not confuse **requested allocation size** with **reported capacity**. Rust guarantees that `Vec::with_capacity(n)` asks the allocator for exactly enough bytes for `n` elements, but the allocator may return a larger allocation. Consequently, `Vec::capacity()` is guaranteed to be **at least** `n`, not equal to `n`. Zero-sized element types are another obvious exception to byte-oriented intuition.
**When to Skip Pre-allocation:**
- the collection usually stays tiny;
- the final size is highly uncertain and over-reservation would waste meaningful memory;
- construction is cold and simplicity matters more;
- `collect` or another API already expresses the operation clearly enough and profiling shows no problem.

### `mem-smallvec` — Use `SmallVec` when collections are usually small but may grow

`SmallVec<[T; N]>` stores up to `N` elements inline in the `SmallVec` value and spills to a heap allocation when it grows beyond that inline capacity. This can avoid allocations for the common small case while preserving a Vec-like growable API.
The trade-off is not free: inline storage makes every `SmallVec` value larger, moves can copy that inline storage, and operations must support both inline and spilled representations. Choose `N` from real workload data rather than folklore, and benchmark when this sits on a hot path.
**Choosing Inline Capacity:**
Prefer measurements or domain bounds:
A type alias does not make `4` universally optimal; it documents the capacity chosen for this workload.
**When to Use Alternatives:**
| Situation | Prefer |
|-----------|--------|
| Usually small, occasionally larger | `SmallVec<[T; N]>` |
| Hard maximum, no heap fallback | `ArrayVec<T, N>` |
| Variable/unbounded and allocation is fine | `Vec<T>` |
| Known approximate final length | `Vec::with_capacity(...)` |

### `mem-arrayvec` — Use `ArrayVec<T, N>` when a hard capacity belongs in the type

`ArrayVec<T, N>` from `arrayvec` stores its elements inline in a fixed-size array and never grows onto the heap. Its capacity is the const generic `N`; `push` panics when full, while fallible methods such as `try_push` return a capacity error.
That makes `ArrayVec` useful when a hard upper bound is part of the design—for example bounded protocol fields, embedded/no-alloc code, or small temporary buffers. It is not automatically better than `Vec`: the inline storage is part of every `ArrayVec` value, so a large capacity makes the value itself large regardless of its current length.
- When Not to Use It

### `mem-box-large-variant` — Consider indirection when one enum variant makes every enum value much larger, but measure the workload before paying for a heap allocation

An enum must be large enough and sufficiently aligned for any of its variants. A rarely used large payload can therefore increase the inline size of **every** value of that enum. Boxing that payload replaces the inline data with a pointer-sized field and can improve density in arrays, vectors, queues, and caches.
That trade is not free. `Box<T>` adds an allocation, pointer chasing, allocator metadata/traffic, and another failure boundary at allocation time. If the large variant is common, short-lived, or already behind indirection, boxing can make the program slower while saving little useful memory.
**Practical Guidance:**
- Inspect the actual enum size on supported targets.
- Pay attention to variant frequency, not just maximum payload size.
- Box a large/cold variant when denser inline storage is worth the allocation and indirection.
- Do not turn Clippy's heuristic threshold into a universal design rule.
- Keep recursive-type indirection conceptually separate from large-variant optimization.
- Benchmark the representative collection/workload after changing representation.

### `mem-boxed-slice` — Use `Box<[T]>` when owned heap data has a fixed length and you do not need spare capacity or growth operations

`Vec<T>` represents an owned growable sequence and therefore tracks pointer, length, and capacity. `Box<[T]>` represents an owned fixed-length slice and tracks only the fat-pointer metadata needed for the allocation and length. On common 64-bit targets that often means one fewer machine word in the owner value, but portable code should not assume exact byte counts without checking the target.
The stronger reason to choose `Box<[T]>` is semantic: once construction is complete, the type says that changing the number of elements is not part of the API.
- Do Not Assume Exact `Vec` Capacity
- Avoid Clone-and-Round-Trip Mutation
**When to Use What:**
| Type | Good fit |
|---|---|
| `Vec<T>` | owned sequence that may grow/shrink or benefits from spare capacity |
| `Box<[T]>` | owned fixed-length heap sequence |
| `[T; N]` | fixed length known in the type, with inline storage wherever the value lives |
| `&[T]` | borrowed view; no ownership needed |
| `Arc<[T]>` | fixed-length owned data shared across threads/owners |
Do not describe `[T; N]` as necessarily “stack allocated”: arrays are stored inline in their containing value, which itself may live on the stack, heap, static storage, or elsewhere.
**Practical Guidance:**
- Build with `Vec<T>` when growth is useful, then freeze with `into_boxed_slice()` when the length becomes fixed.
- Do not pre-call `shrink_to_fit()` solely for `into_boxed_slice()`.
- Do not assume `Vec::with_capacity(n)` reports capacity exactly `n`.
- Measure owner layout on supported targets if the metadata bytes matter.
- Keep `Vec<T>` when repeated growth/shrink is part of normal use.
- Use the fixed-length type mainly because it matches semantics; memory savings are workload- and target-dependent.

### `mem-thinvec` — Use `ThinVec<T>` when a pointer-sized collection handle is valuable

`ThinVec<T>` from Mozilla's `thin_vec` crate stores length and capacity in the allocation rather than in the collection value itself. The collection handle is pointer-sized, and the crate guarantees that `ThinVec<T>` and `Option<ThinVec<T>>` have the same size.
That can reduce the size of structs containing many vector fields or large arrays/vectors of collection handles. The trade-off is that accessing length/capacity for a non-empty value involves the allocation header, and every non-zero-capacity `ThinVec` needs that header allocation.
**When to Use It:**
Consider `ThinVec` when: - many collection handles are stored and their inline footprint matters; - most values are empty or small enough that handle density matters; - profiling or layout inspection shows that reducing parent-object size is useful.
Prefer `Vec` when its standard-library guarantees, raw-parts interoperability, or simpler hot-path access are more important.

### `mem-clone-from` — Use `Clone::clone_from` when repeatedly replacing an existing value and the concrete type can profitably reuse its resources

`Clone::clone_from(&mut self, source)` is semantically equivalent to replacing `self` with `source.clone()`, but the `Clone` trait explicitly permits implementors to override it and reuse resources already owned by `self`.
That makes it useful in reuse-heavy loops and buffers, but the optimization is **type-specific**. The trait does not guarantee allocation reuse for every `Clone` type, and a default `clone_from` implementation may be little different from assignment from `clone()`.
- `Vec<T>::clone_from` Explicitly Reuses Allocation When Possible
- Do Not Assume Every Collection Reuses the Same Way
- When It Helps
**Practical Guidance:**
- Reach for `clone_from` when replacing an existing reusable value, not for every clone.
- Remember that reuse is an implementor optimization, not a blanket trait guarantee.
- `Vec<T>::clone_from` is specifically documented to avoid reallocation when possible.
- Delegate custom `clone_from` implementations to fields that already know how to reuse themselves.
- Verify concrete third-party/std implementations before promising allocation behavior.
- Measure instead of quoting fixed speedup numbers.

### `mem-reuse-collections` — Reuse collection capacity across repeated temporary workloads when allocation behavior or profiling shows it is worthwhile

`Vec::clear`, `String::clear`, and `HashMap::clear` remove their current contents while retaining allocated capacity. In a loop whose temporary working set is repeatedly rebuilt to a similar size, that can avoid allocator churn and make capacity growth happen once instead of over and over.
This is a performance technique, not a universal style rule. `Vec::new()` itself does not allocate, small allocations may be cheap, and retaining the largest capacity ever seen can waste memory. Prefer the clearest ownership shape first, then reuse buffers where the allocation pattern matters.
- Avoid: Repeatedly Rebuild a Temporary Destination
- Prefer: Reuse a Scratch `Vec`
- When Fresh Collections Are Better

### `mem-avoid-format` — Avoid creating an intermediate `String` with `format!` when the caller can use a literal, formatting arguments, or an existing output buffer directly

`format!(...)` produces an owned `String`. That is exactly right when you need an owned formatted string. It is unnecessary when the surrounding API can consume a string literal or formatting arguments directly, or when you already have a reusable destination buffer.
The optimization target is the **intermediate owned string**, not formatting syntax itself. Do not replace clear one-off `format!` calls with complicated machinery unless allocation actually matters.
- Static Text: Borrow It When Ownership Is Unnecessary
- When `format!` Is the Right Tool
**Compact String Types Are a Separate Decision:**
A compact-string crate can change the representation of an **owned** string, but it does not make unnecessary formatting disappear. Whether `CompactString`, `EcoString`, `SmartString`, `Box<str>`, or ordinary `String` is appropriate depends on string lengths, mutation/clone patterns, target layout, and interoperability. See mem-compact-string rather than mixing that storage decision into every formatting rule.
**Practical Guidance:**
- Use `&'static str` or `&str` when ownership is not needed.
- Pass formatting arguments directly to logging/printing APIs.
- Use `write!`/`writeln!` when an existing `String` or I/O sink is the real destination.
- Remember that `join("\n")` omits a trailing newline.
- Use `format!` when an owned formatted `String` is exactly the desired result.
- Optimize repeated formatting only after measuring allocation or throughput pressure.

### `mem-write-over-format` — Write formatting directly into the real destination when an intermediate owned `String` would only be copied elsewhere

`format!(...)` creates an owned `String`. That is exactly right when the desired result is a new string. It is avoidable overhead when the program already has a reusable `String`, byte buffer, file, socket, or another formatting-aware destination.
`write!` and `writeln!` let the formatting machinery target that destination directly. This can reduce temporary allocations and copies, but it does not make formatting itself free and it is not automatically faster for every workload.
- Prefer `writeln!` for Line Semantics
- When `format!` Is Exactly Right
- Avoid Double Formatting
**Practical Guidance:**
- Use `format!` when you need a new owned formatted `String`.
- Use `write!`/`writeln!` when the destination already exists.
- Import `std::fmt::Write` for strings and `std::io::Write` for byte/I/O sinks.
- Propagate errors for genuinely fallible I/O destinations.
- Reuse a cleared buffer only when callers do not need previous results to remain independently owned.
- Reserve capacity from a defensible estimate, not a magic constant.
- Measure allocator and end-to-end effects instead of assuming a fixed speedup.

### `mem-arena-allocator` — Use bump arenas when many values share one lifetime and bulk deallocation is more useful than individual destruction

A bump arena allocates values from chunks and advances an allocation cursor. That can make repeated small allocations cheap and lets the arena reclaim its storage in bulk. The model is especially attractive for parse trees, temporary query state, request-scoped scratch data, and other workloads where many allocations naturally die together.
The trade-off is just as important: values allocated directly with `bumpalo::Bump` do **not** have their `Drop` implementations run when the arena is reset or dropped. If an arena value owns a file, socket, mutex guard, heap allocation, mmap, or another resource whose destructor matters, blindly placing it in the arena can leak or delay that resource.
**The Critical Destructor Caveat:**
Directly bump-allocated values are not individually dropped during arena teardown. For plain data that needs no destructor, this is often exactly what you want. For resource-owning values, it can be wrong.
A plain-data node has no destructor-dependent cleanup. By contrast, putting a `String`, `Vec`, file handle, or other resource-owning object directly in the bump means its own destructor will not run automatically when the bump is cleared.
If destructors must run, choose a representation that explicitly manages them. `bumpalo` offers allocator-aware owned/collection types behind crate features, and manual cleanup is also possible, but those choices should be reviewed carefully rather than assumed.
- When Arenas Fit
**Performance Guidance:**
Do not bake numbers such as “arena allocation is 20–50× faster” or “1–2 ns per allocation” into a general rule. Results depend on allocator, element size/alignment, chunk growth, cache state, compiler options, and whether ordinary allocations were optimized away or pooled elsewhere.
Benchmark the operation that matters: parse throughput, request latency, allocation count, resident memory, or cache behavior—not an isolated synthetic allocation unless that is actually the bottleneck.
**Practical Guidance:**
- Start from a shared-lifetime problem, not from a desire to replace every `Box`.
- Remember that direct bump allocations skip `Drop` on reset/arena destruction.
- Use `reset()` only after all arena borrows are gone.
- Distinguish fallible allocation APIs from fallible initializer APIs.
- Do not share one `Bump` concurrently as though it were a synchronized allocator.
- Treat `slotmap` and arenas as different tools: stable keys versus bulk lifetime allocation.
- Measure before claiming a performance win.

### `mem-zero-copy` — Use zero-copy patterns with slices and `Bytes`

Zero-copy means working with data without copying it. Instead of allocating new memory and copying bytes, you work with references to the original data. This dramatically reduces memory usage and improves performance, especially for large data. The `memchr` crate (2.8+) adds portable SIMD substring search on aarch64, x86_64, and wasm32.
Rust 1.98 also makes a common zero-copy parser task easier: once an iterator or parser gives you a substring/subslice borrowed from the original input, `str::substr_range` and `[T]::subslice_range` recover the corresponding range in the original input without searching or hand-written pointer arithmetic.

### `mem-compact-string` — Consider compact or clone-on-write string types when string representation is a measured memory or allocation bottleneck

`String` is an excellent general-purpose owned UTF-8 buffer: it supports growth and exposes familiar capacity semantics. That generality has representation overhead and short strings normally require a separate heap allocation.
Small-string-optimized and clone-on-write crates trade some API and implementation complexity for different storage behavior:
**Keep Representation Choices Behind Ordinary APIs When Practical:**
This keeps a niche storage type internal. A real constructor may reasonably take `&str`, `String`, `impl Into<String>`, or another shape depending on ownership and ergonomics; do not mechanically genericize every public string parameter.
- When Compact Strings Fit
**Practical Guidance:**
- Choose compact strings from workload data, not from a leaderboard of owner sizes.
- Treat inline capacities and layout sizes as crate-version and target properties.
- Distinguish small-string optimization from clone-on-write semantics.
- Keep niche representation types behind ordinary string-oriented API boundaries when practical.
- Measure total allocation and memory effects, not only `size_of`.
- Re-benchmark when crate versions or target architectures change.

### `mem-smaller-integers` — Use appropriately-sized integers to reduce memory footprint

Using `i64` when `i16` suffices wastes 6 bytes per value. In arrays, vectors, and structs with millions of instances, this waste compounds dramatically. Choosing the smallest integer type that fits your domain reduces memory usage and improves cache utilization.

### `mem-assert-type-size` — Assert type size when it is a real ABI, memory-budget, or measured performance constraint; prefer upper bounds when exact layout is not required

A type stored millions of times can become materially more expensive when one field changes its size or alignment. Compile-time size assertions turn that implicit cost into an explicit contract reviewed with the code change.
But `size_of::<T>() == N` is a strong promise. It is appropriate when exact size is genuinely required—for example an FFI/wire layout with an explicitly chosen representation. For ordinary Rust data structures, a maximum-size assertion is often better: it catches a memory regression without pretending that every field offset or ABI detail is stable.
- Avoid: Accidental Exact-Layout Folklore
- Prefer: Compile-Time Memory Budget
- Prefer: Exact Size for an Explicit C Layout
- Avoid `repr(packed)` as a Memory-Optimization Default
- When an Assertion Is Worth It

### `mem-take-replace` — Use `mem::take` / `mem::replace` to move a value out of a `&mut` without cloning

Rust's ownership rules prevent you from moving a field out of a `&mut self` reference — the compiler must guarantee the field is not left in an invalid state. The standard workaround many developers reach for is `.clone()`, but that allocates unnecessarily. `std::mem::take` swaps the field with `T::default()` and returns the original value; `std::mem::replace` swaps in an explicit value of your choosing. Both are zero-copy and work wherever you have `&mut T`.
**Key Points:**
- `mem::take` requires `T: Default`. If `T` has no meaningful default, use `mem::replace` with an explicit sentinel value (e.g., an `Option<T>` field — `mem::take` an `Option<T>` yields `None`, which is often exactly right).
- Both functions are `#[inline]` and compile away to a few register moves with no heap involvement.
- `Option<T>` is a natural pairing: keep expensive values in `Option<T>` and call `self.field.take()` (the `Option::take` method, same idea) to move ownership out cleanly.

### `mem-drop-order` — Know Rust's deterministic destruction order, and make resource dependencies explicit when one value must outlive another

Drop order is observable for RAII resources: lock guards unlock, transactions may roll back or commit, tracing guards close spans, and file/socket wrappers release operating-system resources.
The important design question is not merely “what drops first?” but **which resource must remain alive while another resource is being destroyed or finalized?** Encode that dependency clearly instead of relying on a comment that contradicts the code.
- Explicit `drop` Must Match the Dependency
**Practical Guidance:**
- Model resource dependencies first: which value must outlive which?
- Use local scopes or explicit `drop` for important early release points.
- For structs, remember fields drop in declaration order; document non-obvious dependency ordering.
- Remember a custom `Drop::drop` runs before automatic field destruction.
- Avoid `ManuallyDrop` unless ordinary ownership cannot express the required behavior.
- Do not rely on oversimplified rules for temporary lifetimes; name important guards.

### `mem-arc-str` — Prefer `Arc<str>` over `Arc<String>` for thread-shared immutable strings

`Arc<String>` stores a pointer to a 24-byte `String` (ptr + len + cap), which itself points to the heap-allocated buffer. That's 8 bytes of capacity metadata that is never used once the string is finalized. `Arc<str>` uses a fat pointer (ptr + len on the stack) with no capacity field, saving 8 bytes per shared instance. The same rationale applies as `Box<[T]>` vs `Vec<T>` (see [mem-boxed-slice](mem-boxed-slice.md)).

### `mem-box-new-uninit` — Use `Box::new_uninit()` when you genuinely need deferred or in-place heap initialization; call `assume_init()` only after the allocation contains a valid `T`

`Box::<T>::new_uninit()` (stable since Rust 1.82) allocates space for `T` without first creating a valid `T`. This is useful when an initializer naturally writes into an output pointer, when constructing a very large value field-by-field, or when an FFI routine guarantees that it initializes the entire object.
It is **not** a general-purpose replacement for `Box::new`. Modern Rust can often optimize ordinary construction well, and uninitialized construction moves correctness obligations into `unsafe` code.
- Avoid: Assume Initialization After Only a Partial Write
- Prefer: Initialize Every Field Before `assume_init`
- Prefer `Box::write` When You Already Have a Complete Value
**Performance Guidance:**
Do not attach fixed speedups such as “10× faster” or size thresholds such as “use this above 1 KiB.” Allocation cost, zeroing, copy elision, cache behavior, and the initializer itself vary by allocator, target, optimization level, and workload.
Use `new_uninit` because the initialization contract calls for it or because measurement shows ordinary construction performs avoidable work—not merely because `T` is large.

### `mem-ecow-clone-heavy` — Consider `EcoString` for clone-heavy immutable-or-COW strings

`EcoString` from `ecow` combines small-string inline storage with clone-on-write heap storage. Short strings fit directly in the value. Longer strings spill into a reference-counted `EcoVec<u8>` allocation; cloning a spilled string shares that allocation, and mutation copies only when the allocation is shared.
This can be attractive for parsers, caches, syntax trees, templates, or configuration structures where strings are cloned frequently and mutated relatively rarely. It is a workload trade-off, not a blanket replacement for `String`.
**When to Reach for EcoString:**
| Workload | `String` | `EcoString` |
|----------|----------|-------------|
| Frequent cloning of long strings | Duplicates owned contents | Heap-backed clones share storage |
| Many short strings | Simple standard type | Inline storage may avoid allocation |
| Heavy in-place mutation | Usually straightforward | COW may detach shared storage |
| Public API interoperability | Ubiquitous | Often expose `&str` at boundaries |
Measure real memory/allocation behavior when the choice matters. Representation size, string-length distribution, clone rate, and mutation rate all affect the result.

### `mem-hotpath-profile` — Profile memory before optimizing

Before reaching for compact strings, arena allocators, or exotic collection types, **measure first**. Memory optimization without profiling is guesswork — you might optimize the wrong allocation, or introduce complexity for zero benefit. Profile-guided memory optimization follows the same principle as `perf-profile-first`: understand where the memory goes before rearranging it.

### `mem-slotmap-arena` — Use `SlotMap` for generation-checked stable keys; use `DenseSlotMap` when densely stored values and fast iteration are important

When values need long-lived handles across insertion and removal, raw `usize` indices into a `Vec<T>` are easy to misuse. `swap_remove` can make an old index refer to a different value, while shifting removal invalidates later indices.
The `slotmap` crate solves that problem with generation/version-checked keys. Removing one entry invalidates that key while keys to other live entries continue to identify their original values.
- Avoid: Raw Indices Can Become Stale
- Prefer: `SlotMap` With a Concrete Key Type
- Prefer Custom Key Types for Distinct Domains
**Performance Tradeoffs:**
Do not attach fixed byte-overhead or cache-locality tables to all slot-map variants. The representation is crate-version- and target-dependent, and the variants make different tradeoffs:
- standard `SlotMap`: direct slot lookup; iteration scans holes;
- `DenseSlotMap`: dense live values and fast iteration; keyed lookup performs additional indirection;
- secondary maps: associate data with keys from a primary slot map without making the key itself an owning reference.
Use `Vec<T>` when stable handles/removal safety are unnecessary. A slot map pays for handle validation and metadata to provide semantics a plain vector does not.
- When It Fits

## 4. Unsafe Code (CRITICAL)

### `unsafe-safety-comment` — Write a `// SAFETY:` comment above every `unsafe` block and a `# Safety` section in every `unsafe fn`.

Unsafe blocks are unauditable without justification. A reviewer cannot verify invariants they cannot read. The `clippy::undocumented_unsafe_blocks` lint enforces this mechanically. The standard library, tokio, and bevy all require both forms before merging unsafe code.
There are two distinct levels of documentation:
**Key Points:**
- A `# Safety` doc section and a `// SAFETY:` inline comment serve different audiences: the doc section targets *callers*, the inline comment targets *auditors* of the implementation.
- Enable the lint explicitly to catch omissions:
- When an unsafe block spans multiple operations, write one `// SAFETY:` comment that addresses each distinct invariant, or split into multiple smaller blocks (see `unsafe-minimize-scope`).
- In an `unsafe fn`, the body still requires `// SAFETY:` comments for each inner `unsafe {}` block under the 2024 edition's `unsafe_op_in_unsafe_fn` lint.

### `unsafe-minimize-scope` — Keep `unsafe` blocks as small as possible — mark only the operation that requires unsafety, not the surrounding safe code.

When an entire function is marked `unsafe fn`, every line inside appears equally suspect to an auditor. Shrinking unsafe blocks to the minimum isolates exactly which operation violates Rust's safety invariants, making reviews tractable and bugs easier to find. The Rust 2024 edition enforces this with the `unsafe_op_in_unsafe_fn` lint: unsafe operations inside an `unsafe fn` now require their own explicit `unsafe {}` block rather than inheriting the function's unsafety implicitly.
**Key Points:**
- **2024 edition `unsafe_op_in_unsafe_fn`**: even inside an `unsafe fn`, each unsafe operation now needs its own `unsafe {}`. This is a hard error in Rust 2024.
- A safe wrapper around a small `unsafe {}` is almost always preferable to exposing the entire function as `unsafe fn`.
- Each small unsafe block needs its own `// SAFETY:` comment (see `unsafe-safety-comment`).
- If multiple consecutive lines are all unsafe for the *same* invariant reason, a single block covering only those lines is acceptable.
- When a Larger Block Is Acceptable

### `unsafe-miri-ci` — Run `cargo miri test` in CI for every crate that contains `unsafe` code.

Miri is the only tool that *dynamically* detects undefined behavior in Rust programs at test time. It catches out-of-bounds memory accesses, use-after-free, reads of uninitialized memory, invalid pointer provenance, data races in `unsafe` multithreaded code, and violations of the Stacked Borrows / Tree Borrows aliasing models. The Rust standard library, tokio, serde, and many foundational crates all run Miri in CI before merging changes that touch unsafe code.
Static analysis and code review can miss subtle UB that only manifests at specific memory layouts; Miri's interpreted execution catches it unconditionally.
**Key Points:**
- **Nightly only**: Miri requires a nightly toolchain. Pin a specific nightly date in `rust-toolchain.toml` if you need reproducible CI.
- **Slow**: Miri interprets rather than compiles, so test suites run 100–1000× slower than normal. Run Miri on a reduced set of tests or on a separate slower CI job if the full suite is prohibitive.
- **`MIRIFLAGS`**: `-Zmiri-strict-provenance` enables stricter pointer provenance checks, catching casts that violate the provenance model. Add `-Zmiri-tree-borrows` to opt into the newer Tree Borrows model.
- **Stacked Borrows**: Miri's default aliasing model. It catches violations of Rust's borrow rules at the pointer level — invaluable for raw-pointer and FFI code.
- **Setup command**: `cargo miri setup` pre-builds the Miri sysroot so the first test run is not cold. Run it once per CI cache key.
- Only crates with `unsafe` blocks need Miri coverage. Pure-safe crates gain nothing from it.
- When It's Acceptable to Skip

### `unsafe-maybeuninit` — Use `MaybeUninit<T>` for uninitialized memory; never use `mem::uninitialized()` or `mem::zeroed()` for types with validity invariants.

Producing an invalid value of `T` is undefined behavior even if code intends to overwrite it immediately. `MaybeUninit<T>` lets memory exist before a valid `T` has been constructed there.
The condition for `assume_init` is **not** "every byte has been initialized." Padding bytes may legitimately remain uninitialized. The requirement is that the memory contains a fully initialized value satisfying all of `T`'s validity requirements.
- Prefer: Single Value
- Prefer: Element-by-Element Array Initialization
**Key Points:**
- `MaybeUninit<T>` is the standard representation for memory that may not yet contain a valid `T`.
- `assume_init` requires a valid initialized `T`, not arbitrary initialization of padding bytes.
- Track partial initialization carefully so initialized elements are dropped exactly once on error paths.
- `mem::zeroed()` is sound only for types for which the all-zero bit pattern is valid; prefer APIs that make that invariant explicit.

### `unsafe-extern-block` — In Rust 2024, use `unsafe extern { }` blocks and mark an item `safe` only when every safe Rust caller can satisfy its contract.

Before Rust 2024, every function declared inside an `extern "C" { }` block was implicitly unsafe to call, while the block itself carried no `unsafe` keyword. Rust 2024 makes the declaration boundary explicit: the block must be `unsafe extern`, signaling that the programmer is responsible for declaring the external ABI accurately.
Items remain unsafe by default. Marking an item `safe` is a much stronger promise: **all values expressible by its Rust signature must be valid inputs for the foreign function**. Raw-pointer APIs with validity, lifetime, aliasing, initialization, or null-termination preconditions should therefore normally remain `unsafe` and be wrapped by a separately implemented safe Rust API.
**Key Points:**
- `unsafe` on the block means the declarations themselves are trusted to match the foreign ABI.
- An `unsafe` item may impose caller obligations; document them and expose a safe wrapper only when the wrapper establishes them.
- A `safe` extern item must be safe for every call permitted by its Rust signature.
- Raw pointers in a signature are not automatically unsafe, but any unchecked validity, aliasing, lifetime, initialization, or provenance requirement is a strong sign that the item must remain `unsafe`.
- Extern statics require the same careful invariant analysis; data races are only one possible source of unsoundness.

### `unsafe-send-sync-manual` — Justify manual `Send`/`Sync` from invariants enforced by the type and its dependencies, not from hoped-for caller behavior

`Send` and `Sync` are unsafe auto traits. A manual implementation is a promise to every safe caller that moving or sharing the type across threads cannot violate Rust's aliasing and data-race rules.
That promise cannot depend on comments such as "callers put this in a `Mutex`" unless the API actually enforces that synchronization. Safe code is allowed to use a `Send`/`Sync` type in every way those traits permit.
- Prefer: Invariant Comes From the Wrapped API
- Prefer Automatic Derivation
**Key Points:**
- Prefer auto traits derived from fields.
- Manual `Send`/`Sync` must remain sound under all safe uses permitted by the public API.
- Do not rely on unenforced caller conventions for soundness.
- Document the invariant immediately above each unsafe impl and revisit it whenever fields or methods change.
- Raw pointers are a common reason to need manual reasoning, not a reason to blindly opt in.

### `unsafe-no-mangle-unsafe` — In Rust 2024, write `#[unsafe(no_mangle)]`, `#[unsafe(export_name = "...")]`, and `#[unsafe(link_section = "...")]` — not the bare attribute forms.

`#[no_mangle]`, `#[export_name]`, and `#[link_section]` were reclassified as unsafe in Rust 2024 because they can cause undefined behavior without any `unsafe` block at the call site. If two items in the same binary share the same exported symbol name, the linker silently picks one and discards the other — the "winning" symbol may have a completely different type, signature, or semantics. The result is type-level UB with no diagnostic from the compiler or linker. Requiring `#[unsafe(...)]` makes this footgun visible and auditable.
**Key Points:**
- The `unsafe(...)` wrapper does **not** require an `unsafe {}` block at the call site; it marks the *attribute itself* as load-bearing for safety. The annotation documents that the programmer accepted responsibility for symbol uniqueness and ABI correctness.
- Symbol collisions are especially dangerous in plugin architectures, `cdylib` crates, embedded firmware with custom linker scripts, and any codebase that links multiple Rust crates into a single binary.
- These attributes interact with `unsafe extern` blocks (see `unsafe-extern-block`): external symbols you import and symbols you export follow the same 2024-edition safety rules.
- The bare forms (`#[no_mangle]` without `unsafe`) are a hard error in Rust 2024 edition code. They still compile in earlier editions but emit a deprecation warning with `--warn future-incompatible`.

### `unsafe-strict-provenance` — Prefer strict provenance APIs (`ptr.addr()`, `ptr.map_addr()`, `ptr.with_addr()`) over integer-pointer round-tripping (`as usize` / `as *const T`); prefer raw borrow syntax (`&raw const x` / `&raw mut x`) over `addr_of!` / `addr_of_mut!`.

A pointer carries an address plus **provenance** describing what memory accesses it can justify. Rust provides two models for code that manipulates pointer addresses:
- **Strict Provenance** keeps a pointer with the desired provenance available and changes or extracts only its address with APIs such as `addr`, `with_addr`, and `map_addr`. - **Exposed Provenance** covers pointer→integer→pointer workflows. A `ptr as usize` cast is equivalent to exposing the pointer's provenance, and an integer→pointer cast is equivalent to reconstructing a pointer using some previously exposed provenance when possible.
- Rust 1.99+: Prefer Raw Layout APIs When You Only Have a Raw Pointer
- Rust 1.99+: Raw Ownership Handoffs Should Not Round-Trip Through `leak`
**Key Points:**
- `addr()` gets the address without exposing provenance.
- `with_addr()` and `map_addr()` preserve the provenance of the source pointer.
- `ptr as usize` is equivalent to `expose_provenance()`; it is not the same operation as `addr()`.
- `addr as *const T` is equivalent to `with_exposed_provenance(addr)`, whose chosen provenance is intentionally not precisely specified.
- Use `without_provenance` for addresses that genuinely have no Rust allocation from which to obtain provenance, such as some MMIO/sentinel-address patterns. Dereferencing still requires the platform and Rust memory-model requirements to permit the access.
- Prefer `&raw const` / `&raw mut` when you need a raw pointer without first creating a reference; Rust 1.99's `raw_borrows_via_references` lint can help find indirect raw borrows.
- Strict Provenance APIs stabilized in Rust 1.84; raw borrow operators stabilized earlier and are the native syntax for raw borrows.

## 5. API Design (HIGH)

### `api-builder-pattern` — Use a builder when construction has several optional settings, validation, or staged configuration

Builders replace long positional constructors with named configuration steps and give construction logic a natural place for defaults and validation. They are most useful when a type has several optional parameters or when construction may fail.
Do not introduce a builder automatically for every struct. A small constructor with a few obvious required arguments is usually clearer.
- Prefer: Fallible Builder with Required and Optional Inputs
- When a Builder Is Overkill
**Practical Guidance:**
- Use builders for several optional settings, validation, or staged construction.
- Keep simple constructors simple.
- Return `Result` from `build()` when runtime validation can fail.
- Use typestate when compile-time construction guarantees justify the extra type complexity.
- Choose consuming or borrowing setters according to intended usage.
- Prefer generated builders when a maintained crate's API fits the project.

### `api-builder-must-use` — Mark consuming builder methods or the builder type `#[must_use]` when ignoring the returned builder is likely a bug

A common builder style takes `self` and returns a modified `Self`. Calling such a method without using the returned value consumes and drops that builder. `#[must_use]` turns an otherwise easy-to-miss mistake into a compiler warning.
This advice specifically applies when ignoring the return value is suspicious. Builders whose setters take `&mut self` mutate in place and do not need `#[must_use]` for this reason.
- Do Not Add `must_use` Mechanically

### `api-newtype-safety` — Use newtypes when identical representation hides meaning the compiler should distinguish

Raw primitives such as `u64` or `String` carry little domain meaning. If two values share the same representation but are not interchangeable—user IDs and group IDs, meters and seconds, validated and unvalidated strings—a newtype lets the compiler enforce that distinction with no runtime tagging requirement.
Use newtypes for meaningful invariants or confusion risks, not merely to wrap every primitive.
**Representation Is a Separate Decision:**
A single-field Rust newtype is often optimized exactly like its field, but source-level size equality is not itself a stable ABI/layout promise. Add `#[repr(transparent)]` only when the wrapper intentionally needs the wrapped field's layout/ABI contract, such as some FFI interfaces.
Do not infer from this assertion that arbitrary transmutation or FFI interchange is safe; see the representation rule for those requirements.
- When Newtypes Help Most

### `api-typestate` — Use typestate when compile-time state transitions materially simplify or strengthen an API

Typestate represents important runtime states as different Rust types. Methods can then exist only for states where they are valid, so some invalid operation sequences become compile-time errors instead of runtime checks.
That guarantee is valuable for protocols, staged resource initialization, transactions, and builders with important required fields. It is not free: state-specific types can complicate storage, trait bounds, type inference, error paths, and APIs that need to choose or erase state dynamically.
- Prefer: Operations Exist Only in Valid States
- Prefer: Builder Typestate for a Required Field
**Practical Guidance:**
- Use typestate for important ordered transitions and state-specific capabilities.
- Let state-changing methods consume `self` when the old state should no longer be usable.
- Returning `Result<NextState, E>` is normal when the transition itself can fail.
- Prefer runtime validation when typestate adds more public complexity than safety or usability.
- Generated typestate is especially useful for builders with required fields.
- Avoid unrelated feature claims: trait-object upcasting and other language features do not by themselves make an API a typestate design.

### `api-sealed-trait` — Seal a public trait when downstream crates should be able to use it but not implement it

A public trait is normally an extension point: downstream crates can implement it for their own types when coherence allows. That is useful when third-party implementations are part of the design, but it also means adding a new required method is a breaking change for those implementations.
A sealed trait deliberately closes that extension point. Downstream code can still name the public trait, call its methods, use it in bounds, and work with your implementations, but it cannot add new implementations. This gives the defining crate more freedom to evolve the trait's implementation requirements.
- Prefer: Private Supertrait Pattern
**Practical Guidance:**
- Seal a trait when downstream crates should consume it but not implement it.
- Use a private-module supertrait as the conventional stable pattern.
- Treat sealing as an API design decision: it trades extensibility for implementation control and some evolution freedom.
- Do not claim sealing makes every future trait change non-breaking.
- Do not claim sealing guarantees correctness; it only limits who can implement the trait.
- Keep traits open when third-party implementations are part of the intended ecosystem.

### `api-extension-trait` — Use a local extension trait when method-call syntax on an external type materially improves an API

Rust does not let you add inherent methods to a type defined in another crate, and the orphan rules restrict implementations of foreign traits for foreign types. A local trait avoids both problems: you own the trait, so you may implement it for an external type and callers get method syntax after importing the trait.
Extension traits are useful, but they are still public API surface. Method names can collide with inherent methods or other imported traits, and broad blanket impls can produce surprising method availability and diagnostics.
- Prefer: Extend an External Type with a Local Trait
- Prefer Narrow Implementations Over Gratuitous Blanket Impl Surface
- When a Newtype Is Better
**Practical Guidance:**
- Define a local extension trait when method-call syntax materially improves use of an external type.
- Keep the receiver implementation as narrow as the abstraction allows.
- Remember callers need the trait in scope.
- Design for method-name collisions, especially when exporting traits in a prelude.
- Make string extension methods Unicode-safe according to an explicit unit (bytes/chars/graphemes).
- Use a newtype when you need foreign trait implementations or new invariants.
- Treat third-party method names and diagnostic wording as versioned details, not permanent contracts.

### `api-parse-dont-validate` — Parse weakly typed input into invariant-bearing domain types at system boundaries instead of repeatedly validating primitives downstream

A validation function that returns only `bool` or `Result<(), E>` often leaves the program holding the same weak type it started with. Downstream code must then trust convention, repeat the check, or accept an invalid state in its type signature.
A parsing boundary returns a stronger type. If that type keeps construction closed and exposes only invariant-preserving operations, successful construction becomes evidence that the invariant holds.
- Avoid: Validate, Then Keep Passing the Primitive
- Prefer: Parse Into a Stronger Type
- Construction Must Actually Be Closed
- Do Not Over-Parse Ephemeral Checks
**Decision Guide:**
| Situation | Typical approach |
|---|---|
| Raw input enters domain code | Parse into a domain type |
| Several functions rely on one invariant | Strong type usually pays off |
| Invalid representation must not be safely constructible | Private representation + checked construction |
| Conventional text/representation conversion | `FromStr` / `TryFrom` |
| One local conditional | Plain validation may be clearer |

### `api-impl-into` — Accept `Into<T>` when the API intentionally takes ownership and useful caller types can convert into `T`

A parameter such as `impl Into<String>` lets callers provide `String` itself or another type with an infallible consuming conversion to `String`. This is useful for constructors, setters, builders, and other APIs that need to own the resulting value.
It is not a free abstraction. The conversion may allocate, a generic function may be monomorphized for multiple input types, and type inference/error messages can become more complex. Prefer an exact `T` when flexibility does not materially improve the API.
- Prefer: Ownership-Taking Convenience
- Trait Objects Are Not a Reason to Reject an `Into` Bound
**Practical Guidance:**
- Use `Into<T>` for infallible consuming conversion into an owned representation.
- Implement `From<Source> for Destination` for conversions you own; the blanket impl supplies `Into`.
- Do not claim `impl Into<T>` incurs virtual trait dispatch—it is statically dispatched.
- Consider monomorphization, inference, and actual conversion cost when making public APIs generic.
- Use `TryInto`/`TryFrom` or named constructors for fallible conversion.
- Keep stored field types concrete even if constructor/setter parameters are flexible.

### `api-impl-asref` — Use `AsRef<T>` for cheap generic borrowed views when accepting several source types is genuinely useful

`AsRef<T>` represents a cheap, infallible conversion from `&Self` to `&T`. It is useful when an API wants a borrowed view such as `&str`, `&[u8]`, or `&Path` and several input types naturally provide that view.
Do not turn every `&T` parameter into `impl AsRef<T>`. A concrete borrow is simpler, avoids extra generic surface area, and communicates exactly what the function needs.
- Prefer: Generic Borrowed View When It Improves the Call Sites
**Choosing the Parameter Shape:**
| Need | Typical parameter |
|---|---|
| Exactly a borrowed `T` | `&T` |
| Several cheap borrowed representations | `impl AsRef<T>` or `P: AsRef<T>` |
| Consume/own a converted value | `impl Into<T>` |
| Fallible consuming conversion | `TryInto<T>` / named constructor |
| Key-like equivalent borrowed representation | `Borrow<Q>` bounds |
| Smart-pointer dereferencing | ordinary `&value` / deref coercion |
Generic convenience has costs: more monomorphizations, more complicated signatures, and sometimes worse type inference. Prefer it when callers actually benefit.
**Practical Guidance:**
- Use `AsRef<T>` only for cheap, infallible borrowed views.
- Remember that a by-value `impl AsRef<T>` parameter still moves owned arguments.
- Prefer `&T` when one borrowed target type already gives ergonomic call sites.
- Do not assume `AsRef<T>` is blanket-reflexive for every `T`.
- Use `Borrow` instead when equality/hash/order equivalence of owned and borrowed forms matters.
- Use deref coercion, not `AsRef`, merely to dereference smart pointers.

### `api-must-use` — Add `#[must_use]` when silently discarding a value is plausibly a bug; rely on the built-in `unused_must_use` semantics instead of treating every return value alike

`#[must_use]` asks the compiler to warn when a value is produced as an expression statement and then discarded. It is useful for values whose purpose is normally in the returned value itself: results of pure computations, lazy values, builders, guards, and domain objects that have no useful effect when immediately dropped.
Do not add it mechanically to every function. A warning that fires for normal intentional usage teaches callers to ignore warnings instead of catching bugs.
- Prefer: Mark a Returned Value Whose Effect Is in the Value
- `Result`, Iterators, Futures, and Other Existing Must-Use Types
- When the Return Value Is Optional Information
- Rust 1.92+: Uninhabited Error/Break Types Do Not Trigger `unused_must_use`
- Messages Should Explain the Consequence

### `api-non-exhaustive` — Use `#[non_exhaustive]` when a public struct, enum, or enum variant is intentionally open to compatible growth

Adding a variant to a public enum or a field to a public struct can break downstream code that matches exhaustively or constructs the type directly. `#[non_exhaustive]` changes what **other crates** may assume so the defining crate can add variants or fields later without that particular source break.
This is an API-design tradeoff, not a blanket requirement for every public type. Closed sets such as a deliberately complete three-way ordering usually should remain exhaustive.
- Avoid: Promise a Closed Shape You Expect to Extend
- Prefer: Mark an Intentionally Open Type
**When to Use It:**
Prefer `#[non_exhaustive]` when all of these are true:
- the type is part of a public library API;
- future variants or fields are plausible;
- downstream exhaustive construction or matching would otherwise constrain compatible evolution.
Do not add it mechanically to internal types or intentionally closed public sets. It imposes real ergonomics costs on callers: wildcard matches lose exhaustiveness checking for future variants, and non-exhaustive structs need constructors or builders.

### `api-from-not-into` — Implement `From<Source> for Destination` for clear infallible conversions you own; use `Into<Destination>` primarily as a caller-side bound

The standard library provides a blanket implementation that makes `From<T> for U` imply `Into<U> for T`. Implementing `From` therefore gives callers both spellings:
- `U::from(value)` when the destination type should be explicit; - `value.into()` when context already determines the destination.
- Prefer: Implement `From` Once
- Use `Into` as an Input Bound When Appropriate
**Practical Guidance:**
- Implement `From<T> for U` rather than `Into<U> for T` when the `From` impl is legal and semantically appropriate.
- Use `Into<U>` as a generic input bound when accepting all converting source types is useful.
- Do not manually reproduce std's blanket `Into` implementation.
- Treat pre-Rust-1.41 orphan-rule advice as history, not a current design pattern.
- Use `TryFrom`/`TryInto` for conversions that can fail.
- Prefer named methods for conversions whose lossiness or domain meaning deserves an explicit verb.

### `api-default-impl` — Implement `Default` only when the type has a sensible canonical default value

`Default` integrates with `Option::unwrap_or_default()`, `#[derive(Default)]`, struct update syntax, and generic code requiring `T: Default`. That convenience is useful only when `default()` represents a meaningful value rather than an arbitrary placeholder.
A public `Default` implementation is a semantic commitment. Callers may rely on what the default means even if they should not rely on every field value remaining identical forever.
- Prefer: A Meaningful Configuration Default
- Derive When Field Defaults Are the Intended Semantics
- Do Not Invent Defaults for Required Identity
**Practical Guidance:**
- Implement `Default` when there is a sensible canonical value.
- Prefer derive when field-wise defaults are exactly the intended semantics.
- Use a manual implementation for meaningful domain-specific defaults.
- Do not use `Default` to fabricate required identity or mandatory input.
- A builder may implement `Default` even when the final built type should not.
- Avoid adding `T: Default` bounds merely for convenience.

### `api-common-traits` — Implement standard traits when their semantics are useful and appropriate for the public type

Trait implementations are part of a public API. They improve interoperability, but they also make semantic promises that downstream code may rely on. Add traits because the type has the corresponding behavior, not because a public type should mechanically derive a standard bundle.
`Debug` is broadly useful for diagnostics, `Clone` promises explicit duplication, and equality/ordering/hash traits define observable semantics. Those promises can affect privacy, cost, compatibility, and future representation changes.
- Prefer: Derive Traits That Match the Type
- Do Not Derive a Bundle Blindly
- Manual Equality and Hashing Must Agree
**Practical Guidance:**
- Treat trait impls as semantic API commitments.
- Prefer derive when field-wise behavior matches the public semantics.
- Do not recommend `Debug + Clone + PartialEq` for every public type by default.
- Keep `Eq`, `Hash`, and ordering implementations mutually consistent.
- Redact sensitive `Debug` output or omit `Debug` where disclosure risk outweighs diagnostic value.
- Implement `Copy` for appropriate value semantics, not merely because a type is small.

### `api-serde-optional` — Make serde optional in general-purpose libraries when serialization is not part of the core API

A public library should not force every downstream build to enable serialization support when many users do not need it. An optional dependency plus a feature lets consumers choose serde integration while keeping the core API usable without serde.
This is a design choice, not a universal rule. If serialization is fundamental to the crate's purpose or public types, making serde required can be simpler and more honest.
- Keep Feature-Off Builds Healthy
- When Serde Should Be Required

### `api-impl-fromiterator` — Implement `FromIterator` and `Extend` for collection types, and `IntoIterator` for all three reference forms

The Rust API Guidelines (C-COLLECT) require that collection types implement `FromIterator<T>` so that `iter.collect::<MyCollection<T>>()` works. Pairing it with `Extend<T>` enables efficient batch insertion — the standard library uses `Extend` internally in `collect` when extending an existing collection. Implementing `IntoIterator` for the type itself, for `&Type`, and for `&mut Type` rounds out the contract and lets the collection participate in `for` loops and iterator adapter chains. Skipping these traits forces callers into awkward manual loops and breaks generic code.

### `api-operator-overload` — Overload operators only when the semantics are natural and unsurprising

Rust allows operator overloading through traits in `std::ops` (`Add`, `Sub`, `Mul`, `Index`, `Neg`, etc.). The Rust API Guidelines (C-OVERLOAD) permit this — but only when the operator meaning is immediately obvious to any reader. Natural fits: arithmetic on numeric newtypes, vector/matrix math, set union/intersection with `+`/`|`, duration arithmetic. Surprising overloads — `+` that mutates state, `*` that performs a network call, `Index` that panics unconditionally — mislead readers and violate the principle of least surprise. When in doubt, name a method instead. Also implement the operator for references to avoid forcing callers to clone.
**Decision Guide:**
| Situation | Verdict |
|-----------|---------|
| Arithmetic on a numeric newtype or geometric type | Implement |
| Set operations (`|` for union, `&` for intersection) | Implement |
| String concatenation on a custom string type | Implement |
| `Index`/`IndexMut` on a container that holds items | Implement |
| `+` or `*` with visible side effects | Never |
| Operator meaning depends on context not captured by types | Use a named method |

### `api-bon-builder` — Use `bon` when typestate builders for structs or functions improve the API; account for proc-macro and typestate compile cost

`bon` can generate typestate builders for structs, functions, and methods, enforcing required members at compile time and supporting features such as `#[builder(into)]`, defaults, async functions, and builder-style constructors.
It is a useful option, not a universal community standard, and its stronger typestate machinery has compile-time cost. Current Bon benchmarks explicitly show more compile-time overhead than simpler builder crates such as `derive_builder`; choose it for API ergonomics and static guarantees, not because it supposedly compiles "10× faster".
**Choosing a Builder Approach:**
- Use Bon when compile-time required-member tracking and function/method builders materially improve the API.
- A small hand-written builder can be clearer for tiny stable APIs.
- Simpler derive crates may compile faster when typestate guarantees are unnecessary.
- Benchmark build times in macro-heavy workspaces instead of relying on generic performance claims.

### `api-do-not-recommend` — Use `#[diagnostic::do_not_recommend]` on legal trait impls whose appearance in diagnostics would usually mislead callers

Rust 1.85 stabilized `#[diagnostic::do_not_recommend]` as a hint to rustc about **diagnostic presentation**. When a trait solver encounters a broad impl whose unsatisfied bounds are implementation detail rather than useful advice, the attribute can tell rustc not to present that impl as the recommended path.
It does not change trait resolution, coherence, visibility, or program semantics. It also does not guarantee exactly what alternative wording rustc will choose.
- Prefer: Hide a Misleading Blanket Trait Impl
- Use It for the Diagnostic, Not for Blanketness Alone
**Requirements and Constraints:**
- Stable since Rust 1.85.
- Intended for a trait `impl` item.
- Takes no arguments.
- Is a compiler diagnostic hint, not a semantic attribute.
- Does not relax orphan/coherence rules.
- Should be used only when suppressing that impl improves the likely error message.
**Practical Guidance:**
- Start by reading the actual compiler error users receive.
- Add `do_not_recommend` only when an impl repeatedly creates a misleading recommendation.
- Keep examples legal without the attribute; the attribute must not be used to disguise a coherence problem.
- Do not promise a particular replacement suggestion—rustc diagnostics may evolve.
- Re-test representative diagnostics when changing broad public impls.

### `api-nutype-validated` — Use `nutype` when generated sanitization, validation, and invariant-preserving trait impls materially simplify a public newtype API

A validated newtype makes an invariant part of the type: once construction succeeds, downstream code receives a `Username`, `Port`, or other domain type instead of repeatedly re-validating a primitive.
The `nutype` proc macro can generate constructors, validation errors, sanitization, and selected trait impls while keeping the inner field private. This can remove substantial boilerplate, but it also adds a proc-macro dependency and compile-time cost. Use it when the invariant-bearing type is worth that tradeoff; a small hand-written newtype remains perfectly reasonable.
- Avoid: Repeated Validation at Call Sites
- Prefer: Parse Once Into a Validated Type
- When Not to Use `nutype`

## 6. Async/Await (HIGH)

### `async-tokio-runtime` — Start with Tokio's default runtime configuration; choose runtime flavor and tuning from execution requirements and measurements

Tokio has separate async worker threads and a blocking thread pool. Runtime configuration changes scheduling, memory use, failure modes, and the capacity available to APIs such as `spawn_blocking` and `tokio::fs`.
Most applications should begin with Tokio's defaults. The multi-thread runtime defaults its worker count to the number of cores available to the process, and Tokio explicitly advises keeping custom worker counts on the smaller side. Arbitrarily doubling workers for “I/O-bound” code is not a general optimization: readiness-based async I/O does not require one worker per blocked operation.
- Avoid: Tuning by Folklore
- Prefer: Start from the Execution Model

### `async-no-lock-await` — Keep blocking lock guards out of awaited sections; use an async mutex when exclusive access itself must span `.await`.

The useful rule is not "never hold any lock across `.await`." Rust async code commonly needs both short in-memory critical sections and serialized access to stateful async resources.
Two questions matter:
- Avoid: Blocking Mutex Guard Across Await
- Prefer: Await First, Then Lock Ordinary Data Briefly
- Prefer: Extract What You Need, Release, Await, Then Update
- Prefer: Async Mutex Across Await When the Resource Must Stay Exclusive
**Decision Guide:**
| Situation | Typical choice |
|---|---|
| Short critical section over in-memory data, no await | blocking/data mutex |
| Need data only to start an async operation | copy/clone needed fields, release lock, await |
| Must keep one async resource exclusively owned across awaits | async mutex |
| Complex serialized protocol / natural single owner | owner task + channels |
| Long blocking operation | move blocking work off executor workers |
**Key Points:**
- A blocking mutex guard crossing `.await` is a strong bug smell and is often rejected when a `Send` future is required.
- A Tokio mutex guard is explicitly designed to cross `.await`.
- Holding an async guard across `.await` is not automatically wrong; unnecessary serialization is the tradeoff.
- Use a standard mutex for ordinary data when the guard stays entirely in synchronous sections.
- Pick mutexes/message passing from ownership and sequencing semantics, not slogans.

### `async-spawn-blocking` — Use `spawn_blocking` for blocking synchronous work; bound CPU-heavy work or use a dedicated CPU pool such as Rayon

Tokio executor workers must keep polling many async tasks. A blocking syscall or long synchronous computation on a worker can delay unrelated futures.
`tokio::task::spawn_blocking` moves synchronous blocking work to Tokio's blocking pool. That is a good fit for blocking APIs and short-to-moderate synchronous operations. It is not automatically the right scheduler for an unbounded stream of CPU-heavy jobs.
**Key Points:**
- Blocking synchronous API → `spawn_blocking` is usually appropriate.
- Many CPU-heavy tasks → bound concurrency or use a dedicated CPU pool.
- `worker_threads` and blocking threads are different pools.
- Started blocking tasks are not cancellable merely by aborting the async handle.
- Measure latency and throughput rather than using universal duration thresholds.

### `async-tokio-fs` — Use `tokio::fs` for ordinary filesystem operations from async code; use dedicated async types for pipes/devices and other special files

Most operating systems do not expose ordinary filesystem operations through the same readiness APIs used for async sockets. Tokio therefore performs ordinary filesystem work through blocking operations offloaded from async workers. Calling `std::fs` directly inside a future can block the worker executing that future.
- When `std::fs` Is Fine

### `async-cancellation-token` — Use `CancellationToken` when tasks need explicit cooperative cancellation

Dropping a Tokio `JoinHandle` detaches the task; it does not stop it. `tokio_util::sync::CancellationToken` provides an asynchronously awaitable cancellation signal that can be cloned or arranged into parent/child relationships.
A cancellation token is **cooperative**. Calling `cancel()` marks the token (and its descendants) cancelled and wakes waiters, but the application still decides where cancellation is observed and what cleanup runs. If code is executing a future that never observes the token, cancellation does not forcibly stop that future.
- Prefer: Cooperatively Stop a Worker
**Practical Guidance:**
- Treat cancellation as a request, not forced task termination.
- Put cancellation points around operations where interruption has acceptable semantics.
- Distinguish shared clones from parent/child cancellation domains.
- Do not assume dropping a token requests cancellation.
- Pair cancellation signaling with explicit task joining when shutdown completion matters.
- Apply a timeout and `abort_all()` when graceful cleanup must have a hard deadline.

### `async-join-parallel` — Use `join!` / `try_join!` for a fixed set of independent futures; they run concurrently on one task, not in parallel by themselves

Awaiting independent I/O operations one after another serializes their waiting time. Tokio's `join!` and `try_join!` poll several futures as part of one parent task, allowing their waits to overlap without spawning separate tasks or allocating a collection.
That is **concurrency**, not automatic parallel execution: the joined futures are multiplexed on the current task. If one branch performs blocking work or a long CPU loop without yielding, it prevents the other branches from progressing too.
- Avoid: Unnecessarily Sequential Independent Work
- Prefer: Join Independent Futures
- Dependent Work Should Stay Sequential
**Choosing the Primitive:**
| Need | Typical primitive |
|------|-------------------|
| Fixed independent futures, keep all outputs | `join!` |
| Fixed fallible futures, fail on first error | `try_join!` |
| First branch to complete | `select!` |
| Dynamic spawned task set | `JoinSet` |
| Dynamic futures with bounded concurrency | buffered stream / `FuturesUnordered` + admission bound |
| Sustained CPU parallelism | CPU-oriented pool / explicitly bounded blocking work |

### `async-try-join` — Use `try_join!` for a fixed set of fallible futures that should run concurrently and stop when one returns an error

Tokio's `try_join!` polls several fallible futures concurrently on the **same parent task**. It returns their outputs when every branch succeeds, or returns the first observed error and drops the remaining branch futures.
That is fail-fast concurrency, not parallel execution. A branch that blocks the thread or performs long CPU work without yielding prevents the other joined branches from progressing.
- Avoid: Independent Operations Run Sequentially
**Choosing the Primitive:**
| Need | Primitive |
|------|-----------|
| Fixed infallible branches | `join!` |
| Fixed fallible branches, stop polling siblings on error | `try_join!` |
| First completion regardless of error | `select!` |
| Dynamic futures, completion-order processing | `FuturesUnordered` |
| Dynamic spawned tasks | `JoinSet` |

### `async-select-racing` — Use `tokio::select!` to wait on several async events, while reasoning explicitly about cancellation of the losing futures

`tokio::select!` polls several futures on the current task and runs the handler for the branch that becomes selected. The other branch futures are dropped when the `select!` expression finishes.
That makes cancellation semantics part of correctness. Dropping a future does not roll back work it already performed, and some operations are not cancellation safe when repeatedly recreated in a loop. Use `select!` when racing is the intended control flow, not as a generic replacement for sequential error handling.
- Prefer: Operation Versus Timeout
- Cancellation-Safe Does Not Mean “Always Prefer Cancellation”
- Dynamic Sets: Use a Stream/Future Collection
- Pin a Reused Future When Necessary
**Practical Guidance:**
- Treat the losing branch as being dropped when another branch wins.
- Check cancellation-safety documentation for operations used in repeated `select!` loops.
- Use `biased;` only when source-order priority is intentional.
- Use `else` for disabled branches, not as a readiness timeout.
- Prefer `timeout()` for a simple deadline when it makes the code clearer.
- Use `FuturesUnordered`, `JoinSet`, or another dynamic collection instead of trying to generate dynamic `select!` branches.

### `async-bounded-channel` — Prefer bounded channels when backlog growth must be constrained; use unbounded channels only when an external invariant bounds the backlog.

`tokio::sync::mpsc::channel` has a fixed queue capacity. When that queue is full, `Sender::send(...).await` **asynchronously waits** for capacity instead of growing the queue. That is backpressure.
`mpsc::unbounded_channel` has no channel-level backpressure. `UnboundedSender::send` is synchronous and messages may be buffered arbitrarily while the receiver falls behind. System memory is therefore the practical bound, and an overloaded producer can drive the process to OOM.
- Avoid: Unbounded Backlog Without an External Bound
- Prefer: Bounded Queue With Backpressure
- Choose Capacity From the Workload
- When Unbounded Can Be Reasonable

### `async-mpsc-queue` — Use `tokio::sync::mpsc` when an async task needs a single-consumer message queue with Tokio-aware waiting or backpressure

`tokio::sync::mpsc` is a multi-producer, single-consumer channel designed to integrate with async tasks. Its bounded form provides async backpressure: `Sender::send(...).await` waits for capacity instead of blocking the executor thread.
Do not turn this into “all channels in async code must be Tokio channels.” A synchronous channel can be appropriate at a sync/async boundary, and Tokio also has an unbounded channel whose `send` is synchronous. Choose based on where waiting happens, whether capacity must be bounded, and which side owns the runtime context.
- Avoid: Blocking Receive on an Async Worker Thread
- Prefer: Bounded Tokio MPSC
- `WeakSender` Does Not Keep the Channel Alive
**Practical Guidance:**
- Do not call blocking receive APIs directly on async runtime workers.
- Prefer bounded `mpsc` when queue growth must be controlled.
- Drop/close senders deliberately so consumers can observe shutdown.
- Use `Receiver::close()` followed by `recv().await` to close producer admission and drain queued work.
- Use `reserve()` when capacity should be secured before expensive message creation.
- Reach for `PollSender` only when integrating with `Sink`/poll-based APIs.

### `async-broadcast-pubsub` — Use `tokio::sync::broadcast` for bounded fan-out where every active subscriber should observe each retained event.

Tokio `broadcast` is a multi-producer, multi-consumer channel. Each sent value is made available to every active receiver. That is different from `mpsc`, where there is one receiving endpoint and each queued value is consumed once.
Broadcast is also **bounded**. Slow receivers do not apply backpressure to senders. If a receiver falls farther behind than the retained history, old values are evicted and that receiver gets `RecvError::Lagged` telling it how many messages were skipped.
- Avoid: Treating MPSC as Pub/Sub
- Prefer: Independent Broadcast Subscribers

### `async-watch-latest` — Use `watch` when receivers need the latest state, not a lossless history of every update

`tokio::sync::watch` stores one value. Each receiver independently tracks whether it has seen the current value, and a slow receiver may skip intermediate updates. That makes `watch` a strong fit for configuration, status, desired state, and other “latest value wins” data.
Do **not** describe watch receivers as seeing every change. If every event matters, use a queue/broadcast design whose lag and backpressure semantics match that requirement.
- Prefer: Observe the Latest Value
- Do Not Hold a `Ref` Across `.await`
**Practical Guidance:**
- Use `watch` only when intermediate updates may be coalesced.
- Do not claim each receiver sees every send.
- Use `borrow_and_update()` when consuming a `changed()` notification in a loop.
- Keep `watch::Ref` guards short and never carry them across `.await`.
- Make `send_if_modified` return value match whether mutation actually occurred.
- Check the current value before awaiting a future state transition.

### `async-oneshot-response` — Use `tokio::sync::oneshot` when exactly one value should travel from one sender to one receiver, especially for actor-style request-response.

A Tokio oneshot channel communicates at most one value. The `Sender` is consumed by `send`, and the `Receiver` is itself a `Future` that resolves to that value or to `RecvError` if the sender disappears without sending.
This matches request-response naturally: put a `oneshot::Sender<Response>` inside the queued request, send the request to the service, then await the paired receiver.
- Avoid: Polling Shared State for One Result
- Prefer: One Sender, One Receiver, One Value

### `async-joinset-structured` — Use `JoinSet` to track a dynamic collection of Tokio tasks when completion order and lifecycle control matter

`tokio::task::JoinSet<T>` owns a set of spawned tasks with one output type. It is useful when tasks are added dynamically and results should be handled as tasks finish rather than in spawn order.
Its lifecycle semantics are important:
- Prefer: Process Tasks as They Finish
**Practical Guidance:**
- Drain `JoinError`s when failures or abort completion matter.
- Use `abort_all()` plus joining when you want to observe task termination.
- Use `shutdown()` only when immediate abort-and-drain is the desired operation.
- Use `detach_all()` only when tasks intentionally should continue untracked.
- For graceful shutdown, signal cooperatively before applying hard abortion.
- Remember that dropping the set aborts registered tasks.

### `async-clone-before-await` — Do not clone merely because an `.await` exists; clone or move ownership when a task/lifetime boundary actually requires ownership.

A reference may legally live across an `.await`. Whether the resulting future is `Send` depends on the referenced type: `&T` is `Send` when `T: Sync`. Borrowing data stored inside an owned `Arc<T>` therefore does **not** inherently make an async function non-`Send`.
Cloning is useful for a different reason: ownership. A spawned task usually must own everything it keeps because `tokio::spawn` requires a `Send + 'static` future. Cloning an `Arc` is a cheap way to give the task another owning handle; cloning the entire inner value is often unnecessary.
- Avoid: Deep-Cloning Just Because an Await Follows
- Prefer: Borrow Across Await When the Owner Lives Long Enough
- Clone a Snapshot When Snapshot Semantics Are Desired
- Prefer Scope Reduction to Unnecessary Copies
**Decision Guide:**
| Situation | Typical choice |
|---|---|
| Owned `Arc<T>` lives for the whole future and borrowed `T` is `Sync` | Borrow across `.await` if convenient |
| Spawned task needs its own ownership while caller keeps state | `Arc::clone` before `async move` |
| Caller transfers ownership completely | Move the existing owner |
| Need a stable snapshot / release a lock | Clone only the required data |
| Value is needed only before `.await` | End its scope before `.await` |
| Intentionally non-`Send` task | Use a local executor rather than cloning blindly |

### `async-fn-in-trait` — Use native `async fn` in traits for static dispatch when its return-future bounds fit the API

Rust has supported `async fn` and return-position `impl Trait` in traits since Rust 1.75. Native async trait methods avoid forcing one erased boxed-future representation on every statically dispatched call.
That does **not** make native async trait methods a universal replacement for `async-trait`. On Rust 1.98, a dispatchable trait method with an opaque return type—including an `async fn`—is still not dyn-compatible. Public APIs also need to decide which auto-trait bounds, especially `Send`, callers are allowed to rely on for the returned future.
- Prefer: Native Async Trait for Static Dispatch
- Prefer: Manual Dyn-Compatible Boxed Future
**Practical Guidance:**
- Prefer native `async fn` for straightforward statically dispatched traits.
- Do not claim native async trait methods are dyn-compatible on Rust 1.98.
- Use explicit `-> impl Future + Send` when the trait must promise a `Send` future.
- Use `trait-variant` for generated bound variants, not as a dyn-dispatch solution.
- Keep `async-trait` or another erased-future design when trait objects are required.
- Benchmark allocation-sensitive paths instead of treating one representation as categorically faster.

### `async-async-fn-bounds` — Use `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce` bounds instead of `F: Fn() -> Fut, Fut: Future`

The `AsyncFn`, `AsyncFnMut`, and `AsyncFnOnce` traits stabilized in Rust 1.85 (February 2025). They let you express higher-order async function bounds in a single, readable constraint — and, critically, they handle lifetime capture correctly. The old two-generic pattern `F: Fn() -> Fut, Fut: Future<Output = T>` cannot accept `async ||` closures that borrow from their environment, because the future's lifetime is not linked to the closure's call. `AsyncFn` solves this structurally.
**Key Points:**
- `AsyncFn()` desugars the bound `F: AsyncFn<(), Output = T>` — the call syntax mirrors `Fn()`.
- Plain `async fn` items (not closures) automatically implement `AsyncFn` when their signature matches.
- `AsyncFn` is in `std::ops` but the traits are brought in scope automatically in the 2024 edition; in older editions you may need `use std::ops::AsyncFn;`.
- The compiler still infers `Send`-ness from the closure body; if you need `Send` futures (Tokio multi-threaded), add `+ Send` to the bound or use a `Send` wrapper.

### `async-cancel-safety` — Ensure futures used in `tokio::select!` branches are cancellation-safe

`tokio::select!` polls branch futures on the current task and drops the losing futures when the expression finishes. Dropping a future does not undo bytes consumed or messages removed. Cancellation safety depends on whether dropping and recreating the operation preserves the progress its caller needs. Check the whole operation across every `.await`, not just its individual primitives.

### `async-blocking-detection` — Detect async worker stalls with latency/console instrumentation; treat blocking-pool metrics as pool pressure, not proof that async workers are blocked

Rust async executors are cooperatively scheduled. A future that calls a blocking API or performs a long CPU loop without yielding can occupy a runtime worker and delay unrelated tasks. On a current-thread runtime, one such operation can stop all async progress until it returns.
Distinguish the execution domains:
- Prefer: Move Blocking Work Off Async Workers
**Review Checklist:**
Look for:
- `std::thread::sleep` inside async code;
- synchronous filesystem/network/database clients on async workers;
- blocking mutex/RwLock acquisition around slow work;
- FFI whose blocking behavior is unknown;
- long loops without `.await`, cooperative yielding, or offloading;
- large `spawn_blocking` bursts without workload-level backpressure.
Then validate suspected paths with traces/profiles rather than inferring causality from one metric.

### `async-runtime-metrics` — Use Tokio runtime metrics as scheduler telemetry, and distinguish stable metrics from `tokio_unstable` instrumentation

`tokio::runtime::RuntimeMetrics` exposes observations about a runtime such as worker count, alive-task count, queue depth, and cumulative worker busy time. These signals can help explain scheduler load, but they are not direct diagnoses of “starvation,” “healthy,” or “overloaded.” Interpret them as time series alongside application latency, throughput, errors, and workload information.
The original rule incorrectly treated the entire API as `tokio_unstable`. On current Tokio, several useful metrics are stable, while many detailed scheduler/blocking-pool metrics still require `--cfg tokio_unstable`.
- Prefer: Stable Runtime Metrics
- Prefer: Measure Deltas, Not Raw Cumulative Counters
- Do Not Invent Universal Health Thresholds
**Practical Guidance:**
- Start with stable metrics when they answer the operational question.
- Treat runtime metrics as observations, not diagnoses.
- Compare cumulative counters over intervals.
- Derive alert thresholds from service objectives and measured workload behavior.
- Gate `tokio_unstable` metrics explicitly and expect API churn.
- Correlate scheduler telemetry with application latency, throughput, and traces.

### `async-structured-concurrency` — Combine `JoinSet` + `CancellationToken` + `select!` for structured async task management

In unstructured concurrency, spawned tasks outlive their parent scope, making it hard to guarantee cleanup, cancellation, or resource release. The 2026 recommended pattern uses three Tokio primitives together:
1. **`JoinSet`** — tracks task lifecycle and aborts on drop 2. **`CancellationToken`** — signals shutdown cooperatively 3. **`select!`** — races between shutdown, work, and completion
**When to Use This Pattern:**
Use the JoinSet + CancellationToken + select! triad when: - Spawning multiple long-lived worker tasks - Tasks need graceful shutdown - You need to react to task panics/failures - Resources must be cleaned up when the scope exits - Concurrency needs to be limited
For simple cases (one-off spawns, fire-and-forget), the full pattern may be overkill.

## 7. Concurrency (HIGH)

### `conc-rayon-par-iter` — Use rayon's `par_iter()` for CPU-bound data parallelism

Rayon's work-stealing scheduler parallelizes data-parallel workloads with an API nearly identical to standard iterators — often a one-word change from `.iter()` to `.par_iter()` yields near-linear speedup across cores. It automatically balances load across threads, handles chunking, and composes with the full iterator adapter chain. For IO-bound concurrency, use async instead; rayon is strictly for CPU-bound computation.
**Key Points:**
| Concern | Guidance |
|---------|----------|
| Import | `use rayon::prelude::*;` enables `.par_iter()` on slices and most collections |
| IO-bound work | Use async (`tokio`, `async-std`), not rayon — rayon threads block |
| Small collections | Sequential is often faster due to thread-spawn overhead; profile first |
| Minimum chunk size | Rayon's `with_min_len()` / `with_max_len()` tune granularity |
| Shared state | Use `Mutex` or atomic operations; rayon does not prevent data races |
**When to Use:**
- Processing large arrays, slices, or collections (image pixels, number crunching, parsing batches)
- CPU-bound transformations: map, filter, fold, sort
- When the per-element work is non-trivial (at least a few hundred nanoseconds)

### `conc-scoped-threads` — Use `std::thread::scope` to borrow stack data across threads

Scoped threads (stable since Rust 1.63) guarantee that all threads spawned inside the scope join before `thread::scope` returns. This lifetime guarantee lets spawned threads borrow non-`'static` data from the enclosing stack frame — no `Arc`, no cloning, no heap allocation required. For short parallel tasks that need to read or write local data, scoped threads are simpler and cheaper than wrapping everything in `Arc<Mutex<...>>`.
**Key Points:**
- The closure passed to `thread::scope` receives a `Scope<'env, '_>` handle; threads spawned via `s.spawn(...)` can borrow anything alive in `'env`.
- All threads are joined automatically when the scope returns — even on panic.
- A panicking child thread causes `thread::scope` itself to panic after joining all remaining children.
- For CPU-bound data-parallel work over large collections, prefer rayon's `par_iter()`, which handles chunking and work-stealing automatically.
**When to Use:**
- Short-lived parallel tasks that share read-only or non-overlapping mutable references to local data
- You need explicit thread control (pinning, priority) that rayon doesn't expose
- Parallelizing a fixed number of distinct sub-tasks (not a homogeneous collection)

### `conc-atomic-ordering` — Use the weakest correct memory `Ordering` for every atomic operation

Defaulting to `SeqCst` (sequentially consistent) on every atomic is a common correctness-first shortcut, but it carries real cost: on x86 the difference is small, but on ARM and RISC-V weaker orderings map to cheaper instructions while `SeqCst` requires full memory barriers. More importantly, choosing the wrong ordering — even a weaker one — is a correctness bug that causes data races the compiler won't catch. Understanding the four practical levels lets you write both correct and efficient concurrent code.

### `conc-thread-local` — Prefer `thread_local!` with `Cell`/`RefCell` over `static mut`

`static mut` requires `unsafe` at every access and is undefined behavior if any two threads touch it simultaneously — the compiler cannot rule that out. In Rust 2024, taking a shared or mutable reference to a `static mut` is a hard error (`static_mut_refs`). `thread_local!` gives each thread its own independent copy of the value, accessed through safe APIs via `Cell` (for `Copy` types) or `RefCell` (for anything else), with no synchronization overhead and no unsafe code needed.
**Key Points:**
- `with_borrow` / `with_borrow_mut` are stable convenience methods (since 1.73) on `LocalKey<RefCell<T>>` — prefer them over the longer `with(|v| v.borrow_mut())` form.
- Thread-local destructors run when the thread exits, so cleanup happens automatically.
- Avoid storing thread-locals in types that are sent across threads; the value is strictly per-thread and is not visible to other threads.
- For read-only global constants shared across threads, use `static` with an immutable type instead.
**When to Use:**
- Scratch buffers, caches, or accumulators that are logically per-thread and don't need to be shared
- Reusing allocations across calls within a single thread (e.g., formatting buffers, temporary vecs)
- Replacing `unsafe static mut` with a safe alternative

## 8. Compiler Optimization (HIGH)

### `opt-inline-small` — Use `#[inline]` selectively, especially when a small non-generic public function benefits from cross-crate inlining.

Rust's optimizer already inlines functions when it considers that profitable. `#[inline]` is a hint, not a guarantee that a call disappears.
One place the attribute has a concrete compilation-model role is a **non-generic function used from another crate**: marking it `#[inline]` makes its body available to downstream code generation so the downstream optimizer can consider inlining it.
- Avoid: Adding `#[inline]` Because a Function Looks Small
- Prefer: Use the Hint for a Deliberate Cross-Crate API Case
- Function-Call Overhead Is Only Part of the Story
**LTO Changes the Tradeoff:**
Link-time optimization can expose more cross-crate code to the optimizer. If a project uses LTO, the marginal value of adding `#[inline]` purely for cross-crate visibility may differ from a non-LTO build.
Measure the release configuration you actually ship.

### `opt-inline-always-rare` — Treat `#[inline(always)]` as a strong optimization hint, not a command; use it only when measurement justifies it.

All Rust inline attributes are hints. `#[inline(always)]` strongly suggests inlining at every call site, but the compiler may still ignore it. Forcing the optimizer toward more inlining can increase code size and instruction-cache pressure, and may make performance worse even when a function is tiny.
Rust already performs automatic inlining. Start without `inline(always)` and add it only when a representative benchmark or profile shows a benefit that survives across the builds/targets you care about.
- Avoid: Blanket Forced-Inline Hints
- Prefer: Default Heuristics First
- Generic Functions Usually Do Not Need `#[inline]` for Body Availability
- When `#[inline(always)]` May Be Worth Testing

### `opt-inline-never-cold` — Use cold-path and inlining annotations as measured optimization hints, not source-level guarantees

Large or expensive error paths can increase the amount of code near a hot path. Rust provides `#[cold]`, `#[inline(never)]`, and `core::hint::cold_path()` to communicate optimization intent, but these are **hints**. They do not guarantee a particular branch instruction, section layout, cache behavior, or final machine-code shape.
Start with clear control flow. Add annotations when profiling or generated-code inspection shows that outlining a rare path matters.
- Do Not Invent `likely()` Semantics
- When Not to Annotate
**Practical Guidance:**
- Keep rare expensive work in a separate helper when that improves clarity or measured code layout.
- Use `#[cold]` to mark a genuinely rarely called function.
- Use `#[inline(never)]` sparingly and remember it is a hint.
- Use `core::hint::cold_path()` for a stable path-level cold hint on Rust 1.95+.
- Never make correctness depend on a branch or inlining hint.
- Measure before and after; remove annotations that do not help.

### `opt-cold-unlikely` — Use `#[cold]` or `core::hint::cold_path()` only when an unlikely path is known or measured to matter.

Rust exposes two stable ways to tell the optimizer that code is unlikely:
- `#[cold]` is a **function-level hint** that the function is unlikely to be called. - `core::hint::cold_path()` is a **path-level hint** that the current branch is unlikely to be taken.
- Avoid: Annotating a Rare-Looking Path by Intuition
- Prefer: Apply a Hint Where the Cold Split Is Intentional
- What the Hints Do Not Guarantee
- Measure the Result

### `opt-likely-hint` — Use `cold_path()` and `select_unpredictable` for branch hints on stable Rust

Modern CPUs predict branches to speculatively execute code. Mispredictions cause pipeline stalls (10-20 cycles). Helping the compiler understand which branches are likely allows it to generate optimal code layout and branch hints, improving performance in hot paths.
**When to Use:**
| Use select_unpredictable | Don't use it |
|--------------------------|--------------|
| Truly unpredictable branches (binary search, hash probes) | Highly predictable branches (error checks, bounds checks) |
| Performance-critical hot paths | Cold paths or infrequent code |
| After profiling confirms mispredictions | Without profiling data |

### `opt-lto-release` — Enable LTO in release builds

Link-Time Optimization (LTO) enables optimizations across crate boundaries that aren't possible during normal compilation. This includes cross-crate inlining, dead code elimination, and devirtualization. Typically provides 5-20% performance improvement.
**When to Use Each:**
| Situation | LTO Setting |
|-----------|-------------|
| Development | `false` (fast compiles) |
| CI builds | `"thin"` (balance) |
| Release binaries (generic) | `"fat"` (max perf) |
| Release binaries (x86-64-v3+) | `"thin"` (avoid 4000% regression) |
| Libraries (crates.io) | `false` (users choose) |

### `opt-codegen-units` — Set `codegen-units = 1` for maximum optimization in release builds

By default, Cargo splits code into multiple codegen units for parallel compilation. This speeds up builds but prevents some cross-unit optimizations. Setting `codegen-units = 1` allows LLVM to optimize across the entire crate, potentially improving runtime performance by 5-20% at the cost of slower builds.

### `opt-pgo-profile` — Use Profile-Guided Optimization (PGO) for maximum performance

PGO uses real runtime behavior to guide compiler optimization decisions. By profiling actual workloads, the compiler learns which code paths are hot, optimizing them aggressively while deprioritizing cold paths. This can yield 10-30% performance improvements beyond standard optimizations.
**When to Use PGO:**
| Use PGO | Skip PGO |
|---------|----------|
| Production deployments | Development builds |
| Performance-critical apps | Libraries (users can PGO; not distributable with `cargo install`) |
| Stable workload patterns | Highly variable workloads |
| Sufficient profiling data | Quick iteration cycles |
**Limitations:**
- **AutoFDO** (automatic feedback-directed optimization) is **not supported for Rust** ([tracking issue #64892](https://github.com/rust-lang/rust/issues/64892)).
- PGO cannot be used for `cargo install` — distributed crates cannot ship profile data.
- PGO is used to optimize the rustc compiler itself: ThinLTO + PGO on AArch64 (since Rust 1.86) gives ~30% faster compiles.

### `opt-target-cpu` — Tune `target-cpu` only for deployment CPUs you actually control, and use explicit runtime dispatch for portable binaries

`rustc` normally targets the baseline implied by the selected target triple. Passing `-C target-cpu=...` can enable additional instructions and tune scheduling for a more specific processor, but it also changes the minimum CPU requirements of the generated code.
`target-cpu=native` means **the CPU running the compiler**. It is useful for local workloads and controlled deployment, but it is a poor default for redistributable binaries because the build machine may support instructions that users' machines do not.
- Do Not Promise Specific Code Generation
**Practical Guidance:**
- Use `target-cpu=native` for local or tightly controlled deployment, not generic distribution.
- Pick `x86-64-v2/v3/v4` or named CPUs only when the supported fleet is known to meet that requirement.
- Keep a baseline path when distributing one binary across heterogeneous CPUs.
- Runtime-detect features before crossing into a specialized `#[target_feature]` implementation.
- Keep the feature-safety boundary explicit; detection alone does not alter the static call context.
- Verify both compatibility and performance on representative deployment hardware.

### `opt-bounds-check` — Structure hot loops so bounds are easy to prove; verify optimized code before using unchecked indexing

Safe slice indexing checks that an index is in bounds. In optimized code, rustc/LLVM can often remove redundant checks when loop structure or prior conditions prove the index valid. You cannot reliably count machine-level bounds checks by reading the source, and a different source spelling does not by itself guarantee faster code.
Prefer safe structures that make invariants obvious. If a hot loop is still limited by checks after optimization, verify that with measurements or generated code before introducing `unsafe`.
- Prefer: Make the Traversal Invariant Obvious
- Do Not Infer Assembly from Source Syntax
**Practical Guidance:**
- Prefer safe iteration/slicing patterns that make bounds obvious to humans and the optimizer.
- Preserve semantics when changing from indexing to `zip` or chunk APIs.
- Remember `split_at_checked` returns `Option`.
- Remember both `get_disjoint_mut` and `get_disjoint_unchecked_mut` are stable since Rust 1.86; only the latter is unsafe.
- Treat exact bounds-check counts and SIMD as properties of optimized output, not syntax.
- Reach for unchecked access only after measurement and with a local, documented proof.

### `opt-simd-portable` — Start with autovectorization; use stable SIMD crates or carefully dispatched `#[target_feature]` code when measurement justifies it.

SIMD (Single Instruction, Multiple Data) can process several values per instruction and substantially speed up suitable workloads. Rust's `std::simd` remains nightly-only, while stable crates such as `wide`, `pulp`, and `safe_arch` provide alternatives. Stable `#[target_feature]` support gives low-level control, but runtime detection does **not** make a call to a feature-enabled function safe by itself.
**Choosing an Approach:**
| Approach | Stability | Portability | Control | Complexity |
|----------|-----------|-------------|---------|------------|
| Autovectorization | Stable | Excellent | Low | Low |
| `wide` | Stable | Good | Medium | Low |
| `pulp` | Stable | Excellent | Medium | Medium |
| `safe_arch` | Stable | Platform-specific | High | Medium |
| `#[target_feature]` | Stable | Platform-specific | Maximum | High |
| `std::simd` | Nightly | Excellent | High | Medium |
**When to Choose What:**
- **Autovectorization** — default first choice; inspect/benchmark before escalating.
- **`wide`** — simple fixed-width explicit SIMD on stable Rust.
- **`pulp`** — portable runtime dispatch and multiversioning on stable Rust.
- **`safe_arch`** — platform-specific intrinsics with safer wrappers.
- **`#[target_feature]`** — maximum control when you can maintain explicit feature detection and unsafe dispatch boundaries.

### `opt-cache-friendly` — Shape data around measured access patterns and working sets; do not assume one layout is universally cache-friendly

Modern processors have several levels of cache, but exact cache sizes, line sizes, miss costs, prefetch behavior, and memory latency are hardware- and workload-dependent. The useful rule is therefore about **locality**: keep data that is consumed together near each other, avoid touching cold data in hot loops, and measure the actual workload before redesigning a representation.
Do not bake universal numbers such as “an L3 miss is 100 cycles” or “a cache line is always 64 bytes” into general Rust guidance. Those are common values on some machines, not language guarantees.
- Split Hot and Cold State When It Helps
- Blocking and Chunk Sizes Must Be Tuned
- Measure the Workload
**Practical Guidance:**
- Optimize the fields and traversal order that are actually hot.
- Prefer contiguous storage when it matches the ownership/update model and improves measured locality.
- Consider SoA or hot/cold splitting for field-wise workloads, not as universal replacements for structs.
- Do not infer cache misses from source-level pointer dereferences.
- Do not hard-code cache sizes, line sizes, or cycle costs as portable facts.
- Benchmark block sizes, padding, and layout changes on representative hardware and data.

### `opt-cold-path` — Use `core::hint::cold_path()` to mark unlikely inline paths (Rust 1.95+)

`cold_path()` is the canonical stable way to hint that a code path is unlikely without extracting code into a separate function. It tells the compiler to optimize the surrounding code for the case where this path is NOT taken, improving branch layout and instruction cache utilization. Unlike `#[cold]`, it works inline — no function extraction needed.
**When to Use cold_path() vs #[cold]:**
| Scenario | Use |
|----------|-----|
| Small unlikely branch (inline) | `cold_path()` |
| Large cold function (> ~10 lines) | `#[cold]` + extraction |
| Both inline hint and extraction | `cold_path()` + `#[cold]` on extracted function |
| In hot loop, branch that's almost never taken | `cold_path()` |

### `opt-select-unpredictable` — Use `core::hint::select_unpredictable()` for branchless conditional moves (Rust 1.88+)

Branch mispredictions cost 10-20 cycles each on modern CPUs. For truly unpredictable branches (binary search midpoints, hash table probing, SIMD-style selections), `select_unpredictable()` generates branchless `cmov`/`csel` instructions that execute in constant time regardless of input data — eliminating misprediction penalties.

## 9. Numeric & Arithmetic Safety (HIGH)

### `num-overflow-explicit` — Handle integer overflow explicitly: `checked_`/`saturating_`/`wrapping_`/`overflowing_`

Integer overflow panics in debug builds and silently wraps (two's complement) in release builds. Relying on either default behavior is a latent bug — the release build can produce wrong results without any diagnostic. Choosing an explicit variant makes intent unmistakable to both the compiler and future readers.
**Key Points:**
| Method family | Returns | Use when |
|---|---|---|
| `checked_*` | `Option<T>` | overflow is an error your caller must handle |
| `saturating_*` | `T` | clamping at the type's bounds is correct behavior |
| `wrapping_*` | `T` | modular arithmetic is intentional (e.g., checksums, ring buffers) |
| `overflowing_*` | `(T, bool)` | you need the result *and* know whether it overflowed |
These methods are available on all primitive integer types in the standard library (`u8` through `u128`, `i8` through `i128`, `usize`, `isize`). Equivalent sub/mul/div/shl/shr variants exist for every arithmetic operation.

### `num-cast-try-from` — Avoid `as` for narrowing casts; use `From` for widening and `TryFrom` for narrowing

The `as` cast silently truncates or wraps on narrowing (`300u32 as u8 == 44`) and produces surprising results on float-to-integer conversion (values outside range saturate to the type's min/max since Rust 1.45, but `NaN` becomes `0`). These behaviors are easy to miss during code review and impossible to catch at runtime without tests. `From`/`Into` are lossless by design and will not compile for lossy conversions; `TryFrom`/`TryInto` return `Result` and make the fallibility explicit.
**Key Points:**
- `From<A> for B` compiles only when the conversion is always lossless. Attempting `u8::from(300u32)` is a compile error.
- `TryFrom` returns `Result<T, TryFromIntError>` from the standard library — no external crates needed.
- Reserve `as` for:
  - Pointer casts (e.g., `*const u8 as *mut u8`) that are intentional.
  - Float-to-integer when you have verified the range and documented the intent.
  - `usize` ↔ pointer-sized integer only when you explicitly need to expose or
    inject provenance. Prefer strict provenance pointer APIs (stable since Rust 1.84):
    `ptr.addr()` instead of `ptr as usize`, and `ptr.map_addr(|a| ...)` instead of
    casting through an integer to manipulate a pointer's address.
- When using `.try_into()`, the turbofish or type annotation is often needed to help inference: `let n: u8 = x.try_into()?;`

### `num-float-compare` — Use approximate comparison when you mean numerical closeness; use exact equality for exact semantics and `total_cmp` for total ordering

Floating-point arithmetic rounds, so mathematically equivalent computations can produce different representable values. That makes exact `==` inappropriate when the intended question is "are these numerical results close enough?"
Exact equality is still correct for exact semantics: sentinels such as `0.0` when both signed zeros are intentionally equivalent, detecting whether an unchanged stored value is exactly equal, or protocols whose specification requires IEEE equality.
**Key Points:**
- Do not replace every float `==` mechanically.
- Approximate equality needs domain-appropriate absolute and/or relative tolerances.
- `NaN != NaN` under ordinary IEEE equality.
- Use `total_cmp` when a complete deterministic ordering is required.
- If bitwise identity is what matters, compare `to_bits()` values explicitly.
- On Rust 1.98+, treat `algebraic_*` operations as an opt-in relaxed-arithmetic contract, not as a universally faster spelling of ordinary operators.
- Benchmark algebraic arithmetic on representative targets and test numerical error bounds before adopting it.

### `num-saturating-clamp` — Bound values with `clamp` and saturating arithmetic

Constraining a numeric value to a range is a common operation, but hand-rolled `if`/`min`/`max` chains are verbose and easy to get wrong (especially when combining signed and unsigned types). `Ord::clamp(min, max)` expresses the intent in a single call and is available on all types that implement `Ord` (all integer primitives, and `f32`/`f64` via their own `clamp` since Rust 1.50). When you additionally want arithmetic that stops at the type's limits rather than panicking or wrapping, combine `clamp` with `saturating_*` methods.
**Key Points:**
- **`clamp` panics if `min > max`** — this is a programming error and is caught in debug builds. If `min`/`max` come from user input, validate their order first.
- **`f32`/`f64` `clamp`** propagates `NaN`: if `self` is `NaN`, the result is `NaN`. If `min` or `max` is `NaN`, the result is unspecified. Filter `NaN` before calling `clamp` on untrusted floats.
- **Saturating vs. clamping**: `saturating_*` applies to a single arithmetic operation and stops at the type's absolute limits (`i32::MIN`/`i32::MAX`). `clamp` applies to the final value and accepts arbitrary bounds. They compose well, as shown in `apply_damage`.
- The standard library docs for `clamp` are at `std::cmp::Ord::clamp` and `f32::clamp`.

### `num-nonzero` — Use `NonZero*` types to forbid zero and unlock the niche optimization

`NonZeroU32`, `NonZeroI64`, and their siblings (available for all integer primitives in `std::num`) make zero unrepresentable at the type level — you cannot construct one without going through `NonZeroU32::new(n)`, which returns `Option<NonZeroU32>`. This pushes the zero-check to the construction site and eliminates defensive zero-checks throughout the rest of the code. As a bonus, the compiler uses the zero bit-pattern as a *niche*, so `Option<NonZeroU32>` is exactly the same size as `u32` — no overhead for the `Option` tag.
**Key Points:**
- All `NonZero*` types live in `std::num`: `NonZeroU8`, `NonZeroU16`, `NonZeroU32`, `NonZeroU64`, `NonZeroU128`, `NonZeroUsize`, and their signed counterparts.
- **Construction**: `NonZeroU32::new(n) -> Option<NonZeroU32>`. Use `NonZeroU32::new(n).expect("n must be non-zero")` only at well-verified program boundaries, not in production fallible paths.
- **Access**: `.get()` returns the inner primitive value.
- **Arithmetic**: `NonZeroU32` does not implement `Add`/`Sub` directly (the result could be zero). Extract with `.get()`, do arithmetic, and reconstruct with `NonZeroU32::new(result)?`.
- **Niche optimization** applies to `Option` and `Result`: the compiler stores the `None`/`Err` discriminant in the zero bit-pattern, so no extra word is needed. This also applies to custom newtypes that wrap `NonZero*`.

## 10. Type Safety (MEDIUM)

### `type-newtype-ids` — Wrap semantically distinct IDs in distinct types, and encode additional invariants such as non-zero values at construction

Raw integers do not distinguish a `UserId` from an `OrderId`. A newtype turns that distinction into a compile-time property while still allowing a compact representation.
Keep the wrapper's construction semantics aligned with the domain. If zero is invalid, encode that with `NonZero`; if parsing or validation is more involved, use a checked constructor or a validated-newtype helper such as `nutype`.
- Avoid: Interchangeable Primitive IDs
- Prefer: Distinct ID Types

### `type-newtype-validated` — Put durable domain invariants behind checked constructors so downstream code can rely on the type instead of re-validating primitives

A validation function that returns `bool` leaves the caller holding the same weakly typed value. A validated newtype records the successful check in the type: safe code cannot construct the value without going through an invariant-preserving boundary.
This is most valuable when the property survives across multiple calls or layers of the program. For a one-off local condition, a plain check is often clearer.
- Avoid: Validate but Keep the Primitive
- Prefer: Close Construction Around the Invariant
- Use `NonZero` for the Common Non-Zero Integer Invariant
- Manual Serde Must Re-Establish the Invariant
**Sanitization Is a Domain Decision:**
Trimming or normalizing case can be correct for some identifiers and wrong for others. Treat sanitization as part of parsing semantics, not as a generic way to make invalid input pass.
Likewise, avoid unchecked constructors unless there is a measured need and a clearly documented invariant proof at every call site.

### `type-enum-states` — Use enums when a value is in exactly one of several mutually exclusive states

Several booleans or loosely related `Option` fields can encode combinations that the domain says are impossible. An enum gives each state one variant, lets each variant carry only the data valid in that state, and makes pattern matches exhaustiveness-checked.
- Avoid: Independent Flags for One State Machine
- Prefer: One Variant per State
- When an Enum Is Not Enough

### `type-option-nullable` — Use `Option<T>` when absence is an ordinary state; use `Result<T, E>` when callers need failure information

`Option<T>` makes “present or absent” explicit in the type system. It avoids sentinel values and nullable raw-pointer conventions, and it lets APIs distinguish ordinary absence from an operation that failed for a reason.
Use `Option` when `None` is sufficient information. If callers need to know *why* a value is missing, return `Result` or another domain-specific type instead.
- Prefer: Model Ordinary Absence Directly
- Match When Both Cases Matter

### `type-result-fallible` — Use `Result<T, E>` when an operation can fail with useful error information

`Result<T, E>` makes recoverable failure part of an API's type. Callers can propagate the error with `?`, inspect it, attach context, retry, or deliberately discard it. That is usually better than a sentinel value, an `Option` that erases the reason for failure, or an unconditional panic.
- Prefer: Preserve the Failure Mode

### `type-phantom-marker` — Use `PhantomData` for zero-cost type markers

Sometimes your type needs to be parameterized by a type that doesn't appear in any field — for variance, drop order, or semantic purposes. `PhantomData<T>` tells the compiler your type is "associated with" `T` without storing any `T` data. It has zero runtime cost. For `!Unpin` markers, use `PhantomPinned`, a dedicated zero-sized type from `std::marker`.

### `type-never-diverge` — Use `!` as the return type of functions that never return normally

The never type `!` has no values. A function returning `!` therefore cannot return normally: it must diverge by looping forever, panicking, terminating the process, or otherwise leaving the current control flow.
Diverging expressions such as `panic!()`, `return`, `break`, and an infinite `loop` can coerce to the type required by their surrounding expression. That is why a panic or process exit can occupy a `match` arm whose other arm produces an ordinary value.
- Prefer: Mark a Diverging Function Explicitly
- Rust 1.92 Never-Type Fallback Lints
- Do Not Overuse `!`

### `type-generic-bounds` — Put each trait bound on the API surface that actually requires it

A trait bound is part of an API's contract. Putting a bound on a generic type definition constrains every use of that type; putting it on one `impl` or method constrains only that functionality. Unnecessary bounds reject otherwise-valid callers and can make downstream trait implementations harder to compose.
Start from the operations and invariants the API needs, then place the corresponding bounds at the narrowest useful level. A bound on the type itself is appropriate when the type's definition or invariant genuinely requires it; it is not merely a style preference to avoid all type-level bounds.
**Type-Level Bounds Are Sometimes Real Requirements:**
A definition can itself require a bound because one of its fields or invariants requires the associated type relationship:
Here `I::Item` cannot even be named without knowing that `I: Iterator`, so the bound belongs on the type.

### `type-no-stringly` — Replace durable stringly-typed states and identifiers with enums or domain types, while keeping text parsing at system boundaries

A `String` can hold any spelling, so APIs that use strings for a closed set of states or for values with strong invariants push mistakes into runtime checks. Enums and newtypes make the accepted domain explicit, improve exhaustiveness checking, and give parsers a natural boundary.
Strings remain the correct representation for genuinely open-ended text. The goal is not “never use strings”; it is to stop using strings as an undocumented type system.
- Avoid: Closed States as Strings
- Prefer: Enum for a Closed Set
- Serde Can Keep the Wire Format Textual
- When Strings Are Correct

### `type-repr-transparent` — Use `#[repr(transparent)]` when a wrapper intentionally needs the wrapped field's layout and ABI

`#[repr(transparent)]` is an interoperability and layout contract, not a default annotation for every newtype. It is useful when a wrapper must deliberately have the same layout and ABI as its non-zero-sized field, especially at FFI boundaries or in carefully documented unsafe abstractions.
For ordinary pure-Rust newtypes, the compiler is free to choose layout and callers should not depend on it. That is normally a feature: it leaves implementation freedom and avoids promising ABI properties that the API does not need.
- Prefer: FFI Newtype
**When to Apply:**
| Scenario | Recommendation |
|----------|----------------|
| FFI wrapper that must match the wrapped ABI | Use `#[repr(transparent)]` |
| Unsafe abstraction whose documented contract depends on layout | Usually use it and document the invariant |
| Pure-Rust semantic newtype | Usually omit it unless layout is intentionally part of the contract |
| "I might want to transmute this later" | Not a sufficient reason |
| Multi-field data structure | Use the representation appropriate to the actual ABI/layout requirement |
**Key Points:**
- Treat `repr(transparent)` as a public layout/ABI promise.
- Do not add it automatically to every one-field newtype.
- `transmute` remains unsafe; layout compatibility is only one of its requirements.
- Prefer constructors and conversion traits over transmutation when you control the wrapper type.

### `type-deref-coercion` — Implement `Deref`/`DerefMut` only for smart-pointer and transparent wrapper types

`Deref` coercions are what make `Box<T>`, `Arc<T>`, `String`, and `Vec<T>` ergonomic — they let the inner type's methods surface through the wrapper transparently. The Rust API Guidelines (C-DEREF) specify this usage precisely: implement `Deref<Target = T>` when your type *is* a smart pointer or a transparent container for `T`. Using it as an OOP-style inheritance mechanism pollutes method resolution, confuses readers, and makes refactoring hazardous because adding methods to `T` silently affects every wrapper that `Deref`s to it.

### `type-display-vs-debug` — Use `Display` for user-facing output and `Debug` for diagnostics; never swap them

`Debug` (`{:?}`) is for developers: logs, panic messages, test assertions, and `dbg!()`. It should always be derived and reflects internal structure. `Display` (`{}`) is for end users: CLI output, error messages surfaced to humans, and log fields meant to be read in production. `std::error::Error` requires `Display` so that error chains read naturally. Routing `Debug` output to users leaks implementation details; routing `Display` output to log frameworks loses structural information.

### `type-numeric-fmt` — Implement `LowerHex`, `UpperHex`, `Octal`, and `Binary` for numeric newtypes

Rust's API Guidelines (C-NUM-FMT) state that numeric types should support `{:x}`, `{:X}`, `{:o}`, and `{:b}` wherever the underlying integer type does. A numeric newtype that silently drops these format specifiers is an ergonomic regression — callers who reach for `{:x}` to debug a bitmask or address will hit a compile error instead. The fix is a one-liner per trait that forwards to the inner value's formatter.

### `type-derive-more-boilerplate` — Use `derive_more` to remove mechanical trait boilerplate when the generated trait semantics are actually part of your API

Newtypes often need straightforward implementations of traits such as `From`, `Display`, `AsRef`, `Deref`, `FromStr`, or `IntoIterator`. `derive_more` can generate those implementations, but each derive changes the public capabilities of the type.
Do not treat “derive everything the inner type has” as automatically good newtype design. A validated/domain type may deliberately **not** expose `Deref`, arbitrary `From`, arithmetic operators, or mutable iteration because those traits can bypass or obscure its abstraction boundary.
- Numeric Operators Should Match Domain Semantics
- When Manual Implementations Are Better
**Practical Guidance:**
- Derive mechanical traits only after deciding that each trait belongs in the type's API.
- Remember that bare `AsRef` and `Deref` target the wrapped field; forwarding is explicit.
- Use `#[as_ref(str)]` or `#[as_ref(forward)]` deliberately rather than assuming `String -> str` forwarding.
- Use `#[deref(forward)]` only when forwarding the inner dereference is intentional.
- Treat `FromStr` errors as inner-parser/configuration dependent, not one universal `ParseError`.
- Request reference forms of `IntoIterator` explicitly when needed.
- Keep validation and domain semantics ahead of boilerplate reduction.

### `type-newtype-repr-transparent` — Use `#[repr(transparent)]` only when a newtype intentionally promises the wrapped field's layout or ABI

A newtype is primarily a type-safety tool. Most pure-Rust newtypes do not need a representation attribute: callers should use constructors and conversion traits rather than depend on layout.
`#[repr(transparent)]` is appropriate when layout or ABI compatibility with the wrapped field is deliberately part of the contract, especially for FFI and some unsafe abstractions. It does not make `transmute` safe; validity requirements still apply and `transmute` remains an unsafe operation.
- FFI/Layout Contract: Use `repr(transparent)`
- Do Not Call Transmutation "Safe"
**When to Apply:**
| Scenario | Recommendation |
|---|---|
| Ordinary semantic newtype | Usually omit `repr` |
| FFI wrapper that must match the wrapped ABI | Use `#[repr(transparent)]` |
| Unsafe abstraction whose contract depends on layout | Use it when the transparent guarantee is the required one, and document why |
| "Maybe I will transmute it later" | Not a sufficient reason |
**Key Points:**
- A representation attribute is an API/layout commitment, not a default decoration.
- `repr(transparent)` guarantees layout/ABI compatibility; it does not waive type validity rules.
- Prefer constructors, `From`, and `TryFrom` over transmutation when you control both sides.
- Keep the canonical detailed guidance in type-repr-transparent.

### `type-nonzero-intrinsics` — Use `NonZero<T>` when zero is invalid, and use only operations whose result semantics preserve that invariant

`core::num::NonZero<T>` makes “not zero” part of the value's validity invariant. For supported primitive types, the all-zero bit pattern is excluded, which gives `Option<NonZero<T>>` a guaranteed niche representation without an additional discriminant.
That invariant also shapes the arithmetic API. `NonZero` does **not** simply expose every method of the underlying integer: operations are provided when their signatures/results can express overflow or otherwise preserve non-zero validity.
- Prefer: Encode the Invariant Once

### `type-nutype-validated` — Use validated newtypes to make invalid states unrepresentable; `nutype` is useful when generated constructors and invariant-preserving trait impls justify a proc macro

A validated newtype moves a check from “remember to validate this primitive everywhere” to “construction is the only place an invalid value can enter.” Downstream APIs can then accept the domain type directly and rely on its invariant.
The important design pattern is the type boundary, not any particular macro. A hand-written private-field newtype is often ideal. `nutype` is useful when sanitization, several validators, parsing/conversion traits, or serde support would otherwise produce repetitive code.
- Avoid: Primitive Obsession
- Prefer: Put the Invariant in the Type
- When `nutype` Fits

## 11. Trait & Generics Design (MEDIUM)

### `trait-associated-type-vs-generic` — Use an associated type when each impl has exactly one output type; use a generic parameter when a type can implement the trait for many input types

The choice between `type Output;` and `<Rhs>` has two concrete consequences. First, an associated type is **part of the implementing type's identity**: callers never name it with turbofish because there is only one valid binding per impl. Second, a generic parameter allows **multiple simultaneous impls** on the same type — `impl Add<f64> for Vec2` and `impl Add<Vec2> for Vec2` can coexist, while `impl Iterator` can only define one `Item`. Using an associated type when multiple impls are needed makes those impls impossible; using a generic parameter when there is only one output forces every call site to write noisy turbofish or type annotations.
The Rust API Guidelines (rust-lang.github.io/api-guidelines/future-proofing.html) capture the rule: prefer associated types when there is a single natural output per implementor.
**Key Points:**
- `std::iter::Iterator`, `std::future::Future`, and `std::ops::Deref` all use associated types because there is exactly one `Item`/`Output`/`Target` per implementor.
- `std::ops::Add<Rhs>`, `std::convert::From<T>`, and `std::convert::Into<T>` use generic parameters because a single type can add to, or convert from, many others.
- When you need to constrain the associated type in a bound, write `P: Parser<Output = JsonValue>` — less noisy than a free generic parameter.
- Use inline associated type bounds (stable since Rust 1.60) to constrain that an associated type implements a trait: `I: Iterator<Item: Copy>` rather than the more verbose `I: Iterator<Item = T> where T: Copy`. This syntax also works in `where` clauses, `impl` blocks, and `dyn Trait` contexts.

### `trait-blanket-impl` — Use a blanket impl `impl<T: Bound> Trait for T` to give behaviour to every type that satisfies a bound

A blanket impl extends an entire class of types at once without touching each one individually. The standard library uses this pervasively: `ToString` is blanket-implemented for every `T: Display`, so any type that implements `Display` automatically gets `.to_string()`. This avoids repetitive boilerplate and keeps extension traits composable. The trade-off is coherence: Rust's orphan rules allow at most one applicable impl per type, so a blanket impl can conflict with a more specific one if not designed carefully. Adding a blanket impl is also a **semver-breaking change** if it could overlap with impls that downstream crates provide.
**Key Points:**
- The standard library blanket-impls `ToString` for all `T: Display`, `From<T> for T` (reflexive), and `impl<T: Error> From<T> for Box<dyn Error>`.
- Blanket impls live in the crate that owns the **trait** (not the type), satisfying the orphan rule.
- A blanket impl prevents any specific impl for a type it already covers — that overlap is a coherence error (E0119), because specialization is not stable. Use a newtype when you need a per-type override.
- Treat adding a public blanket impl as a **minor semver bump at minimum** (or major if it could break downstream).
- Pair blanket impls with sealed traits (`api-sealed-trait`) when you want the blanket behaviour but need to prevent external implementations.

### `trait-coherence-newtype` — Respect the orphan rule; wrap a foreign type in a newtype to implement a foreign trait on it

Rust's coherence rules — enforced by the orphan rule — require that for any `impl Trait for Type`, either `Trait` or `Type` must be defined in the current crate. This prevents two crates from providing conflicting implementations for the same (trait, type) pair, which would make the compiler unable to pick one. When you need to implement a trait you didn't define (e.g., `std::fmt::Display`) on a type you didn't define (e.g., `Vec<i32>`), the compiler rejects the impl outright. The solution is to wrap the foreign type in a local newtype struct, then implement the foreign trait on the wrapper. Marking the wrapper `#[repr(transparent)]` keeps it zero-cost and allows safe pointer casts where needed.
**Key Points:**
- The orphan rule: `impl<T> ForeignTrait for ForeignType<T>` is always rejected, even with a type parameter.
- `#[repr(transparent)]` is mandatory for newtypes that need the same ABI as the inner type (e.g., FFI, pointer casts via `transmute`). For purely logical wrapping, it is optional but good practice.
- Provide `From`/`Into` conversions and an `inner()` / `into_inner()` accessor so callers can move in and out of the wrapper easily.
- The newtype pattern is described in the Rust API Guidelines under "Newtypes provide static distinctions" (rust-lang.github.io/api-guidelines/).
- Newtype wrappers are also the correct way to add trait impls to types from transitive dependencies that you do not control.

### `trait-default-methods` — Define a trait in terms of a few required methods plus defaulted ones built on top of them

A trait with only required methods places the full implementation burden on every consumer. Providing default method bodies — as `std::iter::Iterator` does, building `map`, `filter`, `fold`, and dozens more on a single required `next` — means implementors write only the essential logic and receive the rest for free. Defaults also act as documentation: they show the canonical relationship between methods. Implementors can still override a default for performance (e.g., `Iterator::count` overridden by `std::vec::IntoIter` to avoid iterating) without changing the observable contract.
**Key Points:**
- Keep required methods to the **minimum orthogonal set**: ideally one or two.
- Default implementations must only call other methods on `Self`, not external state.
- An override changes performance but must preserve the same observable semantics.
- Document which methods are required vs defaulted in the trait's module-level doc comment.
- The pattern is explicitly encouraged by the Rust API Guidelines under "Implement common traits from std" and is central to `std::iter::Iterator`, `std::io::Read`, and `std::io::Write`.

### `trait-dyn-vs-generic` — Choose static dispatch (generics / `impl Trait`) vs dynamic dispatch (`dyn Trait`) deliberately

Generic bounds and `impl Trait` monomorphize at compile time: each concrete type gets its own specialised copy that the compiler can inline and optimise, but every distinct type adds to binary size. `dyn Trait` stores a fat pointer (data + vtable) and dispatches at runtime, producing a single code path — necessary when you must store heterogeneous values or return erased types, at the cost of one pointer indirection per call. Choosing the wrong option either leaves performance on the table or prevents heterogeneous collections entirely. Default to generics for hot, simple code; reach for `dyn` when you need flexibility, heap storage, or cross-crate plug-ins.
**Decision Table:**
| Situation | Prefer |
|---|---|
| Single known concrete type | `impl Trait` / generic |
| Hot path, inlining critical | Generic bound |
| Heterogeneous collection (`Vec<Box<dyn …>>`) | `dyn Trait` |
| Storing trait objects across calls | `dyn Trait` |
| Returning erased type from `fn` | `Box<dyn Trait>` or `impl Trait` (static) |
| Binary size matters, many monomorphisations | `dyn Trait` |
| Plug-in / callback registered at runtime | `dyn Trait` |

### `trait-object-safety` — Keep a trait dyn-compatible (object-safe) when you need `dyn Trait`

Only dyn-compatible traits can be used as `dyn Trait`. The Rust Reference defines dyn compatibility: every method must be dispatchable through a vtable, which means no generic type parameters on methods, no bare `Self` return or value position, and no associated constants. Violating these rules produces a hard compiler error at the `dyn` use site — often far from the trait definition. If you need both generic methods and `dyn Trait`, you can gate the non-dispatchable methods with `where Self: Sized`, which excludes them from the vtable while keeping the rest of the trait object-safe.

### `trait-upcasting` — Use trait-object upcasting for dyn-compatible supertrait relationships (Rust 1.86+)

Rust 1.86 stabilized trait-object upcasting coercions: when `Sub: Super`, a `dyn Sub` trait object can coerce to `dyn Super` as long as the relevant traits are dyn-compatible.
This removes many hand-written `as_supertrait` helpers. It does **not** make non-dyn-compatible traits usable as trait objects, and it does not change ordinary generic trait bounds.
- Prefer: Reference Upcasting
- `Any` Supertraits Become Easier to Use
**Migration Guidance:**
If a pre-1.86 API has an `as_super(&self) -> &dyn Super` method solely to work around the old language limitation, consider removing or deprecating that helper when your MSRV is 1.86 or newer.
Keep a named helper if it has additional semantics, is part of a compatibility promise, or is clearer at a public API boundary. Language support removes the technical necessity, not every possible reason for an explicit method.

## 12. Conversions (MEDIUM)

### `conv-tryfrom-fallible` — Implement `TryFrom` for fallible conversions instead of ad-hoc conversion functions

`TryFrom`/`TryInto` is the standard trait pair for conversions that can fail. Implementing `TryFrom<T>` automatically provides `TryInto` for callers (API Guidelines C-CONV-TRAITS), enabling ergonomic `.try_into()?` at call sites. It integrates naturally with the `?` operator, ecosystem crates, and generic bounds that constrain `T: TryFrom<U>`. Ad-hoc conversion functions scatter the conversion surface and deprive callers of these benefits.

### `conv-fromstr-parsing` — Implement `FromStr` to enable `str::parse` for string-to-type conversions

`FromStr` is the single standard hook for parsing a `&str` into a typed value. Implementing it unlocks the idiomatic `.parse::<T>()` call, integrates with CLI argument parsers (clap, argh), and is the expected interface for serde string-deserializable types. A bespoke `fn parse_foo(s: &str)` forces callers to learn a private name and breaks generic code that constrains `T: FromStr`.

### `conv-asmut-mutable` — Accept `impl AsMut<T>` for flexible mutable borrowed inputs instead of concrete mutable references

`AsMut<T>` is the mutable mirror of `AsRef<T>`. Accepting `impl AsMut<[u8]>` instead of `&mut Vec<u8>` lets callers pass `&mut Vec<u8>`, `&mut [u8]`, or `&mut [u8; N]` arrays without any conversion overhead. This widens the function's usefulness without changing its implementation or runtime cost. Reserve it for genuinely generic write targets — not every `&mut T` parameter needs this treatment.
- When Not to Use

## 13. Const & Compile-Time (MEDIUM)

### `const-block` — Use inline `const { }` blocks for compile-time evaluation and assertions

A `const { }` block (stabilized in Rust 1.79) forces the enclosed expression to be evaluated at compile time, even inside a regular function. This has three practical uses: compile-time assertions that fail the build rather than panicking at runtime; precomputed values inlined at the exact call site without a named `const` item; and initializing arrays of non-`Copy` types that require a per-element constant expression. Catching invariant violations at compile time gives a clearer error message and zero runtime cost.

### `const-fn` — Make functions `const fn` when they can run at compile time

A `const fn` can be called in const contexts — array lengths, `const`/`static` initializers, const-generic arguments — as well as at runtime, so marking a pure, simple function `const` widens where it can be used at zero cost. The compiler evaluates calls in const contexts during compilation, eliminating the work entirely from the binary. Current stable Rust supports most arithmetic, bitwise ops, conditionals, and slice operations in `const fn`; the main restrictions are heap allocation and most trait method calls.

### `const-generics` — Parameterize over values with const generics `<const N: usize>`

Const generics let a single type or function work for any array size — or other constant value — without macros, trait objects, or carrying a runtime length field. The compiler monomorphizes one copy per distinct value, so there is no indirection and no overhead compared to hand-writing the same code for each size. This is the idiomatic way to write generic array-based data structures and algorithms on stable Rust.

### `const-vs-static` — Use `const` for an inlined value and `static` for a single addressed instance

`const` items are substituted at each use site: the compiler copies the value inline, there is no fixed memory address, and the value counts against no storage. This is ideal for small configuration values, bitmasks, and magic numbers. `static` items live at a single address for the entire program lifetime and expose a `'static` reference — use them for large lookup tables you do not want duplicated, or when a `&'static T` is required. Avoid `static mut`: referencing it is a hard error in the 2024 edition. For mutable global state, use atomics (`AtomicUsize`, etc.) or `std::sync::OnceLock`/`std::sync::LazyLock`.
**When to Prefer Which:**
| Situation | Use |
|-----------|-----|
| Small constant (number, bool, tiny array) | `const` |
| String literal | `const` or `static` (both work; prefer `const`) |
| Large lookup table | `static` |
| Need `&'static T` | `static` |
| Mutable counter / flag | `static AtomicXxx` |
| Lazily initialized value | `static LazyLock<T>` |
| Single-writer initialization | `static OnceLock<T>` |

## 14. Serde (MEDIUM)

### `serde-rename-all` — Match the external naming convention with `#[serde(rename_all = ...)]`

Rust fields are `snake_case` by convention, but JSON APIs, GraphQL responses, and config formats often use `camelCase`, `kebab-case`, or `SCREAMING_SNAKE_CASE`. Renaming every field individually with `#[serde(rename = "...")]` is noisy and error-prone. A single `#[serde(rename_all = "camelCase")]` on the container keeps Rust idiomatic and the wire format correct in one declaration.
**Key Points:**
`rename_all` applies to both serialization and deserialization. Supported values:
| Value | Example field `foo_bar` becomes |
|---|---|---|
| `"lowercase"` | `foobar` |
| `"UPPERCASE"` | `FOOBAR` |
| `"PascalCase"` | `FooBar` |
| `"camelCase"` | `fooBar` |
| `"snake_case"` | `foo_bar` (identity) |
| `"SCREAMING_SNAKE_CASE"` | `FOO_BAR` |
| `"kebab-case"` | `foo-bar` |
| `"SCREAMING-KEBAB-CASE"` | `FOO-BAR` |
A field-level `#[serde(rename = "...")]` always wins over the container-level `rename_all`, so use it for exceptions like reserved words or one-off mismatches. For enums, `rename_all` applies to variant names.

### `serde-default-compat` — Use `#[serde(default)]` for optional and backward-compatible fields

Without `#[serde(default)]`, any field missing from an incoming payload causes deserialization to fail with a "missing field" error. When you add new fields to a struct over time, older payloads that predate those fields will suddenly break. Marking fields (or the whole container) with `#[serde(default)]` fills missing keys from the type's `Default` implementation, enabling graceful forward compatibility.
**Key Points:**
- **Field-level** `#[serde(default)]` — fills only that field; other required fields still fail if absent.
- **Field-level** `#[serde(default = "path")]` — calls a user-supplied function `fn() -> T`; use this when `Default` would produce the wrong value (e.g. `timeout = 30` rather than `0`).
- **Container-level** `#[serde(default)]` — applies to every field; the struct must implement `Default` (or `#[derive(Default)]`). Convenient for all-optional structs like feature-flag configs.
- The default function signature must be `fn() -> T` with no arguments and no generics.
- `#[serde(default)]` only affects **deserialization**. It has no effect on serialization; pair with `#[serde(skip_serializing_if = "...")]` if you also want to omit defaults on the way out.
**Caveats:**
Using container-level `#[serde(default)]` makes every field optional to deserializers, which can hide typos in field names. Prefer field-level annotation when only some fields are backward-compatible additions.

### `serde-skip-empty` — Omit empty fields with `skip_serializing_if`

Serializing `None` values as `null` and empty collections as `[]` bloats payloads, clutters logs, and can confuse clients that distinguish between a missing key and an explicit null. `#[serde(skip_serializing_if = "predicate")]` conditionally drops a field from output when the predicate returns true, keeping the wire format lean. `#[serde(skip)]` goes further and excludes a field from both serialization and deserialization entirely.
**Key Points:**
- `skip_serializing_if` takes any path resolving to `fn(&T) -> bool`. Common choices:
  - `Option::is_none` for `Option<T>`
  - `Vec::is_empty` / `<[T]>::is_empty` for collections
  - `String::is_empty` for strings
  - A custom function for more complex conditions
- `#[serde(skip)]` removes the field from **both** directions. The type must implement `Default` so deserialization can still construct the struct (serde fills it with `Default::default()`).
- `#[serde(skip_serializing)]` skips only on the way out; `#[serde(skip_deserializing)]` skips only on the way in — useful when reading legacy fields you no longer write.
- Pair `skip_serializing_if` with `#[serde(default)]` so that a missing key on deserialization also produces the empty/`None` value rather than a hard error.

### `serde-flatten` — Inline nested structs or capture extra keys with `#[serde(flatten)]`

APIs frequently share a common set of fields across multiple message types (pagination metadata, audit timestamps, error envelopes). Duplicating those fields in every struct is fragile. `#[serde(flatten)]` merges a nested struct's fields directly into the parent's wire representation, so the JSON looks flat while the Rust code stays modular. The same attribute can also collect all unknown keys into a `HashMap`, giving you a "catch-all" bucket.
**Key Points:**
- Works with both structs and maps. The flattened type must implement `Serialize`/`Deserialize`.
- Multiple `#[serde(flatten)]` fields are allowed on the same struct, as long as the key sets don't overlap at runtime.
- `HashMap<String, serde_json::Value>` (or any map type) as a flattened field acts as a catch-all for keys not matched by other fields — useful for extensible configs and pass-through proxies.
**Caveats:**
- `#[serde(flatten)]` is **incompatible with `#[serde(deny_unknown_fields)]`** on the same struct. The two attributes conflict because `flatten` needs to forward unrecognized keys.
- Flattening uses a less efficient internal deserialization path (content buffering) compared to normal struct deserialization. Avoid it on extremely hot deserialization paths.
- `flatten` does not work with non-self-describing formats like `bincode` that don't support maps with arbitrary keys.

### `serde-enum-representation` — Choose enum tagging deliberately: externally, internally, adjacently tagged, or untagged

Serde's default enum representation (externally tagged) wraps every variant in an object keyed by variant name. That format can clash with external APIs, event systems, or config schemas that use a discriminator field. Picking the wrong tagging strategy produces a mismatch between your wire format and the expected schema, leading to silent parse failures or round-trip data loss.
**Caveats:**
- **Untagged** deserializes by trying each variant in declaration order; it is slower, can silently pick the wrong variant, and produces generic error messages. Reserve it for small, structurally distinct sets (numbers vs strings).
- **Internally tagged** cannot represent tuple variants or newtype variants wrapping primitives/vecs — use adjacently tagged instead.
- All variants in an internally tagged enum must serialize as maps (structs or `HashMap`).

### `serde-deny-unknown-fields` — Reject unexpected keys with `#[serde(deny_unknown_fields)]`

By default, serde silently discards any key in the input that doesn't match a struct field. For user-facing config files and strict API contracts this is dangerous: a typo like `"timout_secs"` passes validation without error, and the intended field is simply never set. `#[serde(deny_unknown_fields)]` turns unrecognized keys into hard errors, surfacing mistakes immediately.
**Key Points:**
- Apply `deny_unknown_fields` to **config-file structs**, **request/response DTOs**, and any struct that forms a public API contract where typos must be caught.
- Skip it for **flexible or extensible** structs where callers are expected to pass extra metadata. Use `#[serde(flatten)]` with a `HashMap` catch-all instead.
- The attribute works with JSON, TOML, YAML, and most self-describing formats.
- Error messages name the unexpected field, making them actionable for end users.
**Caveats:**
`#[serde(deny_unknown_fields)]` is **incompatible with `#[serde(flatten)]`** on the same struct. `flatten` needs to pass unmatched keys down to the flattened field; `deny_unknown_fields` intercepts them first. If you need both behaviors, split the struct or use a two-pass approach (deserialize into a `serde_json::Value`, then convert).

### `serde-custom-with` — Customize a field's (de)serialization with `with` / `serialize_with` / `deserialize_with`

Some types have a natural Rust representation that differs from what the wire format expects: a `Duration` stored as whole seconds, raw bytes encoded as base64, a timestamp as an ISO-8601 string. Changing the field type just to satisfy serde pollutes the domain model. A `#[serde(with = "module")]` (or the one-sided `serialize_with`/`deserialize_with`) attributes point serde at custom conversion functions without touching the field type.
**Key Points:**
- `#[serde(with = "module")]` requires the module to expose both `pub fn serialize<S>(&T, S) -> Result<S::Ok, S::Error>` and `pub fn deserialize<'de, D>(D) -> Result<T, D::Error>`.
- Use `serialize_with = "path"` or `deserialize_with = "path"` to customize only one direction, leaving the other at its derived default.
- The module approach (`with`) is more reusable: define it once, apply it anywhere. Some crates (e.g. `time`, `chrono`, `uuid`) ship ready-made `with` modules in their serde feature.
- For widespread custom representations, a newtype wrapper with its own `Serialize`/`Deserialize` impl is often cleaner than repeating `#[serde(with = "...")]` everywhere.
**Caveats:**
The `with` module functions must match the exact signatures serde expects. The `serialize` function receives `&T` (a reference), not `T`.

### `serde-try-from-validate` — Validate while deserializing with `#[serde(try_from = "Raw")]`

Running validation after deserialization means you can construct an invalid value in memory, even briefly. Parse-don't-validate says to make invalid states unrepresentable. `#[serde(try_from = "Raw")]` wires the deserializer directly through a `TryFrom` conversion: serde reads the raw type, then your conversion either produces the validated value or returns an error — so an invalid instance is never constructed.
**Key Points:**
- `#[serde(try_from = "Raw")]` — serde deserializes `Raw`, then calls `T::try_from(raw)?`. Any error from `TryFrom` becomes a serde deserialization error.
- `#[serde(into = "Raw")]` — serde calls `Raw::from(value)` for serialization. The type must also implement `Clone` because serde may clone before converting.
- The `Raw` type must itself implement `Deserialize` (for `try_from`) and the target must implement `Into<Raw>` / `From<T> for Raw` (for `into`).
- This pattern is composable with other rules: define the `TryFrom` logic once and reuse it in both serde and non-serde code paths (e.g. CLI argument parsing, form validation).
**Caveats:**
`#[serde(try_from)]` and `#[serde(into)]` are mutually exclusive with deriving `Serialize`/`Deserialize` via field-by-field derivation on the same struct — the attribute replaces the derived impl entirely.

## 15. Pattern Matching (MEDIUM)

### `pat-let-else` — Use `let ... else` for early-return pattern extraction

`let ... else` (stable since Rust 1.65) binds a pattern in the success path or diverges in the `else` branch. It keeps the happy path at the top indentation level and eliminates rightward drift that accumulates when nesting multiple `if let` blocks. The `else` block must diverge via `return`, `continue`, `break`, or a macro like `panic!` or `bail!`.

### `pat-matches-macro` — Use `matches!()` for boolean pattern tests

`matches!(value, Pattern)` is the idiomatic way to ask whether a value matches a pattern when the result itself is a boolean. It avoids a `match` whose only purpose is returning `true` or `false`, and it supports alternation and guards.
Use a normal `match` or `if let` when you need to extract a value for further work or perform different actions per branch.
- Avoid: Boolean-Only `match`

### `pat-if-let-chains` — Use `if let` / `while let` chains to combine pattern bindings and conditions

Let chains (stabilized in Rust 1.88 under the 2024 edition) let you write a single `if` or `while` header that binds multiple patterns and tests arbitrary boolean conditions, all with `&&`. Without chains, each additional binding requires another level of nesting, pushing the happy-path body further right and forcing the reader to track multiple scopes. With chains, all preconditions read left-to-right at the same indentation level.
Rust 1.95 extends the same idea to `match` guards: an arm can use `if let PAT = EXPR` and bind values for use in the arm body. This is useful when the primary dispatch belongs in `match`, but a particular arm has one more fallible/pattern-matching prerequisite.
- Rust 1.95+: `if let` Guards in `match`
- Guard Patterns Do Not Make the Match Exhaustive
**When to Prefer `let ... else`:**
Use `let ... else` when the goal is early return on failure; use `if let` / `while let` chains when you have a richer condition that combines multiple optional bindings with a positive body to execute. Use a `match` `if let` guard when the outer enum/pattern dispatch should remain visibly exhaustive and one arm has an extra fallible condition.

### `pat-exhaustive-enum` — Match owned enums exhaustively; avoid catch-all `_` that hides new variants

A `_ =>` wildcard arm silently absorbs any variant added to an enum you own, converting what should be a compile-time error into a silent runtime no-op. Exhaustive matches let the compiler act as a checklist: add a variant, get a build failure everywhere it is unhandled. Reserve `_` and `..` for **foreign** `#[non_exhaustive]` enums, where the language requires a catch-all, and document why it is necessary.
- When `_` Is Required: Foreign `#[non_exhaustive]` Enums

### `pat-at-bindings` — Use `@` bindings to capture a value while matching it against a pattern

The `name @ pattern` syntax binds the matched value to `name` and simultaneously tests it against `pattern` in a single arm. Without `@`, you either re-access the original expression (verbose) or add a guard that repeats the condition and re-extracts the value (redundant). `@` bindings make the constraint and the binding a single, readable unit.

## 16. Macros (MEDIUM)

### `macro-prefer-functions` — Reach for a macro only when a function or generic cannot express it

Macros operate on token streams before type checking, so they bypass type inference, resist IDE navigation, and produce opaque error messages. They also slow incremental compilation and cannot be passed as values. A generic function is almost always clearer, better-optimized by the compiler, and easier for contributors to reason about.
Reach for a macro only when you genuinely need one of: variadic argument counts, a DSL with non-Rust syntax, blanket trait impls across an open-ended set of types, compile-time format/string checks, or eliminating mechanically repetitive boilerplate that a function truly cannot handle.
**When to Reach for a Macro:**
| Situation | Use a macro? |
|-----------|-------------|
| Fixed argument count, any types | No — use generics |
| Truly variadic argument list (`vec![]`, `println!`) | Yes |
| Implementing a trait for many unrelated types | Yes — `macro_rules!` impl block |
| DSL / embedded syntax (SQL, HTML, regex literals) | Yes — proc-macro |
| Compile-time format string validation | Yes — `format_args!` style |
| Boilerplate a derive could generate | Yes — `#[derive(...)]` proc-macro |
| Simple computation or type conversion | No — use a function or trait |

### `macro-rules-hygiene` — Understand `macro_rules!` mixed-site hygiene and use `$crate` for defining-crate paths

`macro_rules!` does not use one simple “definition-site” or “call-site” rule for every name. It has **mixed-site hygiene**:
- loop labels, block labels, and local variables are looked up at the macro definition site; - most other symbols are looked up at the macro invocation site; - metavariables such as `$name:ident` deliberately carry syntax supplied by the caller; - `$crate` is the special way for a declarative macro to refer to the crate that defined it.
- Avoid: `crate::` in an Exported Macro
- Prefer: `$crate` for Defining-Crate Items
**Key Points:**
- `macro_rules!` uses mixed-site hygiene, not one universal lookup rule.
- Use `$crate::...` for paths back into the crate defining an exported declarative macro.
- Do not use `crate::...` for those defining-crate paths in macros intended for downstream use.
- Metavariables deliberately refer to syntax supplied by the caller.
- Separate macro invocations do not share expansion-created local bindings.
- `$crate` does not bypass visibility checks.

### `macro-fragment-specifiers` — Capture with precise fragment specifiers, not raw `:tt`, where you can

Fragment specifiers tell the compiler — and readers — exactly what syntactic category a macro arm expects. They produce targeted error messages ("expected expression" instead of "no rules expected token"), enable better IDE tooling, and prevent ambiguous parses. Using raw `:tt` (token tree) forces you to re-parse or validate by hand and leaks implementation details into error messages.
Note the **follow-set restriction**: after `:expr`, `:ty`, `:pat`, and a few others, only a limited set of tokens may appear — most commonly `=>`, `,`, `;`, `|`, or another fragment. Plan your separator tokens accordingly.

### `macro-export-crate-path` — Use `#[macro_export]` when a `macro_rules!` macro is part of the public crate API

A plain `macro_rules!` definition has textual scope and crate-local visibility. `#[macro_export]` gives the macro public path-based scope at the **crate root**, regardless of which module contains the definition. Downstream Rust 2018+ code can then call `mycrate::my_macro!(...)` directly or import it with `use mycrate::my_macro;`.
That is different from the older `#[macro_use] extern crate ...` mechanism, which bulk-imports macros into a macro-use prelude. Prefer explicit path-based use in modern code.
- Avoid: Implicit Macro Import
- Prefer: Export at the Crate Root
**Key Points:**
- `#[macro_export]` exports a `macro_rules!` macro from the crate root.
- Rust 2018+ callers can use normal path imports or qualified macro paths.
- Do not re-import the same exported macro name back into the crate root; the root path already exists.
- Re-export from another module only when you intentionally want an additional path.
- Use `$crate::...` for defining-crate helper paths inside exported declarative macros.
- `$crate` does not change item visibility.

### `macro-private-helpers` — Route exported-macro support items through a clearly marked `#[doc(hidden)]` module when call-site visibility requires them to be public

An exported declarative macro expands in another crate. Any helper item referenced by the expansion must therefore be reachable from that call site. A common pattern is a public, documentation-hidden module such as `__private` that exposes only the support surface generated code needs.
`#[doc(hidden)]` is **not** privacy and is **not** a semver exemption. The items remain publicly reachable Rust API. The convention reduces documentation clutter and signals “implementation detail,” but downstream code can still name the path. Keep the surface small and coordinate changes with the macros that generate references to it.
- Avoid: Scatter Helpers Across the Crate Root
- Prefer: Concentrate the Required Public Support Surface
**Key Points:**
- `#[doc(hidden)]` hides rendered documentation; it does not change Rust visibility.
- `$crate::__private::...` is the robust path form for declarative macros referring back to their defining crate.
- Keep the hidden public module narrow.
- For procedural macros, coordinate the facade/runtime API with generated paths and dependency-renaming behavior.

### `macro-proc-two-crate` — Put procedural macros in a dedicated `proc-macro = true` crate and re-export them from the ordinary library facade

A procedural macro must live in a crate whose library target has `proc-macro = true`. Such a crate exports procedural macros, not an ordinary public library API. If one product needs both a normal Rust API and derives/attributes/function-like procedural macros, the usual structure is therefore two crates:
- `mycrate` — the ordinary library and public facade; - `mycrate-derive` or `mycrate-macros` — the `proc-macro = true` implementation crate.
- Avoid: Trying to Export Ordinary API from a Proc-Macro Crate
- Prefer: Facade + Proc-Macro Crate
- Generated Paths: Do Not Blindly Hardcode `::mycrate`
**Key Points:**
- Procedural macros require a `proc-macro = true` crate.
- Put normal traits/types/functions in an ordinary library crate and commonly re-export macros from that facade.
- Procedural macro output is unhygienic; use explicit, collision-resistant, appropriately qualified paths.
- There is no procedural `$crate` equivalent for finding the facade crate.
- Hardcoding `::mycrate` breaks when downstream users rename the dependency.
- Use a path override or a crate-name resolver such as `proc-macro-crate` when generated code must refer back to the facade.
- Helpers reached by generated downstream code need real visibility even if hidden from rustdoc.

### `macro-proc-syn-quote` — Put proc-macro parsing and generation in testable `syn`/`quote` helpers

Procedural macros have two different concerns: a thin compiler-facing entry point using `proc_macro::TokenStream`, and ordinary transformation logic that parses syntax, validates it, and generates tokens. Keeping most logic in helpers built around `syn`, `quote`, and `proc-macro2` makes the transformation easier to read and lets normal unit tests exercise it outside a proc-macro invocation.
Use only the `syn` features required by the syntax you parse. A derive macro usually needs `DeriveInput`; `full` is useful only when you genuinely parse the wider Rust grammar.

### `macro-proc-error-spans` — Turn expected proc-macro input errors into spanned compile errors instead of panics

Invalid user input to a procedural macro is an ordinary compile-time error, not an internal crash. `syn::Error` can carry a source span and produce `compile_error!` tokens, so the diagnostic points at the relevant input. Reserve panics for genuine bugs or violated internal invariants, not for supported input validation.
A useful architecture separates a `proc_macro2::TokenStream` expansion helper from the compiler-only proc-macro entry point. The helper can return `syn::Result<_>` and can be unit-tested in an ordinary Rust context.
**Choosing the Span:**
Use `Error::new_spanned(value, message)` when you have a syntax-tree node or tokens representing the offending input. Use `Error::new(span, message)` when you already have the precise span. Point at the smallest useful input that tells the caller what to change.
When validation can discover independent problems in one pass, `syn::Error::combine` can aggregate them before converting to compile-error tokens. Returning the first error is also reasonable when later validation depends on earlier invariants.

## 17. Closures (MEDIUM)

### `closure-fn-trait-bounds` — Require the least restrictive `Fn` trait a callback needs (`FnOnce` ⊇ `FnMut` ⊇ `Fn`)

`FnOnce` is implemented by every closure — it may consume its captures and can only be called once. `FnMut` is implemented by closures that mutate captures, and implies `FnOnce`. `Fn` is the strictest: it only reads captures and can be called any number of times concurrently. Bounding a parameter with the weakest trait the body actually requires accepts the widest set of callers. Requiring `Fn` when you only call the closure once needlessly rejects move-consuming closures.
**Key Points:**
| Trait | Captures | Calls | Accepts |
|-------|----------|-------|---------|
| `FnOnce` | may consume | exactly once | all closures |
| `FnMut` | may mutate | multiple | non-consuming |
| `Fn` | read-only | multiple / shared | pure closures |
- `FnMut` requires `mut f` at the call site (the parameter or binding must be `mut`).
- `Fn: FnMut: FnOnce` — a `Fn` closure satisfies an `FnOnce` bound, not the other way around.
- Standard library examples: `Iterator::map` uses `FnMut`; `thread::spawn` uses `FnOnce + Send + 'static`.

### `closure-impl-fn-return` — Return closures as `impl Fn`/`FnMut`/`FnOnce`, not `Box<dyn Fn>`

`impl Fn` in return position names the closure's concrete (but unnameable) type and enables static dispatch with no heap allocation. `Box<dyn Fn>` adds an allocation and a virtual call every time the closure is invoked. The opaque `impl Trait` syntax was designed precisely for this use case. Reach for `Box<dyn Fn>` only when the function must return *different* closure types depending on runtime conditions, or when the closure must be stored in a struct field or collection.
**Key Points:**
**When `Box<dyn Fn>` is required:**
Different `if`/`match` arms return distinct closure types, so `impl Fn` cannot unify them:
**Returning `FnMut`:** The binding at the call site must be `mut`.

### `closure-move-capture` — Use `move` for closures that outlive the current scope; clone before `move` to keep the original

A closure that borrows its environment can only live as long as that environment. When a closure escapes — passed to a new thread, stored in a struct, or returned from a function — it must own its captures and typically must be `'static`. The `move` keyword transfers ownership of every captured variable into the closure. If you need the value in both the closure and the surrounding code, clone it first and move the clone.
**Key Points:**
- **Thread closures** passed to `std::thread::spawn` must be `'static`, which `move` enables when all captured types are `'static + Send`.
- **Clone selectively:** clone only what the closure needs, not the whole owning struct — see [closure-disjoint-capture](closure-disjoint-capture.md).
- **Async tasks** follow the same rule: `tokio::spawn(async move { … })` takes ownership; clone shared data before the `async move` block.
- A `move` closure can still implement `Fn` or `FnMut` — `move` only controls *how* captures are taken, not how many times the closure can be called.

### `closure-static-vs-dyn` — Accept `impl Fn` (generic) for hot callbacks; use `&dyn Fn`/`Box<dyn Fn>` to cut code size or to store them

A generic parameter `F: Fn(…) -> …` (or `impl Fn`) monomorphizes at each call site: the compiler emits a specialized copy of the function, enabling inlining and zero-cost dispatch. The trade-off is binary bloat when many different closure types are substituted. `&dyn Fn`/`Box<dyn Fn>` share a single compiled copy via a vtable, which reduces code size and is the only option for storing heterogeneous closures (e.g. an event handler registry). Choose by profiling requirements, not habit.
**Decision Table:**
| Situation | Use |
|-----------|-----|
| Hot inner loop, single call site | `impl Fn` / generic `F: Fn` |
| Callback stored in a struct field | `Box<dyn Fn>` |
| Collection of mixed closures | `Vec<Box<dyn Fn(…)>>` |
| Pass-through, one level deep, not stored | `&dyn Fn` (avoids allocation) |
| Called across an `await` point | `Box<dyn Fn + Send>` |
**Note:** `&dyn Fn` is useful to avoid an allocation when you only need to borrow the closure for one call and do not store it. Pass `&closure` (reference to a stack-allocated closure) rather than boxing.

### `closure-disjoint-capture` — Capture only what you use; lean on edition-2021 disjoint closure captures

Before the 2021 edition, a closure captured entire variables — using `config.threshold` pulled in the whole `config` struct, preventing other code from using any other field of `config` concurrently. Since Rust 2021, closures capture individual fields (`config.threshold` only), so sibling fields remain independently accessible. Take advantage of this: write closures that reference only the specific fields or values they need, and add `move` only when ownership is genuinely required. When you do need to `move` a single field, bind it to a local first so the rest of the struct stays usable.
**Key Points:**
- **Edition 2021 rule:** closures capture the *minimal* path used — `foo.bar` rather than `foo`. This reduces spurious borrow conflicts.
- **`move` captures the whole named place.** Writing `move || self.field` inside a method moves `*self`, not just `self.field`. Bind to a local to narrow the capture.
- **Copy types** (integers, booleans) are copied into the closure rather than moved, so the original remains valid even with `move`.
- **Borrow by reference first:** only escalate to `move` when the closure must outlive the scope (see [closure-move-capture](closure-move-capture.md)).

### `closure-async-closures` — Use async closures when a callback future needs to borrow from closure captures; use `AsyncFn*` bounds for higher-order async callbacks

Async closures (`async || { ... }`) stabilized in Rust 1.85. Like an `async fn`, calling one produces a future. Their important advantage over the older `|| async { ... }` pattern is **lending**: the future returned by an async closure can borrow from the closure's captured state.
That matters for callbacks which must keep a borrow of a captured value across an `.await`. Rust also provides the `AsyncFn`, `AsyncFnMut`, and `AsyncFnOnce` traits for higher-order APIs that accept asynchronous callables.
- Avoid: A Regular Closure Returning an Async Block
- Prefer: Borrow Captures Across `.await`
- Do Not Claim an Allocation Difference Without Measuring
**Decision Guide:**
| Need | Prefer |
|------|--------|
| Async callback future borrows captured state | `async || { ... }` |
| Higher-order async callback with lending | `AsyncFn*` bound |
| Simple one-off spawned operation | `tokio::spawn(async move { ... })` |
| Regular closure returning an owned/non-lending future | `|| async move { ... }` can be fine |
| Synchronous OS thread closure | ordinary closure; explicitly run an executor if async work is truly required there |
**Key Points:**
- Async closures and the `AsyncFn*` traits are stable since Rust 1.85.
- Their key ergonomic capability is allowing returned futures to borrow from closure captures and callback arguments.
- Ordinary `Fn`/`FnMut` bounds cannot express all lending async-callback relationships; use `AsyncFn*` where that relationship matters.
- `async move ||` moves captures into the closure, but calling it still returns a future that needs an executor.
- Do not use `std::thread::spawn(async || { ... })` as an async task-spawning primitive.
- Choose call-trait bounds from what callers need; do not mechanically force `FnOnce` merely because a callback is async.

## 18. Collections (MEDIUM)

### `coll-binaryheap` — Use `BinaryHeap` for a priority queue or repeated max-extraction

`std::collections::BinaryHeap<T>` is a max-heap with O(log n) `push` and `pop` (extract-max) and O(1) `peek`. When you repeatedly need the largest (or smallest) element from a growing or shrinking set, it beats sorting a `Vec` after every insertion — sorting is O(n log n) each time, while a heap amortises that cost to O(log n) per operation. For a **min-heap**, wrap your values in `std::cmp::Reverse<T>`; the heap's ordering flips, and the smallest value is extracted first.

### `coll-map-choice` — Pick the map by access pattern: `HashMap` (fast, unordered), `BTreeMap` (sorted / range queries), `IndexMap` (insertion order)

`HashMap` is the right default: O(1) average lookup and insertion with no ordering overhead. `BTreeMap` keeps keys sorted in a B-tree, enabling efficient range queries and ordered iteration at the cost of O(log n) operations. The `indexmap` crate's `IndexMap` preserves insertion order with O(1) average lookup — valuable for deterministic output, config files, or any API where output order must match input order. Choosing the wrong map wastes CPU cycles on sorting you don't need or forces you to sort after the fact.
**Which to Use:**
| Requirement | Choose |
|---|---|
| Fast lookup, order irrelevant | `HashMap` |
| Sorted iteration or range queries | `BTreeMap` |
| Insertion-order iteration + fast lookup | `IndexMap` (indexmap crate) |
| Tiny map (≤ 8 entries), no heap | consider an array of tuples |
**Note on hashing:** The default `HashMap` uses SipHash-1-3, which is DOS-resistant but not the fastest. For non-adversarial hot paths, see `perf-ahash` for a faster hasher that drops in as a type parameter.

### `coll-seq-choice` — Default to `Vec`; use `VecDeque` for queue/deque behaviour; avoid `LinkedList`

`Vec<T>` is a contiguous growable array — the right sequence type for almost every use case. Contiguous layout means the CPU prefetcher works in your favour and each element is a single pointer dereference away. `VecDeque<T>` is a ring buffer with O(1) amortised push and pop at **both** ends; reach for it when you need a FIFO queue or a sliding window. `LinkedList<T>` is heap-allocated per node and pointer-chased on every access; in practice it is almost always slower than `Vec` or `VecDeque` for real workloads, and the standard library itself discourages its use.
**Which to Use:**
| Requirement | Choose |
|---|---|
| General-purpose growable list | `Vec<T>` |
| FIFO queue, deque, or sliding window | `VecDeque<T>` |
| Need O(1) split/splice at arbitrary positions | consider `VecDeque<T>` or rethink the design |
| Linked list (almost never) | `LinkedList<T>` — only if profiling proves it faster |
**Conversion:** `Vec` and `VecDeque` convert cheaply into each other via `From`/`Into` when you need to switch representation.

### `coll-set-membership` — Use `HashSet`/`BTreeSet` for membership tests and dedup, not linear `Vec::contains`

`Vec::contains` is O(n) per call. When you check membership for m items against a list of n items in a loop, the total cost is O(n × m) — quadratic. A `HashSet` reduces each check to O(1) average, making the same loop O(n + m). Use `BTreeSet` when you also need sorted iteration or range queries. Keep a `Vec` only when order matters, duplicates are intentional, or the collection is so small (say, ≤ 8 items) that the overhead of hashing outweighs the savings.
Deduplication follows the same rule: collecting into a `HashSet` is one line and O(n), while repeatedly removing duplicates from a sorted `Vec` is more code and no faster.
**Which to Use:**
| Requirement | Choose |
|---|---|
| Fast membership test, no ordering needed | `HashSet<T>` |
| Membership test + sorted iteration | `BTreeSet<T>` |
| Tiny set (≤ 8 items) | `Vec<T>` with `.contains` may be fine |
| Keep duplicates or care about insertion order | `Vec<T>` |
**Tip:** when building a `HashSet` that will be queried many times, call `HashSet::with_capacity(n)` upfront to avoid rehashing. See `mem-with-capacity`.

## 19. Naming Conventions (MEDIUM)

### `name-types-camel` — Use `UpperCamelCase` for structs, enums, traits, type aliases, and other type-level names

Rust's type-level naming convention is `UpperCamelCase`. The built-in `non_camel_case_types` lint warns by default, and following the convention makes type names visually distinct from functions, variables, and modules.

### `name-variants-camel` — Use `UpperCamelCase` for enum variants

Enum variants follow the same naming convention as types—`UpperCamelCase`. This distinguishes them from fields, variables, and functions. The compiler warns on violations, and consistent naming helps readers instantly recognize variant names.

### `name-funcs-snake` — Use `snake_case` for functions, methods, variables, and modules

Rust's conventional value-level names use `snake_case`. The built-in naming lints warn about non-snake-case functions, methods, variables, and modules by default, and ecosystem code overwhelmingly follows the convention.
Consistent casing makes roles easy to scan: `HttpClient` looks like a type while `send_request` looks like an operation.
- Names Should Still Be Specific

### `name-consts-screaming` — Use `SCREAMING_SNAKE_CASE` for constants and statics

Rust convention uses `SCREAMING_SNAKE_CASE` for both `const` and `static` items, making named global values visually distinct from locals and ordinary functions.
The two item kinds are not otherwise interchangeable:
- Prefer `const` When Identity Is Not Needed

### `name-lifetime-short` — Keep lifetime parameter names short and lowercase; use `'a` by default and descriptive names such as `'src` when they add real meaning

Rust's API Guidelines recommend short lowercase lifetime names, usually a single letter. A single unconstrained borrow is conventionally `'a`; multiple generic lifetimes often use `'a`, `'b`, and so on.
Descriptive short names such as `'src`, `'ctx`, or Serde's `'de` are useful when the lifetime has a semantic role that matters to readers. Longer names are not wrong Rust—the goal is readable signatures, not minimizing character count at any cost.
- Prefer Elision When the Relationship Is Obvious
- Use `'a` for a Simple Named Relationship
- Avoid Invalid Independent Output Lifetimes
**Practical Guidance:**
- Elide lifetimes when Rust's elision rules express the relationship clearly.
- Use `'a`, `'b`, etc. for ordinary generic borrow relationships.
- Use short descriptive names such as `'src` or `'ctx` when they genuinely clarify roles.
- Reserve `'de` for Serde's deserializer lifetime; do not name a borrowed derive target's own lifetime `'de`.
- Treat `'static` as a semantic lifetime, not a naming convention.
- Prefer names that make lifetime relationships understandable rather than enforcing one-character names mechanically.

### `name-type-param-single` — Use concise `UpperCamelCase` type-parameter names—often `T`, `E`, `K`, `V`, but descriptive names are appropriate when they improve clarity

Rust's API Guidelines recommend **concise `UpperCamelCase`** names for type parameters and say they are **usually** a single uppercase letter such as `T`. That is a convention, not a rule that every generic parameter must be one character.
Single-letter names work well when the role is conventional and visible from context. Descriptive type-parameter names are often clearer in APIs with several independent roles or where a single letter would force readers to decode the signature.
- Trait Bounds Do Not Require Long Parameter Names
- Do Not Rename Stable Public Parameters Casually
**Practical Guidance:**
- Follow `UpperCamelCase` for type parameters.
- Prefer conventional single letters when the role is obvious: `T`, `E`, `K`, `V`, `F`.
- Use concise descriptive names when multiple semantic roles would otherwise be hard to decode.
- Avoid redundant `Type` suffixes unless they genuinely disambiguate a domain term.
- Put complex bounds in `where` clauses for readability; do not encode the bounds into the parameter name.
- Treat letter meanings as local conventions, not reserved language meanings.

### `name-as-free` — Use `as_` for free borrowed conversions

Rust's ad-hoc conversion naming convention communicates both ownership and expected cost. An `as_` method is for a **free borrowed-to-borrowed conversion**: it does not consume the receiver and should not perform allocation or other nontrivial work.
The result is often a reference, but not necessarily. For example, the standard library also uses `as_ptr()` for free raw-pointer views.

### `name-to-expensive` — Use `to_` for ad-hoc conversions that do nontrivial work without consuming a non-Copy receiver

Rust's `to_` convention says that an ad-hoc conversion performs nontrivial work. Allocation and cloning are common examples, but `to_` is not limited to conversions that produce an owned value: an expensive borrowed-to-borrowed conversion can also use `to_`.
The Rust API Guidelines distinguish the three conversion prefixes this way:

### `name-into-ownership` — Use `into_` for ad-hoc conversions that consume an owned value and produce another owned representation

Rust's API Guidelines use `as_`, `to_`, and `into_` to communicate both ownership and approximate cost shape:
| Prefix | Typical ownership | Cost | |---|---|---| | `as_` | borrowed → borrowed | free / trivial view | | `to_` | borrowed → owned, or a nontrivial borrowed conversion | potentially expensive | | `into_` | owned → owned for non-`Copy` values | variable |
**Clippy Enforcement:**
`clippy::wrong_self_convention` checks that an `into_*` method takes `self` by value. It also checks the conventional receiver shapes of `as_*`, `is_*`, and `to_*` methods.
This is a naming/receiver convention lint, not proof that a conversion has a particular performance or failure behavior.
**Practical Guidance:**
- Use `into_foo(self)` when consuming a non-`Copy` owner to produce owned `foo` data.
- Do not read `into_` as “free”; the cost is intentionally variable.
- Do not read `into_` as “infallible”; consuming conversions may return `Result`.
- Use `From`/`TryFrom` when the conversion naturally belongs in the standard conversion trait ecosystem.
- Implement `IntoIterator` for consuming collection iteration rather than only inventing an inherent method.
- Let the method name describe the semantic target (`into_inner`, `into_bytes`, `into_parts`) rather than only the fact that failure is possible.

### `name-no-get-prefix` — Omit `get_` for ordinary named getters; reserve `get` for APIs where “get the one obvious value” or validated/indexed access is the established operation

Rust's API Guidelines normally name a getter after the thing it returns:
- `first()` rather than `get_first()`; - `first_mut()` rather than `get_first_mut()`; - `name()` rather than `get_name()`.
**Practical Guidance:**
- Name ordinary property getters `name()`, `value()`, `first()`, etc.
- Name mutable counterparts `name_mut()`, `value_mut()`, `first_mut()`.
- Use plain `get()` when there is one obvious contained value or when the abstraction has an established checked/keyed access operation.
- Use `get_mut` / `_unchecked` families only when those operation families actually exist semantically.
- Name domain lookups for what they select (`current_config`, `user_by_id`) instead of blindly prefixing `get_`.
- Distinguish getters from representation conversions such as `as_` / `into_`.

### `name-is-has-bool` — Name boolean methods as clear predicates; use `is_`, `has_`, `can_`, and similar prefixes when they match the question being answered

A boolean-returning API should read like a predicate at the call site. `is_empty()`, `has_permission()`, and `can_retry()` make their intent obvious, but Rust does **not** require every boolean method to begin with one of these prefixes. Standard APIs also use verbs and verb phrases such as `contains`, `starts_with`, `ends_with`, and `eq_ignore_ascii_case`.
Choose the name that describes the question naturally rather than mechanically adding `is_` to every `bool` return.
- Boolean Methods Need Not Use a Prefix
- Prefer Positive Predicates
**Practical Guidance:**
- Use `is_foo` for state/property predicates when it reads naturally.
- Use `has_foo`, `can_foo`, `should_foo`, or `needs_foo` only when those verbs match the domain meaning.
- Keep natural verb predicates such as `contains` and `starts_with` as verbs; do not prefix them mechanically.
- Prefer positive predicate names unless the negative condition is itself a meaningful state.
- Do not hide surprising side effects behind a predicate-sounding name.
- Treat Clippy's receiver convention as a syntactic convention, not a complete API-design rule.

### `name-iter-convention` — For collection-wide traversal, use the conventional `iter`, `iter_mut`, and `IntoIterator` ownership shapes

Rust collections use a predictable trio for ordinary traversal:
- `iter(&self)` borrows the collection and yields borrowed data; - `iter_mut(&mut self)` mutably borrows it and yields mutable borrowed data where that makes sense; - `IntoIterator` for the owned collection consumes it and yields owned items.
- Specialized Iterators Keep Semantic Names
**Practical Guidance:**
- Use `iter` for ordinary shared traversal of a collection.
- Use `iter_mut` for the corresponding mutable traversal when the abstraction supports it.
- Implement `IntoIterator` for consuming traversal and commonly for `&Collection` / `&mut Collection` too.
- Let the collection define the logical item shape; maps and other structures need not yield a single `&T`.
- Give specialized iterator-producing methods semantic names such as `keys`, `values`, `neighbors`, or `lines`.
- Do not demonstrate the convention with illegal inherent implementations on `Vec`, `HashMap`, or other foreign types.

### `name-iter-method` — Implement `IntoIterator` delegation for `for` loop support

While `name-iter-convention.md` covers the three-method pattern (`iter()`, `iter_mut()`, `into_iter()`), this rule covers `IntoIterator` trait delegation. Implementing `IntoIterator` for `&C`, `&mut C`, and `C` enables idiomatic `for` loop syntax. The standard library convention is clear: `IntoIterator for &C` delegates to `iter()`, and `IntoIterator for &mut C` delegates to `iter_mut()`.
Rust has a strong convention for iterator method names. Following these conventions makes your types work predictably with `for` loops and iterator adapters. Users expect `iter()` for shared references, `iter_mut()` for mutable references, and `into_iter()` for owned iteration.

### `name-iter-type-match` — Name public iterator types after the methods or functions that produce them

Rust's API Guidelines pair iterator-producing method names with predictable iterator type names:
| Producer | Typical public iterator type | |---|---| | `iter()` | `Iter` | | `iter_mut()` | `IterMut` | | `into_iter()` | `IntoIter` | | `keys()` | `Keys` | | `values()` | `Values` | | `values_mut()` | `ValuesMut` | | `drain()` | `Drain` | | `windows()` | `Windows` |
- Do Not Demonstrate the Convention with Illegal Foreign Inherent Impls
**Practical Guidance:**
- Match named iterator types to their producer names: `iter` → `Iter`, `keys` → `Keys`, and so on.
- Let the module path carry collection context instead of redundantly naming the collection in every iterator type.
- Give custom semantic producers matching types such as `Nodes` or `Neighbors`.
- Use `impl Iterator` when callers do not need the concrete iterator type.
- Add lifetimes/generics only when the iterator representation and item type need them.
- Do not use illegal inherent impls on standard-library types as supposedly compilable examples.

### `name-acronym-word` — In `UpperCamelCase`, treat acronyms as ordinary words: `HttpServer`, `Uuid`, `TcpStream`

Rust's naming convention treats acronyms and contractions as words when forming `UpperCamelCase`. That gives predictable word boundaries and matches the standard library: `TcpStream`, `UdpSocket`, `IpAddr`, `Ipv4Addr`, `TypeId`.
In `snake_case`, acronym words are simply lowercase: `parse_json`, `http_status`, `user_id`.
**Clippy Enforcement:**
Enable Clippy's style lint in `Cargo.toml` if you want automated enforcement:
Clippy also supports a more aggressive mode in **`clippy.toml`** (or `.clippy.toml`):
The aggressive option makes the lint trigger on more adjacent-uppercase cases. It is not a nested `[lints.rust]` setting in `.cargo/config.toml`.
**Practical Guidance:**
- In `UpperCamelCase`, write acronym words like ordinary words: `Http`, `Json`, `Uuid`, `Tcp`.
- In `snake_case`, lowercase them normally: `http`, `json`, `uuid`, `tcp`.
- Keep numbers naturally attached: `Utf8`, `Ipv4`, `Base64`.
- Preserve established domain terms such as `CStr` when they are the conventional name.
- Put `upper-case-acronyms-aggressive` in `clippy.toml` if you opt into aggressive Clippy enforcement.
- Avoid gratuitous renames of already-public APIs solely for style.

### `name-crate-no-rs` — Avoid `-rs`, `-rust`, `rust-`, and similar language-only affixes in crate/package names

The Rust API Guidelines explicitly recommend against `-rs` and `-rust` as crate-name prefixes or suffixes: the implementation language is already implied by the ecosystem. Prefer a name that identifies the library, protocol, domain, binding target, or other distinguishing purpose.
This is a naming guideline, not a registry rule. Cargo and crates.io can accept names containing `rust` or `rs`, and a real collision or cross-language repository family can justify disambiguation.
- Prefer Descriptive Names
**Decision Guide:**
| Situation | Prefer |
|---|---|
| Ordinary Rust library | Descriptive package name without language affix |
| Low-level native bindings | Conventional `-sys` name |
| Wrapper for a named external project | Name that identifies the wrapped project/purpose |
| Repository must distinguish several language implementations | Repository-specific suffix may be reasonable |
| crates.io/package namespace collision | Choose a meaningful qualifier before falling back to language-only noise |

### `name-feature` — Name Cargo features without placeholder words like `abc`, `use-abc`, or `with-abc`

Cargo features are conditional compilation flags. Feature names should be descriptive and free of placeholder words (`abc`, `use-`, `with-`) that add noise without conveying meaning. The Cargo convention favors clean, concise feature names that describe what functionality is enabled.

### `name-word-order` — Keep compound names in a consistent, idiomatic word order

Rust's API Guidelines recommend consistency in the order of words in compound names. For similar error types, the standard library commonly uses **verb-object-error** names such as `ParseIntError`, `ParseBoolError`, `JoinPathsError`, and `StripPrefixError`.
The important rule is not that every Rust type must start with a verb. Use ordinary English modifier-noun order for names such as `HttpServer` and `TcpListener`, and match established terminology in the surrounding API. Prefer consistency with closely related standard-library or crate-local names over mechanically rearranging words.
**Decision Guide:**
| Situation | Prefer | Example |
|-----------|--------|---------|
| Family of operation errors | Match the family's established order | `ParseIntError`, `ParseWidgetError` |
| Modifier + noun | Natural English order | `HttpServer`, `TcpListener` |
| Existing public API family | Consistency with sibling names | `FooReader`, `FooWriter` |
| No established convention | Pick a clear order and use it consistently | crate-specific |
The guideline is **consistent word order**, not a universal grammar rule that every compound Rust name must be verb-first.

## 20. Testing (MEDIUM)

### `test-cfg-test-module` — Put unit tests in `#[cfg(test)] mod tests { }` within each module

The `#[cfg(test)]` attribute ensures test code is only compiled during `cargo test`, not in release builds. Placing tests in a `tests` submodule within the same file keeps tests close to the code they test while maintaining separation. This is Rust's idiomatic unit test pattern.

### `test-use-super` — Use `use super::*;` in test modules to access parent module items

The test module is a child of the module being tested. `use super::*` imports all items from the parent module, including private ones. This gives tests access to both public API and internal implementation details for thorough testing.

### `test-integration-dir` — Put external-API integration tests in Cargo's `tests/` targets

Cargo treats top-level integration-test targets under `tests/` as separate crates that depend on the package as an external user would. They can access the library's public API, not its private implementation details.
This complements unit tests inside `src/`: unit tests can exercise private helpers, while integration tests verify that the public package boundary is actually usable.
- Avoid: Calling a Unit Test an Integration Test
- Prefer: Exercise the Public API
- Invalidation Tests Should Reuse the Old Capability

### `test-descriptive-names` — Use descriptive test names that explain what is being tested

Test names appear in test output and serve as documentation. A good test name tells you what behavior is being verified without reading the test body. When a test fails, a descriptive name immediately tells you what broke.

### `test-arrange-act-assert` — Structure tests with clear Arrange, Act, Assert sections

The AAA pattern makes tests readable and maintainable. Each section has a clear purpose: set up test data, execute the code under test, verify the results. This structure helps identify what's being tested and makes tests easier to debug when they fail.

### `test-proptest-properties` — Use proptest for property-based testing

Property-based testing generates random inputs to verify that properties hold across all possible values, not just hand-picked examples. Proptest finds edge cases you wouldn't think to test manually—empty strings, integer overflows, unicode edge cases.

### `test-mockall-mocking` — Use mockall for trait mocking

Unit tests should isolate the code under test from external dependencies (databases, APIs, file systems). Mockall generates mock implementations of traits, allowing you to control and verify behavior without real dependencies.

### `test-mock-traits` — Put meaningful external dependencies behind replaceable boundaries when that improves testing

A service that directly constructs and calls a database, clock, HTTP client, filesystem wrapper, or other external dependency is harder to exercise deterministically. A trait can define the small capability the service actually needs, allowing production and test implementations to be injected separately.
Do not introduce a trait solely because “tests need mocks.” Prefer the narrowest useful seam: a plain function parameter, generic closure, concrete in-memory implementation, or trait depending on the shape and reuse of the dependency.

### `test-fixture-raii` — Use RAII for owned test resources; do not confuse cleanup with safe mutation of process-global state

Tests often acquire resources that should be released on every ordinary scope exit: temporary directories, files, sockets, transactions, or server handles. Putting cleanup in `Drop` (directly or through a library type that already implements it) couples the lifetime of the cleanup action to the resource and also runs during normal panic unwinding.
RAII is not a universal teardown mechanism. It does not run after process abort/kill, and restoring process-global state in `Drop` does not make concurrent mutation of that state safe.

### `test-tokio-async` — Use `#[tokio::test]` for ordinary Tokio-driven async tests, and configure the runtime flavor only when the test needs it

Calling an `async fn` produces a future; something still has to poll that future. Rust's built-in `#[test]` harness expects a synchronous test function, so Tokio tests commonly use `#[tokio::test]` to create a runtime and drive the async body.
A manually built runtime is valid when you need custom setup. `#[tokio::test]` is the concise default, not the only correct approach.
- Manual Runtime When You Need Builder Control

### `test-should-panic` — Use `#[should_panic]` for tests whose success condition is a deliberate panic

A normal Rust test passes when it returns successfully. `#[should_panic]` inverts that condition: the test passes only if it panics.
Use it for APIs whose contract intentionally includes a panic, such as invariant violations or operations documented to reject invalid programmer input. Do not use panic tests for recoverable errors that should be represented with `Result` or `Option`.
- Prefer: Test an Intentional Panic
- Prefer: Test an Invariant at Construction
- Do Not Use `should_panic` for Recoverable Errors
- `should_panic` Tests Must Return `()`
- When `catch_unwind` Is Appropriate
**Practical Guidance:**
- Use plain `#[should_panic]` when any panic is sufficient.
- Add `expected = "..."` when distinguishing the intended panic from an accidental one matters.
- Match messages your code owns; dependency/compiler panic wording can change.
- Prefer `Result`/`Option` assertions for recoverable failures.
- Prefer `assert_matches!` for returned enum shapes.
- Use `catch_unwind` only when the test needs control after the panic.

### `test-criterion-bench` — Use `criterion` for benchmarking (or `divan` for simpler workflows)

Benchmarking requires statistical rigor — warmup, multiple iterations, outlier detection. `criterion` is the standard for statistical CI benchmarks. For simpler use cases, `divan` (4.6M+ downloads, v0.1.21) provides a zero-config attribute-based API. For instruction-level analysis, use `iai-callgrind`.

### `test-doctest-examples` — Keep public documentation examples executable as doctests when practical

Rustdoc can compile and run Rust code fences embedded in documentation. That turns examples into compatibility tests: when an API changes, stale examples fail instead of silently teaching code that no longer works.
Not every documentation block should run. Rustdoc provides `no_run`, `compile_fail`, platform-specific ignore attributes, and `ignore` for cases where execution or compilation is intentionally unsuitable. Prefer the narrowest truthful fence behavior.
- Avoid: Example-Shaped Prose Is Not Tested
- Prefer: Use a Rust Code Fence

### `test-loom-concurrency` — Use `loom` to exhaustively test lock-free and concurrent code

Probabilistic stress tests can run millions of iterations and still miss a race condition that only manifests under a specific thread interleaving. `loom` systematically explores every thread scheduling and memory-reordering permitted by the C11 memory model, turning "we ran it a lot and it seemed fine" into a proof of correctness for the interleavings that exist within the model bounds. Tokio uses loom to verify its internal synchronization primitives.
**Key Points:**
- Keep loom model closures **small**: combinatorial explosion grows with the number of atomic operations and threads. Test one primitive or algorithm at a time.
- loom replaces `std::sync::atomic`, `std::sync::Mutex`, `std::thread`, and `std::cell` with instrumented equivalents — import from `loom::` under `#[cfg(loom)]`.
- Use `loom::model(|| { ... })` as the entry point; loom runs the closure repeatedly under different schedules.
- loom checks the C11 model — it does not detect logical bugs unrelated to concurrency.

### `test-snapshot-testing` — Use snapshot tests for complex output that humans should review as a whole

Large structured output—rendered diagnostics, pretty-printed state, generated code, CLI output, or serialized documents—can be awkward to maintain as long hand-written literals. Snapshot testing stores the approved output separately and presents diffs when it changes.
The value is reviewability, not avoiding assertions. A snapshot is still a test oracle and should represent output that the project intentionally wants to keep stable enough to review.
- Avoid: Large Inline Golden String
- Prefer: Snapshot Structured Output
- CI Must Not Auto-Accept Changes

### `test-assert-matches` — Use `assert_matches!` / `debug_assert_matches!` (Rust 1.96+) for pattern-based assertions

Pattern matching on test results is common—checking enum variants, error kinds, or partial data. `assert!(matches!(..))` gives little information about the actual value on failure. `assert_matches!`, stabilized in Rust 1.96, prints the debug representation of the value that failed to match.
Import the macros explicitly when needed with `use std::{assert_matches, debug_assert_matches};`.

### `test-coverage-llvm-cov` — Use `cargo-llvm-cov` for LLVM-based code coverage

LLVM source-based code coverage provides accurate, region-level coverage data across all platforms (Linux, macOS, Windows). It tracks every branch, expression, and line, with color-coded HTML reports. `cargo-llvm-cov` wraps LLVM's native coverage instrumentation — it's faster, more accurate, and better maintained than `tarpaulin` (now Linux-only legacy).

### `test-fuzzing-minimal` — Use `cargo-fuzz` for fuzz testing critical functions

Fuzz testing generates random inputs to find crashes, panics, or invariant violations in parsing, deserialization, and input-processing functions. `cargo-fuzz` (libFuzzer-based) is significantly faster than naive random testing — it uses coverage guidance to explore new code paths, reaching deep edge cases that property-based testing might miss. Ideal for security-critical and parser code.

### `test-insta-snapshot` — Use `insta` for snapshot/approval testing

Snapshot testing compares output against a stored reference ("snapshot"). When the output changes intentionally, you review and update the snapshot. This is ideal for serialization, rendering, complex assertion outputs, and regression prevention. `insta` (72M+ downloads, v1.48.0) is the standard Rust snapshot testing crate with inline snapshots, review workflow, and CI integration.

### `test-nextest-workflow` — Use `cargo-nextest` for faster execution and CI partitioning

`cargo-nextest` runs tests up to 3× faster than `cargo test` by using a per-process test model: each test runs in its own process (no shared state corruption), with pipelined output, structured reporting, and built-in CI partitioning. It's the recommended test runner for CI, with native support in RustRover and most CI platforms.

### `test-rstest-fixtures` — Use `rstest` for parameterized tests, fixtures, and async test setup

Writing test fixtures and parameterized tests by hand leads to boilerplate duplication. `rstest` (48.8M+ downloads, v0.26.1) provides a declarative approach: `#[fixture]` for shared setup, `#[case]` for parameterized cases, `#[future]` for async fixtures, and named cases for descriptive test output. It integrates seamlessly with `#[tokio::test]`.

## 21. Documentation (MEDIUM)

### `doc-all-public` — Document the public API with rustdoc comments

Documentation is part of a library's interface. Publicly exposed types, fields, variants, traits, methods, functions, constants, and statics should explain the contract callers need in order to use them correctly without reading the implementation.
Use `///` for item documentation and `//!` for crate/module documentation. The goal is useful API documentation, not comments that merely repeat the identifier.

### `doc-module-inner` — Use inner doc comments (`//!`) to document a crate or module as a whole

An outer doc comment (`///`) documents the Rust item that follows it. An inner doc comment (`//!`) documents the item that contains it, so at a crate root it documents the crate and at the start of a module body/file it documents that module.
Module-level documentation is the right place to explain purpose, major concepts, cross-cutting invariants, feature-dependent surface, and a short entry-point example. Individual item docs can then focus on their own contracts.
- Prefer: Document the Module Itself
**Practical Guidance:**
- Use `//!` for the containing crate/module and `///` for the following item.
- Put cross-cutting context at module level instead of repeating it on every item.
- Treat README inclusion as a content-design decision, not a default.
- Document Cargo feature behavior on stable Rust even when you cannot use unstable `#[doc(cfg)]` annotations.
- Do not claim `--cfg docsrs` enables `doc_cfg`.
- In a compile harness, a deterministic README fixture can keep the repository-relative include example strict while real documentation quality remains a rustdoc concern.

### `doc-examples-section` — Add focused `# Examples` sections when an example materially clarifies how to use the API

Rustdoc examples can serve two jobs at once: they teach callers how an API is meant to be used, and runnable doctests keep that usage synchronized with the code. A useful example should emphasize the contract or workflow a reader actually needs rather than reproducing a large amount of setup.
Not every public item needs its own example. Small accessors and self-evident trait implementations can often rely on surrounding type/module documentation. Put examples where they explain construction, error handling, state transitions, feature-dependent behavior, or other non-obvious usage.
- Prefer: A Small Runnable Example
- Use `?` When Fallible Composition Is the Point
- Choose Doctest Attributes Deliberately
**Practical Guidance:**
- Add examples where they explain behavior a reader could plausibly get wrong.
- Keep the visible code focused; hide only incidental setup.
- Prefer doctests that actually compile and run.
- Use `no_run`, `compile_fail`, `ignore`, and `standalone_crate` for their documented semantics rather than as generic escape hatches.
- In a compile-check harness, provide deterministic external-file fixtures when the path dependency itself is what the example needs to verify.

### `doc-errors-section` — Document meaningful failure conditions in a `# Errors` section

A `Result` type says that an operation can fail; it usually does not tell callers which conditions produce which errors. Public fallible APIs should document the failure modes callers need to reason about, especially when several error variants or propagated failures are possible.
A useful `# Errors` section describes **conditions**, not merely “returns an error on failure.”
**Clippy Enforcement:**
`clippy::missing_errors_doc` is a pedantic, allow-by-default lint that checks publicly visible functions returning `Result` and warns when their doc comments lack a `# Errors` section:
Its `check-private-items` configuration can extend the check to private items when a project deliberately wants that policy.
A lint can detect a missing section; it cannot determine whether the section accurately describes the implementation. Keep error documentation synchronized with behavior and error conversions.

### `doc-panics-section` — Include `# Panics` section for functions that can panic

Panics are exceptional conditions that crash the program (or unwind the stack). Users need to know when a function might panic so they can ensure preconditions are met or avoid the function in contexts where panics are unacceptable (e.g., `no_std`, embedded, FFI).
If a function can panic, document exactly when.
- Pattern: Debug-Only Panics

### `doc-safety-section` — Document caller obligations with `# Safety`; justify local unsafe operations with `// SAFETY:` proofs

An `unsafe fn` moves part of Rust's safety proof from the compiler to the caller. Its documentation must state the conditions a caller has to uphold so that calling the function is sound.
That public contract is different from the proof inside an `unsafe { ... }` block. A local `// SAFETY:` comment should explain why the code at that point satisfies the relevant unsafe operation's preconditions.
- Prefer: State the Caller's Preconditions

### `doc-question-mark` — Give doctests a `Result`-returning context when demonstrating fallible operations; do not hide setup failure with unwrap/expect

Documentation examples are copied. If examples use `unwrap()` or `expect()`, agents and users reproduce panic-style extraction even when the API naturally supports propagation.
Rustdoc does **not** simply make every doctest return `Result` when it sees `?`. Give the example an explicit `Result`-returning `main`, or end the doctest with a hidden, type-annotated `Ok::<(), E>(())` so rustdoc can use its implicit result wrapper.
- Fixed Values Do Not Need Panic Extraction Either

### `doc-hidden-setup` — Hide incidental doctest setup with `# ` while leaving the behavior users need to understand visible

Rustdoc treats a line beginning with `# ` inside a Rust doctest as hidden source: the line participates in compilation and execution but is omitted from the rendered code example. This is useful for imports, tiny helper definitions, fallible wrappers, and other setup that would distract from the API call being demonstrated.
Hidden setup is not a license to make examples mysterious. If constructing a value, selecting a feature, or configuring an option is important to successful use, show that code.
- Prefer: Hide Only Incidental Setup
- Do Not Hide the API Contract
**Practical Guidance:**
- Hide imports, fixtures, and wrappers only when they are incidental.
- Keep configuration and construction visible when they teach the API contract.
- Remember that every hidden line still has to compile.
- Keep testing semantics (`no_run`, `compile_fail`, `ignore`) separate from presentation semantics (`# `).
- When an example's only external dependency is a deterministic file path, a verifier fixture can preserve a strict compile contract.

### `doc-intra-links` — Use intra-doc links for important relationships that rustdoc should resolve and validate

Rustdoc intra-doc links turn documentation references into navigable links to Rust items. Because rustdoc resolves the target when documentation is built, broken relationships can be caught by documentation lints instead of silently remaining stale prose.
They do **not** magically follow arbitrary renames or moves. A source-level rename may make a link stop resolving; the benefit is that rustdoc can report that breakage so the documentation is repaired together with the code.
- Prefer: Link the Relationships Readers Need
- Link to Standard-Library Items with Paths When Useful
**Practical Guidance:**
- Link important API relationships, not every noun.
- Expect renames and moves to require link maintenance; let rustdoc catch broken targets.
- Prefer `Self::...` for associated items on the current type.
- Use explicit paths or disambiguators when resolution would otherwise be unclear.
- Keep examples valid Rust so trait/type errors do not obscure documentation checks.
- Verify the generated docs for re-export-heavy APIs.

### `doc-link-types` — Cross-link related public types and operations when the links help readers navigate the API

A public API is usually understood as a graph of related concepts rather than one item at a time. Intra-doc links can connect constructors to builders, operations to their error types, iterators to their item semantics, and modules to the types they expose.
Rustdoc validates those targets when documentation is built. That catches many broken references after refactors, but the links themselves do not automatically rewrite their source paths when items move or are renamed.
- Prefer: Connect an Operation to Its Result and Error Types
- Link Only Publicly Useful Relationships
- Refactors Still Require Documentation Maintenance
**Practical Guidance:**
- Link the next concept a reader is likely to need.
- Link error/result/builder/trait relationships that clarify the public model.
- Do not link implementation-only details just because a Rust item exists.
- Keep examples complete so unrelated type errors do not hide documentation problems.
- Run rustdoc with broken-link warnings enforced after refactors.

### `doc-cargo-metadata` — Fill `Cargo.toml` metadata for published crates

Cargo.toml metadata appears on crates.io, in search results, and helps users evaluate your crate. Missing metadata makes your crate look unprofessional, harder to find, and harder to trust. Complete metadata improves discoverability and adoption.

### `doc-crate-readme` — Unify the README and crate root docs with `#![doc = include_str!("../README.md")]`

Maintaining a `README.md` and a separate crate-level doc comment in `lib.rs` leads to inevitable drift: the README gets updated for GitHub/crates.io visitors while the rustdoc front page grows stale, or vice versa. The `include_str!` attribute macro (stable since Rust 1.54) makes the README the single source of truth for both surfaces. Set `readme = "README.md"` in `Cargo.toml` so crates.io also picks up the same file. The result: one file, three consistent rendering targets — GitHub, crates.io, and docs.rs.

### `doc-cfg-patterns` — Use real `#[cfg(...)]` attributes for availability; when nightly rustdoc's `doc_cfg` is enabled, let `doc(auto_cfg)` surface those conditions and use `doc(cfg)` only when you need to override the displayed condition

Conditionally compiled APIs need two separate things:
1. a real `#[cfg(...)]` that controls whether the item exists; and 2. documentation that tells readers which feature or target makes it available.
- Rust 1.95+: Prefer `cfg_select!` for Mutually Exclusive Alternatives
- Avoid: Treating `doc(cfg)` as the Availability Gate
- Prefer: Let the Real `cfg` Drive Availability and Documentation
- Override the Displayed Condition Only When Useful
- Direct `#[doc(cfg(...))]` Is Nightly-Only on Rust 1.98
- Avoid Over-Tagging

### `doc-hidden-public` — Use `#[doc(hidden)]` only when a public item must remain callable but should be omitted from normal generated documentation

`#[doc(hidden)]` changes **documentation visibility**, not Rust visibility. If an item is `pub`, downstream code can still name and use it even when rustdoc omits it from normal output. Hiding an item therefore does not turn it into implementation-private code and does not erase compatibility concerns around changing or removing it.
This attribute is most useful for deliberately public support surface that end users are not expected to discover directly: macro plumbing, generated helpers, compatibility shims, or implementation-oriented re-exports that must cross a crate boundary.
- Prefer: Public Support Surface Hidden from Normal Docs
- Avoid: Hiding an API Users Are Expected to Call
**Practical Guidance:**
- Prefer Rust privacy when an item does not need to be public.
- Use `#[doc(hidden)]` only when public visibility is intentional but normal discoverability is not.
- Remember that downstream code can still use a hidden public item.
- Treat changes to hidden public surface as compatibility changes according to the promises your crate makes.
- Inspect re-exported documentation rather than assuming `doc(hidden)` propagates exactly as desired through every public path.

### `doc-include-str` — Use `#[doc = include_str!("...")]` when an external text file is intentionally part of an item's generated documentation

`include_str!` reads a UTF-8 file at compile time and expands to a string literal. Supplying that string to the `doc` attribute lets a crate keep substantial Markdown in a separate file while still rendering it as rustdoc documentation.
This can be useful for crate-level README content, long guides, or intentionally shared examples. It also creates a real build dependency on that file: the path must exist, the content must be valid UTF-8, and edits to the file can cause recompilation when the macro is evaluated.
- Gate Documentation-Only Includes Deliberately
**Practical Guidance:**
- Use external docs when they improve maintainability, not merely to move text away from source.
- Remember that ordinary relative `include_str!` paths start from the containing Rust source file.
- Apply the Edition 2024 Markdown-relative rule only to nested includes inside doctests from included Markdown.
- Consider `cfg_attr(doc, ...)` when documentation files should not be evaluated during normal builds, but account for your rustdoc/re-export needs.
- A compile harness can provide small deterministic fixture files to keep repository-relative include examples strict without pretending those fixtures validate real documentation content.

### `doc-test-edition-2024` — Account for Edition 2024 rustdoc doctest merging, `standalone_crate`, and source-relative nested includes

Starting in Edition 2024, rustdoc **attempts to merge compatible doctests** into one compiled test crate. This reduces compilation overhead. The individual doctests are still run in separate processes, so merging does not make their runtime globals shared.
Rustdoc automatically keeps some incompatible examples separate, including `compile_fail` tests, examples with edition tags or crate-wide attributes, and macro definitions that use `$crate`. A smaller set of examples depend on compilation layout in ways rustdoc cannot infer; those may need the `standalone_crate` fence attribute.
**Migration Checklist:**
1. Set the crate to Edition 2024 and run `cargo test --doc`.
2. Fix doctests that assert exact `Location` or `type_name` values if merged source layout changes them.
3. Add `standalone_crate` only where separate compilation is actually required and not already inferred by rustdoc.
4. Recheck macros used in doctests, especially definitions involving `$crate`.
5. Update nested include paths in included Markdown so they are relative to the file containing the doctest.

## 22. Observability (MEDIUM)

### `obs-tracing-over-log` — Use `tracing` for structured, span-aware diagnostics instead of `println!` or bare `log`

`println!` and `eprintln!` have no concept of log levels, targets, or structured data — they cannot be silenced, filtered, or parsed by observability pipelines. The `log` facade improves this but emits only flat strings and has no notion of spans. `tracing` records both *events* (point-in-time observations) and *spans* (contextual scopes that automatically follow execution across `.await` points and threads), with structured key-value fields, level filtering, and target routing. It is also interoperable with the `log` ecosystem via `tracing`'s `log` feature flag.
**Key Points:**
| Approach | Levels | Structured | Async-aware spans | `log` compat |
|---|---|---|---|---|
| `println!` | No | No | No | No |
| `log` facade | Yes | No | No | Yes |
| `tracing` | Yes | Yes | Yes | Yes (via feature) |
- Add to `Cargo.toml`: `tracing = "0.1"` for all crates; `tracing-subscriber = { version = "0.3", features = ["env-filter"] }` for binaries only.
- The `%expr` sigil uses `Display`; `?expr` uses `Debug`; bare `field = value` records typed primitives.
- `tracing` ships a `log` compatibility bridge: set `tracing-subscriber`'s `log` feature or call `tracing_log::LogTracer::init()` to capture existing `log`-emitting dependencies.

### `obs-library-facade` — Reusable libraries should emit observability data without surprising callers by installing process-global logging or tracing state

Global logger/subscriber installation is process-wide coordination. A reusable library that silently performs it can conflict with the application, tests, other libraries, or embedding environments that need different filtering, formatting, destinations, or subscriber composition.
The durable split is:
- Avoid: Hidden Global Setup in Library Work
- Prefer: Library Emits, Application Configures
**Key Points:**
- Do not install process-global observability state as a hidden side effect of ordinary reusable-library calls.
- Emit through a facade and let the application choose collection/filtering/output policy.
- Explicit opt-in setup helpers are different from implicit initialization.
- Prefer fallible initialization APIs when setup may already have occurred.
- Keep subscriber implementation dependencies out of the runtime library dependency graph unless the public API actually needs them.

### `obs-structured-fields` — Record structured key-value fields, not values interpolated into the message string

When values are interpolated directly into the message string (e.g., `"processed 42 items for user 7 in 120ms"`), they become opaque text. Log aggregators (Loki, Elasticsearch, OpenTelemetry) cannot filter on `items = 42` or group by `user.id` because those values no longer exist as discrete fields. Structured fields keep data machine-parseable, filterable, and chart-able without regex post-processing. `tracing` supports three field sigils: `%expr` for `Display`, `?expr` for `Debug`, and bare `field = value` for typed primitives — the message string should only contain a stable, human-readable description.
**Key Points:**
- Keep the message string short, stable, and human-readable. It should make sense *without* the fields.
- Prefer `%` over `?` for values that have a clean `Display` (e.g., `%id`, `%path`) — JSON backends quote Debug output inconsistently.
- Use namespaced field names like `user.id`, `http.status`, `db.query` when aligning to OpenTelemetry semantic conventions.
- Avoid placing the same data in both the message and a field (redundant and noisy).
- Structured fields avoid the allocation cost of `format!()` interpolation — prefer `info!(user_id, items, elapsed_ms, "batch processed")` over `info!("processed {items} items for user {user_id}")`. The message string is a `&'static str` reference, while fields are typed and trivially cheap to skip when the level is disabled. This matters in hot-path and per-item loops.

### `obs-instrument-spans` — Use `#[tracing::instrument]` and spans to attach context to async tasks and requests

A span groups all events emitted during a logical operation (an HTTP request, a database call, a background job) and attaches structured context to every event within it. Without spans, log lines from concurrent async tasks interleave with no way to correlate them. The `#[tracing::instrument]` attribute creates a span automatically from the function's arguments as fields. There is one critical async pitfall: holding a span *entry guard* (`let _g = span.enter()`) across an `.await` point attaches the span to the wrong task when the executor resumes on a different thread — use `.instrument(span)` on the future instead.
**Key Points:**
- **`#[instrument]`** is the preferred way to instrument async functions — it wraps the whole future in `.instrument(span)` under the hood.
- Use `skip(arg)` or `skip_all` to exclude large types (e.g., database pools, byte buffers) and sensitive values from auto-captured fields.
- Use `fields(key = value)` inside `#[instrument]` to add or rename fields beyond the auto-captured args.
- For manual spans, always attach with `.instrument(span).await`, never hold a guard across `.await`.
- Spans nest automatically: entering a child span inside a parent records the parent's context in traces, enabling waterfall views in tools like Jaeger or Tempo.

### `obs-levels-filter` — Use log levels meaningfully and filter with `EnvFilter` / `RUST_LOG`

Log levels exist to communicate urgency and to let operators tune verbosity without recompiling. Misusing them — emitting everything at `info!`, or leaving `debug!` output in hot paths in production — overwhelms aggregators and hides real signals. `tracing_subscriber::EnvFilter` reads the `RUST_LOG` environment variable and supports per-crate, per-target, and per-span directives, giving operators fine-grained control at runtime. For release builds, tracing's `max_level_*` Cargo features can compile out verbose levels entirely, eliminating even the call-site overhead.
**Key Points:**
- `RUST_LOG=info,mycrate=debug,hyper=warn` — comma-separated target=level pairs; the first token sets the global default.
- Compile out verbose levels in release with Cargo features: `tracing = { version = "0.1", features = ["max_level_debug", "release_max_level_info"] }`.
- Prefer `try_from_default_env()` with a fallback string over `from_default_env()` so the binary still starts when `RUST_LOG` is unset or malformed.

### `obs-error-chain` — Log errors with their full source chain, and log each error exactly once

Logging only the top-level `Display` of an error silently drops the underlying cause chain — you see "request failed" but not *why*. The two common fixes are: use `?` format (`error = ?err`) to capture `Debug` output including the chain, or use `{:#}` on an `anyhow::Error` which formats the full cause chain. The second hazard is the log-and-return anti-pattern: logging the error at every propagation layer records the same failure multiple times with different amounts of context, polluting aggregators. Log once, at the boundary that *handles* the error; everywhere else, propagate with `?` and optionally add context.
**Key Points:**
- **`error = ?err`**: uses `Debug` — prints the error and its `source()` chain for types that implement it.
- **`format!("{err:#}")`** or `%format!(...)`: `anyhow::Error`'s alternate Display walks the full chain with `: ` separators.
- **Propagate, don't log**: use `?` and `.context()` / `.with_context()` at intermediate layers; log at the single handling boundary.
- If you *must* log at a non-handling layer (e.g., background task that discards the error), use `warn!` not `error!` to signal it was absorbed.
- The `tracing-error` crate provides `SpanTrace` to capture the span context at the error site and attach it to the error type.

### `obs-no-sensitive-data` — Never log secrets or PII; redact or skip them

Logs and traces are routinely shipped to cloud aggregators (Datadog, Grafana Loki, Splunk) and retained for weeks or months. If a password, API token, session cookie, or piece of PII (email, SSN, health data) appears in a log line or span field, it leaks into systems with weaker access controls than your secrets manager, appears in support exports, and may violate GDPR/HIPAA/PCI-DSS. The fix is cheap: use `#[instrument(skip(...))]` or `skip_all` to exclude sensitive arguments, and wrap sensitive types in a redacting newtype or use the `secrecy` crate's `Secret<T>` which prints `[redacted]` from both `Debug` and `Display`.
**Key Points:**
- **`skip(arg)`**: exclude a single argument from `#[instrument]` auto-captured fields.
- **`skip_all`**: exclude all arguments; then add only safe fields with `fields(key = value)`.
- **Redacting newtypes**: override `Debug` and `Display` to emit `"[redacted]"` — this protects against accidental `?arg` or `%arg` elsewhere in the codebase.
- **`secrecy` crate**: provides `Secret<T>` with a `[redacted]` `Debug` impl and an explicit `.expose_secret()` API so you know exactly where the value is revealed.
- **Do not log full request bodies** in production: they may contain tokens, credentials, or PII embedded in JSON payloads. Log only metadata (size, content-type, path).
- Audit existing spans with `RUST_LOG=trace` in a staging environment before shipping.

## 23. Performance Patterns (MEDIUM)

### `perf-iter-over-index` — Prefer direct iteration when you are traversing values; use indexing when the index is part of the algorithm

Iterators usually express sequential traversal more directly than a manual `0..len` loop and avoid common off-by-one mistakes. They also give the optimizer useful structure, but Rust does **not** promise that an iterator form has no bounds checks, auto-vectorizes, or outperforms equivalent indexing.
Choose the representation that states the algorithm clearly, then inspect or benchmark hot code when the difference matters.
- Prefer: Traverse Values Directly
- Use `enumerate` When You Need Both Index and Value
- When Indexing Is the Right Model
**Practical Guidance:**
- Iterate values directly when the values—not their positions—are what the algorithm needs.
- Use `zip` only when its “stop at the shorter input” semantics are correct.
- Use `enumerate` when both position and value matter.
- Prefer `array_windows::<N>` when a compile-time fixed window type simplifies the code.
- Use indexing freely for genuine positional/random-access algorithms.
- Treat bounds-check elimination and SIMD as measured code-generation properties, not syntax guarantees.

### `perf-iter-lazy` — Keep iterator pipelines lazy when streaming or short-circuiting is useful; collect only when ownership, reuse, sorting, indexing, or another concrete requirement needs a collection

Iterator adapters such as `map`, `filter`, and `take` normally produce another lazy iterator. Work happens as a consumer requests items. This can avoid intermediate allocations and can stop early for consumers such as `find`, `any`, or `take`.
Laziness is not automatically faster. A collection is the right representation when values must be stored, sorted, indexed repeatedly, shared independently from the source, or traversed multiple times.
- Avoid Intermediate Collections That Carry No Ownership Need
**Review Questions:**
Before adding `.collect()` in the middle of a pipeline, ask:
- Does the next operation require a slice/collection rather than an iterator?
- Must these values outlive the source iterator independently?
- Will they be sorted, indexed, mutated, or traversed multiple times?
- Is collection needed for parallelism or an external API boundary?
- Would a short-circuiting consumer avoid most of the work?
If there is a real answer, collect. If not, keeping the iterator lazy is usually simpler.

### `perf-collect-once` — Keep iterator pipelines lazy until you actually need an owned collection; materialize intermediate results when their semantics justify it

Collecting an iterator into `Vec`, `String`, `HashMap`, or another owned collection can require allocation and an additional materialized data structure. Avoiding an intermediate collection can reduce memory traffic when the next operation can consume the iterator directly.
But `.collect()` is not synonymous with “exactly one allocation,” and intermediate materialization is not inherently wrong. Allocation behavior depends on the destination collection and iterator size hints, while sorting, indexing, repeated traversal, ownership boundaries, or API requirements may make a concrete collection exactly the right tool.
- Use Iterator Consumers Instead of Collecting Just to Ask a Question
- Intermediate Collections Are Correct When You Need Their Capabilities
- Directly Iterate Map Views When No Snapshot Is Needed
- Pre-Allocate When You Have a Useful Bound
- Fixed-Size Slice APIs Avoid Temporary Collections When Their Semantics Fit
**Practical Guidance:**
- Avoid temporary collections that exist only to feed the next one-pass iterator operation.
- Use terminal iterator methods directly when they answer the question.
- Materialize when sorting, indexing, mutation, repeated traversal, ownership, or an API boundary requires it.
- Treat allocation counts as implementation/workload details, not syntax-level guarantees.
- Reserve capacity only when you have a useful estimate and the memory trade-off is acceptable.
- Use fixed-size slice APIs when their semantics match the problem, not as generic “faster iterator” replacements.

### `perf-entry-api` — Use a map's entry API when one key lookup should decide both the occupied and vacant cases.

`HashMap::entry` and `BTreeMap::entry` expose a view of one key position as either occupied or vacant. This is ideal for insert-or-update logic because the lookup/navigation used to find that entry can be reused instead of spelling separate `contains_key`/`get_mut`/`insert` operations.
That often improves both clarity and work performed, but do not reduce the rule to “entry is always faster.” An entry API typically takes ownership of a key, while borrowed lookup methods can avoid constructing/owning a key when the occupied case dominates. Choose the API that matches the ownership and mutation pattern.
- Avoid: Search, Then Search Again
- Prefer: Work Through One Entry

### `perf-drain-reuse` — Use `drain` or `extract_if` when you need to remove owned elements while retaining the source collection's allocation; do not introduce an intermediate collection unless ownership requires one

`drain` removes elements and yields them by value while the collection keeps its backing allocation. `extract_if` conditionally removes matching elements and yields those owned values. These operations are useful when the caller wants to reuse the source container rather than consume it wholesale.
They are ownership tools first. Whether they improve performance depends on the surrounding algorithm, retained capacity, element movement, and whether the removed values must be stored elsewhere.
- Reuse a Scratch Destination When a Separate Batch Is Required
- Avoid Intermediate Collections When Moving Between Destinations

### `perf-extend-batch` — Use `extend`, `extend_from_slice`, or `append` when adding a batch expresses the ownership you want; reserve explicitly when the final size is cheaply known

Batch-oriented APIs are often clearer than hand-written element loops, and `Vec` implementations can use iterator information and specialization to grow efficiently. But `extend()` is not a contractual promise of “one allocation,” nor is it universally faster than a `push` loop.
Choose the operation from ownership and source shape first. If the final length is known cheaply and allocations matter, reserving capacity explicitly gives the intent a much firmer footing than relying on an iterator's size hint.
- Prefer: Extend From an Iterator
- Reserve When the Total Size Is Known

### `perf-chain-avoid` — Use `Iterator::chain` when it expresses the traversal clearly; split or materialize only when measurement shows the chained iterator is a bottleneck

`Iterator::chain` represents two iterators as one lazy iterator. At the abstract API level it must know whether the first iterator still has items, but source-level descriptions such as “exactly one extra branch per item” are not reliable descriptions of optimized machine code. LLVM may inline, specialize, simplify, or restructure the iterator state.
Do not ban `.chain()` from hot code by rule. Benchmark the actual loop. Separate loops can sometimes generate better code, but they can also duplicate logic or make short-circuiting and composition less clear.
- Materialize Once Only When Repeated Traversal Needs It
**Practical Guidance:**
- Prefer `.chain()` when it clearly expresses one lazy traversal over multiple sequences.
- Keep `.chain()` for short-circuiting pipelines unless measurement says otherwise.
- Use separate loops when they are clearer or benchmark better in a critical kernel.
- Materialize only when ownership/reuse semantics justify the allocation and copy.
- Remember that the free `iter::chain` function remains nightly-only on Rust 1.98.
- Never assign fixed branch counts or performance rankings from source syntax alone.

### `perf-collect-into` — Reuse an existing destination with `clear()` + `extend()` on stable Rust; nightly `Iterator::collect_into` appends like `Extend::extend` and does not clear for you

`collect::<Vec<_>>()` creates a new destination collection. In a repeated workload where one scratch buffer can be reused, stable Rust already has the essential operation: clear the existing collection and extend it from the new iterator.
Nightly `Iterator::collect_into` is an ergonomic inversion of `Extend::extend`: the method is called on the iterator and adds items to a supplied collection. It **appends to the collection's current contents**. It does not mean “replace this collection with the iterator output,” and it does not implicitly call `clear()`.
- Avoid: Allocate a Fresh Scratch Destination Every Iteration
- Prefer: Stable `clear()` + `extend()`

### `perf-black-box-bench` — Use `std::hint::black_box` in benchmarks when compile-time knowledge could make the measured work unrealistically disappear or specialize.

Optimized benchmark code is still optimized code. If the compiler can prove an input is constant or a result is irrelevant, it may fold, simplify, or remove work that would exist in the real program.
`std::hint::black_box` tells the compiler to be maximally pessimistic about what can be assumed across that point. It is useful for benchmarks, but it is deliberately **best effort**: code generation varies by backend and target, and `black_box` provides no correctness, security, constant-time, or exact “this optimization is impossible” guarantee.
- Avoid: Give the Optimizer the Entire Answer
- Prefer: Hide Relevant Inputs and Consume Outputs
- Do Not Use `black_box` to Manufacture Cold Paths

### `perf-release-profile` — Optimize release profile settings

The default release profile prioritizes compile speed over runtime performance. For production binaries, tuning the release profile can yield significant performance improvements (10-40% in some cases) at the cost of longer compile times.

### `perf-profile-first` — Measure representative workloads before choosing an optimization, then measure again after the change.

Performance work is an experiment. Source-code intuition can identify candidates, but it cannot tell you which cost dominates a real workload, how often a path runs, or whether an optimization improves end-to-end behavior.
A useful workflow separates three questions:
- Avoid: Optimize the Visually Suspicious Line First
- Prefer: Make the Optimization Follow Evidence
- Prefer Algorithmic and Architectural Wins When Evidence Points There
**A Performance Improvement Is a Tradeoff Decision:**
A faster hot path may increase memory, binary size, compile time, code complexity, or worst-case latency. Decide which metrics are guardrails before optimizing.
For example, `#[inline(always)]` may improve a microbenchmark while increasing code size; a cache may reduce CPU while increasing memory; parallelism may improve throughput while worsening single-request latency or contention.
**Decision Guide:**
| Question | Evidence to gather |
|---|---|
| Where is CPU time spent? | application profile |
| Does this small implementation change help? | focused benchmark |
| Is allocation the problem? | allocation profile/counters |
| Is waiting/queueing the problem? | tracing/latency/queue metrics |
| Is a build cache actually reusable? | cold + warm + source-change runs, cache/compile logs |
| Did the optimization help users? | end-to-end metric under representative load |
| Did it create regressions? | predefined guardrails + tests |

### `perf-ahash` — Use a faster hasher (`ahash` / `FxHashMap`) when DoS resistance is not needed

Rust's default `HashMap` uses SipHash-1-3, which is DoS-resistant (hash flooding attacks on external input are not viable) but roughly 2–4× slower than non-cryptographic hashers on typical integer and short-string keys. For internal maps keyed by compiler-generated IDs, integer handles, or other trusted data, switching to a faster hasher can meaningfully reduce CPU time in hot map-heavy code. The wrong choice here is a security bug, not just a performance one — never use a non-DoS-resistant hasher for maps keyed by untrusted external input (user-supplied strings, network data, file paths from untrusted sources).
**Key Points:**
- **Profile first**: switch hashers only after confirming map operations appear in profiler output.
- `ahash::AHashMap` is a drop-in replacement for `HashMap` and is the safest upgrade — it uses a random per-process seed.
- `FxHashMap` is what rustc uses internally; it is predictable, so never expose it to externally-supplied keys.
- Pass `with_capacity` when the final size is known — it applies regardless of hasher choice.

### `perf-io-buffering` — Wrap `Read`/`Write` in `BufReader`/`BufWriter` for many small operations

Every unbuffered read or write to a file or socket is a syscall. Calling `read()` byte-by-byte or line-by-line without buffering can issue millions of syscalls per second, each with kernel-transition overhead that dwarfs the actual data transfer. `BufReader` and `BufWriter` batch those operations into large internal buffer reads and writes, cutting syscall count by orders of magnitude. This is one of the highest-impact, lowest-effort performance fixes available for IO-heavy code.
**Key Points:**
- `BufWriter::flush()?` must be called explicitly. When a `BufWriter` is dropped, it attempts to flush, but any resulting error is **silently discarded**. Always flush before the writer goes out of scope.
- The default buffer size for both `BufReader` and `BufWriter` is 8 KiB. For sequential reads of large files, a larger buffer (32–512 KiB) can improve throughput by reducing the number of `read` syscalls further.
- `BufReader` implements `BufRead`, which provides `lines()`, `read_line()`, and `read_until()` — use these instead of reading bytes manually.
- Network streams (`TcpStream`, etc.) benefit equally from buffering, since each `write` on an unbuffered stream may send a tiny TCP segment.
- If you wrap a type that is already internally buffered (e.g., `tokio::io::BufWriter` in async code), adding another layer is redundant.

### `perf-array-windows` — Use `<[T]>::array_windows` and `<[T]>::as_chunks` when a compile-time window or chunk size is useful

`slice::windows` and `slice::chunks` yield dynamically sized slices (`&[T]`). When the size is known at compile time, newer APIs can expose that fact in the type system:
- `<[T]>::array_windows::<N>()` (Rust 1.94+) yields overlapping `&[T; N]` windows; - `<[T]>::as_chunks::<N>()` (Rust 1.88+) returns `(&[[T; N]], &[T])` for non-overlapping chunks plus a remainder.
- Prefer: Use the Fixed Shape When the Algorithm Has One
**Practical Guidance:**
- Use `array_windows::<N>` for overlapping windows when `N` is a compile-time constant.
- Use `as_chunks::<N>` for non-overlapping fixed-size blocks plus a remainder.
- Keep `windows`, `chunks`, and `chunks_exact` for runtime sizes or when their API is otherwise clearer.
- Do not promise exact bounds-check counts or SIMD from any source form.
- Benchmark or inspect optimized output before calling one equivalent implementation faster.

### `perf-atomic-update` — Use `Atomic*::update` and `try_update` for cleaner compare-and-update loops

Compare-and-exchange loops are the building block of many lock-free atomic updates. The manual pattern is easy to get wrong or make unnecessarily verbose. Rust 1.95 added `update` and `try_update` across the atomic types so common compare-and-update loops can be expressed directly.
These methods do **not** change the memory-model requirements: you still choose the success and failure orderings, and the closure may run more than once under contention. Keep the closure free of externally visible side effects.

### `perf-copy-range` — Treat `Copy` ranges as an ownership and ergonomics choice, not an automatic performance optimization

Rust 1.96's `core::range::Range<T>` can be `Copy` when `T: Copy`, which can simplify small data structures that store ranges by value. But `Copy` does not by itself prove faster code, eliminate all references, or guarantee better generated machine code.
Use the newer range where its value semantics make an API or data structure clearer. Benchmark before presenting the choice as a hot-path optimization.
**Key Points:**
- Choose `core::range::Range` for useful `Copy` value semantics.
- Do not claim that `Iterator` inherently prevents `Copy`.
- Do not claim automatic speedups from the type change.
- Measure hot paths and keep API compatibility in view.

### `perf-extract-if` — Use `extract_if` when matching elements should be removed while their ownership is yielded to the caller.

`extract_if` combines conditional removal with an iterator over the removed values. That is useful when you need **both** partitions: retain non-matching values in the original collection and process/collect matching values by ownership.
Current stable Rust provides:
- Avoid: Clone Matching Elements, Then Scan Again to Retain
- Prefer: Remove and Yield Ownership in One Operation
- Consume the Iterator When You Mean “Extract All Matches”
- When `retain` Is Simpler

### `perf-hint-apis` — Use compiler hint APIs only when their semantics match a measured hot path; they are advisory optimizations, not code-generation guarantees

`std::hint` exposes a few specialized optimization hints. They can influence code layout or branch lowering, but they do not command a particular CPU instruction and they can make performance worse when the workload does not match the hint.
Treat these APIs like other low-level performance tools: keep the ordinary control flow correct without the hint, benchmark representative inputs, and preserve the hint only when it produces a repeatable benefit.
- Do Not Turn Hints Into Performance Folklore
- Prefer Higher-Level Structure First

## 24. Project Structure (LOW)

### `proj-lib-main-split` — Put reusable or directly importable application logic in a library target; keep binary entry points thin when that separation helps.

A package can contain both a library target (`src/lib.rs`) and one or more binary targets (`src/main.rs`, `src/bin/*.rs`). Moving core logic into the library gives binaries, examples, benchmarks, and integration tests a normal Rust API they can import.
That does **not** mean code in `main.rs` is untestable. Binary targets can contain unit tests, and Cargo integration tests can execute built binaries through `CARGO_BIN_EXE_<name>`. The distinction is about **importable API boundaries and reuse**, not whether testing is possible at all.
- Avoid: Domain Logic Exists Only Inside the Binary Target
- Prefer: Importable Logic, Thin Entrypoint
**Decision Guide:**
| Situation | Useful structure |
|---|---|
| Tiny single-purpose executable with little reusable logic | Binary-only may be sufficient |
| Domain logic needs direct integration tests/imports | Library + thin binary |
| Several binaries share code | Library + `src/bin/*` binaries |
| Need end-to-end CLI behavior tests | Test the binary via `CARGO_BIN_EXE_<name>` |
| Need both direct logic tests and CLI tests | Library API plus a small binary boundary |

### `proj-mod-by-feature` — Prefer domain/feature-oriented modules when they keep code that changes together in one place

A module tree should make the codebase easier to navigate and preserve useful boundaries. In applications where each domain feature has a model, storage code, business logic, and handlers, a purely layer-oriented tree can scatter one change across many distant directories.
Feature-oriented modules are a useful default in that situation, not a universal law. Cross-cutting infrastructure, small projects, reusable libraries, and architectures with strong layer boundaries may be clearer with another shape.
- Layer-Only Layout Can Scatter a Feature
**When to Flatten:**
Small modules do not need five files merely to satisfy a pattern:
Split a feature when the extra boundary improves navigation, ownership, testing, or reuse—not because every conceptual layer deserves a file.
**Decision Guide:**
| Dominant change pattern | Often clearer |
|---|---|
| Features change mostly independently | Feature/domain modules |
| Infrastructure reused across many features | Cross-cutting modules |
| Small crate with few items | Flat module tree |
| Public reusable library organized around concepts/types | API-oriented modules |
| Strong architectural layer boundaries are themselves important | Layered or hybrid layout |

### `proj-flat-small` — Keep small projects flat

Over-organizing small projects adds navigation overhead without benefit. A project with 5-10 files doesn't need nested directories. Start flat, add structure only when complexity demands it.
**When to Add Structure:**
| File Count | Structure |
|------------|-----------|
| < 10 files | Flat in `src/` |
| 10-20 files | Group by feature |
| 20+ files | Feature folders with submodules |

### `proj-mod-rs-dir` — Choose a consistent multi-file module layout; both `foo.rs` + `foo/` and `foo/mod.rs` are supported

Rust supports two ordinary filesystem layouts for a module with submodules. Neither is inherently more correct or more scalable. Pick the style that makes your project easy to navigate, and avoid mixing styles accidentally when consistency matters to the team.
- Choose by Project Navigation, Not Submodule Count
- Keep Module Roots Useful

### `proj-pub-crate-internal` — Use the narrowest visibility that matches the intended module boundary; use `pub(crate)` for APIs shared across the crate but not exposed downstream

Every `pub` item reachable from a public module can become part of the API downstream users depend on. `pub(crate)` keeps an item available throughout the current crate without making it externally nameable.
Do not replace all private items with `pub(crate)`. Plain private visibility is stronger encapsulation and is preferable when sibling modules do not need the item.
- Avoid: Expose Implementation State Downstream
- Prefer: Keep the Support API Crate-Local

### `proj-pub-super-parent` — Use `pub(super)` when an item declared in a child module must be visible in its parent module scope

`pub(super)` is shorthand for `pub(in super)`: it raises an item's visibility to the item's **parent module**. It is useful when a child module owns an implementation detail that its parent or sibling modules need, while the rest of the crate should not see it.
Do not use `pub(super)` on an item merely so that the item's own child modules can access it. Ordinary private items are already visible to the module that defines them and its descendants.
**Choosing a Visibility:**
| Form | Meaning |
|---|---|
| private | visible in the current module and its descendants |
| `pub(super)` | visible within the parent module's scope |
| `pub(crate)` | visible throughout the current crate |
| `pub(in crate::path)` | visible within a specified ancestor-module scope |
| `pub` | potentially reachable outside the crate, subject to the enclosing path's visibility |
Visibility restrictions can only name ancestor scopes. If several sibling modules need a shared abstraction, consider whether that abstraction belongs in their parent module rather than automatically widening a child item's visibility.

### `proj-pub-use-reexport` — Use `pub use` to curate intentional public paths; do not expose internal module layout or dependency types accidentally.

A public `use` declaration re-exports a name. It can give callers a stable, ergonomic path even when the item's defining module is private.
That separation is useful: internal modules can reflect implementation structure while the crate root or another public facade presents the API callers are expected to depend on.
- Avoid: Internal Module Tree Becomes the API by Accident
- Prefer: Private Organization, Curated Public Paths
- Selective Re-Export Beats `pub use module::*`
**Re-Exporting Dependency Types Is a Public-Dependency Decision:**
Sometimes callers really should use the exact dependency type accepted or returned by your API. Re-exporting it can give them one canonical path.
This is convenient, but `bytes::Bytes` is now deliberately visible in your API. Upgrading to a semver-incompatible version or replacing it with another type can be a breaking API change even though callers spelled the type through your crate's re-export.
If the dependency is an implementation detail, prefer your own type/trait boundary instead of re-exporting it merely to save callers a dependency declaration.
Also do not assume re-exporting means consumers will **never** need a direct dependency. They may need dependency-specific macros, traits, feature flags, companion types, or APIs you do not re-export.
**Decision Guide:**
| Goal | Typical approach |
|---|---|
| Hide internal module nesting | Private modules + selective root re-exports |
| Expose a small curated facade | Explicit `pub use` list |
| Preserve two names during migration | Re-export with alias |
| Exact dependency type is intentionally public | Re-export it and treat dependency as public API |
| Dependency should remain swappable | Own a wrapper/trait boundary |
| Crate is intentionally a facade | Broader re-exports can be appropriate |

### `proj-prelude-module` — Offer a small opt-in `prelude` only when callers repeatedly need the same coherent set of imports.

A crate prelude is a conventional module whose contents users import explicitly with `use my_crate::prelude::*`. Unlike Rust's language/standard preludes, a library-defined prelude is **not imported automatically**.
A good prelude can reduce repetitive imports for APIs built around extension traits or a tightly related group of core types. A bad prelude hides where names come from, increases collision risk, and creates another public surface that must remain coherent over time.
- Avoid: A Grab-Bag Prelude
- Prefer: Small, Coherent, Opt-In
- Explicit Imports Must Remain First-Class
**Decision Guide:**
| Situation | Recommendation |
|---|---|
| A few obvious explicit imports | Prefer explicit imports |
| Many call sites repeat the same coherent imports | Consider a small prelude |
| Extension traits are essential to normal use | Prelude can improve discoverability |
| Prelude would mostly contain rare modules | Skip it |
| New item is public | Do not automatically add it to the prelude |
| Specialized feature/subsystem | Prefer its own module/import path unless common usage justifies inclusion |

### `proj-bin-dir` — Use `src/bin/` for conventionally discovered additional binary targets

Cargo automatically discovers binary targets in `src/bin/`. For packages with several executables, this often avoids repetitive `[[bin]]` entries and makes the target boundaries obvious.
Explicit `[[bin]]` entries are still appropriate when you need a custom path, name, `required-features`, test/bench settings, or other target configuration.

### `proj-workspace-large` — Use workspaces for large projects

Cargo workspaces manage multiple related crates under one repository. They share a single `Cargo.lock`, build cache, and can be versioned together. For large projects, workspaces improve build times, enforce modularity, and simplify dependency management.
**When to Use Workspaces:**
| Scenario | Recommendation |
|----------|----------------|
| Single binary/library | No workspace needed |
| Library + CLI | Maybe, depends on size |
| Multiple related crates | Yes |
| Shared internal libraries | Yes |
| Microservices mono-repo | Yes |
| Plugin architecture | Yes |
**Known Pitfalls:**
- **Feature unification** — workspace members share feature activation. `crate-a` enabling `tokio/full` activates it for all members. See proj-workspace-deps for mitigations.
- **`default-features = false`** — does not compose with `{dep}.workspace = true` (cargo#12162). Define minimal-feature variants in workspace deps instead.
- **`resolver = "3"`** — required for Edition 2024. Workspaces created with older editions should update explicitly. Virtual workspaces (no root `[package]`) must set `resolver = "3"` explicitly — it is not inferred from member crates' editions.

### `proj-workspace-deps` — Use workspace dependency inheritance for consistent versions across crates

Multi-crate workspaces often have dependency version drift—different crates using different versions of the same dependency. Workspace dependency inheritance (Rust 1.64+) lets you declare dependencies once in the workspace `Cargo.toml` and inherit them in member crates, ensuring consistency.

### `proj-feature-additive` — Design Cargo features to be additive whenever feature unification can combine them

Cargo may unify features requested for the same dependency package, taking their union. A feature therefore should not normally mean “turn some other capability off”: another dependency can enable both features even when one direct consumer expected only one of them.
Treat features as capabilities that can coexist. This is especially important for library crates. Mutually exclusive modes sometimes exist for unavoidable backend or platform reasons, but they are a constraint to detect and document rather than a model Cargo enforces for you.
- Avoid Feature-Dependent Semantic Rewrites

### `proj-msrv-declare` — Declare `rust-version` (MSRV) in Cargo.toml and test it in CI

`package.rust-version` tells Cargo and downstream users which Rust release line the package promises to support. Setting it produces a clear, actionable error when the installed toolchain is too old instead of a cryptic type or feature error deep inside your code.
For Rust 2024 workspaces, resolver 3 makes dependency resolution MSRV-aware: Cargo prefers dependency versions whose own `rust-version` does not exceed the workspace/package compatibility floor. This prevents an ordinary dependency update from silently selecting a release your stated MSRV cannot compile.
- Prefer: Library or Application With an Older Compatibility Floor
**Choosing and Maintaining MSRV:**
- Pick the oldest stable toolchain your users realistically need (distro packages, embedded targets, corporate freeze windows, downstream library policy).
- Do not go lower merely for prestige: a lower floor increases compatibility work and can constrain dependency versions.
- Keep normal development/production builds on a patched stable compiler unless reproducibility or certification requirements call for another explicit policy.
- When a Rust point release fixes a compiler miscompilation, prefer the patched point release rather than pinning the superseded `.0` indefinitely.
- Test important feature/target combinations on the MSRV, not just one trivial default build.
- Run the current stable compiler too; an MSRV-only CI matrix can miss new warnings, linker-policy changes, or forward-compatibility regressions.
- When you intentionally bump a library MSRV, document the change in the changelog/release notes and follow the project's compatibility/versioning policy.
- Tools such as `cargo-msrv` can help discover the apparent source floor, but the supported MSRV remains a project contract that CI should enforce.

### `proj-build-rs-minimal` — Keep `build.rs` deterministic, narrow its declared inputs, and write generated artifacts under `OUT_DIR`.

Cargo compiles and runs a package build script before building the package when that script needs to run. If a build script emits **no** `rerun-if-*` instructions, Cargo conservatively reruns it when any file in the package changes. Emitting narrow `cargo::rerun-if-changed` / `cargo::rerun-if-env-changed` instructions lets Cargo avoid unrelated rebuilds.
Build scripts also run as **host** programs. `cfg!(target_os = ...)` inside `build.rs` describes the host that executes the script, not necessarily the target being compiled. For target configuration, read Cargo's `CARGO_CFG_*` environment variables.
- `rerun-if-*` Details
- Keep the Script Small Enough to Audit

### `proj-lints-table` — Use `[lints]` / `[workspace.lints]` for centralized lint configuration

RFC 3389 (stable since Rust 1.74+) provides native `[lints]` and `[workspace.lints]` tables in Cargo.toml. This replaces `RUSTFLAGS`, `.cargo/config.toml`, and `clippy.toml` for most lint configuration. Centralizing lints in the manifest keeps configuration visible, version-controlled, and inheritable across workspace members.
**Known Limitation:**
Some clippy configuration flags have no `[lints.clippy]` equivalent (e.g., `allow-unwrap-in-tests` in `clippy.toml`). For those, `clippy.toml` may still be needed alongside the manifest lints.

### `proj-workspace-metadata` — Use `[workspace.package]` for shared metadata inheritance

Rust 1.64+ allows declaring package metadata (`version`, `edition`, `license`, `rust-version`, `authors`, `repository`, `description`) once in `[workspace.package]` and inheriting it in member crates with `field.workspace = true`. Without inheritance, each crate copies metadata independently — editions drift, `rust-version` lags behind, and license fields diverge.
Using `[workspace.package]` is mandatory best practice for any multi-crate workspace in 2026.

### `proj-workspace-publish` — Use `cargo publish --workspace` for native workspace publishing (Rust 1.90+)

Publishing multiple crates in a workspace historically required either manual ordering by dependency graph (error-prone) or external tools like `cargo-workspaces` or `cargo-release`. Since Rust 1.90+, `cargo publish --workspace` publishes all workspace crates in topological order — root dependencies first, leaf consumers last.

## 25. Clippy & Linting (LOW)

### `lint-deny-correctness` — Deny clippy::correctness and equivalent rustc lints

Correctness lints catch code that is outright wrong — logic errors, undefined behavior, or code that doesn't do what you think. These should always be errors, not warnings. Many Clippy correctness lints are now being uplifted to the Rust compiler.
CI also commonly wants lint warnings from local workspace packages to fail the build. Before Cargo 1.97, projects often reached for `RUSTFLAGS=-Dwarnings`, which changes compiler flags and therefore build-cache identities. Cargo 1.97 added a native warning policy: `CARGO_BUILD_WARNINGS=deny` (equivalent to Cargo's `build.warnings = "deny"`) can make local-package lint warnings fail the build without injecting a warning flag into `RUSTFLAGS`.

### `lint-warn-suspicious` — Enable clippy::suspicious for likely bugs

The `clippy::suspicious` lint group catches code patterns that are syntactically valid but almost always wrong. These are potential bugs that deserve investigation. Enabling this group as a warning helps catch mistakes early. Several related lints have also been uplifted to rustc.
**When to Allow:**
Rarely. If you need to suppress, document why:

### `lint-warn-style` — Enable `clippy::style` for established Rust idioms, while treating its suggestions as reviewable guidance rather than formatting law

`clippy::style` is one of Clippy's default warning groups. Its lints identify code that is valid but is usually clearer when written with common Rust idioms: `is_empty()` instead of `len() == 0`, `?` instead of propagation boilerplate, direct iteration instead of indexing by range, and so on.
Style lints are not rustfmt, and they are not the Rust compiler's Edition migration lints. Keep those concerns separate:
- Do Not Mix rustc Lints into `clippy::style`
**Practical Guidance:**
- Keep `clippy::style` enabled as a baseline for normal Rust code.
- Run Clippy on the targets/features that matter to the project.
- Review fixes for semantic or readability changes before applying them wholesale.
- Configure disputed lints individually instead of disabling the group.
- Do not confuse Clippy style guidance with rustfmt or Edition migration lints.
- Check current group membership before teaching a named lint as part of `style`.

### `lint-warn-complexity` — Enable `clippy::complexity` to catch needlessly complicated expressions and operations

`clippy::complexity` is one of Clippy's default warning groups. Its lints target code that performs unnecessary operations or expresses a simple computation in a more complicated way than needed.
The group is not a general measurement of “cognitive complexity,” and it does not contain every lint that can make code shorter. Clippy assigns each lint to a primary group such as `complexity`, `style`, `perf`, `suspicious`, or `correctness`; use the current Clippy documentation when group membership matters.
**Practical Guidance:**
- Enable `clippy::complexity` unless the project has a deliberate reason not to use Clippy's default warning groups.
- Run `cargo clippy --all-targets --all-features` in CI when those configurations are supported.
- Review the named lint before documenting why a piece of code is warned on.
- Do not equate shorter code with better code; preserve clarity and required semantics.
- Keep Clippy group guidance separate from Rust edition migration guidance.

### `lint-warn-perf` — Enable `clippy::perf` for established performance anti-patterns; measure before adding optimizer hints

`clippy::perf` contains lints for patterns that are commonly more expensive than a straightforward alternative: redundant allocations, unnecessary cloning, avoidable indirection, and inefficient collection access. It is a useful default warning group, but it is not a profiler and it does not prove that a linted expression matters to your workload.
Compiler hints such as `std::hint::select_unpredictable` and `std::hint::cold_path` are a separate tool. They can change code generation, but their effect is intentionally not guaranteed and can make performance worse when the hint does not match reality.
- Prefer: Fix the Cost, Not Merely the Spelling
**Allocation Guidance:**
`Vec::new()` and `vec![]` both create an empty vector without allocating element storage. The useful optimization is normally to avoid an allocation altogether or reserve capacity when the final size is reasonably predictable.
`with_capacity` is not automatically better: substantial over-reservation wastes memory, and tiny vectors may not justify forecasting capacity.
**Practical Guidance:**
- Enable `clippy::perf` as a warning group and review its findings rather than blindly applying them.
- Keep the project's MSRV in mind when Clippy suggests newer APIs.
- Prefer removing allocations/copies to micro-tuning syntax.
- Profile before changing hot code on performance grounds.
- Treat `select_unpredictable` and `cold_path` as measured, advisory hints—not code-generation contracts.

### `lint-pedantic-selective` — Enable clippy::pedantic selectively

The `clippy::pedantic` group contains opinionated lints that aren't universally applicable. Enabling it wholesale produces noise; selectively enabling useful pedantic lints improves code quality without false positives.

### `lint-missing-docs` — Warn on missing documentation for public items

The `missing_docs` lint ensures all public API items are documented. For libraries, documentation IS the user interface. Missing docs mean users can't understand your API without reading source code.

### `lint-unsafe-doc` — Document every unsafe operation with the invariant that makes it sound

An `unsafe` block tells the compiler that the programmer has discharged safety obligations the type system cannot verify. A useful `// SAFETY:` comment records those obligations and, crucially, why they hold at that exact call site. This makes review and later refactoring much less dependent on reconstructing hidden assumptions.
Clippy's `undocumented_unsafe_blocks` lint checks for a safety comment associated with unsafe blocks and unsafe impls. Separately, in Edition 2024, rustc's `unsafe_op_in_unsafe_fn` lint is **warn-by-default**: unsafe operations inside an `unsafe fn` should still appear in explicit `unsafe { ... }` blocks. Projects may choose to raise either lint to `deny`.
- Keep Unsafe Blocks Small Enough to Review

### `lint-cargo-metadata` — Enable clippy::cargo for published crates

The `clippy::cargo` lint group checks Cargo.toml for issues that affect publishing and dependency management. For crates intended for crates.io, these checks help ensure a professional, well-configured package.
**When to Disable:**
For internal/unpublished crates:
Or selectively:

### `lint-rustfmt-check` — Run cargo fmt --check in CI

Consistent formatting eliminates style debates and makes diffs cleaner. Running `cargo fmt --check` in CI ensures all code follows the same format. This catches formatting issues before merge, not after.

### `lint-workspace-lints` — Configure lints at workspace level for consistent enforcement

Without centralized lint configuration, each crate develops its own standards (or none). Workspace-level lints (Rust 1.74+) ensure consistent code quality across all crates. Denied lints catch issues in CI before they reach production.

### `lint-cfg-check` — Enable `unexpected_cfgs` and declare known cfgs to catch feature-gate typos

A typo in a cfg expression — `#[cfg(feature = "serde_")]` instead of `"serde"`, or `#[cfg(tokio_unstable)]` with no declaration — compiles silently and produces dead code or an always-disabled feature. The `unexpected_cfgs` lint (stabilized in Rust 1.80) flags any cfg name or value not known to the compiler. Cargo automatically teaches the compiler about your declared feature names; for custom cfgs (well-known ones like `tokio_unstable`, or your own) you must declare them via `check-cfg` in the `[lints.rust]` table. This catches bugs at compile time that would otherwise be invisible.

### `lint-clippy-nursery-selected` — Enable `clippy::nursery` lints selectively and re-check group membership when the toolchain changes

Clippy's `nursery` group is explicitly opt-in: these lints are useful but may still have known limitations or evolving diagnostics. Enabling the whole group can create churn as lints change, graduate to another group, or reveal edge cases in a new toolchain.
Select individual lints whose trade-offs fit the codebase and pin/review them with the project's Rust toolchain.
- Avoid: Enable the Whole Nursery Group Without Review
- Prefer: Select Current Nursery Lints Deliberately
**Policy Guidance:**
- Prefer `[lints.clippy]` in `Cargo.toml` when the lint policy should apply crate-wide.
- Review a lint's current documentation before adding it to `deny`; nursery lints may document known problems.
- When upgrading Rust, run Clippy and review changed group membership or diagnostics instead of assuming the old policy description is still exact.
- Do not label a lint “nursery” merely because it once lived there.

### `lint-cargo-unused-features` — Detect unused feature flags declared in Cargo.toml (`[lints.cargo]`, nightly-only)

Feature flags declared in `Cargo.toml` `[features]` that are never referenced in code, `cfg()` expressions, or dependency gates accumulate over time. They make the API surface misleading and increase maintenance burden. A future Cargo lint will detect these automatically; until then, review and prune features manually.
- Configuration (Nightly Only)

### `lint-dylint-custom` — Use Dylint for project-specific custom lints without forking clippy

Clippy is comprehensive, but projects occasionally need lints that are too specific, experimental, or domain-specific for inclusion in clippy. Dylint provides a framework for authoring and running custom lint libraries without forking clippy or modifying the toolchain.
**When to Use Custom Lints:**
- Enforcing project-specific API usage patterns
- Banning certain crate imports or function calls
- Custom naming conventions beyond what clippy offers
- Migration helpers for internal deprecations
- Experimental lints before proposing to clippy

### `lint-edition-2024` — Use the `rust_2024_compatibility` lint group and `cargo fix --edition` to audit edition-sensitive code before switching to Rust 2024

Rust editions can change parsing, name resolution, temporary lifetimes, safety requirements, and other language semantics while preserving compatibility for crates that stay on an older edition. The compiler therefore provides **migration lints** that find code whose meaning or validity changes when moving to Edition 2024.
Do not invent a hand-maintained list of supposed “Edition 2024 lints” with guessed default levels. Rust exposes the real `rust-2024-compatibility` lint group, and `cargo fix --edition` enables that migration machinery and applies machine-applicable rewrites.
**Unsafe Attributes Are a Language Requirement:**
Edition 2024 requires unsafe attributes such as `no_mangle`, `export_name`, and `link_section` to use the `unsafe(...)` form. This is stronger than a style preference:
The migration lint `unsafe_attr_outside_unsafe` helps rewrite the syntax, but the programmer must still review the attribute's safety requirements.
- `extern` Blocks Must Be Marked Unsafe
- `if let` Temporary Scope Changed
**Practical Guidance:**
- Run `cargo fix --edition` before changing the manifest edition.
- Review every safety-related automatic rewrite; migration tooling cannot prove your safety invariants.
- Treat `rust_2024_compatibility` as a migration aid, not a permanent substitute for understanding semantic changes.
- Do not guess default lint levels; query the compiler version you actually support with `rustc -W help`.
- Keep rustc edition lints separate from Clippy's `style`, `complexity`, `perf`, and other groups.
- After migration, run tests, Clippy, and rustdoc under the new edition.

### `lint-lints-table` — Use the `[lints]` table in `Cargo.toml` for canonical lint configuration (Rust 1.74+)

The `[lints]` table in `Cargo.toml` (Rust 1.74+) is the canonical way to configure lints. It replaces inner attributes like `#![deny(clippy::correctness)]` in `lib.rs` as the primary mechanism. Centralizing lint config in `Cargo.toml` keeps code clean, makes lint policy visible at a glance, and enables workspace inheritance.

### `lint-uplifted` — Track Clippy lints uplifted into rustc and adjacent compiler lint changes (Rust 1.86-1.99)

Clippy lints are increasingly being uplifted into the Rust compiler (`rustc`), while newer rustc releases also add adjacent diagnostics that matter to the same safety and correctness policy. Uplifted lints run on every `rustc` invocation without needing Clippy. Track both the uplifts and the nearby compiler-lint changes so configuration stays in `[lints.rust]` when rustc owns the diagnostic.

## 26. Anti-patterns (REFERENCE)

### `anti-unwrap-abuse` — Avoid `unwrap()` and `expect()`; make failure handling or invariant representation explicit

`unwrap()` and `expect()` turn `None` or `Err` into hidden panic control flow. For strict AI-maintained code, there is little reason to accept that shortcut: propagate failures, handle alternatives, assert on the value directly in tests, or represent the invariant in the type system.
The goal is not merely “no bare unwraps.” Replacing `unwrap()` with `expect()` keeps the same failure semantics and is not a fix.
- Tests Do Not Need Panic Extraction
- Prefer Infallible Constants and Constructors

### `anti-expect-lazy` — Do not use `expect()` as a shortcut for either error handling or invariant enforcement

`.expect(message)` is still an implicit panic. The message improves diagnostics, but the caller still cannot see or choose the failure policy.
For strict AI-maintained code, handle the `Result`/`Option` explicitly. Propagate ordinary failures, encode invariants in types, and keep deliberate process termination at the application's outer boundary.
**Decision Guide:**
| Situation | Typical choice |
|---|---|
| Invalid user/config input | return/propagate an error |
| File/network/database failure | return/propagate or recover |
| Optional lookup miss | `Option` or domain error |
| Internal invariant | encode it in types/state; otherwise return an invariant error |
| Fixed literal | use an infallible constant/constructor where available |
| OS thread creation | `Builder::spawn` and handle its `io::Result` |
| Worker panic at `join()` | supervision policy handles the `Result` |
| Fatal application prerequisite | report at top level and return failure `ExitCode` |

### `anti-clone-excessive` — Do not clone merely to satisfy ownership when borrowing, moving, or deliberate sharing better matches the API

`Clone` is an ownership operation, not a synonym for “heap allocation.” Its cost is entirely type-dependent:
- cloning a small plain value may be just a copy; - cloning `String` or `Vec<T>` generally duplicates owned contents and may allocate; - cloning `Arc<T>` increments a reference count rather than duplicating `T`; - clone-on-write types can share heap storage until mutation.
- Borrow When the Callee Only Needs a View
- Iterate by Reference When Ownership Is Not Needed
- Move When the Source Is Finished
- Clone When Independent Ownership Is Actually Required
- Avoid Both Extremes
**Practical Guidance:**
- Borrow when the callee only needs temporary read access.
- Move when the source no longer needs the value.
- Clone when independent ownership is genuinely required.
- Use `Arc`/`Rc` when shared ownership is the intended model, not merely as a generic clone optimization.
- Treat clone cost as type-specific; `Clone` itself promises no allocation behavior.
- Use `clone_from` only as a concrete-type reuse opportunity, not a universal guarantee.
- Prefer clear ownership over lifetime gymnastics, then measure expensive copies in representative workloads.

### `anti-lock-across-await` — Do not hold blocking lock guards across `.await`; an async mutex may intentionally span `.await` when the protected resource must remain exclusively owned.

"Never hold a lock across `.await`" is too broad. The important distinction is the lock implementation and the invariant being protected.
A blocking lock such as `std::sync::Mutex` blocks the current OS thread while waiting. Its `MutexGuard` is also deliberately `!Send`, so a future that keeps that guard across an `.await` cannot be passed to `tokio::spawn`. Even on a local executor where `Send` is not required, holding a blocking guard across suspension can deadlock or stall an executor thread if another task later tries to acquire the same lock.
- Avoid: Blocking Guard Held Across Await
- Prefer: Async Work First, Short Blocking Critical Section Afterward
- Also Good: Async Mutex Across Await When Serialization Is the Invariant

### `anti-string-for-str` — Prefer `&str` over `&String` when the API only needs string contents

`&str` is the natural borrowed string-view type. It accepts string literals, slices, and borrowed `String` values through deref coercion. A `&String` parameter unnecessarily requires the caller to possess the specific owned `String` representation even when the function only reads text.
This does **not** mean `&String` is invalid. Use it when the API genuinely needs `String`-specific state such as capacity. The rule is to accept the least restrictive borrowed type that provides the operations the function actually needs.
- When `&String` Is Actually Appropriate

### `anti-vec-for-slice` — Accept slices when an API only needs element access; accept `Vec` references when vector-specific capacity or length-changing operations are genuinely part of the contract

`&[T]` and `&mut [T]` describe borrowed contiguous elements without requiring a particular owning container. A function that only reads or mutates existing elements can therefore work with vectors, arrays, boxed slices, subslices, and other slice-producing storage.
`&Vec<T>` / `&mut Vec<T>` are appropriate when the function actually needs vector-specific state or operations such as capacity, `push`, `reserve`, or changing the logical length.
- Read-Only Element Access: Prefer `&[T]`
- Mutating Existing Elements: Prefer `&mut [T]`
- Read-Only Vector Metadata Can Also Justify `&Vec<T>`
**Practical Guidance:**
- Accept `&[T]` for read-only access to existing contiguous elements.
- Accept `&mut [T]` when mutating elements without changing length.
- Accept `&Vec<T>` when vector-specific metadata such as capacity is part of the operation.
- Accept `&mut Vec<T>` for length/capacity-changing operations such as `push`, `pop`, `truncate`, or `reserve`.
- Rely on deref coercion so `&Vec<T>` callers naturally satisfy slice parameters.
- Use generic `AsRef<[T]>` only when accepting a wider family of representations is an intentional API benefit.
- Choose the least specific abstraction that still exposes every operation the implementation legitimately needs.

### `anti-index-over-iter` — Don't use indexing when iterators work

Manual indexing (`for i in 0..len`) requires bounds checks on every access, prevents SIMD optimization, and introduces off-by-one error risks. Iterators eliminate these issues and are more idiomatic Rust.
- When Indices Are Needed

### `anti-panic-expected` — Do not use panics as the API for expected runtime failures; keep deliberate termination and assertions explicit at their real boundary

A panic bypasses the function's ordinary return contract. That makes it a poor substitute for `Result` or `Option` when callers can encounter invalid input, missing files, parse failures, unavailable resources, or startup prerequisites.
For strict AI-maintained code, also avoid hiding programmer assumptions behind `unwrap()`/`expect()`. Encode invariants in types where possible and return an explicit invariant error otherwise.
- Internal Invariants: Prefer Representation Over Recovery
- Avoid Panic-Based Lookup APIs When Missing Is Normal
**Decision Guide:**
| Condition | Typical action |
|---|---|
| Invalid user/config input | return `Err` |
| Network/I/O/resource failure | return `Err` or recover |
| Optional lookup miss | `Option` or domain `Result` |
| Internal invariant | encode it in types/state or return explicit invariant error |
| Documented caller precondition | assertion/indexing plus `# Panics` documentation when that contract is intentional |
| Test assertion failure | assertion through the test harness |
| Fatal binary startup policy | handle the `Result` at the outer boundary and return failure `ExitCode` |
| Library startup/configuration failure | return the error to the caller |

### `anti-empty-catch` — Do not accidentally discard errors; make best-effort and discard semantics explicit

A `Result` carries information about whether an operation succeeded. Silently losing that information can hide a bug, but not every error must be propagated or logged. Cleanup, telemetry, cache warming, shutdown, and other best-effort operations may deliberately ignore failure.
The important distinction is **accidental loss** versus an **intentional API policy**. Code should make that policy legible at the point where the error stops mattering.
**Decision Guide:**
| Situation | Typical action |
|-----------|----------------|
| Caller can/should react | Return or propagate the error |
| Local recovery exists | Handle/retry/fallback |
| Batch partial failure matters | Aggregate failures |
| Operational visibility matters | Log/metric/report |
| Failure is intentionally irrelevant | Explicitly discard, ideally with a short reason |
| You only need success/missing state | Converting to `Option` can be appropriate |

### `anti-over-abstraction` — Introduce generics and traits when they express a stable semantic boundary; do not generalize code solely for hypothetical flexibility

Rust gives several forms of abstraction—generic type parameters, traits, trait objects, associated types, enums, macros, and ordinary functions. Each can make code clearer when it captures a real relationship, and each can make code harder to understand when it exists only because “we might need this later.”
The costs are not one-dimensional:
- Start Concrete When the Domain Is Concrete
- Generalize When the Shared Operation Is Real
- Do Not Use a “Rule of Three” as a Gate
- Closed Sets Often Prefer Enums
**Practical Guidance:**
- Start concrete when requirements are concrete and uncertain.
- Generalize when an abstraction captures real shared behavior or a deliberate architectural boundary.
- Do not require two or three implementations before a trait can be justified.
- Treat public generics as API commitments, not free future-proofing.
- Use enums for closed sets and traits/generics for open behavioral sets when appropriate.
- Allow marker traits when they encode a real semantic property.
- Implement `Deref` only when implicit target-like behavior is part of the abstraction.
- Measure compile time, code size, and runtime effects instead of relying on blanket performance claims.

### `anti-premature-optimize` — Don't optimize before profiling

Optimization has costs: engineering time, extra complexity, portability constraints, and sometimes worse performance on workloads you did not measure. Start with clear code, measure a representative build/workload, then optimize the bottlenecks that matter.
This does not mean “ignore obvious asymptotic problems until production.” Choose sensible algorithms and data structures up front; reserve low-level tuning and added complexity for cases backed by measurements or hard requirements.
- When Up-Front Optimization Is Justified

### `anti-type-erasure` — Prefer static polymorphism when one concrete type is sufficient; use `dyn Trait` deliberately when runtime type erasure and heterogeneous implementations are part of the design

Rust supports both static and dynamic polymorphism:
- generics and `impl Trait` keep a concrete type known to the compiler and use static dispatch; - `dyn Trait` erases the concrete type behind a dyn-compatible trait and uses dynamic dispatch.
- Return `impl Trait` When One Hidden Concrete Type Is Enough
- Use `dyn Trait` for Runtime Heterogeneity
- A Trait Object Does Not Require Ownership or Allocation
**Practical Guidance:**
- Return `impl Trait` when the callee can choose one hidden concrete type.
- Use argument-position `impl Trait`/generics when callers choose concrete types and static dispatch is appropriate.
- Use `dyn Trait` when runtime heterogeneity or deliberate type erasure is required.
- Choose `&dyn`, `Box<dyn>`, `Arc<dyn>`, etc. from ownership/lifetime needs; `dyn` itself does not mandate heap allocation.
- Prefer an enum for a closed, known implementation set when exhaustiveness is useful.
- Remember RPITIT is stable, but opaque-return trait methods generally prevent dyn compatibility.
- Measure code size/runtime/compile-time effects instead of relying on blanket “zero-cost” or “smaller binary” claims.

### `anti-format-hot-path` — Avoid unnecessary intermediate formatting allocations in measured hot paths; keep `format!` when a new owned `String` is the actual result you need

`format!(...)` constructs an owned `String`. That allocation is avoidable when formatted output is immediately copied into an existing `String`, byte buffer, logger, file, socket, or other sink. In a high-frequency path, eliminating those intermediates can reduce allocator and copy traffic.
But “never use `format!` in a hot path” is too broad. If the API fundamentally needs a new owned string, some owned storage is required. The relevant questions are:
- Reuse a Buffer When the Lifetime Contract Allows It
- Implement `Display` When the Value Has a Natural Text Representation
- Logging Macros Can Avoid Eager String Construction
- When `format!` Is Fine—even in Frequently Called Code
- Capacity Estimates Must Be Defensible
- Do Not Publish Universal Performance Rankings
**Practical Guidance:**
- Use `format!` when a new owned formatted `String` is the desired result.
- Use `write!`/`writeln!` when a destination buffer or I/O sink already exists.
- On Rust 1.98+, consider `NumBuffer` + integer `format_into` for measured hot-path primitive decimal conversion.
- Reuse buffers only when result lifetimes/ownership make reuse possible.
- Implement `Display` for values with a natural textual representation so callers control allocation.
- Treat `format_args!` as borrowed formatting arguments, not owned storage.
- Pass formatting directly to logging APIs when supported instead of pre-building a `String`.
- Reserve capacity from meaningful bounds, not arbitrary constants.
- Profile before claiming a formatting optimization matters.

### `anti-collect-intermediate` — Keep iterator pipelines lazy when materialization adds no semantic value; collect only when you need owned storage, reordering, repeated access, or another collection operation

An intermediate collection can add allocation, copying/moving, memory traffic, and an additional traversal boundary. When the next operation can consume the iterator directly, staying lazy is often simpler and cheaper.
But `.collect()` is not inherently wrong, and the `Iterator` trait does not guarantee that every possible collection performs a heap allocation. Materialization can be exactly what the algorithm requires—for sorting, indexing, ownership, reuse, or separating phases.
- Use Iterator Consumers for Questions About the Stream
- Materialize When the Next Operation Requires It
- Repeated Traversal Does Not Automatically Require Collection
**Returning an Iterator Can Defer the Decision:**
This is useful when the function's natural output is a traversal and callers should choose whether to count, search, stream, or materialize it.
Returning `impl Iterator` also commits the function to one hidden concrete iterator type per function body; if callers need runtime heterogeneous iterator implementations, another abstraction may be required.
- Avoid Universal Allocation/Pass Tables
**Practical Guidance:**
- Keep filter/map/etc. lazy when the next operation can consume the iterator directly.
- Prefer direct consumers such as `any`, `find`, `count`, and `sum` for stream questions.
- Collect when you need ownership, sorting, indexing, mutation, phase separation, or durable reuse.
- Recompute a cheap repeatable iterator when that is simpler than storing it; materialize expensive/nonrepeatable work when appropriate.
- On stable Rust 1.98, reuse caller-provided collections with `clear` + `extend`; `collect_into` remains nightly-only.
- Do not promise fixed allocation counts without measuring the concrete collection and workload.

### `anti-stringly-typed` — Don't use strings where enums or newtypes provide a meaningful domain type

Strings are appropriate for free-form text and external wire formats, but they are a poor internal representation for a closed set of states or a value with important invariants. Encoding those concepts as enums or newtypes lets the compiler reject swapped arguments and invalid states, centralizes validation, and makes APIs self-documenting.
Parse untrusted strings at boundaries, then use typed values internally.
- When Strings Are Fine

### `anti-arc-mutex-everything` — Do not default to `Arc<Mutex<T>>` when ownership, channels, atomics, or another synchronization primitive better matches the state

`Arc<Mutex<T>>` is a useful way to share mutable state, not a universal default. A mutex serializes access to the protected value, and every caller must reason about lock scope and lock ordering. In async code, the choice between a synchronous mutex and an async mutex also matters.
Start from the ownership model and required operations:
- Avoid: Unnecessary Shared Mutable State
- Prefer: Single-Owner State with Messages
- Prefer: Atomics for an Independent Counter
- Prefer: Own Per-Task State When Sharing Is Unnecessary
**Decision Guide:**
| Shape of the problem | Usually consider |
|---|---|
| State has one natural owner | owned state, possibly `mpsc`/`oneshot` requests |
| Independent counter/flag | atomic with justified ordering |
| Per-request/per-connection data | owned local state |
| Short synchronous critical section | `std::sync::Mutex` / `parking_lot::Mutex` |
| Guard genuinely crosses `.await` | `tokio::sync::Mutex` or redesign ownership |
| Concurrent reads are important | `RwLock`, after considering contention/fairness |
| Multi-field invariant needs one snapshot | a lock or another coordinated representation |
**Practical Guidance:**
- Prefer clear ownership over shared ownership when the data model permits it.
- Do not turn several related fields into independent atomics unless the required cross-field consistency is preserved.
- Keep lock scopes small and explicit.
- Do not assume channels, actors, `RwLock`, or lock-free structures are universally faster than a mutex.
- Choose synchronous versus asynchronous mutexes based on whether a guard must cross `.await`, not on whether the caller happens to be async.

### `anti-blocking-async-drop` — Don't block or depend on asynchronous work completing from `Drop` of async types

`Drop::drop()` is synchronous and runs on the thread that drops the value. In an async program that may be an executor worker, so blocking I/O, sleeps, or nested runtime entry can stall unrelated tasks. Spawning async cleanup from `Drop` is also unreliable as a completion guarantee: the runtime may be shutting down, and `Drop` cannot await the spawned task.
Make required asynchronous cleanup an explicit operation. Keep `Drop` for fast synchronous resource release or best-effort diagnostics.
**Decision Guide:**
| Situation | Preferred approach |
|-----------|--------------------|
| Memory/RAII handle release | ordinary `Drop` |
| OS handle whose close is synchronous | ordinary `Drop` |
| Protocol flush / graceful network shutdown | explicit `async fn close` |
| Required remote acknowledgement | explicit async operation |
| Blocking I/O or sleeps | never perform in async-type `Drop` |
| Best-effort background cleanup | only if loss is acceptable; do not treat spawn as a guarantee |
A useful API pattern is to make `close(self)` consume the object when possible, so successful explicit cleanup also prevents accidental reuse.

### `anti-block-on-async` — Don't call `block_on` from code that is already running asynchronously

`Runtime::block_on` and `Handle::block_on` are bridges from synchronous code into async execution. Calling them from code that is already executing inside an async runtime does not make the nested work “more synchronous”; it can block an executor worker and Tokio runtime-entry combinations can panic when a runtime is started from a thread that is already driving one.
Inside async code, await the future. Keep `block_on` at a deliberately synchronous boundary such as a process entry point or a synchronous API adapter whose caller is not already inside that runtime.

### `anti-deref-overuse` — Implement `Deref` only when transparent target-like behavior is part of the type's intended API

`Deref` is more than a convenience delegation hook. A `Deref<Target = T>` implementation participates in deref coercion and method lookup, so callers can often use `&Wrapper` where `&T` is expected and can call methods from `T` through the wrapper.
That is appropriate when the wrapper is intended to behave transparently like its target and dereferencing is cheap and unsurprising. It is usually a poor fit for an invariant-bearing domain newtype whose abstraction is meant to remain visible.
- Avoid: Incidental Delegation Through `Deref`
- Prefer: Explicit Access for an Invariant-Bearing Newtype
**Decision Guide:**
| Intent | Typical choice |
|---|---|
| Transparent pointer/target-like wrapper | Consider `Deref` |
| Domain newtype with visible semantics/invariants | Explicit inherent methods |
| Generic borrowed conversion is useful | Consider `AsRef<T>` |
| Expose one or two inner operations | Delegate those methods explicitly |
| FFI layout guarantee | `#[repr(transparent)]` is separate from `Deref` |

### `anti-unsafe-send-sync` — Never use `unsafe impl Send` or `unsafe impl Sync` merely to silence auto-trait errors; each impl is a safety contract that other unsafe code may rely on

`Send` and `Sync` are unsafe auto traits:
- `T: Send` means it is sound to transfer ownership of `T` to another thread; - `T: Sync` means it is sound to share `&T` between threads (`&T: Send`).
- Prefer Representations That Derive the Correct Auto Traits
- Keep Thread-Affine FFI Handles on Their Owner Thread
**Practical Guidance:**
- Treat every `unsafe impl Send` / `unsafe impl Sync` as a safety proof obligation.
- Prefer safe fields that let Rust derive the correct auto traits automatically.
- Remember raw pointers are neither `Send` nor `Sync`.
- Remember `Mutex<T>` requires `T: Send`; `Mutex<*mut T>` does not magically become thread-safe.
- Keep thread-affine foreign handles on one thread and communicate via messages when appropriate.
- Justify `Send` and `Sync` separately from ownership, aliasing, mutation, destruction, callbacks, and foreign-library guarantees.
- Use explicit negative-auto-trait marker fields such as `PhantomData<Rc<()>>` when stable structural non-Send/non-Sync behavior is desirable.
- Treat sanitizer/stress testing as supplemental evidence, never the proof itself.

### `anti-session-fixation` — Rotate session IDs when authentication or privilege changes so a pre-authentication identifier cannot inherit elevated state.

A server-side session identifier is itself a capability. Before login it may legitimately identify low-privilege state such as a CSRF synchronizer token, locale, or an anonymous cart. If authentication simply adds privileged state to that same session record, anyone who learned or planted the pre-authentication ID can inherit the authenticated session after the victim logs in.
That is session fixation. Strong passwords, secure cookies, and CSRF protection do not fix it: the problem is preserving an already-known capability across a privilege boundary.
