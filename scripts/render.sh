# Layout helpers sourced by tmux-axolotl.tmux. No tmux processes during rendering:
# these functions compile formats, which tmux evaluates separately for each client.

cap() { printf '%s' "#[nobold]$1$2$3"; }
body() { printf '%s' "#[nobold]$1$2$3 $4 #[nobold]"; }

# panel_bg <side> <index> <count> <name>: a fixed shade by position.
# The right panel is counted from its outer (right) edge. Hidden segments keep
# their slot, as tabs do, so conditional visibility never shifts other colours.
panel_bg() {
  local side=$1 i=$2 count=$3 n=$4 slot
  if [[ ${SEG_STYLE[$n]} == accent ]]; then
    printf '%s' "$accent"
    return
  fi
  if [[ $side == right ]]; then slot=$((count - 1 - i)); else slot=$i; fi
  case $pstyle in
    flat) slot=0 ;;
    alternate) slot=$((slot % 2)) ;;
    *) (( slot >= gsteps )) && slot=$((gsteps - 2 + (slot - gsteps + 2) % 2)) ;;
  esac
  printf '%s' "${panel_shades[$slot]}"
}

build_segments() {
  local t=$1 n side i bgc txt bold icon long short visible wide
  local -a items
  for n in "${segs[@]}"; do
    icon=${SEG_ICON[$n]}
    short=${SEG_SHORT[$n]}
    [[ -n $short ]] && short="${icon:+$icon }$short" || short=$icon
    wide="#{e|>=:#{client_width},${SEG_MIN[$n]}}"
    visible=1
    [[ -z $short ]] && visible=$wide
    [[ -z ${SEG_CONTENT[$n]} && -z $icon ]] && visible=0
    [[ -n ${SEG_IF[$n]} ]] && visible="#{&&:${SEG_IF[$n]},$visible}"
    q set-option -g "@axolotl-seg-$n-visible" "$visible"
  done
  for side in left right; do
    if [[ $side == left ]]; then items=("${left_segs[@]}"); else items=("${right_segs[@]}"); fi
    for i in "${!items[@]}"; do
      n=${items[i]}
      bgc=$(panel_bg "$side" "$i" "${#items[@]}" "$n")
      txt=$text bold=''
      [[ ${SEG_STYLE[$n]} == accent ]] && { txt=$dark; bold='#[bold]'; }
      icon=${SEG_ICON[$n]}
      long="${icon:+$icon }${SEG_CONTENT[$n]}"
      short=${SEG_SHORT[$n]}
      [[ -n $short ]] && short="${icon:+$icon }$short" || short=$icon
      wide="#{e|>=:#{client_width},${SEG_MIN[$n]}}"
      q set-option -g "@axolotl-panel-$side-$t-$i-long" "$(body "#[fg=$txt]" "#[bg=$bgc]" "$bold" "$long")"
      q set-option -g "@axolotl-panel-$side-$t-$i-short" "$(body "#[fg=$txt]" "#[bg=$bgc]" "$bold" "$short")"
      q set-option -g "@axolotl-panel-$side-$t-$i-body" "#{?$wide,#{E:@axolotl-panel-$side-$t-$i-long},#{E:@axolotl-panel-$side-$t-$i-short}}"
    done
  done
}

# Join visible neighbours, skipping any hidden or collapsed-away segments. Each
# panel gets exactly two outer caps. Internal caps point toward the centre:
# right-facing on the left panel, left-facing on the right panel.
# Keep neighbour expressions in options so format size grows linearly with panels.
panel() {
  local t=$1; shift
  local -a items=("$@")
  local i n bgc visible next_bg='#[bg=default]' previous=0 out='' opening closing
  local next_visible=0 next_fg='' next_cap
  # Right-to-left pass: cache the next visible background for each position.
  for ((i = ${#items[@]} - 1; i >= 0; i--)); do
    n=${items[i]}
    bgc=$(panel_bg "$panel_side" "$i" "${#items[@]}" "$n")
    visible="#{E:@axolotl-seg-$n-visible}"
    # These options include the ordered group to support a segment on both sides.
    q set-option -g "@axolotl-panel-$panel_side-$t-$i-next" "$next_bg"
    next_bg="#{?$visible,#[bg=$bgc],#{E:@axolotl-panel-$panel_side-$t-$i-next}}"
    if [[ $panel_side == right ]]; then
      q set-option -g "@axolotl-panel-$panel_side-$t-$i-next-visible" "$next_visible"
      q set-option -g "@axolotl-panel-$panel_side-$t-$i-next-fg" "$next_fg"
      next_visible="#{||:$visible,#{E:@axolotl-panel-$panel_side-$t-$i-next-visible}}"
      next_fg="#{?$visible,#[fg=$bgc],#{E:@axolotl-panel-$panel_side-$t-$i-next-fg}}"
    fi
  done
  for i in "${!items[@]}"; do
    n=${items[i]}
    bgc=$(panel_bg "$panel_side" "$i" "${#items[@]}" "$n")
    visible="#{E:@axolotl-seg-$n-visible}"
    q set-option -g "@axolotl-panel-$panel_side-$t-$i-previous" "$previous"
    opening="#{?$previous,,$(cap "#[fg=$bgc]" '#[bg=default]' "$lcap")}"
    if [[ $panel_side == right ]]; then
      # Keep the same boundary cell, but paint the next segment's left curve
      # over this segment's background. The last visible segment closes outward.
      next_cap=$(cap "#{E:@axolotl-panel-$panel_side-$t-$i-next-fg}" "#[bg=$bgc]" "$lcap")
      closing="#{?#{E:@axolotl-panel-$panel_side-$t-$i-next-visible},$next_cap,$(cap "#[fg=$bgc]" '#[bg=default]' "$rcap")}"
    else
      closing=$(cap "#[fg=$bgc]" "#{E:@axolotl-panel-$panel_side-$t-$i-next}" "$rcap")
    fi
    out+="#{?$visible,$opening#{E:@axolotl-panel-$panel_side-$t-$i-body}$closing,}"
    previous="#{||:#{E:@axolotl-panel-$panel_side-$t-$i-previous},$visible}"
  done
  panel_format=$out
}
