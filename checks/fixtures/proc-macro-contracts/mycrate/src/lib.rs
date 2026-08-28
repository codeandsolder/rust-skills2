pub use mycrate_derive::{Greet, Hello, MyTrait};

pub trait Greet {
    fn greet(&self) -> String;
}

pub trait Hello {
    fn hello(&self) -> &'static str;
}

pub trait MyTrait {
    fn first_field_name() -> &'static str;
}

#[doc(hidden)]
pub mod __private {
    pub fn format_greeting(name: &str) -> String {
        format!("hello, {name}")
    }
}
