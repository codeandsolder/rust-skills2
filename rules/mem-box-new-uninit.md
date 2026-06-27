# mem-box-new-uninit

> Use `Box::new_uninit()` for lazy-initialized heap allocations

**Rule**: `mem-box-new-uninit`

## Why It Matters

`Box::new(value)` always writes the entire value, even fields you immediately overwrite. `Box::new_uninit()` (stable since Rust 1.81) allocates the heap space without zeroing or initializing, letting you fill in fields manually. This avoids wasted work when the default value is expensive or when you need partial initialization. Combined with `MaybeUninit`, it enables safe deferred initialization.

## Bad

```rust
use std::mem::MaybeUninit;

struct LargeStruct {
    header: [u8; 64],
    payload: [u8; 4096],
}

// Box::new zeroes the entire allocation, then we overwrite
fn create() -> Box<LargeStruct> {
    let mut val = Box::new(LargeStruct {
        header: [0u8; 64],     // Zeroed
        payload: [0u8; 4096],  // Zeroed — wasted!
    });
    // Immediately overwrite
    fill_header(&mut val.header);
    fill_payload(&mut val.payload);
    val
}
```

## Good

```rust
use std::boxed::Box;
use std::mem::MaybeUninit;

struct LargeStruct {
    header: [u8; 64],
    payload: [u8; 4096],
}

// Box::new_uninit allocates without zeroing
fn create() -> Box<LargeStruct> {
    // Safety: we fully initialize before assume_init
    let mut val = Box::new_uninit();
    
    // Write fields manually
    fill_header(val.header.as_mut_ptr());
    fill_payload(val.payload.as_mut_ptr());
    
    // Safety: both fields are now initialized
    unsafe { val.assume_init() }
}
```

## MaybeUninit Dance (Complete Example)

```rust
use std::boxed::Box;
use std::mem::MaybeUninit;
use std::ptr;

struct Database {
    connection: [u8; 2048],  // Large socket state
    buffer: [u8; 4096],      // Read buffer
}

impl Database {
    fn new() -> Result<Box<Self>, Error> {
        // Allocate without zeroing 6KB
        let mut db: Box<MaybeUninit<Database>> = Box::new_uninit();
        
        // Initialize fields (may fail)
        if let Err(e) = init_connection(db.connection.as_mut_ptr()) {
            // On error, should drop initialized parts (none yet, so no-op)
            // db is dropped — just the allocation is freed
            return Err(e);
        }
        
        ptr::write(db.buffer.as_mut_ptr(), [0u8; 4096]);  // Zero buffer
        
        // Safety: both fields initialized
        Ok(unsafe { db.assume_init() })
    }
}

fn init_connection(ptr: *mut [u8; 2048]) -> Result<(), Error> {
    // Write connection state...
    Ok(())
}
```

## When to Use Box::new_uninit

```rust
// ✅ Good: Large structs where initialization is deferred
//    Saves zeroing 4KB+ of memory per allocation

// ✅ Good: FFI buffers received from C (filled by the callee)
let buf: Box<MaybeUninit<[u8; 4096]>> = Box::new_uninit();
let len = unsafe { libc::read(fd, buf.as_mut_ptr() as *mut _, 4096) };
// Safety: len bytes are initialized
let initialized: Box<[u8]> = unsafe { buf.assume_init() };
// But we also need to truncate — this is simplified

// ❌ Avoid: Small types where zeroing is negligible
let x = Box::new(42u8);  // Fine, just 1 byte

// ❌ Avoid: When default initialization is already optimal
let x = Box::new(String::new());  // String::new() is cheap
```

## Performance Impact

```rust
// 4KB struct:
// Box::new:    ~500ns (zero + copy)
// Box::new_uninit: ~50ns (just malloc, no zero)
// Savings: ~10x on allocation

// But only matters when:
// 1. Struct is large (> 1KB)
// 2. You're immediately overwriting most fields
// 3. Allocation is on a hot path
```

## Safety Notes

`Box::new_uninit()` returns `Box<MaybeUninit<T>>`. You must call `assume_init()` only after all bytes of `T` are initialized. Calling `assume_init()` on partially-initialized data is **undefined behavior**.

For safer patterns, consider:
- `Box::new(Default::default())` if `T: Default` and zeroing is acceptable
- Builder pattern with `Box::new(field1, field2)` then fill remaining
- Separate allocation into heap-allocated fields (smaller `Box` + `Vec`)

## See Also

- [mem-box-large-variant](mem-box-large-variant.md) — Boxing large enum variants
- [mem-arena-allocator](mem-arena-allocator.md) — Arena allocators for batch allocations
- [type-never-diverge](type-never-diverge.md) — `MaybeUninit` for safe patterns
