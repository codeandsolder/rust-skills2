//! Fixture proving that a reasoned large-enum expectation remains available.
//!
//! Boxing the large variant here would add allocation and pointer chasing. The
//! strict gate should require an explicit reason, not force a heuristic rewrite.

/// Layout probe with intentionally asymmetric variants.
#[expect(
    clippy::large_enum_variant,
    reason = "fixture verifies measured layout tradeoffs may stay inline"
)]
pub enum LayoutProbe {
    /// Tiny control value.
    Small(u8),

    /// Large inline state whose boxing would change allocation/locality behavior.
    Large([u8; 512]),
}
