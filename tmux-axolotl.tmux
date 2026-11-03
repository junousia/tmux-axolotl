#!/usr/bin/env bash
# tmux-axolotl: status bar with a UI feel: powerline pill and rounded tabs.
# Needs a Nerd Font and the tmux-git-workspaces plugin (which provides
# @workspace / @workspace-active).
#
# Layout: tabs on the left; branch segment and workspace pill on the right.
# @axolotl-pill 'left' moves the pill to the left edge instead.
#
# Colours are tiered and chosen per client at render time:
#   truecolor (RGB)  refined palette with soft surface tones
#   256 colours      tuned colourN values
#   basic            the terminal's ANSI palette, so the bar follows its theme
# An @axolotl-* option overrides that colour in every tier.
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

# build <tier> <accent> <text> <muted> <dark> <surface> <active-surface>
build() {
  local t=$1 accent=$2 text=$3 muted=$4 dark=$5 surf=$6 act=$7
  local body="#[fg=$dark]#[bg=$accent]#[bold]$folder $ws #[nobold]"

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
    "#[fg=$muted] #I #W#{?window_bell_flag,#[fg=$accent] $bell,} "
  tmux set-option -g "@axolotl-cur-$t" \
    "#[fg=$act]#[bg=default]$lcap#[fg=$accent]#[bg=$act]#[bold]#I #[fg=$text]#W#[nobold]#{?window_zoomed_flag,#[fg=$accent] $zoom,}#[fg=$act]#[bg=default]$rcap"
}

build rgb \
  "$(opt @axolotl-accent '#d79921')" "$(opt @axolotl-fg '#d5c4a1')" \
  "$(opt @axolotl-muted '#7c6f64')" "$(opt @axolotl-dark '#1d2021')" "#3c3836" "#504945"
build 256 \
  "$(opt @axolotl-accent colour172)" "$(opt @axolotl-fg colour187)" \
  "$(opt @axolotl-muted colour243)" "$(opt @axolotl-dark colour234)" colour237 colour239
build ansi \
  "$(opt @axolotl-accent yellow)" "$(opt @axolotl-fg white)" \
  "$(opt @axolotl-muted brightblack)" "$(opt @axolotl-dark black)" brightblack brightblack

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
