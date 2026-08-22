import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property string configPath: System.getenv("HOME") + "/.config/hypr/bindings.lua"

    FileView {
        path: Qt.binding(() => root.configPath)
        watchChanges: true
        onTextChanged: {
            console.log("AuraBind: Detected external change to bindings.lua.")
        }
    }

    Process {
        id: initProcess
        command: Qt.binding(() => {
            // Secure shell script to append default toggle if it doesn't exist
            let script = `FILE="${root.configPath}"
touch "$FILE"
if ! grep -q 'omarchy-shell shell toggle pikaga.aurabind' "$FILE"; then
    echo '\\n-- >>> managed keybindings block <<<\\no.bind("SUPER + ALT + SHIFT + K", "AuraBind Manager", "omarchy-shell shell toggle pikaga.aurabind")\\n-- <<< managed keybindings block >>>\\n' >> "$FILE"
    hyprctl reload
fi`
            // Base64 encode to eliminate any QML-to-Bash escaping bugs
            let b64 = Qt.btoa(unescape(encodeURIComponent(script)))
            return ["sh", "-c", "echo '" + b64 + "' | base64 -d | bash"]
        })
    }

    Component.onCompleted: {
        initProcess.running = true
    }
}
