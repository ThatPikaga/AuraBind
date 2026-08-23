#!/usr/bin/env python3
import os, glob

home = os.environ.get("HOME", "")
dirs = [
    "/usr/share/applications",
    os.path.join(home, ".local/share/applications"),
    "/var/lib/flatpak/exports/share/applications"
]

for d in dirs:
    if not os.path.isdir(d):
        continue
    for f in sorted(glob.glob(os.path.join(d, "*.desktop"))):
        try:
            with open(f) as fh:
                print(fh.read())
                print("---ENTRY---")
        except:
            pass
