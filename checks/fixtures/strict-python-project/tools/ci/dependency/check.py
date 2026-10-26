from __future__ import annotations

from typing_extensions import TypeIs


def is_text(value: object) -> TypeIs[str]:
    return isinstance(value, str)
