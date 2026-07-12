#!/usr/bin/env zsh
set -euo pipefail

repo="${0:A:h:h}"
export PATH="${repo}/tests/fixtures/bin:${PATH}"
export XDG_CONFIG_HOME="$(mktemp -d "${TMPDIR:-/tmp}/shask-smoke-config.XXXXXX")"
unset SHASK_MODEL
export SHASK_CONTEXT=1
export SHASK_BINDKEY=0

source "${repo}/shask.zsh"

[[ "$SHASK_KEY" == $'\ee' ]] || {
  print -u2 -r -- "expected Alt+E default key sequence"
  exit 1
}
ZDOTDIR="$XDG_CONFIG_HOME" SHASK_BINDKEY=1 zsh -ic '
  source "'"$repo"'/shask.zsh"
  [[ "$SHASK_KEY" == $'"'"'\ee'"'"' ]]
  bindkey -M main "$SHASK_KEY" | grep -Fq shask
' || {
  print -u2 -r -- "expected Alt+E binding in an interactive zsh"
  exit 1
}

[[ "$(shask --model)" == "openai-codex/gpt-5.4-mini" ]] || {
  print -u2 -r -- "expected default model"
  exit 1
}

mkdir -p "$XDG_CONFIG_HOME/shell-assist"
print -r -- "model=openai-codex/gpt-5.6-luna" > "$XDG_CONFIG_HOME/shell-assist/config"
unset SHASK_MODEL
source "${repo}/shask.zsh"
[[ "$SHASK_MODEL" == "openai-codex/gpt-5.6-luna" ]] || {
  print -u2 -r -- "expected legacy pai config fallback"
  exit 1
}
XDG_CONFIG_HOME="$XDG_CONFIG_HOME" SHASK_MODEL="new/model" zsh -dfc '
  source "'"$repo"'/shask.zsh"
  [[ "$SHASK_MODEL" == "new/model" ]]
' || {
  print -u2 -r -- "expected new model environment to override legacy config"
  exit 1
}

shask --model anthropic/claude-sonnet-4-5 >/dev/null
[[ "$(shask --model)" == "anthropic/claude-sonnet-4-5" ]] || {
  print -u2 -r -- "expected persisted model"
  exit 1
}
[[ -f "$XDG_CONFIG_HOME/shask/config" ]] || {
  print -u2 -r -- "expected model config file"
  exit 1
}
unset SHASK_MODEL
source "${repo}/shask.zsh"
[[ "$SHASK_MODEL" == "anthropic/claude-sonnet-4-5" ]] || {
  print -u2 -r -- "expected saved model after reload"
  exit 1
}
[[ "$("${repo}/bin/shask" --model google/gemini-2.5-pro)" == "shask: model set to google/gemini-2.5-pro" ]] || {
  print -u2 -r -- "expected standalone wrapper to save model"
  exit 1
}
[[ "$("${repo}/bin/pai" --model 2>/dev/null)" == "google/gemini-2.5-pro" ]] || {
  print -u2 -r -- "expected legacy pai wrapper compatibility"
  exit 1
}
unset SHASK_MODEL
source "${repo}/shask.zsh"
[[ "$SHASK_MODEL" == "google/gemini-2.5-pro" ]] || {
  print -u2 -r -- "expected wrapper-saved model after reload"
  exit 1
}

typeset -a spinner_updates=()
zle() {
  [[ "$1" == -R ]] && spinner_updates+=("$2")
  return 0
}
export PI_FIXTURE_DELAY=0.35
BUFFER="list files"
_shask_zle
unset PI_FIXTURE_DELAY
[[ "$BUFFER" == "ls -la" ]] || {
  print -u2 -r -- "expected Alt+E widget result"
  exit 1
}
(( $#spinner_updates >= 3 )) &&
  [[ "$spinner_updates[1]" == *"Generating command…"* ]] &&
  [[ "$spinner_updates[1]" != "$spinner_updates[2]" ]] || {
  print -u2 -r -- "expected multiple distinct animated spinner updates"
  exit 1
}

export PI_FIXTURE_FAIL=1
BUFFER="keep my request"
if _shask_zle 2>/dev/null; then
  print -u2 -r -- "expected failed generation"
  exit 1
fi
unset PI_FIXTURE_FAIL
[[ "$BUFFER" == "keep my request" ]] || {
  print -u2 -r -- "expected failed generation to restore the request"
  exit 1
}

err_file="${TMPDIR:-/tmp}/shask-smoke-$$.err"
: > "$err_file"
_shask_context_block >/dev/null 2>"$err_file"
if [[ -s "$err_file" ]]; then
  print -u2 -r -- "context block wrote stderr:"
  cat "$err_file" >&2
  exit 1
fi

generated="$(shask --print list files)"
[[ "$generated" == "ls -la" ]] || {
  print -u2 -r -- "expected sanitized command 'ls -la', got: $generated"
  exit 1
}

description="$(shask --describe 'ls -la')"
[[ "$description" == "Lists files with details." ]] || {
  print -u2 -r -- "unexpected description: $description"
  exit 1
}

install_home="$(mktemp -d "${TMPDIR:-/tmp}/shask-install-smoke.XXXXXX")"
mkdir -p "$install_home/.local/share/shell-assist/bin" "$install_home/.local/bin"
print -r -- legacy > "$install_home/.local/share/shell-assist/shell-assist.zsh"
print -r -- legacy > "$install_home/.local/share/shell-assist/bin/pai"
ln -s "$install_home/.local/share/shell-assist/bin/pai" "$install_home/.local/bin/pai"
cat > "$install_home/.zshrc" <<'EOF'
# >>> shell-assist >>>
source "$HOME/.local/share/shell-assist/shell-assist.zsh"
# <<< shell-assist <<<
echo "documentation: source $HOME/.local/share/shell-assist/shell-assist.zsh"
EOF
HOME="$install_home" \
ZDOTDIR="$install_home" \
SHASK_INSTALL_DIR="$install_home/.local/share/shask" \
SHASK_BIN_DIR="$install_home/.local/bin" \
SHASK_LEGACY_INSTALL_DIR="$install_home/.local/share/shell-assist" \
zsh "$repo/install.sh" >/dev/null
[[ -L "$install_home/.local/bin/shask" && -L "$install_home/.local/bin/pai" ]] || {
  print -u2 -r -- "expected shask and compatibility command links"
  exit 1
}
grep -Fq '# >>> shask >>>' "$install_home/.zshrc" && ! grep -Fq '# >>> shell-assist >>>' "$install_home/.zshrc" || {
  print -u2 -r -- "expected zshrc integration migration"
  exit 1
}
grep -Fq 'documentation: source $HOME/.local/share/shell-assist/shell-assist.zsh' "$install_home/.zshrc" || {
  print -u2 -r -- "expected documentation mentioning the legacy path to remain"
  exit 1
}
[[ ! -e "$install_home/.local/share/shell-assist" ]] || {
  print -u2 -r -- "expected legacy install migration"
  exit 1
}

malformed_home="$(mktemp -d "${TMPDIR:-/tmp}/shask-malformed-smoke.XXXXXX")"
cat > "$malformed_home/.zshrc" <<'EOF'
# >>> shell-assist >>>
source "$HOME/.local/share/shell-assist/shell-assist.zsh"
IMPORTANT_AFTER_MALFORMED_BLOCK=1
EOF
if HOME="$malformed_home" ZDOTDIR="$malformed_home" zsh "$repo/install.sh" >/dev/null 2>&1; then
  print -u2 -r -- "expected malformed zshrc migration to fail safely"
  exit 1
fi
grep -Fq 'IMPORTANT_AFTER_MALFORMED_BLOCK=1' "$malformed_home/.zshrc" || {
  print -u2 -r -- "expected malformed zshrc contents to be preserved"
  exit 1
}
[[ ! -e "$malformed_home/.local/share/shask" && ! -e "$malformed_home/.local/bin/shask" ]] || {
  print -u2 -r -- "expected malformed zshrc to fail before installation"
  exit 1
}

unowned_home="$(mktemp -d "${TMPDIR:-/tmp}/shask-unowned-smoke.XXXXXX")"
mkdir -p "$unowned_home/.local/share/shell-assist"
print -r -- user-data > "$unowned_home/.local/share/shell-assist/keep"
HOME="$unowned_home" ZDOTDIR="$unowned_home" zsh "$repo/install.sh" --uninstall >/dev/null
[[ -f "$unowned_home/.local/share/shell-assist/keep" ]] || {
  print -u2 -r -- "expected unrecognized legacy directory to remain untouched"
  exit 1
}

print -r -- "smoke ok"
