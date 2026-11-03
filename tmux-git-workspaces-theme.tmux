#!/usr/bin/env bash
# Minimal workspace-aware status bar. Needs a Nerd Font / powerline glyphs and
# the tmux-git-workspaces plugin (which provides @workspace / @workspace-active).
# Colours default to the terminal's ANSI palette, so the bar follows your
# terminal theme. Override with any tmux colour (names, colourN, #hex).
dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

opt() { local v; v=$(tmux show-option -gqv "$1"); echo "${v:-$2}"; }
accent=$(opt @wstheme-accent 'yellow')
fg=$(opt @wstheme-fg 'default')
muted=$(opt @wstheme-muted 'brightblack')
dark=$(opt @wstheme-dark 'black')   # text on the accent pill

arrow=$''; branch_icon=$''; bar=$'▎'
bell=$''; zoom=$''

ws='#{?#{@workspace-active},#{b:@workspace-active},#S}'
git="#(git -C '#{@workspace-active}' branch --show-current 2>/dev/null)"

tmux set-option -g status-style "bg=default,fg=$fg"
tmux set-option -g status-left-length 80
tmux set-option -g status-right-length 120
tmux set-option -g window-status-separator ''

tmux set-option -g status-left "#[fg=$dark]#[bg=$accent]#[bold] $ws #[nobold]#[fg=$accent]#[bg=default]$arrow#[fg=$muted] $branch_icon $git  "
tmux set-option -g status-right "#[fg=$muted]#('$dir/scripts/others.sh' '#{@workspace-active}') #[default]"

tmux set-option -g window-status-format "#[fg=$muted] #I #W#{?window_bell_flag,#[fg=$accent] $bell,} "
tmux set-option -g window-status-current-format "#[fg=$accent]$bar#[fg=$fg]#[bold]#I #W#[nobold]#{?window_zoomed_flag,#[fg=$accent] $zoom,} "
