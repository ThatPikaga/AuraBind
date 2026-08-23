#!/usr/bin/env python3
import os, json, sys

home = os.environ.get("HOME", "")
dirs = [
    home + "/.config/omarchy/plugins/",
    "/usr/share/omarchy/plugins/"
]

for d in dirs:
    if not os.path.isdir(d):
        continue
    for entry in sorted(os.listdir(d)):
        path = os.path.join(d, entry)
        if not os.path.isdir(path):
            continue
        manifest = os.path.join(path, "manifest.json")
        display = entry
        if os.path.isfile(manifest):
            try:
                with open(manifest) as f:
                    data = json.load(f)
                    if "name" in data:
                        display = data["name"]
            except:
                pass
        print(f"{entry}|{display}")
