# lint-clippy-nursery-selected

> Keep all nursery lints enabled in shared strict CI; review genuine heuristic exceptions individually and re-check group membership when the toolchain changes

## Why It Matters

Clippy's `nursery` group is explicitly opt-in: these lints are useful but may still have known limitations or evolving diagnostics. Enabling the whole group can create churn as lints change, graduate to another group, or reveal edge cases in a new toolchain.

The shared strict gate deliberately denies the entire group. Correct real issues; use a narrow reasoned expectation for a genuinely suppressible false positive. Review changes when updating the selected nightly.

## Shared Policy

```toml
[lints.clippy]
nursery = { level = "deny", priority = -1 }
```

The reusable strict workflow already sets this level; do not duplicate or
weaken it in a repository's manifest. An independent project outside the
shared policy can select individual lints after review.

On the reviewed 1.102 nightly, the following membership is confirmed
from the compiler inventory.

## What These Lints Target

| Lint | Current group | Typical signal |
|---|---|---|
| `significant_drop_tightening` | nursery | Significant drop types kept alive longer than needed |
| `redundant_clone` | nursery | A clone whose value can be moved instead |
| `use_self` | nursery | Repeating the implementing type where `Self` is clearer |
| `or_fun_call` | nursery | Eager fallback construction where a lazy alternative is preferable |
| `redundant_else` | pedantic | `else` following a branch that always diverges |

Do not rely on this table forever. Clippy group membership is toolchain-versioned policy, not a language guarantee.

## Self-Contained Examples

The code patterns are ordinary Rust; Clippy adds diagnostics when the corresponding lint is enabled.

<!-- rust-check: compile -->
```rust
use std::sync::Mutex;

struct State {
    values: Vec<u32>,
}

fn length_then_work(state: &Mutex<State>) -> Option<usize> {
    let len = {
        let guard = state.lock().ok()?;
        guard.values.len()
    };

    expensive_work();
    Some(len)
}

fn expensive_work() {}

struct Widget {
    value: u32,
}

impl Widget {
    fn new(value: u32) -> Self {
        Self { value }
    }

    fn value(&self) -> u32 {
        self.value
    }
}

fn main() {
    let state = Mutex::new(State { values: vec![1, 2, 3] });
    assert_eq!(length_then_work(&state), Some(3));
    assert_eq!(Widget::new(7).value(), 7);
}
```

For `redundant_clone`, prefer moving an owned value when the original is no longer needed:

<!-- rust-check: compile -->
```rust
fn consume(value: String) -> usize {
    value.len()
}

fn main() {
    let value = String::from("hello");
    let len = consume(value);
    assert_eq!(len, 5);
}
```

For lazy fallback construction, use the API that matches the type and desired laziness rather than memorizing a textual rewrite:

<!-- rust-check: compile -->
```rust
fn make_default() -> String {
    String::from("fallback")
}

fn main() {
    let value: Option<String> = None;
    let selected = value.unwrap_or_else(make_default);
    assert_eq!(selected, "fallback");
}
```

## Policy Guidance

- Prefer `[lints.clippy]` in `Cargo.toml` when the lint policy should apply crate-wide.
- Review a lint's actual diagnostics; nursery lints may document known problems. An expectation must name one specific suppressible lint and include a reason.
- When upgrading Rust, run Clippy and review changed group membership or diagnostics instead of assuming the old policy description is still exact.
- Do not label a lint “nursery” merely because it once lived there.

## See Also

- [lint-pedantic-selective](lint-pedantic-selective.md) - selectively enable pedantic lints
- [lint-warn-perf](lint-warn-perf.md) - performance lint policy
- [anti-lock-across-await](anti-lock-across-await.md) - async lock lifetime guidance
