#!/usr/bin/env bash
# tmux-axolotl: status bar with a UI feel: powerline pill and rounded tabs.
# Needs a Nerd Font and the tmux-git-workspaces plugin (which provides
# @workspace / @workspace-active).
#
# Layout: hostname pill on the left, tabs centred, branch segment and workspace
# pill on the right.
# @axolotl-pill 'left' moves the workspace pill to the left edge instead.
# Tabs form one connected bar: inactive tabs show their window name shortened to
# @axolotl-abbrev chars (4), on backgrounds that darken left to right; the selected tab shows the full
# window name. Rename windows with automatic-rename-format or rename-window.
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
names_opt=(pill scheme numbers host justify abbrev scheme-key gradient gradient-steps accent fg muted dark surface active)
US=$'\x1f'
fmt=; for n in "${names_opt[@]}"; do fmt+="#{@axolotl-$n}$US"; done
IFS=$US read -r -a vals < <(tmux display -p "$fmt")
declare -A uopt
for i in "${!names_opt[@]}"; do uopt[${names_opt[$i]}]=${vals[$i]-}; done
opt() { local v=${uopt[${1#@axolotl-}]}; echo "${v:-$2}"; }

# tmux commands are batched and sent in one call at the end
cmds=()
q() { cmds+=("$@" ';'); }

# glyphs as UTF-8 bytes (independent of the locale this script runs in)
lcap=$'\xee\x82\xb6'; rcap=$'\xee\x82\xb4'
branch_icon=$'\xee\x82\xa0'; folder=$'\xef\x81\xbb'
bell=$'\xef\x83\xb3'; zoom=$'\xef\x80\x8e'; hosticon=$'\xef\x84\x88'

ws='#{?#{@workspace-active},#{b:@workspace-active},#S}'
git="#(git -C '#{@workspace-active}' branch --show-current 2>/dev/null)"
pill_pos=$(opt @axolotl-pill right)
scheme=$(opt @axolotl-scheme terminal)
numbers=$(opt @axolotl-numbers on)
host_on=$(opt @axolotl-host on)
justify=$(opt @axolotl-justify centre)
abbr=$(opt @axolotl-abbrev 4)
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
  local sfg sbg lbg rbg
  sfg=$(shade fg "$slot")
  sbg=$(shade bg "$slot")
  # neighbours: none at the ends of the run
  lbg="#{?#{||:#{==:#{@workspace-pos},first},#{==:#{@workspace-pos},only}},#[bg=default],$(shade bg "#{e|-:$slot,1}")}"
  rbg="#{?#{||:#{==:#{@workspace-pos},last},#{==:#{@workspace-pos},only}},#[bg=default],$(shade bg "#{e|+:$slot,1}")}"
  local body="#[fg=$dark]#[bg=$accent]#[bold]$folder $ws #[nobold]"
  # window numbers: the active tab's accent moves to its name when they're hidden
  local cnum=""; [[ $numbers == off ]] || cnum="#I "
  local num="#I "
  [[ $numbers == off ]] && num=""

  local host=""
  [[ $host_on != off ]] && host="#[fg=$surf]#[bg=default]$lcap#[fg=$text]#[bg=$surf]$hosticon #h #[fg=$surf]#[bg=default]$rcap "

  if [[ $pill_pos == left ]]; then
    q set-option -g "@axolotl-left-$t" \
      "${host}#[fg=$accent]#[bg=default]$lcap$body#[fg=$accent]#[bg=default]$rcap "
    q set-option -g "@axolotl-right-git-$t" \
      "#[fg=$surf]#[bg=default]$lcap#[fg=$text]#[bg=$surf]$branch_icon $git #[fg=$surf]#[bg=default]$rcap "
    q set-option -g "@axolotl-right-nogit-$t" ""
  else
    q set-option -g "@axolotl-left-$t" "$host"
    q set-option -g "@axolotl-right-git-$t" \
      "#[fg=$surf]#[bg=default]$lcap#[fg=$text]#[bg=$surf]$branch_icon $git #[fg=$surf]#[bg=default]$rcap #[fg=$accent]#[bg=default]$lcap$body#[fg=$accent]#[bg=default]$rcap "
    q set-option -g "@axolotl-right-nogit-$t" \
      "#[fg=$accent]#[bg=default]$lcap$body#[fg=$accent]#[bg=default]$rcap "
  fi

  # one connected bar: inactive tabs show their window name abbreviated, on shades that
  # have a fixed gradient by position; the selected tab is an accent segment with the
  # full name. End caps need the workspace plugin's @workspace-pos (first/last
  # visible tab); without it the bar simply has square ends.
  local first="#{||:#{==:#{@workspace-pos},first},#{==:#{@workspace-pos},only}}"
  local wlc="#{?$first,${sfg}#[bg=default]$lcap,}"
  q set-option -g "@axolotl-win-$t" \
    "${wlc}#[fg=$tabfg]${sbg} ${num}#{=/$abbr/…:window_name}#{?window_bell_flag,#[fg=$accent] $bell,} #{?#{==:#{@workspace-nextact},1},${sbg} ,${sfg}${rbg}$rcap}"
  q set-option -g "@axolotl-cur-$t" \
    "#[fg=$accent]${lbg}$lcap#[fg=$dark]#[bg=$accent]#[bold] ${cnum}#W#{?window_zoomed_flag, $zoom,} #[nobold]#[fg=$accent]${rbg}$rcap"
}
build rgb; build 256; build ansi

# pick the tier per client; #{E:...} keeps the styles' commas out of #{?...}
rgb='#{m:*RGB*,#{client_termfeatures}}'
c256='#{||:#{m:*256*,#{client_termfeatures}},#{m:*256*,#{client_termname}}}'
tier() { echo "#{?$rgb,#{E:@axolotl-$1-rgb},#{?$c256,#{E:@axolotl-$1-256},#{E:@axolotl-$1-ansi}}}"; }
nogit='#{==:#{@workspace-active},(no repo)}'

q set-option -g status-style "bg=default,fg=default"
q set-option -g status-left-length 80
q set-option -g status-right-length 80
q set-option -g status-justify "$justify"
q set-option -g window-status-style none
q set-option -g window-status-current-style none
q set-option -g window-status-separator ''
q set-option -g status-left "$(tier left)"
q set-option -g status-right "#{?$nogit,$(tier right-nogit),$(tier right-git)}"
q set-option -g window-status-format "$(tier win)"
q set-option -g window-status-current-format "$(tier cur)"
tmux "${cmds[@]}"

# prefix + T (@axolotl-scheme-key): pick a colour scheme with live preview
key=$(opt @axolotl-scheme-key T)
[[ $key != off ]] && tmux bind-key "$key" display-popup -E -w 40 -h 14 -b rounded -T ' scheme ' "$dir/scripts/scheme.sh pick"
