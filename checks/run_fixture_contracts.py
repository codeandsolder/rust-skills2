#!/usr/bin/env python3
"""Run each fixture referenced by a `rust-check: fixture(name)` contract once."""
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
MANIFEST = HERE / "manifest.json"


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "x86_64-unknown-linux-gnu"
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    fixtures = sorted(
        {
            info["expect"].split(":", 1)[1]
            for info in manifest.values()
            if info.get("expect", "").startswith("fixture:")
        }
    )

    env = os.environ.copy()
    env["RUST_SKILLS_ROOT"] = str(ROOT)
    env["RUST_SKILLS_TARGET"] = target

    for name in fixtures:
        script = HERE / "fixtures" / name / "verify.sh"
        if not script.is_file():
            raise SystemExit(f"fixture {name!r} has no verifier: {script}")
        print(f"==> fixture contract: {name}", flush=True)
        subprocess.run(["bash", str(script)], cwd=ROOT, env=env, check=True)

    print(f"OK: {len(fixtures)} fixture contract(s)")


if __name__ == "__main__":
    main()
