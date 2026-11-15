# proj-cargo-publish-age

> Use Cargo 1.100's native dependency cooldown when new releases need time for review, while keeping lockfile changes intentional

**Rule**: `proj-cargo-publish-age`

## Why It Matters

Rust/Cargo 1.100 stabilizes minimum publish age resolution. Cargo skips versions newer than a configured cooldown *when resolving* dependencies, except versions already present in `Cargo.lock`. This is useful for projects using a review/quarantine window for new releases, and avoids a parallel bespoke resolver.

## Good: Explicit Registry Cooldown

```toml
# .cargo/config.toml (local repo or CI policy; Cargo 1.100+)
[registry]
global-min-publish-age = "3 days"
```

`cargo update` now reports versions held back by the minimum age. Where a specific vetted release must be selected urgently, perform an explicit exact-version update and document that exception; do not globally disable cooldowns just to get one crate.

## Important Boundaries

- The resolver consults the registry's publication timestamps; versions with no `pubtime` in the index are not delayed.
- Existing locked versions are permitted regardless of when they were published, so reusing an old `Cargo.lock` does not re-enforce the policy retroactively.
- `cargo install` does not apply the cooldown to either the installed crate or its dependencies. Pin installation versions independently.
- Cargo's cooldown controls *version selection*, not source trust. Continue dependency review and lockfile auditing.
- Don't unilaterally change the fleet's age window or a third-party library's supported Cargo version.

## See Also

- [proj-workspace-deps](./proj-workspace-deps.md) — resolver features
- [proj-msrv-declare](./proj-msrv-declare.md) — when Cargo configuration raises development MSRV
- [Cargo 1.100 changelog](https://doc.rust-lang.org/cargo/CHANGELOG.html#cargo-1100-2026-11-12)
