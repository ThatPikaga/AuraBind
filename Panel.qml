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
  readonly property string pluginDir: (manifest && manifest.__sourceDir) || (home + "/.config/omarchy/plugins/ThatPikaga.aurabind")
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

  onKeyComboCountChanged: {
    var arr = []
    for (var i = 0; i < keyComboCount; i++) {
      arr.push(keyComboKeys[i] !== undefined ? keyComboKeys[i] : "")
    }
    keyComboKeys = arr
  }

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
  //
  // Reads all Lua binding source files as plain text and PARSEs them with
  // the non-executing parser in LuaConfig.js. No file is ever loaded or
  // executed as Lua code — eliminating the arbitrary-code-execution risk
  // from the old read.lua approach.

  function scanBindings() {
    // User config is already loaded via configFile.text()
    // Load defaults from Omarchy default binding directory
    var oPath = root.omarchyPath || "/usr/share/omarchy"
    // Process to cat all default binding files
    defaultsScannerProc.command = ["sh", "-c", "cat " + oPath + "/default/hypr/bindings/*.lua 2>/dev/null || true"]
    defaultsScannerProc.running = true
  }

  function onDefaultsScanned(text) {
    // Parse default bindings from the concatenated source text
    var defaults = LuaConfig.parseLuaSourceForBindings(text || "", "default")

    // Parse user's bindings.lua (the non-managed-block portion)
    var userFileText = configFile.text() || ""
    var split = LuaConfig.splitBlock(userFileText)
    var body = split.found ? split.body : ""
    var beforeBlock = split.found ? split.before : userFileText

    // Parse user custom bindings (from the managed block)
    var managedLines = body.split("\n")
    root.rawManagedLines = managedLines

    // Also parse any hl.unbind() or o.bind() calls that the user wrote
    // BEFORE the managed block (outside the fence)
    var outsideBindings = LuaConfig.parseLuaSourceForBindings(beforeBlock, "custom-outside")

    // Merge: defaults + outside bindings for display, userBindings from the managed block
    var allParsed = defaults.slice()
    // Add outside bindings to the user bindings pool
    var combinedUserBindings = LuaConfig.parseManagedBlock(managedLines.join("\n"))
    for (var i = 0; i < outsideBindings.length; i++) {
      var ob = outsideBindings[i]
      if (ob.type === "unbind") {
        // Check if it's already in the managed block
        var found = false
        for (var j = 0; j < combinedUserBindings.length; j++) {
          if (combinedUserBindings[j].type === "unbind" && combinedUserBindings[j].keys === ob.keys) {
            found = true; break
          }
        }
        if (!found) combinedUserBindings.push(ob)
      }
    }

    var result = LuaConfig.mergeBindings(allParsed, managedLines)
    // Keep outside-bindings visible too
    for (var k = 0; k < outsideBindings.length; k++) {
      var ob2 = outsideBindings[k]
      var exists = false
      for (var j2 = 0; j2 < result.merged.length; j2++) {
        if (result.merged[j2].keys === ob2.keys && result.merged[j2].type === ob2.type) {
          exists = true; break
        }
      }
      if (!exists) {
        ob2.source = "custom"
        result.merged.unshift(ob2)
      }
    }

    root.allDefaults = allParsed
    root.mergedBindings = result.merged
    root.userBindings = combinedUserBindings

    root.statusText = result.merged.length + " bindings loaded"
    statusClear.restart()
  }

  // For completeness, also explicitly read user hl.bind/o.bind calls
  // from outside the managed block (the -- before the fence)

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
    return LuaConfig.renderManagedBody(root.allDefaults, root.userBindings)
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
    id: defaultsScannerProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onDefaultsScanned(text)
    }
  }

  Process {
    id: appScannerProc
    command: ["python3", home + "/.config/omarchy/plugins/ThatPikaga.aurabind/scan_apps.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onAppsScanned(String(text || ""))
      }
    }
  }

  Process {
    id: flatpakProc
    command: ["python3", home + "/.config/omarchy/plugins/ThatPikaga.aurabind/scan_flatpak.py"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onFlatpakScanned(String(text || ""))
      }
    }
  }

  Process {
    id: pluginScannerProc
    command: ["python3", home + "/.config/omarchy/plugins/ThatPikaga.aurabind/scan_plugins.py"]
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
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "aurabind"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Scrim (click to dismiss) — also captures Escape
    Rectangle {
      anchors.fill: parent
      color: root.scrim
      Keys.onEscapePressed: root.dismiss()
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    // Main card
    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(1024), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(820), window.height - Style.gapsOut * 4)
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
            Layout.minimumWidth: Style.space(140)
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
            id: bindingRow
            width: bindList.width
            height: 68
            color: {
              if (modelData.type === "unbind") return Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.06)
              if (modelData.source === "custom") return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
              return mouseHover.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            }
            radius: Style.cornerRadius
            border.width: modelData.type === "unbind" ? 1 : 0
            border.color: modelData.type === "unbind" ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.25) : "transparent"

            property bool hovered: mouseHover.containsMouse

            Rectangle {
              anchors.fill: parent
              visible: (ListView.isCurrentItem || bindingRow.hovered) && modelData.type !== "unbind" && modelData.source !== "custom"
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.foreground, root.accent)
            }

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.spacing.rowPaddingX
              spacing: Style.spacing.md

              // Key combo column
              Column {
                Layout.preferredWidth: Style.space(190)
                spacing: 3
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
                  width: catLabel.implicitWidth + 8
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
                Layout.preferredWidth: Style.space(160)
                Layout.fillWidth: true
                spacing: 3
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
                Layout.minimumWidth: Style.space(140)
                text: modelData.type === "unbind" ? "Disabled" : modelData.command
                color: modelData.type === "unbind" ? root.urgent : Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
              }

              // Spacer to push action buttons right
              Item { Layout.fillWidth: true; Layout.maximumWidth: Style.space(8) }

              // Action buttons
              Row {
                spacing: Style.spacing.xs
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

            // Hover detection
            MouseArea {
              id: mouseHover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              cursorShape: Qt.PointingHandCursor
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
          Layout.preferredHeight: Math.max(footerBtn.implicitHeight, disabledBtn.implicitHeight, footerHint.implicitHeight) + Style.spacing.md

          RowLayout {
            anchors.fill: parent
            spacing: Style.spacing.lg

            Button {
              id: footerBtn
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
            Layout.fillWidth: true
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

            Button {
              id: disabledBtn
              visible: root.disabledBindings.length > 0
              text: "⚠ Disabled (" + root.disabledBindings.length + ")"
              foreground: root.urgent
              accent: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)
              fontFamily: root.fontFamily
              onClicked: { disabledDialog.visible = true }
            }
          }
        }
      }
    }

    // ---- add / edit binding dialog (REDESIGNED)
    Rectangle {
      id: addDialog
      visible: false
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
      z: 200

      MouseArea { anchors.fill: parent; onClicked: {} }

      BorderSurface {
        id: addDialogSurface
        anchors.centerIn: parent
        width: Math.min(Style.space(600), parent.width - Style.gapsOut * 4)
        height: Math.min(Style.space(740), parent.height - Style.gapsOut * 4)
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.popupPadding

        ColumnLayout {
          anchors.fill: parent
          anchors.topMargin: addDialogSurface.contentTopInset
          anchors.rightMargin: addDialogSurface.contentRightInset
          anchors.bottomMargin: addDialogSurface.contentBottomInset
          anchors.leftMargin: addDialogSurface.contentLeftInset
          spacing: 0

          // ── Title bar ──────────────────────────────────────────
          RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Rectangle {
              width: Style.space(6)
              height: addDialogTitle.implicitHeight
              radius: Style.space(3)
              color: root.accent
            }

            Text {
              id: addDialogTitle
              text: root.editIndex >= 0 ? "Edit Binding" : "Add New Binding"
              font.pixelSize: Style.font.heading
              font.bold: true
              font.family: root.fontFamily
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

          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.bottomMargin: Style.spacing.sm }

          // ── Scrollable form body ───────────────────────────────
          ScrollView {
            id: addDialogScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
              width: addDialogScroll.width - Style.space(8)
              spacing: Style.spacing.lg

              // ── Step 1 · Modifiers ───────────────────────────
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.sm

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "1"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Modifiers"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                Flow {
                  Layout.fillWidth: true
                  spacing: Style.spacing.xs

                  Repeater {
                    model: [
                      { label: "SUPER", prop: "keyModSuper" },
                      { label: "ALT",   prop: "keyModAlt" },
                      { label: "CTRL",  prop: "keyModCtrl" },
                      { label: "SHIFT", prop: "keyModShift" }
                    ]

                    delegate: Rectangle {
                      id: modPill
                      width: modPillLabel.implicitWidth + Style.space(24)
                      height: Style.space(32)
                      radius: Style.space(16)
                      color: {
                        var active = modelData.prop === "keyModSuper" ? root.keyModSuper
                                   : modelData.prop === "keyModAlt"   ? root.keyModAlt
                                   : modelData.prop === "keyModCtrl"  ? root.keyModCtrl
                                   : root.keyModShift
                        return active
                          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                      }
                      border.width: 1
                      border.color: {
                        var active = modelData.prop === "keyModSuper" ? root.keyModSuper
                                   : modelData.prop === "keyModAlt"   ? root.keyModAlt
                                   : modelData.prop === "keyModCtrl"  ? root.keyModCtrl
                                   : root.keyModShift
                        return active
                          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                      }

                      Text {
                        id: modPillLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: {
                          var active = modelData.prop === "keyModSuper" ? root.keyModSuper
                                     : modelData.prop === "keyModAlt"   ? root.keyModAlt
                                     : modelData.prop === "keyModCtrl"  ? root.keyModCtrl
                                     : root.keyModShift
                          return active ? root.accent : Qt.darker(root.foreground, 1.4)
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (modelData.prop === "keyModSuper") root.keyModSuper = !root.keyModSuper
                          else if (modelData.prop === "keyModAlt") root.keyModAlt = !root.keyModAlt
                          else if (modelData.prop === "keyModCtrl") root.keyModCtrl = !root.keyModCtrl
                          else if (modelData.prop === "keyModShift") root.keyModShift = !root.keyModShift
                        }
                      }
                    }
                  }
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              // ── Step 2 · Key Count ───────────────────────────
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.sm

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "2"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Number of keys"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                RowLayout {
                  spacing: Style.spacing.xs

                  Rectangle {
                    width: Style.space(32); height: Style.space(32); radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "−"
                      color: root.foreground; font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle; font.bold: true
                    }
                    MouseArea {
                      anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                      onClicked: { if (root.keyComboCount > 1) root.keyComboCount-- }
                    }
                  }

                  Rectangle {
                    width: Style.space(44); height: Style.space(32); radius: Style.cornerRadius
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1)
                    border.width: 1
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3)
                    Text {
                      anchors.centerIn: parent
                      text: String(root.keyComboCount)
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle; font.bold: true
                    }
                  }

                  Rectangle {
                    width: Style.space(32); height: Style.space(32); radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "+"
                      color: root.foreground; font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle; font.bold: true
                    }
                    MouseArea {
                      anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                      onClicked: { if (root.keyComboCount < 5) root.keyComboCount++ }
                    }
                  }

                  Text {
                    text: "key" + (root.keyComboCount > 1 ? "s" : "") + " in combo"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.leftMargin: Style.spacing.xs
                  }
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              // ── Step 3 · Key Selectors ───────────────────────
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.sm

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "3"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Select keys"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                Repeater {
                  model: root.keyComboCount

                  delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.xs

                    Text {
                      text: "Key " + (index + 1)
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      Layout.preferredWidth: Style.space(42)
                    }

                    Dropdown {
                      Layout.fillWidth: true
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      value: root.keyComboKeys[index] || ""
                      options: root.allKeys
                      onChanged: function(val) {
                        var arr = root.keyComboKeys.slice()
                        while (arr.length <= index) arr.push("")
                        arr[index] = val
                        root.keyComboKeys = arr
                      }
                    }
                  }
                }

                // Key combo preview (prominent)
                Rectangle {
                  Layout.fillWidth: true
                  Layout.topMargin: Style.spacing.xs
                  Layout.preferredHeight: Style.space(44)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
                  border.width: 1
                  border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.spacing.sm

                    Text {
                      text: "⌨"
                      font.pixelSize: Style.font.subtitle
                      color: root.accent
                    }

                    Text {
                      text: root.buildKeyComboString() || "(no keys selected)"
                      color: root.buildKeyComboString() ? root.foreground : Qt.darker(root.foreground, 1.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle
                      font.bold: true
                      font.letterSpacing: Style.space(1)
                    }
                  }
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              // ── Step 4 · Description ─────────────────────────
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.sm

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "4"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Description"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                TextField {
                  id: descField
                  Layout.fillWidth: true
                  placeholderText: "e.g. Open Browser"
                  foreground: root.foreground
                  accent: root.accent
                  font.family: root.fontFamily
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              // ── Step 5 · Action Type ─────────────────────────
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.sm

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "5"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Action type"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                Flow {
                  Layout.fillWidth: true
                  spacing: Style.spacing.xs

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

                    delegate: Rectangle {
                      id: actionPill
                      width: actionPillLabel.implicitWidth + Style.space(20)
                      height: Style.space(30)
                      radius: Style.space(15)
                      color: root.selectedActionIndex === modelData.idx
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                      border.width: 1
                      border.color: root.selectedActionIndex === modelData.idx
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                      Text {
                        id: actionPillLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: root.selectedActionIndex === modelData.idx
                        color: root.selectedActionIndex === modelData.idx
                          ? root.accent
                          : Qt.darker(root.foreground, 1.3)
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
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
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              // ── Step 6 · Action Details ──────────────────────
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.sm

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "6"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Action details"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                // Action 0: Open App
                ColumnLayout {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 0
                  spacing: Style.spacing.xs

                  TextField {
                    id: appSearchField
                    Layout.fillWidth: true
                    placeholderText: "Search installed apps…"
                    foreground: root.foreground
                    accent: root.accent
                    font.family: root.fontFamily
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(180)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                    clip: true

                    ListView {
                      id: appListView
                      anchors.fill: parent
                      anchors.margins: Style.space(2)
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
                        height: Style.space(30)
                        radius: Style.space(4)
                        color: {
                          if (root.appDropdownValue === modelData.exec)
                            return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                          if (appDelegateHover.containsMouse)
                            return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                          return "transparent"
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          anchors.left: parent.left
                          anchors.leftMargin: Style.spacing.sm
                          anchors.right: parent.right
                          anchors.rightMargin: Style.spacing.sm
                          text: modelData.name || modelData.exec
                          color: root.appDropdownValue === modelData.exec ? root.accent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: root.appDropdownValue === modelData.exec
                          elide: Text.ElideRight
                        }

                        MouseArea {
                          id: appDelegateHover
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.appDropdownValue = modelData.exec
                        }
                      }
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: appListView.count === 0
                      text: appSearchField.text ? "No apps match your search" : "Loading apps…"
                      color: Qt.darker(root.foreground, 1.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    visible: root.appDropdownValue !== ""
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: Style.spacing.sm
                      anchors.rightMargin: Style.spacing.sm
                      spacing: Style.spacing.xs

                      Text {
                        text: "✓"
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      Text {
                        Layout.fillWidth: true
                        text: root.appDropdownValue
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                // Action 1, 4, 5: Command / Lua / Web
                ColumnLayout {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 1 || root.selectedActionIndex === 4 || root.selectedActionIndex === 5
                  spacing: Style.spacing.xs

                  Text {
                    text: {
                      if (root.selectedActionIndex === 1) return "Enter the command to execute:"
                      if (root.selectedActionIndex === 4) return "Enter the Lua script or dispatcher command:"
                      if (root.selectedActionIndex === 5) return "Enter the URL to open:"
                      return ""
                    }
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  TextField {
                    id: dispatcherField
                    Layout.fillWidth: true
                    placeholderText: {
                      if (root.selectedActionIndex === 1) return "e.g. firefox"
                      if (root.selectedActionIndex === 4) return "e.g. lua script or dispatcher cmd"
                      if (root.selectedActionIndex === 5) return "e.g. https://example.com"
                      return ""
                    }
                    foreground: root.foreground
                    accent: root.accent
                    font.family: root.fontFamily
                  }
                }

                // Action 2: Kill Active Window
                Rectangle {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 2
                  height: Style.space(48)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.06)
                  border.width: 1
                  border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.2)

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.md
                    anchors.rightMargin: Style.spacing.md
                    spacing: Style.spacing.sm

                    Text {
                      text: "⚠"
                      font.pixelSize: Style.font.body
                      color: root.urgent
                    }
                    Text {
                      Layout.fillWidth: true
                      text: "This action kills the currently active window."
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                  }
                }

                // Action 3: Plugin
                ColumnLayout {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 3
                  spacing: Style.spacing.xs

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(180)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                    clip: true

                    ListView {
                      id: pluginListView
                      anchors.fill: parent
                      anchors.margins: Style.space(2)
                      clip: true
                      model: root.plugins

                      delegate: Rectangle {
                        width: ListView.view.width
                        height: Style.space(30)
                        radius: Style.space(4)
                        color: {
                          if (root.pluginDropdownValue === modelData.toggleCmd)
                            return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                          if (pluginDelegateHover.containsMouse)
                            return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                          return "transparent"
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          anchors.left: parent.left
                          anchors.leftMargin: Style.spacing.sm
                          anchors.right: parent.right
                          anchors.rightMargin: Style.spacing.sm
                          text: modelData.name + (modelData.id ? "  (" + modelData.id + ")" : "")
                          color: root.pluginDropdownValue === modelData.toggleCmd ? root.accent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: root.pluginDropdownValue === modelData.toggleCmd
                          elide: Text.ElideRight
                        }

                        MouseArea {
                          id: pluginDelegateHover
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.pluginDropdownValue = modelData.toggleCmd
                        }
                      }
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: pluginListView.count === 0
                      text: "Loading plugins…"
                      color: Qt.darker(root.foreground, 1.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    visible: root.pluginDropdownValue !== ""
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: Style.spacing.sm
                      anchors.rightMargin: Style.spacing.sm
                      spacing: Style.spacing.xs

                      Text {
                        text: "✓"
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      Text {
                        Layout.fillWidth: true
                        text: root.pluginDropdownValue
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                // Action 6: Unbind
                Rectangle {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 6
                  height: Style.space(48)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.06)
                  border.width: 1
                  border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.2)

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.md
                    anchors.rightMargin: Style.spacing.md
                    spacing: Style.spacing.sm

                    Text {
                      text: "⊘"
                      font.pixelSize: Style.font.body
                      color: root.urgent
                    }
                    Text {
                      Layout.fillWidth: true
                      text: "This will unbind (disable) the key combination."
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                  }
                }
              }
            }
          }

          // ── Footer: Cancel / Save ────────────────────────────
          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.topMargin: Style.spacing.sm }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Text {
              Layout.fillWidth: true
              visible: root.errorText !== ""
              text: "⚠ " + root.errorText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true; visible: root.errorText === "" }

            // Cancel — ghost style
            Rectangle {
              id: cancelBtn
              width: cancelBtnLabel.implicitWidth + Style.space(28)
              height: Style.space(36)
              radius: Style.cornerRadius
              color: cancelBtnHover.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                : "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

              Text {
                id: cancelBtnLabel
                anchors.centerIn: parent
                text: "Cancel"
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: cancelBtnHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { addDialog.visible = false; root.editIndex = -1 }
              }
            }

            // Save — accent-filled primary
            Rectangle {
              id: saveBtn
              width: saveBtnLabel.implicitWidth + Style.space(32)
              height: Style.space(36)
              radius: Style.cornerRadius
              color: saveBtnHover.containsMouse
                ? Qt.lighter(root.accent, 1.15)
                : root.accent

              Text {
                id: saveBtnLabel
                anchors.centerIn: parent
                text: root.editIndex >= 0 ? "Update" : "Save"
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              MouseArea {
                id: saveBtnHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveBinding()
              }
            }
          }
        }
      }
    }

    // ---- disabled keybindings dialog overlay
    Rectangle {
      id: disabledDialog
      visible: false
      anchors.fill: parent
      color: Qt.rgba(0,0,0,0.5)
      z: 200
      MouseArea { anchors.fill: parent; onClicked: {} }

      BorderSurface {
        anchors.centerIn: parent
        width: Math.min(Style.space(520), parent.width - Style.gapsOut * 4)
        height: Math.min(Style.space(480), parent.height - Style.gapsOut * 4)
        radius: Style.cornerRadius
        color: root.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.panelPadding

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.spacing.panelGap

          // Title bar
          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "⚠ Disabled Keybindings (" + root.disabledBindings.length + ")"
              font.pixelSize: Style.font.heading
              font.bold: true
              color: root.urgent
              Layout.fillWidth: true
            }
            PanelActionButton {
              iconText: "X"
              tooltipText: "Close"
              foreground: root.foreground
              onClicked: { disabledDialog.visible = false }
            }
          }

          Text {
            text: "These keybindings have been disabled via hl.unbind(). Click Re-enable to restore the default."
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Scrollable list of disabled bindings
          ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ListView {
              id: disabledListView
              anchors.fill: parent
              spacing: Style.spacing.xs
              model: root.disabledBindings

              delegate: Rectangle {
                width: disabledListView.width
                height: Style.space(36)
                color: mouseHover.containsMouse
                  ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.08)
                  : "transparent"
                radius: Style.cornerRadius
                border.width: 1
                border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.sm
                  spacing: Style.spacing.sm

                  Text {
                    text: modelData.keys
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    Layout.preferredWidth: Style.space(180)
                  }

                  Item { Layout.fillWidth: true }

                  Button {
                    text: "Re-enable"
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    accent: root.accent
                    implicitHeight: 24
                    onClicked: {
                      root.reEnableBinding(modelData.keys)
                    }
                  }
                }

                MouseArea {
                  id: mouseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  cursorShape: Qt.PointingHandCursor
                }
              }
            }
          }

          // Close button at bottom
          RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Button {
              text: "Close"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: { disabledDialog.visible = false }
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
      target: "ThatPikaga.aurabind"
      function open() { root.open("{}") }
      function close() { root.dismiss() }
      function toggle() { root.toggle() }
    }
  }
}