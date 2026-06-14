# Rust Skills

218 Rust rules your AI coding agent can use to write better code. Current for Rust 1.96 (2024 edition).

Works with Claude Code, Cursor, Windsurf, Copilot, Codex, Aider, Zed, Amp, Cline, and pretty much any other agent that supports skills.

## Install

```bash
npx add-skill leonardomso/rust-skills
```

That's it. The CLI figures out which agents you have and installs the skill to the right place.

## How to use it

After installing, just ask your agent:

```
/rust-skills review this function
```

```
/rust-skills is my error handling idiomatic?
```

```
/rust-skills check for memory issues
```

The agent loads the relevant rules and applies them to your code.

## What's in here

218 rules split into 18 categories:

| Category | Rules | What it covers |
|----------|-------|----------------|
| **Ownership & Borrowing** | 12 | When to borrow vs clone, Arc/Rc, lifetimes |
| **Error Handling** | 12 | thiserror for libs, anyhow for apps, the `?` operator |
| **Memory** | 17 | SmallVec, arenas, avoiding allocations, `mem::take`, drop order |
| **Unsafe Code** | 7 | `SAFETY:` comments, Miri, `MaybeUninit`, 2024-edition unsafe |
| **API Design** | 17 | Builder pattern, newtypes, sealed traits, `FromIterator` |
| **Async** | 18 | Tokio patterns, channels, async fn in traits, cancel safety |
| **Concurrency** | 4 | rayon, scoped threads, atomic ordering, thread-locals |
| **Optimization** | 12 | LTO, inlining, PGO, SIMD |
| **Type Safety** | 13 | Newtypes, parse don't validate, `Deref`, `Display`/`Debug` |
| **Conversions** | 3 | `TryFrom`, `FromStr`, `AsMut` |
| **Pattern Matching** | 5 | `let-else`, `matches!`, if-let chains, exhaustive matches |
| **Naming** | 16 | Following Rust API Guidelines |
| **Testing** | 15 | Proptest, mockall, criterion, loom, snapshot tests |
| **Docs** | 12 | Doc examples, intra-doc links, README/crate-doc unification |
| **Performance** | 13 | Iterators, entry API, faster hashers, I/O buffering |
| **Project Structure** | 14 | Workspaces, module layout, features, MSRV |
| **Linting** | 13 | Clippy config, CI setup, `unexpected_cfgs` |
| **Anti-patterns** | 15 | Common mistakes and how to fix them |

Each rule has:
- Why it matters
- Bad code example
- Good code example
- Links to official docs when relevant

## Manual install

If `add-skill` doesn't work for your setup, here's how to install manually:

<details>
<summary><b>Claude Code</b></summary>

Global (applies to all projects):
```bash
git clone https://github.com/leonardomso/rust-skills.git ~/.claude/skills/rust-skills
```

Or just for one project:
```bash
git clone https://github.com/leonardomso/rust-skills.git .claude/skills/rust-skills
```
</details>

<details>
<summary><b>OpenCode</b></summary>

```bash
git clone https://github.com/leonardomso/rust-skills.git .opencode/skills/rust-skills
```
</details>

<details>
<summary><b>Cursor</b></summary>

```bash
git clone https://github.com/leonardomso/rust-skills.git .cursor/skills/rust-skills
```

Or just grab the skill file:
```bash
curl -o .cursorrules https://raw.githubusercontent.com/leonardomso/rust-skills/master/SKILL.md
```
</details>

<details>
<summary><b>Windsurf</b></summary>

```bash
mkdir -p .windsurf/rules
curl -o .windsurf/rules/rust-skills.md https://raw.githubusercontent.com/leonardomso/rust-skills/master/SKILL.md
```
</details>

<details>
<summary><b>OpenAI Codex</b></summary>

```bash
git clone https://github.com/leonardomso/rust-skills.git .codex/skills/rust-skills
```

Or use the AGENTS.md standard:
```bash
curl -o AGENTS.md https://raw.githubusercontent.com/leonardomso/rust-skills/master/SKILL.md
```
</details>

<details>
<summary><b>GitHub Copilot</b></summary>

```bash
mkdir -p .github
curl -o .github/copilot-instructions.md https://raw.githubusercontent.com/leonardomso/rust-skills/master/SKILL.md
```
</details>

<details>
<summary><b>Aider</b></summary>

Add to `.aider.conf.yml`:
```yaml
read: path/to/rust-skills/SKILL.md
```

Or pass it directly:
```bash
aider --read path/to/rust-skills/SKILL.md
```
</details>

<details>
<summary><b>Zed</b></summary>

```bash
curl -o AGENTS.md https://raw.githubusercontent.com/leonardomso/rust-skills/master/SKILL.md
```
</details>

<details>
<summary><b>Amp</b></summary>

```bash
git clone https://github.com/leonardomso/rust-skills.git .agents/skills/rust-skills
```
</details>

<details>
<summary><b>Cline / Roo Code</b></summary>

```bash
mkdir -p .clinerules
curl -o .clinerules/rust-skills.md https://raw.githubusercontent.com/leonardomso/rust-skills/master/SKILL.md
```
</details>

<details>
<summary><b>Other agents (AGENTS.md)</b></summary>

If your agent supports the [AGENTS.md](https://agents.md) standard:
```bash
curl -o AGENTS.md https://raw.githubusercontent.com/leonardomso/rust-skills/master/SKILL.md
```
</details>

## All rules

See [SKILL.md](./SKILL.md) for the full list with links to each rule file.

## Where these rules come from

- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- [Rust Performance Book](https://nnethercote.github.io/perf-book/)
- [Rust Design Patterns](https://rust-unofficial.github.io/patterns/)
- Real code from ripgrep, tokio, serde, polars, axum
- Clippy docs

## Contributing

PRs welcome. Just follow the format of existing rules.

## License

MIT
