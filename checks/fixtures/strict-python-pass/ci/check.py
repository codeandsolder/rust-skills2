from __future__ import annotations


def doubled(value: int) -> int:
    return value * 2


def main() -> int:
    return 0 if doubled(2) == 4 else 1


if __name__ == "__main__":
    raise SystemExit(main())
