# Pi-backed shell assistant for zsh on macOS.
# Source this file from ~/.zshrc to get:
#   - pai: confirmed shell-assistant command runner
#   - Alt+E: replace the current zle buffer with a generated command

# Config knobs:
#   PI_SHELL_ASSIST_MODEL=openai-codex/gpt-5.4-mini
#   PI_SHELL_ASSIST_CONTEXT=basic          # none | basic | git
#   PI_SHELL_ASSIST_BINDKEY=1              # set 0 to skip key binding
#   PI_SHELL_ASSIST_KEY=$'\ee'             # Alt+E by default
#   PI_SHELL_ASSIST_MAX_STATUS_LINES=40

: ${PI_SHELL_ASSIST_MODEL:=openai-codex/gpt-5.4-mini}
: ${PI_SHELL_ASSIST_CONTEXT:=basic}
: ${PI_SHELL_ASSIST_BINDKEY:=1}
: ${PI_SHELL_ASSIST_MAX_STATUS_LINES:=40}

_pi_shell_assist_has() {
  command -v "$1" >/dev/null 2>&1
}

_pi_shell_assist_usage() {
  cat <<'EOF'
Usage:
  pai <natural language request>
  pai --print <natural language request>
  pai --describe <shell command>

Examples:
  pai find all pdfs bigger than 10mb under downloads
  pai --print show listening tcp ports
  pai --describe 'find . -name "*.log" -mtime +7 -print'

Default mode opens a confirmation menu:
  execute | revise | describe | copy | quit

Environment:
  PI_SHELL_ASSIST_MODEL       pi model id (default: openai-codex/gpt-5.4-mini)
  PI_SHELL_ASSIST_CONTEXT     none/basic/git context level
  PI_SHELL_ASSIST_BINDKEY     1/0 bind Alt+E when sourced interactively
  PI_SHELL_ASSIST_KEY         zle key sequence, default Alt+E
EOF
}

_pi_shell_assist_os_label() {
  local product version build
  product="$(sw_vers -productName 2>/dev/null || print -r -- macOS)"
  version="$(sw_vers -productVersion 2>/dev/null || print -r -- unknown)"
  build="$(sw_vers -buildVersion 2>/dev/null || true)"
  print -r -- "$product $version${build:+ ($build)}"
}

_pi_shell_assist_context_block() {
  case "${PI_SHELL_ASSIST_CONTEXT}" in
    0|none|off|false|no) return 0 ;;
  esac

  print -r -- "Working directory: $PWD"

  [[ "${PI_SHELL_ASSIST_CONTEXT}" != git ]] && return 0

  if _pi_shell_assist_has git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local root branch git_status_text
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    branch="$(git branch --show-current 2>/dev/null || true)"
    git_status_text="$(git status --short 2>/dev/null | head -n "${PI_SHELL_ASSIST_MAX_STATUS_LINES}")"
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

_pi_shell_assist_generation_system_prompt() {
  cat <<EOF
Provide only zsh commands for $(_pi_shell_assist_os_label) without any description.
Ensure the output is a valid zsh command.
If there is a lack of details, provide the most logical safe solution.
If multiple steps are required, try to combine them using '&&'.
Output only plain text without any markdown formatting.

Target environment:
- Shell: zsh ${ZSH_VERSION:-unknown}
$(_pi_shell_assist_context_block)

Additional rules:
- Never paste the natural-language request into the command unless it is genuinely data to search for, print, or pass as an argument.
- For questions asking "how many", "count", or "number of", default to Finder-like, non-recursive counts for a folder unless the user says recursively, all, under, inside subfolders, or similar.
- For "how many files are in FOLDER", count immediate regular files only: find FOLDER -maxdepth 1 -type f | wc -l
- For "how many items are in FOLDER", count immediate visible Finder-like items: find FOLDER -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l
- For recursive requests such as "all files under FOLDER" or "including subfolders", use recursive find: find FOLDER -type f | wc -l
- Quote paths and user data safely. Expand ~ to the user's home path when helpful.
- Prefer built-in macOS/BSD utilities unless the user clearly asks for another tool.
- Do not invent files, directories, flags, or commands when a standard macOS equivalent exists.
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
EOF
}

_pi_shell_assist_describe_system_prompt() {
  cat <<'EOF'
Provide a terse, single-sentence description of the given zsh command.
Describe each important argument and option.
Keep the response under about 80 words.
Use markdown only if it improves readability.
EOF
}

_pi_shell_assist_call_pi() {
  local system_prompt="$1"
  local user_message="$2"

  if ! _pi_shell_assist_has pi; then
    print -u2 -r -- "pai: pi command not found in PATH"
    return 127
  fi

  command pi \
    --model "${PI_SHELL_ASSIST_MODEL}" \
    --system-prompt "$system_prompt" \
    --no-extensions \
    --no-tools \
    -p \
    --no-session \
    "$user_message"
}

_pi_shell_assist_sanitize_command() {
  perl -0pe 's/\r//g; s/^\s*```[a-zA-Z0-9_-]*\s*\n//; s/\n```\s*$//; s/^\s+//; s/\s+$//'
}

_pi_shell_assist_generate() {
  emulate -L zsh
  setopt pipefail

  local request="$1"
  local system_prompt output
  system_prompt="$(_pi_shell_assist_generation_system_prompt)"
  output="$(_pi_shell_assist_call_pi "$system_prompt" "$request")" || return $?
  print -r -- "$output" | _pi_shell_assist_sanitize_command
}

_pi_shell_assist_describe() {
  emulate -L zsh
  local command_text="$1"
  local system_prompt
  system_prompt="$(_pi_shell_assist_describe_system_prompt)"
  _pi_shell_assist_call_pi "$system_prompt" "$command_text"
}

_pi_shell_assist_copy() {
  local command_text="$1"
  if ! _pi_shell_assist_has pbcopy; then
    print -u2 -r -- "pai: pbcopy command not found"
    return 127
  fi
  print -rn -- "$command_text" | pbcopy
}

_pi_shell_assist_record_history() {
  emulate -L zsh
  local command_text="$1"

  # Add the generated command to the current zsh history, then ask zsh to append
  # new entries to HISTFILE when possible. This records the generated command,
  # not merely the `pai ...` invocation.
  print -sr -- "$command_text"
  fc -AI 2>/dev/null || true
}

_pi_shell_assist_prompt_request() {
  local request
  read -r "request?What should the shell command do? "
  print -r -- "$request"
}

_pi_shell_assist_menu() {
  emulate -L zsh
  local request="$1"
  local command_text revision choice exit_code action_prompt

  if [[ -z "$request" ]]; then
    request="$(_pi_shell_assist_prompt_request)"
  fi
  if [[ -z "$request" ]]; then
    print -u2 -r -- "pai: empty request"
    return 2
  fi

  command_text="$(_pi_shell_assist_generate "$request")" || return $?
  if [[ -z "$command_text" ]]; then
    print -u2 -r -- "pai: pi generated an empty command"
    return 1
  fi

  action_prompt="%F{cyan}e%f%F{244}xecute | %f%F{cyan}r%f%F{244}evise | %f%F{cyan}d%f%F{244}escribe | %f%F{cyan}c%f%F{244}opy | %f%F{cyan}q%f%F{244}uit%f: "

  while true; do
    print -P -- "%F{214}${command_text}%f"
    print -Pn -- "$action_prompt"
    read -sk 1 choice
    print

    case "$choice" in
      e|E)
        eval "$command_text"
        exit_code=$?
        if (( exit_code == 0 )); then
          _pi_shell_assist_record_history "$command_text"
        fi
        return $exit_code
        ;;
      r|R)
        read -r "revision?Enter revision: "
        if [[ -n "$revision" ]]; then
          request+=$'\n'
          request+="Previous command: $command_text"
          request+=$'\n'
          request+="Revision: $revision"
          command_text="$(_pi_shell_assist_generate "$request")" || return $?
        fi
        ;;
      d|D)
        _pi_shell_assist_describe "$command_text"
        print
        ;;
      c|C)
        _pi_shell_assist_copy "$command_text" && print -r -- "Copied."
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

pai() {
  emulate -L zsh

  local mode="menu"
  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        _pi_shell_assist_usage
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
      --)
        shift
        break
        ;;
      -*)
        print -u2 -r -- "pai: unknown option: $1"
        print -u2 -r -- "Try: pai --help"
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
        text="$(_pi_shell_assist_prompt_request)"
      fi
      _pi_shell_assist_generate "$text"
      ;;
    describe)
      if [[ -z "$text" ]]; then
        read -r "text?Command to describe: "
      fi
      _pi_shell_assist_describe "$text"
      ;;
    *)
      _pi_shell_assist_menu "$text"
      ;;
  esac
}

_pi_shell_assist_zle() {
  emulate -L zsh

  if [[ -z "$BUFFER" ]]; then
    zle -M "Type a natural-language request, then press Alt+E."
    return 0
  fi

  local old="$BUFFER"
  local generated
  BUFFER+="⌛"
  CURSOR=${#BUFFER}
  zle -I
  zle redisplay

  if generated="$(_pi_shell_assist_generate "$old")" && [[ -n "$generated" ]]; then
    BUFFER="$generated"
    CURSOR=${#BUFFER}
    zle -M "Generated command. Press Enter to run, or edit first."
  else
    BUFFER="$old"
    CURSOR=${#BUFFER}
    zle -M "pi shell-assist failed"
    return 1
  fi
}

if [[ -o interactive ]] && (( ${+widgets} )); then
  zle -N pi-shell-assist _pi_shell_assist_zle
  if [[ "${PI_SHELL_ASSIST_BINDKEY}" != 0 ]]; then
    bindkey "${PI_SHELL_ASSIST_KEY:-$'\ee'}" pi-shell-assist
  fi
fi
