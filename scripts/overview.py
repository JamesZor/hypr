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
import threading
import unicodedata


DIGITS = "1234567890"
VIM_KEYS = {"j": "Down", "k": "Up", "h": "Left", "l": "Right"}
ALIASES_PATH = Path(__file__).resolve().with_name("overview-aliases.json")


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


def monitor_matches(selector, monitor, description):
    if selector.startswith("desc:"):
        return description.startswith(selector[5:].strip())
    return monitor == selector


def bank_start(rules, monitor, description):
    for rule in rules:
        selector = rule.get("monitor")
        if rule.get("default") is not True or rule.get("enabled") is False or not isinstance(selector, str):
            continue
        if monitor_matches(selector, monitor, description):
            return decimal(rule.get("workspaceString"))
    return None


def read_aliases():
    with suppress(OSError, ValueError, RecursionError):
        raw = json.loads(ALIASES_PATH.read_text(encoding="utf-8"))
        if isinstance(raw, dict):
            return {selector: alias for selector, value in raw.items()
                    if (alias := text(value).strip()[:32].strip())}
    return {}


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
    aliases = read_aliases()
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
        alias = next((value for selector, value in aliases.items()
                      if monitor_matches(selector, connector, description)), None)
        screens.append({"monitor": connector, "description": description, "alias": alias,
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

        if len(key) == 1:
            key = key.lower()
            key = VIM_KEYS.get(key, key)
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
    return (re.sub(r"[\r\n\u2028\u2029]", " ", value).replace("\0", "�")
            .encode("utf-8", errors="replace").decode("utf-8"))


def run_gui(names_path, finish):
    from gi import require_version

    require_version("Gdk", "3.0")
    require_version("Gtk", "3.0")
    require_version("GtkLayerShell", "0.1")
    from gi.repository import Gdk, Gtk, GtkLayerShell, Pango

    if not Gtk.init_check([])[0] or not GtkLayerShell.is_supported():
        raise RuntimeError("a Wayland display with layer-shell support is required")
    overview = Overview(names_path)

    window = Gtk.Window(decorated=False)
    window.set_name("workspace-overview")
    window.connect("delete-event", lambda *_: finish(0))
    GtkLayerShell.init_for_window(window)
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.EXCLUSIVE)
    # Leave anchors, exclusive zone and monitor at their defaults.
    window.set_border_width(12)

    css = Gtk.CssProvider()
    css.load_from_data(b"""
        #workspace-overview, #workspace-overview textview, #workspace-overview textview text {
            background-color: #282828;
            background-image: none;
            color: #ebdbb2;
            font-family: monospace;
        }
        #workspace-overview label {
            color: #d8a657;
            font-family: monospace;
        }
    """)
    Gtk.StyleContext.add_provider_for_screen(window.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    window.add(box)
    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    # The minimum request persists after the layer-shell configure.
    scroll.set_size_request(760, 460)
    box.pack_start(scroll, True, True, 0)
    view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                        wrap_mode=Gtk.WrapMode.WORD_CHAR, can_focus=False)
    scroll.add(view)
    body = view.get_buffer()
    prompt = Gtk.Label(xalign=0, no_show_all=True)
    prompt.set_line_wrap(True)
    box.pack_end(prompt, False, False, 0)

    alternate = body.create_tag("alternate", paragraph_background="#32302f")
    selected = body.create_tag("selected", paragraph_background="#687b31",
                               foreground="#fbf1c7", weight=Pango.Weight.BOLD)
    # The higher-priority name and marker tags retain their accent on the selected row.
    name_tag = body.create_tag("name", foreground="#d8a657")
    shown_tag = body.create_tag("shown", foreground="#a9b665")
    header_tag = body.create_tag("header", foreground="#a9b665", weight=Pango.Weight.BOLD)
    detail_tag = body.create_tag("detail", foreground="#a89984")
    app_tag = body.create_tag("app", foreground="#a89984", weight=Pango.Weight.BOLD)

    def render():
        chunks = []
        styles = []
        offset = selected_offset = 0

        def line(*parts, row_style=None):
            nonlocal offset
            if chunks:
                chunks.append("\n")
                offset += 1
            start = offset
            for value, tag in parts:
                value = display_text(value)
                chunks.append(value)
                end = offset + len(value)
                if tag is not None and end > offset:
                    styles.append((tag, offset, end))
                offset = end
            if row_style is not None:
                styles.append((row_style, start, offset))
            return start

        for index, screen in enumerate(overview.screens):
            if index:
                line(("", None))
            connector = screen["monitor"]
            if screen["alias"]:
                header = f"{screen['alias']} ({connector})"
            elif screen["description"]:
                header = f"{connector} — {screen['description']}"
            else:
                header = connector
            line((header, header_tag))
            for i, row in enumerate(screen["workspaces"]):
                is_selected = row["id"] == overview.selected
                number = row["slot"] if row["slot"] is not None else row["id"]
                name = f"  {row['name']}" if row["name"] else ""
                apps = ", ".join(win["app"] for win in row["windows"])
                suffix = f"  [{apps}]" if apps else ""
                marker = ("●", shown_tag) if row["shown"] else (" ", None)
                row_style = selected if is_selected else alternate if i % 2 else None
                row_offset = line(marker, (f" {number:>2}", None), (name, name_tag), (suffix, None),
                                  row_style=row_style)
                if is_selected:
                    selected_offset = row_offset
                    for win in row["windows"]:
                        line(("     " + win["app"], app_tag), (": " + win["title"], detail_tag))

        body.set_text("".join(chunks) if chunks else "No screens")
        for tag, start, end in styles:
            body.apply_tag(tag, body.get_iter_at_offset(start), body.get_iter_at_offset(end))
        body.place_cursor(body.get_iter_at_offset(selected_offset))
        view.scroll_to_mark(body.get_insert(), 0.05, False, 0, 0)
        prompt.set_text(display_text("Name: " + overview.buffer))
        prompt.set_visible(overview.mode == "rename")

    modifiers = Gdk.ModifierType
    ignored = modifiers.CONTROL_MASK | modifiers.MOD1_MASK | modifiers.SUPER_MASK | modifiers.MOD4_MASK

    def on_key(_window, event):
        try:
            if event.state & ignored:
                return True
            keyval = event.keyval
            key = Gdk.keyval_name(keyval)
            if key not in ("Up", "Down", "Left", "Right", "Return", "KP_Enter", "Escape", "BackSpace"):
                codepoint = Gdk.keyval_to_unicode(keyval)
                if not codepoint:
                    return False
                char = chr(codepoint)
                if overview.mode == "rename":
                    if not (char.isprintable() or unicodedata.category(char) == "Zs"):
                        return False
                    key = {"text": char}
                else:
                    key = char.lower()
                    if key not in VIM_KEYS and key != "r" and key not in DIGITS:
                        return False
            overview.key(key)
            if overview.closed:
                finish(0)
            render()
        except BaseException as exc:
            finish(1, exc)
        return True

    window.connect("key-press-event", on_key)
    render()
    window.show_all()
    Gtk.main()
    finish(0)  # Keep the window alive until the process exits, even if the loop returns.


def run_popup(names_path, pid_path):
    closing = threading.Lock()

    def finish(status, error=None):
        with closing:
            try:
                release_pid(pid_path)
                if error is not None:
                    print(f"overview: {error}", file=sys.stderr, flush=True)
            finally:
                # Do not enter GTK teardown or wait for its threads at interpreter shutdown.
                os._exit(status)

    signals = {signal.SIGTERM, signal.SIGINT}

    def wait_for_close_signal():
        try:
            received = signal.sigwait(signals)
        except BaseException as exc:
            finish(1, exc)
        else:
            finish(0 if received == signal.SIGTERM else 1)

    try:
        # Queue signals even during the pid-file transaction. Start waiting only after
        # it unlocks, but before importing GTK; no reliance on GTK's main loop or on
        # a Python signal handler getting time on the main thread during startup.
        signal.pthread_sigmask(signal.SIG_BLOCK, signals)
        if not toggle(pid_path, dry_run=False):
            threading.Thread(target=wait_for_close_signal, daemon=True).start()
            run_gui(names_path, finish)
    except BaseException as exc:
        finish(1, exc)
    finish(0)


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

    run_popup(names_path, pid_path)


if __name__ == "__main__":
    sys.exit(main())
