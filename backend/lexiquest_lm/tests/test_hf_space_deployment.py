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


def _calls_named(node: ast.AST, name: str) -> list[ast.Call]:
    return [
        child
        for child in ast.walk(node)
        if isinstance(child, ast.Call)
        and isinstance(child.func, ast.Name)
        and child.func.id == name
    ]


def _references_attribute(node: ast.AST, obj: str, attr: str) -> bool:
    return any(
        isinstance(child, ast.Attribute)
        and isinstance(child.value, ast.Name)
        and child.value.id == obj
        and child.attr == attr
        for child in ast.walk(node)
    )


def _has_positive_floor(node: ast.AST) -> bool:
    for call in _calls_named(node, "max"):
        for arg in call.args:
            if (
                isinstance(arg, ast.Constant)
                and isinstance(arg.value, int)
                and not isinstance(arg.value, bool)
                and arg.value >= 1
            ):
                return True
    return False


def _has_cap(node: ast.AST, name: str) -> bool:
    for call in _calls_named(node, "min"):
        for arg in call.args:
            if isinstance(arg, ast.Name) and arg.id == name:
                return True
    return False


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


def test_app_defines_bounded_positive_max_input_tokens() -> None:
    source = _source("app.py")
    tree = ast.parse(source)

    value: ast.AST | None = None
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == "MAX_INPUT_TOKENS"
            for target in node.targets
        ):
            value = node.value
            break
    assert value is not None, "MAX_INPUT_TOKENS must be defined at module scope"

    default = re.search(
        r"os\.environ\.get\(\s*[\"']MAX_INPUT_TOKENS[\"']\s*,\s*[\"'](\d+)[\"']\s*\)",
        source,
    )
    assert default is not None, (
        "MAX_INPUT_TOKENS must be read via os.environ.get with an integer default"
    )
    assert int(default.group(1)) > 0
    assert _has_positive_floor(value)


def test_tokenizer_call_truncates_to_max_input_tokens() -> None:
    tree = ast.parse(_source("app.py"))
    calls = _calls_named(tree, "tokenizer")
    served = [
        call
        for call in calls
        if any(keyword.arg == "return_tensors" for keyword in call.keywords)
    ]
    assert served, "serving tokenizer call must pass return_tensors"
    keywords = {
        keyword.arg: keyword.value
        for call in served
        for keyword in call.keywords
    }

    truncation = keywords.get("truncation")
    assert isinstance(truncation, ast.Constant) and truncation.value is True
    max_length = keywords.get("max_length")
    assert isinstance(max_length, ast.Name)
    assert max_length.id == "MAX_INPUT_TOKENS"


def test_max_tokens_is_clamped_to_inclusive_range() -> None:
    tree = ast.parse(_source("app.py"))
    bounding = next(
        (
            node.value
            for node in ast.walk(tree)
            if isinstance(node, ast.Assign)
            and _references_attribute(node.value, "request", "max_tokens")
        ),
        None,
    )
    assert bounding is not None
    assert _has_positive_floor(bounding)
    assert _has_cap(bounding, "MAX_NEW_TOKENS")
