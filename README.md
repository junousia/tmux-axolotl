# tmux-axolotl

A compact tmux status bar with connected, rounded segments and colours that adapt to your terminal. Works best with [tmux-git-workspaces](https://github.com/junousia/tmux-git-workspaces), which it uses to group windows by git repository.

```
 ( host )             ( shell | vim | logs )             ( main | workspace )
```

The bar is built from small widgets with Nerd Font glyphs:

- **Left:** hostname, or your own segment list.
- **Centre:** the current workspace's windows in one connected bar. Selection changes the colours while title positions stay fixed. Bell and zoom state have their own glyphs.
- **Right:** branch and workspace joined into one pill group; the branch disappears outside a git repo.

To put the pill on the left edge instead (branch stays on the right):

```tmux
set -g @axolotl-pill 'left'
```

## Side panels and segments

Each side panel is one connected group of segments, with rounded outer ends and shared internal boundaries. The joins curve toward the centre of the status bar: right on the left panel, left on the right panel:

```tmux
set -g @axolotl-left  'host'                    # default
set -g @axolotl-right 'branch workspace'        # default
```

Built-in segments: `host`, `branch` (hidden outside git repos), and `workspace`. Each segment has a long and a short form and **expands as the terminal gets wider**: the long form needs a client width of at least `@axolotl-segment-<name>-min` columns (host 110, branch 90, workspace 70, your own 100), below that the short form is shown (just the icon unless you set `-short`). The width thresholds determine which segments collapse first. Iconless segments with no short form disappear. Hidden segments leave no gaps or orphaned caps; their visible neighbours join directly.

**Add your own**, from `tmux.conf` or from another plugin:

```tmux
set -g @axolotl-segment-load        '#(cut -d" " -f1 /proc/loadavg)'   # any tmux format, #() included
set -g @axolotl-segment-load-icon   ''                                # optional
set -g @axolotl-segment-load-short  ''                                # optional short form (default: icon only)
set -g @axolotl-segment-load-style  'surface'                          # or 'accent'
set -g @axolotl-segment-load-if     '#{==:#{pane_current_command},ssh}'  # optional condition
set -g @axolotl-segment-load-min    '100'                              # width needed for the long form
set -g @axolotl-right 'load branch workspace'
```

Segments take the theme's colours (scheme, tier, overrides) automatically. Colours in a segment's own format are yours to choose. Conditions must not contain bare commas outside `#{...}`. A plugin that registers a segment must load *before* tmux-axolotl (TPM loads in `@plugin` order), or re-run `~/.tmux/plugins/tmux-axolotl/tmux-axolotl.tmux` afterwards.

## Stable window tabs

Tabs share the same padding and boundary geometry as the side panels. Each tab
owns one boundary cell to its right, including the curve leading into the active
tab. Selection and workspace metadata updates therefore cannot insert or remove
separator cells. The active curve is chosen from tmux's live selection during
the same redraw as the highlight; it does not wait for workspace shell hooks.

By default, active and inactive titles use the same `@axolotl-abbrev` limit (4).
Increase it for more readable titles while keeping selection steady:

```tmux
set -g @axolotl-abbrev '12'
```

To restore the previous behaviour of expanding the selected title in full:

```tmux
set -g @axolotl-title-mode 'expand'  # default: stable
```

Expansion intentionally changes the bar's width when selection moves. Renaming a
window or changing its bell/zoom state can also change its content and width.

## Colour schemes

```tmux
set -g @axolotl-scheme 'terminal'   # default
```

| Scheme | |
| --- | --- |
| `terminal` | The terminal's own ANSI colours, so the bar follows your terminal theme |
| `gruvbox` | Warm amber on dark browns |
| `tokyonight` | Cool blue |
| `catppuccin` | Mocha, with a mauve accent |
| `nord` | Muted frost blue |
| `rose-pine` | Soft iris and rose tones |
| `kanagawa` | Wave: indigo-black with a crystal-blue accent |
| `kanagawa-dragon` | Dragon: darker and warmer, muted blue-grey accent |
| `kanagawa-lotus` | Lotus: a light scheme, for light terminals |

Named schemes adapt to the terminal, chosen per client: truecolor terminals get the exact hex colours, 256-colour terminals the nearest xterm colours, and basic terminals fall back to the ANSI palette. `terminal` uses the ANSI palette everywhere. For truecolor, make sure tmux knows about it, e.g. `set -as terminal-features ',xterm-256color:RGB'`.

**Switching live:** `prefix + T` opens a picker with colour swatches. The bar previews each scheme as you move through the list; Enter keeps it, Esc restores the previous one. The switch lasts until tmux restarts: put `set -g @axolotl-scheme '<name>'` in `tmux.conf` to keep it. Needs `fzf`. Change the key with `set -g @axolotl-scheme-key 'X'`, or `off` to disable the binding.

Add your own by dropping a file in `schemes/` that sets `accent`, `fg`, `muted`, `dark`, `surface` and `active` as `#rrggbb` values (see `schemes/gruvbox`).

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

Any tmux colour works: ANSI names (`yellow`, `brightblack`), `colourN`, or `#rrggbb`. A colour option overrides that colour of the scheme in every tier.

```tmux
set -g @axolotl-pill 'right'          # or 'left': moves the workspace segment to the left panel (see segments)
set -g @axolotl-numbers 'on'          # 'off' hides window numbers (the active tab's name takes the accent)
set -g @axolotl-gradient 'fade'       # inactive tab shading: fade | alternate | flat (default: fade; flat for the 'terminal' scheme)
set -g @axolotl-gradient-steps '4'    # number of shades a fade uses (2-8)
set -g @axolotl-abbrev '4'            # title limit for both selection states
set -g @axolotl-title-mode 'stable'   # 'expand' shows the selected title in full
set -g @axolotl-host 'on'             # 'off' hides the hostname pill
set -g @axolotl-justify 'centre'      # 'left' left-aligns the tabs
set -g @axolotl-accent 'yellow'       # pill, active tab index, bell glyph
set -g @axolotl-fg 'white'            # text on the branch segment and active tab
set -g @axolotl-muted 'brightblack'   # inactive windows
set -g @axolotl-dark 'black'          # text on the accent pill
set -g @axolotl-surface 'brightblack' # branch segment background
set -g @axolotl-active 'brightblack'  # active tab background
```

## Sharing the palette

The resolved palette is published as tmux options, `@axolotl-pal-<tier>-<name>` (tier `rgb`, `256` or `ansi`; names `accent`, `fg`, `muted`, `dark`, `surface`, `active`), so other plugins can match the bar. [tmux-git-workspaces](https://github.com/junousia/tmux-git-workspaces) uses them for its picker.

## Development checks

Run `python3 -B -m unittest discover -s tests -v` with tmux and Bash on `PATH`.
The checks use private tmux servers and control clients; existing sessions are
not touched. They cover title columns and selection curves before and after workspace updates, filtered
window gaps, all
three colour tiers and gradients, window numbers, zoom state, single tabs,
optional title expansion, panel visibility and width thresholds, seam colours,
and literal custom segment values.

`scripts/render.sh` contains the shared body/cap geometry and panel composition.
The main script resolves options and palettes, then streams one quoted
configuration to tmux. Layouts are evaluated per client without polling or shell
commands for their boundaries.

## License

MIT
