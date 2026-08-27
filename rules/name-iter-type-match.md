# name-iter-type-match

> Name public iterator types after the methods or functions that produce them

## Why It Matters

Rust's API Guidelines pair iterator-producing method names with predictable iterator type names:

| Producer | Typical public iterator type |
|---|---|
| `iter()` | `Iter` |
| `iter_mut()` | `IterMut` |
| `into_iter()` | `IntoIter` |
| `keys()` | `Keys` |
| `values()` | `Values` |
| `values_mut()` | `ValuesMut` |
| `drain()` | `Drain` |
| `windows()` | `Windows` |

The type usually lives in the collection's module, so `vec::IntoIter`, `hash_map::Keys`, or `slice::Windows` is unambiguous without spelling the collection name again inside the type.

This convention is chiefly for **named public iterator types**. If a method returns `impl Iterator`, there is no public concrete iterator name to match.

## A Complete Custom Collection

```rust
mod bag {
    pub struct Bag<T> {
        items: Vec<T>,
    }

    pub struct Iter<'a, T> {
        inner: std::slice::Iter<'a, T>,
    }

    pub struct IterMut<'a, T> {
        inner: std::slice::IterMut<'a, T>,
    }

    pub struct IntoIter<T> {
        inner: std::vec::IntoIter<T>,
    }

    impl<T> Bag<T> {
        pub fn new(items: Vec<T>) -> Self {
            Self { items }
        }

        pub fn iter(&self) -> Iter<'_, T> {
            Iter { inner: self.items.iter() }
        }

        pub fn iter_mut(&mut self) -> IterMut<'_, T> {
            IterMut { inner: self.items.iter_mut() }
        }
    }

    impl<'a, T> Iterator for Iter<'a, T> {
        type Item = &'a T;

        fn next(&mut self) -> Option<Self::Item> {
            self.inner.next()
        }
    }

    impl<'a, T> Iterator for IterMut<'a, T> {
        type Item = &'a mut T;

        fn next(&mut self) -> Option<Self::Item> {
            self.inner.next()
        }
    }

    impl<T> Iterator for IntoIter<T> {
        type Item = T;

        fn next(&mut self) -> Option<Self::Item> {
            self.inner.next()
        }
    }

    impl<T> IntoIterator for Bag<T> {
        type Item = T;
        type IntoIter = IntoIter<T>;

        fn into_iter(self) -> Self::IntoIter {
            IntoIter { inner: self.items.into_iter() }
        }
    }
}

fn main() {
    let mut bag = bag::Bag::new(vec![1, 2, 3]);
    assert_eq!(bag.iter().copied().sum::<i32>(), 6);
    bag.iter_mut().for_each(|value| *value *= 2);
    assert_eq!(bag.into_iter().collect::<Vec<_>>(), vec![2, 4, 6]);
}
```

The module path supplies the collection context: `bag::Iter`, `bag::IterMut`, `bag::IntoIter`.

## Specialized Producers Match Their Semantic Names

```rust
struct Graph {
    nodes: Vec<u32>,
}

struct Nodes<'a> {
    inner: std::slice::Iter<'a, u32>,
}

impl<'a> Iterator for Nodes<'a> {
    type Item = &'a u32;

    fn next(&mut self) -> Option<Self::Item> {
        self.inner.next()
    }
}

impl Graph {
    fn nodes(&self) -> Nodes<'_> {
        Nodes { inner: self.nodes.iter() }
    }
}

fn main() {
    let graph = Graph { nodes: vec![10, 20] };
    assert_eq!(graph.nodes().copied().collect::<Vec<_>>(), vec![10, 20]);
}
```

A producer called `nodes()` naturally returns `Nodes`; similarly `edges()` → `Edges`, `neighbors()` → `Neighbors`, and so on.

Do not add a lifetime parameter merely to make a type name look iterator-like. A lifetime belongs on the iterator type only when its representation or item type actually needs that borrow.

## `impl Iterator` Changes the Public-Type Question

If callers do not need to name the concrete iterator, returning `impl Iterator` can avoid exposing an iterator wrapper at all:

```rust
struct Graph {
    nodes: Vec<u32>,
}

impl Graph {
    fn nodes(&self) -> impl Iterator<Item = &u32> {
        self.nodes.iter()
    }
}

fn main() {
    let graph = Graph { nodes: vec![1, 2, 3] };
    assert_eq!(graph.nodes().copied().sum::<u32>(), 6);
}
```

Use a named iterator type when it is part of the public API, needs additional methods/traits, or must appear in associated types such as `IntoIterator::IntoIter`.

## Do Not Demonstrate the Convention with Illegal Foreign Inherent Impls

Rust does not permit your crate to add inherent methods to `Vec<T>`, `HashMap<K, V>`, or other foreign types. This kind of pseudo-code is useful only as prose:

```text
Vec::iter      -> slice::Iter
Vec::iter_mut  -> slice::IterMut
Vec::into_iter -> vec::IntoIter
HashMap::keys  -> hash_map::Keys
HashMap::values -> hash_map::Values
```

When examples are marked as Rust, make them legal Rust rather than writing fictitious `impl Vec<T> { ... }` blocks.

## Naming Is About the Producer, Not the Trait Name

Avoid vague names such as `Iterator`, `MyCollectionIterator`, or `I` when the iterator has a clear producer method. The method/type pair conveys more information:

```text
iter()      -> Iter
keys()      -> Keys
neighbors() -> Neighbors
```

A longer name can still be appropriate when the producer itself has a longer semantic name. The guideline is predictability, not an absolute ban on descriptive type names.

## Practical Guidance

- Match named iterator types to their producer names: `iter` → `Iter`, `keys` → `Keys`, and so on.
- Let the module path carry collection context instead of redundantly naming the collection in every iterator type.
- Give custom semantic producers matching types such as `Nodes` or `Neighbors`.
- Use `impl Iterator` when callers do not need the concrete iterator type.
- Add lifetimes/generics only when the iterator representation and item type need them.
- Do not use illegal inherent impls on standard-library types as supposedly compilable examples.

## See Also

- [name-iter-convention](./name-iter-convention.md) - `iter` / `iter_mut` / `IntoIterator`
- [name-iter-method](./name-iter-method.md) - Iterator method names
- [api-common-traits](./api-common-traits.md) - Common trait implementations
