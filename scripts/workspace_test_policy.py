#!/usr/bin/env python3
"""Resolve per-package test-panic policy for the strict workspace gate."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Any


def fail(message: str) -> "NoReturn":
    print(f"rust-skills2: {message}", file=sys.stderr)
    raise SystemExit(2)


def parse_bool(value: str) -> bool:
    if value == "true":
        return True
    if value == "false":
        return False
    raise argparse.ArgumentTypeError("expected true or false")


def run_json(argv: list[str]) -> dict[str, Any]:
    result = subprocess.run(
        argv,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr, end="")
        fail(f"command failed: {' '.join(argv)}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        fail(f"invalid JSON from {' '.join(argv)}: {error}")
    if not isinstance(value, dict):
        fail(f"unexpected JSON shape from {' '.join(argv)}")
    return value


def parse_package_selectors(cargo_args: list[str]) -> tuple[bool, list[str], list[str]]:
    workspace = False
    packages: list[str] = []
    excludes: list[str] = []
    i = 0
    while i < len(cargo_args):
        arg = cargo_args[i]
        if arg == "--workspace":
            workspace = True
        elif arg in {"-p", "--package", "--exclude"}:
            if i + 1 >= len(cargo_args):
                fail(f"missing value for {arg}")
            value = cargo_args[i + 1]
            if arg == "--exclude":
                excludes.append(value)
            else:
                packages.append(value)
            i += 1
        elif arg.startswith("--package="):
            packages.append(arg.split("=", 1)[1])
        elif arg.startswith("--exclude="):
            excludes.append(arg.split("=", 1)[1])
        i += 1
    return workspace, packages, excludes


def matches_spec(package: dict[str, Any], spec: str) -> bool:
    name = str(package.get("name", ""))
    version = str(package.get("version", ""))
    package_id = str(package.get("id", ""))
    return spec in {
        name,
        f"{name}@{version}",
        package_id,
    }


def select_packages(metadata: dict[str, Any], cargo_args: list[str]) -> list[dict[str, Any]]:
    members = set(metadata.get("workspace_members") or [])
    packages = [
        package
        for package in metadata.get("packages") or []
        if isinstance(package, dict) and package.get("id") in members
    ]
    by_id = {str(package["id"]): package for package in packages}

    workspace, package_specs, exclude_specs = parse_package_selectors(cargo_args)

    if package_specs:
        selected: list[dict[str, Any]] = []
        for spec in package_specs:
            matches = [package for package in packages if matches_spec(package, spec)]
            if len(matches) != 1:
                fail(
                    f"package selector {spec!r} resolved to {len(matches)} workspace members; "
                    "use an exact name@version spec"
                )
            if matches[0] not in selected:
                selected.append(matches[0])
    elif workspace:
        selected = list(packages)
    else:
        default_ids = metadata.get("workspace_default_members") or []
        selected = [by_id[str(package_id)] for package_id in default_ids if str(package_id) in by_id]
        if not selected:
            selected = list(packages)

    for spec in exclude_specs:
        matches = [package for package in selected if matches_spec(package, spec)]
        if not matches:
            fail(f"exclude selector {spec!r} does not match a selected workspace member")
        selected = [package for package in selected if package not in matches]

    return sorted(selected, key=lambda package: (str(package["name"]), str(package["version"])))


def rust_skills2_table(value: Any, location: str) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        fail(f"{location} rust-skills2 metadata must be a table")
    return value


def bool_field(table: dict[str, Any], key: str, location: str) -> bool | None:
    if key not in table:
        return None
    value = table[key]
    if not isinstance(value, bool):
        fail(f"{location} {key} must be true or false")
    return value


def reason_field(table: dict[str, Any], key: str, location: str) -> str | None:
    if key not in table:
        return None
    value = table[key]
    if not isinstance(value, str) or not value.strip():
        fail(f"{location} {key} must be a non-empty string")
    return value.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--default-allow-test-panics", required=True, type=parse_bool)
    parser.add_argument("--cargo-arg", action="append", default=[])
    args = parser.parse_args()

    metadata = run_json(["cargo", "+nightly", "metadata", "--no-deps", "--format-version", "1"])

    workspace_table = rust_skills2_table(
        (metadata.get("metadata") or {}).get("rust-skills2"),
        "workspace.metadata",
    )
    workspace_override = bool_field(
        workspace_table, "allow-test-panics", "workspace.metadata.rust-skills2"
    )
    workspace_reason = reason_field(
        workspace_table, "allow-test-panics-reason", "workspace.metadata.rust-skills2"
    )

    workspace_default = (
        args.default_allow_test_panics if workspace_override is None else workspace_override
    )
    if workspace_override is True and args.default_allow_test_panics is False and workspace_reason is None:
        fail(
            "workspace.metadata.rust-skills2.allow-test-panics = true requires "
            "allow-test-panics-reason"
        )

    selected = select_packages(metadata, args.cargo_arg)
    if not selected:
        fail("Cargo selectors resolved to no workspace packages")

    for package in selected:
        package_location = f"{package['manifest_path']}: package.metadata.rust-skills2"
        package_metadata = package.get("metadata") or {}
        if not isinstance(package_metadata, dict):
            fail(f"{package['manifest_path']}: package metadata must be a table")
        package_table = rust_skills2_table(package_metadata.get("rust-skills2"), package_location)

        package_override = bool_field(package_table, "allow-test-panics", package_location)
        package_reason = reason_field(package_table, "allow-test-panics-reason", package_location)

        effective = workspace_default if package_override is None else package_override
        inherited = workspace_default
        if package_override is True and inherited is False and package_reason is None:
            fail(
                f"{package_location}.allow-test-panics = true requires "
                "allow-test-panics-reason"
            )

        policy = "relaxed" if effective else "strict"
        spec = f"{package['name']}@{package['version']}"
        print(f"{policy}\t{spec}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
