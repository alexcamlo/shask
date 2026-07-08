#!/usr/bin/env zsh
# Install shell-assist for zsh on macOS.
#
# Remote install:
#   curl -fsSL https://raw.githubusercontent.com/alexcamlo/shell-assist/main/install.sh | zsh
#
# Local install:
#   ./install.sh

set -euo pipefail

: ${SHELL_ASSIST_REPO_URL:=https://github.com/alexcamlo/shell-assist.git}
: ${SHELL_ASSIST_REF:=main}
: ${SHELL_ASSIST_INSTALL_DIR:=$HOME/.local/share/shell-assist}
: ${SHELL_ASSIST_BIN_DIR:=$HOME/.local/bin}

zshrc="${ZDOTDIR:-$HOME}/.zshrc"
dry_run=0
uninstall=0
update_zshrc=1

usage() {
  cat <<EOF
Usage:
  install.sh [options]

Options:
  --dry-run       Print actions without changing files
  --uninstall     Remove zsh integration and move installed files to Trash
  --no-zshrc      Do not edit ~/.zshrc
  -h, --help      Show this help

Environment:
  SHELL_ASSIST_REPO_URL     Git repo URL (default: ${SHELL_ASSIST_REPO_URL})
  SHELL_ASSIST_REF          Git ref to install (default: ${SHELL_ASSIST_REF})
  SHELL_ASSIST_INSTALL_DIR  Install dir (default: ${SHELL_ASSIST_INSTALL_DIR})
  SHELL_ASSIST_BIN_DIR      Bin dir for pai symlink (default: ${SHELL_ASSIST_BIN_DIR})
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --uninstall) uninstall=1 ;;
    --no-zshrc) update_zshrc=0 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
  shift
done

say() {
  print -r -- "$*"
}

run() {
  if (( dry_run )); then
    print -r -- "+ $*"
  else
    "$@"
  fi
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    print -u2 -r -- "shell-assist install: missing required command: $1"
    exit 1
  fi
}

source_path_for_zshrc() {
  local path="$SHELL_ASSIST_INSTALL_DIR/shell-assist.zsh"
  if [[ "$path" == "$HOME/"* ]]; then
    path="\$HOME/${path#$HOME/}"
  fi
  print -r -- "$path"
}

zshrc_block() {
  local source_path
  source_path="$(source_path_for_zshrc)"
  cat <<EOF
# >>> shell-assist >>>
source "$source_path"
# <<< shell-assist <<<
EOF
}

write_zshrc_block() {
  (( update_zshrc )) || return 0

  local block tmp
  block="$(zshrc_block)"
  tmp="${zshrc}.shell-assist.$$"

  if (( dry_run )); then
    say "Would update $zshrc with:"
    print -r -- "$block"
    return 0
  fi

  touch "$zshrc"
  if grep -Fqx '# >>> shell-assist >>>' "$zshrc"; then
    awk '
      $0 == "# >>> shell-assist >>>" { print block; skip=1; next }
      $0 == "# <<< shell-assist <<<" { skip=0; next }
      !skip { print }
    ' block="$block" "$zshrc" > "$tmp"
    mv "$tmp" "$zshrc"
  else
    {
      print
      print -r -- "$block"
    } >> "$zshrc"
  fi
}

remove_zshrc_block() {
  (( update_zshrc )) || return 0
  [[ -f "$zshrc" ]] || return 0

  local tmp="${zshrc}.shell-assist.$$"
  if (( dry_run )); then
    say "Would remove shell-assist block from $zshrc"
    return 0
  fi

  awk '
    $0 == "# >>> shell-assist >>>" { skip=1; next }
    $0 == "# <<< shell-assist <<<" { skip=0; next }
    !skip { print }
  ' "$zshrc" > "$tmp"
  mv "$tmp" "$zshrc"
}

move_to_trash() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0

  local trash_dir="$HOME/.Trash"
  local name timestamp target
  timestamp="$(date +%Y%m%d%H%M%S)"
  name="${path:t}"
  target="$trash_dir/${name}.shell-assist.$timestamp"

  if (( dry_run )); then
    say "Would move $path to $target"
    return 0
  fi

  mkdir -p "$trash_dir"
  mv "$path" "$target"
}

install_from_local_checkout() {
  local source_dir="$1"

  run mkdir -p "$SHELL_ASSIST_INSTALL_DIR/bin"
  run cp "$source_dir/shell-assist.zsh" "$SHELL_ASSIST_INSTALL_DIR/shell-assist.zsh"
  run cp "$source_dir/bin/pai" "$SHELL_ASSIST_INSTALL_DIR/bin/pai"
  run chmod +x "$SHELL_ASSIST_INSTALL_DIR/bin/pai"
}

install_from_git() {
  need git

  if [[ -d "$SHELL_ASSIST_INSTALL_DIR/.git" ]]; then
    run git -C "$SHELL_ASSIST_INSTALL_DIR" fetch --depth=1 origin "$SHELL_ASSIST_REF"
    run git -C "$SHELL_ASSIST_INSTALL_DIR" checkout -q FETCH_HEAD
  elif [[ -d "$SHELL_ASSIST_INSTALL_DIR" && -n "$(command ls -A "$SHELL_ASSIST_INSTALL_DIR" 2>/dev/null)" ]]; then
    print -u2 -r -- "Install dir exists and is not a git checkout: $SHELL_ASSIST_INSTALL_DIR"
    print -u2 -r -- "Move it aside or set SHELL_ASSIST_INSTALL_DIR."
    exit 1
  else
    run mkdir -p "${SHELL_ASSIST_INSTALL_DIR:h}"
    run git clone --depth=1 --branch "$SHELL_ASSIST_REF" "$SHELL_ASSIST_REPO_URL" "$SHELL_ASSIST_INSTALL_DIR"
  fi
}

link_pai() {
  local target="$SHELL_ASSIST_INSTALL_DIR/bin/pai"
  local link="$SHELL_ASSIST_BIN_DIR/pai"

  run mkdir -p "$SHELL_ASSIST_BIN_DIR"

  if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
    return 0
  fi

  if [[ -e "$link" || -L "$link" ]]; then
    move_to_trash "$link"
  fi

  run ln -s "$target" "$link"
}

install_shell_assist() {
  local script_dir="${0:A:h}"

  if [[ -f "$script_dir/shell-assist.zsh" && -f "$script_dir/bin/pai" ]]; then
    say "Installing from local checkout: $script_dir"
    install_from_local_checkout "$script_dir"
  else
    say "Installing from git: $SHELL_ASSIST_REPO_URL#$SHELL_ASSIST_REF"
    install_from_git
  fi

  link_pai
  write_zshrc_block

  say "shell-assist installed. Restart zsh or run:"
  say "  source \"$(source_path_for_zshrc)\""
  say "Then try:"
  say "  pai list files"
}

uninstall_shell_assist() {
  remove_zshrc_block
  move_to_trash "$SHELL_ASSIST_BIN_DIR/pai"
  move_to_trash "$SHELL_ASSIST_INSTALL_DIR"
  say "shell-assist uninstalled. Restart zsh or remove it from this shell session manually."
}

if (( uninstall )); then
  uninstall_shell_assist
else
  install_shell_assist
fi
