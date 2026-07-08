# shell-assist

A zsh/macOS shell assistant powered by `pi`, modeled after AIChat's shell assistant.

It turns natural language into a zsh command, requires confirmation before execution,
can revise/describe/copy the command, and records successfully executed generated
commands in zsh history.

## Requirements

- macOS 26+
- zsh
- `pi` on `PATH`
- `pbcopy` for copy action (built into macOS)

Default backend invocation uses `pi --system-prompt` so the shell prompt is a real system message rather than part of the user request:

```sh
pi --model openai-codex/gpt-5.4-mini --system-prompt '<shell assistant prompt>' --no-extensions --no-tools -p --no-session '<request>'
```

The shell system prompt starts from AIChat's `%shell%` role and adds macOS/zsh-specific safety and Finder-counting rules.

## Install

Repo-first install for your current shell:

```sh
source ./shell-assist.zsh
```

Permanent zsh install:

```sh
scripts/install-zsh --print
# review the output, then either add it yourself or run:
scripts/install-zsh --write
```

`--write` appends a `source .../shell-assist.zsh` line to `~/.zshrc`.

Optional executable command:

```sh
chmod +x bin/pai scripts/install-zsh
export PATH="$PWD/bin:$PATH"
```

> For full shell functionality, prefer sourcing `shell-assist.zsh`. The executable
> wrapper runs in a child shell, so commands like `cd` or `export` cannot affect
> your current terminal session.

## Usage

Interactive confirmed execution:

```sh
pai find all pdfs bigger than 10mb under Downloads
```

Menu actions:

- `e` execute after confirmation
- `r` revise the generated command
- `d` describe the generated command
- `c` copy command to clipboard
- `q` quit

Generate only:

```sh
pai --print show listening tcp ports
```

Describe an existing command:

```sh
pai --describe 'find . -name "*.log" -mtime +7 -print'
```

## Alt+E zsh widget

When sourced in an interactive zsh, `Alt+E` is bound automatically.

1. Type a natural-language request at your prompt.
2. Press `Alt+E`.
3. The buffer is replaced with a generated command.
4. Review/edit it, then press Enter yourself.

This is the closest match to AIChat's shell integration and naturally requires
confirmation because nothing runs until you press Enter.

## Configuration

Set these before sourcing `shell-assist.zsh`:

```sh
export PI_SHELL_ASSIST_MODEL=openai-codex/gpt-5.4-mini
export PI_SHELL_ASSIST_CONTEXT=basic   # none | basic | git
export PI_SHELL_ASSIST_BINDKEY=1       # 0 disables Alt+E binding
export PI_SHELL_ASSIST_KEY=$'\ee'      # Alt+E
```

Context defaults to `basic`: OS, zsh version, and current directory. Set
`PI_SHELL_ASSIST_CONTEXT=git` to include a short git branch/status summary, or
`none` to send no cwd/git context. No file contents are sent.

## Dotfiles / chezmoi

Recommended pattern: track this repo or copy `shell-assist.zsh` into dotfiles,
then source it from `.zshrc`:

```sh
source /path/to/shell-assist/shell-assist.zsh
```

For chezmoi, add the source line to your managed zsh template rather than running
`--write` directly.
