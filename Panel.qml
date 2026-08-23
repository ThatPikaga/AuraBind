import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// AuraBind - a GUI for editing Hyprland keybindings on the fly.
//
// Reads and writes a managed block inside ~/.config/hypr/bindings.lua
// using the same fence pattern as Omaland, so the file survives both
// hand-edits and plugin writes.

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (manifest && manifest.__sourceDir) || (home + "/.config/omarchy/plugins/pikaga.aurabind")
  readonly property string configPath: home + "/.config/hypr/bindings.lua"

  property bool opened: false
  property var keybinds: []
  property bool isCapturing: false
  property string capturedMod: ""
  property string capturedKey: ""
  property string errorText: ""
  property string statusText: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.menuFamily

  readonly property string beginFence: "-- >>> managed keybindings block <<<"
  readonly property string endFence:   "-- <<< managed keybindings block >>>"

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.opened = true
    configFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "aurabind")
    else close()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ------------------------------------------------------------- parsing

  function parseConfig(text) {
    if (!text) { keybinds = []; return }
    var split = splitBlock(text)
    if (!split.found) { keybinds = []; return }

    var binds = []
    var lines = split.body.split("\n")
    for (var line of lines) {
      line = line.trim()
      if (line === "" || line.startsWith("--")) continue

      var m = line.match(/^o\.bind\("([^"]+)",\s*"([^"]*)",\s*"(.+)"\)$/)
      if (m) { binds.push({ type: "bind", keys: m[1], desc: m[2], command: m[3] }); continue }

      var u = line.match(/^hl\.unbind\("([^"]+)"\)$/)
      if (u) binds.push({ type: "unbind", keys: u[1], desc: "Disable Default", command: "" })
    }
    keybinds = binds
  }

  function splitBlock(text) {
    var src = String(text || "")
    var b = src.indexOf(root.beginFence)
    if (b === -1) return { found: false, before: src, body: "", after: "" }
    var e = src.indexOf(root.endFence, b)
    if (e === -1) return { found: false, before: src, body: "", after: "" }
    return { found: true, before: src.substring(0, b), body: src.substring(b + root.beginFence.length, e), after: src.substring(e + root.endFence.length) }
  }

  function renderBlockBody() {
    var lines = []
    for (var bind of keybinds) {
      if (bind.type === "bind")
        lines.push('o.bind("' + bind.keys.replace(/"/g, '\\"') + '", "' + bind.desc.replace(/"/g, '\\"') + '", "' + bind.command.replace(/"/g, '\\"') + '")')
      else if (bind.type === "unbind")
        lines.push('hl.unbind("' + bind.keys + '")')
    }
    return lines.join("\n")
  }

  function applyBlock(text, body) {
    var split = splitBlock(text)
    if (!body) {
      if (!split.found) return String(text || "")
      return (split.before.replace(/\n+$/, "\n") + split.after.replace(/^\n+/, "")).replace(/\n{3,}$/, "\n")
    }
    var block = root.beginFence + "\n  -- Written by AuraBind\n" + body + "\n" + root.endFence
    if (split.found) return split.before + block + split.after
    var head = String(text || "")
    if (head.length > 0 && head[head.length - 1] !== "\n") head += "\n"
    return head + "\n" + block + "\n"
  }

  function saveConfig() {
    var body = renderBlockBody()
    var current = configFile.text()
    var next = applyBlock(current, body)
    if (next === current) { reloadProc.running = true; return }
    root.statusText = "Saving"
    root.selfWrite = true
    configFile.setText(next)
  }

  function noteSaved() {
    root.selfWrite = false
    root.statusText = "Saved"
    reloadProc.running = true
    configFile.reload()
  }

  function noteSaveFailed() {
    root.selfWrite = false; root.statusText = ""; root.errorText = "Write failed"
  }

  // ----------------------------------------------------------- key capture

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

  function startCapture() {
    isCapturing = true; capturedMod = ""; capturedKey = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function editBinding(index) {
    var bind = keybinds[index]
    var arr = bind.keys.split(" + ")
    capturedKey = arr.pop(); capturedMod = arr.join(" + ")
    descField.text = bind.desc
    if (bind.type === "unbind") { actionCombo.value = actionCombo.options[6] }
    else {
      var cmd = bind.command.toLowerCase()
      if (cmd.startsWith("workspace ")) actionCombo.value = actionCombo.options[3]
      else if (cmd === "killactive") actionCombo.value = actionCombo.options[4]
      else if (cmd === "reload") actionCombo.value = actionCombo.options[5]
      else if (cmd.indexOf("omarchy-shell") !== -1) actionCombo.value = actionCombo.options[2]
      else actionCombo.value = actionCombo.options[1]
      var parts = bind.command.split(" ")
      dispatcherField.text = parts.shift() || ""; paramsField.text = parts.join(" ")
    }
    addDialog.editIndex = index; addDialog.visible = true
  }

  function deleteBinding(index) {
    var binds = [...keybinds]; binds.splice(index, 1); keybinds = binds; saveConfig()
  }

  function saveBinding() {
    var modPrefix = capturedMod !== "" ? capturedMod + " + " : ""
    var fullKeys = modPrefix + capturedKey
    if (capturedKey === "UNKNOWN" || fullKeys.trim() === "") return
    var fullCmd = dispatcherField.text.trim() + (paramsField.text.trim() ? " " + paramsField.text.trim() : "")
    var nb = { type: actionCombo.value === actionCombo.options[6] ? "unbind" : "bind", keys: fullKeys, desc: descField.text || "Custom Binding", command: fullCmd.trim() }
    var binds = [...keybinds]
    if (addDialog.editIndex !== -1) binds[addDialog.editIndex] = nb; else binds.push(nb)
    keybinds = binds; saveConfig()
    addDialog.visible = false; addDialog.editIndex = -1; capturedMod = ""; capturedKey = ""
  }

  // ------------------------------------------------------------- processes

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
    onExited: { errorsProc.running = true }
  }

  Process {
    id: errorsProc
    command: ["hyprctl", "configerrors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        root.errorText = (out === "" || out === "no errors") ? "" : out
      }
    }
  }

  Timer {
    id: statusClear; interval: 1800
    running: root.statusText === "Saved"
    onTriggered: root.statusText = ""
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true; printErrors: false; watchChanges: true
    onLoaded: root.parseConfig(text())
    onLoadFailed: { keybinds = [] }
    onSaved: root.noteSaved()
    onSaveFailed: root.noteSaveFailed()
    onFileChanged: { if (!root.selfWrite) reload() }
  }

  // ------------------------------------------------------------------- UI

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "aurabind"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent; color: root.scrim
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(780), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(640), window.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent; focus: true; visible: !root.isCapturing

        Keys.onPressed: function(event) {
          var vim = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
          else if (event.key === Qt.Key_Down || (vim && event.key === Qt.Key_J)) { bindList.incrementCurrentIndex(); event.accepted = true }
          else if (event.key === Qt.Key_Up || (vim && event.key === Qt.Key_K)) { bindList.decrementCurrentIndex(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (bindList.currentIndex >= 0 && bindList.currentIndex < keybinds.length) editBinding(bindList.currentIndex)
            event.accepted = true
          }
          else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (bindList.currentIndex >= 0 && bindList.currentIndex < keybinds.length) deleteBinding(bindList.currentIndex)
            event.accepted = true
          }
        }
      }

      // ---- capture overlay
      Rectangle {
        anchors.fill: parent; visible: root.isCapturing; color: root.background; z: 10
        ColumnLayout {
          anchors.centerIn: parent; spacing: Style.spacing.lg
          Text { text: "Press a key combination..."; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; Layout.alignment: Qt.AlignHCenter }
          Text { text: capturedMod !== "" ? capturedMod + " + " + capturedKey : "..."; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true; Layout.alignment: Qt.AlignHCenter }
          Button { text: "Cancel"; Layout.alignment: Qt.AlignHCenter; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.isCapturing = false }
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.isCapturing = false; event.accepted = true; return }
          if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta || event.key === Qt.Key_AltGr) { event.accepted = true; return }
          var mods = []
          if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
          if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
          if (event.modifiers & Qt.AltModifier) mods.push("ALT")
          if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
          capturedMod = mods.join(" + "); capturedKey = getKeyString(event.key); event.accepted = true
        }
      }

      // ---- main content
      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset; anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset; anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        Item {
          Layout.fillWidth: true; Layout.preferredHeight: Math.max(titleBlock.implicitHeight, headerActions.implicitHeight)
          Column {
            id: titleBlock
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: Style.spacing.xxs
            Text { text: "AuraBind"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
            Text { text: "~/.config/hypr/bindings.lua"; color: Qt.darker(root.foreground, 1.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          Row {
            id: headerActions
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.spacing.lg
            Text { text: keybinds.length + (keybinds.length === 1 ? " binding" : " bindings"); color: keybinds.length > 0 ? root.accent : Qt.darker(root.foreground, 1.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            Button { text: "Add"; enabled: !root.isCapturing; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; anchors.verticalCenter: parent.verticalCenter; onClicked: { addDialog.editIndex = -1; capturedMod = ""; capturedKey = ""; descField.text = ""; dispatcherField.text = "exec"; paramsField.text = ""; actionCombo.value = actionCombo.options[0]; addDialog.visible = true } }
            PanelActionButton { iconText: "X"; tooltipText: "Close - Esc"; foreground: root.foreground; onClicked: root.dismiss() }
          }
        }

        PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }
        TextField { id: searchField; Layout.fillWidth: true; placeholderText: "Search bindings..."; foreground: root.foreground; accent: root.accent }

        ListView {
          id: bindList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
          model: keybinds; spacing: Style.spacing.xs; currentIndex: -1
          ScrollBar.vertical: ScrollBar {}
          delegate: Rectangle {
            width: bindList.width; height: 48; color: Color.menu.selectedBackground; radius: Style.cornerRadius
            opacity: searchField.text === "" || (modelData.keys + " " + modelData.desc + " " + modelData.command).toLowerCase().indexOf(searchField.text.toLowerCase()) !== -1 ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            RowLayout {
              anchors.fill: parent; anchors.margins: Style.spacing.md; spacing: Style.spacing.lg
              Text { text: modelData.keys; color: root.accent; font.family: root.fontFamily; font.bold: true; font.pixelSize: Style.font.subtitle; Layout.preferredWidth: Style.space(140) }
              Text { text: modelData.desc; color: root.foreground; font.family: root.fontFamily; font.weight: Font.DemiBold; Layout.preferredWidth: Style.space(100); elide: Text.ElideRight }
              Text { text: modelData.type === "bind" ? modelData.command : "UNBIND"; color: modelData.type === "bind" ? root.foreground : Color.urgent; font.family: root.fontFamily; Layout.fillWidth: true; elide: Text.ElideRight }
              Button { text: "Edit"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: editBinding(index) }
              Button { text: "Del"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: deleteBinding(index) }
            }
          }
        }

        // ---- footer
        Item {
          Layout.fillWidth: true; Layout.preferredHeight: footerText.implicitHeight + Style.spacing.md
          Text {
            id: footerText
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: { if (root.errorText !== "") return root.errorText; if (root.statusText !== "") return root.statusText; return "Up/Down navigate - Enter edit - Delete remove - Esc close" }
            color: root.errorText !== "" ? Color.urgent : Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
          }
        }
      }
    }

    // ---- add/edit dialog overlay
    Rectangle {
      id: addDialog
      property int editIndex: -1
      visible: false; anchors.fill: parent; color: Qt.rgba(0,0,0,0.5); z: 100
      MouseArea { anchors.fill: parent; onClicked: {} }

      BorderSurface {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(Style.space(440), parent.width - Style.gapsOut * 4)
        height: Math.min(Style.space(520), parent.height - Style.gapsOut * 4)
        radius: Style.cornerRadius; color: root.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.panelPadding

        ColumnLayout {
          anchors.fill: parent; spacing: Style.spacing.panelGap
          Text { text: addDialog.editIndex === -1 ? "Add Binding" : "Edit Binding"; font.pixelSize: Style.font.heading; font.bold: true; color: root.foreground; Layout.alignment: Qt.AlignHCenter }
          Text { text: "Key Combination"; color: root.foreground }
          Button {
            Layout.fillWidth: true
            text: isCapturing ? "Capturing..." : ((capturedMod !== "" ? capturedMod + " + " : "") + capturedKey || "Click to capture...")
            foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
            onClicked: startCapture()
          }
          Text { text: "Description"; color: root.foreground }
          TextField { id: descField; Layout.fillWidth: true; placeholderText: "e.g. Open Terminal"; foreground: root.foreground; accent: root.accent }
          Text { text: "Action Type"; color: root.foreground }
          Dropdown {
            id: actionCombo; Layout.fillWidth: true; label: ""
            foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
            options: ["Open App", "Custom Command", "Start Plugin", "Workspace", "Kill Active", "Reload", "Unbind (Disable Default)"]
            value: options[0]
            onChanged: function(val) {
              var opts = actionCombo.options
              var idx = -1
              for (var i = 0; i < opts.length; i++) { if (opts[i] === val) { idx = i; break } }
              dispatcherField.enabled = idx !== 4 && idx !== 5 && idx !== 6
              paramsField.enabled = dispatcherField.enabled
              if (idx === 0) { dispatcherField.text = "exec"; paramsField.placeholderText = "e.g. kitty" }
              else if (idx === 1) { dispatcherField.text = ""; paramsField.placeholderText = "e.g. alacritty -e ssh" }
              else if (idx === 2) { dispatcherField.text = "exec"; paramsField.placeholderText = "e.g. omarchy-shell shell toggle" }
              else if (idx === 3) { dispatcherField.text = "workspace"; paramsField.placeholderText = "e.g. 1" }
              else if (idx === 4) { dispatcherField.text = "killactive"; paramsField.text = "" }
              else if (idx === 5) { dispatcherField.text = "reload"; paramsField.text = "" }
              else if (idx === 6) { dispatcherField.text = ""; paramsField.text = "" }
            }
          }
          Text { text: "Dispatcher"; color: root.foreground }
          TextField { id: dispatcherField; Layout.fillWidth: true; foreground: root.foreground; accent: root.accent }
          Text { text: "Parameters"; color: root.foreground }
          TextField { id: paramsField; Layout.fillWidth: true; foreground: root.foreground; accent: root.accent }
          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            Item { Layout.fillWidth: true }
            Button { text: "Cancel"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: { addDialog.visible = false; addDialog.editIndex = -1 } }
            Button { text: "Save"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: saveBinding() }
          }
        }
      }
    }
  }

  IpcHandler {
    target: "pikaga.aurabind"
    function open() { root.open("{}") }
    function close() { root.dismiss() }
    function toggle() { root.toggle() }
  }
}