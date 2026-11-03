# tmux-heron

A tmux status bar with a UI feel: powerline pill, rounded tabs and chips, with colours that adapt to your terminal. Works best with [tmux-git-workspaces](https://github.com/junousia/tmux-git-workspaces), which it uses to group windows by git repository.

```
 ws-a  master  (0 shell) 1 vim                         ws-b 1  ws-c 1  (no repo) 1
```

The bar is built from small widgets with Nerd Font glyphs:

- **Left, workspace pill:** the current workspace in an accent pill, joined by a powerline arrow to a branch segment (omitted outside a git repo).
- **Middle, tabs:** only the current workspace's windows. The active one is a rounded tab with an accent index; others are muted. Bell and zoom each get a glyph.
- **Right, chips:** every other workspace as a rounded chip with its window count. An accent dot means a window there rang the bell.

## Colours

The bar picks a palette per client, based on what the terminal supports:

| Terminal | Palette |
| --- | --- |
| Truecolor (`RGB` feature) | Refined RGB palette with soft surface tones |
| 256 colours | Tuned `colourN` values |
| Basic | The terminal's ANSI palette, so the bar follows your terminal theme |

For truecolor, make sure tmux knows about it, e.g. `set -as terminal-features ',xterm-256color:RGB'`.

## Requirements

- tmux 3.3+
- A [Nerd Font](https://www.nerdfonts.com/) (or any font with powerline glyphs) in your terminal
- [tmux-git-workspaces](https://github.com/junousia/tmux-git-workspaces), which tags windows with their workspace and filters the window list

## Install

With [TPM](https://github.com/tmux-plugins/tpm), list the theme **before** the plugin and remove other status bar themes (such as tmux2k):

```tmux
set -g @plugin 'junousia/tmux-heron'
set -g @plugin 'junousia/tmux-git-workspaces'
```

## Options

Any tmux colour works: ANSI names (`yellow`, `brightblack`), `colourN`, or `#rrggbb`. An option overrides that colour in every palette tier.

```tmux
set -g @heron-accent 'yellow'       # pill, active tab index, bell dot
set -g @heron-fg 'white'            # text on tabs and chips
set -g @heron-muted 'brightblack'   # inactive windows
set -g @heron-dark 'black'          # text on the accent pill
```

## License

MIT
