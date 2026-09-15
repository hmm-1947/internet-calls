"""Simple numeric-tuple version comparison, e.g. '2.10.0' vs '2.9.0'.

Used to decide whether an installed app build is older than the version
the admin has published as required. Deliberately not a full semver
implementation (no pre-release/build-metadata handling) since app builds
here only ever use plain "major.minor.patch"-style numbers.
"""
import re


def _parts(version: str) -> tuple[int, ...]:
    return tuple(int(x) for x in re.findall(r"\d+", version or ""))


def is_outdated(current_version: str | None, required_version: str | None) -> bool:
    """True if `current_version` is behind `required_version`.

    No required version set -> nothing is ever outdated (feature is off).
    Required version set but the client didn't report one -> treated as
    outdated, since an app old enough to predate this check is, by
    definition, not on the latest version.
    """
    if not required_version:
        return False
    if not current_version:
        return True
    return _parts(current_version) < _parts(required_version)
