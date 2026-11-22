#!/usr/bin/env python3
"""Build every nightly example once and execute runnable main functions."""

import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    examples = {
        name: info for name, info in manifest.items() if info["expect"] == "nightly"
    }
    package = HERE / "nightly"
    generated = {path.stem for path in (package / "examples").glob("*.rs")}
    if set(examples) != generated or not examples:
        raise SystemExit("nightly example inventory differs from generated sources")

    result = subprocess.run(
        [
            "cargo",
            "+nightly",
            "build",
            "--examples",
            "--locked",
            "--all-features",
            "--message-format=json-render-diagnostics",
        ],
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
        raise SystemExit("Cargo did not report an executable for every nightly example")

    ran = 0
    for name, info in examples.items():
        if info["nightly_run"]:
            subprocess.run([executables[name]], cwd=package, check=True)
            ran += 1
    print(f"OK: {len(examples)} nightly examples built; {ran} executable contracts passed")


if __name__ == "__main__":
    main()
