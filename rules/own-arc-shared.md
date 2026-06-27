# own-arc-shared

> Use `Arc<T>` for thread-safe shared ownership

## Why It Matters

`Arc` (Atomic Reference Counted) provides shared ownership across threads. Unlike `Rc`, its reference count is updated atomically, making it safe for concurrent access. Use it when multiple threads need to read the same data.

## Bad

```rust
use std::rc::Rc;
use std::thread;

let data = Rc::new(vec![1, 2, 3]);
let data_clone = Rc::clone(&data);

// ERROR: Rc cannot be sent between threads safely
thread::spawn(move || {
    println!("{:?}", data_clone);
});
```

## Good

```rust
use std::sync::Arc;
use std::thread;

let data = Arc::new(vec![1, 2, 3]);
let data_clone = Arc::clone(&data);

thread::spawn(move || {
    println!("{:?}", data_clone);  // Safe!
});

println!("{:?}", data);  // Original still accessible
```

## Arc with Mutex for Mutable Shared State

```rust
use std::sync::{Arc, Mutex};
use std::thread;

let counter = Arc::new(Mutex::new(0));
let mut handles = vec![];

for _ in 0..10 {
    let counter = Arc::clone(&counter);
    let handle = thread::spawn(move || {
        let mut num = counter.lock().unwrap();
        *num += 1;
    });
    handles.push(handle);
}

for handle in handles {
    handle.join().unwrap();
}

println!("Result: {}", *counter.lock().unwrap());
```

## Arc vs Rc Decision Tree

```
Need shared ownership?
├── No → Use owned value or references
└── Yes → Will it cross thread boundaries?
    ├── No → Use Rc<T> (cheaper, no atomic ops)
    └── Yes → Use Arc<T>
        └── Need mutation?
            ├── No → Arc<T> is enough
            └── Yes → Arc<Mutex<T>> or Arc<RwLock<T>>
```

## Common Patterns

```rust
use std::sync::Arc;

// Shared configuration (read-only)
struct AppConfig {
    database_url: String,
    max_connections: u32,
}

fn setup_workers(config: Arc<AppConfig>) {
    for i in 0..4 {
        let config = Arc::clone(&config);
        std::thread::spawn(move || {
            println!("Worker {} using db: {}", i, config.database_url);
        });
    }
}

// Shared cache with interior mutability
use std::sync::RwLock;
use std::collections::HashMap;

type Cache = Arc<RwLock<HashMap<String, String>>>;

fn get_cached(cache: &Cache, key: &str) -> Option<String> {
    cache.read().unwrap().get(key).cloned()
}

fn set_cached(cache: &Cache, key: String, value: String) {
    cache.write().unwrap().insert(key, value);
}
```

## Recent Additions

### `Arc::new_zeroed` / `Arc::new_zeroed_slice` (1.92)

Allocate an `Arc` with zeroed memory, avoiding the cost of initializing then overwriting:

```rust
use std::sync::Arc;

// Before 1.92: allocate, zero, then initialize
let mut buf = Arc::new([0u8; 4096]);
Arc::get_mut(&mut buf).unwrap().copy_from_slice(&data);

// 1.92+: allocate already-zeroed
let buf = unsafe { Arc::new_zeroed::<[u8; 4096]>() };
let mut buf = unsafe { buf.assume_init() };
buf.copy_from_slice(&data);

// Zeroed slice variant
let slice = unsafe { Arc::new_zeroed_slice::<u8>(4096) };
```

### `Pin<Arc<T>>` Default (1.91)

```rust
use std::pin::Pin;
use std::sync::Arc;

// 1.91+: Pin<Arc<T>> implements Default when T: Default
fn spawn_task() -> Pin<Arc<MyActor>> {
    Default::default()  // Creates Pin<Arc<MyActor>>::default()
}
```

### `LazyLock<Arc<T>>` Global Singleton Pattern

```rust
use std::sync::{Arc, LazyLock};

static GLOBAL_CONFIG: LazyLock<Arc<AppConfig>> = LazyLock::new(|| {
    Arc::new(AppConfig::load())
});

// First access initializes; subsequent accesses are fast Arc clones
fn get_config() -> Arc<AppConfig> {
    GLOBAL_CONFIG.clone()
}
```

### Atomic Pointer Operations on Arc (1.91)

`Arc` supports atomic pointer operations through `core::sync::atomic::AtomicPtr`:

```rust
use std::sync::Arc;
use std::sync::atomic::{AtomicPtr, Ordering};

// Atomic swap of managed Arc data (conceptually)
fn atomic_replace(data: &AtomicPtr<MyData>, new: Arc<MyData>) -> Arc<MyData> {
    let ptr = Arc::into_raw(new) as *mut MyData;
    let old = data.swap(ptr, Ordering::AcqRel);
    unsafe { Arc::from_raw(old) }
}
```

## Performance Considerations

```rust
// Arc::clone is cheap - just increments atomic counter
let a = Arc::new(large_data);
let b = Arc::clone(&a);  // Fast! No data copied

// But atomic operations have overhead vs Rc
// Use Rc in single-threaded contexts for better performance

// Avoid cloning Arc in hot loops if possible
// Bad:
for item in items {
    let arc = Arc::clone(&shared);  // Atomic op each iteration
    process(arc, item);
}

// Better: Clone once outside loop if possible
let arc = Arc::clone(&shared);
for item in items {
    process(&arc, item);  // Pass reference
}
```

## See Also

- [own-rc-single-thread](own-rc-single-thread.md) - Use Rc for single-threaded sharing
- [own-mutex-interior](own-mutex-interior.md) - Use Mutex for interior mutability
- [async-clone-before-await](async-clone-before-await.md) - Clone Arc before await points
