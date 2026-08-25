import QtQuick
import Quickshell

// Installs the launcher entry, so the panel is reachable from SUPER+SPACE
// without the user wiring up a keybind first. Omarchy has no install hook
// and no manifest field for registering one, so it happens here instead.
//
// Only a file carrying the X-AuraBind-Managed marker is written or deleted.
QtObject {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string dest: Quickshell.env("HOME") + "/.local/share/applications/aurabind.desktop"
  readonly property string marker: "^X-AuraBind-Managed=true$"

  readonly property string installScript:
      '[ -f "$1" ] || exit 0\n'
    + 'if [ -e "$2" ] && ! grep -q "$3" "$2"; then exit 0; fi\n'
    + 'dir="${2%/*}"\n'
    + 'mkdir -p "$dir" || exit 0\n'
    + 'tmp=$(mktemp "$dir/.aurabind.XXXXXX") || exit 0\n'
    + 'sed "s|@ICON@|$4|" "$1" > "$tmp" || { rm -f "$tmp"; exit 0; }\n'
    + 'if [ -e "$2" ]; then\n'
    + '  if [ -L "$2" ]; then rm -f "$2"; fi\n'
    + '  if [ "$(stat -c %u "$2" 2>/dev/null)" != "$(id -u)" ]; then rm -f "$tmp"; exit 0; fi\n'
    + 'fi\n'
    + 'mv -f "$tmp" "$2"\n'

  readonly property string removeScript:
    'if [ -L "$1" ]; then exit 0; fi\n'
    + 'if [ -e "$1" ] && grep -q "$2" "$1" 2>/dev/null; then rm -f "$1"; fi\n'

  property bool installed: false

  onManifestChanged: {
    var dir = manifest && manifest.__sourceDir
    if (installed || !dir) return
    installed = true
    Quickshell.execDetached(["sh", "-c", installScript, "sh",
                             dir + "/aurabind.desktop", dest, marker, dir + "/icon.png"])
  }

  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["sh", "-c", removeScript, "sh", dest, marker])
  }
}