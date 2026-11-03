#!/usr/bin/env bash
# Workspace-aware status bar with a UI feel: powerline pill, rounded tabs and
# chips. Needs a Nerd Font and the tmux-git-workspaces plugin (which provides
# @workspace / @workspace-active).
#
# Colours are tiered and chosen per client at render time:
#   truecolor (RGB)  refined palette with soft surface tones
#   256 colours      tuned colourN values
#   basic            the terminal's ANSI palette, so the bar follows its theme
# A @wstheme-* option overrides that colour in every tier.
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

opt() { local v; v=$(tmux show-option -gqv "$1"); echo "${v:-$2}"; }

# glyphs as UTF-8 bytes (independent of the locale this script runs in)
arrow=$'\xee\x82\xb0'; lcap=$'\xee\x82\xb6'; rcap=$'\xee\x82\xb4'
branch_icon=$'\xee\x82\xa0'; folder=$'\xef\x81\xbb'
bell=$'\xef\x83\xb3'; zoom=$'\xef\x80\x8e'

ws='#{?#{@workspace-active},#{b:@workspace-active},#S}'
git="#(git -C '#{@workspace-active}' branch --show-current 2>/dev/null)"

# build <tier> <accent> <text> <muted> <dark> <surface> <active-surface>
build() {
  local t=$1 accent=$2 text=$3 muted=$4 dark=$5 surf=$6 act=$7

  # workspace pill; with a branch segment unless the workspace is (no repo)
  local pill="#[fg=$accent]#[bg=default]$lcap#[fg=$dark]#[bg=$accent]#[bold]$folder $ws #[nobold]"
  tmux set-option -g "@wstheme-left-git-$t" \
    "$pill#[fg=$accent]#[bg=$surf]$arrow#[fg=$text]#[bg=$surf] $branch_icon $git #[fg=$surf]#[bg=default]$arrow "
  tmux set-option -g "@wstheme-left-nogit-$t" \
    "$pill#[fg=$accent]#[bg=default]$arrow "

  tmux set-option -g "@wstheme-right-$t" \
    "#('$dir/scripts/others.sh' '#{@workspace-active}' '$surf' '$text' '$accent')#[default]"

  tmux set-option -g "@wstheme-win-$t" \
    "#[fg=$muted] #I #W#{?window_bell_flag,#[fg=$accent] $bell,} "
  tmux set-option -g "@wstheme-cur-$t" \
    "#[fg=$act]#[bg=default]$lcap#[fg=$accent]#[bg=$act]#[bold]#I #[fg=$text]#W#[nobold]#{?window_zoomed_flag,#[fg=$accent] $zoom,}#[fg=$act]#[bg=default]$rcap"
}

build rgb \
  "$(opt @wstheme-accent '#d79921')" "$(opt @wstheme-fg '#d5c4a1')" \
  "$(opt @wstheme-muted '#7c6f64')" "$(opt @wstheme-dark '#1d2021')" "#3c3836" "#504945"
build 256 \
  "$(opt @wstheme-accent colour172)" "$(opt @wstheme-fg colour187)" \
  "$(opt @wstheme-muted colour243)" "$(opt @wstheme-dark colour234)" colour237 colour239
build ansi \
  "$(opt @wstheme-accent yellow)" "$(opt @wstheme-fg white)" \
  "$(opt @wstheme-muted brightblack)" "$(opt @wstheme-dark black)" brightblack brightblack

# pick the tier per client; #{E:...} keeps the styles' commas out of #{?...}
rgb='#{m:*RGB*,#{client_termfeatures}}'
c256='#{||:#{m:*256*,#{client_termfeatures}},#{m:*256*,#{client_termname}}}'
tier() { echo "#{?$rgb,#{E:@wstheme-$1-rgb},#{?$c256,#{E:@wstheme-$1-256},#{E:@wstheme-$1-ansi}}}"; }
nogit='#{==:#{@workspace-active},(no repo)}'

tmux set-option -g status-style "bg=default,fg=default"
tmux set-option -g status-left-length 80
tmux set-option -g status-right-length 160
tmux set-option -g window-status-separator ''
tmux set-option -g status-left "#{?$nogit,$(tier left-nogit),$(tier left-git)}"
tmux set-option -g status-right "$(tier right)"
tmux set-option -g window-status-format "$(tier win)"
tmux set-option -g window-status-current-format "$(tier cur)"
