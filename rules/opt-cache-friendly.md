# opt-cache-friendly

> Shape data around measured access patterns and working sets; do not assume one layout is universally cache-friendly

## Why It Matters

Modern processors have several levels of cache, but exact cache sizes, line sizes, miss costs, prefetch behavior, and memory latency are hardware- and workload-dependent. The useful rule is therefore about **locality**: keep data that is consumed together near each other, avoid touching cold data in hot loops, and measure the actual workload before redesigning a representation.

Do not bake universal numbers such as “an L3 miss is 100 cycles” or “a cache line is always 64 bytes” into general Rust guidance. Those are common values on some machines, not language guarantees.

## AoS and SoA Are Workload Choices

An array of structs is often good when most fields of each object are used together:

```rust
#[derive(Clone, Copy)]
struct Particle {
    position: [f32; 3],
    velocity: [f32; 3],
    mass: f32,
}

fn integrate(particles: &mut [Particle], dt: f32) {
    for particle in particles {
        for axis in 0..3 {
            particle.position[axis] += particle.velocity[axis] * dt;
        }
    }
}

fn main() {
    let mut particles = [Particle {
        position: [0.0; 3],
        velocity: [1.0, 0.0, 0.0],
        mass: 1.0,
    }];
    integrate(&mut particles, 0.5);
    assert_eq!(particles[0].position[0], 0.5);
}
```

A struct of arrays can be better when hot loops touch only a subset of fields across many objects:

```rust
struct Particles {
    positions: Vec<f32>,
    velocities: Vec<f32>,
    masses: Vec<f32>,
}

impl Particles {
    fn integrate_x(&mut self, dt: f32) {
        for (position, velocity) in self.positions.iter_mut().zip(&self.velocities) {
            *position += *velocity * dt;
        }
    }
}

fn main() {
    let mut particles = Particles {
        positions: vec![0.0, 10.0],
        velocities: vec![2.0, -1.0],
        masses: vec![1.0, 50.0],
    };
    particles.integrate_x(0.5);
    assert_eq!(particles.positions, [1.0, 9.5]);
    assert_eq!(particles.masses[1], 50.0);
}
```

Neither layout is categorically better. SoA can improve locality and vectorization for field-wise passes, while AoS can reduce indirection and simplify code when fields are consumed together.

## Split Hot and Cold State When It Helps

If a tight loop repeatedly touches a small portion of a large record, separating rarely used state can reduce the hot working set:

```rust
struct EntityHot {
    position: [f32; 2],
    velocity: [f32; 2],
}

struct EntityCold {
    name: String,
    notes: String,
}

struct World {
    hot: Vec<EntityHot>,
    cold: Vec<EntityCold>,
}

fn step(world: &mut World, dt: f32) {
    for entity in &mut world.hot {
        entity.position[0] += entity.velocity[0] * dt;
        entity.position[1] += entity.velocity[1] * dt;
    }
}

fn main() {
    let mut world = World {
        hot: vec![EntityHot {
            position: [0.0, 0.0],
            velocity: [1.0, 2.0],
        }],
        cold: vec![EntityCold {
            name: "demo".into(),
            notes: "rarely read".into(),
        }],
    };
    step(&mut world, 1.0);
    assert_eq!(world.hot[0].position, [1.0, 2.0]);
    assert_eq!(world.cold[0].name, "demo");
}
```

This adds representation complexity and may require keeping parallel collections synchronized. Use it when profiling shows the working-set reduction matters.

## Contiguous Storage Often Helps, but Pointer Chasing Is Not Automatically a Miss

Heap-linked structures tend to have weaker spatial locality than contiguous vectors, but an individual pointer dereference is not synonymous with a cache miss.

```rust
struct Node {
    value: i32,
    next: Option<Box<Node>>,
}

fn sum_linked(mut node: Option<&Node>) -> i32 {
    let mut sum = 0;
    while let Some(current) = node {
        sum += current.value;
        node = current.next.as_deref();
    }
    sum
}

fn sum_contiguous(values: &[i32]) -> i32 {
    values.iter().sum()
}

fn main() {
    let list = Node {
        value: 1,
        next: Some(Box::new(Node {
            value: 2,
            next: None,
        })),
    };
    assert_eq!(sum_linked(Some(&list)), 3);
    assert_eq!(sum_contiguous(&[1, 2]), 3);
}
```

Choose indexed/contiguous representations when they fit the semantics and measurement shows locality matters; linked or boxed structures can still be the right design for stable ownership, sparse mutation, or recursive shape.

## Blocking and Chunk Sizes Must Be Tuned

Cache blocking can improve matrix/image/array kernels, but a constant such as 32 or 64 is not guaranteed to fit the useful cache level on every machine. Prefer a benchmarked block size, a library with architecture-specific kernels, or a parameter that can be tuned.

Likewise, `slice::chunks()` only groups iteration; it does not issue a manual hardware prefetch by itself.

## Alignment and False Sharing

`#[repr(align(N))]` requests a minimum alignment for a Rust type. It can be useful for hardware interfaces or deliberately padded concurrent data, but choosing `N = 64` does not mean Rust has discovered the machine's cache-line size.

```rust
use std::sync::atomic::{AtomicU64, Ordering};

#[repr(align(64))]
struct AlignedCounter(AtomicU64);

fn main() {
    let counter = AlignedCounter(AtomicU64::new(0));
    counter.0.fetch_add(1, Ordering::Relaxed);
    assert_eq!(counter.0.load(Ordering::Relaxed), 1);
}
```

Treat padding/alignment as a target-specific optimization and verify both memory overhead and contention effects.

## Measure the Workload

Useful measurements include end-to-end latency/throughput, CPU profiles, allocation counts, working-set size, and hardware performance counters where available. On Linux, `perf stat`/`perf record` can help; cache simulators can be useful too, but neither substitutes for measuring the deployment workload.

## Practical Guidance

- Optimize the fields and traversal order that are actually hot.
- Prefer contiguous storage when it matches the ownership/update model and improves measured locality.
- Consider SoA or hot/cold splitting for field-wise workloads, not as universal replacements for structs.
- Do not infer cache misses from source-level pointer dereferences.
- Do not hard-code cache sizes, line sizes, or cycle costs as portable facts.
- Benchmark block sizes, padding, and layout changes on representative hardware and data.

## See Also

- [mem-smaller-integers](./mem-smaller-integers.md) - Reducing representation size when the range permits it
- [mem-box-large-variant](./mem-box-large-variant.md) - Enum size and boxing trade-offs
- [perf-profile-first](./perf-profile-first.md) - Measure before optimizing
