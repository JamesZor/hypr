#!/usr/bin/env python3
"""Workspace overview for Hyprland 0.57.2. The JSON modes do not need GTK."""

import argparse
from collections import defaultdict
from contextlib import contextmanager, suppress
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import unicodedata


DIGITS = "1234567890"


def records(value):
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []


def text(value):
    return value if isinstance(value, str) else ""


def coordinate(value):
    return value if type(value) in (int, float) else 0


def decimal(value):
    if type(value) is int:
        return value
    if isinstance(value, str) and re.fullmatch(r"[+-]?\d+", value.strip()):
        with suppress(ValueError):
            return int(value)
    return None


def workspace_id(ref):
    if isinstance(ref, dict) and ref.get("type") != "special":
        wid = ref.get("id")
        if type(wid) is int and wid >= 1:
            return wid
    return None


def hyprctl(*args):
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, encoding="utf-8", timeout=2)
    except (OSError, subprocess.TimeoutExpired, UnicodeError):
        return None


def query(subject):
    reply = hyprctl("-j", subject)
    if reply is not None and reply.returncode == 0:
        with suppress(ValueError, RecursionError):
            return records(json.loads(reply.stdout))
    return []


def dispatch(expression):
    reply = hyprctl("dispatch", expression)
    return reply is not None and reply.returncode == 0 and reply.stdout.startswith("ok")


def lua_string(value):
    # Lua short strings accept three-digit decimal byte escapes. Use those for
    # control and non-ASCII bytes, without involving the shell or long strings.
    escaped = {34: '\\"', 92: '\\\\'}
    return '"' + "".join(
        escaped.get(b, chr(b) if 32 <= b <= 126 else f"\\{b:03d}")
        for b in value.encode("utf-8", errors="surrogatepass")
    ) + '"'


def rename_workspace(wid, name):
    return dispatch(f"hl.dsp.workspace.rename({{ workspace = {wid}, name = {lua_string(name)} }})")


def read_names(path):
    if path is not None:
        with suppress(OSError, ValueError, RecursionError):
            raw = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                return {wid: name for key, name in raw.items()
                        if isinstance(name, str) and (wid := decimal(key)) is not None}
    return {}


def write_names(path, names):
    if path is None:
        return
    temporary = None
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, encoding="utf-8", mode="w", delete=False) as file:
            temporary = Path(file.name)
            json.dump(names, file)
        temporary.replace(path)
    except OSError as exc:
        print(f"overview: could not save names: {exc}", file=sys.stderr)
    finally:
        if temporary is not None:
            with suppress(OSError):
                temporary.unlink(missing_ok=True)


def bank_start(rules, monitor, description):
    for rule in rules:
        selector = rule.get("monitor")
        if rule.get("default") is not True or rule.get("enabled") is False or not isinstance(selector, str):
            continue
        matches = (description.startswith(selector[5:].strip()) if selector.startswith("desc:")
                   else monitor == selector)
        if matches:
            return decimal(rule.get("workspaceString"))
    return None


def windows_by_workspace(clients):
    def position(client):
        at = client.get("at")
        x, y = (at + [0, 0])[:2] if isinstance(at, list) else (0, 0)
        return coordinate(y), coordinate(x), text(client.get("address"))

    windows = defaultdict(list)
    for client in sorted(clients, key=position):
        wid = workspace_id(client.get("workspace"))
        app = text(client.get("class"))
        if wid is None or app == "hypr-monitor-overlay":
            continue
        title = " ".join(text(client.get("title")).split())
        windows[wid].append({"app": app or text(client.get("initialClass")) or "?",
                             "title": title if len(title) <= 60 else title[:59] + "…"})
    return windows


def read_screens(names):
    monitors = query("monitors")
    workspaces = query("workspaces")
    windows = windows_by_workspace(query("clients"))
    rules = query("workspacerules")
    live = {wid: ws for ws in workspaces if (wid := workspace_id(ws)) is not None}
    by_monitor = defaultdict(list)
    for wid, ws in live.items():
        by_monitor[text(ws.get("monitor"))].append(wid)
    empty = names.keys() - live.keys()

    def location(monitor):
        return coordinate(monitor.get("x")), coordinate(monitor.get("y")), text(monitor.get("name"))

    screens = []
    for monitor in sorted(monitors, key=location):
        connector = text(monitor.get("name"))
        if not connector or monitor.get("disabled", False) is not False:
            continue
        description = text(monitor.get("description"))
        start = bank_start(rules, connector, description)
        active = workspace_id(monitor.get("activeWorkspace"))
        ids = by_monitor[connector].copy()
        if start is not None:
            # Remove each stored-only id from consideration after its first matching screen.
            bank_empty = empty.intersection(range(start, start + 10))
            ids.extend(bank_empty)
            empty.difference_update(bank_empty)

        rows = []
        for wid in sorted(ids):
            ws = live.get(wid)
            live_name = ws.get("name") if ws is not None else None
            rows.append({
                "id": wid,
                "slot": wid - start + 1 if start is not None and start <= wid < start + 10 else None,
                "name": names.get(wid, live_name if isinstance(live_name, str) and live_name != str(wid) else None),
                "shown": ws is not None and wid == active,
                "windows": windows.get(wid, []) if ws is not None else [],
            })
        screens.append({"monitor": connector, "description": description,
                        "focused": monitor.get("focused") is True, "workspaces": rows})
    return screens, live


def landing_row(rows):
    return next((row for row in rows if row["shown"]), rows[0])


class Overview:
    def __init__(self, names_path):
        self.names_path = names_path
        self.mode = "normal"
        self.buffer = ""
        self.closed = False
        self.refresh()
        self.selected = next((row["id"] for screen in self.screens if screen["focused"]
                              for row in screen["workspaces"] if row["shown"]),
                             self.rows[0][1]["id"] if self.rows else None)

    def refresh(self):
        self.names = read_names(self.names_path)
        self.screens, self.live = read_screens(self.names)
        self.rows = [(i, row) for i, screen in enumerate(self.screens) for row in screen["workspaces"]]

    def model(self):
        return {"screens": self.screens, "selected": self.selected}

    def jump(self):
        wid = self.selected
        if wid is not None and dispatch(f"hl.dsp.focus({{ workspace = {wid} }})"):
            if wid in self.names and self.live.get(wid, {}).get("name") != self.names[wid]:
                rename_workspace(wid, self.names[wid])
        self.closed = True

    def commit_name(self):
        wid = self.selected
        name = "".join(c for c in self.buffer if unicodedata.category(c) != "Cc").strip()[:32]
        names = self.names.copy()
        if not name:
            names.pop(wid, None)
            if wid in self.live:
                rename_workspace(wid, str(wid))
        elif wid not in self.live or rename_workspace(wid, name):
            names[wid] = name
        if names != self.names:
            write_names(self.names_path, names)

        old_ids = [row["id"] for _, row in self.rows]
        self.refresh()
        ids = [row["id"] for _, row in self.rows]
        if wid not in ids:
            preceding = old_ids[:old_ids.index(wid)]
            self.selected = next((old for old in reversed(preceding) if old in ids), ids[0] if ids else None)
        self.mode = "normal"
        self.buffer = ""

    def key(self, key):
        if self.closed:
            return
        if key == "KP_Enter":
            key = "Return"
        if self.mode == "rename":
            if isinstance(key, dict):
                self.buffer += text(key.get("text"))
            elif key == "BackSpace":
                self.buffer = self.buffer[:-1]
            elif key == "Escape":
                self.mode = "normal"
                self.buffer = ""
            elif key == "Return":
                self.commit_name()
            return
        if key == "Escape":
            self.closed = True
            return
        if key == "Return":
            self.jump()
            return
        if self.selected is None or not isinstance(key, str):
            return

        index = next(i for i, (_, row) in enumerate(self.rows) if row["id"] == self.selected)
        screen, row = self.rows[index]
        if key == "r":
            self.mode = "rename"
            self.buffer = row["name"] or ""
        elif key in ("Up", "Down"):
            target = index + (-1 if key == "Up" else 1)
            if 0 <= target < len(self.rows):
                self.selected = self.rows[target][1]["id"]
        elif key in ("Left", "Right"):
            step = -1 if key == "Left" else 1
            for target in range(screen + step, -1 if step == -1 else len(self.screens), step):
                rows = self.screens[target]["workspaces"]
                if rows:
                    self.selected = landing_row(rows)["id"]
                    break
        elif len(key) == 1 and key in DIGITS:
            for candidate in self.screens[screen]["workspaces"]:
                if candidate["slot"] == DIGITS.index(key) + 1:
                    self.selected = candidate["id"]
                    break


@contextmanager
def pid_lock(path):
    # Serialize checking, publishing and removing pid files without creating a lock file.
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def read_pid(path):
    with suppress(OSError, ValueError):
        return decimal(path.read_text(encoding="ascii"))
    return None


def stop_overview(pid):
    if pid is None or pid <= 0 or pid == os.getpid():
        return False
    try:
        # A pidfd prevents signaling a different process if the pid gets reused.
        fd = os.pidfd_open(pid)
        try:
            if b"overview.py" in Path(f"/proc/{pid}/cmdline").read_bytes():
                signal.pidfd_send_signal(fd, signal.SIGTERM)
                return True
        finally:
            os.close(fd)
    except (OSError, OverflowError):
        pass
    return False


def toggle(path, dry_run):
    if path is not None:
        try:
            if not dry_run:
                path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            with pid_lock(path):
                if stop_overview(read_pid(path)):
                    with suppress(OSError):
                        path.unlink(missing_ok=True)
                    return True
                if not dry_run:
                    path.write_text(f"{os.getpid()}\n", encoding="ascii")
        except OSError:
            if not dry_run:
                raise
    return False


def release_pid(path):
    if path is not None:
        with suppress(OSError), pid_lock(path):
            if read_pid(path) == os.getpid():
                path.unlink(missing_ok=True)


def display_text(value):
    # Keep external strings on one line and suitable for GTK's UTF-8 C strings.
    return (value.replace("\0", "�").replace("\n", " ").replace("\r", " ")
            .encode("utf-8", errors="replace").decode("utf-8"))


def run_gui(names_path, stopping, stop):
    from gi import require_version

    require_version("Gdk", "3.0")
    require_version("Gtk", "3.0")
    require_version("GtkLayerShell", "0.1")
    from gi.repository import Gdk, GLib, Gtk, GtkLayerShell, Pango

    if not Gtk.init_check([])[0] or not GtkLayerShell.is_supported():
        raise RuntimeError("a Wayland display with layer-shell support is required")
    overview = Overview(names_path)

    def quit_loop(*_):
        stop()
        if Gtk.main_level():
            Gtk.main_quit()
        return GLib.SOURCE_REMOVE

    # A Python handler covers startup; this source can wake a sleeping Gtk.main().
    # Recent GI versions expose Unix helpers in the GLibUnix namespace instead.
    add_signal = getattr(GLib, "unix_signal_add", None)
    if add_signal is None:
        from gi.repository import GLibUnix

        add_signal = GLibUnix.signal_add
    add_signal(GLib.PRIORITY_HIGH, signal.SIGTERM, quit_loop, None)
    if stopping():
        return
    window = Gtk.Window(decorated=False)
    GtkLayerShell.init_for_window(window)
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.EXCLUSIVE)
    # Leave anchors, exclusive zone and monitor at their defaults.
    window.set_default_size(640, 440)
    window.set_border_width(12)

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    window.add(box)
    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    box.pack_start(scroll, True, True, 0)
    view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                        wrap_mode=Gtk.WrapMode.WORD_CHAR, can_focus=False)
    scroll.add(view)
    body = view.get_buffer()
    prompt = Gtk.Label(xalign=0, no_show_all=True)
    font = Pango.AttrList()
    font.insert(Pango.attr_family_new("monospace"))
    prompt.set_attributes(font)
    prompt.set_line_wrap(True)
    box.pack_end(prompt, False, False, 0)

    def render():
        lines = []
        selected_line = 0
        for screen in overview.screens:
            header = screen["monitor"]
            if screen["description"]:
                header += " — " + screen["description"]
            if lines:
                lines.append("")
            lines.append(display_text(header))
            for row in screen["workspaces"]:
                selected = row["id"] == overview.selected
                if selected:
                    selected_line = len(lines)
                number = row["slot"] if row["slot"] is not None else row["id"]
                name = f"  {row['name']}" if row["name"] else ""
                apps = ", ".join(win["app"] for win in row["windows"])
                suffix = f"  [{apps}]" if apps else ""
                lines.append(display_text(f"{'>' if selected else ' '} {number:>2}{name}{suffix}"))
                if selected:
                    lines.extend(display_text(f"     {win['app']}: {win['title']}") for win in row["windows"])
        body.set_text("\n".join(lines) if lines else "No screens")
        body.place_cursor(body.get_iter_at_line(selected_line))
        view.scroll_to_mark(body.get_insert(), 0.05, False, 0, 0)
        prompt.set_text(display_text("Name: " + overview.buffer))
        prompt.set_visible(overview.mode == "rename")

    def on_key(_window, event):
        key = Gdk.keyval_name(event.keyval)
        if key not in ("Up", "Down", "Left", "Right", "Return", "KP_Enter", "Escape", "BackSpace"):
            codepoint = Gdk.keyval_to_unicode(event.keyval)
            char = chr(codepoint) if codepoint else ""
            if overview.mode == "rename" and char and (char.isprintable() or unicodedata.category(char) == "Zs"):
                key = {"text": char}
            elif char and char.lower() in DIGITS + "r":
                key = char.lower()
            else:
                return False
        overview.key(key)
        if overview.closed:
            window.destroy()
        else:
            render()
        return True

    window.connect("key-press-event", on_key)
    window.connect("destroy", quit_loop)
    render()
    window.show_all()
    if not stopping():
        Gtk.main()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--print-json", action="store_true")
    modes.add_argument("--keys-json")
    modes.add_argument("--dry-open", action="store_true")
    args = parser.parse_args()
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    directory = Path(runtime) / "hypr-overview" if runtime else None
    names_path = directory / "names.json" if directory is not None else None
    pid_path = directory / "pid" if directory is not None else None

    if args.print_json or args.keys_json is not None:
        keys = []
        if args.keys_json is not None:
            try:
                keys = json.loads(args.keys_json)
            except (ValueError, RecursionError):
                parser.error("--keys-json requires a JSON list")
            if not isinstance(keys, list):
                parser.error("--keys-json requires a JSON list")
        overview = Overview(names_path)
        for key in keys:
            overview.key(key)
        model = overview.model()
        if args.keys_json is not None:
            model.update(mode=overview.mode, closed=overview.closed)
        print(json.dumps(model))
        return 0

    if args.dry_open:
        print("closed" if toggle(pid_path, dry_run=True) else "open")
        return 0

    terminated = False

    def stop(*_):
        nonlocal terminated
        terminated = True

    signal.signal(signal.SIGTERM, stop)
    try:
        if not toggle(pid_path, dry_run=False) and not terminated:
            run_gui(names_path, lambda: terminated, stop)
        return 0
    except (ImportError, OSError, RuntimeError, ValueError) as exc:
        print(f"overview: {exc}", file=sys.stderr)
        return 1
    finally:
        release_pid(pid_path)


if __name__ == "__main__":
    sys.exit(main())
