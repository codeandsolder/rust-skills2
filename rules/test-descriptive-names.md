# test-descriptive-names

> Use descriptive test names that explain what is being tested

## Why It Matters

Test names appear in test output and serve as documentation. A good test name tells you what behavior is being verified without reading the test body. When a test fails, a descriptive name immediately tells you what broke.

## Bad

```rust
#[test]
fn test1() { ... }

#[test]
fn test_parse() { ... }  // Parse what? What behavior?

#[test]
fn it_works() { ... }

#[test]
fn test_function() { ... }

// Failure output: "test test_parse ... FAILED"
// What failed? No idea.
```

## Good

<!-- rust-check: fragment; reason=extraction artifact: wrapper/context -->
```rust
#[test]
fn parse_returns_error_for_empty_input() { ... }

#[test]
fn parse_handles_unicode_characters() { ... }

#[test]
fn user_creation_requires_valid_email() { ... }

#[test]
fn expired_token_is_rejected() { ... }

// Failure output: "test parse_returns_error_for_empty_input ... FAILED"
// Immediately know what broke!
```

## Naming Patterns

```rust
// Pattern: function_condition_expected_result
#[test]
fn parse_valid_json_returns_document() { ... }

#[test]
fn parse_invalid_json_returns_syntax_error() { ... }

// Pattern: scenario_expectation
#[test]
fn empty_cart_has_zero_total() { ... }

#[test]
fn adding_item_increases_cart_total() { ... }

// Pattern: when_given_then (BDD-style)
#[test]
fn when_user_not_found_then_returns_404() { ... }
```

## Edge Cases

```rust
#[test]
fn handles_empty_string() { ... }

#[test]
fn handles_max_length_input() { ... }

#[test]
fn handles_unicode_emoji() { ... }

#[test]
fn handles_null_bytes() { ... }

#[test]
fn handles_concurrent_access() { ... }
```

## Error Cases

```rust
#[test]
fn rejects_negative_quantity() { ... }

#[test]
fn returns_error_for_invalid_email_format() { ... }

#[test]
fn panics_on_double_initialization() { ... }

#[test]
fn timeout_returns_timeout_error() { ... }
```

## Module Organization

```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    mod parsing {
        use super::*;
        
        #[test]
        fn accepts_valid_json() { ... }
        
        #[test]
        fn rejects_trailing_comma() { ... }
    }
    
    mod validation {
        use super::*;
        
        #[test]
        fn requires_name_field() { ... }
        
        #[test]
        fn email_must_contain_at_symbol() { ... }
    }
}

// Test output:
// tests::parsing::accepts_valid_json
// tests::parsing::rejects_trailing_comma
// tests::validation::requires_name_field
```

## rstest Named Cases

```rust
use rstest::*;

// Named cases appear in test output as case names
#[rstest]
#[case::empty_string_trim("", true)]
#[case::whitespace("   ", true)]
#[case::valid_string("hello", false)]
fn test_is_blank(#[case] input: &str, #[case] expected: bool) {
    assert_eq!(input.trim().is_empty(), expected);
}

// Output:
// test_is_blank::empty_string_trim
// test_is_blank::whitespace
// test_is_blank::valid_string

// With complex parameters
#[rstest]
#[case::valid_email("user@example.com", true)]
#[case::missing_at("userexample.com", false)]
#[case::empty_local("@example.com", false)]
fn test_email_validation(#[case] email: &str, #[case] valid: bool) {
    assert_eq!(validate_email(email).is_ok(), valid);
}
```

## See Also

- [test-arrange-act-assert](./test-arrange-act-assert.md) - Test structure
- [test-cfg-test-module](./test-cfg-test-module.md) - Test module organization
- [test-rstest-fixtures](./test-rstest-fixtures.md) - rstest parameterized tests
- [doc-examples-section](./doc-examples-section.md) - Documentation tests
