# ADR 0001: Pi-backed shask shell assistant

## Status

Accepted

## Context

We want the shell-assistant behavior from `sigoden/aichat`, but implemented with
`pi` and optimized for the user's environment: zsh on macOS 26+.

AIChat's relevant shell-assistant behavior:

- generate a shell command from natural language
- use OS/shell context in the prompt
- offer execute / revise / describe / copy / quit
- provide shell integration that replaces the current input buffer
- append successful generated commands to shell history

A normal executable cannot change the parent shell's state. Commands like `cd`,
`export`, `alias`, and shell options only persist when run by the interactive
shell itself.

## Decision

Implement the assistant as a zsh source file with a `shask` function and zle widget.
Also provide `bin/shask` as a convenience wrapper for use from `PATH`.

The canonical pi backend uses a custom system prompt:

```sh
pi --model openai-codex/gpt-5.4-mini --system-prompt '<shell assistant prompt>' --no-extensions --no-tools -p --no-session '<request>'
```

The shell system prompt is based on AIChat's built-in `%shell%` role, then extended with macOS/zsh-specific safety and Finder-counting semantics.

The generated command is never executed without explicit confirmation.

`shask` provides the full menu flow:

- execute
- revise
- describe
- copy
- quit

The `Alt+E` widget follows AIChat's shell integration model: it replaces the
current zle buffer with the generated command and lets the user press Enter.

## Consequences

- Sourcing `shask.zsh` is the preferred install path.
- `bin/shask` is useful, but commands that must affect the current shell will not
  persist because the wrapper runs in a child shell.
- Context is small by default: OS, zsh version, and cwd.
- Git context is opt-in with `SHASK_CONTEXT=git` to keep prompts faster.
- No file contents are sent to pi by default.
- The implementation is portable within zsh/macOS without Rust or Python.
