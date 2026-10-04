# unsafe-strict-provenance

> Prefer strict provenance APIs (`ptr.addr()`, `ptr.map_addr()`, `ptr.with_addr()`) over integer-pointer round-tripping (`as usize` / `as *const T`); prefer raw borrow syntax (`&raw const x` / `&raw mut x`) over `addr_of!` / `addr_of_mut!`.

## Why It Matters

A pointer carries an address plus **provenance** describing what memory accesses it can justify. Rust provides two models for code that manipulates pointer addresses:

- **Strict Provenance** keeps a pointer with the desired provenance available and changes or extracts only its address with APIs such as `addr`, `with_addr`, and `map_addr`.
- **Exposed Provenance** covers pointer→integer→pointer workflows. A `ptr as usize` cast is equivalent to exposing the pointer's provenance, and an integer→pointer cast is equivalent to reconstructing a pointer using some previously exposed provenance when possible.

Exposed Provenance is intentionally less precise and harder for tools and unusual architectures to support. Prefer Strict Provenance when the algorithm can retain a source pointer carrying the required provenance.

Raw borrow syntax (`&raw const place` / `&raw mut place`) is also preferable when creating a raw pointer to a place for which forming an intermediate Rust reference would itself be invalid, such as an unaligned field of a packed struct.

## Bad

```rust
let value = 123u32;
let ptr: *const u32 = &value;

// This opts into the ambiguous Exposed Provenance model.
let addr = ptr as usize;
let back = addr as *const u32;

// Address tagging through integer casts also unnecessarily exposes provenance.
let tagged_addr = (ptr as usize) | 1;
let tagged_ptr = tagged_addr as *const u32;

let _ = (back, tagged_ptr);
```

Integer casts are not automatically UB, but they are a poorer default when a provenance-preserving pointer is already available.

## Good

```rust
use std::ptr;

let value = 123u32;
let ptr: *const u32 = &value;

// Extract an address without exposing provenance, then reattach ptr's provenance.
let addr = ptr.addr();
let back = ptr.with_addr(addr);
assert_eq!(back, ptr);

// Transform an address while retaining ptr's provenance.
let tagged = ptr.map_addr(|a| a | 1);
let untagged = tagged.map_addr(|a| a & !1);
assert_eq!(untagged, ptr);

#[repr(packed)]
struct Header {
    data_length: u16,
    flags: u8,
}

let mut header = Header {
    data_length: 7,
    flags: 0,
};

// Raw borrows do not create an intermediate reference to a packed field.
let field_ptr: *const u16 = &raw const header.data_length;
let field_mut: *mut u8 = &raw mut header.flags;
let _ = (field_ptr, field_mut);

// Synthesize an address only when no provenance-bearing source pointer exists.
let null: *const u32 = ptr::without_provenance(0);
assert!(null.is_null());

// If an external API truly requires an integer round trip, make the choice
// explicit with the Exposed Provenance APIs.
let exposed = ptr.expose_provenance();
let restored: *const u32 = ptr::with_exposed_provenance(exposed);
let _ = restored;
```

A tagged pointer must be untagged before dereferencing, and the resulting address must still be within the range permitted by the retained provenance and satisfy the usual alignment/validity requirements.


## Rust 1.99+: Prefer Raw Layout APIs When You Only Have a Raw Pointer

Rust 1.99 stabilizes `size_of_val_raw`, `align_of_val_raw`, and
`Layout::for_value_raw`. They let unsafe code query layout from a raw pointer,
including a pointer to a dynamically sized value, without first manufacturing
a reference merely to call the reference-based layout APIs.

```rust
use core::alloc::Layout;
use core::mem::{align_of_val_raw, size_of_val_raw};

unsafe fn inspect_layout<T: ?Sized>(ptr: *const T) -> (usize, usize, Layout) {
    // SAFETY: the caller guarantees ptr has metadata valid for these raw
    // layout queries, as required by each API.
    unsafe {
        (
            size_of_val_raw(ptr),
            align_of_val_raw(ptr),
            Layout::for_value_raw(ptr),
        )
    }
}
```

These functions are still `unsafe`: for a DST, the pointer metadata must be
valid enough for the layout computation even when the pointee memory is not
dereferenced. Use them to avoid creating an unnecessary reference, not to turn
an arbitrary bit-pattern pointer into a valid Rust object.

Rust 1.99 also adds the allow-by-default `raw_borrows_via_references` lint.
It detects cases where code creates a reference only for it to decay
immediately to a raw pointer. That is a useful review signal in unsafe-heavy
code: prefer a direct raw borrow when a reference is not part of the intended
invariant.

## Rust 1.99+: Raw Ownership Handoffs Should Not Round-Trip Through `leak`

Do not use `Box::leak` as a temporary route to a raw pointer and later
reconstruct ownership. The Rust 1.99 documentation explicitly recommends
against that “unleak” pattern because it interacts poorly with current and
future optimizer/allocator assumptions.

When ownership must leave `Box` temporarily, use the ownership-preserving raw
APIs instead:

```rust
use core::ptr::NonNull;

fn round_trip(value: Box<u32>) -> Box<u32> {
    let ptr: NonNull<u32> = Box::into_non_null(value);

    // ... hand ptr through an API that preserves the allocation ownership ...

    // SAFETY: ptr came from Box::into_non_null, still denotes that same live
    // allocation, and no other owner will free it.
    unsafe { Box::from_non_null(ptr) }
}
```

Use `Box::leak` only when intentionally giving up automatic destruction for
the required lifetime. The same “do not leak and later un-leak” guidance
applies to other standard-library leak helpers.

## Key Points

- `addr()` gets the address without exposing provenance.
- `with_addr()` and `map_addr()` preserve the provenance of the source pointer.
- `ptr as usize` is equivalent to `expose_provenance()`; it is not the same operation as `addr()`.
- `addr as *const T` is equivalent to `with_exposed_provenance(addr)`, whose chosen provenance is intentionally not precisely specified.
- Use `without_provenance` for addresses that genuinely have no Rust allocation from which to obtain provenance, such as some MMIO/sentinel-address patterns. Dereferencing still requires the platform and Rust memory-model requirements to permit the access.
- Prefer `&raw const` / `&raw mut` when you need a raw pointer without first creating a reference; Rust 1.99's `raw_borrows_via_references` lint can help find indirect raw borrows.
- Strict Provenance APIs stabilized in Rust 1.84; raw borrow operators stabilized earlier and are the native syntax for raw borrows.

## See Also

- [unsafe-miri-ci](unsafe-miri-ci.md) — use Miri to exercise unsafe invariants
- [unsafe-maybeuninit](unsafe-maybeuninit.md) — uninitialized storage and raw pointers
- [unsafe-safety-comment](unsafe-safety-comment.md) — document unsafe invariants
- [type-repr-transparent](type-repr-transparent.md) — layout/ABI contracts for wrappers
