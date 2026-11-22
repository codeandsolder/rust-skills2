# unsafe-no-mangle-unsafe

> Make symbol identity, ABI and linker-section preconditions explicit when using unsafe attributes; use Edition 2024 attribute syntax

## Why It Matters

`#[unsafe(no_mangle)]`, `#[unsafe(export_name = "...")]` and
`#[unsafe(link_section = "...")]` impose obligations on the item author.
Symbol names can collide across crates, native libraries and dynamically
loaded components. Linkers may reject collisions or resolve them in ways
that bind callers to a different, incompatible definition.

A linker section may impose alignment, memory permissions, retention,
startup, relocation, or platform-specific layout requirements. Simply
moving an object into an arbitrary section is not safe by construction.

## Bad: Bare Unsafe Attributes in Edition 2024

<!-- rust-check: compile_fail; reason=Edition 2024 requires unsafe attribute syntax for no_mangle -->
```rust
#[no_mangle]
pub extern "C" fn example_library_version() -> u32 {
    1
}
```

## Good: Explicit Symbol Contract

```rust
// SAFETY: the owning library reserves this exported symbol and matches
// the declared C ABI and signature in its external header.
#[unsafe(no_mangle)]
pub extern "C" fn example_library_version() -> u32 {
    1
}

// SAFETY: the owning library reserves a distinct export name, and the
// external header declares an equivalent C ABI and return type.
#[unsafe(export_name = "example_library_protocol")]
pub extern "C" fn protocol_version() -> u32 {
    2
}
```

These names and signatures are examples of a deliberate foreign boundary.
In actual code verify that symbol identity and calling convention match
every supported consumer. Do not maintain obsolete aliases just because
an earlier implementation exported them; preserve only real external
contracts.

## Linker Sections

Do not use arbitrary named sections just to move data, and do not
recommend executable pre-main hooks as a generic initialization pattern.
Use a custom section only when the target ABI, loader or linker script
requires it; document the applicable contract and why it is satisfied.
Validate the final binary's section layout, address/alignment, access
permissions, retention and startup behavior for each supported target.

For example, firmware vector tables and immutable memory-mapped metadata
have different section contracts. A section name copied from one target
does not establish the contract on another.

## Migration and Call-Site Safety

| Earlier editions | Edition 2024 |
|---|---|
| `#[no_mangle]` | `#[unsafe(no_mangle)]` |
| `#[export_name = "sym"]` | `#[unsafe(export_name = "sym")]` |
| `#[link_section = ".sec"]` | `#[unsafe(link_section = ".sec")]` |

The bare syntax is rejected in Edition 2024. Cargo's edition migration
can rewrite syntax, but the author must audit each actual obligation.
An unsafe attribute does not automatically make the function unsafe to
call. Conversely, an exported function with caller validity requirements
must still have an unsafe callable contract.

## See Also

- [unsafe-extern-block](./unsafe-extern-block.md)
- [unsafe-ffi-boundary](./unsafe-ffi-boundary.md)
- [proj-explicit-startup](./proj-explicit-startup.md)
- [type-repr-transparent](./type-repr-transparent.md)
- [Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-attributes.html)
