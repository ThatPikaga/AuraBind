#!/usr/bin/env python3
"""Scan installed Omarchy plugins and output JSON array.

Safe: reads only directory names and manifest.json metadata.
No plugin code is loaded or executed.
"""
import json, os

home = os.environ.get("HOME", "")
dirs = [
    os.path.join(home, ".config/omarchy/plugins/"),
    "/usr/share/omarchy/plugins/",
]

entries = []

for d in dirs:
    if not os.path.isdir(d):
        continue
    for entry in sorted(os.listdir(d)):
        path = os.path.join(d, entry)
        if not os.path.isdir(path):
            continue
        manifest_path = os.path.join(path, "manifest.json")
        name = entry
        kinds = []
        if os.path.isfile(manifest_path):
            try:
                with open(manifest_path, "r") as f:
                    data = json.load(f)
                    if "name" in data:
                        name = data["name"]
                    if "kinds" in data:
                        kinds = data["kinds"]
            except Exception:
                pass
        if not kinds or "panel" in kinds:
            entries.append({
                "id": entry,
                "name": name,
                "toggleCmd": "omarchy-shell shell toggle " + entry,
            })

print(json.dumps(entries))