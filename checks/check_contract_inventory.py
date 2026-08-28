#!/usr/bin/env python3
"""Enforce that maintained rule contracts have no weak skip expectations."""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))

forbidden = []
for name, info in manifest.items():
    if info.get("expect") in {"ignore", "fragment"}:
        forbidden.append((name, info))

if forbidden:
    print(f"FAIL: {len(forbidden)} weak verifier exemption(s) remain:")
    for _name, info in sorted(
        forbidden,
        key=lambda row: (row[1].get("file", ""), row[1].get("line", 0)),
    ):
        print(
            f"  {info.get('file', '?')}:{info.get('line', '?')} "
            f"[{info.get('section', '?')}] -> {info.get('expect')}"
        )
    raise SystemExit(1)

fixtures = sorted(
    {
        info["expect"].split(":", 1)[1]
        for info in manifest.values()
        if info.get("expect", "").startswith("fixture:")
    }
)
print(
    "OK: no ignore/fragment contracts; "
    f"{len(fixtures)} referenced fixture contract(s)"
)
