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
// Scans Lua config files for every default binding, writes user overrides
// into a managed block in ~/.config/hypr/bindings.lua, detects conflicts,
// and includes an on-screen app picker for the "Open App" action type.

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (manifest && manifest.__sourceDir) || (home + "/.config/omarchy/plugins/pikaga.aurabind")
  readonly property string configPath: home + "/.config/hypr/bindings.lua"

  property bool opened: false
  property var bindings: []
  property var userBindings: []
  property bool isCapturing: false
  property string capturedMod: ""
  property string capturedKey: ""
  property string errorText: ""
  property string statusText: ""
  property int selectedActionIndex: 0
  property int bindingsRevision: 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.menuFamily

  property string categoryFilter: "All"
  property var installedApps: []
  property bool showAppPicker: false
  property bool showConflictDialog: false
  property var conflictBindings: []

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
    errorText = ""
    statusText = ""
    loadApps()
    scanBindings()
    // Also force-read from config file directly in case FileView.onLoaded
    // doesn't fire on reload
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

  // ------------------------------------------------------- scan bindings

  function scanBindings() {
    var luaPath = root.pluginDir + "/read.lua"
    var oPath = root.omarchyPath || ""
    var envPrefix = oPath ? "OMARCHY_PATH=" + oPath + " " : ""
    scannerProc.command = ["sh", "-c", envPrefix + "lua '" + luaPath.replace(/'/g, "'\\''") + "'"]
    scannerProc.running = true
  }

  function updateActionFields() {
    var idx2 = root.selectedActionIndex
    var isDisabled = idx2 === 6
    dispatcherField.enabled = !isDisabled
    paramsField.enabled = idx2 === 1
    dispatcherLabel.visible = !isDisabled
    dispatcherField.visible = !isDisabled
    paramsLabel.visible = idx2 === 1
    paramsField.visible = idx2 === 1
    if (idx2 === 0) dispatcherField.placeholderText = "e.g. kitty or firefox"
    else if (idx2 === 1) dispatcherField.placeholderText = "Full command"
    else if (idx2 === 2) dispatcherField.placeholderText = "e.g. 1 or 2"
    else if (idx2 === 3) dispatcherField.placeholderText = "e.g. omarchy.shell toggle"
    else if (idx2 === 4) dispatcherField.placeholderText = "e.g. hl.dsp.window.close()"
    else if (idx2 === 5) dispatcherField.placeholderText = "e.g. https://app.example.com"
    else if (idx2 === 6) { dispatcherField.text = ""; paramsField.text = "" }
  }

  function onScanComplete(text) {
    var all = LuaConfig.parseBindings(text)
    var managed = parseManagedConfig(configFile.text())

    var userByKey = {}
    for (var i = 0; i < managed.length; i++) {
      var u = managed[i]
      u.source = "custom"
      userByKey[u.keys + "|" + u.desc] = u
    }

    var merged = []
    var seen = {}
    for (var j = 0; j < all.length; j++) {
      var b = all[j]
      var key2 = b.keys + "|" + b.desc
      if (userByKey[key2]) {
        if (!seen[key2]) {
          var u2 = userByKey[key2]
          u2.source = "custom"
          merged.push(u2)
          seen[key2] = true
        }
        delete userByKey[key2]
      } else {
        if (!seen[key2]) {
          merged.push(b)
          seen[key2] = true
        }
      }
    }
    for (var k in userByKey) {
      if (!seen[k]) {
        userByKey[k].source = "custom"
        merged.push(userByKey[k])
        seen[k] = true
      }
    }

    root.bindings = merged
    root.userBindings = managed
    root.bindingsRevision += 1
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

  function filteredBindings(search, category, revision) {
    var out = []
    for (var i = 0; i < root.bindings.length; i++) {
      var b = root.bindings[i]
      var searchable = (b.keys + " " + b.desc + " " + b.command).toLowerCase()
      if (search !== "" && searchable.indexOf(search.toLowerCase()) === -1) continue
      if (category !== "All" && categorize(b) !== category) continue
      out.push(b)
    }
    return out
  }

  // ------------------------------------------------------- managed block parsing

  function parseManagedConfig(text) {
    var split = LuaConfig.splitBlock(text)
    if (!split.found) return []
    var binds = []
    var lines = split.body.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "" || line.startsWith("--")) continue
      var m = line.match(/^o\.bind\("([^"]+)",\s*"([^"]*)",\s*"(.+)"\)$/)
      if (m) {
        binds.push({
          type: "bind", keys: m[1], desc: m[2] || "", command: m[3], source: "custom"
        })
        continue
      }
      var u = line.match(/^hl\.unbind\("([^"]+)"\)$/)
      if (u) {
        binds.push({
          type: "unbind", keys: u[1], desc: "Disable Default", command: "", source: "custom"
        })
      }
    }
    return binds
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
    root.statusText = "Saving"
    root.selfWrite = true
    configFile.setText(next)
  }

  function noteSaved() {
    root.selfWrite = false
    root.statusText = "Saved"
    reloadProc.running = true
    configFile.reload()
    scanBindings()
  }

  function noteSaveFailed() {
    root.selfWrite = false
    root.statusText = ""
    root.errorText = "Write failed"
  }

  function rebuildBindings() {
    var all = []
    for (var i = 0; i < root.bindings.length; i++) {
      var b = root.bindings[i]
      if (b.source !== "custom") all.push(b)
    }
    for (var j = 0; j < root.userBindings.length; j++) {
      all.push(root.userBindings[j])
    }
    root.bindings = all
    root.bindingsRevision += 1
  }

  // ------------------------------------------------------- conflict detection

  function findConflicts() {
    var conflictMap = {}
    var conflicts = []
    for (var ic = 0; ic < root.bindings.length; ic++) {
      var bc = root.bindings[ic]
      var kc = bc.keys
      if (!conflictMap[kc]) conflictMap[kc] = []
      conflictMap[kc].push(bc)
    }
    for (var cc in conflictMap) {
      if (conflictMap[cc].length > 1) {
        for (var i9 = 0; i9 < conflictMap[cc].length; i9++) {
          conflicts.push(conflictMap[cc][i9])
        }
      }
    }
    return conflicts
  }

  // ------------------------------------------------------- binding CRUD

  function editBinding(index) {
    var bind = root.bindings[index]
    if (!bind) return
    addDialog.editIndex = index
    var arr = bind.keys.split(" + ")
    root.capturedKey = arr.pop()
    root.capturedMod = arr.join(" + ")
    descField.text = bind.desc
    setActionFromBinding(bind)
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

  function deleteBinding(index) {
    var bind = root.bindings[index]
    if (!bind) return
    if (bind.source === "custom") {
      var newUser = []
      for (var i3 = 0; i3 < root.userBindings.length; i3++) {
        var ub = root.userBindings[i3]
        if (ub.keys === bind.keys && ub.desc === bind.desc) continue
        newUser.push(ub)
      }
      root.userBindings = newUser
      rebuildBindings()
      saveConfig()
    } else {
      var found = false
      for (var i4 = 0; i4 < root.userBindings.length; i4++) {
        if (root.userBindings[i4].keys === bind.keys) { found = true; break }
      }
      if (!found) {
        root.userBindings.push({
          type: "unbind", keys: bind.keys, desc: "Disable Default", command: ""
        })
        rebuildBindings()
        saveConfig()
      }
    }
  }

  function saveBinding() {
    var modPrefix = root.capturedMod !== "" ? root.capturedMod + " + " : ""
    var fullKeys = modPrefix + root.capturedKey
    if (root.capturedKey === "UNKNOWN" || fullKeys.trim() === "") return

    if (root.selectedActionIndex === 6) {
      addUserBinding({ type: "unbind", keys: fullKeys, desc: descField.text || "Disabled", command: "" })
      return
    }

    var cmd = buildCommandString()
    if (cmd === null) return

    var nb2 = { type: "bind", keys: fullKeys, desc: descField.text || "Custom Binding", command: cmd, source: "custom", kind: "custom" }
    checkConflicts(fullKeys, nb2)
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
    for (var i6 = 0; i6 < root.bindings.length; i6++) {
      var b = root.bindings[i6]
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

  property var pendingNewBind: null

  function confirmConflictOverride() {
    root.showConflictDialog = false
    var nb = root.pendingNewBind
    var newUser3 = []
    for (var i7 = 0; i7 < root.userBindings.length; i7++) {
      var ub2 = root.userBindings[i7]
      if (ub2.keys === nb.keys) continue
      newUser3.push(ub2)
    }
    root.userBindings = newUser3
    root.userBindings.push(nb)
    rebuildBindings()
    saveConfig()
    addDialog.visible = false
    addDialog.editIndex = -1
    root.capturedMod = ""
    root.capturedKey = ""
  }

  function cancelConflictOverride() {
    root.showConflictDialog = false
    root.pendingNewBind = null
  }

  function addUserBinding(nb) {
    var newUser4 = []
    for (var i8 = 0; i8 < root.userBindings.length; i8++) {
      var ub3 = root.userBindings[i8]
      if (ub3.keys === nb.keys) continue
      newUser4.push(ub3)
    }
    newUser4.push(nb)
    root.userBindings = newUser4
    rebuildBindings()
    saveConfig()
    addDialog.visible = false
    addDialog.editIndex = -1
    root.capturedMod = ""
    root.capturedKey = ""
  }

  // ----------------------------------------------------------- key capture

  function startCapture() {
    isCapturing = true
    capturedMod = ""
    capturedKey = ""
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
  // ------------------------------------------------------------- processes

  Process {
    id: scannerProc
    // command set dynamically in scanBindings()
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
        var entries = String(text || "")
        root.onAppsScanned(entries)
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
    interval: 1800
    running: root.statusText === "Saved"
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

    Rectangle { anchors.fill: parent; color: root.scrim; MouseArea { anchors.fill: parent; onClicked: root.dismiss() } }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(860), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(700), window.height - Style.gapsOut * 4)
      radius: Style.cornerRadius; color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

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

      Rectangle {
        anchors.fill: parent; visible: root.isCapturing; color: root.background; z: 10
        ColumnLayout {
          anchors.centerIn: parent; spacing: Style.spacing.lg
          Text { text: "Press a key combination... (Esc to cancel)"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; Layout.alignment: Qt.AlignHCenter }
          Text { text: root.capturedMod !== "" ? root.capturedMod + " + " + root.capturedKey : "..."; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true; Layout.alignment: Qt.AlignHCenter }
          Button { text: "Cancel"; Layout.alignment: Qt.AlignHCenter; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.isCapturing = false }
        }
        Item {
          id: captureCatcher; anchors.fill: parent
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.isCapturing = false; event.accepted = true; return }
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta || event.key === Qt.Key_AltGr) { event.accepted = true; return }
            var mods = []
            if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
            if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
            if (event.modifiers & Qt.AltModifier) mods.push("ALT")
            if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
            root.capturedMod = mods.join(" + "); root.capturedKey = getKeyString(event.key); event.accepted = true
          }
        }
      }

      // ---- main content
      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(titleBlock.implicitHeight, headerActions.implicitHeight)

          Column {
            id: titleBlock
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs
            Text { text: "AuraBind"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
            Text { text: root.configPath; color: Qt.darker(root.foreground, 1.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg
            Text { text: root.bindings.length + (root.bindings.length === 1 ? " binding" : " bindings") + " (" + root.bindingsRevision + ")"; color: root.bindings.length > 0 ? root.accent : Qt.darker(root.foreground, 1.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            PanelActionButton { iconText: "X"; tooltipText: "Close"; foreground: root.foreground; anchors.verticalCenter: parent.verticalCenter; onClicked: root.dismiss() }
          }
        }

        PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

        RowLayout {
          Layout.fillWidth: true; spacing: Style.spacing.sm
          TextField { id: searchField; Layout.fillWidth: true; placeholderText: "Search keys, description, or command..."; foreground: root.foreground; accent: root.accent }
          Dropdown {
            id: categoryDropdown; Layout.preferredWidth: Style.space(180)
            foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
            value: root.categoryFilter; options: root.categories
            onChanged: function(val) { root.categoryFilter = val }
          }
        }

        ListView {
          id: bindList
          Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: Style.spacing.xs; currentIndex: -1
          ScrollBar.vertical: ScrollBar {}
          model: root.filteredBindings(searchField.text, root.categoryFilter, root.bindingsRevision)

          delegate: Rectangle {
            width: bindList.width; height: 52
            color: modelData.source === "custom" ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08) : Color.menu.selectedBackground
            radius: Style.cornerRadius
            border.width: modelData.type === "unbind" ? 1 : 0
            border.color: modelData.type === "unbind" ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.3) : "transparent"

            RowLayout {
              anchors.fill: parent; anchors.margins: Style.spacing.md; spacing: Style.spacing.sm
              Column {
                Layout.preferredWidth: Style.space(160); spacing: 2
                Text { text: modelData.keys; color: modelData.type === "unbind" ? Color.urgent : root.accent; font.family: root.fontFamily; font.bold: true; font.pixelSize: Style.font.subtitle; elide: Text.ElideRight }
                Rectangle {
                  visible: root.categorize(modelData) !== "Other"; height: 16; width: catText.implicitWidth + 6; radius: 3
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                  Text { id: catText; anchors.centerIn: parent; text: root.categorize(modelData); color: Qt.darker(root.foreground, 1.5); font.pixelSize: 9; font.family: root.fontFamily }
                }
              }
              Column { Layout.fillWidth: true; Layout.preferredWidth: Style.space(120); spacing: 2
                Text { text: modelData.desc; color: modelData.source === "custom" ? root.accent : root.foreground; font.family: root.fontFamily; font.weight: modelData.source === "custom" ? Font.Bold : Font.DemiBold; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                Text { text: modelData.source === "custom" ? "Custom" : ""; color: Qt.darker(root.accent, 1.2); font.family: root.fontFamily; font.pixelSize: 9; visible: modelData.source === "custom" }
              }
              Text { Layout.fillWidth: true; text: modelData.type === "unbind" ? "Disabled" : modelData.command; color: modelData.type === "unbind" ? Color.urgent : Qt.darker(root.foreground, 1.3); font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap }
              Button { text: "Edit"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: editBinding(index) }
              Button { text: modelData.source === "custom" ? "Del" : "Unbind"; foreground: root.foreground; accent: Color.urgent; fontFamily: root.fontFamily; onClicked: deleteBinding(index) }
            }
          }

          Rectangle {
            anchors.centerIn: parent; visible: bindList.count === 0; width: parent.width; height: 100; color: "transparent"
            Text { anchors.centerIn: parent; text: searchField.text ? 'No bindings found' : "Press + Add Binding"; color: Qt.darker(root.foreground, 1.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
        }

        Item {
          Layout.fillWidth: true; Layout.preferredHeight: footerText.implicitHeight + Style.spacing.md
          Button {
            id: addButton; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: "+ Add Binding"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; enabled: !root.isCapturing
            onClicked: { addDialog.editIndex = -1; root.capturedMod = ""; root.capturedKey = ""; descField.text = ""; dispatcherField.text = ""; paramsField.text = ""; paramsField.visible = false; paramsLabel.visible = false; root.selectedActionIndex = 0; addDialog.visible = true }
          }
          Text {
            id: footerText; anchors.left: addButton.right; anchors.leftMargin: Style.spacing.lg; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: { if (root.errorText !== "") return "Error: " + root.errorText; if (root.statusText !== "") return root.statusText; return "Up/Down or J/K  Enter edit  Del disable  Esc close  Filter by search & category" }
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
        width: Math.min(Style.space(500), parent.width - Style.gapsOut * 4)
        height: Math.min(Style.space(620), parent.height - Style.gapsOut * 4)
        radius: Style.cornerRadius; color: root.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.panelPadding

        ColumnLayout {
          anchors.fill: parent; spacing: Style.spacing.panelGap

          Text { text: addDialog.editIndex === -1 ? "Add Binding" : "Edit Binding"; font.pixelSize: Style.font.heading; font.bold: true; color: root.foreground; Layout.alignment: Qt.AlignHCenter }

          Text { text: "Key Combination"; color: root.foreground }
          Button { Layout.fillWidth: true; text: root.isCapturing ? "Capturing..." : ((root.capturedMod !== "" ? root.capturedMod + " + " : "") + root.capturedKey || "Click to capture..."); foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: startCapture() }

          Text { text: "Description"; color: root.foreground }
          TextField { id: descField; Layout.fillWidth: true; placeholderText: "e.g. Open Terminal"; foreground: root.foreground; accent: root.accent }

          Text { text: "Action Type"; color: root.foreground }
          Flow {
            Layout.fillWidth: true; spacing: Style.spacing.xxs
            Button {
              id: openAppBtn; text: "Open App"; checked: root.selectedActionIndex === 0
              checkable: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              onClicked: { root.selectedActionIndex = 0; updateActionFields() }
            }
            Button {
              id: customCmdBtn; text: "Custom Cmd"; checked: root.selectedActionIndex === 1
              checkable: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              onClicked: { root.selectedActionIndex = 1; updateActionFields() }
            }
            Button {
              id: workspaceBtn; text: "Workspace"; checked: root.selectedActionIndex === 2
              checkable: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              onClicked: { root.selectedActionIndex = 2; updateActionFields() }
            }
            Button {
              id: pluginBtn; text: "Plugin"; checked: root.selectedActionIndex === 3
              checkable: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              onClicked: { root.selectedActionIndex = 3; updateActionFields() }
            }
            Button {
              id: dispatcherBtn; text: "Lua/Disp"; checked: root.selectedActionIndex === 4
              checkable: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              onClicked: { root.selectedActionIndex = 4; updateActionFields() }
            }
            Button {
              id: webAppBtn; text: "Web App"; checked: root.selectedActionIndex === 5
              checkable: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              onClicked: { root.selectedActionIndex = 5; updateActionFields() }
            }
            Button {
              id: unbindBtn; text: "Unbind"; checked: root.selectedActionIndex === 6
              checkable: true; foreground: root.foreground; accent: Color.urgent; fontFamily: root.fontFamily
              onClicked: { root.selectedActionIndex = 6; updateActionFields() }
            }
            Button {
              id: appPickerButton
              text: "Browse Apps"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              visible: root.selectedActionIndex === 0
              onClicked: { showAppPicker = true; appPickTarget = "dispatcher"; appSearchField.text = ""; Qt.callLater(function() { appSearchField.forceActiveFocus() }) }
            }
          }

          Text { id: dispatcherLabel; text: "Command / Dispatcher"; color: root.foreground }
          TextField { id: dispatcherField; Layout.fillWidth: true; placeholderText: "e.g. kitty or firefox"; foreground: root.foreground; accent: root.accent }

          Text { id: paramsLabel; visible: false; text: "Arguments"; color: root.foreground }
          TextField { id: paramsField; Layout.fillWidth: true; visible: false; placeholderText: "e.g. --new-window"; foreground: root.foreground; accent: root.accent }

          RowLayout {
            Layout.fillWidth: true; Layout.topMargin: Style.spacing.md
            Item { Layout.fillWidth: true }
            Button { text: "Cancel"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: { addDialog.visible = false; addDialog.editIndex = -1; root.isCapturing = false } }
            Button { text: "Save"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: saveBinding() }
          }
        }
      }
    }
  }

  // ---- app picker overlay
  Rectangle {
    id: appPicker
    visible: root.showAppPicker
    anchors.fill: parent; color: Qt.rgba(0,0,0,0.5); z: 200
    MouseArea { anchors.fill: parent; onClicked: {} }

    BorderSurface {
      anchors.centerIn: parent
      width: Math.min(Style.space(480), parent.width - Style.gapsOut * 4)
      height: Math.min(Style.space(500), parent.height - Style.gapsOut * 4)
      radius: Style.cornerRadius; color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      ColumnLayout {
        anchors.fill: parent; spacing: Style.spacing.panelGap

        Text { text: "Browse Applications"; font.pixelSize: Style.font.heading; font.bold: true; color: root.foreground; Layout.alignment: Qt.AlignHCenter }
        TextField { id: appSearchField; Layout.fillWidth: true; placeholderText: "Search apps..."; foreground: root.foreground; accent: root.accent }

        ListView {
          Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: Style.spacing.xs
          ScrollBar.vertical: ScrollBar {}
          model: {
            var q = (appSearchField.text || "").toLowerCase(); var out = []
            for (var i = 0; i < root.installedApps.length; i++) {
              var a = root.installedApps[i]
              if (q === "" || (a.name.toLowerCase().indexOf(q) !== -1) || (a.exec.toLowerCase().indexOf(q) !== -1)) out.push(a)
            }
            return out
          }
          delegate: Rectangle {
            width: parent.width; height: 42; color: Color.menu.selectedBackground; radius: Style.cornerRadius
            MouseArea {
              anchors.fill: parent
              onClicked: { dispatcherField.text = modelData.exec; root.showAppPicker = false }
            }
            RowLayout {
              anchors.fill: parent; anchors.margins: Style.spacing.md; spacing: Style.spacing.sm
              Rectangle {
                width: 32; height: 32; radius: 4; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                Text { anchors.centerIn: parent; text: modelData.name.charAt(0).toUpperCase(); color: root.accent; font.family: root.fontFamily; font.bold: true; font.pixelSize: Style.font.subtitle }
              }
              Column {
                Layout.fillWidth: true; spacing: 2
                Text { text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.weight: Font.DemiBold; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                Text { text: modelData.comment || modelData.exec; color: Qt.darker(root.foreground, 1.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
              }
            }
          }
        }

        Button { Layout.alignment: Qt.AlignHCenter; text: "Cancel"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.showAppPicker = false }
      }
    }
  }

  // ---- conflict dialog overlay
  Rectangle {
    id: conflictDialog
    visible: root.showConflictDialog
    anchors.fill: parent; color: Qt.rgba(0,0,0,0.5); z: 200
    MouseArea { anchors.fill: parent; onClicked: {} }

    BorderSurface {
      anchors.centerIn: parent
      width: Math.min(Style.space(400), parent.width - Style.gapsOut * 4)
      height: Math.min(Style.space(220), parent.height - Style.gapsOut * 4)
      radius: Style.cornerRadius; color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      ColumnLayout {
        anchors.fill: parent; spacing: Style.spacing.panelGap
        Text { text: "Key Conflict"; font.pixelSize: Style.font.heading; font.bold: true; color: Color.urgent; Layout.alignment: Qt.AlignHCenter }
        Text { text: "This key combination is already used by another custom binding. Override it?"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
        Text { text: "Existing: " + (root.conflictBindings.length > 0 ? root.conflictBindings[0].desc : "unknown"); color: Qt.darker(root.foreground, 1.5); font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        RowLayout {
          Layout.fillWidth: true; Layout.topMargin: Style.spacing.md
          Item { Layout.fillWidth: true }
          Button { text: "Cancel"; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: { root.showConflictDialog = false; root.pendingNewBind = null } }
          Button { text: "Override"; foreground: root.foreground; accent: Color.urgent; fontFamily: root.fontFamily; onClicked: root.confirmConflictOverride() }
        }
      }
    }
  }

  // Run initial scan once the component is ready.
  // This ensures bindings load even if the panel opens before FileView fires.
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

  IpcHandler {
    target: "pikaga.aurabind"
    function open() { root.open("{}") }
    function close() { root.dismiss() }
    function toggle() { root.toggle() }
  }
}
