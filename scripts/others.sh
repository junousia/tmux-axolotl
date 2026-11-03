#!/usr/bin/env bash
# Chips for the workspaces other than $1 (the active workspace root), as tmux
# style codes. $2 surface, $3 text, $4 accent colour. A workspace with a window
# that rang the bell gets an accent dot.
active=$1 surface=$2 text=$3 accent=$4
lcap=$'\xee\x82\xb6'; rcap=$'\xee\x82\xb4'; folder=$'\xef\x81\xbb'

declare -A count bell
order=()
while IFS=$'\t' read -r b ws; do
  [[ $ws == "$active" ]] && continue
  [[ -z ${count[$ws]+x} ]] && { order+=("$ws"); count[$ws]=0; bell[$ws]=; }
  count[$ws]=$(( count[$ws] + 1 ))
  [[ $b == 1 ]] && bell[$ws]=1
done < <(tmux list-windows -F $'#{window_bell_flag}\t#{@workspace}')

for ws in "${order[@]}"; do
  name=${ws##*/}; name=${name//#/##}
  dot=; [[ -n ${bell[$ws]} ]] && dot="#[fg=$accent] ●"
  printf '#[fg=%s]#[bg=default]%s#[fg=%s]#[bg=%s]%s %s %s%s#[fg=%s]#[bg=default]%s ' \
    "$surface" "$lcap" "$text" "$surface" "$folder" "$name" "${count[$ws]}" "$dot" "$surface" "$rcap"
done
