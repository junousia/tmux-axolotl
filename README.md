# tmux-axolotl

A tmux status bar with a UI feel: powerline pill and rounded tabs, with colours that adapt to your terminal. Works best with [tmux-git-workspaces](https://github.com/junousia/tmux-git-workspaces), which it uses to group windows by git repository.

```
 (0 shell) 1 vim                                           master  ws-a
```

The bar is built from small widgets with Nerd Font glyphs:

- **Left, tabs:** only the current workspace's windows. The active one is a rounded tab with an accent index; others are muted. Bell and zoom each get a glyph.
- **Right, branch and workspace pill:** the git branch in a soft segment, then the workspace name in an accent pill (the branch segment is omitted outside a git repo).

To put the pill on the left edge instead (branch stays on the right):

```tmux
set -g @axolotl-pill 'left'
```

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
set -g @plugin 'junousia/tmux-axolotl'
set -g @plugin 'junousia/tmux-git-workspaces'
```

## Options

Any tmux colour works: ANSI names (`yellow`, `brightblack`), `colourN`, or `#rrggbb`. An option overrides that colour in every palette tier.

```tmux
set -g @axolotl-accent 'yellow'       # pill, active tab index, bell glyph
set -g @axolotl-fg 'white'            # text on the branch segment and active tab
set -g @axolotl-muted 'brightblack'   # inactive windows
set -g @axolotl-dark 'black'          # text on the accent pill
```

## License

MIT
