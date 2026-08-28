# macro-proc-error-spans

> Turn expected proc-macro input errors into spanned compile errors instead of panics

## Why It Matters

Invalid user input to a procedural macro is an ordinary compile-time error, not an internal crash. `syn::Error` can carry a source span and produce `compile_error!` tokens, so the diagnostic points at the relevant input. Reserve panics for genuine bugs or violated internal invariants, not for supported input validation.

A useful architecture separates a `proc_macro2::TokenStream` expansion helper from the compiler-only proc-macro entry point. The helper can return `syn::Result<_>` and can be unit-tested in an ordinary Rust context.

## Bad

```rust
use proc_macro2::TokenStream;
use quote::quote;
use syn::{Data, DeriveInput};

fn expand(input: TokenStream) -> TokenStream {
    let input: DeriveInput = syn::parse2(input).unwrap();
    let fields = match input.data {
        Data::Struct(data) => data.fields,
        _ => panic!("MyTrait only supports structs"),
    };
    let first = fields.iter().next().unwrap();
    let name = first.ident.as_ref().unwrap();
    quote! { const FIRST_FIELD: &str = stringify!(#name); }
}

fn main() {}
```

Every expected validation failure becomes a panic with poorer user-facing context.

## Good

```rust
use proc_macro2::TokenStream;
use quote::quote;
use syn::{Data, DeriveInput, Error, Fields};

fn expand(input: TokenStream) -> syn::Result<TokenStream> {
    let input: DeriveInput = syn::parse2(input)?;

    let fields = match &input.data {
        Data::Struct(data) => &data.fields,
        _ => {
            return Err(Error::new_spanned(
                &input.ident,
                "MyTrait can only be derived for structs",
            ));
        }
    };

    let named = match fields {
        Fields::Named(named) => named,
        _ => {
            return Err(Error::new_spanned(
                fields,
                "MyTrait requires named fields",
            ));
        }
    };

    let first = named.named.first().ok_or_else(|| {
        Error::new_spanned(&input.ident, "MyTrait requires at least one field")
    })?;
    let field = first.ident.as_ref().expect("Fields::Named has identifiers");
    let ty = &input.ident;

    Ok(quote! {
        impl MyTrait for #ty {
            fn first_field_name() -> &'static str {
                stringify!(#field)
            }
        }
    })
}

fn main() {
    let input = quote! { struct Demo { value: u8 } };
    assert!(expand(input).is_ok());
}
```

The remaining `expect` is an internal invariant supplied by `syn::Fields::Named`, not validation of user input.

## Proc-Macro Entry Point

The actual `#[proc_macro_derive]` item must live in a crate whose Cargo target is `proc-macro = true`, so it is verified in the dedicated proc-macro workspace rather than the ordinary example harness:

<!-- rust-check: fixture(proc-macro-contracts) -->
```rust
use proc_macro::TokenStream;

#[proc_macro_derive(MyTrait)]
pub fn derive_my_trait(input: TokenStream) -> TokenStream {
    match expand(input.into()) {
        Ok(tokens) => tokens.into(),
        Err(error) => error.into_compile_error().into(),
    }
}
```

Keeping parsing/validation in `expand` avoids using `parse_macro_input!` inside a `Result`-returning helper. `parse_macro_input!` is designed for a proc-macro entry point that itself returns `proc_macro::TokenStream`; for a reusable `proc_macro2` helper, `syn::parse2` fits directly with `syn::Result`.

## Choosing the Span

Use `Error::new_spanned(value, message)` when you have a syntax-tree node or tokens representing the offending input. Use `Error::new(span, message)` when you already have the precise span. Point at the smallest useful input that tells the caller what to change.

When validation can discover independent problems in one pass, `syn::Error::combine` can aggregate them before converting to compile-error tokens. Returning the first error is also reasonable when later validation depends on earlier invariants.

## See Also

- [macro-proc-syn-quote](./macro-proc-syn-quote.md) - parsing with syn and generating with quote
- [err-thiserror-lib](./err-thiserror-lib.md) - runtime library error types
