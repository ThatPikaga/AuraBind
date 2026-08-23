#!/usr/bin/env python3
import subprocess, json

try:
    result = subprocess.run(
        ["flatpak", "list", "--app", "--columns=name,application"],
        capture_output=True, text=True, timeout=10
    )
    for line in result.stdout.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2:
            print(f"{parts[0]}\t{parts[1]}")
except:
    pass
