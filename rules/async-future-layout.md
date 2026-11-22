# async-future-layout

> Measure hot future state size and retain only the data needed across suspension points; preserve laziness, lifetime, and cancellation semantics

## Why It Matters

An async function builds a future that may contain initial captures and state needed across suspension points. Large buffers, nested futures and duplicated await sites can enlarge that representation, and may increase task allocation, stack moves or cache pressure. Exact layout depends on the compiler and target; do not treat it as a language guarantee.

## Good: Scope Synchronous Work Before Suspension

<!-- rust-check: run -->
```rust
fn prepare(input: u8) -> u32 {
    let buffer = [input; 4096];
    buffer.iter().map(|&byte| u32::from(byte)).sum()
}

async fn compact(input: u8) -> u32 {
    let sum = prepare(input);
    tokio::task::yield_now().await;
    sum
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let future = compact(3);
    println!("future size: {} bytes", std::mem::size_of_val(&future));
    let runtime = tokio::runtime::Builder::new_current_thread().build()?;
    assert_eq!(runtime.block_on(future), 12_288);
    Ok(())
}
```

The synchronous buffer is not logically live across the suspension point.
Measure the actual future size, task allocations, throughput and latency
on the representative target. A fixed layout assertion is appropriate only
if the project really has a size budget on specified targets.

## Reduce State Without Moving Semantics

- Shorten lifetimes by using lexical scopes; retain only values actually needed after an await.
- Factor duplicate suspension sites when each branch can produce the arguments for one common async operation. Do not merge distinct error, cancellation or ordering behavior.
- Pass small owned values or appropriate borrows rather than capturing entire unrelated state. An initial owned argument can occupy the unpolled future even if a field is later dropped.
- Moving setup outside an async function into a synchronous function returning a future makes that setup eager at call time. Confirm that its errors, effects and destruction timing are acceptable.
- Boxing a large nested future can reduce the containing state size at the expense of allocation, indirection and potentially more moves. Do not automatically box on a size warning; measure and consider restructuring first.
- Separate sustained CPU work into a suitable bounded executor. Smaller state does not make CPU work cooperative.

The shared strict gate already enables the pedantic `clippy::large_futures`
lint; its threshold is a diagnostic, not an optimal task-size limit. Inspect
compiler type-size diagnostics when appropriate, and verify on the selected
toolchain rather than assuming an optimization from a compiler proposal is
already implemented.

## See Also

- [async-cooperative-budget](./async-cooperative-budget.md)
- [async-spawn-blocking](./async-spawn-blocking.md)
- [async-cancel-safety](./async-cancel-safety.md)
- [mem-assert-type-size](./mem-assert-type-size.md)
- [Rust async guidance](https://microsoft.github.io/rust-guidelines/guidelines/performance/)
