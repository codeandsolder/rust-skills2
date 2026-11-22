# proj-rust-native-porting

> Preserve the source program's intended algorithmic and domain contracts while redesigning ownership, failure channels, and architecture for Rust

## Why It Matters

A source-to-source port can be useful as an initial behavioral reference,
but its pointer graph, global state, macros, class hierarchy or error
codes often encode constraints of another implementation language.
Conversely, replacing the algorithm wholesale during translation makes
equivalence failures difficult to diagnose.

## Establish Behavior First

Identify the source revision, external format or mathematical specification,
observable inputs and outputs, supported configurations, and known defects.
Capture representative and adversarial cases. For numerical behavior,
specify the rounding and tolerance requirements, special values, units and
ordering dependencies. Treat undefined behavior or known defects in the
source as issues to resolve deliberately, not fidelity targets.

## Translate Semantics, Not Syntax

- Map owned allocations to owning types, borrowed views to slices or references, and shared ownership to a mechanism justified by actual lifetime relationships.
- Replace pointer-or-status out parameters with typed return values when the Rust boundary can change. Retain a narrow adapter only where the foreign ABI itself is required.
- Represent mutually exclusive states and valid domain values with enums and checked constructors, not transplanted bit flags, null sentinels or unrestricted mutation.
- Replace implicit globals and ambient configuration with explicit state and typed arguments.
- Preserve algorithmic complexity and data layout where they matter, then measure improvements. Do not choose unsafe code or a particular dispatch strategy merely to resemble the source.
- Eliminate speculative abstraction, duplicated translation helpers and wrappers that no downstream contract needs. Break private interfaces when the resulting design is better.

## Prove Equivalence Independently

Compare the actual Rust implementation with a separately maintained reference
implementation and specification cases. A translated copy of the same test
formula can hide shared mistakes. Keep intentional behavior changes recorded,
including the reason and a regression demonstrating the new contract.
For a large corpus, iterate on the failing subset and run the complete
regression corpus when the relevant fix is finished.

Do not use a successful translation of a handful of cases as a reason to
hardcode support for those cases. Seek the general correct algorithm.

## See Also

- [test-independent-oracle](./test-independent-oracle.md)
- [unsafe-ffi-boundary](./unsafe-ffi-boundary.md)
- [anti-over-abstraction](./anti-over-abstraction.md)
- [proj-explicit-configuration](./proj-explicit-configuration.md)
- [opt-simd-portable](./opt-simd-portable.md)
