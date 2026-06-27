# own-lifetime-elision

> Rely on lifetime elision rules; add explicit lifetimes only when required

## Why It Matters

Rust's lifetime elision rules handle most common borrowing patterns automatically. Adding explicit lifetimes where they're not needed clutters code without adding clarity. However, understanding when elision applies helps you know when explicit lifetimes are truly necessary.

**Edition 2024's RPIT lifetime capture is the single biggest improvement to Rust's lifetime ergonomics since NLL (Non-Lexical Lifetimes).** Many functions that previously required explicit lifetime annotations or clone-for-lifetime workarounds now compile automatically.

## Bad

```rust
// Unnecessary explicit lifetimes - elision handles these
fn first_word<'a>(s: &'a str) -> &'a str {
    s.split_whitespace().next().unwrap_or("")
}

fn get_name<'a>(person: &'a Person) -> &'a str {
    &person.name
}

impl<'a> Display for Wrapper<'a> {
    fn fmt<'b>(&'b self, f: &'b mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}
```

## Good

```rust
// Let elision do its job
fn first_word(s: &str) -> &str {
    s.split_whitespace().next().unwrap_or("")
}

fn get_name(person: &Person) -> &str {
    &person.name
}

impl Display for Wrapper<'_> {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}
```

## The Three Elision Rules

1. **Each input reference gets its own lifetime:**
   ```rust
   fn foo(x: &str, y: &str) 
   // becomes
   fn foo<'a, 'b>(x: &'a str, y: &'b str)
   ```

2. **One input reference → output gets same lifetime:**
   ```rust
   fn foo(x: &str) -> &str
   // becomes  
   fn foo<'a>(x: &'a str) -> &'a str
   ```

3. **Method with `&self`/`&mut self` → output gets self's lifetime:**
   ```rust
   fn foo(&self, x: &str) -> &str
   // becomes
   fn foo<'a, 'b>(&'a self, x: &'b str) -> &'a str
   ```

## When Explicit Lifetimes ARE Required

```rust
// Multiple input references, output could come from either
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}

// Struct holding references
struct Parser<'input> {
    source: &'input str,
    position: usize,
}

// Multiple distinct lifetimes needed
struct Context<'s, 'c> {
    source: &'s str,
    cache: &'c mut Cache,
}

// Static lifetime for constants
fn get_default() -> &'static str {
    "default"
}
```

## Anonymous Lifetime `'_`

Use `'_` to let the compiler infer while being explicit about the presence of a lifetime:

```rust
// In struct definitions
impl Iterator for Parser<'_> {
    type Item = Token;
    fn next(&mut self) -> Option<Self::Item> { ... }
}

// In function signatures where it adds clarity
fn parse(input: &str) -> Result<Ast<'_>, Error> { ... }

// Especially useful in trait bounds
fn process(data: &impl AsRef<str>) -> Cow<'_, str> { ... }
```

## Edition 2024 RPIT Lifetime Capture

In Edition 2024, return-position `impl Trait` (RPIT) automatically captures all in-scope lifetimes. This is transformative for functions that return types containing borrowed data.

### Before (Edition 2021): Explicit lifetime annotations required

```rust
// Must add '_ lifetime to connect return to &self
fn iter(&self) -> impl Iterator<Item = &str> + '_ {
    self.items.iter().map(|s| s.as_str())
}

// Must use 'static bound or clone when lifetimes can't be named
fn get_connection(&self) -> impl Future<Output = Result<()>> + 'static {
    let config = self.config.clone(); // Clone to escape &self lifetime
    async move { connect(config).await }
}
```

### After (Edition 2024): Automatic lifetime capture

```rust
// Lifetimes are automatically captured from &self
fn iter(&self) -> impl Iterator<Item = &str> {
    self.items.iter().map(|s| s.as_str())
}

// No need for 'static + clone workaround
async fn get_connection(&self) -> Result<()> {
    connect(&self.config).await  // &self lifetime auto-captured
}
```

### Impact: Eliminates Clone-for-Lifetime Workarounds

The biggest practical impact is eliminating `clone()` calls that existed solely to satisfy lifetime bounds:

```rust
// Edition 2021: must clone to satisfy 'static bound
struct Processor {
    name: String,
}

impl Processor {
    fn process(&self) -> impl Future<Output = ()> + 'static {
        let name = self.name.clone(); // Clone just for lifetime
        async move { println!("{}", name) }
    }
}

// Edition 2024: borrow naturally, no clone needed
impl Processor {
    async fn process(&self) {
        println!("{}", self.name) // Borrows &self — no clone
    }
}
```

See [own-cow-rpit-edition2024](own-cow-rpit-edition2024.md) for how this interacts with `Cow<'_, T>` return types.

### Common Patterns Transformed by RPIT Capture

```rust
// Edition 2021: explicit lifetime
fn filter(&self, pred: impl Fn(&str) -> bool) -> impl Iterator<Item = &str> + '_ { ... }

// Edition 2024: automatic
fn filter(&self, pred: impl Fn(&str) -> bool) -> impl Iterator<Item = &str> { ... }
```

## Recent Additions

### `mismatched_lifetime_syntaxes` Lint (1.89)

This lint detects confusing lifetime syntax usage:

```rust
// Lint warns: inconsistent use of 'a and '_ in similar positions
fn foo<'a>(x: &'a str) -> &'_ str { x }
// Warning: mismatched_lifetime_syntaxes — mixing explicit and anonymous
```

Resolution: be consistent within a signature.

### Lifetime Normalization for Closures (1.94)

Closure lifetime inference is more precise in Rust 1.94+:

```rust
// Before 1.94: complex closure signatures needed explicit annotations
let result: &str;
let process = |s: &str| -> &str { s.trim() };
result = process("  hello  "); // OK

// 1.94+: closure lifetime normalization handles more patterns
let transform = |x: &i32| -> &i32 { x };
let value = 42;
let r = transform(&value); // Works seamlessly
```

### `'_` in `impl Trait` Positions (Edition 2024)

```rust
// Edition 2024: '_ can be used in impl Trait position
fn make_debug(&self) -> impl Debug + '_ { ... }
// Equivalent to omitting '_ in Edition 2024 (auto-captured)
fn make_debug(&self) -> impl Debug { ... }
```

## Common Patterns

```rust
// ✅ Elision works
fn trim(s: &str) -> &str { s.trim() }
fn first(v: &[i32]) -> Option<&i32> { v.first() }
fn name(&self) -> &str { &self.name }

// ❌ Elision fails - multiple inputs, ambiguous output
fn pick(a: &str, b: &str, first: bool) -> &str // Error!

// ✅ Fixed with explicit lifetime
fn pick<'a>(a: &'a str, b: &'a str, first: bool) -> &'a str {
    if first { a } else { b }
}
```

## See Also

- [own-cow-rpit-edition2024](./own-cow-rpit-edition2024.md) - Edition 2024 RPIT with Cow
- [own-borrow-over-clone](./own-borrow-over-clone.md) - Prefer borrowing to avoid ownership issues
- [own-refcell-interior](./own-refcell-interior.md) - Edition 2024 temporary scope changes
- [api-impl-asref](./api-impl-asref.md) - Generic borrowing with AsRef
