#!/usr/bin/env bats

# Tests for zsh-direnv plugin
#
# Requires bats-core: https://github.com/bats-core/bats-core
# Run: bats tests/plugin.bats

export PLUGIN_DIR
PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# A fake `direnv` whose output is driven by the STUB_* variables:
#   STUB_CODE  export code printed on stdout
#   STUB_MSG   log line printed on stderr
#   STUB_RC    exit status
setup() {
  export STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  cat >"$STUB_BIN/direnv" <<'EOF'
#!/bin/sh
printf '%s' "$STUB_CODE"
[ -n "$STUB_MSG" ] && printf '%s\n' "$STUB_MSG" >&2
exit "${STUB_RC:-0}"
EOF
  chmod +x "$STUB_BIN/direnv"
  unset STUB_CODE STUB_MSG STUB_RC ZSH_DIRENV_DISABLE DIRENV_DIR FOO
}

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

@test "fails with a warning when direnv is not installed" {
  run zsh -c '
    PATH="/usr/bin:/bin"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
  '
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"direnv not found"* ]]
}

@test "status is empty after loading" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    echo "[${ZSH_DIRENV_STATUS}]"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

@test "status is exported for prompts running in a child process" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    ZSH_DIRENV_STATUS=loaded
    env | grep "^ZSH_DIRENV_STATUS="
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ZSH_DIRENV_STATUS=loaded" ]]
}

@test "precmd hook is registered" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    echo "${precmd_functions[*]}"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"_zsh_direnv__precmd"* ]]
}

@test "precmd is a no-op when ZSH_DIRENV_DISABLE is 1" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    export ZSH_DIRENV_DISABLE=1
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    echo "[${_zsh_direnv__fd}]"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

# ---------------------------------------------------------------------------
# Applying the environment
# ---------------------------------------------------------------------------

@test "exports from direnv are applied to the shell" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    export STUB_CODE="export FOO=bar;export DIRENV_DIR=-/proj;"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd
    echo "$FOO $ZSH_DIRENV_STATUS"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "bar loaded" ]]
}

@test "unsets from direnv are applied and the status is cleared" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    export FOO=bar DIRENV_DIR=-/proj
    export STUB_CODE="unset FOO;unset DIRENV_DIR;"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    ZSH_DIRENV_STATUS=loaded
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd
    echo "${FOO:-unset} [${ZSH_DIRENV_STATUS}]"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "unset []" ]]
}

@test "direnv log output is printed" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    export STUB_CODE="export FOO=bar;export DIRENV_DIR=-/proj;"
    export STUB_MSG="direnv: export +FOO"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"direnv: export +FOO"* ]]
}

@test "the prompt is redrawn only after direnv's output is printed" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { echo "zle $*"; }
    export STUB_CODE="export FOO=bar;export DIRENV_DIR=-/proj;"
    export STUB_MSG="direnv: export +FOO"
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd 2>&1
  '
  [[ "$status" -eq 0 ]]
  # zle -F registration, -F unregistration, then: invalidate, print, redisplay, reset
  [[ "${lines[2]}" == "zle -I" ]]
  [[ "${lines[3]}" == "direnv: export +FOO" ]]
  [[ "${lines[4]}" == "zle -R" ]]
  [[ "${lines[5]}" == "zle reset-prompt" ]]
}

@test "a run that produced no result is rejected" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    exec {fd}< <(print -n)
    _zsh_direnv__apply $fd
    echo "status=$?"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "status=1" ]]
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

@test "status is blocked when the .envrc needs direnv allow" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    export STUB_CODE="export DIRENV_DIR=-/proj;"
    export STUB_MSG="direnv: error /proj/.envrc is blocked. Run \`direnv allow\` to approve its content"
    export STUB_RC=1
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd 2>/dev/null
    echo "$ZSH_DIRENV_STATUS"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "blocked" ]]
}

@test "status stays blocked while direnv is silent" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    export DIRENV_DIR=-/proj
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    ZSH_DIRENV_STATUS=blocked
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd
    echo "$ZSH_DIRENV_STATUS"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "blocked" ]]
}

@test "status is error when direnv fails" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    export STUB_MSG="direnv: error boom"
    export STUB_RC=1
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd 2>/dev/null
    echo "$ZSH_DIRENV_STATUS"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "error" ]]
}

@test "status is loading while an .envrc above the cwd is not loaded yet" {
  mkdir -p "$BATS_TEST_TMPDIR/proj/src"
  touch "$BATS_TEST_TMPDIR/proj/.envrc"
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    cd "$BATS_TEST_TMPDIR/proj/src"
    _zsh_direnv__precmd
    echo "$ZSH_DIRENV_STATUS"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "loading" ]]
}

@test "status is not loading once that .envrc is loaded" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  touch "$BATS_TEST_TMPDIR/proj/.envrc"
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    cd "$BATS_TEST_TMPDIR/proj"
    export DIRENV_DIR="-${PWD:A}"
    ZSH_DIRENV_STATUS=loaded
    _zsh_direnv__precmd
    echo "$ZSH_DIRENV_STATUS"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "loaded" ]]
}

@test "status is not loading when there is no .envrc" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    cd "$BATS_TEST_TMPDIR"
    _zsh_direnv__precmd
    echo "[${ZSH_DIRENV_STATUS}]"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

@test "status falls back when direnv ignores the .envrc" {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  touch "$BATS_TEST_TMPDIR/proj/.envrc"
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    cd "$BATS_TEST_TMPDIR/proj"
    _zsh_direnv__precmd
    _zsh_direnv__apply $_zsh_direnv__fd
    echo "[${ZSH_DIRENV_STATUS}]"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}

# ---------------------------------------------------------------------------
# Overlapping runs
# ---------------------------------------------------------------------------

@test "a new prompt cancels the run that is still in flight" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { echo "zle $*"; }
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    _zsh_direnv__precmd
  '
  [[ "$status" -eq 0 ]]
  # the first run is unregistered before the second one is registered
  [[ "${lines[0]}" =~ ^"zle -F "[0-9]+" _zsh_direnv__apply"$ ]]
  [[ "${lines[1]}" =~ ^"zle -F "[0-9]+$ ]]
  [[ "${lines[2]}" =~ ^"zle -F "[0-9]+" _zsh_direnv__apply"$ ]]
}

@test "cancel leaves nothing in flight" {
  run zsh -c '
    PATH="$STUB_BIN:$PATH"
    zle() { :; }
    source "$PLUGIN_DIR/zsh-direnv.plugin.zsh"
    _zsh_direnv__precmd
    _zsh_direnv__cancel
    echo "[${_zsh_direnv__fd}]"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "[]" ]]
}
