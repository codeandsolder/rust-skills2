# mem-slotmap-arena

> Use `SlotMap` for generation-checked stable keys; use `DenseSlotMap` when densely stored values and fast iteration are important

**Rule**: `mem-slotmap-arena`

## Why It Matters

When values need long-lived handles across insertion and removal, raw `usize` indices into a `Vec<T>` are easy to misuse. `swap_remove` can make an old index refer to a different value, while shifting removal invalidates later indices.

The `slotmap` crate solves that problem with generation/version-checked keys. Removing one entry invalidates that key while keys to other live entries continue to identify their original values.

Do not describe every slot map as “contiguous storage.” The standard `SlotMap` stores slots and can accumulate holes, so iteration scans empty slots as well as occupied ones. `DenseSlotMap` specifically keeps values in dense contiguous storage and trades an extra level of indirection on keyed lookup for fast iteration.

## Bad: Raw Indices Can Become Stale

```rust
#[derive(Debug, PartialEq, Eq)]
struct Entity(&'static str);

fn main() {
    let mut entities = vec![Entity("hero"), Entity("monster")];
    let monster_index = 1usize;

    entities.swap_remove(0);

    // The old index is now out of bounds; with a different removal pattern an
    // old index can instead refer to the wrong value.
    assert!(entities.get(monster_index).is_none());
}
```

The type system cannot distinguish an index captured before the collection was mutated from a fresh valid index.

## Good: `SlotMap` With a Concrete Key Type

```rust
use slotmap::{DefaultKey, SlotMap};

#[derive(Debug, PartialEq, Eq)]
struct Entity(&'static str);

fn main() {
    let mut world: SlotMap<DefaultKey, Entity> = SlotMap::new();

    let hero = world.insert(Entity("hero"));
    let monster = world.insert(Entity("monster"));

    assert_eq!(world[hero], Entity("hero"));

    assert_eq!(world.remove(monster), Some(Entity("monster")));
    assert!(world.contains_key(hero));
    assert!(!world.contains_key(monster));
}
```

`slotmap::Key` is a **trait**, not the concrete key type to put in `SlotMap<Key, V>`. Use `DefaultKey` for simple cases or define a custom key type.

## Prefer Custom Key Types for Distinct Domains

```rust
use slotmap::{new_key_type, SlotMap};

new_key_type! {
    struct NodeKey;
    struct TextureKey;
}

#[derive(Debug)]
struct Node {
    edges: Vec<NodeKey>,
}

fn main() {
    let mut nodes: SlotMap<NodeKey, Node> = SlotMap::with_key();
    let a = nodes.insert(Node { edges: Vec::new() });
    let b = nodes.insert(Node { edges: Vec::new() });
    nodes[a].edges.push(b);

    let mut textures: SlotMap<TextureKey, &'static str> = SlotMap::with_key();
    let texture = textures.insert("albedo");

    assert_eq!(nodes[a].edges, [b]);
    assert_eq!(textures[texture], "albedo");
    // nodes.get(texture); // does not compile: TextureKey is not NodeKey
}
```

The custom key types prevent accidentally using a handle from one slot map with another slot map whose values happen to have a compatible shape.

## `SlotMap` vs `DenseSlotMap`

Use ordinary `SlotMap` when keyed operations dominate and sparse slots are acceptable:

```rust
use slotmap::{DefaultKey, SlotMap};

fn main() {
    let mut values: SlotMap<DefaultKey, i32> = SlotMap::new();
    let a = values.insert(10);
    let b = values.insert(20);
    values.remove(a);

    assert_eq!(values[b], 20);
}
```

Use `DenseSlotMap` when iterating all live values frequently is important:

```rust
use slotmap::{DefaultKey, DenseSlotMap};

fn main() {
    let mut values: DenseSlotMap<DefaultKey, i32> = DenseSlotMap::new();
    let a = values.insert(10);
    let b = values.insert(20);
    values.remove(a);

    let live: Vec<_> = values.values().copied().collect();
    assert_eq!(live, [20]);
    assert_eq!(values[b], 20);
}
```

`DenseSlotMap` keeps the values densely packed while maintaining stable generation-checked keys through internal indirection. Do not claim the standard `SlotMap` has the same dense-value layout.

## Graphs and Trees

Keys are useful for graph-like relationships because the nodes can move internally without invalidating logical references:

```rust
use slotmap::{new_key_type, SlotMap};

new_key_type! { struct NodeKey; }

#[derive(Debug)]
struct Node {
    name: String,
    edges: Vec<NodeKey>,
}

#[derive(Default)]
struct Graph {
    nodes: SlotMap<NodeKey, Node>,
}

impl Graph {
    fn add_node(&mut self, name: &str) -> NodeKey {
        self.nodes.insert(Node {
            name: name.to_owned(),
            edges: Vec::new(),
        })
    }

    fn add_edge(&mut self, from: NodeKey, to: NodeKey) {
        if self.nodes.contains_key(to) {
            if let Some(node) = self.nodes.get_mut(from) {
                node.edges.push(to);
            }
        }
    }
}

fn main() {
    let mut graph = Graph::default();
    let root = graph.add_node("root");
    let child = graph.add_node("child");
    graph.add_edge(root, child);

    assert_eq!(graph.nodes[root].name, "root");
    assert_eq!(graph.nodes[root].edges, [child]);
}
```

This is safer than storing raw pointers into a growable collection and more robust than naked integer indices across removal.

## Keys Are Handles, Not Rust References

A slot-map key does not create a self-referential Rust struct in the borrow-checker sense. It is an opaque handle used to look the value up later. That distinction is valuable: moving/reallocating the collection does not leave an actual `&T` pointing into old storage.

A key can still become invalid when its entry is removed. Always decide how your domain handles dangling logical edges—ignore them, clean them eagerly, validate on lookup, or maintain secondary structures.

## Performance Tradeoffs

Do not attach fixed byte-overhead or cache-locality tables to all slot-map variants. The representation is crate-version- and target-dependent, and the variants make different tradeoffs:

- standard `SlotMap`: direct slot lookup; iteration scans holes;
- `DenseSlotMap`: dense live values and fast iteration; keyed lookup performs additional indirection;
- secondary maps: associate data with keys from a primary slot map without making the key itself an owning reference.

Use `Vec<T>` when stable handles/removal safety are unnecessary. A slot map pays for handle validation and metadata to provide semantics a plain vector does not.

## When It Fits

Good candidates include:

- entity/scene registries with insertion and removal;
- graph/tree nodes with cross-links;
- resource tables exposed through opaque handles;
- arenas where values need stable logical identities but not stable memory addresses.

Prefer a `Vec`, `VecDeque`, map, slab, arena, or direct ownership when those semantics fit better. “Stable handle” alone does not imply `SlotMap` is automatically the fastest structure.

## Cargo.toml

```toml
[dependencies]
slotmap = "1"
```

Pin a tighter version only when your application's dependency policy calls for it; this rule should not hard-code a patch release as a semantic requirement.

## See Also

- [mem-arena-allocator](./mem-arena-allocator.md) — bump arenas with different lifetime/removal semantics
- [mem-box-large-variant](./mem-box-large-variant.md) — indirection for representation size

## References

- [slotmap crate documentation](https://docs.rs/slotmap/latest/slotmap/)
- [DenseSlotMap](https://docs.rs/slotmap/latest/slotmap/struct.DenseSlotMap.html)
- [new_key_type!](https://docs.rs/slotmap/latest/slotmap/macro.new_key_type.html)
