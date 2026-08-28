use proc_macro::TokenStream;
use proc_macro2::{Span, TokenStream as TokenStream2};
use proc_macro_crate::{crate_name, FoundCrate};
use quote::quote;
use syn::{Data, DeriveInput, Error, Fields, Ident};

fn facade_path() -> TokenStream2 {
    match crate_name("mycrate").expect("mycrate must be present") {
        FoundCrate::Itself => quote!(crate),
        FoundCrate::Name(name) => {
            let ident = Ident::new(&name, Span::call_site());
            quote!(::#ident)
        }
    }
}

fn generate_hello_impl(input: &DeriveInput) -> TokenStream2 {
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

fn expand_hello(input: TokenStream2) -> syn::Result<TokenStream2> {
    let input: DeriveInput = syn::parse2(input)?;
    Ok(generate_hello_impl(&input))
}

#[proc_macro_derive(Hello)]
pub fn derive_hello(input: TokenStream) -> TokenStream {
    match expand_hello(input.into()) {
        Ok(tokens) => tokens.into(),
        Err(error) => error.into_compile_error().into(),
    }
}

fn expand_my_trait(input: TokenStream2) -> syn::Result<TokenStream2> {
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

#[proc_macro_derive(MyTrait)]
pub fn derive_my_trait(input: TokenStream) -> TokenStream {
    match expand_my_trait(input.into()) {
        Ok(tokens) => tokens.into(),
        Err(error) => error.into_compile_error().into(),
    }
}

#[proc_macro_derive(Greet)]
pub fn derive_greet(input: TokenStream) -> TokenStream {
    let input: DeriveInput = match syn::parse(input) {
        Ok(input) => input,
        Err(error) => return error.into_compile_error().into(),
    };
    let name = &input.ident;
    let facade = facade_path();

    quote! {
        impl #facade::Greet for #name {
            fn greet(&self) -> String {
                #facade::__private::format_greeting(stringify!(#name))
            }
        }
    }
    .into()
}
