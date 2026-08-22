import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Window {
    id: root
    title: "AuraBind Keybindings"
    width: 520
    height: 640
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    color: "transparent"
    visible: false // Starts hidden, toggled via IPC

    // Theme fallbacks for Omarchy
    QtObject {
        id: theme
        property color bg: (typeof qs !== 'undefined' && qs.Commons && qs.Commons.palette && qs.Commons.palette.window) ? qs.Commons.palette.window : "#1e1e2e"
        property color text: (typeof qs !== 'undefined' && qs.Commons && qs.Commons.palette && qs.Commons.palette.windowText) ? qs.Commons.palette.windowText : "#cdd6f4"
        property color accent: (typeof qs !== 'undefined' && qs.Commons && qs.Commons.palette && qs.Commons.palette.highlight) ? qs.Commons.palette.highlight : "#89b4fa"
        property color surface: (typeof qs !== 'undefined' && qs.Commons && qs.Commons.palette && qs.Commons.palette.button) ? qs.Commons.palette.button : "#313244"
        property string fontFamily: (typeof qs !== 'undefined' && qs.Commons && qs.Commons.fontFamily) ? qs.Commons.fontFamily : "sans-serif"
    }

    property bool isCapturing: false
    property string capturedMod: ""
    property string capturedKey: ""
    property var keybinds: []
    property string configPath: System.getenv("HOME") + "/.config/hypr/bindings.lua"

    // IPC Handler to listen for toggle commands from the desktop shortcut
    IpcHandler {
        target: "pikaga.aurabind"
        function toggle() {
            root.visible = !root.visible
            if (root.visible) {
                root.requestActivate()
                readProcess.running = true // Refresh on open
            }
        }
    }

    Process {
        id: readProcess
        command: ["sh", "-c", `cat ${configPath}`]
        stdout: StdioCollector { onStreamFinished: parseConfig(text) }
    }

    Process {
        id: writeProcess
        command: ["sh", "-c", "echo ''"]
        onRunningChanged: if (!running) reloadProcess.running = true
    }

    Process {
        id: reloadProcess
        command: ["hyprctl", "reload"]
    }

    Component.onCompleted: {
        readProcess.running = true
    }

    function parseConfig(text) {
        if (!text) { keybinds = []; return }
        let binds = []
        let lines = text.split("\n")
        let inBlock = false
        
        for (let line of lines) {
            line = line.trim()
            if (line === "-- >>> managed keybindings block <<<") { inBlock = true; continue }
            if (line === "-- <<< managed keybindings block >>>") { inBlock = false; continue }
            
            if (inBlock) {
                let bindMatch = line.match(/^o\.bind\("([^"]+)",\s*"([^"]*)",\s*"(.+)"\)$/)
                if (bindMatch) {
                    binds.push({ type: "bind", keys: bindMatch[1], desc: bindMatch[2], command: bindMatch[3] })
                    continue
                }
                let unbindMatch = line.match(/^hl\.unbind\("([^"]+)"\)$/)
                if (unbindMatch) {
                    binds.push({ type: "unbind", keys: unbindMatch[1], desc: "Disable Default", command: "" })
                }
            }
        }
        keybinds = binds
    }

    function saveConfig() {
        let blockStart = "-- >>> managed keybindings block <<<"
        let blockEnd = "-- <<< managed keybindings block >>>"
        
        let content = "\n" + blockStart + "\n"
        for (let bind of keybinds) {
            if (bind.type === "bind") {
                content += `o.bind("${bind.keys.replace(/"/g, '\\"')}", "${bind.desc.replace(/"/g, '\\"')}", "${bind.command.replace(/"/g, '\\"')}")\n`
            } else if (bind.type === "unbind") {
                content += `hl.unbind("${bind.keys}")\n`
            }
        }
        content += blockEnd + "\n"
        
        let b64Content = Qt.btoa(unescape(encodeURIComponent(content)))
        let mergeScript = `
            FILE="${configPath}"
            TEMP="/tmp/aurabind_merge"
            touch "$FILE"
            awk -v start="${blockStart}" -v end="${blockEnd}" '$0==start{skip=1;next} $0==end{skip=0;next} !skip' "$FILE" > "$TEMP"
            echo "${b64Content}" | base64 -d >> "$TEMP"
            mv "$TEMP" "$FILE"
        `
        let b64Script = Qt.btoa(unescape(encodeURIComponent(mergeScript)))
        writeProcess.command = ["sh", "-c", `echo "${b64Script}" | base64 -d | bash`]
        writeProcess.running = true
    }

    function getKeyString(key) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key).toUpperCase()
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
        if (key === Qt.Key_Return || key === Qt.Key_Enter) return "RETURN"
        if (key === Qt.Key_Escape) return "ESCAPE"
        if (key === Qt.Key_Tab) return "TAB"
        if (key === Qt.Key_Backspace) return "BACKSPACE"
        if (key === Qt.Key_Delete) return "DELETE"
        if (key === Qt.Key_Space) return "SPACE"
        if (key === Qt.Key_Left) return "LEFT"
        if (key === Qt.Key_Right) return "RIGHT"
        if (key === Qt.Key_Up) return "UP"
        if (key === Qt.Key_Down) return "DOWN"
        if (key === Qt.Key_Comma) return "COMMA"
        if (key === Qt.Key_Period) return "PERIOD"
        if (key === Qt.Key_Slash) return "SLASH"
        if (key === Qt.Key_Minus) return "MINUS"
        if (key === Qt.Key_Equal) return "EQUAL"
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + (key - Qt.Key_F1 + 1)
        return "UNKNOWN"
    }

    function editBinding(index) {
        let bind = keybinds[index]
        let keysArray = bind.keys.split(" + ")
        capturedKey = keysArray.pop()
        capturedMod = keysArray.join(" + ")
        descField.text = bind.desc
        
        if (bind.type === "unbind") { actionCombo.currentIndex = 6 } 
        else {
            let cmd = bind.command.toLowerCase()
            if (cmd.startsWith("workspace ")) actionCombo.currentIndex = 3
            else if (cmd === "killactive") actionCombo.currentIndex = 4
            else if (cmd === "reload") actionCombo.currentIndex = 5
            else if (cmd.includes("omarchy-shell")) actionCombo.currentIndex = 2
            else actionCombo.currentIndex = 1
            
            let parts = bind.command.split(" ")
            dispatcherField.text = parts.shift() || ""
            paramsField.text = parts.join(" ")
        }
        
        addDialog.editIndex = index
        addDialog.visible = true
    }

    function deleteBinding(index) {
        let binds = [...keybinds]
        binds.splice(index, 1)
        keybinds = binds
        saveConfig()
        readProcess.running = true
        reloadProcess.running = true
    }

    function saveBinding() {
        let modPrefix = capturedMod !== "" ? capturedMod + " + " : ""
        let fullKeys = modPrefix + capturedKey
        if (capturedKey === "UNKNOWN" || fullKeys.trim() === "") return
        
        let fullCommand = dispatcherField.text.trim() + (paramsField.text.trim() ? " " + paramsField.text.trim() : "")
        let newBind = {
            type: actionCombo.currentIndex === 6 ? "unbind" : "bind",
            keys: fullKeys, desc: descField.text || "Custom Binding", command: fullCommand.trim()
        }
        
        let binds = [...keybinds]
        if (addDialog.editIndex !== -1) binds[addDialog.editIndex] = newBind
        else binds.push(newBind)
        
        keybinds = binds
        saveConfig()
        readProcess.running = true
        reloadProcess.running = true
        addDialog.visible = false
        addDialog.editIndex = -1
        capturedMod = ""
        capturedKey = ""
    }

    Rectangle {
        anchors.fill: parent
        color: theme.bg
        opacity: 0.95
        radius: 12
        border.color: theme.accent
        border.width: 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "AuraBind Manager"
                    color: theme.text
                    font.family: theme.fontFamily
                    font.pixelSize: 24
                    font.bold: true
                    Layout.fillWidth: true
                }
                Button {
                    text: "+ Add"
                    onClicked: {
                        addDialog.editIndex = -1
                        capturedMod = ""; capturedKey = ""
                        actionCombo.currentIndex = 0
                        descField.text = ""; dispatcherField.text = "exec"; paramsField.text = ""
                        addDialog.visible = true
                    }
                }
                Button {
                    text: "Close"
                    onClicked: root.visible = false
                }
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search bindings..."
                color: theme.text
                background: Rectangle { color: theme.surface; radius: 6 }
            }

            ListView {
                id: bindList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: keybinds
                spacing: 8
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    width: bindList.width
                    height: visible ? 50 : 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on height { NumberAnimation { duration: 150 } }
                    color: theme.surface
                    radius: 8
                    
                    property bool matches: searchField.text === "" || 
                                           (modelData.keys + " " + modelData.desc + " " + modelData.command).toLowerCase().indexOf(searchField.text.toLowerCase()) !== -1
                    visible: matches

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 16

                        Label {
                            text: modelData.keys
                            color: theme.accent
                            font.family: theme.fontFamily
                            font.bold: true
                            font.pixelSize: 16
                            Layout.preferredWidth: 180
                        }
                        Label {
                            text: modelData.desc
                            color: theme.text
                            font.family: theme.fontFamily
                            font.weight: Font.DemiBold
                            Layout.preferredWidth: 150
                        }
                        Label {
                            text: modelData.type === "bind" ? modelData.command : "UNBIND"
                            color: modelData.type === "bind" ? theme.text : "#f38ba8" 
                            font.family: theme.fontFamily
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Button { text: "Edit"; onClicked: editBinding(index) }
                        Button { text: "Delete"; onClicked: deleteBinding(index) }
                    }
                }
            }
        }
    }

    FocusScope {
        id: captureArea
        visible: isCapturing
        focus: visible
        anchors.fill: parent
        z: 999

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.7
            MouseArea { anchors.fill: parent }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 24

            Label {
                text: "Press a key combination..."
                color: "white"
                font.pixelSize: 28
                font.family: theme.fontFamily
                Layout.alignment: Qt.AlignHCenter
            }
            Label {
                text: capturedMod !== "" ? `${capturedMod} + ${capturedKey}` : "..."
                color: theme.accent
                font.pixelSize: 48
                font.family: theme.fontFamily
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }
            Button {
                text: "Cancel"
                Layout.alignment: Qt.AlignHCenter
                onClicked: isCapturing = false
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { isCapturing = false; event.accepted = true; return }
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control || 
                event.key === Qt.Key_Alt || event.key === Qt.Key_Meta || event.key === Qt.Key_AltGr) {
                event.accepted = true; return
            }

            let mods = []
            if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
            if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
            if (event.modifiers & Qt.AltModifier) mods.push("ALT")
            if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")

            capturedMod = mods.join(" + ")
            capturedKey = getKeyString(event.key)
            event.accepted = true
        }
    }

    Rectangle {
        id: addDialog
        visible: false
        anchors.centerIn: parent
        width: 420
        height: 520
        color: theme.bg
        border.color: theme.accent
        border.width: 2
        radius: 12
        z: 1000

        property int editIndex: -1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            Label {
                text: addDialog.editIndex === -1 ? "Add New Binding" : "Edit Binding"
                font.pixelSize: 20
                font.bold: true
                color: theme.text
                Layout.alignment: Qt.AlignHCenter
            }

            Label { text: "Key Combination"; color: theme.text }
            Button {
                Layout.fillWidth: true
                text: isCapturing ? "Capturing..." : ((capturedMod !== "" ? `${capturedMod} + ` : "") + capturedKey || "Click to capture...")
                onClicked: { isCapturing = true; capturedMod = ""; capturedKey = "" }
            }

            Label { text: "Description"; color: theme.text }
            TextField {
                id: descField
                Layout.fillWidth: true
                placeholderText: "e.g. Open Terminal"
                color: theme.text
                background: Rectangle { color: theme.surface; radius: 6 }
            }

            Label { text: "Action Type"; color: theme.text }
            ComboBox {
                id: actionCombo
                Layout.fillWidth: true
                model: ["Open App", "Custom Command", "Start Plugin", "Workspace", "Kill Active", "Reload", "Unbind (Disable Default)"]
                currentIndex: 0
                color: theme.text
                background: Rectangle { color: theme.surface; radius: 6 }
                onCurrentIndexChanged: {
                    switch(currentIndex) {
                        case 0: dispatcherField.text = "exec"; paramsField.placeholderText = "e.g., kitty"; dispatcherField.enabled = true; paramsField.enabled = true; break;
                        case 1: dispatcherField.text = ""; paramsField.placeholderText = "e.g., alacritty -e ssh"; dispatcherField.enabled = true; paramsField.enabled = true; break;
                        case 2: dispatcherField.text = "exec"; paramsField.placeholderText = "e.g., omarchy-shell shell toggle plugin"; dispatcherField.enabled = true; paramsField.enabled = true; break;
                        case 3: dispatcherField.text = "workspace"; paramsField.placeholderText = "e.g., 1"; dispatcherField.enabled = true; paramsField.enabled = true; break;
                        case 4: dispatcherField.text = "killactive"; paramsField.text = ""; dispatcherField.enabled = false; paramsField.enabled = false; break;
                        case 5: dispatcherField.text = "reload"; paramsField.text = ""; dispatcherField.enabled = false; paramsField.enabled = false; break;
                        case 6: dispatcherField.text = ""; paramsField.text = ""; dispatcherField.enabled = false; paramsField.enabled = false; break;
                    }
                }
            }

            Label { text: "Dispatcher"; color: theme.text }
            TextField {
                id: dispatcherField
                Layout.fillWidth: true
                color: theme.text
                background: Rectangle { color: theme.surface; radius: 6 }
            }

            Label { text: "Parameters"; color: theme.text }
            TextField {
                id: paramsField
                Layout.fillWidth: true
                color: theme.text
                background: Rectangle { color: theme.surface; radius: 6 }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Item { Layout.fillWidth: true }
                Button { text: "Cancel"; onClicked: addDialog.visible = false }
                Button { text: "Save"; onClicked: saveBinding() }
            }
        }
    }
}