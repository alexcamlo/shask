#!/usr/bin/env zsh
# Install shask for zsh on macOS.
#
# Remote install:
#   curl -fsSL https://raw.githubusercontent.com/alexcamlo/shask/main/install.sh | zsh
#
# Local install:
#   ./install.sh

set -euo pipefail

: ${SHASK_REPO_URL:=${SHELL_ASSIST_REPO_URL:-https://github.com/alexcamlo/shask.git}}
: ${SHASK_REF:=${SHELL_ASSIST_REF:-main}}
: ${SHASK_INSTALL_DIR:=${SHELL_ASSIST_INSTALL_DIR:-$HOME/.local/share/shask}}
: ${SHASK_BIN_DIR:=${SHELL_ASSIST_BIN_DIR:-$HOME/.local/bin}}
: ${SHASK_LEGACY_INSTALL_DIR:=$HOME/.local/share/shell-assist}

install_script_path="${0:A}"
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
  SHASK_REPO_URL     Git repo URL (default: ${SHASK_REPO_URL})
  SHASK_REF          Git ref to install (default: ${SHASK_REF})
  SHASK_INSTALL_DIR  Install dir (default: ${SHASK_INSTALL_DIR})
  SHASK_BIN_DIR      Bin dir for shask symlink (default: ${SHASK_BIN_DIR})
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
    print -u2 -r -- "shask install: missing required command: $1"
    exit 1
  fi
}

source_path_for_zshrc() {
  local source_file="$SHASK_INSTALL_DIR/shask.zsh"
  if [[ "$source_file" == "$HOME/"* ]]; then
    source_file="\$HOME/${source_file#$HOME/}"
  fi
  print -r -- "$source_file"
}

zshrc_block() {
  local source_path
  source_path="$(source_path_for_zshrc)"
  cat <<EOF
# >>> shask >>>
source "$source_path"
# <<< shask <<<
EOF
}

validate_zshrc_blocks() {
  awk '
    $0 == "# >>> shask >>>" || $0 == "# >>> shell-assist >>>" {
      if (open) exit 1
      open=1
      next
    }
    $0 == "# <<< shask <<<" || $0 == "# <<< shell-assist <<<" {
      if (!open) exit 1
      open=0
    }
    END { if (open) exit 1 }
  ' "$zshrc"
}

remove_zshrc_block() {
  (( update_zshrc )) || return 0
  [[ -f "$zshrc" ]] || return 0

  local tmp="${zshrc}.shask.$$"
  if ! validate_zshrc_blocks; then
    print -u2 -r -- "shask install: malformed managed block in $zshrc; refusing to modify it"
    return 1
  fi
  if (( dry_run )); then
    say "Would remove existing shask/shell-assist blocks from $zshrc"
    return 0
  fi

  awk -v home="$HOME" '
    function is_legacy_source(line, path) {
      path = home "/.local/share/shell-assist/shell-assist.zsh"
      return line == "source \"" path "\"" ||
             line == "[ -f \"" path "\" ] && source \"" path "\""
    }
    $0 == "# >>> shask >>>" || $0 == "# >>> shell-assist >>>" { skip=1; next }
    $0 == "# <<< shask <<<" || $0 == "# <<< shell-assist <<<" { skip=0; next }
    !skip && !is_legacy_source($0) { print }
  ' "$zshrc" > "$tmp"
  mv "$tmp" "$zshrc"
}

write_zshrc_block() {
  (( update_zshrc )) || return 0

  local block
  block="$(zshrc_block)"

  if (( dry_run )); then
    say "Would replace existing shask/shell-assist integration in $zshrc with:"
    print -r -- "$block"
    return 0
  fi

  touch "$zshrc"
  remove_zshrc_block
  {
    print
    print -r -- "$block"
  } >> "$zshrc"
}

is_legacy_install() {
  [[ -f "$SHASK_LEGACY_INSTALL_DIR/shell-assist.zsh" && -f "$SHASK_LEGACY_INSTALL_DIR/bin/pai" ]]
}

move_to_trash() {
  local item_path="$1"
  [[ -e "$item_path" || -L "$item_path" ]] || return 0

  local trash_dir="$HOME/.Trash"
  local name timestamp target
  timestamp="$(date +%Y%m%d%H%M%S)"
  name="${item_path:t}"
  target="$trash_dir/${name}.shask.$timestamp"

  if (( dry_run )); then
    say "Would move $item_path to $target"
    return 0
  fi

  mkdir -p "$trash_dir"
  mv "$item_path" "$target"
}

install_from_local_checkout() {
  local source_dir="$1"

  run mkdir -p "$SHASK_INSTALL_DIR/bin"
  run cp "$source_dir/shask.zsh" "$SHASK_INSTALL_DIR/shask.zsh"
  run cp "$source_dir/bin/shask" "$SHASK_INSTALL_DIR/bin/shask"
  run cp "$source_dir/bin/pai" "$SHASK_INSTALL_DIR/bin/pai"
  run chmod +x "$SHASK_INSTALL_DIR/bin/shask" "$SHASK_INSTALL_DIR/bin/pai"
}

install_from_git() {
  need git

  if [[ -d "$SHASK_INSTALL_DIR/.git" ]]; then
    run git -C "$SHASK_INSTALL_DIR" fetch --depth=1 origin "$SHASK_REF"
    run git -C "$SHASK_INSTALL_DIR" checkout -q FETCH_HEAD
  elif [[ -d "$SHASK_INSTALL_DIR" && -n "$(command ls -A "$SHASK_INSTALL_DIR" 2>/dev/null)" ]]; then
    say "Moving existing non-git install aside: $SHASK_INSTALL_DIR"
    move_to_trash "$SHASK_INSTALL_DIR"
    run mkdir -p "${SHASK_INSTALL_DIR:h}"
    run git clone --depth=1 --branch "$SHASK_REF" "$SHASK_REPO_URL" "$SHASK_INSTALL_DIR"
  else
    run mkdir -p "${SHASK_INSTALL_DIR:h}"
    run git clone --depth=1 --branch "$SHASK_REF" "$SHASK_REPO_URL" "$SHASK_INSTALL_DIR"
  fi
}

link_command() {
  local name="$1"
  local target="$SHASK_INSTALL_DIR/bin/$name"
  local link="$SHASK_BIN_DIR/$name"

  run mkdir -p "$SHASK_BIN_DIR"

  if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
    return 0
  fi

  if [[ "$name" == pai && ( -e "$link" || -L "$link" ) ]]; then
    local existing_target=""
    [[ -L "$link" ]] && existing_target="$(readlink "$link")"
    if [[ "$existing_target" != "$SHASK_LEGACY_INSTALL_DIR/bin/pai" ]]; then
      say "Leaving existing non-shask command untouched: $link"
      return 0
    fi
  fi

  if [[ -e "$link" || -L "$link" ]]; then
    move_to_trash "$link"
  fi

  run ln -s "$target" "$link"
}

install_shask() {
  local script_path="$install_script_path"
  local script_dir="${script_path:h}"

  if (( update_zshrc )) && [[ -f "$zshrc" ]] && ! validate_zshrc_blocks; then
    print -u2 -r -- "shask install: malformed managed block in $zshrc; refusing to install"
    return 1
  fi

  if [[ -f "$script_path" && "${script_path:t}" == "install.sh" && -f "$script_dir/shask.zsh" && -f "$script_dir/bin/shask" ]]; then
    say "Installing from local checkout: $script_dir"
    install_from_local_checkout "$script_dir"
  else
    say "Installing from git: $SHASK_REPO_URL#$SHASK_REF"
    install_from_git
  fi

  link_command shask
  link_command pai
  write_zshrc_block

  if [[ "$SHASK_LEGACY_INSTALL_DIR" != "$SHASK_INSTALL_DIR" && ( -e "$SHASK_LEGACY_INSTALL_DIR" || -L "$SHASK_LEGACY_INSTALL_DIR" ) ]]; then
    if is_legacy_install; then
      say "Moving legacy shell-assist install aside: $SHASK_LEGACY_INSTALL_DIR"
      move_to_trash "$SHASK_LEGACY_INSTALL_DIR"
    else
      say "Leaving unrecognized legacy path untouched: $SHASK_LEGACY_INSTALL_DIR"
    fi
  fi

  say "shask installed. Restart zsh or run:"
  say "  source \"$(source_path_for_zshrc)\""
  say "Then try:"
  say "  shask list files"
}

remove_owned_command_link() {
  local name="$1" link="$SHASK_BIN_DIR/$1" existing_target=""
  [[ -L "$link" ]] || return 0
  existing_target="$(readlink "$link")"
  if [[ "$existing_target" == "$SHASK_INSTALL_DIR/bin/$name" || "$existing_target" == "$SHASK_LEGACY_INSTALL_DIR/bin/pai" ]]; then
    move_to_trash "$link"
  fi
}

uninstall_shask() {
  remove_zshrc_block
  remove_owned_command_link shask
  remove_owned_command_link pai
  move_to_trash "$SHASK_INSTALL_DIR"
  if [[ "$SHASK_LEGACY_INSTALL_DIR" != "$SHASK_INSTALL_DIR" ]] && is_legacy_install; then
    move_to_trash "$SHASK_LEGACY_INSTALL_DIR"
  fi
  say "shask uninstalled. Restart zsh or remove it from this shell session manually."
}

if (( uninstall )); then
  uninstall_shask
else
  install_shask
fi
