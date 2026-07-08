# shell-assist

Pi-powered zsh shell assistant for macOS. Generate, review, revise, explain,
copy, and safely execute shell commands from natural language.

`pai` recreates the shell-assistant workflow from
[`sigoden/aichat`](https://github.com/sigoden/aichat), but uses
[`pi`](https://github.com/earendil-works/pi-coding-agent) as the LLM backend.

## Features

- Natural language → valid zsh command
- macOS 26+ target environment
- Confirmation before execution
- Revise generated commands without starting over
- Explain generated or existing shell commands
- Copy commands to the clipboard with `pbcopy`
- Add successfully executed generated commands to zsh history
- Optional `Alt+E` zle widget that replaces the current prompt buffer
- Uses `pi --system-prompt` so shell-assistant instructions are sent as a real system prompt

## Requirements

- macOS 26+
- zsh
- `pi` available on `PATH`
- `pbcopy` for clipboard support (built into macOS)

## Quick start

Clone the repo, then source the zsh integration:

```sh
git clone <repo-url> shell-assist
cd shell-assist
source ./shell-assist.zsh
```

Ask for a command:

```sh
pai find all pdfs bigger than 10mb under Downloads
```

`pai` will generate a command, then ask what to do:

```text
execute | revise | describe | copy | quit:
```

The first letter of each action is highlighted. Press:

- `e` execute
- `r` revise
- `d` describe
- `c` copy
- `q` quit

## Install permanently

Print the `.zshrc` source line:

```sh
scripts/install-zsh --print
```

Append it to `~/.zshrc`:

```sh
scripts/install-zsh --write
```

For chezmoi or another dotfile manager, add the printed source line to your
managed zsh config instead of using `--write`.

## Usage

### Confirmed execution

```sh
pai tell me how many items are in ~/Downloads folder
```

Example output:

```sh
find "$HOME/Downloads" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l
```

Then choose `execute`, `revise`, `describe`, `copy`, or `quit`.

### Generate only

```sh
pai --print show listening tcp ports
```

### Explain a command

```sh
pai --describe 'find . -name "*.log" -mtime +7 -print'
```

### Alt+E prompt replacement

When `shell-assist.zsh` is sourced in an interactive zsh session, `Alt+E` is
bound automatically.

1. Type a natural-language request at your shell prompt.
2. Press `Alt+E`.
3. The prompt buffer is replaced with a generated command.
4. Review or edit the command.
5. Press Enter yourself to run it.

This mirrors AIChat's shell integration and never auto-executes.

## Configuration

Set these before sourcing `shell-assist.zsh`:

```sh
export PI_SHELL_ASSIST_MODEL=openai-codex/gpt-5.4-mini
export PI_SHELL_ASSIST_CONTEXT=basic   # none | basic | git
export PI_SHELL_ASSIST_BINDKEY=1       # 0 disables Alt+E binding
export PI_SHELL_ASSIST_KEY=$'\ee'      # Alt+E
```

Context modes:

- `none`: no cwd/git context
- `basic`: OS, zsh version, and current directory
- `git`: `basic` plus git root, branch, and short status

No file contents are sent to `pi` by default.

## Backend

Default generation call shape:

```sh
pi \
  --model "$PI_SHELL_ASSIST_MODEL" \
  --system-prompt '<shell assistant prompt>' \
  --no-extensions \
  --no-tools \
  -p \
  --no-session \
  '<natural language request>'
```

The system prompt starts from AIChat's `%shell%` role and adds macOS/zsh-specific
safety rules and Finder-like counting behavior.

## Executable wrapper

`bin/pai` is included for convenience:

```sh
export PATH="$PWD/bin:$PATH"
pai --print list files
```

For full shell behavior, prefer sourcing `shell-assist.zsh`. The wrapper runs in
a child shell, so generated commands like `cd`, `export`, or `alias` cannot affect
your current terminal session.

## Safety notes

- Commands are not executed without explicit confirmation.
- The `Alt+E` widget only replaces your current prompt buffer.
- Destructive commands are discouraged in the prompt; review everything before executing.
- Successful generated commands are recorded in zsh history after execution.

## Development

Run smoke checks:

```sh
zsh -n shell-assist.zsh bin/pai scripts/install-zsh tests/smoke.zsh tests/fixtures/bin/pi
zsh tests/smoke.zsh
```
