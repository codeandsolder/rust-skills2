# test-proptest-properties

> Use proptest for property-based testing

## Why It Matters

Property-based testing generates random inputs to verify that properties hold across all possible values, not just hand-picked examples. Proptest finds edge cases you wouldn't think to test manually—empty strings, integer overflows, unicode edge cases.

## Setup

```toml
# Cargo.toml
[dev-dependencies]
proptest = "1.0"
```

## Basic Usage

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_reverse_reverse_is_identity(s in ".*") {
        let reversed: String = s.chars().rev().collect();
        let double_reversed: String = reversed.chars().rev().collect();
        assert_eq!(s, double_reversed);
    }
    
    #[test]
    fn test_sort_is_idempotent(mut v in prop::collection::vec(any::<i32>(), 0..100)) {
        v.sort();
        let sorted = v.clone();
        v.sort();
        assert_eq!(v, sorted);
    }
}
```

## Common Strategies

```rust
use proptest::prelude::*;

proptest! {
    // Any type implementing Arbitrary
    #[test]
    fn test_i32(x in any::<i32>()) { }
    
    // Regex-based string generation
    #[test]
    fn test_email(email in "[a-z]+@[a-z]+\\.[a-z]{2,3}") { }
    
    // Ranges
    #[test]
    fn test_range(x in 0..100i32) { }
    
    // Collections
    #[test]
    fn test_vec(v in prop::collection::vec(any::<i32>(), 0..10)) { }
    
    // Optionals
    #[test]
    fn test_option(opt in prop::option::of(any::<i32>())) { }
}
```

## Custom Strategies

```rust
use proptest::prelude::*;

#[derive(Debug, Clone)]
struct User {
    name: String,
    age: u8,
}

fn user_strategy() -> impl Strategy<Value = User> {
    ("[a-zA-Z]{1,20}", 0..120u8)
        .prop_map(|(name, age)| User { name, age })
}

proptest! {
    #[test]
    fn test_user(user in user_strategy()) {
        assert!(user.age < 150);
        assert!(!user.name.is_empty());
    }
}

// Or derive Arbitrary
use proptest_derive::Arbitrary;

#[derive(Debug, Arbitrary)]
struct Point {
    x: i32,
    y: i32,
}
```

## Properties to Test

| Property | Example |
|----------|---------|
| Roundtrip | `decode(encode(x)) == x` |
| Idempotence | `f(f(x)) == f(x)` |
| Commutativity | `f(a, b) == f(b, a)` |
| Associativity | `f(f(a, b), c) == f(a, f(b, c))` |
| Identity | `f(x, identity) == x` |
| Invariants | `len(push(v, x)) == len(v) + 1` |

## Using assert_matches! (Rust 1.96+)

```rust
use std::assert_matches;

proptest! {
    #[test]
    fn test_parse_result(input in "[a-z0-9]*") {
        let result = parse(&input);
        // Better diagnostics than prop_assert!(matches!(..))
        assert_matches!(result, Ok(_) | Err(ParseError::InvalidSyntax { .. }));
    }

    #[test]
    fn test_response_status(code in any::<u16>()) {
        let response = build_response(code);
        // Clear failure messages during shrinking
        assert_matches!(response.status(), 200..=599);
    }
}
```

## Deriving Arbitrary

```rust
use proptest::prelude::*;
use proptest_derive::Arbitrary;

#[derive(Debug, Arbitrary)]
struct User {
    name: String,
    age: u8,
    email: String,
}

proptest! {
    #[test]
    fn test_user_roundtrip(user: User) {
        let json = serde_json::to_string(&user).unwrap();
        let deserialized: User = serde_json::from_str(&json).unwrap();
        assert_eq!(user.name, deserialized.name);
    }
}
```

## Stateful Testing (proptest-stateful)

```rust
use proptest::prelude::*;
use proptest_stateful::*;

// Define state machine for a stack
#[derive(Default, Clone)]
struct StackModel {
    values: Vec<i32>,
}

#[derive(Clone)]
enum StackOp {
    Push(i32),
    Pop,
}

fn stack_transition(model: &mut StackModel, op: &StackOp) {
    match op {
        StackOp::Push(v) => model.values.push(*v),
        StackOp::Pop => { model.values.pop(); }
    }
}

proptest! {
    #[test]
    fn test_stack_operations(ops in prop::collection::vec(any::<StackOp>(), 0..50)) {
        // proptest-stateful generates random sequences of operations
        // and verifies the implementation matches the model
    }
}
```

## Example: Parser Roundtrip

```rust
proptest! {
    #[test]
    fn parse_roundtrip(config in valid_config_strategy()) {
        let serialized = config.to_string();
        let parsed = Config::parse(&serialized).unwrap();
        assert_eq!(config, parsed);
    }
}
```

## Shrinking

Proptest automatically shrinks failing inputs to minimal cases:

```rust
// If this fails with vec![100, 50, 75, 25, 0]
// Proptest will shrink to vec![1, 0] (minimal failing case)
proptest! {
    #[test]
    fn test_sorted(v in prop::collection::vec(0..1000i32, 1..100)) {
        let sorted = is_sorted(&v);
        // This will fail and shrink
    }
}
```

## Configuration

```rust
proptest! {
    #![proptest_config(ProptestConfig {
        cases: 1000,  // More test cases
        max_shrink_iters: 10000,  // More shrinking
        ..ProptestConfig::default()
    })]
    
    #[test]
    fn extensive_test(x in any::<i32>()) { }
}
```

## See Also

- [test-assert-matches](./test-assert-matches.md) - Pattern-based assertions
- [test-criterion-bench](./test-criterion-bench.md) - Benchmarking
- [test-mockall-mocking](./test-mockall-mocking.md) - Mocking
- [test-arrange-act-assert](./test-arrange-act-assert.md) - Test structure
- [test-fuzzing-minimal](./test-fuzzing-minimal.md) - Fuzz testing alternative
