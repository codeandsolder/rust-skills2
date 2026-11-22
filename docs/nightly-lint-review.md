# Nightly lint review — 2026-11-22

Compared installed rustc/Clippy 1.100.0 (0ef1bc3860, 2026-11-09) with
1.102.0-nightly (bdf712ee87, 2026-11-21) on x86_64 Linux. This is a toolchain
delta, not a claim that each lint was first merged on November 21.

Reproduce using `rustup run 1.100.0 clippy-driver -W help` and
`rustup run nightly clippy-driver -W help`; compare individual lint rows
and group membership separately. For rustc use `rustc +1.100.0 -W help`
and `rustc +nightly -W help`. See [Clippy's index](https://clippy.rust-lang.org/master/)
and [rustc lint documentation](https://doc.rust-lang.org/nightly/rustc/lints/listing/).

## Compiler additions

| Lint | Default | Policy |
|---|---|---|
| `let_underscore_drop_guard` | deny | Already fatal; detects immediate guard destruction |
| `no_link_attributes` | deny | Already fatal |
| `unstable_imports` | deny | Already fatal |
| `partial_stack_protector` | warn | Already fatal |
| `unevaluated_default_field_value` | warn | Already fatal |
| `unmarked_unchecked_type_aliases` | allow | Consider individually for type-alias experiments; not a blanket fleet policy |

## Clippy delta

| Lint | Current group | Policy |
|---|---|---|
| `bufreader_stdin` | pedantic | Already enabled |
| `deprecated_attributes_without_since` | pedantic | Already enabled |
| `ifs_as_logical_ops` | pedantic | Already enabled |
| `undocumented_may_panic_call` | pedantic | Already enabled; inspect false positives before making unsuppressible |
| `large_unopt_stack_frames` | suspicious | Already enabled; replaces former allow-level `large_stack_frames` |
| `new_instead_of_clear` | perf | Already enabled |
| `unnecessary_box_pin` | perf | Already enabled |
| `try_from_instead_of_from_str` | style | Already enabled |
| `unnecessary_as_slice` | complexity | Already enabled |
| `deprecated_attributes_without_note` | restriction | Recommended candidate; requires intentional deprecation guidance |
| `must_use_without_reason` | restriction | Recommended candidate for API design; evaluate existing standard/generated patterns before enforcing globally |

The description of `extend_with_drain` also broadens from vectors to collections.

The strict gate denies warnings, correctness, suspicious, perf, style,
complexity, pedantic and nursery. The default relaxed-test mode has a separate
policy. In handwritten production source, correctness/suspicious/perf are
unsuppressible except explicitly documented exceptions. Pedantic/nursery
(including `use_self`) are fatal but permit narrow reasoned expectations.
The two new restriction candidates are deliberately not added automatically:
first probe representative repositories for their semantics and migration
impact. Do not enable the entire restriction group.

For current unstable feature guidance see
[proj-nightly-features](../rules/proj-nightly-features.md).
