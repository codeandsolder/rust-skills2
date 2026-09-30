//! Positive fixture: a specific reasoned allow may preserve an external schema.

#[allow(
    clippy::struct_field_names,
    reason = "field names intentionally mirror the external wire schema"
)]
pub struct WireTuple {
    pub tuple_id: u64,
    pub tuple_local: u64,
    pub tuple_remote: u64,
}
