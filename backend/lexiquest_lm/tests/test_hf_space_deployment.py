"""Static deployment invariants for the standalone Hugging Face Space."""

from __future__ import annotations

import ast
import re
from pathlib import Path

import pytest

from tokenise_dataset import SYSTEM_PROMPT as TRAIN_SYSTEM_PROMPT
from tokenise_dataset import format_prompt as train_format_prompt

_SPACE_DIR = Path(__file__).resolve().parent.parent / "deploy" / "hf_space"


def _source(name: str) -> str:
    return (_SPACE_DIR / name).read_text(encoding="utf-8")


def _serving_prompt_helpers() -> tuple[str, object]:
    tree = ast.parse(_source("app.py"))
    namespace: dict[str, object] = {}
    selected: list[ast.stmt] = []
    for node in tree.body:
        if isinstance(node, ast.Assign):
            names = {
                target.id
                for target in node.targets
                if isinstance(target, ast.Name)
            }
            if names & {"SYSTEM_PROMPT", "_PROMPT_TEMPLATE"}:
                selected.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name == "format_prompt":
            selected.append(node)
    module = ast.fix_missing_locations(ast.Module(body=selected, type_ignores=[]))
    exec(compile(module, str(_SPACE_DIR / "app.py"), "exec"), namespace)
    return str(namespace["SYSTEM_PROMPT"]), namespace["format_prompt"]


def test_deploy_directory_contains_required_space_files() -> None:
    required = {"app.py", "auth.py", "requirements.txt", "README.md", "Dockerfile"}
    assert required <= {entry.name for entry in _SPACE_DIR.iterdir()}


def test_app_has_no_training_tree_runtime_dependency() -> None:
    tree = ast.parse(_source("app.py"))
    imported_modules = {
        alias.name
        for node in tree.body
        if isinstance(node, ast.Import)
        for alias in node.names
    } | {
        node.module or ""
        for node in tree.body
        if isinstance(node, ast.ImportFrom)
    }
    assert "tokenise_dataset" not in imported_modules
    assert "sys.path" not in _source("app.py")


@pytest.mark.parametrize(
    "user_prompt",
    [
        "Write ONE example sentence using the word cat.",
        "เขียนประโยคสั้น ๆ อธิบายคำว่า school",
    ],
)
def test_serving_prompt_is_byte_compatible_with_training(user_prompt: str) -> None:
    serving_system_prompt, serving_format_prompt = _serving_prompt_helpers()
    assert serving_system_prompt == TRAIN_SYSTEM_PROMPT
    assert callable(serving_format_prompt)
    assert serving_format_prompt(user_prompt) == train_format_prompt(user_prompt)


def test_dockerfile_is_hardened_for_hugging_face_space() -> None:
    dockerfile = _source("Dockerfile")
    assert re.search(
        r"^FROM\s+python:3\.11\.\d+-slim-bookworm@sha256:[0-9a-f]{64}$",
        dockerfile,
        re.MULTILINE,
    )
    assert re.search(r"^USER\s+(?!root\b|0\b)\S+", dockerfile, re.MULTILINE)
    assert re.search(r"^EXPOSE\s+7860$", dockerfile, re.MULTILINE)
    command = next(
        line for line in dockerfile.splitlines() if line.startswith("CMD ")
    )
    for expected in ("uvicorn", "app:app", "0.0.0.0", "7860"):
        assert expected in command
    assert "HEALTHCHECK" in dockerfile
