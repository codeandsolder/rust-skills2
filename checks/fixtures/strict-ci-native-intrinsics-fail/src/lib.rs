// This code is deliberately rejected even though the cfg is disabled.
#[cfg(any())]
use core::{simd::Simd, arch::x86_64::{_mm_add_epi32 as add, *}};
#[cfg(any())]
use std::arch::aarch64::vaddq_u32;
