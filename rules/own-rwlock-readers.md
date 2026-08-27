# own-rwlock-readers

> Use the right `RwLock<T>` when reads significantly outnumber writes

## Why It Matters

`Mutex<T>` allows only one thread or task to access data at a time, even for reads. `RwLock<T>` allows multiple concurrent readers OR one exclusive writer. For read-heavy workloads, this can improve throughput by eliminating unnecessary serialization of read operations.

Pick the lock based on context:

- `std::sync::RwLock` or `parking_lot::RwLock` for synchronous code
- `tokio::sync::RwLock` for async code

## Bad

<!-- rust-check: fragment; reason=anti-pattern fragment uses surrounding shared state and data types -->
```rust
use std::sync::{Arc, Mutex};

// Configuration rarely changes but is read constantly
let config = Arc::new(Mutex::new(Config::load()));

// Every read blocks other reads unnecessarily
fn get_setting(config: &Mutex<Config>, key: &str) -> String {
    let guard = config.lock().unwrap();
    guard.get(key).to_string()
}

// 100 threads reading = serialized, one at a time
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use std::sync::{Arc, RwLock};

// Multiple readers can proceed concurrently
let config = Arc::new(RwLock::new(Config::load()));

fn get_setting(config: &RwLock<Config>, key: &str) -> String {
    let guard = config.read().unwrap(); // Multiple threads can hold read lock
    guard.get(key).to_string()
}

fn update_setting(config: &RwLock<Config>, key: &str, value: &str) {
    let mut guard = config.write().unwrap(); // Exclusive access for writes
    guard.set(key, value);
}

// 100 threads reading = parallel execution
```

## Async code needs tokio::sync::RwLock

```rust
use std::sync::Arc;
use tokio::sync::RwLock;

struct Config {
    enabled: bool,
}

async fn is_enabled(config: Arc<RwLock<Config>>) -> bool {
    config.read().await.enabled
}

async fn set_enabled(config: Arc<RwLock<Config>>, enabled: bool) {
    config.write().await.enabled = enabled;
}
```

Do not default to `std::sync::RwLock` or `parking_lot::RwLock` in async code unless the lock usage is strictly synchronous and never crosses `.await`.

## parking_lot::RwLock for synchronous code

For synchronous code, `parking_lot::RwLock` is often a good performance-oriented choice:

```rust
use parking_lot::RwLock;
use std::sync::Arc;

let data = Arc::new(RwLock::new(HashMap::new()));

// Read - no unwrap needed
let value = data.read().get("key").cloned();

// Write
data.write().insert("key".to_string(), "value".to_string());

// Upgradeable read lock (unique to parking_lot)
let upgradeable = data.upgradable_read();
if upgradeable.get("key").is_none() {
    let mut write = parking_lot::RwLockUpgradableReadGuard::upgrade(upgradeable);
    write.insert("key".to_string(), "default".to_string());
}
```

## When RwLock Hurts

RwLock has overhead for tracking readers. It can be slower than Mutex when:

| Scenario | Better Choice |
|----------|---------------|
| Writes are frequent (>20% of operations) | `Mutex` |
| Lock held very briefly | `Mutex` |
| Single-threaded | `RefCell` |
| Reads dominate, lock held longer | `RwLock` |

## Write Starvation

Standard `RwLock` may starve writers if readers are continuous. `parking_lot::RwLock` is fair by default.

```rust
// parking_lot is writer-fair, preventing starvation
use parking_lot::RwLock;
```

## RwLockWriteGuard::downgrade (1.92) — Write Then Read Atomically

A long-standing API gap: atomically downgrade a write lock to a read lock without releasing the lock. This eliminates the race window between unlocking write and acquiring read:

```rust
use std::sync::RwLock;

let lock = RwLock::new(vec![1, 2, 3]);

// Before 1.92: must release write lock, then acquire read lock
// Between release and acquire, another thread can write!
{
    let mut wg = lock.write().unwrap();
    wg.push(4);
    // wg dropped here — write lock released
}
// ⚠️ Race window: another thread could write before we read
let rg = lock.read().unwrap();
println!("len = {}", rg.len());

// 1.92+: atomically downgrade write → read
{
    let mut wg = lock.write().unwrap();
    wg.push(4);
    // Downgrade to read without releasing the lock
    let rg = RwLockWriteGuard::downgrade(wg);
    // Lock is still held as read — no other thread can write
    println!("len = {}", rg.len());
} // Read guard dropped here
```

This is especially valuable in concurrent data structures where you need to modify then immediately observe the result atomically.

## Real-World Pattern: Cached Computation

```rust
use parking_lot::RwLock;
use std::sync::Arc;

struct CachedData {
    cache: RwLock<Option<ExpensiveResult>>,
}

impl CachedData {
    fn get(&self) -> ExpensiveResult {
        // Fast path: read lock
        if let Some(cached) = self.cache.read().as_ref() {
            return cached.clone();
        }
        
        // Slow path: compute and cache
        let result = compute_expensive();
        *self.cache.write() = Some(result.clone());
        result
    }
}
```

## See Also

- [own-mutex-interior](./own-mutex-interior.md) - When writes are frequent
- [async-no-lock-await](./async-no-lock-await.md) - RwLock in async contexts
