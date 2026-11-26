//! Require portable SIMD for operations that do not need a native instruction.
use crate::mask_noncode;
mod exceptions;
use regex::Regex;
use std::{collections::BTreeSet, sync::LazyLock};

static TOKEN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?:(?:r#)?(?:\p{XID_Start}|_)\p{XID_Continue}*|::|[^\s])")
        .unwrap_or_else(|error| unreachable!("invalid static token pattern: {error}"))
});

struct Token<'a> {
    text: &'a str,
    offset: usize,
}

fn allowed_x86(name: &str) -> bool {
    matches!(
        name,
        // Native register types are needed at the boundary of the approved operations.
        "__m128i" | "__m256i" | "__m512i"
        // SHA compression/schedule instructions.
        | "_mm_sha1msg1_epu32" | "_mm_sha1msg2_epu32" | "_mm_sha1nexte_epu32"
        | "_mm_sha1rnds4_epu32" | "_mm_sha256msg1_epu32" | "_mm_sha256msg2_epu32"
        | "_mm_sha256rnds2_epu32"
        // AES rounds and key scheduling (including VAES).
        | "_mm_aesenc_si128" | "_mm_aesenclast_si128" | "_mm_aesdec_si128"
        | "_mm_aesdeclast_si128" | "_mm_aesimc_si128" | "_mm_aeskeygenassist_si128"
        | "_mm256_aesenc_epi128" | "_mm256_aesenclast_epi128"
        | "_mm256_aesdec_epi128" | "_mm256_aesdeclast_epi128"
        | "_mm512_aesenc_epi128" | "_mm512_aesenclast_epi128"
        | "_mm512_aesdec_epi128" | "_mm512_aesdeclast_epi128"
        // Dedicated CRC update instructions have no corresponding portable SIMD operation.
        | "_mm_crc32_u8" | "_mm_crc32_u16" | "_mm_crc32_u32" | "_mm_crc32_u64"
    )
}

fn allowed_arm(name: &str) -> bool {
    matches!(
        name,
        "uint8x16_t"
            | "uint32x4_t"
            | "uint64x2_t"
            | "vsha1cq_u32"
            | "vsha1mq_u32"
            | "vsha1pq_u32"
            | "vsha1su0q_u32"
            | "vsha1su1q_u32"
            | "vsha256hq_u32"
            | "vsha256h2q_u32"
            | "vsha256su0q_u32"
            | "vsha256su1q_u32"
            | "vsha512hq_u64"
            | "vsha512h2q_u64"
            | "vsha512su0q_u64"
            | "vsha512su1q_u64"
            | "vaeseq_u8"
            | "vaesdq_u8"
            | "vaesmcq_u8"
            | "vaesimcq_u8"
            | "__crc32b"
            | "__crc32h"
            | "__crc32w"
            | "__crc32d"
            | "__crc32cb"
            | "__crc32ch"
            | "__crc32cw"
            | "__crc32cd"
    )
}

fn allowed(path: &[&str]) -> bool {
    match path {
        // Architecture detection and assembly macros are not SIMD intrinsics.
        ["arch", name] => {
            matches!(*name, "asm" | "global_asm" | "naked_asm")
                || (name.starts_with("is_") && name.ends_with("_feature_detected"))
        }
        ["arch", architecture @ ("x86" | "x86_64"), name] => {
            allowed_x86(name) || exceptions::allowed(architecture, name)
        }
        ["arch", architecture @ ("arm" | "aarch64"), name] => {
            allowed_arm(name) || exceptions::allowed(architecture, name)
        }
        ["arch", "loongarch64", name] => {
            exceptions::allowed("loongarch64", name)
                || matches!(
                    *name,
                    "crc_w_b_w"
                        | "crc_w_h_w"
                        | "crc_w_w_w"
                        | "crc_w_d_w"
                        | "crcc_w_b_w"
                        | "crcc_w_h_w"
                        | "crcc_w_w_w"
                        | "crcc_w_d_w"
                )
        }
        ["arch", architecture, name] => exceptions::allowed(architecture, name),
        _ => false,
    }
}

fn token<'a>(tokens: &[Token<'a>], at: usize) -> &'a str {
    tokens.get(at).map_or("", |item| item.text)
}

// Follow paths and grouped use trees. Once a non-arch branch is entered,
// it cannot refer to the native std/core namespace, so there is no need to
// descend into it except to advance past the import group.
fn walk<'a>(
    tokens: &[Token<'a>],
    at: &mut usize,
    path: &mut Vec<&'a str>,
    findings: &mut Vec<(usize, String)>,
) {
    if token(tokens, *at) == "{" {
        *at += 1;
        while *at < tokens.len() && token(tokens, *at) != "}" {
            let before = *at;
            walk(tokens, at, path, findings);
            if token(tokens, *at) == "," {
                *at += 1;
            }
            if *at == before {
                break;
            }
        }
        if token(tokens, *at) == "}" {
            *at += 1;
        }
        return;
    }
    let Some(item) = tokens.get(*at) else {
        return;
    };
    if item.text.is_empty() || matches!(item.text, "}" | "," | ";") {
        return;
    }
    path.push(item.text);
    *at += 1;
    if token(tokens, *at) == "::" && token(tokens, *at + 1) != "<" {
        *at += 1;
        walk(tokens, at, path, findings);
    } else {
        if path.first() == Some(&"arch") && !allowed(path) {
            findings.push((item.offset, path.join("::")));
        }
        if token(tokens, *at) == "as" {
            *at = (*at + 2).min(tokens.len());
        }
    }
    path.pop();
}

/// Find disallowed native paths in handwritten Rust, including inactive cfg
/// branches and macro token trees. Broad imports must name their leaves.
pub(crate) fn violations(source: &str) -> Vec<(usize, String)> {
    if !source.contains("arch") {
        return Vec::new();
    }
    let masked = mask_noncode(source);
    let tokens: Vec<_> = TOKEN
        .find_iter(&masked)
        .map(|item| Token {
            text: item.as_str().strip_prefix("r#").unwrap_or(item.as_str()),
            offset: item.start(),
        })
        .collect();
    let mut roots = BTreeSet::from(["core", "std"]);
    // Also recognize explicitly renamed core/std crates, including extern crate.
    for window in tokens.windows(3) {
        if matches!(window[0].text, "core" | "std") && window[1].text == "as" {
            roots.insert(window[2].text);
        }
    }
    let mut findings = Vec::new();
    for (index, item) in tokens.iter().enumerate() {
        if roots.contains(item.text) && token(&tokens, index + 1) == "::" {
            walk(&tokens, &mut (index + 2), &mut Vec::new(), &mut findings);
        }
    }
    findings.sort_unstable();
    findings.dedup();
    findings
        .into_iter()
        .map(|(offset, path)| {
            let line = memchr::memchr_iter(b'\n', &source.as_bytes()[..offset]).count() + 1;
            (line, path)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_native_operations_and_broad_imports() {
        for source in [
            "std::arch::x86_64::_mm_add_ps(a, b);",
            "use core :: arch :: x86_64 :: *;",
            "use std::{simd::Simd, arch::{aarch64::{vaddq_u32 as add, self}}};",
            "pub use core::arch as native;",
            "use core::arch;",
            "extern crate core as c; c::arch::wasm32::i32x4_add(a, b);",
            "use core as c; c::arch::riscv64::some_new_intrinsic();",
            "#[cfg(target_arch = \"x86\")] use ::std::arch::x86::_mm_loadu_si128;",
            "macro_rules! foo { () => { core::arch::x86_64::_mm_mul_ps(a,b) } }",
            "use core::arch::x86_64::{_mm_sha256rnds2_epu32, _mm_shuffle_epi32};",
            "use core::r#arch::x86_64::_mm_add_ps;",
            "core::arch::x86_64::_mm_clmulepi64_si128::<0>(a,b);",
            "use core::arch::x86_64::_mm256_clmulepi64_epi128;",
            "use core::arch::aarch64::vmull_p64;",
            "use core::arch::aarch64::vsha1h_u32;",
            "use core::arch::x86_64::_mm_gf2p8mul_epi8;",
            "use core::arch::x86_64::_pext_u64;",
            "use core::arch::x86_64::_mm256_dpbusd_epi32;",
            "use core::arch::riscv64::sha256sig0;",
            "use core::arch::wasm32::f32_sqrt;",
            "use core::arch::x86_64::_mm_pause;",
            "use core::arch::aarch64::__yield;",
        ] {
            assert!(!violations(source).is_empty(), "{source}");
        }
    }

    #[test]
    fn accepts_portable_and_explicit_hardware_operations() {
        for source in [
            "use core::simd::{Simd, simd_swizzle};",
            "use std::arch::{asm, is_x86_feature_detected};",
            "use core::arch::x86_64::{__m128i, _mm_sha256rnds2_epu32 as sha};",
            "use std::{simd::Simd, arch::aarch64::{vaeseq_u8, __crc32w}};",
            "// core::arch::x86_64::_mm_add_ps\nlet s = r#\"std::arch::wasm32::v128_add\"#;",
            "crate::arch::x86_64::custom();",
            "use core::sync::atomic::Ordering;",
            "use core::arch::loongarch64::{crc_w_b_w, crc_w_d_w};",
            "use safe_arch::mul_i16_low_m128i;",
            "use aes::cipher::BlockEncrypt;",
            "use core::arch::x86_64::{_mm256_sha512rnds2_epi64, _mm_sm3rnds2_epi32, _mm_sm4rnds4_epi32, _mm_loadiwkey};",
            "use core::arch::x86_64::{_tile_loadconfig, _tile_dpbssd, _tile_release};",
            "use core::arch::x86_64::{__cpuid, _rdtsc, _rdseed64_step, _mm_clflush, _xsave64, _xbegin};",
            "use core::arch::aarch64::{vsm4eq_u32, __rndr, __arm_mte_set_tag, __dsb, ISH};",
            "use core::arch::riscv64::{aes64es, sm4ed, fence_i, sfence_vma_all};",
            "use core::arch::loongarch64::{rdtime_d, csrrd, ibar};",
            "use core::arch::wasm32::{memory_grow, memory_atomic_wait32};",
            "let p = a.widening_carryless_mul(b); let q = a.carryless_mul(b);",
        ] {
            assert!(violations(source).is_empty(), "{source}");
        }
    }

    #[test]
    fn reports_leaf_and_line() {
        assert_eq!(
            violations("use std::{\n arch::{x86_64::{\n _mm_add_ps,\n _mm_mul_ps}}};"),
            [
                (3, "arch::x86_64::_mm_add_ps".into()),
                (4, "arch::x86_64::_mm_mul_ps".into())
            ]
        );
    }
}
