#!/usr/bin/env python3
"""Build uploadable Agent Skill archives from the repository source tree."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_PATHS = (Path("SKILL.md"), Path("LICENSE"), Path("rules"))
FIXED_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
NAME_RE = re.compile(r"(?m)^name:\s*([A-Za-z0-9][A-Za-z0-9_-]*)\s*$")


def read_skill_name() -> str:
    skill_file = ROOT / "SKILL.md"
    text = skill_file.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise SystemExit("SKILL.md must start with YAML frontmatter")

    end = text.find("\n---\n", 4)
    if end == -1:
        raise SystemExit("SKILL.md frontmatter is not terminated")

    match = NAME_RE.search(text[: end + 1])
    if not match:
        raise SystemExit("SKILL.md frontmatter must contain a simple 'name:' field")
    return match.group(1)


def package_files() -> list[Path]:
    files: list[Path] = []
    for relative in PACKAGE_PATHS:
        source = ROOT / relative
        if not source.exists():
            raise SystemExit(f"required package path is missing: {relative}")
        if source.is_symlink():
            raise SystemExit(f"package path must not be a symlink: {relative}")
        if source.is_file():
            files.append(relative)
            continue

        for child in source.rglob("*"):
            if child.is_symlink():
                raise SystemExit(f"package contents must not contain symlinks: {child.relative_to(ROOT)}")
            if child.is_file():
                files.append(child.relative_to(ROOT))

    return sorted(files, key=lambda path: path.as_posix())


def add_file(archive: zipfile.ZipFile, skill_name: str, relative: Path) -> None:
    archive_name = f"{skill_name}/{relative.as_posix()}"
    info = zipfile.ZipInfo(archive_name, FIXED_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    archive.writestr(info, (ROOT / relative).read_bytes(), compresslevel=9)


def validate_archive(path: Path, skill_name: str, expected_files: list[Path]) -> None:
    expected = {f"{skill_name}/{relative.as_posix()}" for relative in expected_files}

    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        actual = set(names)
        if len(names) != len(actual):
            raise SystemExit("package contains duplicate ZIP entries")
        if actual != expected:
            missing = sorted(expected - actual)
            extra = sorted(actual - expected)
            raise SystemExit(f"package contents differ from manifest; missing={missing}, extra={extra}")

        top_levels: set[str] = set()
        for name in names:
            parsed = PurePosixPath(name)
            if parsed.is_absolute() or ".." in parsed.parts:
                raise SystemExit(f"unsafe path in package: {name}")
            if len(parsed.parts) < 2:
                raise SystemExit(f"package entry is not inside the skill folder: {name}")
            top_levels.add(parsed.parts[0])

        if top_levels != {skill_name}:
            raise SystemExit(f"package must contain exactly one top-level folder named {skill_name!r}")
        if f"{skill_name}/SKILL.md" not in actual:
            raise SystemExit("package is missing SKILL.md")
        if not any(name.startswith(f"{skill_name}/rules/") for name in actual):
            raise SystemExit("package contains no rule files")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build(output_dir: Path) -> tuple[Path, Path, Path]:
    skill_name = read_skill_name()
    files = package_files()
    output_dir.mkdir(parents=True, exist_ok=True)

    zip_path = output_dir / f"{skill_name}.zip"
    skill_path = output_dir / f"{skill_name}.skill"
    checksum_path = output_dir / "SHA256SUMS"

    with zipfile.ZipFile(zip_path, "w") as archive:
        for relative in files:
            add_file(archive, skill_name, relative)

    validate_archive(zip_path, skill_name, files)
    shutil.copyfile(zip_path, skill_path)

    checksum_path.write_text(
        f"{sha256(zip_path)}  {zip_path.name}\n"
        f"{sha256(skill_path)}  {skill_path.name}\n",
        encoding="utf-8",
        newline="\n",
    )

    if zip_path.read_bytes() != skill_path.read_bytes():
        raise SystemExit(".zip and .skill outputs are not byte-identical")

    return zip_path, skill_path, checksum_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / "dist",
        help="output directory (default: ./dist)",
    )
    args = parser.parse_args()

    outputs = build(args.output_dir.resolve())
    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()
