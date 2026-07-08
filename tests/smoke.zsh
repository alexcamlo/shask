#!/usr/bin/env zsh
set -euo pipefail

repo="${0:A:h:h}"
export PATH="${repo}/tests/fixtures/bin:${PATH}"
export PI_SHELL_ASSIST_CONTEXT=1
export PI_SHELL_ASSIST_BINDKEY=0

source "${repo}/shell-assist.zsh"

err_file="${TMPDIR:-/tmp}/shell-assist-smoke-$$.err"
: > "$err_file"
_pi_shell_assist_context_block >/dev/null 2>"$err_file"
if [[ -s "$err_file" ]]; then
  print -u2 -r -- "context block wrote stderr:"
  cat "$err_file" >&2
  exit 1
fi

generated="$(pai --print list files)"
[[ "$generated" == "ls -la" ]] || {
  print -u2 -r -- "expected sanitized command 'ls -la', got: $generated"
  exit 1
}

description="$(pai --describe 'ls -la')"
[[ "$description" == "Lists files with details." ]] || {
  print -u2 -r -- "unexpected description: $description"
  exit 1
}

print -r -- "smoke ok"
