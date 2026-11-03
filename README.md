# tmux-git-workspaces-theme

A minimal tmux status bar built around git workspaces. Companion to [tmux-git-workspaces](https://github.com/junousia/tmux-git-workspaces).

```
 ws-a  master  ▎0 shell   1 vim                         ws-b 1 · ws-c 1 · (no repo) 1
 └ pill ┘└ branch ┘└ this workspace's windows ┘                └ other workspaces ┘
```

- **Left:** the current workspace as a small powerline pill, with its git branch.
- **Middle:** only the current workspace's windows. The active one is marked with a `▎` bar; a bell and zoom each get a glyph.
- **Right:** the other workspaces and their window counts, dim. A trailing `●` means a window there rang the bell.
- **Colours follow your terminal theme.** The defaults are the terminal's ANSI palette (`yellow`, `brightblack`, `black`, `default`), so changing your terminal colour scheme changes the bar. The bar background is transparent.

## Requirements

- tmux 3.3+
- A [Nerd Font](https://www.nerdfonts.com/) (or any font with powerline glyphs) in your terminal
- [tmux-git-workspaces](https://github.com/junousia/tmux-git-workspaces), which tags windows with their workspace and filters the window list

## Install

With [TPM](https://github.com/tmux-plugins/tpm), list the theme **before** the plugin and remove other status bar themes:

```tmux
set -g @plugin 'junousia/tmux-git-workspaces-theme'
set -g @plugin 'junousia/tmux-git-workspaces'
```

## Options

Any tmux colour works: ANSI names (`yellow`, `brightblack`), `colourN`, or `#rrggbb`.

```tmux
set -g @wstheme-accent 'yellow'       # pill and active-window bar
set -g @wstheme-fg 'default'          # active window text
set -g @wstheme-muted 'brightblack'   # inactive windows, branch, other workspaces
set -g @wstheme-dark 'black'          # text on the accent pill
```

## License

MIT
