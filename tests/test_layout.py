"""Exercise the real tmux format renderer on an isolated server."""

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
STYLE = re.compile(r"#\[[^\]]*\]")


class StatusLayoutTest(unittest.TestCase):
    def setUp(self):
        for command in ("tmux", "bash"):
            if shutil.which(command) is None:
                self.skipTest(f"{command} is required")
        self.temp = tempfile.TemporaryDirectory(prefix="axolotl-tabs-")
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.socket = str(directory / "socket")
        self.binary = shutil.which("tmux")
        self.env = os.environ.copy()
        self.env.pop("TMUX", None)
        bindir = directory / "bin"
        bindir.mkdir()
        wrapper = bindir / "tmux"
        wrapper.write_text(
            f"#!/bin/sh\nexec {shlex.quote(self.binary)} "
            f"-S {shlex.quote(self.socket)} \"$@\"\n"
        )
        wrapper.chmod(0o755)
        self.env["PATH"] = str(bindir) + os.pathsep + self.env["PATH"]
        self.addCleanup(self.stop_server)
        first = self.tmux(
            "-f", "/dev/null", "new-session", "-d", "-s", "tabs", "-n", "fish",
            "-P", "-F", "#{window_id}", "/bin/sh",
        ).strip()
        self.windows = [first]
        for _ in range(2):
            self.windows.append(self.tmux(
                "new-window", "-n", "fish", "-P", "-F", "#{window_id}", "/bin/sh",
            ).strip())
        self.tmux("set-option", "-g", "@axolotl-scheme", "kanagawa-dragon")
        self.tmux("set-option", "-g", "@axolotl-scheme-key", "off")

    def stop_server(self):
        subprocess.run([self.binary, "-S", self.socket, "kill-server"], capture_output=True)

    def tmux(self, *args):
        return subprocess.run(
            [self.binary, "-S", self.socket, *args], env=self.env,
            check=True, text=True, capture_output=True, timeout=15,
        ).stdout

    def load_theme(self, numbers):
        self.tmux("set-option", "-g", "@axolotl-numbers", numbers)
        result = subprocess.run(
            [shutil.which("bash"), str(ROOT / "tmux-axolotl.tmux")],
            env=self.env, check=True, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.stderr, "")

    def select(self, active):
        self.tmux("select-window", "-t", self.windows[active])
        for i, window in enumerate(self.windows):
            position = "only" if len(self.windows) == 1 else "first" if i == 0 else "last" if i == len(self.windows) - 1 else "mid"
            for name, value in (("pos", position), ("slot", str(i)),
                                ("nextact", str(int(i + 1 == active)))):
                self.tmux("set-option", "-w", "-t", window, "@workspace-" + name, value)

    def rendered_tab(self, window, tier, active=False):
        kind = "cur" if active else "win"
        result = self.tmux("display-message", "-p", "-t", window,
                           f"#{{E:@axolotl-{kind}-{tier}}}")
        return STYLE.sub("", result.rstrip("\n"))

    def test_tab_left_of_active_has_one_right_padding_cell(self):
        for numbers in ("off", "on"):
            self.load_theme(numbers)
            for active in (1, 2):
                self.select(active)
                for tier in ("rgb", "256", "ansi"):
                    with self.subTest(numbers=numbers, active=active, tier=tier):
                        tab = self.rendered_tab(self.windows[active - 1], tier)
                        self.assertTrue(tab.endswith("fish "), repr(tab))

    def assert_stable_titles(self):
        for tier in ("rgb", "256", "ansi"):
            layouts = []
            for active in range(len(self.windows)):
                # Inspect both the initial redraw (neighbour flags still stale)
                # and the settled redraw after workspace metadata updates.
                self.tmux("select-window", "-t", self.windows[active])
                for settled in (False, True):
                    if settled:
                        self.select(active)
                    offset = 0
                    positions = []
                    for i, window in enumerate(self.windows):
                        title = self.tmux("display-message", "-p", "-t", window,
                                          "#{=/4/…:window_name}").strip()
                        tab = self.rendered_tab(window, tier, i == active)
                        positions.append(offset + tab.index(title))
                        offset += len(tab)
                    layouts.append((positions, offset))
            with self.subTest(tier=tier):
                self.assertEqual(layouts, [layouts[0]] * len(layouts))

    def test_selection_curves_update_before_workspace_hooks(self):
        self.load_theme("off")
        # A hidden window between visible neighbours prevents accidentally using
        # physical window indexes as adjacency. Slots describe the visible run.
        hidden = self.tmux("new-window", "-d", "-P", "-F", "#{window_id}", "/bin/sh").strip()
        self.tmux("swap-window", "-s", hidden, "-t", self.windows[1])
        self.tmux("swap-window", "-s", self.windows[1], "-t", self.windows[2])
        for old_active in range(3):
            for new_active in range(3):
                self.select(old_active)
                self.tmux("select-window", "-t", self.windows[new_active])
                # No layout/sync call: both stale 1s and stale 0s must be ignored.
                before = {}
                for tier in ("rgb", "256", "ansi"):
                    for i, window in enumerate(self.windows):
                        kind = "cur" if i == new_active else "win"
                        raw = self.tmux("display-message", "-p", "-t", window,
                                        f"#{{E:@axolotl-{kind}-{tier}}}")
                        before[tier, window] = raw
                        tab = STYLE.sub("", raw).rstrip("\n")
                        expected_edge = "" if i + 1 == new_active else ""
                        with self.subTest(old=old_active, new=new_active, tier=tier, tab=i):
                            self.assertTrue(tab.endswith(expected_edge), repr(tab))
                    # The status line uses a W loop; also check nested native
                    # selection lookup in that exact rendering context.
                    fmt = ("#{W:#{?#{!=:#{@workspace-slot},},#{E:@axolotl-win-" + tier + "},},"
                           "#{E:@axolotl-cur-" + tier + "}}")
                    raw = self.tmux("display-message", "-p", fmt)
                    self.assertEqual(raw.rstrip("\n"), "".join(
                        before[tier, window].rstrip("\n") for window in self.windows))
                self.select(new_active)
                for (tier, window), raw in before.items():
                    kind = "cur" if window == self.windows[new_active] else "win"
                    self.assertEqual(raw, self.tmux("display-message", "-p", "-t", window,
                                                   f"#{{E:@axolotl-{kind}-{tier}}}"))

    def test_title_columns_and_bar_width_stay_fixed(self):
        for window, name in zip(self.windows, ("sh", "editor", "long-window-name")):
            self.tmux("rename-window", "-t", window, name)
        for gradient in ("flat", "alternate", "fade"):
            self.tmux("set-option", "-g", "@axolotl-gradient", gradient)
            for numbers in ("off", "on"):
                with self.subTest(gradient=gradient, numbers=numbers):
                    self.load_theme(numbers)
                    self.select(0)
                    self.assert_stable_titles()

    def test_zoom_indicator_does_not_move_titles_on_selection(self):
        self.tmux("split-window", "-t", self.windows[1], "/bin/sh")
        self.tmux("resize-pane", "-Z", "-t", self.windows[1])
        self.load_theme("off")
        self.select(0)
        self.assert_stable_titles()

    def test_single_window_has_both_outer_caps(self):
        for window in self.windows[1:]:
            self.tmux("kill-window", "-t", window)
        self.windows = self.windows[:1]
        self.load_theme("off")
        self.select(0)
        for tier in ("rgb", "256", "ansi"):
            self.assertEqual(self.rendered_tab(self.windows[0], tier, True), " fish ")

    def test_expanding_titles_are_opt_in(self):
        self.tmux("rename-window", "-t", self.windows[0], "long-window-name")
        self.tmux("set-option", "-g", "@axolotl-title-mode", "expand")
        self.load_theme("off")
        self.select(0)
        for tier in ("rgb", "256", "ansi"):
            self.assertIn("long-window-name", self.rendered_tab(self.windows[0], tier, True))
            self.assertNotIn("long-window-name", self.rendered_tab(self.windows[0], tier))

    def attach_client(self):
        self.client = subprocess.Popen(
            [self.binary, "-S", self.socket, "-C", "attach-session", "-t", "tabs"],
            env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        def stop_client():
            self.client.terminate()
            self.client.communicate(timeout=5)
        self.addCleanup(stop_client)
        for _ in range(100):
            name = self.tmux("list-clients", "-F", "#{client_name}").strip()
            if name:
                return name
            time.sleep(0.01)
        self.fail("control client did not attach")

    def configure_panel(self):
        self.tmux("set-option", "-g", "@axolotl-panel-gradient", "flat")
        for side in ("left", "right"):
            self.tmux("set-option", "-g", "@axolotl-" + side, "a b c")
        for name, style, minimum, icon in (("a", "surface", "110", "A"),
                                           ("b", "accent", "90", ""),
                                           ("c", "surface", "70", "C")):
            for suffix, value in (("", name.upper() * 3), ("-icon", icon),
                                  ("-style", style), ("-min", minimum),
                                  ("-if", "#{@test-show-" + name + "}")):
                self.tmux("set-option", "-g", "@axolotl-segment-" + name + suffix, value)
            self.tmux("set-option", "-g", "@test-show-" + name, "1")
        self.load_theme("off")

    def test_panels_join_visible_neighbours_at_each_client_width(self):
        client = self.attach_client()
        self.configure_panel()
        for width in (160, 100, 80, 60):
            self.tmux("refresh-client", "-t", client, "-C", f"{width},24")
            for mask in range(8):
                for i, name in enumerate("abc"):
                    self.tmux("set-option", "-g", "@test-show-" + name, str((mask >> i) & 1))
                visible = [name for i, name in enumerate("abc")
                           if (mask >> i) & 1 and (name != "b" or width >= 90)]
                bodies = {"a": "A AAA" if width >= 110 else "A", "b": "BBB",
                          "c": "C CCC" if width >= 70 else "C"}
                for side in ("left", "right"):
                    join = "" if side == "left" else ""
                    expected = ("" + join.join(" " + bodies[n] + " " for n in visible)
                                + "") if visible else ""
                    for tier in ("rgb", "256", "ansi"):
                        with self.subTest(width=width, mask=mask, side=side, tier=tier):
                            raw = self.tmux("display-message", "-p", "-c", client,
                                            f"#{{E:@axolotl-{side}-{tier}}}").rstrip("\n")
                            self.assertEqual(STYLE.sub("", raw), expected)
                            # Verify the foreground/background swap as well as
                            # the glyph direction at each internal boundary.
                            palette = {key: self.tmux("show-option", "-gqv",
                                       f"@axolotl-pal-{tier}-{key}").strip()
                                       for key in ("surface", "accent")}
                            for i, name in enumerate(visible):
                                own = palette["accent" if name == "b" else "surface"]
                                nxt = (palette["accent" if visible[i + 1] == "b" else "surface"]
                                       if i + 1 < len(visible) else "default")
                                if side == "right" and i + 1 < len(visible):
                                    self.assertIn(f"#[fg={nxt}]#[bg={own}]", raw)
                                else:
                                    self.assertIn(f"#[fg={own}]#[bg={nxt}]", raw)

    def test_modules_can_move_between_panels(self):
        client = self.attach_client()
        self.tmux("refresh-client", "-t", client, "-C", "180,24")
        self.tmux("set-option", "-g", "@axolotl-segment-session-icon", "S")
        self.tmux("set-option", "-g", "@axolotl-segment-cwd-icon", "D")
        self.tmux("set-option", "-g", "@axolotl-segment-pane-icon", "P")
        self.tmux("set-option", "-g", "@axolotl-segment-clock-icon", "T")
        for left, right in (("session cwd", "pane clock"),
                            ("clock pane", "cwd session")):
            self.tmux("set-option", "-g", "@axolotl-left", left)
            self.tmux("set-option", "-g", "@axolotl-right", right)
            self.load_theme("off")
            for side, names in (("left", left.split()), ("right", right.split())):
                raw = self.tmux("display-message", "-p", "-c", client,
                                f"#{{E:@axolotl-{side}-rgb}}")
                bar = STYLE.sub("", raw)
                self.assertEqual(bar.count("" if side == "right" else ""),
                                 len(names))
                self.assertIn("tabs" if "session" in names else "P sh" if "pane" in names else "D", bar)
                self.assertNotIn("#(", self.tmux("show-option", "-gqv",
                    f"@axolotl-{side}-rgb"))
                if "clock" in names:
                    self.assertRegex(bar, r"\b[0-2][0-9]:[0-5][0-9]\b")
                if "cwd" in names:
                    cwd = self.tmux("display-message", "-p", "-c", client,
                                    "#{b:pane_current_path}").strip()
                    self.assertIn("D " + cwd, bar)
                for name in names:
                    icon = {"session": "S", "cwd": "D", "pane": "P", "clock": "T"}[name]
                    self.assertIn(icon + " ", bar)

    def test_empty_panel_and_icon_override(self):
        client = self.attach_client()
        self.tmux("refresh-client", "-t", client, "-C", "160,24")
        self.tmux("set-option", "-g", "@axolotl-left", "none")
        self.tmux("set-option", "-g", "@axolotl-right", "session")
        self.tmux("set-option", "-g", "@axolotl-segment-session-icon", "none")
        self.load_theme("off")
        self.assertEqual(self.tmux("display-message", "-p", "-c", client,
                         "#{E:@axolotl-left-rgb}").strip(), "")
        raw = self.tmux("display-message", "-p", "-c", client,
                        "#{E:@axolotl-right-rgb}")
        self.assertEqual(STYLE.sub("", raw).strip(), " tabs ")

    def test_panel_gradient_runs_from_outer_edges_to_centre(self):
        self.configure_panel()
        self.tmux("set-option", "-g", "@axolotl-segment-b-style", "surface")
        shades = {}
        for mode in ("flat", "alternate", "fade"):
            self.tmux("set-option", "-g", "@axolotl-panel-gradient", mode)
            self.load_theme("off")
            self.assertEqual(self.tmux("show-option", "-gqv", "status-justify").strip(),
                             "absolute-centre")
            for side in ("left", "right"):
                shades[mode, side] = []
                for i in range(3):
                    raw = self.tmux("show-option", "-gqv",
                                    f"@axolotl-panel-{side}-rgb-{i}-long")
                    shades[mode, side].append(re.search(r"#\[bg=([^\]]+)\]", raw).group(1))
            self.assertEqual(shades[mode, "left"], list(reversed(shades[mode, "right"])))
        self.assertEqual(len(set(shades["flat", "left"])), 1)
        self.assertEqual(len(set(shades["alternate", "left"])), 2)
        self.assertEqual(len(set(shades["fade", "left"])), 3)
        # Increasing the strength must move the inner shade farther from the
        # surface while keeping the outer shade and accent segment unchanged.
        self.tmux("set-option", "-g", "@axolotl-panel-gradient-strength", "70")
        self.load_theme("off")
        raw = self.tmux("show-option", "-gqv", "@axolotl-panel-left-rgb-2-long")
        stronger = re.search(r"#\[bg=([^\]]+)\]", raw).group(1)
        base = shades["fade", "left"][0]
        mild = shades["fade", "left"][2]
        self.assertGreater(int(stronger[1:3], 16) - int(base[1:3], 16),
                           int(mild[1:3], 16) - int(base[1:3], 16))

    def test_custom_segment_literals_survive_configuration_transport(self):
        client = self.attach_client()
        literal = "O'Reilly \"$HOME\" \\path ; #"
        self.tmux("set-option", "-g", "@axolotl-left", "literal")
        self.tmux("set-option", "-g", "@axolotl-segment-literal-icon", literal)
        self.load_theme("off")
        raw = self.tmux("display-message", "-p", "-c", client, "#{E:@axolotl-left-rgb}")
        self.assertEqual(STYLE.sub("", raw).rstrip("\n"), " " + literal + " ")

    def test_workspace_pill_uses_current_window_without_hook(self):
        client = self.attach_client()
        self.tmux("refresh-client", "-t", client, "-C", "160,24")
        roots = ("/tmp/alpha", "/tmp/beta", "(no repo)")
        for window, root in zip(self.windows, roots):
            self.tmux("set-option", "-w", "-t", window, "@workspace", root)
        self.load_theme("off")
        for window, expected in zip(self.windows, ("alpha", "beta", "(no repo)")):
            self.tmux("select-window", "-t", window)
            raw = self.tmux("display-message", "-p", "-c", client, "#{E:@axolotl-right-rgb}")
            self.assertIn(expected, STYLE.sub("", raw))

    def test_builtin_branch_hides_without_breaking_workspace_pill(self):
        client = self.attach_client()
        self.tmux("refresh-client", "-t", client, "-C", "160,24")
        self.tmux("set-option", "-g", "@axolotl-segment-branch", "main")
        self.load_theme("off")
        for workspace, count in (("/tmp/project", 2), ("(no repo)", 1)):
            self.tmux("set-option", "-w", "-t", self.windows[2], "@workspace", workspace)
            raw = self.tmux("display-message", "-p", "-c", client, "#{E:@axolotl-right-rgb}")
            bar = STYLE.sub("", raw).strip()
            self.assertEqual(bar.count(""), count)
            self.assertEqual(bar.count(""), 1)
            self.assertEqual("main" in bar, count == 2)


if __name__ == "__main__":
    unittest.main()
