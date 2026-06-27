# unsafe-strict-provenance

> Prefer strict provenance APIs (`ptr.addr()`, `ptr.map_addr()`, `ptr.with_addr()`) over integer-pointer round-tripping (`as usize` / `as *const T`); prefer raw borrow syntax (`&raw const x` / `&raw mut x`) over `addr_of!` / `addr_of_mut!`.

## Why It Matters

Every pointer carries **provenance** — metadata that describes which allocation it belongs to and which memory it may access. Converting a pointer to an integer with `as usize` discards provenance, and converting the integer back with `as *const T` creates a new pointer whose provenance is ambiguous. The compiler and Miri treat such round-tripped pointers as potentially pointing anywhere, which can cause undefined behavior, inhibit optimizations, and produce false positives from dynamic analysis.

Strict provenance APIs (stabilized in Rust 1.84) make the provenance flow explicit: `addr()` extracts only the address without exposing provenance, `with_addr()` reattaches the original pointer's provenance to a new address, and `map_addr()` transforms the address while keeping provenance intact.

Similarly, the raw borrow operators `&raw const` / `&raw mut` (stabilized in Rust 1.82) create raw pointers directly without creating an intermediate reference — avoiding UB from unaligned or uninitialized place expressions that would occur if you wrote `&x as *const T` instead.

## Bad

```rust
// Loses provenance — Miri strict-provenance flags this.
let ptr: *const u32 = &val;
let addr = ptr as usize;                     // provenance discarded
let back = addr as *const u32;               // provenance invented — may be UB

// Pointer tagging the wrong way.
let tagged = (ptr as usize) | 0x1;           // provenance lost
let tagged_ptr = tagged as *const u32;       // invalid provenance

// Creating a raw pointer through a reference — UB for repr(packed) fields.
let field_ptr = &packed.unaligned as *const u32;  // intermediate & is UB
```

## Good

```rust
use std::ptr;

// ---- 1. Address extraction with provenance preserved ----
let ptr: *const u32 = &val;
let addr = ptr.addr();                        // usize, no provenance exposed
let back = ptr.with_addr(addr);               // provenance restored from ptr

// ---- 2. Address transformation ----
// Align down to 8-byte boundary, keeping provenance.
let aligned = ptr.map_addr(|a| a & !0b111);

// ---- 3. Pointer tagging via map_addr ----
// Store a tag bit in the low bits (sound when alignment is known).
let tagged = ptr.map_addr(|a| a | 0x1);
let untagged = tagged.map_addr(|a| a & !0x1);

// ---- 4. Raw borrow syntax (Rust 1.82+) ----
// Create raw pointers safely, even for repr(packed) fields.
let field_ptr: *const u16 = &raw const header.data_length;
let field_mut: *mut u8    = &raw mut header.flags;

// Equivalent to the now-soft-deprecated macros:
// let field_ptr = addr_of!(header.data_length);
// let field_mut = addr_of_mut!(header.flags);

// ---- 5. Creating dangling / null pointers ----
use std::ptr;

// Well-known sentinel addresses.
let zero: *const u32 = ptr::without_provenance::<u32>(0);               // null
let high: *const u32 = ptr::without_provenance::<u32>(0xFFFF_0000);
let dangling: *mut u32 = ptr::dangling_mut();                           // aligned, valid for ZST access

// ---- 6. Exposed provenance for FFI that *must* round-trip ----
// Only use expose_provenance / with_exposed_provenance when the system API
// (e.g., mmap, shmget) inherently works with integer addresses.
let exposed = ptr.expose_provenance();
// ... pass exposed to FFI ...
let restored: *mut u32 = ptr::with_exposed_provenance_mut(exposed);
```

## Key Points

- **Strict provenance APIs are stable since Rust 1.84**. They are the preferred way to decompose and recompose pointer-address pairs. See the tracking issue [#95228](https://github.com/rust-lang/rust/issues/95228).
- **Raw borrow operators `&raw const` / `&raw mut` are stable since Rust 1.82** and **soft-deprecate** `addr_of!` / `addr_of_mut!`. Prefer the native syntax in new code.
- `addr()` returns a `usize` but does **not** expose provenance. This is the key difference from `as usize` — the compiler and Miri can still reason about where the pointer came from if the provenance is later reattached with `with_addr()` or `map_addr()`.
- `without_provenance::<T>(addr)` creates a pointer with no provenance — useful for well-known sentinel addresses (null, MMIO regions) but dereferencing it (except possibly for ZSTs) is immediate UB.
- `expose_provenance()` / `with_exposed_provenance()` are for migrating existing code that genuinely cannot avoid integer-pointer round-tripping (e.g., system APIs like `mmap`). New code should avoid them.
- Miri's `-Zmiri-strict-provenance` flag detects provenance violations — run it in CI (see `unsafe-miri-ci.md`).

## See Also

- [unsafe-miri-ci](unsafe-miri-ci.md) — detect provenance violations in CI with Miri's `-Zmiri-strict-provenance`
- [unsafe-maybeuninit](unsafe-maybeuninit.md) — use `MaybeUninit<T>` for uninitialized memory (often combined with raw pointers)
- [unsafe-safety-comment](unsafe-safety-comment.md) — document the invariants of every unsafe block including raw pointer dereferences
- [type-repr-transparent](type-repr-transparent.md) — use `#[repr(transparent)]` for FFI newtypes that interact with raw pointers
