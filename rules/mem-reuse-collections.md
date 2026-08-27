# mem-reuse-collections

> Reuse collection capacity across repeated temporary workloads when allocation behavior or profiling shows it is worthwhile

## Why It Matters

`Vec::clear`, `String::clear`, and `HashMap::clear` remove their current contents while retaining allocated capacity. In a loop whose temporary working set is repeatedly rebuilt to a similar size, that can avoid allocator churn and make capacity growth happen once instead of over and over.

This is a performance technique, not a universal style rule. `Vec::new()` itself does not allocate, small allocations may be cheap, and retaining the largest capacity ever seen can waste memory. Prefer the clearest ownership shape first, then reuse buffers where the allocation pattern matters.

## Bad: Repeatedly Rebuild a Temporary Destination

```rust
fn positive_squares(batches: &[Vec<i32>]) -> Vec<i32> {
    let mut total = Vec::new();

    for batch in batches {
        let temporary: Vec<i32> = batch
            .iter()
            .copied()
            .filter(|x| *x > 0)
            .map(|x| x * x)
            .collect();

        total.extend(temporary);
    }

    total
}

fn main() {
    let batches = vec![vec![-1, 2, 3], vec![4, -5]];
    assert_eq!(positive_squares(&batches), vec![4, 9, 16]);
}
```

If this loop is hot and batches repeatedly reach similar sizes, each fresh temporary destination must acquire its own backing storage.

## Good: Reuse a Scratch `Vec`

```rust
fn positive_squares(batches: &[Vec<i32>]) -> Vec<i32> {
    let mut total = Vec::new();
    let mut scratch = Vec::new();

    for batch in batches {
        scratch.clear();
        scratch.extend(
            batch
                .iter()
                .copied()
                .filter(|x| *x > 0)
                .map(|x| x * x),
        );

        total.extend_from_slice(&scratch);
    }

    total
}

fn main() {
    let batches = vec![vec![-1, 2, 3], vec![4, -5]];
    assert_eq!(positive_squares(&batches), vec![4, 9, 16]);
}
```

`clear()` drops/removes the current elements and sets the length to zero, but the `Vec` keeps its allocation for the next iteration.

If the scratch values do not need to exist as a separate collection at all, extending `total` directly from the iterator is simpler and may be faster. Reuse is useful when a downstream operation genuinely needs the temporary slice/container.

## Strings: Often Write Directly Into the Final Buffer

Do not introduce a reusable per-line `String` automatically. If the result is one accumulated string, writing directly to it avoids both a temporary allocation and a copy:

```rust
use std::fmt::Write;

fn format_rows(rows: &[(&str, i32)]) -> String {
    let mut output = String::new();

    for (name, value) in rows {
        writeln!(&mut output, "{name}: {value}").unwrap();
    }

    output
}

fn main() {
    assert_eq!(format_rows(&[("a", 1), ("b", 2)]), "a: 1\nb: 2\n");
}
```

A separate reusable line buffer makes sense when another API needs each formatted record independently before it is reused—for example a parser, encoder, or I/O routine with a scratch-buffer interface.

## `clear`, `truncate`, `drain`, and Fresh Allocation

```rust
fn main() {
    let mut values = Vec::with_capacity(16);
    values.extend([1, 2, 3, 4, 5]);
    let capacity = values.capacity();

    values.clear();
    assert!(values.is_empty());
    assert_eq!(values.capacity(), capacity);

    values.extend([10, 20, 30, 40]);
    values.truncate(2);
    assert_eq!(values, [10, 20]);
    assert_eq!(values.capacity(), capacity);

    let drained: Vec<_> = values.drain(..).collect();
    assert_eq!(drained, [10, 20]);
    assert_eq!(values.capacity(), capacity);
}
```

Use `drain` when you need to consume/move out removed elements. Use `truncate` when keeping a prefix. Use `clear` when no element should remain.

Assigning `Vec::new()` or `String::new()` drops the previous allocation; that can be exactly what you want when retaining a large scratch buffer would be undesirable.

## Retained Capacity Can Become a Memory Problem

A reusable buffer tends to remember its high-water mark. One exceptional 100 MiB input can leave a long-lived scratch `Vec` holding that capacity after subsequent inputs shrink back to kilobytes.

Possible responses include:

- keep reuse only while capacity stays below a chosen workload-specific limit;
- replace an oversized scratch buffer with a fresh one;
- call `shrink_to` / `shrink_to_fit` when reclaiming memory is worth the allocator work;
- scope the scratch buffer more narrowly so it is naturally dropped.

Do not call `shrink_to_fit()` every iteration; that defeats the point of capacity reuse.

## HashMap Reuse

```rust
use std::collections::HashMap;

fn count_words(lines: &[&str]) -> Vec<Vec<(String, usize)>> {
    let mut output = Vec::with_capacity(lines.len());
    let mut counts = HashMap::<String, usize>::new();

    for line in lines {
        counts.clear();

        for word in line.split_whitespace() {
            *counts.entry(word.to_owned()).or_insert(0) += 1;
        }

        let mut row: Vec<_> = counts
            .iter()
            .map(|(word, count)| (word.clone(), *count))
            .collect();
        row.sort_unstable();
        output.push(row);
    }

    output
}

fn main() {
    let result = count_words(&["a b a", "b c"]);
    assert_eq!(result[0], vec![("a".into(), 2), ("b".into(), 1)]);
}
```

The map's bucket allocation can be reused across lines, but output that must own each line's result still needs independent storage. Reusing one container does not eliminate allocations required by the program's ownership requirements.

## When Fresh Collections Are Better

Fresh containers are often clearer when:

- each iteration transfers ownership of its collection into a result;
- different iterations run concurrently and need independent mutation;
- working-set sizes vary wildly and high-water capacity retention is costly;
- the loop is cold or profiling shows allocator work is irrelevant;
- the optimizer/library already provides a more direct no-temporary path.

Do not twist APIs around scratch-buffer reuse unless the saved work matters.

## See Also

- [mem-with-capacity](./mem-with-capacity.md) — reserve when size is predictable
- [mem-clone-from](./mem-clone-from.md) — reuse allocations during cloning
- [mem-write-over-format](./mem-write-over-format.md) — write into existing strings/buffers
- [perf-collect-into](./perf-collect-into.md) — iterator collection into an existing destination
