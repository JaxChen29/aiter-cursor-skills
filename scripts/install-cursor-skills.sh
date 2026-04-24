#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install aiter-cursor-skills into ~/.cursor/skills using symlinks.

Usage:
  ./scripts/install-cursor-skills.sh [--skip-hook] [skill-name ...]

Examples:
  ./scripts/install-cursor-skills.sh
  ./scripts/install-cursor-skills.sh commit-review code-review
  ./scripts/install-cursor-skills.sh --skip-hook

Environment overrides:
  CURSOR_HOME         Defaults to $HOME/.cursor
  CURSOR_SKILLS_DIR   Defaults to $CURSOR_HOME/skills
  CURSOR_HOOKS_DIR    Defaults to $CURSOR_HOME/hooks
  CURSOR_HOOKS_JSON   Defaults to $CURSOR_HOME/hooks.json
EOF
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

CURSOR_HOME=${CURSOR_HOME:-"$HOME/.cursor"}
CURSOR_SKILLS_DIR=${CURSOR_SKILLS_DIR:-"$CURSOR_HOME/skills"}
CURSOR_HOOKS_DIR=${CURSOR_HOOKS_DIR:-"$CURSOR_HOME/hooks"}
CURSOR_HOOKS_JSON=${CURSOR_HOOKS_JSON:-"$CURSOR_HOME/hooks.json"}

INSTALL_HOOK=1
declare -a REQUESTED_SKILLS=()
declare -a ALL_SKILLS=(
  "aiter-dev"
  "kernel-workflow"
  "code-review"
  "doc-analysis"
  "env-setup"
  "commit-review"
  "fmha-bwd-sbhd-lsed-fix"
  "daily-report"
)

skill_kind() {
  case "$1" in
    aiter-dev|kernel-workflow|code-review|env-setup|daily-report)
      printf '%s\n' "flat"
      ;;
    doc-analysis|commit-review|fmha-bwd-sbhd-lsed-fix)
      printf '%s\n' "dir"
      ;;
    *)
      return 1
      ;;
  esac
}

skill_source() {
  case "$1" in
    aiter-dev)
      printf '%s\n' "$REPO_ROOT/skills/general/aiter-dev.md"
      ;;
    kernel-workflow)
      printf '%s\n' "$REPO_ROOT/skills/general/kernel-workflow.md"
      ;;
    code-review)
      printf '%s\n' "$REPO_ROOT/skills/general/code-review.md"
      ;;
    doc-analysis)
      printf '%s\n' "$REPO_ROOT/skills/general/doc-analysis"
      ;;
    env-setup)
      printf '%s\n' "$REPO_ROOT/skills/general/env-setup.md"
      ;;
    commit-review)
      printf '%s\n' "$REPO_ROOT/skills/general/commit-review"
      ;;
    fmha-bwd-sbhd-lsed-fix)
      printf '%s\n' "$REPO_ROOT/skills/general/fmha-bwd-sbhd-lsed-fix"
      ;;
    daily-report)
      printf '%s\n' "$REPO_ROOT/skills/personal/daily-report.md"
      ;;
    *)
      return 1
      ;;
  esac
}

install_flat_skill() {
  local skill_name=$1
  local source_path=$2
  local target_dir="$CURSOR_SKILLS_DIR/$skill_name"
  local target_file="$target_dir/SKILL.md"

  if [[ ! -e "$source_path" ]]; then
    printf 'Missing source file for %s: %s\n' "$skill_name" "$source_path" >&2
    exit 1
  fi

  if [[ -L "$target_dir" ]]; then
    rm -f "$target_dir"
  fi

  if [[ -e "$target_dir" && ! -d "$target_dir" ]]; then
    printf 'Refusing to overwrite non-directory target: %s\n' "$target_dir" >&2
    exit 1
  fi

  mkdir -p "$target_dir"

  if [[ -e "$target_file" && ! -L "$target_file" ]]; then
    printf 'Refusing to overwrite non-symlink file: %s\n' "$target_file" >&2
    exit 1
  fi

  ln -sfn "$source_path" "$target_file"
  printf 'Installed flat skill wrapper: %s -> %s\n' "$target_file" "$source_path"
}

install_dir_skill() {
  local skill_name=$1
  local source_path=$2
  local target_dir="$CURSOR_SKILLS_DIR/$skill_name"

  if [[ ! -e "$source_path" ]]; then
    printf 'Missing source directory for %s: %s\n' "$skill_name" "$source_path" >&2
    exit 1
  fi

  if [[ -e "$target_dir" && ! -L "$target_dir" ]]; then
    printf 'Refusing to overwrite existing directory: %s\n' "$target_dir" >&2
    exit 1
  fi

  ln -sfn "$source_path" "$target_dir"
  printf 'Installed directory skill: %s -> %s\n' "$target_dir" "$source_path"
}

install_hook() {
  local source_path="$REPO_ROOT/hooks/commit-review-post-commit.sh"
  local target_path="$CURSOR_HOOKS_DIR/commit-review-post-commit.sh"

  if [[ ! -e "$source_path" ]]; then
    printf 'Missing hook source: %s\n' "$source_path" >&2
    exit 1
  fi

  mkdir -p "$CURSOR_HOOKS_DIR"

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    printf 'Refusing to overwrite existing hook file: %s\n' "$target_path" >&2
    exit 1
  fi

  ln -sfn "$source_path" "$target_path"

  python3 - "$CURSOR_HOOKS_JSON" <<'PY'
import json
import pathlib
import sys

hooks_json_path = pathlib.Path(sys.argv[1])
command_path = "hooks/commit-review-post-commit.sh"
new_entry = {
    "command": command_path,
    "matcher": "^Shell$",
    "timeout": 10,
}

if hooks_json_path.exists():
    try:
        data = json.loads(hooks_json_path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Failed to parse existing hooks.json: {exc}")
else:
    data = {}

if not isinstance(data, dict):
    data = {}

hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

post_tool_use = hooks.get("postToolUse")
if not isinstance(post_tool_use, list):
    post_tool_use = []

filtered_entries = []
for entry in post_tool_use:
    if not isinstance(entry, dict):
        filtered_entries.append(entry)
        continue

    if entry.get("command") == command_path:
        continue

    filtered_entries.append(entry)

filtered_entries.append(new_entry)

hooks["postToolUse"] = filtered_entries
data["version"] = 1
data["hooks"] = hooks

hooks_json_path.parent.mkdir(parents=True, exist_ok=True)
hooks_json_path.write_text(json.dumps(data, indent=2) + "\n")
PY

  printf 'Installed post-commit hook: %s -> %s\n' "$target_path" "$source_path"
  printf 'Updated hook config: %s\n' "$CURSOR_HOOKS_JSON"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --skip-hook)
      INSTALL_HOOK=0
      ;;
    *)
      REQUESTED_SKILLS+=("$1")
      ;;
  esac
  shift
done

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required by this installer.\n' >&2
  exit 1
fi

mkdir -p "$CURSOR_SKILLS_DIR"

if [[ ${#REQUESTED_SKILLS[@]} -eq 0 ]]; then
  REQUESTED_SKILLS=("${ALL_SKILLS[@]}")
fi

for skill_name in "${REQUESTED_SKILLS[@]}"; do
  if ! kind=$(skill_kind "$skill_name"); then
    printf 'Unknown skill: %s\n' "$skill_name" >&2
    usage >&2
    exit 1
  fi

  source_path=$(skill_source "$skill_name")

  case "$kind" in
    flat)
      install_flat_skill "$skill_name" "$source_path"
      ;;
    dir)
      install_dir_skill "$skill_name" "$source_path"
      ;;
  esac
done

if [[ $INSTALL_HOOK -eq 1 ]]; then
  install_hook
fi

printf '\nInstalled %s skill(s) into %s\n' "${#REQUESTED_SKILLS[@]}" "$CURSOR_SKILLS_DIR"
if [[ $INSTALL_HOOK -eq 1 ]]; then
  printf 'Post-commit hook installed under %s\n' "$CURSOR_HOOKS_DIR"
else
  printf 'Post-commit hook skipped.\n'
fi
printf 'Restart Cursor if the new skills do not appear immediately.\n'
