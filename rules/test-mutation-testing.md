# test-mutation-testing

> Use focused mutation testing to discover semantic test gaps; investigate surviving meaningful mutants instead of maximizing a score

## Why It Matters

Line and branch coverage indicate execution, not whether assertions detect a behavioral change. Mutation testing makes small deliberate source changes and checks whether the tests reject them. Surviving mutations can reveal missing cases, weak assertions or unobserved failures.

## Good: Start with High-Value Logic

With a reviewed and pinned cargo-mutants version installed, target the code under change:

```bash
cargo mutants --file src/parser.rs
```

Choose the workspace/package, feature set, test command and build directory
appropriate to the project. Check the installed tool's help for the exact
options; respect central build-cache and dependency policies. Keep output
in a dedicated test artifact directory, not the repository root.

First establish that the unmodified tests pass. Then examine surviving
mutants, such as a changed boundary comparison, omitted state update or
inverted condition. Reproduce the relevant semantic difference with a
focused test whose expected result is independently justified.

## Interpret Results Carefully

- An equivalent mutation may preserve all observable behavior; do not write a brittle implementation-specific test just to kill it.
- A mutation that fails to compile is not evidence of a good test.
- Timeouts can indicate a real nontermination defect or unstable infrastructure; reproduce before classifying them.
- A survived change in a genuinely irrelevant path may indicate code that should be removed rather than a missing assertion.
- Mutation operators are selective and cannot prove tests catch every bug.

Use small, targeted runs before expensive whole-crate or workspace campaigns.
Re-run impacted tests and normal checks after correcting a genuine gap.
Parallel mutation tools must isolate modified sources and build state,
preserve the managed compiler cache, and bound resource usage. Treat newer
compiler-assisted tools such as mutest-rs as alternatives to evaluate against
the actual nightly, corpus and test needs, not automatic replacements.

## See Also

- [test-independent-oracle](./test-independent-oracle.md)
- [test-coverage-llvm-cov](./test-coverage-llvm-cov.md)
- [cargo-mutants](https://mutants.rs/)
- [mutest-rs](https://github.com/mutest/mutest-rs)
