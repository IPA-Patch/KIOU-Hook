"""AST-based recipe consistency check.

Validates the per-version ``SITES`` tables in ``recipes/v_*.py`` against
the master ``HOOK_IDS`` / ``ENTRY_SLOT_INDEX`` maps in
``recipes/common.py`` — without importing anything (avoids the runtime
dependency on Kanade's ``tools.encode`` which lives in a sibling repo).

Fails the CI when:

  - A ``SITES`` row references a hook id name not present in ``HOOK_IDS``.
  - A ``CAVE_ENTRY`` row's hook id isn't in ``ENTRY_SLOT_INDEX``.
  - ``ENTRY_SLOT_COUNT`` doesn't match the number of entries in
    ``ENTRY_SLOT_INDEX``.
  - A ``kind`` other than ``CAVE_ENTRY`` / ``CAVE_OBSERVER`` appears.
  - A prologue hex is not exactly 8 characters (4 bytes).
  - Duplicate site RVAs within one recipe.

Run: ``python -m tools.check_recipes`` from the repo root.
"""

from __future__ import annotations

import ast
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
RECIPES_DIR = REPO_ROOT / "recipes"


class RecipeError(Exception):
    """Raised when a recipe fails consistency checks."""


def _load_module_ast(path: pathlib.Path) -> ast.Module:
    return ast.parse(path.read_text(), filename=str(path))


def _find_dict_assign(module: ast.Module, name: str) -> dict[str, int]:
    """Extract a ``name: dict[str, int]`` module-level assignment."""

    for node in module.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = (
                node.targets if isinstance(node, ast.Assign) else [node.target]
            )
            for target in targets:
                if isinstance(target, ast.Name) and target.id == name:
                    if not isinstance(node.value, ast.Dict):
                        raise RecipeError(f"{name}: expected dict literal")
                    out: dict[str, int] = {}
                    for k, v in zip(node.value.keys, node.value.values, strict=True):
                        if not isinstance(k, ast.Constant) or not isinstance(k.value, str):
                            raise RecipeError(f"{name}: non-string key")
                        if not isinstance(v, ast.Constant) or not isinstance(v.value, int):
                            raise RecipeError(f"{name}[{k.value}]: non-int value")
                        out[k.value] = v.value
                    return out
    raise RecipeError(f"{name}: not found at module level")


def _find_int_assign(module: ast.Module, name: str) -> int:
    for node in module.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = (
                node.targets if isinstance(node, ast.Assign) else [node.target]
            )
            for target in targets:
                if isinstance(target, ast.Name) and target.id == name:
                    if not isinstance(node.value, ast.Constant) or not isinstance(
                        node.value.value, int
                    ):
                        raise RecipeError(f"{name}: expected int constant")
                    return node.value.value
    raise RecipeError(f"{name}: not found")


def _find_sites_assign(module: ast.Module) -> list[tuple[int, str, str, str, str]]:
    """Extract the ``SITES`` list of tuples from a per-version recipe."""

    for node in module.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "SITES":
                    if not isinstance(node.value, ast.List):
                        raise RecipeError("SITES: expected list literal")
                    rows: list[tuple[int, str, str, str, str]] = []
                    for i, elt in enumerate(node.value.elts):
                        if not isinstance(elt, ast.Tuple) or len(elt.elts) != 5:
                            raise RecipeError(
                                f"SITES[{i}]: expected 5-tuple (rva, prologue_hex, hook_id_name, kind, label)"
                            )
                        rva_n, prologue_n, hook_id_n, kind_n, label_n = elt.elts
                        if not isinstance(rva_n, ast.Constant) or not isinstance(
                            rva_n.value, int
                        ):
                            raise RecipeError(f"SITES[{i}].rva: expected int constant")
                        if not isinstance(prologue_n, ast.Constant) or not isinstance(
                            prologue_n.value, str
                        ):
                            raise RecipeError(
                                f"SITES[{i}].prologue_hex: expected str constant"
                            )
                        # hook_id_name is usually a bare Name (e.g. KIOU_HOOK_ID_...)
                        # or a string constant; accept both.
                        if isinstance(hook_id_n, ast.Constant) and isinstance(
                            hook_id_n.value, str
                        ):
                            hook_id_val = hook_id_n.value
                        elif isinstance(hook_id_n, ast.Name):
                            hook_id_val = hook_id_n.id
                        else:
                            raise RecipeError(
                                f"SITES[{i}].hook_id_name: expected str or Name"
                            )
                        # kind is imported: CAVE_ENTRY / CAVE_OBSERVER (Name node)
                        if isinstance(kind_n, ast.Name):
                            kind_val = kind_n.id
                        elif isinstance(kind_n, ast.Constant) and isinstance(
                            kind_n.value, str
                        ):
                            kind_val = kind_n.value
                        else:
                            raise RecipeError(f"SITES[{i}].kind: expected Name or str")
                        if not isinstance(label_n, ast.Constant) or not isinstance(
                            label_n.value, str
                        ):
                            raise RecipeError(f"SITES[{i}].label: expected str")
                        rows.append(
                            (rva_n.value, prologue_n.value, hook_id_val, kind_val, label_n.value)
                        )
                    return rows
    raise RecipeError("SITES: not found at module level")


def check() -> None:
    common_path = RECIPES_DIR / "common.py"
    if not common_path.exists():
        raise RecipeError(f"{common_path}: missing")

    common_ast = _load_module_ast(common_path)
    hook_ids = _find_dict_assign(common_ast, "HOOK_IDS")
    entry_slot_index = _find_dict_assign(common_ast, "ENTRY_SLOT_INDEX")
    entry_slot_count = _find_int_assign(common_ast, "ENTRY_SLOT_COUNT")
    entry_slot_capacity = _find_int_assign(common_ast, "ENTRY_SLOT_CAPACITY")

    if entry_slot_count != len(entry_slot_index):
        raise RecipeError(
            f"ENTRY_SLOT_COUNT ({entry_slot_count}) != len(ENTRY_SLOT_INDEX) ({len(entry_slot_index)})"
        )
    if entry_slot_capacity < entry_slot_count:
        raise RecipeError(
            f"ENTRY_SLOT_CAPACITY ({entry_slot_capacity}) < ENTRY_SLOT_COUNT ({entry_slot_count})"
        )

    slot_values = list(entry_slot_index.values())
    if sorted(slot_values) != list(range(entry_slot_count)):
        raise RecipeError(
            f"ENTRY_SLOT_INDEX values must be contiguous 0..{entry_slot_count - 1}; "
            f"got {sorted(slot_values)}"
        )

    version_recipes = sorted(
        p for p in RECIPES_DIR.glob("v*.py") if p.stem.startswith("v")
    )
    if not version_recipes:
        raise RecipeError("no per-version recipes (recipes/v*.py) found")

    errors: list[str] = []
    for recipe in version_recipes:
        try:
            recipe_ast = _load_module_ast(recipe)
            sites = _find_sites_assign(recipe_ast)
        except RecipeError as e:
            errors.append(f"{recipe.name}: {e}")
            continue

        seen_rvas: dict[int, str] = {}
        for i, (rva, prologue_hex, hook_id_name, kind, label) in enumerate(sites):
            where = f"{recipe.name} SITES[{i}] ({label})"
            if len(prologue_hex) != 8:
                errors.append(
                    f"{where}: prologue_hex must be 8 chars (4 bytes); got {len(prologue_hex)}"
                )
            try:
                int(prologue_hex, 16)
            except ValueError:
                errors.append(f"{where}: prologue_hex not valid hex")
            if kind not in {"CAVE_ENTRY", "CAVE_OBSERVER"}:
                errors.append(f"{where}: unknown kind {kind!r}")
            if hook_id_name not in hook_ids:
                errors.append(
                    f"{where}: hook_id_name {hook_id_name!r} missing from HOOK_IDS"
                )
            if kind == "CAVE_ENTRY" and hook_id_name not in entry_slot_index:
                errors.append(
                    f"{where}: CAVE_ENTRY row's hook_id {hook_id_name!r} missing from ENTRY_SLOT_INDEX"
                )
            if kind == "CAVE_OBSERVER" and hook_id_name in entry_slot_index:
                errors.append(
                    f"{where}: CAVE_OBSERVER row's hook_id {hook_id_name!r} unexpectedly in ENTRY_SLOT_INDEX"
                )
            if rva in seen_rvas:
                errors.append(
                    f"{where}: duplicate site RVA 0x{rva:X} (already at {seen_rvas[rva]})"
                )
            else:
                seen_rvas[rva] = label

    if errors:
        raise RecipeError("\n  ".join(["recipe check failed:", *errors]))

    print(
        f"OK: HOOK_IDS={len(hook_ids)} ENTRY_SLOT_INDEX={len(entry_slot_index)} "
        f"ENTRY_SLOT_COUNT={entry_slot_count} recipes={len(version_recipes)} "
        f"sites={sum(len(_find_sites_assign(_load_module_ast(p))) for p in version_recipes)}"
    )


if __name__ == "__main__":
    try:
        check()
    except RecipeError as e:
        print(f"recipe-check: {e}", file=sys.stderr)
        sys.exit(1)
