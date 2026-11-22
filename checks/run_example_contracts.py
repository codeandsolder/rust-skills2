#!/usr/bin/env python3
"""Build selected documentation examples once and execute runnable contracts."""

import argparse
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("stable", "nightly"))
    parser.add_argument("--target")
    args = parser.parse_args()
    mode = args.mode
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))

    if mode == "nightly":
        package = HERE / "nightly"
        examples = {
            name: info for name, info in manifest.items() if info["expect"] == "nightly"
        }
        generated = {path.stem for path in (package / "examples").glob("*.rs")}
        if set(examples) != generated:
            raise SystemExit("nightly example inventory differs from generated sources")
        command = ["cargo", "build", "--examples", "--all-features"]
    else:
        package = HERE
        examples = {name: info for name, info in manifest.items() if info.get("stable_run")}
        command = ["cargo", "build"]
        for name in examples:
            command.extend(("--example", name))

    if not examples:
        raise SystemExit(f"no {mode} examples selected")

    if args.target:
        command.extend(("--target", args.target))

    result = subprocess.run(
        [*command, "--locked", "--message-format=json-render-diagnostics"],
        cwd=package,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    executables = {}
    for line in result.stdout.splitlines():
        message = json.loads(line)
        if (
            message["reason"] == "compiler-artifact"
            and "example" in message["target"]["kind"]
            and message["executable"] is not None
        ):
            executables[message["target"]["name"]] = Path(message["executable"])
    if set(executables) != set(examples):
        raise SystemExit("Cargo did not report an executable for every selected example")

    ran = 0
    for name, info in examples.items():
        if info[f"{mode}_run"]:
            subprocess.run([executables[name]], cwd=package, check=True, timeout=30)
            ran += 1
    print(f"OK: {len(examples)} {mode} examples built; {ran} executable contracts passed")


if __name__ == "__main__":
    main()
