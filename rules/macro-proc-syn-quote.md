# macro-proc-syn-quote

> Put proc-macro parsing and generation in testable `syn`/`quote` helpers

## Why It Matters

Procedural macros have two different concerns: a thin compiler-facing entry point using `proc_macro::TokenStream`, and ordinary transformation logic that parses syntax, validates it, and generates tokens. Keeping most logic in helpers built around `syn`, `quote`, and `proc-macro2` makes the transformation easier to read and lets normal unit tests exercise it outside a proc-macro invocation.

Use only the `syn` features required by the syntax you parse. A derive macro usually needs `DeriveInput`; `full` is useful only when you genuinely parse the wider Rust grammar.

## Bad

```rust
use proc_macro2::{TokenStream, TokenTree};

fn find_type_name(input: TokenStream) -> String {
    // Positional token walking quickly becomes wrong around attributes,
    // visibility, generics, where clauses, and other valid Rust syntax.
    input.into_iter()
        .find_map(|token| match token {
            TokenTree::Ident(ident) => Some(ident.to_string()),
            _ => None,
        })
        .expect("type name")
}

fn main() {}
```

## Good

```rust
use proc_macro2::TokenStream;
use quote::quote;
use syn::DeriveInput;

fn generate_hello_impl(input: &DeriveInput) -> TokenStream {
    let name = &input.ident;
    let (impl_generics, ty_generics, where_clause) = input.generics.split_for_impl();

    quote! {
        impl #impl_generics Hello for #name #ty_generics #where_clause {
            fn hello(&self) -> &'static str {
                stringify!(#name)
            }
        }
    }
}

fn expand(input: TokenStream) -> syn::Result<TokenStream> {
    let input: DeriveInput = syn::parse2(input)?;
    Ok(generate_hello_impl(&input))
}

fn main() {
    let input: DeriveInput = syn::parse_quote! { struct Widget<T>(T); };
    let tokens = generate_hello_impl(&input).to_string();
    assert!(tokens.contains("Hello for Widget"));

    assert!(expand(quote! { struct Plain; }).is_ok());
}
```

`quote!` preserves token structure and lets syntax-tree values be interpolated directly. `proc_macro2::TokenStream` is usable in ordinary library/test code, which is the key reason to keep the transformation helper independent of the compiler-only entry point.

## Cargo Setup

A derive crate typically has a dedicated proc-macro target and dependencies along these lines:

```toml
[lib]
proc-macro = true

[dependencies]
proc-macro2 = "1"
quote = "1"
syn = { version = "2", features = ["derive"] }
```

Choose `syn` features from the APIs the macro actually uses rather than copying `full` by default.

## Thin Proc-Macro Entry Point

The entry point itself requires a `proc-macro` crate target, so it is verified in the dedicated proc-macro workspace rather than wrapped as an ordinary binary example:

<!-- rust-check: fixture(proc-macro-contracts) -->
```rust
use proc_macro::TokenStream;

#[proc_macro_derive(Hello)]
pub fn derive_hello(input: TokenStream) -> TokenStream {
    match expand(input.into()) {
        Ok(tokens) => tokens.into(),
        Err(error) => error.into_compile_error().into(),
    }
}
```

The useful unit-test surface is `expand`/`generate_hello_impl`, not the compiler entry point.

## Spans and Generated Diagnostics

Use `quote_spanned!` when generated code should deliberately inherit a particular source span. Do not attach every generated token to one arbitrary span: default `quote!` interpolation often provides better, more natural provenance.

<!-- rust-check: compile -->
```rust
use proc_macro2::TokenStream;
use quote::quote_spanned;
use syn::{spanned::Spanned, Field};

fn access_named_field(field: &Field) -> syn::Result<TokenStream> {
    let name = field.ident.as_ref().ok_or_else(|| {
        syn::Error::new_spanned(field, "expected a named field")
    })?;
    let span = field.span();

    Ok(quote_spanned! { span => self.#name })
}

fn main() {}
```

This helper uses only `proc_macro2`, `syn`, and `quote`; it does not require a `proc-macro = true` crate target and is compile-checked as ordinary Rust.

For errors detected by the macro itself, prefer `syn::Error` with an appropriate input span; see the dedicated error-span rule.

## See Also

- [macro-proc-two-crate](./macro-proc-two-crate.md) - separating proc-macro and facade crates
- [macro-proc-error-spans](./macro-proc-error-spans.md) - reporting input errors with spans
