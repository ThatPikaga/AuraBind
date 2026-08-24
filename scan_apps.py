#!/usr/bin/env python3
"""Scan system for installable applications and output JSON.

Scans these sources (all read-only — no code is ever executed):
  • .desktop files from /usr/share/applications, ~/.local/share/applications,
    and /var/lib/flatpak/exports/share/applications
  • Flatpak via `flatpak list --app`
  • AppImage files from ~/Applications/ and ~/.local/bin/
  • Snap apps from /snap/bin/ (symlinks, listed but never followed)
  • Pacman/AUR explicit packages (via `pacman -Qqe`, package names only)

Each entry has: {"name": str, "exec": str, "icon": str, "source": str}

Sources and their risk level:
  desktop    — reads plaintext .desktop metadata files          ✅ no code
  flatpak    — runs `flatpak list --app` (read-only query)       ✅ no code
  appimage   — reads directory listings, never mounts/execes    ✅ no code
  snap       — reads symlink names in /snap/bin/                ✅ no code
  pacman     — runs `pacman -Qqe` (lists package names only)    ✅ no code
"""
import json, os, glob, subprocess

home = os.environ.get("HOME", "")
entries = []
seen_execs = set()


def add(name, exec_cmd, icon="", source=""):
    if not exec_cmd or exec_cmd in seen_execs:
        return
    seen_execs.add(exec_cmd)
    entries.append({
        "name": name,
        "exec": exec_cmd,
        "icon": icon,
        "source": source,
    })


# ── .desktop files ───────────────────────────────────────────────
for d in [
    "/usr/share/applications",
    os.path.join(home, ".local/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
]:
    if not os.path.isdir(d):
        continue
    for f in sorted(glob.glob(os.path.join(d, "*.desktop"))):
        try:
            with open(f, "r", errors="replace") as fh:
                content = fh.read()
        except Exception:
            continue
        name, exec_cmd = "", ""
        for line in content.splitlines():
            line = line.strip()
            if line.startswith("Name="):
                name = line[5:]
            elif line.startswith("Exec="):
                raw = line[5:]
                for token in ("%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N",
                              "%i", "%c", "%k", "%v", "%m"):
                    raw = raw.replace(" " + token, "").replace(token, "")
                exec_cmd = raw.strip()
        if exec_cmd:
            add(name or exec_cmd, exec_cmd, source="desktop")


# ── Flatpak ──────────────────────────────────────────────────────
try:
    result = subprocess.run(
        ["flatpak", "list", "--app", "--columns=name,application"],
        capture_output=True, text=True, timeout=10,
    )
    for line in result.stdout.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2:
            add(parts[0].strip(), "flatpak run " + parts[1].strip(), source="flatpak")
except Exception:
    pass


# ── AppImage (~/Applications/*.AppImage, ~/.local/bin/*.AppImage) ─
for appdir in [
    os.path.join(home, "Applications"),
    os.path.join(home, ".local/bin"),
]:
    if not os.path.isdir(appdir):
        continue
    for f in sorted(glob.glob(os.path.join(appdir, "*.AppImage"))):
        basename = os.path.basename(f)
        stem = basename.replace(".AppImage", "")
        # Strip version suffix like "-4.0.0" for a cleaner name
        name = stem
        if "-" in stem:
            parts = stem.rsplit("-", 1)
            if parts[1] and parts[1][0].isdigit():
                name = parts[0]
        add(name, f, source="appimage")


# ── Snap (symlinks in /snap/bin/) ────────────────────────────────
snap_bin = "/snap/bin"
if os.path.isdir(snap_bin):
    for entry in sorted(os.listdir(snap_bin)):
        full = os.path.join(snap_bin, entry)
        if os.path.islink(full) and not entry.startswith("."):
            add(entry, "snap run " + entry, source="snap")


# ── Pacman / AUR (list explicitly installed packages) ─────────────
try:
    result = subprocess.run(
        ["pacman", "-Qqe"],
        capture_output=True, text=True, timeout=15,
    )
    for line in result.stdout.strip().split("\n"):
        pkg = line.strip()
        if not pkg or pkg.startswith("."):
            continue
        # Skip if a desktop entry already covers this package name
        pkg_key = pkg.lower().replace("-", "").replace(" ", "")
        already_have = any(
            e["name"].lower().replace("-", "").replace(" ", "") == pkg_key
            for e in entries
        )
        if already_have:
            continue
        # Only add if an executable binary exists
        for bindir in ["/usr/bin/" + pkg, "/usr/local/bin/" + pkg,
                       os.path.join(home, ".local/bin", pkg)]:
            if os.path.isfile(bindir) and os.access(bindir, os.X_OK):
                add(pkg, pkg, source="pacman")
                break
except FileNotFoundError:
    pass  # pacman not available (not Arch/derivative)

print(json.dumps(entries))