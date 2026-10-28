# zsh-direnv

> Non-blocking direnv for Zsh — your prompt returns immediately while the `.envrc` loads in the background.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![CI](https://github.com/zsh-contrib/zsh-direnv/actions/workflows/ci.yml/badge.svg)](https://github.com/zsh-contrib/zsh-direnv/actions/workflows/ci.yml)

Stop waiting for a slow `.envrc` every time you `cd` into a project. `zsh-direnv` runs `direnv export` in the background and applies the result as soon as it is ready, using zsh's own `zle -F` file-descriptor handlers — no daemon, no binary, a single plugin file. It also exposes the load state as `$ZSH_DIRENV_STATUS`, so your prompt can show what direnv is doing.

## Requirements

- [direnv](https://direnv.net/) (`direnv`)

**macOS (Homebrew):**

```bash
brew install direnv
```

**Nix:**

```bash
nix profile install nixpkgs#direnv
```

## Installation

`zsh-direnv` replaces direnv's own shell hook — remove any `eval "$(direnv hook zsh)"` line from your `.zshrc` first.

### Using zinit

```zsh
zinit load zsh-contrib/zsh-direnv
```

### Using sheldon

```toml
[plugins.zsh-direnv]
github = "zsh-contrib/zsh-direnv"
```

### Manual

```zsh
git clone https://github.com/zsh-contrib/zsh-direnv.git ~/.zsh/plugins/zsh-direnv
source ~/.zsh/plugins/zsh-direnv/zsh-direnv.plugin.zsh
```

## Configuration

### Disable

Set `ZSH_DIRENV_DISABLE=1` to turn the plugin into a complete no-op:

```zsh
export ZSH_DIRENV_DISABLE=1
```

### Silence direnv

direnv's own logging settings apply. For example, to hide the `direnv: export +FOO` lines:

```zsh
export DIRENV_LOG_FORMAT=""
```

### Style direnv's output

The colors of `DIRENV_LOG_FORMAT` are kept, so the output can be styled like the rest of your shell, for example with [gum](https://github.com/charmbracelet/gum):

```zsh
export DIRENV_LOG_FORMAT="$(CLICOLOR_FORCE=1 gum style --foreground 8 'direnv: %s')"
```

`CLICOLOR_FORCE=1` makes gum emit its colors even though the output is captured by `$(...)`.

### Prompt

`$ZSH_DIRENV_STATUS` holds the state of the last direnv run:

| Value | Meaning |
|-------|---------|
| `loading` | an `.envrc` is being evaluated |
| `loaded` | an `.envrc` is active |
| `blocked` | an `.envrc` exists but needs `direnv allow` |
| `error` | direnv failed |
| *(empty)* | no `.envrc` applies |

Read it from your prompt, for example:

```zsh
setopt prompt_subst
RPROMPT='${ZSH_DIRENV_STATUS:+direnv:$ZSH_DIRENV_STATUS}'
```

The prompt is redrawn when the environment or the status changes.

### Starship

The status is exported, so [starship](https://starship.rs/) can show it with the `env_var` module:

```toml
# ~/.config/starship.toml
format = "${env_var.ZSH_DIRENV_STATUS}$character"

[env_var.ZSH_DIRENV_STATUS]
format = "[direnv:$env_value](yellow) "
```

Load `zsh-direnv` in the same `.zshrc` as `starship init zsh`; the order does not matter.

## Behavior

Before each prompt the plugin:

1. Cancels the previous run if it is still in flight, so a stale result is never applied
2. Flags the status as `loading` if an `.envrc` sits above the current directory and its environment is not loaded yet
3. Starts `direnv export zsh` in the background and returns the prompt right away
4. Applies the exported variables and prints direnv's log output once the run finishes, then redraws the prompt

Because the environment arrives asynchronously, a command you run before the load finishes does not see it yet. Watch for `loaded` in your prompt, or keep the `.envrc` fast with [nix-direnv](https://github.com/nix-community/nix-direnv).

Unlike [direnv-instant](https://github.com/Mic92/direnv-instant), `zsh-direnv` does not apply a cached environment before direnv has validated the `.envrc`. The environment you get is always the one direnv has just approved.

## The zsh-contrib Ecosystem

| Repo | What it provides |
|------|-----------------|
| [zsh-aws](https://github.com/zsh-contrib/zsh-aws) | AWS credential management with aws-vault and tmux |
| **zsh-direnv** ← you are here | Non-blocking direnv integration |
| [zsh-eza](https://github.com/zsh-contrib/zsh-eza) | eza with Catppuccin and Rose Pine theming |
| [zsh-fzf](https://github.com/zsh-contrib/zsh-fzf) | fzf with Catppuccin and Rose Pine theming |
| [zsh-op](https://github.com/zsh-contrib/zsh-op) | 1Password CLI with secure caching and SSH key management |
| [zsh-tmux](https://github.com/zsh-contrib/zsh-tmux) | Automatic tmux window title management |
| [zsh-vivid](https://github.com/zsh-contrib/zsh-vivid) | vivid LS_COLORS generation with theme support |

## License

[MIT](LICENSE) — Copyright (c) 2025 zsh-contrib

<!-- markdownlint-disable-file MD013 -->
