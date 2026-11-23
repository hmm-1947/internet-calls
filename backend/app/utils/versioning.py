def _build(value: str | None) -> int | None:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def is_outdated(current_build: str | None, required_build: str | None) -> bool:
    required = _build(required_build)
    if required is None:
        return False
    current = _build(current_build)
    if current is None:
        return True
    return current < required
