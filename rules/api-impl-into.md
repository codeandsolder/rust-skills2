# api-impl-into

> Accept `impl Into<T>` for flexible APIs, implement `From<T>` for conversions

## Why It Matters

APIs that accept `impl Into<T>` are ergonomic—callers can pass the target type directly or any type that converts to it. This reduces boilerplate `.into()` calls at call sites. Implement `From<T>` rather than `Into<T>` because `From` implies `Into` through a blanket implementation.

## Bad

```rust
// Requires exact type - forces callers to convert
fn process_path(path: PathBuf) { ... }
fn set_name(name: String) { ... }

// Caller must convert explicitly
process_path(PathBuf::from("/path/to/file"));
process_path("/path/to/file".to_path_buf());  // Verbose
process_path("/path/to/file".into());          // Explicit

set_name(String::from("Alice"));
set_name("Alice".to_string());  // Verbose
```

## Good

```rust
// Accept anything that converts to the target type
fn process_path(path: impl Into<PathBuf>) {
    let path = path.into();  // Convert once inside
    // ...
}

fn set_name(name: impl Into<String>) {
    let name = name.into();
    // ...
}

// Callers are ergonomic
process_path("/path/to/file");    // &str converts automatically
process_path(PathBuf::from(".")); // PathBuf works too

set_name("Alice");                // &str
set_name(String::from("Alice"));  // String
set_name(format!("User-{}", id)); // String from format!
```

## Implement From, Not Into

```rust
struct UserId(u64);

// ✅ Implement From
impl From<u64> for UserId {
    fn from(id: u64) -> Self {
        UserId(id)
    }
}

// Into is automatically provided by blanket impl
let id: UserId = 42u64.into();  // Works!

// ❌ Don't implement Into directly
impl Into<UserId> for u64 {
    fn into(self) -> UserId {
        UserId(self)  // This works but is non-idiomatic
    }
}
```

## Common Conversions

```rust
// String-like types
fn log_message(msg: impl Into<String>) { ... }
log_message("literal");           // &str
log_message(String::from("own")); // String
log_message(Cow::from("cow"));    // Cow<str>

// Path-like types  
fn read_file(path: impl AsRef<Path>) { ... }  // AsRef for borrowed access
fn write_file(path: impl Into<PathBuf>) { ... }  // Into when storing

// Duration
fn set_timeout(duration: impl Into<Duration>) { ... }
set_timeout(Duration::from_secs(5));
// Note: no blanket impl for integers, would need custom wrapper
```

## AsRef vs Into

```rust
// AsRef<T>: borrow as &T, no conversion cost
fn count_bytes(data: impl AsRef<[u8]>) -> usize {
    data.as_ref().len()  // Just borrows, no allocation
}
count_bytes("hello");  // &str -> &[u8]
count_bytes(b"hello"); // &[u8] -> &[u8]
count_bytes(vec![1, 2, 3]);  // &Vec<u8> -> &[u8]

// Into<T>: convert to owned T, may allocate
fn store_data(data: impl Into<Vec<u8>>) {
    let owned: Vec<u8> = data.into();  // Takes ownership
    // ...
}
```

## When NOT to Use impl Into

```rust
// ❌ Trait objects need Sized
fn process(handler: impl Into<Box<dyn Handler>>) { }
// Better: just take Box<dyn Handler> directly

// ❌ Recursive types
struct Node {
    children: Vec<impl Into<Node>>,  // Error: impl Trait not allowed here
}

// ❌ Performance-critical hot paths (minor overhead of trait dispatch)
fn hot_path(value: impl Into<u64>) {
    // Consider taking u64 directly if called billions of times
}

// ❌ When you need to name the type
fn returns_impl() -> impl Into<String> { }  // Opaque, hard to use
```

## Builder Pattern with Into

```rust
struct Config {
    name: String,
    path: PathBuf,
}

impl Config {
    fn new(name: impl Into<String>) -> Self {
        Config {
            name: name.into(),
            path: PathBuf::new(),
        }
    }
    
    fn path(mut self, path: impl Into<PathBuf>) -> Self {
        self.path = path.into();
        self
    }
}

// Clean builder calls
let config = Config::new("myapp")
    .path("/etc/myapp");
```

## Builder Pattern: Into Opt-In

In builder patterns, prefer opt-in `Into` conversions (e.g., `bon`'s `#[builder(into)]`) over implicit ones. This gives callers ergonomic flexibility without hiding the conversion cost:

```rust
use bon::Builder;

#[derive(Builder)]
pub struct Config {
    #[builder(into)]  // Opt-in: callers can pass &str, String, Cow, etc.
    name: String,

    #[builder(default = 8080)]
    port: u16,
}

// Callers get ergonomic conversion
let config = Config::builder()
    .name("my-service")  // &str auto-converts via Into<String>
    .build();
```

Without `#[builder(into)]`, callers must convert explicitly. With it, the conversion is visible in the builder definition and callers benefit from ergonomic usage. This is preferable to using `impl Into<String>` in every setter, which makes the conversion implicit at the call site.

## See Also

- [api-impl-asref](./api-impl-asref.md) - When to use AsRef instead
- [api-from-not-into](./api-from-not-into.md) - Why From is preferred
- [api-bon-builder](./api-bon-builder.md) - bon crate builder with Into support
- [err-from-impl](./err-from-impl.md) - From for error conversion
