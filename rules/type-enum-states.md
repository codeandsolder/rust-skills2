# type-enum-states

> Use enums for mutually exclusive states

**Rule**: `type-enum-states`

## Why It Matters

When a value can be in exactly one of several states, an enum makes invalid states unrepresentable. The compiler ensures all states are handled. Contrast with boolean flags or optional fields that can represent impossible combinations.

## Bad

```rust
struct Connection {
    is_connected: bool,
    is_authenticated: bool,
    is_disconnected: bool,  // Can all three be true? False?
    socket: Option<TcpStream>,
    credentials: Option<Credentials>,
}

// Possible invalid states:
// - is_connected && is_disconnected (contradiction)
// - is_authenticated && !is_connected (impossible)
// - socket is None but is_connected is true (inconsistent)
```

## Good

```rust
enum ConnectionState {
    Disconnected,
    Connecting { address: SocketAddr },
    Connected { socket: TcpStream },
    Authenticated { socket: TcpStream, session: Session },
    Failed { error: ConnectionError },
}

struct Connection {
    state: ConnectionState,
}

// Impossible states are unrepresentable
// Each state has exactly the data it needs
```

## Pattern Matching Ensures Completeness

```rust
fn handle_connection(conn: &Connection) {
    match &conn.state {
        ConnectionState::Disconnected => println!("Not connected"),
        ConnectionState::Connecting { address } => println!("Connecting to {}", address),
        ConnectionState::Connected { socket } => println!("Connected, not authenticated"),
        ConnectionState::Authenticated { socket, session } => {
            println!("Authenticated as {}", session.user);
        }
        ConnectionState::Failed { error } => println!("Failed: {}", error),
    }
    // Compiler error if any state is missing
}
```

## State Transitions

```rust
impl Connection {
    fn connect(&mut self, addr: SocketAddr) -> Result<(), Error> {
        match &self.state {
            ConnectionState::Disconnected => {
                self.state = ConnectionState::Connecting { address: addr };
                Ok(())
            }
            _ => Err(Error::AlreadyConnected),
        }
    }

    fn authenticate(&mut self, creds: Credentials) -> Result<(), Error> {
        match std::mem::replace(&mut self.state, ConnectionState::Disconnected) {
            ConnectionState::Connected { socket } => {
                let session = perform_auth(&socket, creds)?;
                self.state = ConnectionState::Authenticated { socket, session };
                Ok(())
            }
            other => {
                self.state = other;
                Err(Error::NotConnected)
            }
        }
    }
}
```

## `let_chains` for Peeling Nested States (Edition 2024, Rust 1.85+)

When enums are nested (e.g., `Option<Result<T, E>>` or multi-level enums), `let_chains` eliminates deep nesting:

```rust
// Before let_chains: deeply nested
fn process(response: Option<Result<Data, Error>>) {
    if let Some(result) = response {
        if let Ok(data) = result {
            handle_data(data);
        }
    }
}

// After let_chains (Edition 2024, Rust 1.85+): flat and readable
fn process(response: Option<Result<Data, Error>>) {
    if let Some(Ok(data)) = response {
        handle_data(data);
    }
}

// Multiple let patterns in a chain
if let Some(user) = find_user(id)
    && let Some(address) = user.address
    && let Some(country) = address.country
{
    println!("User is in {}", country);
}
```

## `cfg_select!` for Compile-Time State Selection (Rust 1.95+)

```rust
use core::cfg_select;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Platform {
    Linux,
    MacOs,
    Windows,
    Other,
}

// Select state based on target platform at compile time
const CURRENT_PLATFORM: Platform = cfg_select! {
    target_os = "linux" => Platform::Linux,
    target_os = "macos" => Platform::MacOs,
    target_os = "windows" => Platform::Windows,
    _ => Platform::Other,
};
// CURRENT_PLATFORM is a compile-time constant — dead code
// elimination removes unused platform branches.

fn platform_specific_work() {
    match CURRENT_PLATFORM {
        Platform::Linux => /* linux-specific */,
        Platform::MacOs => /* macOS-specific */,
        Platform::Windows => /* windows-specific */,
        Platform::Other => /* fallback */,
    }
}
```

## Result and Option as State Enums

```rust
// Option<T> is an enum for "might not exist"
// Result<T, E> is an enum for "might have failed"
// Use these instead of nullable/sentinel values

fn find_user(id: u64) -> Option<User> { todo!() }
fn parse_config(s: &str) -> Result<Config, ParseError> { todo!() }
```

## Avoid Boolean Flags

```rust
// Bad: boolean flags can represent impossible combinations
struct Task {
    is_running: bool,
    is_completed: bool,
    is_failed: bool,
    error: Option<Error>,
}

// Good: enum — each state has exactly the data it needs
enum TaskState {
    Pending,
    Running { started_at: Instant },
    Completed { result: Output },
    Failed { error: Error },
}

struct Task {
    state: TaskState,
}
```

## See Also

- [Rust Book: Enums](https://doc.rust-lang.org/book/ch06-00-enums.html)
- [Making Impossible States Impossible](https://geeklaunch.io/blog/make-impossible-states-impossible/)
- [api-typestate](./api-typestate.md) — Type-level state machines
- [api-non-exhaustive](./api-non-exhaustive.md) — Forward-compatible enums
- [type-option-nullable](./type-option-nullable.md) — `Option` for optional values
