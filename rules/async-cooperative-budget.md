# async-cooperative-budget

> Bound work per async scheduling turn and batch ready operations when it improves throughput without violating latency or cancellation requirements

## Why It Matters

An await on an immediately ready future need not yield. A hot receive loop or a CPU loop can monopolize an executor worker, even when written in async Rust. Tokio's cooperative scheduling helps for participating operations, but does not automatically preempt arbitrary synchronous code.

## Good: Reuse a Bounded Receive Buffer

<!-- rust-check: run -->
```rust
use std::num::NonZeroUsize;
use tokio::sync::mpsc;

async fn drain(
    mut receiver: mpsc::Receiver<u32>,
    limit: NonZeroUsize,
    mut process: impl FnMut(&[u32]),
) {
    let mut batch = Vec::with_capacity(limit.get());
    loop {
        let count = receiver.recv_many(&mut batch, limit.get()).await;
        if count == 0 {
            break;
        }
        process(&batch);
        batch.clear();
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = tokio::runtime::Builder::new_current_thread().build()?;
    runtime.block_on(async {
        let (sender, receiver) = mpsc::channel(8);
        for value in 0..7 {
            sender.send(value).await?;
        }
        drop(sender);
        let limit = NonZeroUsize::new(3).ok_or("invalid limit")?;
        let mut seen = Vec::new();
        drain(receiver, limit, |batch| {
            assert!(!batch.is_empty() && batch.len() <= limit.get());
            seen.extend_from_slice(batch);
        }).await;
        assert_eq!(seen, (0..7).collect::<Vec<_>>());
        Ok::<_, Box<dyn std::error::Error>>(())
    })
}
```

With a positive limit, `recv_many` returns zero only when the channel is
closed and drained (including outstanding permits). It appends to the
destination; clear or drain the processed batch before reuse. It is
cancellation-safe as a receive operation, but the enclosing drain function
is not automatically cancellation-safe if it owns messages that were
already received. Define whether shutdown drains, persists, retries or
discards such work. The synchronous callback must itself be bounded.

## Cooperative CPU Chunks

<!-- rust-check: run -->
```rust
async fn checksum(chunks: &[&[u8]]) -> u64 {
    let mut sum = 0_u64;
    for chunk in chunks {
        sum = chunk.iter().fold(sum, |acc, &byte| acc.wrapping_add(u64::from(byte)));
        tokio::task::consume_budget().await;
    }
    sum
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = tokio::runtime::Builder::new_current_thread().build()?;
    assert_eq!(runtime.block_on(checksum(&[&[1, 2], &[], &[3]])), 6);
    Ok(())
}
```

This only makes sense if each chunk has bounded, small cost. The budget
operation yields when Tokio's current budget is exhausted, not after a
specified duration. Offload sustained heavy work to a bounded CPU pool.
For third-party futures that do not cooperate, consider Tokio's cooperative
wrapper where appropriate; it cannot interrupt a single long-running poll.

## Measure the Tradeoff

Use representative arrival rates and queue depth, throughput, worker
utilization and tail latency. Increasing batches amortizes polling and
synchronization costs, while increasing worst-case work before other tasks
can run. Avoid arbitrary global batch sizes or yield intervals. Partition
independent state when contention dominates; do not add task/lock boundaries
to a pipeline that does not need them.

## See Also

- [async-mpsc-queue](./async-mpsc-queue.md)
- [async-cancel-safety](./async-cancel-safety.md)
- [async-blocking-detection](./async-blocking-detection.md)
- [async-future-layout](./async-future-layout.md)
- [Tokio cooperative scheduling](https://docs.rs/tokio/latest/tokio/task/coop/index.html)
- [Tokio recv_many](https://docs.rs/tokio/latest/tokio/sync/mpsc/struct.Receiver.html#method.recv_many)
