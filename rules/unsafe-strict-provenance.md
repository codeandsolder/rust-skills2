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

## Key Points

- `addr()` gets the address without exposing provenance.
- `with_addr()` and `map_addr()` preserve the provenance of the source pointer.
- `ptr as usize` is equivalent to `expose_provenance()`; it is not the same operation as `addr()`.
- `addr as *const T` is equivalent to `with_exposed_provenance(addr)`, whose chosen provenance is intentionally not precisely specified.
- Use `without_provenance` for addresses that genuinely have no Rust allocation from which to obtain provenance, such as some MMIO/sentinel-address patterns. Dereferencing still requires the platform and Rust memory-model requirements to permit the access.
- Prefer `&raw const` / `&raw mut` when you need a raw pointer without first creating a reference.
- Strict Provenance APIs stabilized in Rust 1.84; raw borrow operators stabilized earlier and are the native syntax for raw borrows.

## See Also

- [unsafe-miri-ci](unsafe-miri-ci.md) — use Miri to exercise unsafe invariants
- [unsafe-maybeuninit](unsafe-maybeuninit.md) — uninitialized storage and raw pointers
- [unsafe-safety-comment](unsafe-safety-comment.md) — document unsafe invariants
- [type-repr-transparent](type-repr-transparent.md) — layout/ABI contracts for wrappers
