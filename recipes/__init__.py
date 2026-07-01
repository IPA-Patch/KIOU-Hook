"""KIOU-Hook recipe — entry point for ``tools.patch_macho``.

Selects the active version via the ``TARGET_VERSION`` environment variable
(default: ``1.0.2``) and re-exports the patch surface that
``tools.patch_macho`` and ``tools.verify_sites`` expect.
"""

from __future__ import annotations

import importlib
import os

from recipes.common import (
    DYLIB_PATH,
    ENTRY_SLOT_CAPACITY,
    ENTRY_SLOT_COUNT,
    ENTRY_SLOT_INDEX,
    PLIST_KEYS,
    TARGET_BASENAME,
    build_exports,
)

__all__ = [
    "CAVE_PATCHES",
    "CAVE_REGION",
    "DYLIB_PATH",
    "ENTRY_SLOT_BASE_RVA",
    "ENTRY_SLOT_CAPACITY",
    "ENTRY_SLOT_COUNT",
    "ENTRY_SLOT_INDEX",
    "HOOK_SLOT_RVA",
    "INJECT_ENTRY_TABLE_RVA",
    "PATCHES",
    "PLIST_KEYS",
    "PROBED_HOOK_SLOT_RVA",
    "PROBED_INJECT_ENTRY_TABLE_RVA",
    "TARGET_BASENAME",
    "build_exports",
]

_VERSIONS: dict[str, str | None] = {
    "1.0.1": "recipes.v1_0_1",
    "1.0.2": "recipes.v1_0_2",
}

_DEFAULT_VERSION = "1.0.2"

_target_version = os.environ.get("TARGET_VERSION", _DEFAULT_VERSION)
_module_name = _VERSIONS.get(_target_version)

if _module_name is None:
    _known = [v for v, m in _VERSIONS.items() if m is not None]
    raise ImportError(
        f"KIOU version {_target_version!r} is not in the version registry.\n"
        f"  Known versions: {_known}"
    )

_v = importlib.import_module(_module_name)

assert _v.ENTRY_SLOT_BASE_RVA + ENTRY_SLOT_CAPACITY * 8 <= _v.ZERO_REGION_END_RVA, (
    f"entry slot reservation overflows verified-zero region for {_target_version}"
)
assert _v.HOOK_SLOT_RVA + 8 <= _v.ZERO_REGION_END_RVA, (
    f"observer slot placement overflows verified-zero region for {_target_version}"
)

CAVE_REGION                   = _v.CAVE_REGION
HOOK_SLOT_RVA                 = _v.HOOK_SLOT_RVA
PROBED_HOOK_SLOT_RVA          = _v.PROBED_HOOK_SLOT_RVA
INJECT_ENTRY_TABLE_RVA        = _v.INJECT_ENTRY_TABLE_RVA
PROBED_INJECT_ENTRY_TABLE_RVA = _v.PROBED_INJECT_ENTRY_TABLE_RVA
ENTRY_SLOT_BASE_RVA           = _v.ENTRY_SLOT_BASE_RVA

PATCHES, CAVE_PATCHES, _SITES = build_exports(
    _v.SITES,
    _v.AFK_SITE,
    _v.AFK_ORIG_8,
    _v.HOOK_SLOT_RVA,
    _v.ENTRY_SLOT_BASE_RVA,
)
