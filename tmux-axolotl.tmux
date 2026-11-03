#!/usr/bin/env bash
# tmux-axolotl: status bar with a UI feel: powerline pill and rounded tabs.
# Needs a Nerd Font and the tmux-git-workspaces plugin (which provides
# @workspace / @workspace-active).
#
# Layout: tabs on the left; branch segment and workspace pill on the right.
# @axolotl-pill 'left' moves the pill to the left edge instead.
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

opt() { local v; v=$(tmux show-option -gqv "$1"); echo "${v:-$2}"; }

# glyphs as UTF-8 bytes (independent of the locale this script runs in)
rarrow=$'\xee\x82\xb0'; larrow=$'\xee\x82\xb2'
lcap=$'\xee\x82\xb6'; rcap=$'\xee\x82\xb4'
branch_icon=$'\xee\x82\xa0'; folder=$'\xef\x81\xbb'
bell=$'\xef\x83\xb3'; zoom=$'\xef\x80\x8e'

ws='#{?#{@workspace-active},#{b:@workspace-active},#S}'
git="#(git -C '#{@workspace-active}' branch --show-current 2>/dev/null)"
pill_pos=$(opt @axolotl-pill right)
scheme=$(opt @axolotl-scheme terminal)
numbers=$(opt @axolotl-numbers on)

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
    o=$(tmux show-option -gqv "@axolotl-$n"); [[ -n $o ]] && pal[$t-$n]=$o
    tmux set-option -g "@axolotl-pal-$t-$n" "${pal[$t-$n]}"
  done
done

# build <tier>
build() {
  local t=$1
  local accent=${pal[$t-accent]} text=${pal[$t-fg]} muted=${pal[$t-muted]}
  local dark=${pal[$t-dark]} surf=${pal[$t-surface]} act=${pal[$t-active]}
  local body="#[fg=$dark]#[bg=$accent]#[bold]$folder $ws #[nobold]"
  # window numbers: the active tab's accent moves to its name when they're hidden
  local num="#I " cur_text="#[fg=$accent]#I #[fg=$text]#W"
  if [[ $numbers == off ]]; then num=""; cur_text="#[fg=$accent]#W"; fi

  if [[ $pill_pos == left ]]; then
    tmux set-option -g "@axolotl-left-$t" \
      "#[fg=$accent]#[bg=default]$lcap$body#[fg=$accent]#[bg=default]$rarrow "
    tmux set-option -g "@axolotl-right-git-$t" \
      "#[fg=$surf]#[bg=default]$lcap#[fg=$text]#[bg=$surf]$branch_icon $git #[fg=$surf]#[bg=default]$rcap "
    tmux set-option -g "@axolotl-right-nogit-$t" ""
  else
    tmux set-option -g "@axolotl-left-$t" ""
    tmux set-option -g "@axolotl-right-git-$t" \
      "#[fg=$surf]#[bg=default]$larrow#[fg=$text]#[bg=$surf] $branch_icon $git #[fg=$accent]#[bg=$surf]$larrow$body#[fg=$accent]#[bg=default]$rcap "
    tmux set-option -g "@axolotl-right-nogit-$t" \
      "#[fg=$accent]#[bg=default]$larrow$body#[fg=$accent]#[bg=default]$rcap "
  fi

  tmux set-option -g "@axolotl-win-$t" \
    "#[fg=$muted] ${num}#W#{?window_bell_flag,#[fg=$accent] $bell,} "
  tmux set-option -g "@axolotl-cur-$t" \
    "#[fg=$act]#[bg=default]$lcap#[fg=$accent]#[bg=$act]#[bold]${cur_text}#[nobold]#{?window_zoomed_flag,#[fg=$accent] $zoom,}#[fg=$act]#[bg=default]$rcap"
}
build rgb; build 256; build ansi

# pick the tier per client; #{E:...} keeps the styles' commas out of #{?...}
rgb='#{m:*RGB*,#{client_termfeatures}}'
c256='#{||:#{m:*256*,#{client_termfeatures}},#{m:*256*,#{client_termname}}}'
tier() { echo "#{?$rgb,#{E:@axolotl-$1-rgb},#{?$c256,#{E:@axolotl-$1-256},#{E:@axolotl-$1-ansi}}}"; }
nogit='#{==:#{@workspace-active},(no repo)}'

tmux set-option -g status-style "bg=default,fg=default"
tmux set-option -g status-left-length 60
tmux set-option -g status-right-length 80
tmux set-option -g window-status-separator ''
tmux set-option -g status-left "$(tier left)"
tmux set-option -g status-right "#{?$nogit,$(tier right-nogit),$(tier right-git)}"
tmux set-option -g window-status-format "$(tier win)"
tmux set-option -g window-status-current-format "$(tier cur)"
