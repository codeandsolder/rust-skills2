//! Deterministic, compressed Agent Skill archives. Directory traversal and
//! output publication are host operations; ZIP construction and verification
//! use the same Rust/WASI binary on every platform.

use sha2::{Digest, Sha256};
use std::{
    collections::BTreeSet,
    error::Error,
    fs,
    io::{self, Cursor, Read, Write},
    path::Path,
};
use zip::{CompressionMethod, DateTime, ZipArchive, ZipWriter, write::SimpleFileOptions};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}

fn skill_name(text: &str) -> Result<&str> {
    let rest = text
        .strip_prefix("---\n")
        .ok_or_else(|| invalid("SKILL.md must start with YAML frontmatter"))?;
    let (frontmatter, _) = rest
        .split_once("\n---\n")
        .ok_or_else(|| invalid("SKILL.md frontmatter is not terminated"))?;
    let mut names = frontmatter
        .lines()
        .filter_map(|line| line.strip_prefix("name:").map(str::trim));
    let name = names
        .next()
        .ok_or_else(|| invalid("SKILL.md frontmatter lacks name"))?;
    if names.next().is_some()
        || !name
            .as_bytes()
            .first()
            .is_some_and(u8::is_ascii_alphanumeric)
        || !name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-'))
    {
        return Err(invalid("SKILL.md must contain one simple skill name").into());
    }
    Ok(name)
}

fn validate_paths(paths: &[String]) -> Result<()> {
    let mut seen = BTreeSet::new();
    for name in paths {
        if name.contains(['\\', ':', '\0'])
            || name
                .split('/')
                .any(|part| part.is_empty() || part == "." || part == "..")
            || !(matches!(name.as_str(), "LICENSE" | "SKILL.md") || name.starts_with("rules/"))
            || !seen.insert(name.as_str())
        {
            return Err(invalid(format!("invalid or duplicate package path: {name}")).into());
        }
    }
    if !seen.contains("LICENSE")
        || !seen.contains("SKILL.md")
        || !seen.iter().any(|name| name.starts_with("rules/"))
    {
        return Err(invalid("package requires LICENSE, SKILL.md and rule files").into());
    }
    Ok(())
}

struct Entry {
    name: String,
    bytes: Vec<u8>,
}

fn archive(entries: &[Entry]) -> Result<Vec<u8>> {
    let options = SimpleFileOptions::default()
        .compression_method(CompressionMethod::Deflated)
        .compression_level(Some(9))
        .last_modified_time(DateTime::default())
        .unix_permissions(0o644);
    let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
    for entry in entries {
        writer.start_file(&entry.name, options)?;
        writer.write_all(&entry.bytes)?;
    }
    let bytes = writer.finish()?.into_inner();
    verify(&bytes, entries)?;
    Ok(bytes)
}

fn verify(bytes: &[u8], entries: &[Entry]) -> Result<()> {
    let mut reader = ZipArchive::new(Cursor::new(bytes))?;
    if reader.len() != entries.len() {
        return Err(invalid("archive entry count differs from manifest").into());
    }
    let mut decoded = Vec::new();
    for (index, entry) in entries.iter().enumerate() {
        let mut file = reader.by_index(index)?;
        if file.name()? != entry.name
            || file.compression() != CompressionMethod::Deflated
            || file.last_modified() != Some(DateTime::default())
            || file.unix_mode() != Some(0o100_644)
        {
            return Err(invalid(format!("archive entry metadata mismatch: {}", entry.name)).into());
        }
        decoded.clear();
        file.read_to_end(&mut decoded)?;
        if decoded != entry.bytes {
            return Err(invalid(format!("archive contents differ: {}", entry.name)).into());
        }
    }
    Ok(())
}

fn build(root: &Path, output: &Path, mut paths: Vec<String>) -> Result<()> {
    validate_paths(&paths)?;
    paths.sort_unstable();
    let text = fs::read_to_string(root.join("SKILL.md"))?;
    let name = skill_name(&text)?;
    let entries: Vec<_> = paths
        .iter()
        .map(|relative| -> Result<Entry> {
            Ok(Entry {
                name: format!("{name}/{relative}"),
                bytes: fs::read(root.join(relative))?,
            })
        })
        .collect::<Result<_>>()?;
    let bytes = archive(&entries)?;
    let digest = hex::encode(Sha256::digest(&bytes));
    let zip_name = format!("{name}.zip");
    let skill_file = format!("{name}.skill");
    fs::write(output.join(&zip_name), &bytes)?;
    fs::write(output.join(&skill_file), &bytes)?;
    fs::write(
        output.join("SHA256SUMS"),
        format!("{digest}  {zip_name}\n{digest}  {skill_file}\n"),
    )?;
    Ok(())
}

fn main() -> Result<()> {
    let paths: Vec<String> = serde_json::from_reader(io::stdin().lock())?;
    build(Path::new("/workspace"), Path::new("/out"), paths)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frontmatter_requires_one_portable_name() -> Result<()> {
        assert_eq!(
            skill_name("---\nname: rust-skills\n---\nbody")?,
            "rust-skills"
        );
        for source in [
            "name: rust-skills\n",
            "---\nname: rust-skills\n",
            "---\nname: ../unsafe\n---\n",
            "---\nname: rust-skills\nname: duplicate\n---\n",
            "---\nname: invalid space\n---\n",
        ] {
            assert!(skill_name(source).is_err());
        }
        Ok(())
    }

    #[test]
    fn archive_paths_are_unique_and_bounded() -> Result<()> {
        let base = vec!["LICENSE".into(), "SKILL.md".into(), "rules/one.md".into()];
        validate_paths(&base)?;
        for name in [
            "rules/../escape",
            "/rules/a",
            "rules//a",
            "rules/a\\b",
            "rules/one.md",
            "outside",
        ] {
            let mut paths = base.clone();
            paths.push(name.into());
            assert!(validate_paths(&paths).is_err());
        }
        assert!(validate_paths(&base[..2]).is_err());
        Ok(())
    }

    #[test]
    fn archive_roundtrips_and_is_deterministic() -> Result<()> {
        let inputs = vec![
            Entry {
                name: "skill/LICENSE".into(),
                bytes: b"license".to_vec(),
            },
            Entry {
                name: "skill/SKILL.md".into(),
                bytes: b"skill".to_vec(),
            },
            Entry {
                name: "skill/rules/\u{1f980}.md".into(),
                bytes: b"example\n".repeat(4096),
            },
        ];
        let first = archive(&inputs)?;
        let second = archive(&inputs)?;
        assert_eq!(first, second);
        assert!(first.len() < 1024);
        Ok(())
    }
}
