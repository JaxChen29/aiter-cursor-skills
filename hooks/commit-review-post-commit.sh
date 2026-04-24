#!/usr/bin/env python3
import json
import re
import sys


def nested_get(data, *keys):
    current = data
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def first_string(*values):
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def flatten_output(value):
    if isinstance(value, str):
        return value.strip()

    if isinstance(value, dict):
        parts = []
        for key in ("stdout", "stderr", "output", "message", "text"):
            item = value.get(key)
            if isinstance(item, str) and item.strip():
                parts.append(item.strip())
        return "\n".join(parts)

    return ""


raw_input = sys.stdin.read()
if not raw_input.strip():
    print("{}")
    raise SystemExit(0)

try:
    payload = json.loads(raw_input)
except json.JSONDecodeError:
    print("{}")
    raise SystemExit(0)

command = first_string(
    nested_get(payload, "tool_input", "command"),
    nested_get(payload, "input", "command"),
    payload.get("command"),
)

if not command:
    print("{}")
    raise SystemExit(0)

if not re.search(r"\bgit\b", command) or not re.search(r"\bcommit\b", command):
    print("{}")
    raise SystemExit(0)

working_directory = first_string(
    nested_get(payload, "tool_input", "working_directory"),
    nested_get(payload, "input", "working_directory"),
    payload.get("working_directory"),
    payload.get("cwd"),
)

tool_output = (
    payload.get("tool_output")
    if isinstance(payload, dict)
    else None
)
output_text = flatten_output(tool_output)
if not output_text:
    output_text = flatten_output(payload.get("output"))

sha_match = re.search(r"\[[^\]]+ ([0-9a-f]{7,40})\]", output_text)
if not sha_match:
    sha_match = re.search(r"\b([0-9a-f]{7,40})\b", output_text)

review_target = sha_match.group(1) if sha_match else "HEAD"

context_lines = [
    "A new git commit was created from a Cursor shell command.",
]

if working_directory:
    context_lines.append(f"Repository: `{working_directory}`")

context_lines.extend(
    [
        f"Review target: `{review_target}`.",
        "Use the `commit-review` skill if it is installed.",
        "Start with `git show --stat --summary <target>`, `git show --format=fuller --no-patch <target>`, and `git show <target>`.",
        "Return findings first with severity tags, then open questions or assumptions, then a short summary.",
        "Prioritize correctness, regression risk, missing tests, and aiter SP3 or kernel concerns for low-level code.",
    ]
)

print(json.dumps({"additional_context": "\n".join(context_lines)}))
