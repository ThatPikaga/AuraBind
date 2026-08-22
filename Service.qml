import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Watch for external changes to bindings.lua
    FileView {
        path: System.getenv("HOME") + "/.config/hypr/bindings.lua"
        watchChanges: true
        
        onTextChanged: {
            console.log("AuraBind: Detected external change to bindings.lua. Panel will refresh on next open.")
        }
    }
}