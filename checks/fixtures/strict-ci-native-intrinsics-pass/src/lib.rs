#![feature(portable_simd)]

use core::simd::Simd;
#[cfg(target_arch = "x86_64")]
use core::arch::x86_64::{__m128i, _mm_sha256rnds2_epu32};
#[cfg(target_arch = "aarch64")]
use core::arch::aarch64::vaeseq_u8;
#[cfg(any())]
use core::arch::x86_64::{_mm256_sha512rnds2_epi64, _tile_dpbssd, __cpuid};
#[cfg(any())]
use core::arch::wasm32::{memory_size, memory_grow};

pub fn portable(a: Simd<u32, 4>, b: Simd<u32, 4>) -> Simd<u32, 4> {
    a + b
}
