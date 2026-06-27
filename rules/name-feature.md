# name-feature

> Name Cargo features without placeholder words like `abc`, `use-abc`, or `with-abc`

## Why It Matters

Cargo features are conditional compilation flags. Feature names should be descriptive and free of placeholder words (`abc`, `use-`, `with-`) that add noise without conveying meaning. The Cargo convention favors clean, concise feature names that describe what functionality is enabled.

## Bad

```toml
# Bad: placeholder/noise words
[features]
abc = []           # Meaningless
use-json = []      # "use" is noise
with-tls = []      # "with" is noise
enable-metrics = [] # "enable" is noise
support-gzip = []  # "support" is noise
```

## Good

```toml
# Good: descriptive feature names
[features]
json = []          # Clear: enables JSON support
tls = []           # Clear: enables TLS
metrics = []       # Clear: enables metrics
gzip = []          # Clear: enables gzip compression
```

## Feature Name Guidelines

| Do | Don't |
|----|-------|
| `json` | `use-json` |
| `tls` | `with-tls` |
| `metrics` | `enable-metrics` |
| `gzip` | `support-gzip` |
| `serde` | `serde-support` |
| `default` | `default-features` |

## Real Examples

```toml
# From well-known crates (simplified)
[features]
default = ["std"]
std = []
sync = []
format = []

# Default features
default = ["std", "format"]
```

## Feature Dependencies

```toml
[features]
default = ["std"]
std = []
full = ["json", "tls", "metrics", "gzip"]
json = ["serde_json"]
tls = ["native-tls"]
```

## Rationale

Placeholder words like `use-`, `with-`, `enable-`, `support-` are redundant — every feature enables or supports something. The feature name should be the noun that describes what it provides, not the verb describing what it does. This keeps `Cargo.toml` clean and features predictable.

## See Also

- [proj-feature-additive](./proj-feature-additive.md) — Design Cargo features to be strictly additive
- [name-types-camel](./name-types-camel.md) — UpperCamelCase naming for types
- [name-word-order](./name-word-order.md) — Verb-object naming for error types

## References

- [Rust API Guidelines: C-FEATURE](https://rust-lang.github.io/api-guidelines/naming.html#c-feature)
- [Cargo Reference: Features](https://doc.rust-lang.org/cargo/reference/features.html)
