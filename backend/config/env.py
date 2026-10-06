"""Environment helpers. Settings come from the environment only; a git-ignored
backend/.env file is read for local development and never overrides real variables."""

import os
from pathlib import Path


def load_dotenv(path: Path) -> None:
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def get(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    return default if value is None or value == "" else value


def required(name: str) -> str:
    value = get(name)
    if value is None:
        raise RuntimeError(f"Environment variable {name} is required")
    return value


def get_bool(name: str, default: bool = False) -> bool:
    value = get(name)
    return default if value is None else value.strip().lower() in {"1", "true", "yes", "on"}


def get_int(name: str, default: int) -> int:
    value = get(name)
    return default if value is None else int(value)


def get_list(name: str, default: tuple[str, ...] = ()) -> list[str]:
    value = get(name)
    if value is None:
        return list(default)
    return [item.strip() for item in value.split(",") if item.strip()]
