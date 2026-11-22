"""Check actual Clippy diagnostics against the semantic inventory contract."""

import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
expected = {
    number for number, line in enumerate(source.read_text().splitlines(), start=1)
    if line.endswith("// audit")
}
observed: set[int] = set()
for line in sys.stdin:
    item = json.loads(line)
    if item.get("reason") != "compiler-message":
        continue
    message = item["message"]
    code = (message.get("code") or {}).get("code")
    if code == "unfulfilled_lint_expectations":
        raise SystemExit("credential boundary expectation did not correspond to an actual finding")
    if code != "clippy::disallowed_methods":
        continue
    if message["level"] != "warning":
        raise SystemExit(f"advisory unexpectedly became {message['level']}")
    for span in message["spans"]:
        if span["is_primary"] and Path(span["file_name"]).name == source.name:
            observed.add(span["line_start"])
if observed != expected:
    raise SystemExit(f"ambient audit mismatch: expected {sorted(expected)}, observed {sorted(observed)}")
print(f"OK: {len(observed)} compiler-resolved ambient environment operations")
