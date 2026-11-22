# obs-instrument-spans

> Use `#[tracing::instrument]` and spans to attach context to async tasks and requests

## Why It Matters

A span groups all events emitted during a logical operation (an HTTP request, a database call, a background job) and attaches structured context to every event within it. Without spans, log lines from concurrent async tasks interleave with no way to correlate them. The `#[tracing::instrument]` attribute creates a span automatically from the function's arguments as fields. There is one critical async pitfall: holding a span *entry guard* (`let _g = span.enter()`) across an `.await` point can leave the span entered while another task runs, even on a single thread, or cross thread boundaries — use `.instrument(span)` on the future instead.

## Bad

```rust
use tracing::{info, span, Level};

// BAD: holding an entry guard across .await corrupts span context
async fn fetch_user(user_id: u64) -> Result<String, String> {
    let span = span!(Level::INFO, "fetch_user", user_id);
    let _guard = span.enter(); // guard held here...

    let result = some_async_db_call(user_id).await; // ...across this await — wrong!
    info!("fetched user");
    result
}

async fn some_async_db_call(_id: u64) -> Result<String, String> {
    Ok("alice".to_string())
}
```

## Good

```rust
use tracing::{info, instrument, Instrument, info_span};

// GOOD: #[instrument] handles async correctly; skip large/sensitive args
#[instrument(skip(db), fields(user.id = user_id))]
async fn fetch_user(user_id: u64, db: &DbPool) -> Result<String, DbError> {
    info!("fetching user from database");
    let user = db.query_user(user_id).await?;
    info!(username = %user.name, "user fetched");
    Ok(user.name)
}

// GOOD: manual span + .instrument() for dynamic fields
async fn process_job(job_id: &str) {
    let span = info_span!("process_job", job.id = job_id);
    async move {
        info!("job started");
        do_work().await;
        info!("job complete");
    }
    .instrument(span)
    .await;
}

async fn do_work() {}

// Placeholder types for the example
struct DbPool;
#[derive(Debug)] struct DbUser { name: String }
#[derive(Debug)] struct DbError;

impl DbPool {
    async fn query_user(&self, _id: u64) -> Result<DbUser, DbError> {
        Ok(DbUser { name: "alice".to_string() })
    }
}
```

## Key Points

- **`#[instrument]`** instruments async functions so the span is entered during polling, not held across suspension.
- Use `skip(arg)` or `skip_all` to exclude large types (e.g., database pools, byte buffers) and sensitive values from auto-captured fields.
- Use `fields(key = value)` inside `#[instrument]` to add or rename fields beyond the auto-captured args.
- For manual spans, always attach with `.instrument(span).await`, never hold a guard across `.await`.
- Spans nest automatically: entering a child span inside a parent records the parent's context in traces, enabling waterfall views in tools like Jaeger or Tempo.

For hot paths, avoid eagerly preparing expensive diagnostic fields; measure with the actual subscriber and event volume. Prefer useful aggregate observations over extraneous per-item spans.

## See Also

- [obs-hotpath-overhead](./obs-hotpath-overhead.md)

- [obs-structured-fields](obs-structured-fields.md) - structured fields within span events
- [obs-no-sensitive-data](obs-no-sensitive-data.md) - use `skip` to prevent secrets leaking into spans
- [async-no-lock-await](async-no-lock-await.md) - same problem pattern: do not hold guards across `.await`
