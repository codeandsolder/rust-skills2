#!/usr/bin/env python3
"""Regression tests for shell-inert generated maintenance issue bodies."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RENDERER = ROOT / ".github/scripts/render-maintenance-template.py"
WORKFLOW = ROOT / ".github/workflows/rust-release-queue.yml"


def render(template: str, **values: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(values)
    return subprocess.run(
        [sys.executable, str(RENDERER)],
        input=template,
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        sentinel = Path(tmp) / "executed"
        payload = f"$(touch {sentinel})"
        template = "literal `cargo update` and " + payload + "\n<!-- ${marker} -->\n${details}\n"
        details = "injected `code` " + payload + " ${marker}"
        result = render(template, marker="test-marker", details=details)
        assert result.returncode == 0, result.stderr
        assert not sentinel.exists(), "renderer executed shell syntax"
        assert result.stdout == (
            "literal `cargo update` and " + payload + "\n"
            "<!-- test-marker -->\n"
            + details
            + "\n"
        )

    missing = render("${missing}\n")
    assert missing.returncode != 0
    assert "missing template variable: missing" in missing.stderr

    workflow = WORKFLOW.read_text()
    quoted_call = "body=\"$(python3 .github/scripts/render-maintenance-template.py <<'EOF'"
    assert workflow.count(quoted_call) == 1
    assert 'body="$(cat <<EOF' not in workflow
    assert "`SKILL.md`" in workflow
    assert "\\`SKILL.md\\`" not in workflow


if __name__ == "__main__":
    main()
