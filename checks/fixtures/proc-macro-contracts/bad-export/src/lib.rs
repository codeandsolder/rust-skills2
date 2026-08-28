use proc_macro::TokenStream;

#[proc_macro_derive(Greet)]
pub fn derive_greet(_input: TokenStream) -> TokenStream {
    TokenStream::new()
}

pub trait Greet {
    fn greet(&self) -> String;
}
