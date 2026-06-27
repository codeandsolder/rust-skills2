# mem-slotmap-arena

> Use `SlotMap<K, V>` for stable handles with contiguous storage

**Rule**: `mem-slotmap-arena`

## Why It Matters

When you need to store and reference many objects (ECS, graph nodes, self-referencing structs), `Vec<T>` with indices is fast but indices become stale if elements are removed. `Rc<T>` / `Arc<T>` have pointer overhead and refcount cycles. `SlotMap` (1.1.1, actively maintained) provides the best of both: stable, type-safe handles (generation-counted keys) backed by contiguous storage — O(1) access, O(1) insert, O(1) remove without invalidating existing handles.

## Bad

```rust
// Vec with indices — fast, but removal shifts everything
struct EntitySystem {
    entities: Vec<Entity>,  // Removing an entity invalidates all subsequent indices
}

fn remove_entity(system: &mut EntitySystem, idx: usize) {
    system.entities.swap_remove(idx);  // O(1) but last element moves here
    // Other systems still hold idx → now points to wrong entity!
}

// Rc-based — pointer chasing, no locality
struct Entity {
    components: Vec<Rc<dyn Component>>,
}
// Each Rc traversal is a pointer chase; bad cache behavior
```

## Good

```rust
use slotmap::{SlotMap, Key};

// SlotMap with generation-counted stable keys
let mut world: SlotMap<Key, Entity> = SlotMap::new();

// Insert returns a stable handle
let hero: Key = world.insert(Entity::new("hero"));
let monster: Key = world.insert(Entity::new("monster"));

// Access via handle — O(1), generation-checked
assert_eq!(world[hero].name, "hero");

// Remove without invalidating other handles
world.remove(monster);
assert!(world.contains_key(hero));  // hero handle still valid
assert!(!world.contains_key(monster));
```

## SlotMap Variants

```rust
use slotmap::{
    SlotMap,       // Standard: keys can be reused
    HopSlotMap,    // Iteration faster, removal slightly slower
    DenseSlotMap,  // Contiguous storage, stable keys, fast iteration
};

// HopSlotMap: best iteration performance
let mut hop: HopSlotMap<Key, Entity> = HopSlotMap::new();
let k = hop.insert(Entity::new("fast-iter"));

// DenseSlotMap: contiguous storage, stable keys
let mut dense: DenseSlotMap<Key, Entity> = DenseSlotMap::new();
let k = dense.insert(Entity::new("dense"));
for entity in dense.iter() {  // Cache-friendly iteration
    process(entity);
}
```

## Graph Nodes Example

```rust
use slotmap::{SlotMap, Key};

// Node with edges stored as stable handles
struct Node {
    name: String,
    edges: Vec<Key>,  // Stable handles to other nodes
}

struct Graph {
    nodes: SlotMap<Key, Node>,
}

impl Graph {
    fn add_node(&mut self, name: &str) -> Key {
        self.nodes.insert(Node {
            name: name.into(),
            edges: Vec::new(),
        })
    }
    
    fn add_edge(&mut self, from: Key, to: Key) {
        // Both keys are generation-checked at lookup
        if let Some(node) = self.nodes.get_mut(from) {
            node.edges.push(to);
        }
    }
    
    fn remove_node(&mut self, key: Key) -> bool {
        // Removing a node doesn't invalidate any other key
        self.nodes.remove(key).is_some()
    }
}
```

## Self-Referencing Structs

```rust
use slotmap::{SlotMap, Key};

struct AstNode {
    kind: AstKind,
    parent: Option<Key>,       // Stable handle, not raw pointer
    children: Vec<Key>,        // Stable handles survive moves
}

// Self-referencing with SlotMap keys is safe
// because keys are generation-counted and remain valid
// even when the SlotMap reallocates
```

## SlotMap vs Alternatives

| Feature | `Vec<(usize, T)>` | `SlotMap<K, V>` | `Rc<T>` |
|---------|-------------------|-----------------|---------|
| Access | O(1) | O(1) | O(1) |
| Insert | O(1) | O(1) | O(1) |
| Remove | O(1) swap + stale index | O(1), handles stable | O(1), refcount |
| Handle safety | None (raw usize) | Generation-counted | Type-safe |
| Cache locality | Good (contiguous) | Good (contiguous) | Poor (pointer chase) |
| Memory overhead | 0 bytes per handle | 8 bytes per entry | 16 bytes per Rc |

## When to Use

```rust
// ✅ Good: ECS / entity systems
let mut ecs: SlotMap<Key, Component> = SlotMap::new();

// ✅ Good: Graph / tree with cross-references
struct Tree {
    nodes: SlotMap<Key, TreeNode>,
}

// ✅ Good: Arena with stable handles instead of raw pointers
// (See also mem-arena-allocator.md for bump allocation)

// ✅ Good: Self-referencing types (where &self references would dangle)
struct SelfRef {
    handle_self: Key,  // Points back into parent SlotMap
}

// ❌ Avoid: Simple sequential data (use Vec)
let mut simple: Vec<i32> = vec![1, 2, 3];  // No removal needed

// ❌ Avoid: Hot-path iteration where Key overhead matters
// (but DenseSlotMap minimizes this)
```

## Cargo.toml

```toml
[dependencies]
slotmap = "1.1.1"
```

## See Also

- [mem-arena-allocator](mem-arena-allocator.md) — Bump allocators for batch allocations
- [mem-thinvec](mem-thinvec.md) — `DenseSlotMap` alternative for sparse data
- [mem-box-large-variant](mem-box-large-variant.md) — Boxing large enum variants
