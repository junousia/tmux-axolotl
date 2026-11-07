#!/usr/bin/env bash
# tmux-axolotl: status bar with a UI feel: powerline pill and rounded tabs.
if (( BASH_VERSINFO[0] < 4 )); then
  printf 'tmux-axolotl requires Bash 4 or newer on PATH\n' >&2
  exit 1
fi
# Needs a Nerd Font and the tmux-git-workspaces plugin (which provides
# @workspace / @workspace-active).
#
# Layout: hostname pill on the left, tabs centred, branch segment and workspace
# pill on the right.
# @axolotl-pill 'left' moves the workspace pill to the left edge instead.
# Tabs form one connected bar: inactive tabs show their window name shortened to
# @axolotl-abbrev chars (4), on backgrounds that darken left to right. Selection
# changes colours, not geometry; @axolotl-title-mode expand restores full active
# titles. Rename windows with automatic-rename-format or rename-window.
# @axolotl-gradient fade|alternate|flat sets how inactive tabs are shaded (default:
# fade, flat for the 'terminal' scheme); @axolotl-gradient-steps (2-8, default 4)
# sets how many shades a fade uses.
# prefix + T opens a colour scheme picker with live preview (@axolotl-scheme-key
# changes the key, 'off' disables the binding).
# @axolotl-host 'off' hides the hostname pill; @axolotl-justify 'left' left-aligns
# the tabs instead of centring them.
# @axolotl-numbers 'off' hides the window numbers in the tabs.
#
# Colours: @axolotl-scheme picks a palette (default 'terminal': the terminal's
# own ANSI colours, so the bar follows your terminal theme). Named schemes in
# schemes/ use exact hex colours on truecolor terminals, the nearest xterm
# colours on 256-colour ones, and the ANSI palette on basic ones. Tier is chosen
# per client at render time. An @axolotl-<colour> option overrides that colour
# in every tier. The resolved palette is published as @axolotl-pal-<tier>-<name>
# for other plugins to inherit.
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# read every option we use in a single tmux call (each tmux call is a process)
names_opt=(pill scheme numbers host justify abbrev title-mode scheme-key gradient gradient-steps left right accent fg muted dark surface active)
US=$'\x1f'
fmt=; for n in "${names_opt[@]}"; do fmt+="#{@axolotl-$n}$US"; done
IFS=$US read -r -a vals < <(tmux display -p "$fmt")
declare -A uopt
for i in "${!names_opt[@]}"; do uopt[${names_opt[$i]}]=${vals[$i]-}; done
opt() { local v=${uopt[${1#@axolotl-}]}; echo "${v:-$2}"; }

# Side-panel segments. Each side is one connected group of visible segments.
# Built-ins: host, branch, workspace. Define your own (any plugin can):
#   set -g @axolotl-segment-<name> '<tmux format, may use #(command)>'
#   optional: -icon, -short (short form, default icon only), -style (surface|accent),
#             -if (format; shown when true), -min (client width needed for the long form)
# Load segment-defining plugins before this one, or re-run this script afterwards.

# Stream a quoted configuration in one call instead of sending an argv batch:
# custom panels can exceed tmux's command-message size limit.
cmds=()
q() {
  local arg line=''
  for arg in "$@"; do
    arg=${arg//\\/\\\\}
    arg=${arg//\"/\\\"}
    arg=${arg//\$/\\\$}
    arg=${arg//$'\n'/\\n}
    arg=${arg//$'\r'/\\r}
    arg=${arg//$'\t'/\\t}
    line+="\"$arg\" "
  done
  cmds+=("$line")
}

# glyphs as UTF-8 bytes (independent of the locale this script runs in)
lcap=$'\xee\x82\xb6'; rcap=$'\xee\x82\xb4'
branch_icon=$'\xee\x82\xa0'; folder=$'\xef\x81\xbb'
bell=$'\xef\x83\xb3'; zoom=$'\xef\x80\x8e'; hosticon=$'\xef\x84\x88'

active_root='#{W:,#{@workspace}}'
ws="#{?$active_root,#{b:$active_root},#S}"
git="#(git -C '$active_root' branch --show-current 2>/dev/null)"
pill_pos=$(opt @axolotl-pill right)
scheme=$(opt @axolotl-scheme terminal)
numbers=$(opt @axolotl-numbers on)
host_on=$(opt @axolotl-host on)
justify=$(opt @axolotl-justify centre)
abbr=$(opt @axolotl-abbrev 4)
title_mode=$(opt @axolotl-title-mode stable)
gradient=$(opt @axolotl-gradient '')
gsteps=$(opt @axolotl-gradient-steps 4)
(( gsteps < 2 )) && gsteps=2; (( gsteps > 8 )) && gsteps=8

# nearest xterm-256 colour for #rrggbb (6x6x6 cube or grayscale ramp)
levels=(0 95 135 175 215 255)
nearest() { local v=$1 i best=0 bd=999 d; for i in 0 1 2 3 4 5; do d=$(( v - levels[i] )); (( d < 0 )) && d=$(( -d )); (( d < bd )) && { bd=$d; best=$i; }; done; echo "$best"; }
to256() {
  local h=${1#\#} r g b ri gi bi cr cg cb gray gv dc dg
  r=$((16#${h:0:2})); g=$((16#${h:2:2})); b=$((16#${h:4:2}))
  ri=$(nearest $r); gi=$(nearest $g); bi=$(nearest $b)
  cr=${levels[ri]}; cg=${levels[gi]}; cb=${levels[bi]}
  gray=$(( (r + g + b) / 3 )); gray=$(( (gray - 3) / 10 )); (( gray < 0 )) && gray=0; (( gray > 23 )) && gray=23
  gv=$(( 8 + 10 * gray ))
  dc=$(( (r-cr)*(r-cr) + (g-cg)*(g-cg) + (b-cb)*(b-cb) ))
  dg=$(( (r-gv)*(r-gv) + (g-gv)*(g-gv) + (b-gv)*(b-gv) ))
  if (( dg < dc )); then echo "colour$(( 232 + gray ))"; else echo "colour$(( 16 + 36*ri + 6*gi + bi ))"; fi
}

# resolve the palette per tier: tier_<tier>[accent|fg|muted|dark|surface|active]
names=(accent fg muted dark surface active)
ansi_default=(yellow white brightblack black brightblack brightblack)
declare -A pal
for i in "${!names[@]}"; do
  n=${names[$i]}
  pal[ansi-$n]=${ansi_default[$i]}; pal[256-$n]=${ansi_default[$i]}; pal[rgb-$n]=${ansi_default[$i]}
done
if [[ $scheme != terminal && -f $dir/schemes/$scheme ]]; then
  # shellcheck disable=SC1090
  source "$dir/schemes/$scheme"
  for n in "${names[@]}"; do
    hex=${!n}
    pal[rgb-$n]=$hex; pal[256-$n]=$(to256 "$hex")
  done
fi
# per-colour user overrides apply to every tier and are published below
for t in rgb 256 ansi; do
  for n in "${names[@]}"; do
    o=${uopt[$n]}; [[ -n $o ]] && pal[$t-$n]=$o
    q set-option -g "@axolotl-pal-$t-$n" "${pal[$t-$n]}"
  done
done

# blend <hexA> <hexB> <k> <n>: colour k/n of the way from A to B
blend() {
  local a=${1#\#} b=${2#\#} k=$3 n=$4 out="#" i x y
  for i in 0 2 4; do
    x=$((16#${a:i:2})); y=$((16#${b:i:2}))
    out+=$(printf '%02x' $(( x + (y - x) * k / n )))
  done
  echo "$out"
}
hexre='^#[0-9a-fA-F]{6}$'

# segment lists and per-segment settings (second tmux call, one per run)
left_def=; [[ $host_on != off ]] && left_def=host
right_def="branch workspace"
[[ $pill_pos == left ]] && { left_def="$left_def workspace"; right_def=branch; }
read -r -a left_segs <<<"$(opt @axolotl-left "$left_def")"
read -r -a right_segs <<<"$(opt @axolotl-right "$right_def")"
[[ ${#left_segs[@]} == 1 && ${left_segs[0]} == none ]] && left_segs=()
[[ ${#right_segs[@]} == 1 && ${right_segs[0]} == none ]] && right_segs=()
segs=("${left_segs[@]}" "${right_segs[@]}")
fmt=; for n in "${segs[@]}"; do for k in "" -icon -short -style -if -min; do fmt+="#{@axolotl-segment-$n$k}$US"; done; done
IFS=$US read -r -a svals < <(tmux display -p "$fmt")
declare -A SEG_CONTENT SEG_ICON SEG_SHORT SEG_STYLE SEG_IF SEG_MIN
si=0
for n in "${segs[@]}"; do
  u_content=${svals[si++]-}; u_icon=${svals[si++]-}; u_short=${svals[si++]-}
  u_style=${svals[si++]-}; u_if=${svals[si++]-}; u_min=${svals[si++]-}
  # A module only declares defaults. Layout, styling and placement stay in the
  # shared renderer; modules are sourced once when this theme is loaded.
  segment_content= segment_icon= segment_short= segment_style=surface
  segment_if= segment_min=100
  if [[ $n =~ ^[a-z][a-z0-9_-]*$ && -f $dir/segments/$n.sh ]]; then
    source "$dir/segments/$n.sh"
  fi
  [[ -n $u_content ]] && segment_content="#{E:@axolotl-segment-$n}"
  SEG_CONTENT[$n]=$segment_content
  SEG_ICON[$n]=${u_icon:-$segment_icon}
  [[ ${SEG_ICON[$n]} == none ]] && SEG_ICON[$n]=''
  SEG_SHORT[$n]=${u_short:-$segment_short}
  SEG_STYLE[$n]=${u_style:-$segment_style}
  SEG_IF[$n]=${u_if:-$segment_if}
  SEG_MIN[$n]=${u_min:-$segment_min}
done

# Shared geometry for tabs and panels; colour and visibility are separate from
# cell ownership. A segment owns its body and the one boundary cell to its right.
# Only the first visible segment owns a left outer cap.
source "$dir/scripts/render.sh"

# build <tier>
build() {
  local t=$1
  local accent=${pal[$t-accent]} text=${pal[$t-fg]} muted=${pal[$t-muted]}
  local dark=${pal[$t-dark]} surf=${pal[$t-surface]} act=${pal[$t-active]}
  # Tab shades by slot (needs the plugin's @workspace-slot). @axolotl-gradient:
  #   fade       lightest at the left, darkening over @axolotl-gradient-steps tabs
  #   alternate  two shades, taking turns
  #   flat       one shade
  # Default: fade, except flat for palettes that can't be blended (the 'terminal'
  # scheme uses ANSI names). The shade depends only on the tab's slot, never on
  # which tab is selected.
  local -a sh; local tabfg=$muted style=$gradient steps=$gsteps hex=0
  [[ $t != ansi && ${pal[rgb-active]} =~ $hexre && ${pal[rgb-dark]} =~ $hexre ]] && hex=1
  # the muted colour is unreadable on ANSI shades (brightblack on brightblack)
  (( hex )) || tabfg=$text
  [[ -z $style ]] && { (( hex )) && style=fade || style=flat; }
  [[ $style == fade ]] && (( ! hex )) && style=alternate
  case $style in
    flat)      sh=("" "$surf") ;;
    alternate) if (( hex )); then sh=("" "$surf" "$act"); else sh=("" "$surf" "$dark"); fi ;;
    *)         style=fade
               for ((k = 1; k <= steps; k++)); do
                 sh[k]=$(blend "${pal[rgb-active]}" "${pal[rgb-dark]}" $((k - 1)) $((steps - 1)))
                 [[ $t == 256 ]] && sh[k]=$(to256 "${sh[k]}")
               done ;;
  esac
  # shade <fg|bg> <slot expr>: style tag for a tab's shade; an empty slot (no tab
  # there) is the terminal background
  shade() {
    local d="$2" tail k
    case $style in
      flat) tail="#[$1=${sh[1]}]" ;;
      alternate) tail="#{?#{==:#{e|%:$d,2},0},#[$1=${sh[1]}],#[$1=${sh[2]}]}" ;;
      *)  # fade: slots 0..steps-2 take their own shade; from there on the last two alternate
          tail="#{?#{==:#{e|%:$d,2},$(( (steps - 1) % 2 ))},#[$1=${sh[steps]}],#[$1=${sh[steps - 1]}]}"
          for ((k = steps - 2; k >= 0; k--)); do tail="#{?#{==:$d,$k},#[$1=${sh[k + 1]}],$tail}"; done ;;
    esac
    echo "#{?#{==:$d,},#[$1=default],$tail}"
  }
  local slot='#{@workspace-slot}'
  local sfg sbg rbg
  sfg=$(shade fg "$slot")
  sbg=$(shade bg "$slot")
  # neighbours: none at the ends of the run
  rbg="#{?#{||:#{==:#{@workspace-pos},last},#{==:#{@workspace-pos},only}},#[bg=default],$(shade bg "#{e|+:$slot,1}")}"
  # window numbers: the active tab's accent moves to its name when they're hidden
  local num="#I "
  [[ $numbers == off ]] && num=""

  build_segments "$t"
  local panel_side panel_format
  panel_side=left; panel "$t" "${left_segs[@]}"
  q set-option -g "@axolotl-left-$t" "$panel_format"
  panel_side=right; panel "$t" "${right_segs[@]}"
  q set-option -g "@axolotl-right-$t" "$panel_format"

  local first="#{||:#{==:#{@workspace-pos},first},#{==:#{@workspace-pos},only}}"
  local label="${num}#{=/$abbr/…:window_name}" current
  current=$label
  [[ $title_mode == expand ]] && current="${num}#W"
  # Show window state in either selection state, so selecting a zoomed window
  # doesn't insert a new cell. Bell takes precedence when both flags are set.
  local flags="#{?window_bell_flag,#[fg=$accent] $bell,#{?window_zoomed_flag, $zoom,}}"
  local current_flags="#{?window_bell_flag, $bell,#{?window_zoomed_flag, $zoom,}}"
  local left="#{?$first,$(cap "$sfg" '#[bg=default]' "$lcap"),}"
  local current_left="#{?$first,$(cap "#[fg=$accent]" '#[bg=default]' "$lcap"),}"
  # The predecessor owns the active tab's left curve. Read the selected slot
  # directly from tmux's live window loop, not the shell-updated nextact flag:
  # the curve and highlight must move in the same redraw. Visible slots also
  # handle hidden windows and gaps in window indexes.
  local next_active="#{==:#{e|+:$slot,1},#{W:,#{@workspace-slot}}}"
  local join="#{?$next_active,$(cap "#[fg=$accent]" "$sbg" "$lcap"),$(cap "$sfg" "$rbg" "$rcap")}"
  q set-option -g "@axolotl-win-$t" \
    "$left$(body "#[fg=$tabfg]" "$sbg" '' "$label$flags")$join"
  q set-option -g "@axolotl-cur-$t" \
    "$current_left$(body "#[fg=$dark]" "#[bg=$accent]" '#[bold]' "$current$current_flags")$(cap "#[fg=$accent]" "$rbg" "$rcap")"
}
build rgb; build 256; build ansi

# pick the tier per client; #{E:...} keeps the styles' commas out of #{?...}
rgb='#{m:*RGB*,#{client_termfeatures}}'
c256='#{||:#{m:*256*,#{client_termfeatures}},#{m:*256*,#{client_termname}}}'
tier() { echo "#{?$rgb,#{E:@axolotl-$1-rgb},#{?$c256,#{E:@axolotl-$1-256},#{E:@axolotl-$1-ansi}}}"; }

q set-option -g status-style "bg=default,fg=default"
q set-option -g status-left-length 120
q set-option -g status-right-length 120
q set-option -g status-justify "$justify"
q set-option -g window-status-style none
q set-option -g window-status-current-style none
q set-option -g window-status-separator ''
q set-option -g status-left "$(tier left)"
q set-option -g status-right "$(tier right)"
q set-option -g window-status-format "$(tier win)"
q set-option -g window-status-current-format "$(tier cur)"
printf '%s\n' "${cmds[@]}" | tmux source-file - || exit $?

# prefix + T (@axolotl-scheme-key): pick a colour scheme with live preview
key=$(opt @axolotl-scheme-key T)
if [[ $key != off ]]; then
  tmux bind-key "$key" display-popup -E -w 40 -h 14 -b rounded -T ' scheme ' "$dir/scripts/scheme.sh pick"
fi
