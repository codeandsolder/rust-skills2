//! Exact-name exceptions for operations with hardware-specific semantics.
//! Do not add ordinary arithmetic here merely because an ISA implements it.

fn x86_crypto(name: &str) -> bool {
    matches!(
        name,
        "_mm256_sha512msg1_epi64"
            | "_mm256_sha512msg2_epi64"
            | "_mm256_sha512rnds2_epi64"
            | "_mm_sm3msg1_epi32"
            | "_mm_sm3msg2_epi32"
            | "_mm_sm3rnds2_epi32"
            | "_mm_sm4key4_epi32"
            | "_mm_sm4rnds4_epi32"
            | "_mm256_sm4key4_epi32"
            | "_mm256_sm4rnds4_epi32"
            | "_mm_loadiwkey"
            | "_mm_encodekey128_u32"
            | "_mm_encodekey256_u32"
            | "_mm_aesenc128kl_u8"
            | "_mm_aesdec128kl_u8"
            | "_mm_aesenc256kl_u8"
            | "_mm_aesdec256kl_u8"
            | "_mm_aesencwide128kl_u8"
            | "_mm_aesdecwide128kl_u8"
            | "_mm_aesencwide256kl_u8"
            | "_mm_aesdecwide256kl_u8"
    )
}

fn arm_crypto(name: &str) -> bool {
    matches!(
        name,
        "vsm3partw1q_u32"
            | "vsm3partw2q_u32"
            | "vsm3ss1q_u32"
            | "vsm3tt1aq_u32"
            | "vsm3tt1bq_u32"
            | "vsm3tt2aq_u32"
            | "vsm3tt2bq_u32"
            | "vsm4ekeyq_u32"
            | "vsm4eq_u32"
    )
}

fn riscv_crypto(name: &str) -> bool {
    matches!(
        name,
        "aes32esi"
            | "aes32esmi"
            | "aes32dsi"
            | "aes32dsmi"
            | "aes64es"
            | "aes64esm"
            | "aes64ds"
            | "aes64dsm"
            | "aes64ks1i"
            | "aes64ks2"
            | "aes64im"
            | "sm4ed"
            | "sm4ks"
    )
}

fn x86_system(name: &str) -> bool {
    matches!(
        name,
        "CpuidResult"
            | "__cpuid_count"
            | "__cpuid"
            | "__get_cpuid_max"
            | "_rdtsc"
            | "__rdtscp"
            | "_rdrand16_step"
            | "_rdrand32_step"
            | "_rdrand64_step"
            | "_rdseed16_step"
            | "_rdseed32_step"
            | "_rdseed64_step"
            | "_mm_clflush"
            | "_mm_clflushopt"
            | "_mm_sfence"
            | "_mm_lfence"
            | "_fxsave"
            | "_fxrstor"
            | "_fxsave64"
            | "_fxrstor64"
            | "_xsave"
            | "_xrstor"
            | "_xsetbv"
            | "_xgetbv"
            | "_xsaveopt"
            | "_xsavec"
            | "_xsaves"
            | "_xrstors"
            | "_xsave64"
            | "_xrstor64"
            | "_xsaveopt64"
            | "_xsavec64"
            | "_xsaves64"
            | "_xrstors64"
            | "_xbegin"
            | "_xend"
            | "_xabort"
            | "_xtest"
            | "_xabort_code"
            | "_XBEGIN_STARTED"
            | "_XABORT_EXPLICIT"
            | "_XABORT_RETRY"
            | "_XABORT_CONFLICT"
            | "_XABORT_CAPACITY"
            | "_XABORT_DEBUG"
            | "_XABORT_NESTED"
            | "__readeflags"
            | "__writeeflags"
    )
}

fn arm_system(name: &str) -> bool {
    matches!(
        name,
        "__rndr"
            | "__rndrrs"
            | "__arm_mte_create_random_tag"
            | "__arm_mte_increment_tag"
            | "__arm_mte_exclude_tag"
            | "__arm_mte_set_tag"
            | "__arm_mte_get_tag"
            | "__arm_mte_ptrdiff"
            | "__wfi"
            | "__wfe"
            | "__sev"
            | "__sevl"
            | "__dmb"
            | "__dsb"
            | "__isb"
            | "SY"
            | "ST"
            | "LD"
            | "ISH"
            | "ISHST"
            | "ISHLD"
            | "NSH"
            | "NSHST"
            | "NSHLD"
            | "OSH"
            | "OSHST"
            | "OSHLD"
    )
}

fn riscv_system(name: &str) -> bool {
    matches!(
        name,
        "wfi"
            | "fence_i"
            | "sfence_vma"
            | "sfence_vma_vaddr"
            | "sfence_vma_asid"
            | "sfence_vma_all"
            | "sinval_vma"
            | "sinval_vma_vaddr"
            | "sinval_vma_asid"
            | "sinval_vma_all"
            | "sfence_w_inval"
            | "sfence_inval_ir"
            | "hlv_b"
            | "hlv_bu"
            | "hlv_h"
            | "hlv_hu"
            | "hlvx_hu"
            | "hlv_w"
            | "hlvx_wu"
            | "hsv_b"
            | "hsv_h"
            | "hsv_w"
            | "hfence_vvma"
            | "hfence_vvma_vaddr"
            | "hfence_vvma_asid"
            | "hfence_vvma_all"
            | "hfence_gvma"
            | "hfence_gvma_gaddr"
            | "hfence_gvma_vmid"
            | "hfence_gvma_all"
            | "hinval_vvma"
            | "hinval_vvma_vaddr"
            | "hinval_vvma_asid"
            | "hinval_vvma_all"
            | "hinval_gvma"
            | "hinval_gvma_gaddr"
            | "hinval_gvma_vmid"
            | "hinval_gvma_all"
            | "frrm"
            | "hlv_wu"
            | "hlv_d"
            | "hsv_d"
    )
}

fn loong_system(name: &str) -> bool {
    matches!(
        name,
        "rdtime_d"
            | "rdtimel_w"
            | "rdtimeh_w"
            | "cacop"
            | "csrrd"
            | "csrwr"
            | "csrxchg"
            | "iocsrrd_d"
            | "iocsrwr_d"
            | "iocsrrd_b"
            | "iocsrrd_h"
            | "iocsrrd_w"
            | "iocsrwr_b"
            | "iocsrwr_h"
            | "iocsrwr_w"
            | "lddir"
            | "ldpte"
            | "dbar"
            | "ibar"
            | "movgr2fcsr"
            | "movfcsr2gr"
            | "brk"
            | "cpucfg"
            | "syscall"
    )
}

fn wasm_system(name: &str) -> bool {
    matches!(
        name,
        "memory_size"
            | "memory_grow"
            | "memory_atomic_wait32"
            | "memory_atomic_wait64"
            | "memory_atomic_notify"
            | "unreachable"
    )
}

fn x86_tile(name: &str) -> bool {
    matches!(
        name,
        "_tile_loadconfig"
            | "_tile_storeconfig"
            | "_tile_loadd"
            | "_tile_release"
            | "_tile_stored"
            | "_tile_stream_loadd"
            | "_tile_zero"
            | "_tile_dpbf16ps"
            | "_tile_dpbssd"
            | "_tile_dpbsud"
            | "_tile_dpbusd"
            | "_tile_dpbuud"
            | "_tile_dpfp16ps"
            | "_tile_cmmimfp16ps"
            | "_tile_cmmrlfp16ps"
            | "_tile_dpbf8ps"
            | "_tile_dpbhf8ps"
            | "_tile_dphbf8ps"
            | "_tile_dphf8ps"
            | "_tile_loaddrs"
            | "_tile_stream_loaddrs"
            | "_tile_cvtrowd2ps"
            | "_tile_cvtrowd2psi"
            | "_tile_cvtrowps2phh"
            | "_tile_cvtrowps2phhi"
            | "_tile_cvtrowps2phl"
            | "_tile_cvtrowps2phli"
            | "_tile_cvtrowps2bf16h"
            | "_tile_cvtrowps2bf16hi"
            | "_tile_cvtrowps2bf16l"
            | "_tile_cvtrowps2bf16li"
            | "_tile_movrow"
            | "_tile_movrowi"
    )
}

pub(super) fn allowed(architecture: &str, name: &str) -> bool {
    match architecture {
        "x86" => x86_crypto(name) || x86_system(name),
        "x86_64" => x86_crypto(name) || x86_system(name) || x86_tile(name),
        "arm" | "aarch64" => arm_crypto(name) || arm_system(name),
        "riscv32" | "riscv64" => riscv_crypto(name) || riscv_system(name),
        "loongarch32" | "loongarch64" => loong_system(name),
        "wasm32" => wasm_system(name),
        "powerpc" | "powerpc64" => name == "trap",
        _ => false,
    }
}
