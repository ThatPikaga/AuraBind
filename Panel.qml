import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "LuaConfig.js" as LuaConfig

// AuraBind v2.0 — Omarchy Hyprland keybindings manager.
// Shows every active keybinding (default + custom), edits create managed
// overrides in ~/.config/hypr/bindings.lua, detects conflicts, and
// includes an on-screen app picker for the "Open App" action type.

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (manifest && manifest.__sourceDir) || (home + "/.config/omarchy/plugins/pikaga.aurabind")
  readonly property string configPath: home + "/.config/hypr/bindings.lua"

  property bool opened: false

  // ---- data
  property var allDefaults: []           // raw from scanner (pre-merge)
  property var mergedBindings: []        // defaults + user overrides (merged, sorted)
  property var userBindings: []          // parsed from managed block lines
  property var rawManagedLines: []       // the raw body lines of the managed block

  // ---- UI state
  property bool isCapturing: false
  property string capturedMod: ""
  property string capturedKey: ""
  property string errorText: ""
  property string statusText: ""
  property int selectedActionIndex: 0
  property int editIndex: -1
  property bool showAppPicker: false
  property bool showConflictDialog: false
  property var conflictBindings: []
  property var pendingNewBind: null

  // ---- filter state
  property string searchText: ""
  property string categoryFilter: "All"

  // ---- colors & style
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color scrim: Color.menu.scrim
  property color urgent: Color.urgent
  property string fontFamily: Style.font.menuFamily

  readonly property var categories: [
    "All", "Applications", "Window Management", "Media & Audio",
    "Workspaces", "System & Menus", "Clipboard & Text",
    "Screenshots & Capture", "Notifications", "Hardware & Display",
    "Navigation"
  ]

  readonly property var categoryKeywords: {
    "Applications": ["browser", "terminal", "file manager", "editor", "music",
      "spotify", "obsidian", "signal", "docker", "chatgpt", "email",
      "calculator", "omawrite", "passwords", "youtube", "whatsapp",
      "calendar", "photos", "maps", "google", "grok", "tmux", "herdr"],
    "Window Management": ["close window", "full screen", "full width",
      "toggle window", "pseudo", "pop window", "save window", "restore window",
      "float", "tile", "group", "split", "opacity", "gaps", "drag", "resize",
      "scratchpad", "window transparency", "window square", "window gap",
      "border"],
    "Media & Audio": ["volume", "mute", "audio", "brightness", "play",
      "pause", "next track", "previous track", "media", "eject", "keyboard backlight"],
    "Workspaces": ["workspace", "move window to workspace", "switch to workspace",
      "scroll active workspace"],
    "System & Menus": ["omarchy menu", "menu toggle", "system menu",
      "power menu", "lock system", "background switcher", "theme menu",
      "toggle top bar", "toggle nightlight", "toggle locking", "toggle idle",
      "reminder", "share", "calculator", "agent"],
    "Clipboard & Text": ["copy", "paste", "cut", "clipboard", "universal copy",
      "universal paste", "universal cut", "transcode"],
    "Screenshots & Capture": ["screenshot", "screenrecording", "color picker",
      "capture", "ocr", "text capture", "webcam", "print"],
    "Notifications": ["notification", "dismiss", "reminder"],
    "Hardware & Display": ["monitor", "display", "touchpad", "keyboard",
      "scaling", "bluetooth", "network", "wifi", "battery",
      "zoom", "internal"],
    "Navigation": ["focus on", "swap window", "move window", "cycle",
      "next window", "previous window", "next monitor", "previous monitor",
      "next workspace", "tab"]
  }

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.opened = true
    root.errorText = ""
    root.statusText = ""
    root.editIndex = -1
    root.isCapturing = false
    root.showAppPicker = false
    root.showConflictDialog = false

    loadApps()
    scanBindings()
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
    if (root.opened) { root.dismiss() }
    else { root.open("{}") }
  }

  // --------------------------------------------------------- load apps

  function loadApps() {
    appScannerProc.running = true
  }

  function onAppsScanned(text) {
    root.installedApps = LuaConfig.parseDesktopEntries(text || "")
    root.installedApps.sort(function(a, b) {
      return (a.name || "").localeCompare(b.name || "")
    })
  }

  property var installedApps: []

  // ------------------------------------------------------- scan bindings

  function scanBindings() {
    var luaPath = root.pluginDir + "/read.lua"
    var oPath = root.omarchyPath || ""
    var envPrefix = oPath ? "OMARCHY_PATH=" + oPath + " " : ""
    scannerProc.command = ["sh", "-c", envPrefix + "lua '" + luaPath.replace(/'/g, "'\\''") + "'"]
    scannerProc.running = true
  }

  function onScanComplete(text) {
    var defaults = LuaConfig.parseBindings(text)

    // Parse the managed block from bindings.lua
    var split = LuaConfig.splitBlock(configFile.text())
    var managedLines = split.found ? split.body.split("\n") : []
    root.rawManagedLines = managedLines

    var result = LuaConfig.mergeBindings(defaults, managedLines)
    root.allDefaults = defaults
    root.mergedBindings = result.merged
    root.userBindings = result.userBindings

    root.statusText = root.mergedBindings.length + " bindings loaded"
    statusClear.restart()
  }

  // --------------------------------------------------------- categorization

  function categorize(binding) {
    var search = (binding.desc + " " + binding.command + " " + binding.keys).toLowerCase()
    for (var c = 0; c < root.categories.length; c++) {
      var cat = root.categories[c]
      if (cat === "All") continue
      var keywords = root.categoryKeywords[cat]
      if (!keywords) continue
      for (var k = 0; k < keywords.length; k++) {
        if (search.indexOf(keywords[k].toLowerCase()) !== -1) return cat
      }
    }
    return "Other"
  }

  function getFilteredBindings() {
    var out = []
    for (var i = 0; i < root.mergedBindings.length; i++) {
      var b = root.mergedBindings[i]
      var searchable = (b.keys + " " + b.desc + " " + b.command).toLowerCase()
      if (root.searchText !== "" && searchable.indexOf(root.searchText.toLowerCase()) === -1) continue
      if (root.categoryFilter !== "All" && categorize(b) !== root.categoryFilter) continue
      out.push(b)
    }
    return out
  }

  // ------------------------------------------------------- save config

  function renderManagedBody() {
    var lines = []
    for (var i = 0; i < root.userBindings.length; i++) {
      var b = root.userBindings[i]
      if (b.type === "bind")
        lines.push('o.bind("' + b.keys.replace(/"/g, '\\"') + '", "' + b.desc.replace(/"/g, '\\"') + '", "' + b.command.replace(/"/g, '\\"') + '")')
      else if (b.type === "unbind")
        lines.push('hl.unbind("' + b.keys + '")')
    }
    return lines.join("\n")
  }

  function saveConfig() {
    var body = renderManagedBody()
    var current = configFile.text()
    var next = LuaConfig.applyBlock(current, body)
    if (next === current) { reloadProc.running = true; return }
    root.statusText = "Saving..."
    root.selfWrite = true
    configFile.setText(next)
  }

  property bool selfWrite: false

  function noteSaved() {
    root.selfWrite = false
    root.statusText = "Saved! hyprctl reload..."
    reloadProc.running = true
    configFile.reload()
    scanBindings()
  }

  function noteSaveFailed() {
    root.selfWrite = false
    root.statusText = ""
    root.errorText = "Write failed — check permissions"
  }

  // ------------------------------------------------------- binding CRUD

  function editBinding(index) {
    // index is from the filtered list. Find the actual binding.
    var filtered = root.getFilteredBindings()
    var bind = filtered[index]
    if (!bind) return

    // Find index in mergedBindings to set editIndex on the right one
    for (var i = 0; i < root.mergedBindings.length; i++) {
      if (root.mergedBindings[i] === bind) {
        root.editIndex = i
        break
      }
    }

    var bind2 = root.mergedBindings[root.editIndex]
    if (!bind2) return

    var arr = bind2.keys.split(" + ")
    root.capturedKey = arr.pop()
    root.capturedMod = arr.join(" + ")
    descField.text = bind2.desc
    setActionFromBinding(bind2)
    addDialog.visible = true
  }

  function setActionFromBinding(bind) {
    if (bind.type === "unbind") {
      root.selectedActionIndex = 6
      dispatcherField.enabled = false
      paramsField.enabled = false
      dispatcherField.text = ""
      paramsField.text = ""
      return
    }
    dispatcherField.enabled = true
    paramsField.enabled = true
    var cmd = (bind.command || "").toLowerCase()
    var kind = bind.kind || ""
    if (kind === "lua" || kind === "menu" || kind === "toggle" || kind === "plugin") {
      root.selectedActionIndex = 4
      dispatcherField.text = bind.command || ""
      paramsField.text = ""
    } else if (kind === "webapp") {
      root.selectedActionIndex = 5
      dispatcherField.text = bind.arg || ""
      paramsField.text = ""
    } else if (cmd.indexOf("workspace ") === 0) {
      root.selectedActionIndex = 2
      dispatcherField.text = bind.command.replace(/^workspace\s+/, "")
      paramsField.text = ""
    } else if (cmd === "killactive" || cmd === "reload") {
      root.selectedActionIndex = 1
      dispatcherField.text = bind.command || ""
      paramsField.text = ""
    } else if (kind === "omarchy" || kind === "launch" || kind === "tui" || kind === "") {
      root.selectedActionIndex = 0
      dispatcherField.text = bind.arg || bind.command || ""
      paramsField.text = ""
    } else {
      root.selectedActionIndex = 1
      dispatcherField.text = bind.command || ""
      paramsField.text = ""
    }
  }

  function updateActionFields() {
    var isDisabled = root.selectedActionIndex === 6
    dispatcherField.enabled = !isDisabled
    paramsField.enabled = root.selectedActionIndex === 1
    dispatcherLabel.visible = !isDisabled
    dispatcherField.visible = !isDisabled
    paramsLabel.visible = root.selectedActionIndex === 1
    paramsField.visible = root.selectedActionIndex === 1
    if (root.selectedActionIndex === 0) dispatcherField.placeholderText = "e.g. kitty or firefox"
    else if (root.selectedActionIndex === 1) dispatcherField.placeholderText = "Full command"
    else if (root.selectedActionIndex === 2) dispatcherField.placeholderText = "e.g. 1 or 2"
    else if (root.selectedActionIndex === 3) dispatcherField.placeholderText = "e.g. omarchy.shell toggle"
    else if (root.selectedActionIndex === 4) dispatcherField.placeholderText = "e.g. hl.dsp.window.close()"
    else if (root.selectedActionIndex === 5) dispatcherField.placeholderText = "e.g. https://app.example.com"
    else if (root.selectedActionIndex === 6) { dispatcherField.text = ""; paramsField.text = "" }
  }

  function deleteBinding(index) {
    var filtered = root.getFilteredBindings()
    var bind = filtered[index]
    if (!bind) return

    if (bind.source === "custom") {
      // Remove from userBindings
      var newUser = []
      for (var i = 0; i < root.userBindings.length; i++) {
        var ub = root.userBindings[i]
        if (ub.keys === bind.keys && ub.desc === bind.desc) continue
        if (ub.type === "unbind" && ub.keys === bind.keys) continue
        newUser.push(ub)
      }
      root.userBindings = newUser
      remergeAndSave()
    } else {
      // Default binding → add an unbind for this key
      var found = false
      for (var j = 0; j < root.userBindings.length; j++) {
        if (root.userBindings[j].type === "unbind" && root.userBindings[j].keys === bind.keys) {
          found = true
          break
        }
      }
      if (!found) {
        root.userBindings.push({
          type: "unbind", keys: bind.keys, desc: "Disable Default", command: ""
        })
        remergeAndSave()
      }
    }
  }

  function remergeAndSave() {
    // Re-parse the managed body to get current userBindings
    var split = LuaConfig.splitBlock(configFile.text())
    var managedLines = split.found ? split.body.split("\n") : []
    var parsed = []
    for (var i = 0; i < managedLines.length; i++) {
      var p = LuaConfig.parseManagedLine(managedLines[i])
      if (p) parsed.push(p)
    }
    root.userBindings = parsed
    var result = LuaConfig.mergeBindings(root.allDefaults, managedLines)
    root.mergedBindings = result.merged
    saveConfig()
  }

  // ------------------------------------------------------- save binding

  function saveBinding() {
    var modPrefix = root.capturedMod !== "" ? root.capturedMod + " + " : ""
    var fullKeys = modPrefix + root.capturedKey
    if (root.capturedKey === "UNKNOWN" || fullKeys.trim() === "") return

    if (root.selectedActionIndex === 6) {
      // Unbind
      addUserBinding({ type: "unbind", keys: fullKeys, desc: descField.text || "Disabled", command: "" })
      return
    }

    var cmd = buildCommandString()
    if (cmd === null) return

    var nb = {
      type: "bind",
      keys: fullKeys,
      desc: descField.text || "Custom Binding",
      command: cmd,
      source: "custom",
      kind: "custom"
    }
    checkConflicts(fullKeys, nb)
  }

  function buildCommandString() {
    var idx = root.selectedActionIndex
    if (idx < 0 || idx > 6) return null
    switch (idx) {
      case 0: // Open App
        return dispatcherField.text.trim() || null
      case 1: // Custom Command
        return (dispatcherField.text.trim() + " " + paramsField.text.trim()).trim() || null
      case 2: // Workspace
        return "workspace " + dispatcherField.text.trim()
      case 3: // Plugin
        return dispatcherField.text.trim() || null
      case 4: // Dispatcher/Lua
        return dispatcherField.text.trim() || null
      case 5: // Web App
        return "omarchy-launch-webapp '" + (dispatcherField.text.trim() || "").replace(/'/g, "'\\''") + "'"
      case 6: // Unbind
        return null
      default:
        return dispatcherField.text.trim() || null
    }
  }

  function checkConflicts(keys, newBind) {
    root.conflictBindings = []
    for (var i = 0; i < root.mergedBindings.length; i++) {
      var b = root.mergedBindings[i]
      if (b.source === "custom" && b.keys === keys && b.desc !== newBind.desc) {
        root.conflictBindings.push(b)
      }
    }
    if (root.conflictBindings.length > 0) {
      root.pendingNewBind = newBind
      root.showConflictDialog = true
    } else {
      addUserBinding(newBind)
    }
  }

  function confirmConflictOverride() {
    root.showConflictDialog = false
    var nb = root.pendingNewBind
    root.pendingNewBind = null
    // Remove existing binding with same keys
    var newUser = []
    for (var i = 0; i < root.userBindings.length; i++) {
      var ub = root.userBindings[i]
      if (ub.keys === nb.keys) continue
      newUser.push(ub)
    }
    newUser.push(nb)
    root.userBindings = newUser

    var result = LuaConfig.mergeBindings(root.allDefaults, root.rawManagedLines)
    root.mergedBindings = result.merged
    root.userBindings = result.userBindings
    saveConfig()
    addDialog.visible = false
    root.editIndex = -1
    root.capturedMod = ""
    root.capturedKey = ""
  }

  function cancelConflictOverride() {
    root.showConflictDialog = false
    root.pendingNewBind = null
  }

  function addUserBinding(nb) {
    // Remove any existing binding with same keys
    var newUser = []
    for (var i = 0; i < root.userBindings.length; i++) {
      var ub = root.userBindings[i]
      if (ub.keys === nb.keys) continue
      newUser.push(ub)
    }
    newUser.push(nb)
    root.userBindings = newUser

    var result = LuaConfig.mergeBindings(root.allDefaults, root.rawManagedLines)
    root.mergedBindings = result.merged
    root.userBindings = result.userBindings
    saveConfig()
    addDialog.visible = false
    root.editIndex = -1
    root.capturedMod = ""
    root.capturedKey = ""
  }

  // ----------------------------------------------------------- key capture

  function startCapture() {
    root.isCapturing = true
    root.capturedMod = ""
    root.capturedKey = ""
    Qt.callLater(function() { captureCatcher.forceActiveFocus() })
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

  // ------------------------------------------------------------- Processes

  Process {
    id: scannerProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onScanComplete(text)
    }
  }

  Process {
    id: appScannerProc
    command: ["sh", "-c", "for d in /usr/share/applications $HOME/.local/share/applications; do ls $d/*.desktop 2>/dev/null | while read f; do cat \"$f\"; echo '---ENTRY---'; done; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onAppsScanned(String(text || ""))
      }
    }
  }

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
    id: statusClear
    interval: 2500
    running: root.statusText !== ""
    onTriggered: root.statusText = ""
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true; printErrors: false; watchChanges: true
    onLoaded: { root.scanBindings() }
    onLoadFailed: {}
    onSaved: root.noteSaved()
    onSaveFailed: root.noteSaveFailed()
    onFileChanged: { if (!root.selfWrite) reload() }
  }

  Timer {
    id: startupTimer
    interval: 100
    running: true
    repeat: false
    onTriggered: {
      scanBindings()
      loadApps()
    }
  }

  // ------------------------------------------------------------------- UI

  PanelWindow {
    id: window
    visible: root.opened
    anchors.fill: parent
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "aurabind"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Scrim (click to dismiss)
    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    // Main card
    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(900), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(740), window.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Keyboard navigation catcher (not capturing)
      Item {
        id: keyCatcher
        anchors.fill: parent
        visible: !root.isCapturing && !root.showAppPicker && !root.showConflictDialog
        focus: true
        Keys.onPressed: function(event) {
          var vim = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
          else if (event.key === Qt.Key_Down || (vim && event.key === Qt.Key_J)) { bindList.incrementCurrentIndex(); event.accepted = true }
          else if (event.key === Qt.Key_Up || (vim && event.key === Qt.Key_K)) { bindList.decrementCurrentIndex(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (bindList.currentIndex >= 0 && bindList.currentIndex < bindList.count) editBinding(bindList.currentIndex)
            event.accepted = true
          }
          else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (bindList.currentIndex >= 0 && bindList.currentIndex < bindList.count) deleteBinding(bindList.currentIndex)
            event.accepted = true
          }
        }
      }

      // Capture overlay
      Rectangle {
        anchors.fill: parent
        visible: root.isCapturing
        color: root.background
        z: 10
        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.spacing.xl
          Text {
            text: "Press a key combination... (Esc to cancel)"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            Layout.alignment: Qt.AlignHCenter
          }
          Text {
            text: root.capturedMod !== "" ? root.capturedMod + " + " + root.capturedKey : "..."
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
          }
          Button {
            text: "Cancel"
            Layout.alignment: Qt.AlignHCenter
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: { root.isCapturing = false }
          }
        }

        Item {
          id: captureCatcher
          anchors.fill: parent
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.isCapturing = false
              event.accepted = true
              return
            }
            // Ignore pure modifier presses
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt || event.key === Qt.Key_Meta ||
                event.key === Qt.Key_AltGr) {
              event.accepted = true
              return
            }
            var mods = []
            if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
            if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
            if (event.modifiers & Qt.AltModifier) mods.push("ALT")
            if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
            root.capturedMod = mods.join(" + ")
            root.capturedKey = getKeyString(event.key)
            event.accepted = true
          }
        }
      }

      // ---- MAIN CONTENT LAYOUT
      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        // Header
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(headerTitle.implicitHeight, headerActions.implicitHeight)

          Column {
            id: headerTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs
            Text {
              text: "AuraBind — Keybind Manager"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: root.configPath
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md
            Rectangle {
              height: 20
              width: countText.implicitWidth + 12
              radius: 4
              color: root.mergedBindings.length > 0 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
              anchors.verticalCenter: parent.verticalCenter
              Text {
                id: countText
                anchors.centerIn: parent
                text: root.mergedBindings.length + " total" + (root.mergedBindings.length !== 1 ? "" : "")
                color: root.mergedBindings.length > 0 ? root.accent : Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            PanelActionButton { iconText: "X"; tooltipText: "Close"; foreground: root.foreground; onClicked: root.dismiss() }
          }
        }

        PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

        // Search & filter bar
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search keys, description, or command..."
            foreground: root.foreground
            accent: root.accent
            onTextChanged: { root.searchText = text }
          }

          Dropdown {
            id: categoryDropdown
            Layout.preferredWidth: Style.space(180)
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            value: root.categoryFilter
            options: root.categories
            onChanged: function(val) { root.categoryFilter = val }
          }
        }

        // Binding list
        ListView {
          id: bindList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.spacing.xxs
          currentIndex: -1
          ScrollBar.vertical: ScrollBar {}
          model: root.getFilteredBindings()

          delegate: Rectangle {
            width: bindList.width
            height: 56
            color: {
              if (modelData.type === "unbind") return Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.06)
              if (modelData.source === "custom") return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
              return ListView.isCurrentItem ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            }
            radius: Style.cornerRadius
            border.width: modelData.type === "unbind" ? 1 : 0
            border.color: modelData.type === "unbind" ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.25) : "transparent"

            // Highlight row background on current
            Rectangle {
              anchors.fill: parent
              visible: ListView.isCurrentItem && modelData.type !== "unbind" && modelData.source !== "custom"
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.foreground, root.accent)
            }

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.spacing.rowPaddingX
              spacing: Style.spacing.sm

              // Key combo column
              Column {
                Layout.preferredWidth: Style.space(170)
                spacing: 2
                Text {
                  text: modelData.keys
                  color: modelData.type === "unbind" ? root.urgent : root.accent
                  font.family: root.fontFamily
                  font.bold: true
                  font.pixelSize: Style.font.subtitle
                  elide: Text.ElideRight
                }
                Rectangle {
                  visible: root.categorize(modelData) !== "Other"
                  height: 16
                  width: catLabel.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                  Text {
                    id: catLabel
                    anchors.centerIn: parent
                    text: root.categorize(modelData)
                    color: Qt.darker(root.foreground, 1.4)
                    font.pixelSize: 9
                    font.family: root.fontFamily
                  }
                }
              }

              // Description column
              Column {
                Layout.preferredWidth: Style.space(140)
                Layout.fillWidth: true
                spacing: 2
                Text {
                  text: modelData.desc
                  color: modelData.source === "custom" ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.weight: modelData.source === "custom" ? Font.Bold : Font.DemiBold
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.source === "custom" ? "✦ Custom" : (modelData.type === "unbind" ? "✕ Disabled" : "Default")
                  color: modelData.source === "custom" ? Qt.lighter(root.accent, 1.2) : (modelData.type === "unbind" ? root.urgent : Qt.darker(root.foreground, 1.5))
                  font.family: root.fontFamily
                  font.pixelSize: 9
                }
              }

              // Command column
              Text {
                Layout.fillWidth: true
                Layout.preferredWidth: Style.space(180)
                text: modelData.type === "unbind" ? "Disabled" : modelData.command
                color: modelData.type === "unbind" ? root.urgent : Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
              }

              // Action buttons
              PanelActionButton {
                iconText: "✎"
                tooltipText: "Edit"
                foreground: root.foreground
                onClicked: editBinding(index)
              }
              PanelActionButton {
                iconText: modelData.source === "custom" ? "✕" : "⊘"
                tooltipText: modelData.source === "custom" ? "Delete custom" : "Disable default"
                foreground: root.urgent
                onClicked: deleteBinding(index)
              }
            }
          }

          // Empty state
          Rectangle {
            anchors.centerIn: parent
            visible: bindList.count === 0
            width: parent.width
            height: 100
            color: "transparent"
            Text {
              anchors.centerIn: parent
              text: root.searchText ? "No matching bindings found" : "No bindings loaded — click + Add Binding to create one"
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Footer
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: footerBtn.implicitHeight + Style.spacing.md

          Button {
            id: footerBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "+ Add Binding"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            enabled: !root.isCapturing
            onClicked: {
              root.editIndex = -1
              root.capturedMod = ""
              root.capturedKey = ""
              descField.text = ""
              dispatcherField.text = ""
              paramsField.text = ""
              paramsField.visible = false
              paramsLabel.visible = false
              root.selectedActionIndex = 0
              addDialog.visible = true
            }
          }

          Text {
            id: footerHint
            anchors.left: footerBtn.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (root.errorText !== "") return "⚠ Error: " + root.errorText
              if (root.statusText !== "") return root.statusText
              return "↑↓ or J/K · Enter edit · Del disable · Esc close"
            }
            color: root.errorText !== "" ? root.urgent : Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // ---- add/edit dialog overlay
  Rectangle {
    id: addDialog
    property int editIndex: -1
    visible: false
    anchors.fill: parent
    color: Qt.rgba(0,0,0,0.5)
    z: 100
    MouseArea { anchors.fill: parent; onClicked: {} }

    BorderSurface {
      id: dialogCard
      anchors.centerIn: parent
      width: Math.min(Style.space(520), parent.width - Style.gapsOut * 4)
      height: Math.min(Style.space(680), parent.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        Text {
          text: addDialog.editIndex === -1 ? "Add Binding" : "Edit Binding"
          font.pixelSize: Style.font.heading
          font.bold: true
          color: root.foreground
          Layout.alignment: Qt.AlignHCenter
        }

        // Key capture button
        Text { text: "Key Combination"; color: root.foreground }
        Button {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(36)
          text: root.isCapturing ? "Capturing..." : (root.capturedKey ? root.capturedMod + " + " + root.capturedKey : "Click to capture...")
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onClicked: startCapture()
        }

        // Description
        Text { text: "Description"; color: root.foreground }
        TextField {
          id: descField
          Layout.fillWidth: true
          placeholderText: "e.g. Open Terminal"
          foreground: root.foreground
          accent: root.accent
        }

        // Action Type
        Text { text: "Action Type"; color: root.foreground }
        Flow {
          Layout.fillWidth: true
          spacing: Style.spacing.xxs

          Button {
            text: "Open App"
            accent: root.selectedActionIndex === 0 ? root.accent : Qt.darker(root.foreground, 1.5)
            foreground: root.selectedActionIndex === 0 ? root.accent : root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.selectedActionIndex = 0; updateActionFields() }
          }
          Button {
            text: "Custom Cmd"
            accent: root.selectedActionIndex === 1 ? root.accent : Qt.darker(root.foreground, 1.5)
            foreground: root.selectedActionIndex === 1 ? root.accent : root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.selectedActionIndex = 1; updateActionFields() }
          }
          Button {
            text: "Workspace"
            accent: root.selectedActionIndex === 2 ? root.accent : Qt.darker(root.foreground, 1.5)
            foreground: root.selectedActionIndex === 2 ? root.accent : root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.selectedActionIndex = 2; updateActionFields() }
          }
          Button {
            text: "Plugin"
            accent: root.selectedActionIndex === 3 ? root.accent : Qt.darker(root.foreground, 1.5)
            foreground: root.selectedActionIndex === 3 ? root.accent : root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.selectedActionIndex = 3; updateActionFields() }
          }
          Button {
            text: "Lua/Disp"
            accent: root.selectedActionIndex === 4 ? root.accent : Qt.darker(root.foreground, 1.5)
            foreground: root.selectedActionIndex === 4 ? root.accent : root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.selectedActionIndex = 4; updateActionFields() }
          }
          Button {
            text: "Web App"
            accent: root.selectedActionIndex === 5 ? root.accent : Qt.darker(root.foreground, 1.5)
            foreground: root.selectedActionIndex === 5 ? root.accent : root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.selectedActionIndex = 5; updateActionFields() }
          }
          Button {
            id: unbindBtn
            text: "Unbind"
            accent: root.selectedActionIndex === 6 ? root.urgent : Qt.darker(root.foreground, 1.5)
            foreground: root.selectedActionIndex === 6 ? root.urgent : root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.selectedActionIndex = 6; updateActionFields() }
          }
          Button {
            id: appPickerBtn
            text: "Browse Apps"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            visible: root.selectedActionIndex === 0
            onClicked: {
              root.showAppPicker = true
              appSearchField.text = ""
              Qt.callLater(function() { appSearchField.forceActiveFocus() })
            }
          }
        }

        // Dispatcher field
        Text { id: dispatcherLabel; text: "Command / Dispatcher"; color: root.foreground }
        TextField {
          id: dispatcherField
          Layout.fillWidth: true
          placeholderText: "e.g. kitty or firefox"
          foreground: root.foreground
          accent: root.accent
        }

        // Params field (only for Custom Command)
        Text { id: paramsLabel; visible: false; text: "Arguments"; color: root.foreground }
        TextField {
          id: paramsField
          Layout.fillWidth: true
          visible: false
          placeholderText: "e.g. --new-window"
          foreground: root.foreground
          accent: root.accent
        }

        // Dialog actions
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.md
          Item { Layout.fillWidth: true }
          Button {
            text: "Cancel"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: {
              addDialog.visible = false
              addDialog.editIndex = -1
              root.isCapturing = false
            }
          }
          Button {
            text: "Save"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: saveBinding()
          }
        }
      }
    }
  }

  // ---- app picker overlay
  Rectangle {
    id: appPicker
    visible: root.showAppPicker
    anchors.fill: parent
    color: Qt.rgba(0,0,0,0.5)
    z: 200
    MouseArea { anchors.fill: parent; onClicked: {} }

    BorderSurface {
      anchors.centerIn: parent
      width: Math.min(Style.space(480), parent.width - Style.gapsOut * 4)
      height: Math.min(Style.space(540), parent.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        Text {
          text: "Browse Applications"
          font.pixelSize: Style.font.heading
          font.bold: true
          color: root.foreground
          Layout.alignment: Qt.AlignHCenter
        }

        TextField {
          id: appSearchField
          Layout.fillWidth: true
          placeholderText: "Search apps..."
          foreground: root.foreground
          accent: root.accent
        }

        ListView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.spacing.xs
          ScrollBar.vertical: ScrollBar {}
          model: {
            var q = (appSearchField.text || "").toLowerCase()
            var out = []
            for (var i = 0; i < root.installedApps.length; i++) {
              var a = root.installedApps[i]
              if (q === "" || (a.name.toLowerCase().indexOf(q) !== -1) || (a.exec.toLowerCase().indexOf(q) !== -1))
                out.push(a)
            }
            return out
          }

          delegate: Rectangle {
            width: parent.width
            height: 42
            color: Color.menu.selectedBackground
            radius: Style.cornerRadius
            MouseArea {
              anchors.fill: parent
              onClicked: {
                dispatcherField.text = modelData.exec
                root.showAppPicker = false
              }
            }
            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              spacing: Style.spacing.sm
              Rectangle {
                width: 32
                height: 32
                radius: 4
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                Text {
                  anchors.centerIn: parent
                  text: modelData.name.charAt(0).toUpperCase()
                  color: root.accent
                  font.family: root.fontFamily
                  font.bold: true
                  font.pixelSize: Style.font.subtitle
                }
              }
              Column {
                Layout.fillWidth: true
                spacing: 2
                Text {
                  text: modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.weight: Font.DemiBold
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.comment || modelData.exec
                  color: Qt.darker(root.foreground, 1.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        Button {
          Layout.alignment: Qt.AlignHCenter
          text: "Cancel"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onClicked: root.showAppPicker = false
        }
      }
    }
  }

  // ---- conflict dialog overlay
  Rectangle {
    id: conflictDialog
    visible: root.showConflictDialog
    anchors.fill: parent
    color: Qt.rgba(0,0,0,0.5)
    z: 200
    MouseArea { anchors.fill: parent; onClicked: {} }

    BorderSurface {
      anchors.centerIn: parent
      width: Math.min(Style.space(420), parent.width - Style.gapsOut * 4)
      height: Math.min(Style.space(240), parent.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        Text {
          text: "Key Conflict"
          font.pixelSize: Style.font.heading
          font.bold: true
          color: root.urgent
          Layout.alignment: Qt.AlignHCenter
        }
        Text {
          text: "This key combination is already used by another custom binding. Override it?"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
        Text {
          text: "Existing: " + (root.conflictBindings.length > 0 ? root.conflictBindings[0].desc : "unknown")
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.md
          Item { Layout.fillWidth: true }
          Button {
            text: "Cancel"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: { root.showConflictDialog = false; root.pendingNewBind = null }
          }
          Button {
            text: "Override"
            foreground: root.foreground
            accent: root.urgent
            fontFamily: root.fontFamily
            onClicked: root.confirmConflictOverride()
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

