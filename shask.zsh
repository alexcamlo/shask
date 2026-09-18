# Ask your shell. Powered by Pi, for zsh.
# Source this file from ~/.zshrc to get:
#   - shask: confirmed command runner
#   - Alt+E: open the same confirmation menu for the current buffer

# Configuration is persisted by `shask --model <provider/model>` in:
#   ${XDG_CONFIG_HOME:-$HOME/.config}/shask/config
#   SHASK_CONTEXT=basic          # none | basic | git
#   SHASK_BINDKEY=1              # set 0 to skip key binding
#   SHASK_KEY=$'\ee'             # Alt+E by default
#   SHASK_MAX_STATUS_LINES=40

: ${SHASK_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/shask/config}
: ${SHASK_CONTEXT:=basic}
: ${SHASK_BINDKEY:=1}
: ${SHASK_MAX_STATUS_LINES:=40}
: ${SHASK_KEY:=$'\ee'}

_shask_has() {
  command -v "$1" >/dev/null 2>&1
}

_shask_usage() {
  cat <<'EOF'
Usage:
  shask <natural language request>
  shask --print <natural language request>
  shask --describe <shell command>
  shask --model [provider/model]

Examples:
  shask find all pdfs bigger than 10mb under downloads
  shask --print show listening tcp ports
  shask --describe 'find . -name "*.log" -mtime +7 -print'
  shask --model anthropic/claude-sonnet-4-5

Default mode opens a confirmation menu:
  execute | revise | describe | copy | quit

Configuration:
  shask --model <id> persists the model in
  ${XDG_CONFIG_HOME:-$HOME/.config}/shask/config
  shask --model prints the active model.

Environment (optional):
  SHASK_CONFIG      override saved-config path
  SHASK_MODEL       fallback model when no saved model exists
  SHASK_CONTEXT     none/basic/git context level
  SHASK_BINDKEY     1/0 bind Alt+E when sourced interactively
  SHASK_KEY         zle key sequence, default Alt+E
EOF
}

_shask_model_from_config() {
  local config_path="$1" line model=""
  [[ -r "$config_path" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == model=* ]] && model="${line#model=}"
  done < "$config_path"

  [[ -n "$model" ]] && print -r -- "$model"
}

_shask_set_model() {
  emulate -L zsh

  local model="$1" config_dir tmp
  if [[ -z "$model" || "$model" == *[[:space:]]* ]]; then
    print -u2 -r -- "shask: model must be a non-empty provider/model id"
    return 2
  fi

  config_dir="${SHASK_CONFIG:h}"
  mkdir -p "$config_dir" || return $?
  tmp="${config_dir}/.${SHASK_CONFIG:t}.$$"
  {
    print -r -- "# Managed by shask --model."
    print -r -- "model=$model"
  } > "$tmp" || return $?
  mv "$tmp" "$SHASK_CONFIG" || return $?

  SHASK_MODEL="$model"
  print -r -- "shask: model set to $model"
}

_shask_load_model() {
  local saved_model
  if saved_model="$(_shask_model_from_config "$SHASK_CONFIG" 2>/dev/null)"; then
    SHASK_MODEL="$saved_model"
  elif [[ -z "${SHASK_MODEL:-}" ]]; then
    SHASK_MODEL="openai-codex/gpt-5.6-luna:low"
  fi
}

_shask_load_model

_shask_os_label() {
  [[ -n "${SHASK_OS_LABEL:-}" ]] && { print -r -- "$SHASK_OS_LABEL"; return; }

  local kernel="$(uname -s 2>/dev/null || print -r -- unknown)"
  if [[ "$kernel" == Darwin ]] && _shask_has sw_vers; then
    print -r -- "macOS $(sw_vers -productVersion 2>/dev/null || print -r -- unknown) ($(uname -m))"
  else
    print -r -- "$kernel $(uname -r 2>/dev/null || print -r -- unknown) ($(uname -m 2>/dev/null || print -r -- unknown))"
  fi
}

_shask_context_block() {
  case "${SHASK_CONTEXT}" in
    0|none|off|false|no) return 0 ;;
  esac

  print -r -- "Working directory: $PWD"

  [[ "${SHASK_CONTEXT}" != git ]] && return 0

  if _shask_has git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local root branch git_status_text
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    branch="$(git branch --show-current 2>/dev/null || true)"
    git_status_text="$(git status --short 2>/dev/null | head -n "${SHASK_MAX_STATUS_LINES}")"
    print -r -- "Git root: ${root:-unknown}"
    print -r -- "Git branch: ${branch:-detached-or-unknown}"
    if [[ -n "$git_status_text" ]]; then
      print -r -- "Git status --short:"
      print -r -- "$git_status_text"
    else
      print -r -- "Git status --short: clean"
    fi
  fi
}

_shask_generation_system_prompt() {
  cat <<EOF
Provide only zsh commands for $(_shask_os_label) without any description.
Ensure the output is a valid zsh command.
If there is a lack of details, provide the most logical safe solution.
If multiple steps are required, try to combine them using '&&'.
Output only plain text without any markdown formatting.

Target environment:
- Shell: zsh ${ZSH_VERSION:-unknown}
$(_shask_context_block)

Additional rules:
- Never paste the natural-language request into the command unless it is genuinely data to search for, print, or pass as an argument.
- For questions asking "how many", "count", or "number of", default to Finder-like, non-recursive counts for a folder unless the user says recursively, all, under, inside subfolders, or similar.
- For "how many files are in FOLDER", count immediate regular files only: find FOLDER -maxdepth 1 -type f | wc -l
- For "how many items are in FOLDER", count immediate visible Finder-like items: find FOLDER -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l
- For recursive requests such as "all files under FOLDER" or "including subfolders", use recursive find: find FOLDER -type f | wc -l
- Quote paths and user data safely. Expand ~ to the user's home path when helpful.
- For name searches, default to case-insensitive substring matching such as -iname '*review-loop*' and do not add -type f unless the user explicitly asks for regular files. This includes extension variants and symlinks.
- Use utilities and flags available on the detected target OS; prefer its built-in tools unless the user clearly asks for another tool.
- For opening a file or URL, use open on macOS, xdg-open (or gio open) on Linux, and the target OS's native equivalent elsewhere.
- Never emit a command from another OS when the target OS has a native equivalent.
- Do not invent files, directories, flags, or commands when a standard target-OS equivalent exists.
- Avoid irreversible destructive commands. Prefer trash/mv-to-Trash patterns over rm/rmdir unless the user explicitly asks for permanent deletion.

Examples:
- Request: tell me how many files are in ~/Downloads folder
  Command: find "$HOME/Downloads" -maxdepth 1 -type f | wc -l
- Request: tell me how many items are in ~/Downloads folder
  Command: find "$HOME/Downloads" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l
- Request: count all files under ~/Downloads including subfolders
  Command: find "$HOME/Downloads" -type f | wc -l
- Request: find all pdfs bigger than 10mb under Downloads
  Command: find "$HOME/Downloads" -type f -iname '*.pdf' -size +10M -print
- Request: find a file with name review-loop
  Command: find . -iname '*review-loop*' -print
EOF
}

_shask_describe_system_prompt() {
  cat <<'EOF'
Provide a terse, single-sentence description of the given zsh command.
Describe each important argument and option.
Keep the response under about 80 words.
Use markdown only if it improves readability.
EOF
}

_shask_call_pi() {
  local system_prompt="$1"
  local user_message="$2"

  if ! _shask_has pi; then
    print -u2 -r -- "shask: pi command not found in PATH"
    return 127
  fi

  [[ -t 2 ]] && print -u2 -r -- "shask: asking Pi…"

  pi \
    --model "${SHASK_MODEL}" \
    --system-prompt "$system_prompt" \
    --no-extensions \
    --no-tools \
    -p \
    --no-session \
    "$user_message"
}

_shask_sanitize_command() {
  perl -0pe 's/\r//g; s/^\s*```[a-zA-Z0-9_-]*\s*\n//; s/(?:^|\n)```\s*$//; s/^\s+//; s/\s+$//'
}

_shask_generate() {
  emulate -L zsh
  setopt pipefail

  local request="$1"
  local system_prompt output
  system_prompt="$(_shask_generation_system_prompt)"
  output="$(_shask_call_pi "$system_prompt" "$request")" || return $?
  output="$(print -r -- "$output" | _shask_sanitize_command)" || return $?
  if [[ -z "$output" ]]; then
    print -u2 -r -- "shask: pi generated an empty command"
    return 1
  fi
  print -r -- "$output"
}

_shask_describe() {
  emulate -L zsh
  local command_text="$1"
  local system_prompt
  system_prompt="$(_shask_describe_system_prompt)"
  _shask_call_pi "$system_prompt" "$command_text"
}

_shask_copy() {
  local command_text="$1"
  if _shask_has pbcopy; then
    print -rn -- "$command_text" | pbcopy
  elif _shask_has wl-copy; then
    print -rn -- "$command_text" | wl-copy
  elif _shask_has xclip; then
    print -rn -- "$command_text" | xclip -selection clipboard
  elif _shask_has xsel; then
    print -rn -- "$command_text" | xsel --clipboard --input
  else
    print -u2 -r -- "shask: no supported clipboard command found"
    return 127
  fi
}

_shask_record_history() {
  emulate -L zsh
  local command_text="$1"

  # Add the generated command to the current zsh history, then ask zsh to append
  # new entries to HISTFILE when possible. This records the generated command,
  # not merely the `shask ...` invocation.
  print -sr -- "$command_text"
  fc -AI 2>/dev/null || true
}

_shask_prompt_request() {
  local request
  read -r "request?What should the shell command do? "
  print -r -- "$request"
}

_shask_menu() {
  emulate -L zsh
  local request="$1"
  local command_text revision choice exit_code action_prompt

  if [[ -z "$request" ]]; then
    request="$(_shask_prompt_request)"
  fi
  if [[ -z "$request" ]]; then
    print -u2 -r -- "shask: empty request"
    return 2
  fi

  command_text="$(_shask_generate "$request")" || return $?
  action_prompt="%f%k%s%F{magenta}e%f%F{grey}xecute | %f%F{magenta}r%f%F{grey}evise | %f%F{magenta}d%f%F{grey}escribe | %f%F{magenta}c%f%F{grey}opy | %f%F{magenta}q%f%F{grey}uit%f%k%s: "

  while true; do
    print -Pn -- "%F{yellow}"
    print -r -- "$command_text"
    print -Pn -- "%f"
    print -Pn -- "$action_prompt"
    if ! read -k 1 choice; then
      print
      return 0
    fi
    print -n -- $'\r\e[2K'

    case "$choice" in
      e|E)
        eval "$command_text"
        exit_code=$?
        if (( exit_code == 0 )); then
          _shask_record_history "$command_text"
        fi
        return $exit_code
        ;;
      r|R)
        read -r "revision?Enter revision: " || return 0
        if [[ -n "$revision" ]]; then
          request+=$'\n'
          request+="Previous command: $command_text"
          request+=$'\n'
          request+="Revision: $revision"
          command_text="$(_shask_generate "$request")" || return $?
        fi
        ;;
      d|D)
        _shask_describe "$command_text"
        print
        ;;
      c|C)
        _shask_copy "$command_text" && print -r -- "Copied."
        ;;
      q|Q|$'\e')
        return 0
        ;;
      *)
        print -r -- "Unknown choice."
        ;;
    esac
  done
}

shask() {
  emulate -L zsh

  local mode="menu"
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        _shask_usage
        return 0
        ;;
      -p|--print|--dry-run)
        mode="print"
        shift
        ;;
      --describe)
        mode="describe"
        shift
        ;;
      --model)
        shift
        if (( $# == 0 )); then
          print -r -- "$SHASK_MODEL"
          return 0
        fi
        _shask_set_model "$1"
        return $?
        ;;
      --)
        shift
        break
        ;;
      -*)
        print -u2 -r -- "shask: unknown option: $1"
        print -u2 -r -- "Try: shask --help"
        return 2
        ;;
      *)
        break
        ;;
    esac
  done

  local text="$*"
  case "$mode" in
    print)
      if [[ -z "$text" ]]; then
        text="$(_shask_prompt_request)"
      fi
      _shask_generate "$text"
      ;;
    describe)
      if [[ -z "$text" ]]; then
        read -r "text?Command to describe: "
      fi
      _shask_describe "$text"
      ;;
    *)
      _shask_menu "$text"
      ;;
  esac
}

_shask_zle() {
  # Quote the request as data, then let zsh run the normal confirmation menu.
  BUFFER="shask -- ${(q)BUFFER}"
  zle accept-line
}

if [[ -o interactive ]] && (( ${+widgets} )); then
  zle -N shask _shask_zle
  if [[ "${SHASK_BINDKEY}" != 0 ]]; then
    bindkey "$SHASK_KEY" shask
  fi
fi
