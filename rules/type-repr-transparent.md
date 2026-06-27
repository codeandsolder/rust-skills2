# type-repr-transparent

> Always add `#[repr(transparent)]` to single-field newtypes

**Rule**: `type-repr-transparent`

## Why It Matters

`#[repr(transparent)]` guarantees a newtype has the same memory layout as its inner type. This is essential for FFI where you need type safety in Rust but must match C ABI layouts. Beyond FFI, you should always add `#[repr(transparent)]` to every single-field newtype — it is a zero-cost annotation that provides a guaranteed layout, enables niche optimization (e.g., with `NonZero`), and allows safe transmutation. Without it, the compiler may add padding or change layout at any time across versions, optimization levels, or targets.

## Bad

```rust
// No layout guarantee — might not match inner type
struct Handle(u64);

// Passing to C code — unspecified behavior
extern "C" {
    fn process_handle(h: Handle);  // Layout may not match u64
}

// Wrapping C type without layout guarantee
struct SafePointer(*mut c_void);

// Pure Rust newtype — works by accident, unspecified
struct Meters(f64);

// "It works anyway" — relying on unspecified behavior
// that can change with compiler version or optimization level.
```

## Good

```rust
// Guaranteed same layout as inner type
#[repr(transparent)]
struct Handle(u64);

// Safe for FFI
extern "C" {
    fn process_handle(h: Handle);  // Same layout as u64
}

// FFI pointer wrapper
#[repr(transparent)]
struct SafePointer(*mut c_void);

// Pure Rust — always add it for guaranteed layout
#[repr(transparent)]
struct Meters(f64);
```

## What `#[repr(transparent)]` Guarantees

```rust
use std::mem::{size_of, align_of};

#[repr(transparent)]
struct Meters(f64);

// Same size
assert_eq!(size_of::<Meters>(), size_of::<f64>());

// Same alignment
assert_eq!(align_of::<Meters>(), align_of::<f64>());

// Same ABI — can pass where f64 expected
extern "C" fn measure(distance: Meters) { ... }
```

## With `PhantomData`

```rust
use std::marker::PhantomData;

// PhantomData is zero-sized, doesn't affect layout
#[repr(transparent)]
struct TypedHandle<T> {
    raw: u64,
    _marker: PhantomData<T>,
}

// Still same layout as u64
assert_eq!(size_of::<TypedHandle<String>>(), size_of::<u64>());
```

## NonZero Niche Optimization

```rust
use std::num::NonZeroU64;

#[repr(transparent)]
struct NonZeroHandle(NonZeroU64);

// Inherits null-pointer optimization — Option is same size as u64
assert_eq!(size_of::<NonZeroHandle>(), size_of::<u64>());
assert_eq!(size_of::<Option<NonZeroHandle>>(), size_of::<u64>());

// Without repr(transparent), this optimization may not apply
// consistently across compiler versions.
```

## FFI Pattern with Edition 2024 `unsafe extern`

```rust
// Edition 2024: extern blocks require `unsafe` keyword; individual
// fn declarations inside must be annotated `safe` or `unsafe`.
mod ffi {
    use std::os::raw::c_int;

    #[repr(transparent)]
    pub struct FileDescriptor(c_int);

    unsafe extern "C" {
        // safe fn: callable from safe code without an unsafe block
        pub safe fn open(path: *const i8, flags: c_int) -> FileDescriptor;
        // unsafe fn: requires an unsafe block at the call site
        pub unsafe fn close(fd: FileDescriptor) -> c_int;
        pub unsafe fn read(fd: FileDescriptor, buf: *mut u8, len: usize) -> isize;
    }
}

// Safe wrapper
pub struct File {
    fd: ffi::FileDescriptor,
}

impl File {
    pub fn open(path: &str) -> std::io::Result<Self> {
        let c_path = std::ffi::CString::new(path)?;
        let fd = unsafe { ffi::open(c_path.as_ptr(), 0) };
        Ok(File { fd })
    }
}

impl Drop for File {
    fn drop(&mut self) {
        unsafe { ffi::close(self.fd); }
    }
}
```

## When to Apply

| Scenario | Apply `#[repr(transparent)]`? |
|----------|-------------------------------|
| Single-field tuple struct | Always |
| Single-field named struct | Always |
| FFI newtype wrappers | Always (required) |
| Type-safe handles | Always |
| NonZero niche optimization | Always |
| Pure Rust newtypes | Always (zero cost, guaranteed layout) |
| Multi-field structs | N/A (only for single-field) |

## See Also

- [Rust Reference: repr(transparent)](https://doc.rust-lang.org/reference/type-layout.html#the-transparent-representation)
- [type-newtype-ids](./type-newtype-ids.md) — Newtype pattern
- [type-newtype-repr-transparent](./type-newtype-repr-transparent.md) — All-newtype `#[repr(transparent)]` guide
- [type-phantom-marker](./type-phantom-marker.md) — `PhantomData` usage
- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — NonZero niche optimization
- [api-newtype-safety](./api-newtype-safety.md) — Type-safe newtypes
