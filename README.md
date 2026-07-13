# shask

<p align="center">
  <img src="Icon-iOS-Default-1024x1024@1x.png" alt="shask icon" width="160">
</p>

**Ask your shell. Powered by Pi.**

Pi-powered zsh shell assistant for macOS. Generate, review, revise, explain,
copy, and safely execute shell commands from natural language.

`shask` recreates the shell-assistant workflow from
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
- Animated Unicode spinner while the `Alt+E` request is generated
- Uses `pi --system-prompt` so shell-assistant instructions are sent as a real system prompt

## Requirements

- macOS 26+
- zsh
- `pi` available on `PATH`
- `pbcopy` for clipboard support (built into macOS)

## Install

One command:

```sh
curl -fsSL https://raw.githubusercontent.com/alexcamlo/shask/main/install.sh | zsh
```

Restart zsh, or source the integration immediately:

```sh
source "$HOME/.local/share/shask/shask.zsh"
```

Ask for a command:

```sh
shask find all pdfs bigger than 10mb under Downloads
```

`shask` will generate a command, then ask what to do:

```text
execute | revise | describe | copy | quit:
```

The first letter of each action is highlighted. Press:

- `e` execute
- `r` revise
- `d` describe
- `c` copy
- `q` quit

The installer:

- installs files to `$HOME/.local/share/shask`
- creates `$HOME/.local/bin/shask`
- keeps `$HOME/.local/bin/pai` as a temporary compatibility alias
- adds a managed source block to `${ZDOTDIR:-$HOME}/.zshrc`

Uninstall, also one command:

```sh
curl -fsSL https://raw.githubusercontent.com/alexcamlo/shask/main/install.sh | zsh -s -- --uninstall
```

## Usage

### Confirmed execution

```sh
shask tell me how many items are in ~/Downloads folder
```

Example output:

```sh
find "$HOME/Downloads" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l
```

Then choose `execute`, `revise`, `describe`, `copy`, or `quit`.

### Generate only

```sh
shask --print show listening tcp ports
```

### Explain a command

```sh
shask --describe 'find . -name "*.log" -mtime +7 -print'
```

### Alt+E prompt replacement

When `shask.zsh` is sourced in an interactive zsh session, `Alt+E` is
bound automatically.

1. Type a natural-language request at your shell prompt.
2. Press `Alt+E`.
3. The prompt buffer is replaced with a generated command.
4. Review or edit the command.
5. Press Enter yourself to run it.

This mirrors AIChat's shell integration and never auto-executes.

## Configuration

Set the model persistently through `shask`; no `~/.zshrc` environment variable is
needed:

```sh
shask --model openai/gpt-4o-mini
shask --model anthropic/claude-sonnet-4-5
shask --model google/gemini-2.5-pro
```

`shask --model` prints the active model. The setting is stored in
`${XDG_CONFIG_HOME:-$HOME/.config}/shask/config`, so it works both from
the standalone `shask` executable and the sourced zsh integration.

To see models available through your Pi login:

```sh
pi --list-models
```

Optional environment overrides for shell behavior can still be set before
sourcing `shask.zsh`:

```sh
export SHASK_CONTEXT=basic   # none | basic | git
export SHASK_BINDKEY=1       # 0 disables Alt+E binding
export SHASK_KEY=$'\ee'      # Alt+E
```

`SHASK_MODEL` is a fallback when no saved model is configured.
`SHASK_CONFIG` can redirect the config-file path, which is useful for isolated
environments or tests.

### Migrating from pai / shell-assist

The installer replaces the old zsh integration and preserves `pai` as a
deprecated forwarding command. Existing models from
`~/.config/shell-assist/config` and legacy `PI_SHELL_ASSIST_*` environment
variables continue to work when no new `SHASK_*` equivalent is configured.
New model selections are saved to `~/.config/shask/config`.

### Context

Context modes:

- `none`: no cwd/git context
- `basic`: OS, zsh version, and current directory
- `git`: `basic` plus git root, branch, and short status

No file contents are sent to `pi` by default.

## Backend

Default generation call shape:

```sh
pi \
  --model "$SHASK_MODEL" \
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

`bin/shask` is included for convenience:

```sh
export PATH="$PWD/bin:$PATH"
shask --print list files
```

For full shell behavior, prefer sourcing `shask.zsh`. The wrapper runs in
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
zsh -n shask.zsh bin/shask bin/pai scripts/install-zsh install.sh tests/smoke.zsh tests/fixtures/bin/pi
zsh tests/smoke.zsh
```
