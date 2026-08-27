# type-enum-states

> Use enums when a value is in exactly one of several mutually exclusive states

**Rule**: `type-enum-states`

## Why It Matters

Several booleans or loosely related `Option` fields can encode combinations that the domain says are impossible. An enum gives each state one variant, lets each variant carry only the data valid in that state, and makes pattern matches exhaustiveness-checked.

## Bad: Independent Flags for One State Machine

```rust
#[derive(Debug)]
struct Connection {
    is_connected: bool,
    is_authenticated: bool,
    is_disconnected: bool,
}

fn main() {
    let impossible = Connection {
        is_connected: true,
        is_authenticated: true,
        is_disconnected: true,
    };

    assert!(impossible.is_connected && impossible.is_disconnected);
}
```

The type permits contradictory states, so every consumer has to recover the missing invariant with runtime checks.

## Good: One Variant per State

```rust
#[derive(Debug, PartialEq, Eq)]
enum ConnectionState {
    Disconnected,
    Connecting { address: String },
    Connected,
    Authenticated { user: String },
    Failed { message: String },
}

fn describe(state: &ConnectionState) -> &'static str {
    match state {
        ConnectionState::Disconnected => "disconnected",
        ConnectionState::Connecting { .. } => "connecting",
        ConnectionState::Connected => "connected",
        ConnectionState::Authenticated { .. } => "authenticated",
        ConnectionState::Failed { .. } => "failed",
    }
}

fn main() {
    let state = ConnectionState::Authenticated { user: "alice".into() };
    assert_eq!(describe(&state), "authenticated");
}
```

Adding a new variant makes non-wildcard matches fail to compile until they handle it. That is usually exactly what state-machine code wants.

## Put State-Specific Data in the Variant

```rust
#[derive(Debug)]
enum JobState {
    Queued,
    Running { started_ms: u64 },
    Completed { output: String },
    Failed { error: String },
}

fn output(state: &JobState) -> Option<&str> {
    match state {
        JobState::Completed { output } => Some(output),
        _ => None,
    }
}
```

This is stronger than a `status` enum plus independent optional `started`, `output`, and `error` fields: values that do not belong to a state cannot be present in that variant.

## State Transitions Can Consume the Old State

When a transition logically replaces one state with another, taking `self` can make the transition explicit and avoid a temporary invalid value.

```rust
#[derive(Debug, PartialEq, Eq)]
enum Upload {
    Pending { bytes: Vec<u8> },
    Sent { id: u64 },
}

impl Upload {
    fn send(self, id: u64) -> Self {
        match self {
            Upload::Pending { .. } => Upload::Sent { id },
            sent @ Upload::Sent { .. } => sent,
        }
    }
}

fn main() {
    let upload = Upload::Pending { bytes: vec![1, 2, 3] };
    assert_eq!(upload.send(7), Upload::Sent { id: 7 });
}
```

For in-place state machines, `mem::replace`, `Option::take`, or a dedicated transition API can be appropriate. Choose the ownership shape from the transition semantics rather than forcing every state through mutable flags.

## `let` Chains for Related Pattern Checks (Rust 1.88+, Edition 2024)

Rust 1.88 stabilized `let` chains in the 2024 edition. They are useful when several dependent optional/state checks must all succeed and you also have boolean conditions.

```rust
#[derive(Debug)]
struct Address {
    country: Option<String>,
}

#[derive(Debug)]
struct User {
    address: Option<Address>,
}

fn company_country(user: Option<User>) -> Option<String> {
    if let Some(user) = user
        && let Some(address) = user.address
        && let Some(country) = address.country
        && country.ends_with("land")
    {
        Some(country)
    } else {
        None
    }
}

fn main() {
    let user = User {
        address: Some(Address { country: Some("Finland".into()) }),
    };
    assert_eq!(company_country(Some(user)).as_deref(), Some("Finland"));
}
```

Do not call a single nested pattern such as `if let Some(Ok(value)) = result` a let-chain; that syntax has long been available. A let-chain specifically combines `let` expressions with `&&`.

## `cfg_select!` for Compile-Time Selection (Rust 1.95+)

`cfg_select!` selects the **first** matching `cfg` arm at compile time and does not emit the unselected arms. It can produce items or be used in expression position.

```rust
use core::cfg_select;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Platform {
    Linux,
    MacOs,
    Windows,
    Other,
}

const CURRENT_PLATFORM: Platform = cfg_select! {
    target_os = "linux" => Platform::Linux,
    target_os = "macos" => Platform::MacOs,
    target_os = "windows" => Platform::Windows,
    _ => Platform::Other,
};

fn platform_name() -> &'static str {
    match CURRENT_PLATFORM {
        Platform::Linux => "linux",
        Platform::MacOs => "macos",
        Platform::Windows => "windows",
        Platform::Other => "other",
    }
}

fn main() {
    assert!(!platform_name().is_empty());
}
```

This is compile-time conditional compilation, not a runtime state-machine mechanism. Use an enum at runtime when the state can change while the program is running.

## `Option` and `Result` Are Already State Enums

Do not invent sentinel values when the standard enums already model the state.

```rust
fn find_name(names: &[&str], index: usize) -> Option<String> {
    names.get(index).map(|name| (*name).to_owned())
}

fn parse_port(text: &str) -> Result<u16, std::num::ParseIntError> {
    text.parse()
}
```

## When an Enum Is Not Enough

A runtime enum ensures the value is in one valid state. It does **not** by itself prevent callers from requesting an invalid transition. If transition legality must be encoded in the type system, consider a typestate API; if external callers need forward-compatible matching, consider `#[non_exhaustive]`.

## See Also

- [api-typestate](./api-typestate.md) — type-level state transitions
- [api-non-exhaustive](./api-non-exhaustive.md) — forward-compatible public enums
- [type-option-nullable](./type-option-nullable.md) — optional values
