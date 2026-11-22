# doc-current-contract

> Document current observable behavior, prerequisites, invariants, and non-obvious reasons; keep obsolete implementation history out of authoritative guidance

## Why It Matters

Documentation that narrates a previous implementation can quietly become
wrong after a refactor. Readers need the current contract: what the code
accepts, returns, guarantees, and how to use it. Maintainers also need the
rationale for constraints that are not obvious from the code.

## Good: Describe the Contract at the API

<!-- rust-check: run -->
```rust
/// Returns the number of complete fixed-size frames and the remaining bytes.
/// A zero frame size cannot be represented.
fn frame_counts(bytes: usize, frame_size: std::num::NonZeroUsize) -> (usize, usize) {
    let size = frame_size.get();
    (bytes / size, bytes % size)
}

fn main() -> Result<(), &'static str> {
    let frame_size = std::num::NonZeroUsize::new(8).ok_or("zero frame size")?;
    assert_eq!(frame_counts(19, frame_size), (2, 3));
    assert_eq!(frame_counts(0, frame_size), (0, 0));
    Ok(())
}
```

The documentation specifies observable semantics rather than explaining
which earlier implementation used a loop or why a previous PR was
reverted. A safety proof, unusual numeric assumption or actual platform
restriction belongs near the code that relies on it.

## Maintain a Single Authoritative Account

- Update docs, examples and referenced contracts in the same change as behavior.
- Keep current project architecture, configuration and operational requirements in the canonical documentation. Preserve significant decisions and investigations in separate dated records.
- Avoid inventing a compatibility requirement solely to keep outdated instructions accurate. Remove dead aliases and obsolete advice when no contract requires them.
- Retain meaningful references to specifications, tracking issues or measurements that justify a current decision; do not delete rationale merely because it is old.
- Compile examples and execute important behavioral examples; neither replaces verifying the prose.

## See Also

- [doc-all-public](./doc-all-public.md)
- [doc-examples-section](./doc-examples-section.md)
- [doc-safety-section](./doc-safety-section.md)
- [test-independent-oracle](./test-independent-oracle.md)
