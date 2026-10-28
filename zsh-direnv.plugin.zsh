#!/usr/bin/env zsh
#

if (( ! $+commands[direnv] )); then
  print -u2 "zsh-direnv: direnv not found in PATH"
  return 1
fi

# State of the last direnv run, meant to be read from a prompt:
#   loading  an .envrc is being evaluated
#   loaded   an .envrc is active
#   blocked  an .envrc exists but needs `direnv allow`
#   error    direnv failed
# Empty when no .envrc applies. Exported so that prompts running as a separate
# process, like starship, can read it.
typeset -gx ZSH_DIRENV_STATUS=""

# Status to fall back to when direnv reports nothing, i.e. the one that was
# active before "loading" was flagged.
typeset -g _zsh_direnv__status=""

# File descriptor of the in-flight `direnv export`, empty when idle.
typeset -g _zsh_direnv__fd=""

# Separates export code, exit status and log output on the pipe back from the
# background run. The unit separator never appears in direnv's output.
typeset -g _zsh_direnv__sep=$'\x1f'

# Print the directory of the closest .envrc above $PWD, if any. Only used to
# tell "loading" apart from "no .envrc" before direnv has answered.
function _zsh_direnv__envrc_dir() {
  emulate -L zsh

  local dir=$PWD
  while [[ -n $dir ]]; do
    [[ -f $dir/.envrc ]] && { print -r -- $dir; return 0 }
    dir=${dir%/*}
  done
  return 1
}

# Runs in a subshell. direnv's export code goes straight to the pipe (fd 3),
# while its log output is captured and appended after the exit status.
function _zsh_direnv__run() {
  local msgs rc
  { msgs=$(direnv export zsh 2>&1 1>&3 3>&-); rc=$? } 3>&1
  print -rn -- "${_zsh_direnv__sep}${rc}${_zsh_direnv__sep}${msgs}"
}

# Stop waiting for the in-flight run so that its result is never applied.
function _zsh_direnv__cancel() {
  emulate -L zsh

  [[ -n $_zsh_direnv__fd ]] || return 0
  zle -F $_zsh_direnv__fd
  exec {_zsh_direnv__fd}<&-
  _zsh_direnv__fd=""
}

# PROMPT as it was before direnv's output was put in front of it, and the
# resulting string, so that only our own change is ever undone.
typeset -g _zsh_direnv__prompt=""
typeset -g _zsh_direnv__prefixed=""

# Put direnv's log output (e.g. "direnv: export +FOO") in front of the prompt,
# so it reads like plain direnv: the output above a single prompt. Printing it
# from the handler instead leaves the first prompt on screen above the output,
# and a reset-prompt after that wipes it on multi-line prompts such as starship's.
# The colors of DIRENV_LOG_FORMAT are kept, marked as zero-width for zsh.
function _zsh_direnv__show() {
  emulate -L zsh -o extendedglob

  local line out open='%{' close='%}'
  for line in ${(f)1}; do
    line=${line//\%/%%}
    [[ -o promptsubst ]] && line=${line//(#m)[\\\$\`]/\\$MATCH}
    line=${line//(#m)$'\e'\[[0-9;]#m/$open$MATCH$close}
    out+=$line$'\n'
  done

  _zsh_direnv__prompt=$PROMPT
  PROMPT=$out$PROMPT
  _zsh_direnv__prefixed=$PROMPT
}

# Undo _zsh_direnv__show, unless something else changed PROMPT in the meantime.
function _zsh_direnv__hide() {
  emulate -L zsh

  [[ -n $_zsh_direnv__prefixed && $PROMPT == "$_zsh_direnv__prefixed" ]] && PROMPT=$_zsh_direnv__prompt
  _zsh_direnv__prompt=""
  _zsh_direnv__prefixed=""
}

# Called by zle once the background run has written its result.
function _zsh_direnv__apply() {
  emulate -L zsh

  local fd=$1 data
  [[ $2 == nval ]] && return 0

  IFS= read -r -u $fd -d '' data
  zle -F $fd
  exec {fd}<&-
  _zsh_direnv__fd=""

  local sep=$_zsh_direnv__sep
  [[ $data == *${sep}*${sep}* ]] || return 1

  local code=${data%%${sep}*}
  local rest=${data#*${sep}}
  local rc=${rest%%${sep}*}
  local msgs=${rest#*${sep}}
  local before=$ZSH_DIRENV_STATUS

  [[ -n $code ]] && eval "$code"

  if [[ $msgs == *"is blocked"* ]]; then
    ZSH_DIRENV_STATUS=blocked
  elif (( rc != 0 )); then
    ZSH_DIRENV_STATUS=error
  elif [[ -z $code && -z $msgs ]]; then
    # direnv is silent once nothing changes, including for a blocked .envrc.
    ZSH_DIRENV_STATUS=$_zsh_direnv__status
  elif [[ -n $DIRENV_DIR ]]; then
    ZSH_DIRENV_STATUS=loaded
  else
    ZSH_DIRENV_STATUS=""
  fi

  [[ -n $msgs ]] && _zsh_direnv__show $msgs

  # Redraw so a prompt that reads the env or the status picks up the change.
  if [[ -n $code || -n $msgs || $before != $ZSH_DIRENV_STATUS ]]; then
    zle reset-prompt
  fi
}

# called just before the prompt is printed
function _zsh_direnv__precmd() {
  emulate -L zsh

  _zsh_direnv__hide

  # Opt-out: users who set ZSH_DIRENV_DISABLE=1 get a complete no-op.
  [[ "${ZSH_DIRENV_DISABLE:-0}" == 1 ]] && return 0

  _zsh_direnv__cancel

  # Flag the status up front, but only when the env of that .envrc is not
  # loaded yet, otherwise the prompt would flicker on every command.
  local dir
  [[ $ZSH_DIRENV_STATUS == loading ]] || _zsh_direnv__status=$ZSH_DIRENV_STATUS
  dir=$(_zsh_direnv__envrc_dir) && [[ $DIRENV_DIR != -${dir:A} ]] && ZSH_DIRENV_STATUS=loading

  exec {_zsh_direnv__fd}< <(_zsh_direnv__run)
  zle -F $_zsh_direnv__fd _zsh_direnv__apply
}

autoload -Uz add-zsh-hook

add-zsh-hook precmd _zsh_direnv__precmd
