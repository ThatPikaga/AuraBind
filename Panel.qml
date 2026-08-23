import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "LuaConfig.js" as LuaConfig

// AuraBind v3.0 — Omarchy Hyprland keybindings manager.
// Shows every active keybinding, manages overrides in bindings.lua.
// Key features:
//   • Key combo builder (mod checkboxes + dropdown key selectors)
//   • Action types: Open App, Custom Cmd, Kill Active, Plugin, Lua/Dsp, Web App, Unbind
//   • App dropdown with search (all installed apps)
//   • Plugin dropdown
//   • Disabled Keybindings section with Re-enable buttons
//   • Conflict detection

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
  property var allDefaults: []
  property var mergedBindings: []
  property var userBindings: []
  property var rawManagedLines: []
  property var disabledBindings: []

  // ---- UI state
  property string errorText: ""
  property string statusText: ""
  property bool _autoPopulated: false
  property int editIndex: -1
  property bool showConflictDialog: false
  property var conflictBindings: []
  property var pendingNewBind: null
  property var selectedActionIndex: 0

  // ---- key combo builder state
  property int keyComboCount: 1
  property var keyModSuper: true
  property var keyModAlt: false
  property var keyModCtrl: false
  property var keyModShift: false
  property var keyComboKeys: []

  // ---- filter state
  property string searchText: ""
  property string categoryFilter: "All"

  // ---- dropdown data
  property var installedApps: []
  property var plugins: []

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

  readonly property var allKeys: [
    "A","B","C","D","E","F","G","H","I","J","K","L","M",
    "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
    "0","1","2","3","4","5","6","7","8","9",
    "F1","F2","F3","F4","F5","F6","F7","F8","F9","F10",
    "F11","F12","F13","F14","F15","F16","F17","F18","F19","F20",
    "F21","F22","F23","F24","F25",
    "RETURN","ESCAPE","TAB","BACKSPACE","DELETE","SPACE",
    "LEFT","RIGHT","UP","DOWN",
    "COMMA","PERIOD","SLASH","MINUS","EQUAL",
    "APOSTROPHE","SEMICOLON","BRACKETLEFT","BRACKETRIGHT","BACKSLASH","GRAVE",
    "HOME","END","PAGEUP","PAGEDOWN","INSERT",
    "PAUSE","SCROLLLOCK","PRINT","HELP","MENU",
    "XF86AudioRaiseVolume","XF86AudioLowerVolume","XF86AudioMute","XF86AudioMicMute",
    "XF86MonBrightnessUp","XF86MonBrightnessDown",
    "XF86KbdBrightnessUp","XF86KbdBrightnessDown","XF86KbdLightOnOff",
    "XF86TouchpadToggle","XF86TouchpadOn","XF86TouchpadOff",
    "XF86AudioPlay","XF86AudioPause","XF86AudioNext","XF86AudioPrev","XF86AudioStop",
    "XF86Launch1","XF86Launch2","XF86Launch3","XF86Launch4","XF86Launch5",
    "XF86Favorites","XF86Search","XF86HomePage","XF86Mail","XF86Calculator"
  ]


  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.opened = true
    root.errorText = ""
    root.statusText = ""
    root._autoPopulated = false
    root.editIndex = -1
    root.showConflictDialog = false
    root.selectedActionIndex = 0
    root.keyComboCount = 1
    root.keyModSuper = true
    root.keyModAlt = false
    root.keyModCtrl = false
    root.keyModShift = false
    root.keyComboKeys = []

    loadApps()
    loadPlugins()
    loadDisabledBindings()
    scanBindings()
    configFile.reload()
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
    flatpakProc.running = true
  }

  function onAppsScanned(text) {
    // Cache desktop apps from the first (real) scan
    if (text) {
      root.cachedDesktopApps = LuaConfig.parseDesktopEntries(text || "")
    }
    var desktopApps = root.cachedDesktopApps || []
    var seen = {}
    var combined = []
    for (var i = 0; i < desktopApps.length; i++) {
      var key = desktopApps[i].exec || desktopApps[i].name
      if (key && !seen[key]) {
        seen[key] = true
        combined.push(desktopApps[i])
      }
    }
    for (var j = 0; j < root.flatpakApps.length; j++) {
      var fa = root.flatpakApps[j]
      if (!seen[fa.exec]) {
        seen[fa.exec] = true
        combined.push(fa)
      }
    }
    combined.sort(function(a, b) {
      return (a.name || "").localeCompare(b.name || "")
    })
    root.installedApps = combined
  }

  property var cachedDesktopApps: []
  property var flatpakApps: []

  function onFlatpakScanned(text) {
    var apps = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length >= 2) {
        apps.push({
          name: parts[0],
          exec: "flatpak run " + parts[1],
          icon: "",
          categories: "",
          comment: ""
        })
      }
    }
    root.flatpakApps = apps
    root.onAppsScanned("")
  }

  // --------------------------------------------------------- load plugins

  function loadPlugins() {
    pluginScannerProc.running = true
  }

  function onPluginsScanned(text) {
    var out = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      var parts = line.split("|")
      if (parts.length >= 1) {
        out.push({
          id: parts[0],
          name: parts[1] || parts[0],
          toggleCmd: "omarchy-shell shell toggle " + parts[0]
        })
      }
    }
    root.plugins = out
  }

  // --------------------------------------------------------- load disabled bindings

  function loadDisabledBindings() {
    var found = LuaConfig.findDisabledBindings(configFile.text())
    root.disabledBindings = found
  }

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
    var split = LuaConfig.splitBlock(configFile.text())
    var managedLines = split.found ? split.body.split("\n") : []
    root.rawManagedLines = managedLines

    if (defaults.length > 0 && !LuaConfig.hasRealBindings(split.body) && !root._autoPopulated) {
      root._autoPopulated = true
      var populateBody = LuaConfig.autoPopulateLines(defaults)
      if (populateBody) {
        var newText = LuaConfig.applyBlock(configFile.text(), populateBody)
        if (newText !== configFile.text()) {
          configFile.setText(newText)
          root.statusText = "Auto-populated " + defaults.length + " default bindings"
          statusClear.restart()
          return
        }
      }
    }

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
    return LuaConfig.renderManagedBody(root.userBindings)
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
    loadDisabledBindings()
    scanBindings()
  }

  function noteSaveFailed() {
    root.selfWrite = false
    root.statusText = ""
    root.errorText = "Write failed - check permissions"
  }

  // ------------------------------------------------------- binding CRUD

  function editBinding(index) {
    var filtered = root.getFilteredBindings()
    var bind = filtered[index]
    if (!bind) return

    for (var i = 0; i < root.mergedBindings.length; i++) {
      if (root.mergedBindings[i] === bind) {
        root.editIndex = i
        break
      }
    }

    var bind2 = root.mergedBindings[root.editIndex]
    if (!bind2) return

    // Parse key combo from "SUPER + SHIFT + A" etc.
    var arr = bind2.keys.split(" + ")
    root.keyComboKeys = []
    root.keyModSuper = false; root.keyModAlt = false; root.keyModCtrl = false; root.keyModShift = false
    for (var k = 0; k < arr.length; k++) {
      var part = arr[k]
      if (part === "SUPER") root.keyModSuper = true
      else if (part === "ALT") root.keyModAlt = true
      else if (part === "CTRL") root.keyModCtrl = true
      else if (part === "SHIFT") root.keyModShift = true
      else root.keyComboKeys.push(part)
    }
    root.keyComboCount = root.keyComboKeys.length > 0 ? root.keyComboKeys.length : 1
    if (root.keyComboKeys.length === 0) root.keyComboKeys = [""]

    descField.text = bind2.desc
    root.setActionFromBinding(bind2)
    addDialog.visible = true
  }

  function setActionFromBinding(bind) {
    var at = LuaConfig.detectActionType(bind, root.installedApps)
    root.selectedActionIndex = at
  }

  function deleteBinding(index) {
    var filtered = root.getFilteredBindings()
    var bind = filtered[index]
    if (!bind) return

    if (bind.source === "custom") {
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
    var split = LuaConfig.splitBlock(configFile.text())
    var managedLines = split.found ? split.body.split("\n") : []
    root.userBindings = LuaConfig.parseManagedBlock(managedLines.join("\n"))
    var result = LuaConfig.mergeBindings(root.allDefaults, managedLines)
    root.mergedBindings = result.merged
    saveConfig()
  }

  // ------------------------------------------------------- build key combo string

  function buildKeyComboString() {
    var mods = []
    if (root.keyModSuper) mods.push("SUPER")
    if (root.keyModAlt) mods.push("ALT")
    if (root.keyModCtrl) mods.push("CTRL")
    if (root.keyModShift) mods.push("SHIFT")
    var keys = []
    for (var i = 0; i < root.keyComboKeys.length; i++) {
      if (root.keyComboKeys[i] && root.keyComboKeys[i] !== "") keys.push(root.keyComboKeys[i])
    }
    if (keys.length === 0) return ""
    var allParts = mods.concat(keys)
    return allParts.join(" + ")
  }

  // ------------------------------------------------------- save binding

  function saveBinding() {
    var fullKeys = buildKeyComboString()
    if (fullKeys === "") {
      root.errorText = "Please set at least one key combination"
      errorClear.restart()
      return
    }

    if (root.selectedActionIndex === 6) {
      addUserBinding({ type: "unbind", keys: fullKeys, desc: descField.text || "Disabled", command: "", actionType: 6 })
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
      kind: "custom",
      actionType: root.selectedActionIndex
    }
    checkConflicts(fullKeys, nb)
  }

  function buildCommandString() {
    var idx = root.selectedActionIndex
    switch (idx) {
      case 0: // Open App
        return appDropdownValue || ""
      case 1: // Custom Command
        return dispatcherField.text.trim() || null
      case 2: // Kill Active Window
        return "killactive"
      case 3: // Plugin
        return pluginDropdownValue || ""
      case 4: // Lua/Dispatcher
        return dispatcherField.text.trim() || null
      case 5: // Web App
        return dispatcherField.text.trim() || null
      case 6: // Unbind
        return null
      default:
        return dispatcherField.text.trim() || null
    }
  }

  property string appDropdownValue: ""
  property string pluginDropdownValue: ""

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
    root.keyComboKeys = []
    root.keyComboCount = 1
    root.keyModSuper = true
  }

  function cancelConflictOverride() {
    root.showConflictDialog = false
    root.pendingNewBind = null
  }

  function addUserBinding(nb) {
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
    root.keyComboKeys = []
    root.keyComboCount = 1
    root.keyModSuper = true
  }

  // ------------------------------------------------------- re-enable disabled binding

  function reEnableBinding(keys) {
    // Remove just the hl.unbind() line from the userBindings and the raw file
    var newUser = []
    for (var i = 0; i < root.userBindings.length; i++) {
      var ub = root.userBindings[i]
      if (ub.type === "unbind" && ub.keys === keys) continue
      newUser.push(ub)
    }
    root.userBindings = newUser

    // Also remove from disabledBindings
    var newDisabled = []
    for (var j = 0; j < root.disabledBindings.length; j++) {
      if (root.disabledBindings[j].keys !== keys) newDisabled.push(root.disabledBindings[j])
    }
    root.disabledBindings = newDisabled

    saveConfig()
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
    command: ["python3", home + "/.config/omarchy/plugins/pikaga.aurabind/scan_apps.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onAppsScanned(String(text || ""))
      }
    }
  }

  Process {
    id: flatpakProc
    command: ["python3", home + "/.config/omarchy/plugins/pikaga.aurabind/scan_flatpak.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onFlatpakScanned(String(text || ""))
      }
    }
  }

  Process {
    id: pluginScannerProc
    command: ["python3", home + "/.config/omarchy/plugins/pikaga.aurabind/scan_plugins.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onPluginsScanned(String(text || ""))
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

  Timer {
    id: errorClear
    interval: 3000
    running: root.errorText !== ""
    onTriggered: root.errorText = ""
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true; printErrors: false; watchChanges: true
    onLoaded: { root.loadDisabledBindings(); root.scanBindings() }
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
      loadPlugins()
      loadDisabledBindings()
    }
  }


  // ------------------------------------------------------------------- UI

  PanelWindow {
    id: window
    visible: root.opened
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
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
      width: Math.min(Style.space(960), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(780), window.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      // ---- MAIN CONTENT LAYOUT
      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset + Style.spacing.sm
        anchors.rightMargin: card.contentRightInset + Style.spacing.md
        anchors.bottomMargin: card.contentBottomInset + Style.spacing.sm
        anchors.leftMargin: card.contentLeftInset + Style.spacing.md
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
                text: root.mergedBindings.length + " total"
                color: root.mergedBindings.length > 0 ? root.accent : Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            PanelActionButton { iconText: "X"; tooltipText: "Close"; foreground: root.foreground; onClicked: root.dismiss() }
          }
        }

        PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

        // Disabled Keybindings section (if any)
        Rectangle {
          visible: root.disabledBindings.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: disabledHeader.implicitHeight + disabledList.implicitHeight + Style.spacing.md
          color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.04)
          radius: Style.cornerRadius
          border.width: 1
          border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            spacing: Style.spacing.xs

            Text {
              id: disabledHeader
              text: "⚠ Disabled Keybindings (" + root.disabledBindings.length + ")"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              id: disabledList
              model: root.disabledBindings

              Rectangle {
                width: parent.width
                height: 28
                color: "transparent"
                RowLayout {
                  anchors.fill: parent
                  spacing: Style.spacing.sm
                  Text {
                    text: modelData.keys
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    Layout.preferredWidth: Style.space(160)
                  }
                  Item { Layout.fillWidth: true }
                  Button {
                    text: "Re-enable"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.accent
                    implicitHeight: 22
                    onClicked: root.reEnableBinding(modelData.keys)
                  }
                }
              }
            }
          }
        }

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
              text: root.searchText ? "No matching bindings found" : "No bindings loaded - click + Add Binding to create one"
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
            onClicked: {
              root.editIndex = -1
              root.keyComboKeys = []
              root.keyComboCount = 1
              root.keyModSuper = true
              root.keyModAlt = false
              root.keyModCtrl = false
              root.keyModShift = false
              descField.text = ""
              dispatcherField.text = ""
              root.selectedActionIndex = 0
              root.appDropdownValue = ""
              root.pluginDropdownValue = ""
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

  // ---- add / edit binding dialog
  Rectangle {
    id: addDialog
    visible: false
    anchors.fill: parent
    color: Qt.rgba(0,0,0,0.5)
    z: 200
    MouseArea { anchors.fill: parent; onClicked: {} }

    BorderSurface {
      anchors.centerIn: parent
      width: Math.min(Style.space(520), parent.width - Style.gapsOut * 4)
      height: Math.min(Style.space(620), parent.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        // ---- Title bar
        RowLayout {
          Layout.fillWidth: true
          Text {
            id: addDialogTitle
            text: root.editIndex >= 0 ? "Edit Binding" : "Add New Binding"
            font.pixelSize: Style.font.heading
            font.bold: true
            color: root.foreground
            Layout.fillWidth: true
          }
          PanelActionButton {
            iconText: "X"
            tooltipText: "Close"
            foreground: root.foreground
            onClicked: { addDialog.visible = false; root.editIndex = -1 }
          }
        }

        // ---- Step 1: Modifier CheckBoxes
        Text {
          text: "Step 1: Modifiers"
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm
          CheckBox {
            id: modSuper
            text: "SUPER"
            checked: root.keyModSuper
            onCheckedChanged: root.keyModSuper = checked
          }
          CheckBox {
            id: modAlt
            text: "ALT"
            checked: root.keyModAlt
            onCheckedChanged: root.keyModAlt = checked
          }
          CheckBox {
            id: modCtrl
            text: "CTRL"
            checked: root.keyModCtrl
            onCheckedChanged: root.keyModCtrl = checked
          }
          CheckBox {
            id: modShift
            text: "SHIFT"
            checked: root.keyModShift
            onCheckedChanged: root.keyModShift = checked
          }
        }

        // ---- Step 2: Key combo count SpinBox
        Text {
          text: "Step 2: How many key combinations?"
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }
        SpinBox {
          id: comboCount
          from: 1
          to: 5
          value: root.keyComboCount
          onValueChanged: {
            root.keyComboCount = value
            var arr = []
            for (var i = 0; i < value; i++) {
              arr.push(root.keyComboKeys[i] !== undefined ? root.keyComboKeys[i] : "")
            }
            root.keyComboKeys = arr
          }
        }

        // ---- Step 3: Key combo selectors (Repeater)
        Text {
          text: "Step 3: Select keys"
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }
        Repeater {
          id: keySelectorRepeater
          model: root.keyComboCount

          ComboBox {
            id: keyComboBox
            Layout.fillWidth: true
            model: root.allKeys
            editable: true
            currentIndex: {
              var currentVal = root.keyComboKeys[index] || ""
              for (var i = 0; i < model.length; i++) {
                if (model[i] === currentVal) return i
              }
              return -1
            }
            onCurrentTextChanged: {
              var arr = root.keyComboKeys.slice()
              arr[index] = currentText
              root.keyComboKeys = arr
            }
          }
        }

        // ---- Key combo preview
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(36)
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          border.width: 1
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3)
          Text {
            id: comboPreview
            anchors.centerIn: parent
            text: root.buildKeyComboString() || "(no keys selected)"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        // ---- Step 4: Description
        Text {
          text: "Step 4: Description"
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }
        TextField {
          id: descField
          Layout.fillWidth: true
          placeholderText: "e.g. Open Browser"
          foreground: root.foreground
          font.family: root.fontFamily
        }

        // ---- Step 5: Action type grid
        Text {
          text: "Step 5: Action type"
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }
        GridLayout {
          id: actionGrid
          Layout.fillWidth: true
          columns: 4
          rowSpacing: Style.spacing.xs
          columnSpacing: Style.spacing.xs

          Repeater {
            model: [
              { label: "Open App", idx: 0 },
              { label: "Command", idx: 1 },
              { label: "Kill Win", idx: 2 },
              { label: "Plugin", idx: 3 },
              { label: "Lua/Dsp", idx: 4 },
              { label: "Web App", idx: 5 },
              { label: "Unbind", idx: 6 }
            ]

            Button {
              id: actionTypeBtn
              Layout.fillWidth: true
              text: modelData.label
              fontFamily: root.fontFamily
              foreground: root.selectedActionIndex === modelData.idx ? root.background : root.foreground
              accent: root.selectedActionIndex === modelData.idx ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              onClicked: {
                root.selectedActionIndex = modelData.idx
                root.appDropdownValue = ""
                root.pluginDropdownValue = ""
                dispatcherField.text = ""
                appSearchField.text = ""
              }
            }
          }
        }

        // ---- Step 6: Action-specific UI
        Text {
          text: "Step 6: Action details"
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }

        // Action 0: Open App - search + ListView
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(Style.space(160), parent.height * 0.3)
          visible: root.selectedActionIndex === 0
          color: "transparent"

          ColumnLayout {
            anchors.fill: parent
            spacing: Style.spacing.xs

            TextField {
              id: appSearchField
              Layout.fillWidth: true
              placeholderText: "Search installed apps..."
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
            }

            ListView {
              id: appListView
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              model: {
                var apps = root.installedApps
                var q = appSearchField.text.toLowerCase()
                if (q === "") return apps
                var filtered = []
                for (var i = 0; i < apps.length; i++) {
                  if ((apps[i].name || "").toLowerCase().indexOf(q) >= 0 ||
                      (apps[i].exec || "").toLowerCase().indexOf(q) >= 0) {
                    filtered.push(apps[i])
                  }
                }
                return filtered
              }

              delegate: Rectangle {
                width: ListView.view.width
                height: Style.space(28)
                color: root.appDropdownValue === modelData.exec
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                  : "transparent"
                radius: Style.cornerRadius

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.sm
                  text: modelData.name || modelData.exec
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.appDropdownValue = modelData.exec
                }
              }
            }

          // Selected app display
          Rectangle {
            visible: root.appDropdownValue !== ""
            Layout.fillWidth: true
            height: 24
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1)
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              text: "Selected: " + root.appDropdownValue
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }
          }
          }
        }

        // Action 1, 4, 5: dispatcherField
        TextField {
          id: dispatcherField
          Layout.fillWidth: true
          visible: root.selectedActionIndex === 1 || root.selectedActionIndex === 4 || root.selectedActionIndex === 5
          placeholderText: {
            if (root.selectedActionIndex === 1) return "e.g. firefox"
            if (root.selectedActionIndex === 4) return "e.g. lua script or dispatcher cmd"
            if (root.selectedActionIndex === 5) return "e.g. https://example.com"
            return ""
          }
          foreground: root.foreground
          font.family: root.fontFamily
        }

        // Action 2: Kill Active Window - explanatory text
        Text {
          Layout.fillWidth: true
          visible: root.selectedActionIndex === 2
          text: "This action kills the currently active window."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // Action 3: Plugin ListView
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(Style.space(160), parent.height * 0.3)
          visible: root.selectedActionIndex === 3
          color: "transparent"

          ListView {
            id: pluginListView
            anchors.fill: parent
            clip: true
            model: root.plugins

            delegate: Rectangle {
              width: ListView.view.width
              height: Style.space(28)
              color: root.pluginDropdownValue === modelData.toggleCmd
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                : "transparent"
              radius: Style.cornerRadius

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                text: modelData.name + (modelData.id ? " (" + modelData.id + ")" : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.pluginDropdownValue = modelData.toggleCmd
              }
            }
          }

        // Selected plugin display
        Rectangle {
          visible: root.pluginDropdownValue !== ""
          Layout.fillWidth: true
          height: 24
          radius: Style.cornerRadius
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1)
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            text: "Selected: " + root.pluginDropdownValue
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }
        }
        }

        // Action 6: Unbind - explanatory text
        Text {
          Layout.fillWidth: true
          visible: root.selectedActionIndex === 6
          text: "This will unbind (disable) the key combination."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---- Save / Cancel buttons
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.md
          Item { Layout.fillWidth: true }
          Button {
            text: "Cancel"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: { addDialog.visible = false; root.editIndex = -1 }
          }
          Button {
            text: "Save"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.saveBinding()
          }
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