# name-iter-convention

> For collection-wide traversal, use the conventional `iter`, `iter_mut`, and `IntoIterator` ownership shapes

## Why It Matters

Rust collections use a predictable trio for ordinary traversal:

- `iter(&self)` borrows the collection and yields borrowed data;
- `iter_mut(&mut self)` mutably borrows it and yields mutable borrowed data where that makes sense;
- `IntoIterator` for the owned collection consumes it and yields owned items.

This convention makes generic and `for`-loop code predictable. It does **not** mean every method that happens to return an iterator should be called `iter_*`; semantic iterators such as `keys()`, `values()`, `lines()`, `windows()`, or `neighbors()` should keep descriptive names.

## A Conventional Collection

```rust
struct MyCollection<T> {
    items: Vec<T>,
}

impl<T> MyCollection<T> {
    fn iter(&self) -> std::slice::Iter<'_, T> {
        self.items.iter()
    }

    fn iter_mut(&mut self) -> std::slice::IterMut<'_, T> {
        self.items.iter_mut()
    }
}

impl<T> IntoIterator for MyCollection<T> {
    type Item = T;
    type IntoIter = std::vec::IntoIter<T>;

    fn into_iter(self) -> Self::IntoIter {
        self.items.into_iter()
    }
}

impl<'a, T> IntoIterator for &'a MyCollection<T> {
    type Item = &'a T;
    type IntoIter = std::slice::Iter<'a, T>;

    fn into_iter(self) -> Self::IntoIter {
        self.items.iter()
    }
}

impl<'a, T> IntoIterator for &'a mut MyCollection<T> {
    type Item = &'a mut T;
    type IntoIter = std::slice::IterMut<'a, T>;

    fn into_iter(self) -> Self::IntoIter {
        self.items.iter_mut()
    }
}

fn main() {
    let mut collection = MyCollection { items: vec![1, 2, 3] };

    assert_eq!(collection.iter().copied().sum::<i32>(), 6);

    for value in &mut collection {
        *value *= 2;
    }

    let owned: Vec<_> = collection.into_iter().collect();
    assert_eq!(owned, vec![2, 4, 6]);
}
```

Implementing `IntoIterator` for owned and reference forms enables the natural `for x in collection`, `for x in &collection`, and `for x in &mut collection` syntax.

## The Item Shape Depends on the Collection

Do not reduce the convention to a universal table saying `iter()` always returns `&T`. For maps, ordinary iteration yields key-value pairs:

```rust
use std::collections::HashMap;

fn main() {
    let mut map = HashMap::from([("a", 1), ("b", 2)]);

    for (key, value) in map.iter() {
        assert!(!key.is_empty());
        assert!(*value > 0);
    }

    for value in map.values_mut() {
        *value += 1;
    }

    let owned: HashMap<_, _> = map.into_iter().collect();
    assert_eq!(owned.len(), 2);
}
```

The convention describes **ownership and traversal role**, while the collection defines its logical item type.

## Specialized Iterators Keep Semantic Names

A collection can expose more focused traversals without forcing `iter_` into every name:

```rust
struct Graph {
    nodes: Vec<u32>,
}

impl Graph {
    fn nodes(&self) -> impl Iterator<Item = &u32> {
        self.nodes.iter()
    }

    fn even_nodes(&self) -> impl Iterator<Item = &u32> {
        self.nodes.iter().filter(|node| **node % 2 == 0)
    }
}

fn main() {
    let graph = Graph { nodes: vec![1, 2, 3, 4] };
    assert_eq!(graph.nodes().count(), 4);
    assert_eq!(graph.even_nodes().copied().collect::<Vec<_>>(), vec![2, 4]);
}
```

Names should describe what the iterator traverses. The API Guidelines explicitly note that an iterator-returning operation such as percent encoding need not be shoehorned into `iter`/`iter_mut`/`into_iter` naming when that would lose semantic clarity.

## `into_iter()` Usually Comes from the Trait

For collection types, prefer implementing `IntoIterator` rather than merely adding an inherent method with the right spelling. The trait is what enables `for` loops and generic `IntoIterator` bounds.

```rust
fn total<I>(values: I) -> i32
where
    I: IntoIterator<Item = i32>,
{
    values.into_iter().sum()
}

fn main() {
    assert_eq!(total(vec![1, 2, 3]), 6);
}
```

An inherent `into_iter` method can exist in unusual APIs, but it does not substitute for the trait when collection interoperability is the goal.

## Standard-Library Shapes

Use real calls rather than pseudo-implementations of foreign standard-library types:

```rust
use std::collections::HashMap;

fn main() {
    let mut values = vec![1, 2, 3];
    assert_eq!(values.iter().copied().sum::<i32>(), 6);
    values.iter_mut().for_each(|value| *value += 1);
    assert_eq!(values.into_iter().collect::<Vec<_>>(), vec![2, 3, 4]);

    let map = HashMap::from([("a", 1)]);
    assert_eq!(map.keys().copied().collect::<Vec<_>>(), vec!["a"]);
    assert_eq!(map.values().copied().collect::<Vec<_>>(), vec![1]);
}
```

## Practical Guidance

- Use `iter` for ordinary shared traversal of a collection.
- Use `iter_mut` for the corresponding mutable traversal when the abstraction supports it.
- Implement `IntoIterator` for consuming traversal and commonly for `&Collection` / `&mut Collection` too.
- Let the collection define the logical item shape; maps and other structures need not yield a single `&T`.
- Give specialized iterator-producing methods semantic names such as `keys`, `values`, `neighbors`, or `lines`.
- Do not demonstrate the convention with illegal inherent implementations on `Vec`, `HashMap`, or other foreign types.

## See Also

- [name-iter-type-match](./name-iter-type-match.md) - Iterator type naming
- [name-iter-method](./name-iter-method.md) - Iterator method names
- [perf-iter-over-index](./perf-iter-over-index.md) - Iterator traversal
