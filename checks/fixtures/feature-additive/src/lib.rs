#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(not(feature = "std"))]
extern crate alloc;

#[cfg(feature = "std")]
pub type Buffer<T> = std::vec::Vec<T>;

#[cfg(not(feature = "std"))]
pub type Buffer<T> = alloc::vec::Vec<T>;

pub fn empty_buffer<T>() -> Buffer<T> {
    Buffer::new()
}
