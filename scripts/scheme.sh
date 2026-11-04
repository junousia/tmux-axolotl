#!/usr/bin/env bash
# Colour scheme switcher.
#   scheme.sh apply <name>   switch the running tmux to that scheme
#   scheme.sh pick           fzf picker with live preview; Esc restores the old one
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

apply() {
  # global option; also drop any session-level override that would shadow it
  tmux set-option -g @axolotl-scheme "$1" ';' set-option -u @axolotl-scheme 2>/dev/null
  tmux run-shell "$dir/tmux-axolotl.tmux"
  # the workspace plugin wraps the theme's window formats, so wrap again
  local ws; ws="$(dirname "$dir")/tmux-git-workspaces/tmux-git-workspaces.tmux"
  [[ -f $ws ]] && tmux run-shell "$ws"
  tmux refresh-client -S 2>/dev/null
}

swatch() {  # swatch <scheme>: accent / surface / active colour blocks
  local f="$dir/schemes/$1" accent surface active
  [[ -f $f ]] || { printf '        '; return; }
  # shellcheck disable=SC1090
  eval "$(sed -n 's/^\(accent\|surface\|active\)=\(.*\)$/\1=\2/p' "$f")"
  local c h r g b
  for c in "$accent" "$surface" "$active"; do
    h=${c#\#}; r=$((16#${h:0:2})); g=$((16#${h:2:2})); b=$((16#${h:4:2}))
    printf '\e[48;2;%d;%d;%dm  \e[0m' "$r" "$g" "$b"
  done
}

case $1 in
  apply) apply "$2" ;;
  pick)
    command -v fzf >/dev/null || { tmux display-message "axolotl: fzf is needed for the scheme picker"; exit 1; }
    orig=$(tmux show-option -gqv @axolotl-scheme); orig=${orig:-terminal}
    list() {
      printf 'terminal\t(follow terminal colours)\n'
      for f in "$dir"/schemes/*; do n=${f##*/}; printf '%s\t%s\n' "$n" "$(swatch "$n")"; done
    }
    sel=$(list | FZF_DEFAULT_OPTS= fzf --ansi --delimiter='\t' --no-sort --reverse \
      --prompt='scheme > ' --header="Enter: apply   Esc: cancel   (current: $orig)" \
      --bind "focus:execute-silent('$dir/scripts/scheme.sh' apply {1})" | cut -f1)
    if [[ -n $sel ]]; then
      apply "$sel"
      tmux display-message "axolotl scheme: $sel  (keep it: set -g @axolotl-scheme '$sel' in tmux.conf)"
    else
      apply "$orig"
    fi ;;
  *) echo "usage: scheme.sh apply <name> | pick" >&2; exit 2 ;;
esac
