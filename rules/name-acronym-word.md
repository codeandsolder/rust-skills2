# name-acronym-word

> Treat acronyms as words in identifiers: `HttpServer`, not `HTTPServer`

## Why It Matters

When acronyms are written in ALL CAPS within identifiers, word boundaries become unclear: is `HTTPSHandler` "HTTPS Handler" or "HTTP SHandler"? Treating acronyms as words (`HttpsHandler`) maintains clear word boundaries and follows Rust convention. The standard library uses this consistently.

## Bad

```rust
// ALL CAPS acronyms - unclear word boundaries
struct HTTPServer { ... }      // HTTP + Server or H + TTP + Server?
struct TCPIPConnection { ... } // TCP + IP? Or other splits?
struct JSONParser { ... }
struct XMLHTTPRequest { ... }  // Very confusing

fn parseJSON(input: &str) { ... }
fn connectTCP(addr: &str) { ... }
```

## Good

```rust
// Acronyms as words - clear boundaries
struct HttpServer { ... }      // Http + Server
struct TcpIpConnection { ... } // Tcp + Ip + Connection
struct JsonParser { ... }
struct XmlHttpRequest { ... }

fn parse_json(input: &str) { ... }
fn connect_tcp(addr: &str) { ... }

// More examples
struct Uuid { ... }            // Not UUID
struct Uri { ... }             // Not URI
struct Url { ... }             // Not URL
struct Html { ... }            // Not HTML
struct Css { ... }             // Not CSS
struct Api { ... }             // Not API
```

## Standard Library Examples

```rust
// std uses acronyms as words
std::net::TcpStream            // Not TCPStream
std::net::TcpListener          // Not TCPListener
std::net::UdpSocket            // Not UDPSocket
std::net::IpAddr               // Not IPAddr
std::io::IoError               // Not IOError (though Io is acceptable too)
```

## Two-Letter Acronyms

```rust
// Two-letter acronyms: strongly prefer treating as word
struct Io { ... }            // Preferred
struct Id { ... }            // Preferred
struct IoHandler { ... }     // Preferred
struct IdGenerator { ... }   // Preferred

// Against: IO, ID - now considered outdated style
```

## Compound Words

```rust
// Contractions of compound words count as one word
struct Stdin { ... }         // Not StdIn
struct Usize { ... }         // Not USize
struct CString { ... }       // Not CString (c-string, not c string)
struct CStr { ... }          // Not CStr
struct Uuid { ... }          // Not UUID
```

## Clippy Enforcement

Enable `clippy::upper_case_acronyms` (style, since 1.51) to catch all-caps acronyms. For stricter enforcement, enable the aggressive option:

```rust
#![warn(clippy::upper_case_acronyms)]

// Aggressive mode (config): catches more edge cases like HTTP → Http
// In .cargo/config.toml:
// [lints.rust]
// clippy.upper_case_acronyms.upper-case-acronyms-aggressive = true
```

## Anti-Patterns

```rust
// Bad: ALL-CAPS acronyms in identifiers
struct HTTPResponse { ... }   // Should be HttpResponse
struct JSONParser { ... }     // Should be JsonParser
struct TCPConnection { ... }  // Should be TcpConnection
struct XMLDocument { ... }    // Should be XmlDocument

// Good: acronyms as words
struct HttpResponse { ... }
struct JsonParser { ... }
struct TcpConnection { ... }
struct XmlDocument { ... }
```

## In snake_case

```rust
// Acronyms become lowercase in snake_case
fn parse_json() { ... }
fn connect_tcp() { ... }
fn generate_uuid() { ... }
fn fetch_http() { ... }
fn encode_url() { ... }

// Variables
let json_response = fetch_json();
let tcp_connection = connect_tcp();
let user_id = generate_uuid();
```

## Mixed Cases

```rust
// When acronym is part of compound
struct HttpsConnection { ... }   // Https (not HTTPS)
struct Utf8String { ... }        // Utf8 (not UTF8)
struct Base64Encoder { ... }     // Base64 as word

// Multiple acronyms
struct JsonApiClient { ... }     // Json + Api + Client
struct RestApiHandler { ... }    // Rest + Api + Handler
```

## See Also

- [name-types-camel](./name-types-camel.md) - Type naming conventions
- [name-funcs-snake](./name-funcs-snake.md) - Function naming conventions
- [name-consts-screaming](./name-consts-screaming.md) - Constant naming
