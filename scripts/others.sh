#!/usr/bin/env bash
# Summary of the workspaces other than $1 (the active workspace root), e.g.
#   mcp-rs 1 · (no repo) 4
# A workspace with a window that rang the bell gets a trailing dot.

active=$1
declare -A count bell
order=()

while IFS=$'\t' read -r b ws; do
  [[ $ws == "$active" ]] && continue
  [[ -z ${count[$ws]+x} ]] && { order+=("$ws"); count[$ws]=0; bell[$ws]=; }
  count[$ws]=$(( count[$ws] + 1 ))
  [[ $b == 1 ]] && bell[$ws]=" ●"
done < <(tmux list-windows -F $'#{window_bell_flag}\t#{@workspace}')

out=
for ws in "${order[@]}"; do
  out+="${out:+ · }${ws##*/} ${count[$ws]}${bell[$ws]}"
done
printf '%s' "$out"
