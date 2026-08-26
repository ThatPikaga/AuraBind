import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "LuaConfig.js" as LuaConfig

// AuraBind v5.0.1 — Omarchy Hyprland keybindings manager.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: (manifest && manifest.__sourceDir) || (home + "/.config/omarchy/plugins/thatpikaga.aurabind")
  readonly property string configPath: home + "/.config/hypr/bindings.lua"

  property bool opened: false

  // ---- data
  property var allDefaults: []
  property var mergedBindings: []
  property var userBindings: []
  property var rawManagedLines: []
  property var disabledBindings: []
  
  // Security: Safe file reading properties
  property string fileContent: ""
  property string lastModTime: ""

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

  readonly property var allKeys: [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "SPACE", "RETURN", "ESCAPE", "TAB", "BACKSPACE", "DELETE",
    "INSERT", "HOME", "END", "PAGEUP", "PAGEDOWN",
    "UP", "DOWN", "LEFT", "RIGHT",
    "CAPSLOCK", "NUMLOCK", "SCROLLLOCK", "PRINT", "PAUSE", "MENU", "HELP",
    "COMMA", "PERIOD", "SLASH", "BACKSLASH", "SEMICOLON", "APOSTROPHE",
    "MINUS", "EQUAL", "BRACKETLEFT", "BRACKETRIGHT", "GRAVE",
    "KP_0", "KP_1", "KP_2", "KP_3", "KP_4", "KP_5", "KP_6", "KP_7", "KP_8", "KP_9",
    "KP_DIVIDE", "KP_MULTIPLY", "KP_SUBTRACT", "KP_ADD", "KP_ENTER", "KP_DECIMAL",
    "XF86AudioMute", "XF86AudioLowerVolume", "XF86AudioRaiseVolume",
    "XF86AudioPlay", "XF86AudioPause", "XF86AudioStop", "XF86AudioPrev", "XF86AudioNext",
    "XF86AudioMedia", "XF86AudioMicMute",
    "XF86MonBrightnessUp", "XF86MonBrightnessDown",
    "XF86Launch0", "XF86Launch1", "XF86Launch2", "XF86Launch3", "XF86Launch4", "XF86Launch5", "XF86Launch6", "XF86Launch7", "XF86Launch8", "XF86Launch9", "XF86LaunchA", "XF86LaunchB", "XF86LaunchC", "XF86LaunchD", "XF86LaunchE", "XF86LaunchF",
    "XF86Mail", "XF86HomePage", "XF86Search", "XF86Calculator", "XF86Explorer",
    "XF86PowerOff", "XF86Sleep", "XF86WLAN", "XF86Tools",
    "MOUSE_LEFT", "MOUSE_RIGHT", "MOUSE_MIDDLE", "MOUSE_BACK", "MOUSE_FORWARD",
    "MOUSE_SCROLL_UP", "MOUSE_SCROLL_DOWN"
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
    root.statusText = "Reading bindings…"
    root.editIndex = -1
    root.showConflictDialog = false
    root.selectedActionIndex = 0
    root.keyComboCount = 1
    root.keyModSuper = true
    root.keyModAlt = false
    root.keyModCtrl = false
    root.keyModShift = false
    root.keyComboKeys = []

    loadDisabledBindings()
    scanBindings()
    safeReaderProc.running = true
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

  // --------------------------------------------------------- load disabled bindings

  function loadDisabledBindings() {
    var found = LuaConfig.findDisabledBindings(root.fileContent)
    root.disabledBindings = found
  }

  function onFileRead() {
    root.loadDisabledBindings()
    root.scanBindings()
  }

  // ------------------------------------------------------- scan bindings
  function scanBindings() {
    var oPath = root.omarchyPath || "/usr/share/omarchy"
    defaultsScannerProc.command = ["find", oPath + "/default/hypr/bindings", "-maxdepth", "1", "-name", "*.lua", "-type", "f", "-exec", "cat", "{}", "+"]
    defaultsScannerProc.running = true
  }

  function onDefaultsScanned(text) {
    var defaults = LuaConfig.parseLuaSourceForBindings(text || "", "default")
    var userFileText = root.fileContent || ""
    var split = LuaConfig.splitBlock(userFileText)
    var body = split.found ? split.body : ""
    var beforeBlock = split.found ? split.before : userFileText

    var managedLines = body.split("\n")
    root.rawManagedLines = managedLines

    var outsideBindings = LuaConfig.parseLuaSourceForBindings(beforeBlock, "custom-outside")
    var allParsed = defaults.slice()
    var combinedUserBindings = LuaConfig.parseManagedBlock(managedLines.join("\n"))
    
    for (var i = 0; i < outsideBindings.length; i++) {
      var ob = outsideBindings[i]
      if (ob.type === "unbind") {
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
    var current = root.fileContent
    var next = LuaConfig.applyBlock(current, body)
    if (next === current) { reloadProc.running = true; return }
    root.statusText = "Saving..."
    root.selfWrite = true
    writerProc.textToWrite = next
    writerProc.running = true
  }

  property bool selfWrite: false

  function noteSaved() {
    root.selfWrite = false
    root.statusText = "Saved! hyprctl reload..."
    reloadProc.running = true
    safeReaderProc.running = true
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
    
    if (bind2.command && bind2.type !== "unbind") {
        dispatcherField.text = bind2.command
    } else {
        dispatcherField.text = ""
    }
    
    addDialog.visible = true
    addDialog.forceActiveFocus()
  }

  function setActionFromBinding(bind) {
    var at = LuaConfig.detectActionType(bind)
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
      saveConfig()
    } else {
      var found = false
      for (var j = 0; j < root.userBindings.length; j++) {
        if (root.userBindings[j].type === "unbind" && root.userBindings[j].keys === bind.keys) {
          found = true
          break
        }
      }
      if (!found) {
        var newUser = root.userBindings.slice()
        newUser.push({
          type: "unbind", keys: bind.keys, desc: "Disable Default", command: ""
        })
        root.userBindings = newUser
        saveConfig()
      }
    }
  }

  function remergeAndSave() {
    var split = LuaConfig.splitBlock(root.fileContent)
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

    if (root.selectedActionIndex === 4) {
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
      case 0: return dispatcherField.text.trim() || null
      case 1: return "killactive"
      case 2: return dispatcherField.text.trim() || null
      case 3: return dispatcherField.text.trim() || null
      case 4: return null
      default: return dispatcherField.text.trim() || null
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
    var newUser = []
    for (var i = 0; i < root.userBindings.length; i++) {
      var ub = root.userBindings[i]
      if (ub.keys === nb.keys) continue
      newUser.push(ub)
    }
    newUser.push(nb)
    root.userBindings = newUser
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
    saveConfig()
    addDialog.visible = false
    root.editIndex = -1
    root.keyComboKeys = []
    root.keyComboCount = 1
    root.keyModSuper = true
  }

  // ------------------------------------------------------- re-enable disabled binding

  function reEnableBinding(keys) {
    var newUser = []
    for (var i = 0; i < root.userBindings.length; i++) {
      var ub = root.userBindings[i]
      if (ub.type === "unbind" && ub.keys === keys) continue
      newUser.push(ub)
    }
    root.userBindings = newUser

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
      onStreamFinished: {
        var t = text || ""
        if (t.length > 1000000) t = t.substring(0, 1000000)
        root.onDefaultsScanned(t)
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

  // SECURITY FIX: Bounded, no-follow regular file reader
  Process {
    id: safeReaderProc
    command: ["sh", "-c", 'f="$1"; if [ -L "$f" ]; then echo "SYMLINK"; exit 0; fi; if [ ! -f "$f" ]; then echo "NOT_FILE"; exit 0; fi; size=$(stat -c %s "$f" 2>/dev/null || echo 0); if [ "$size" -gt 5000000 ]; then echo "TOO_LARGE"; exit 0; fi; cat "$f"', "sh", root.configPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = text || ""
        if (t === "SYMLINK" || t === "NOT_FILE" || t === "TOO_LARGE") {
          root.errorText = "bindings.lua is invalid, a symlink, or too large."
          root.fileContent = ""
        } else {
          root.fileContent = t
        }
        root.onFileRead()
      }
    }
  }

  // SECURITY FIX: Safe atomic writer
  Process {
    id: writerProc
    property string textToWrite: ""
    command: ["sh", "-c", 'printf "%s" "$1" > "$2.tmp" && mv "$2.tmp" "$2"', "sh", writerProc.textToWrite, root.configPath]
    onExited: {
      if (exitCode === 0) {
        root.noteSaved()
      } else {
        root.noteSaveFailed()
      }
    }
  }

  // SECURITY FIX: Safe watcher (Polls mtime instead of reading via FileView)
  Timer {
    id: watchTimer
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: {
      checkModProc.running = true
    }
  }

  Process {
    id: checkModProc
    command: ["stat", "-c", "%Y", root.configPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var newMod = String(text || "").trim()
        if (newMod !== "" && newMod !== root.lastModTime) {
          root.lastModTime = newMod
          if (!root.selfWrite) {
            safeReaderProc.running = true
          }
        }
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

  Timer {
    id: startupTimer
    interval: 100
    running: true
    repeat: false
    onTriggered: {
      safeReaderProc.running = true
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

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      Keys.onEscapePressed: root.dismiss()
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

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

      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset + Style.spacing.sm
        anchors.rightMargin: card.contentRightInset + Style.spacing.md
        anchors.bottomMargin: card.contentBottomInset + Style.spacing.sm
        anchors.leftMargin: card.contentLeftInset + Style.spacing.md
        spacing: Style.spacing.panelGap

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
              textFormat: Text.PlainText
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
            PanelActionButton { iconText: "?"; tooltipText: "Help"; foreground: root.foreground; onClicked: { helpDialog.visible = true } }
            PanelActionButton { iconText: "X"; tooltipText: "Close"; foreground: root.foreground; onClicked: root.dismiss() }
          }
        }

        PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

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

              Column {
                Layout.preferredWidth: Style.space(190)
                spacing: 3
                Text {
                  text: modelData.keys
                  textFormat: Text.PlainText
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
                    textFormat: Text.PlainText
                    color: Qt.darker(root.foreground, 1.4)
                    font.pixelSize: 9
                    font.family: root.fontFamily
                  }
                }
              }

              Column {
                Layout.preferredWidth: Style.space(160)
                Layout.fillWidth: true
                spacing: 3
                Text {
                  text: modelData.desc
                  textFormat: Text.PlainText
                  color: modelData.source === "custom" ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.weight: modelData.source === "custom" ? Font.Bold : Font.DemiBold
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.source === "custom" ? "✦ Custom" : (modelData.type === "unbind" ? "✕ Disabled" : "Default")
                  textFormat: Text.PlainText
                  color: modelData.source === "custom" ? Qt.lighter(root.accent, 1.2) : (modelData.type === "unbind" ? root.urgent : Qt.darker(root.foreground, 1.5))
                  font.family: root.fontFamily
                  font.pixelSize: 9
                }
              }

              Text {
                Layout.fillWidth: true
                Layout.minimumWidth: Style.space(140)
                text: modelData.type === "unbind" ? "Disabled" : modelData.command
                textFormat: Text.PlainText
                color: modelData.type === "unbind" ? root.urgent : Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
              }

              Item { Layout.fillWidth: true; Layout.maximumWidth: Style.space(8) }

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

            MouseArea {
              id: mouseHover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              cursorShape: Qt.PointingHandCursor
            }
          }

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
                addDialog.visible = true
                addDialog.forceActiveFocus()
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

    Rectangle {
      id: addDialog
      visible: false
      focus: true
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
                      textFormat: Text.PlainText
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      Layout.preferredWidth: Style.space(42)
                    }

                    Item {
                      id: keySelector
                      Layout.fillWidth: true
                      Layout.preferredHeight: Style.space(36)

                      property string selectedKey: root.keyComboKeys[index] !== undefined ? root.keyComboKeys[index] : ""
                      property bool isPopupOpen: false
                      property string filterText: ""

                      Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                        border.width: 1
                        border.color: keyField.activeFocus || keySelector.isPopupOpen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: Style.spacing.sm
                          anchors.rightMargin: 0
                          spacing: 0

                          TextInput {
                            id: keyField
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: keySelector.selectedKey
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            clip: true
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter
                            
                            onTextChanged: {
                              keySelector.filterText = text
                              if (!keySelector.isPopupOpen && text.length > 0) keySelector.isPopupOpen = true
                            }
                            
                            onEditingFinished: commitSelection()
                            onActiveFocusChanged: {
                              if (!activeFocus && !keyPopup.visible) commitSelection()
                            }

                            function commitSelection() {
                              var arr = root.keyComboKeys.slice()
                              while (arr.length <= index) arr.push("")
                              arr[index] = text.toUpperCase()
                              root.keyComboKeys = arr
                              keySelector.selectedKey = text.toUpperCase()
                              keySelector.isPopupOpen = false
                            }
                            
                            Keys.onDownPressed: {
                              keyPopup.open()
                              keyListView.forceActiveFocus()
                              keyListView.currentIndex = 0
                            }
                            Keys.onEnterPressed: commitSelection()
                            Keys.onReturnPressed: commitSelection()
                            Keys.onEscapePressed: keySelector.isPopupOpen = false
                          }

                          Rectangle {
                            Layout.preferredWidth: Style.space(36)
                            Layout.fillHeight: true
                            color: "transparent"
                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                keySelector.isPopupOpen = !keySelector.isPopupOpen
                                if (keySelector.isPopupOpen) keyField.forceActiveFocus()
                              }
                            }
                            Text {
                              anchors.centerIn: parent
                              text: keySelector.isPopupOpen ? "▲" : "▼"
                              color: root.foreground
                              font.pixelSize: Style.font.caption
                            }
                          }
                        }
                      }

                      // FIX 1: Constrained Popup Size
                      Popup {
                        id: keyPopup
                        parent: addDialog
                        width: Math.min(Style.space(260), keySelector.width)
                        height: Math.min(Style.space(200), keyListView.contentHeight + Style.space(8))
                        
                        property point globalPos: keySelector.mapToItem(addDialog, 0, 0)
                        x: globalPos.x
                        y: globalPos.y + keySelector.height
                        
                        padding: 0
                        visible: keySelector.isPopupOpen
                        modal: false
                        focus: false
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                        onClosed: keySelector.isPopupOpen = false

                        background: Rectangle {
                          color: Color.popups.background
                          border.width: 1
                          border.color: Color.popups.border
                          radius: Style.cornerRadius
                        }

                        contentItem: ListView {
                          id: keyListView
                          clip: true
                          model: keySelector.filteredKeysModel
                          spacing: 2
                          ScrollBar.vertical: ScrollBar {}
                          
                          Keys.onUpPressed: { if (currentIndex > 0) currentIndex-- }
                          Keys.onDownPressed: { if (currentIndex < count - 1) currentIndex++ }
                          Keys.onEnterPressed: { if (currentItem) currentItem.selectKey() }
                          Keys.onReturnPressed: { if (currentItem) currentItem.selectKey() }
                          Keys.onEscapePressed: { keySelector.isPopupOpen = false; keyField.forceActiveFocus() }

                          delegate: Item {
                            id: keyDelegate
                            width: keyListView.width
                            height: Style.space(32)
                            
                            property bool isHovered: hoverArea.containsMouse
                            property bool isSelected: modelData.toUpperCase() === keyField.text.toUpperCase()
                            
                            function selectKey() {
                              keyField.text = modelData
                              keyField.commitSelection()
                              keyPopup.close()
                              keyField.forceActiveFocus()
                            }

                            Rectangle {
                              anchors.fill: parent
                              anchors.margins: 2
                              radius: Style.cornerRadius
                              color: isSelected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2) : 
                                     isHovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1) : "transparent"
                            }
                            
                            Text {
                              anchors.verticalCenter: parent.verticalCenter
                              anchors.left: parent.left
                              anchors.leftMargin: Style.spacing.sm
                              text: modelData
                              color: isSelected ? root.accent : root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: isSelected
                            }
                            
                            MouseArea {
                              id: hoverArea
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: keyDelegate.selectKey()
                            }
                          }
                        }
                      }

                      property var filteredKeysModel: {
                        var out = []
                        var filter = keySelector.filterText.toLowerCase()
                        for (var i = 0; i < root.allKeys.length; i++) {
                          if (filter === "" || root.allKeys[i].toLowerCase().indexOf(filter) !== -1) {
                            out.push(root.allKeys[i])
                          }
                        }
                        return out.slice(0, 100)
                      }
                    }
                  }
                }

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
                      textFormat: Text.PlainText
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
                  maximumLength: 200
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

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
                      { label: "Command", idx: 0 },
                      { label: "Kill Win", idx: 1 },
                      { label: "Lua/Dsp", idx: 2 },
                      { label: "Web App", idx: 3 },
                      { label: "Unbind", idx: 4 }
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
                          dispatcherField.text = ""
                        }
                      }
                    }
                  }
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

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

                ColumnLayout {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 0 || root.selectedActionIndex === 2 || root.selectedActionIndex === 3
                  spacing: Style.spacing.xs

                  Text {
                    text: {
                      if (root.selectedActionIndex === 0) return "Enter the command to execute (e.g. firefox, brave, flatpak run com.bitwarden):"
                      if (root.selectedActionIndex === 2) return "Enter the Lua script or dispatcher command:"
                      if (root.selectedActionIndex === 3) return "Enter the URL to open in your browser:"
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
                      if (root.selectedActionIndex === 0) return "e.g. firefox"
                      if (root.selectedActionIndex === 2) return "e.g. hl.dsp:exec_cmd() or custom function"
                      if (root.selectedActionIndex === 3) return "e.g. https://example.com"
                      return ""
                    }
                    foreground: root.foreground
                    accent: root.accent
                    font.family: root.fontFamily
                    maximumLength: 1000
                  }
                }

                Rectangle {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 1
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

                Rectangle {
                  Layout.fillWidth: true
                  visible: root.selectedActionIndex === 4
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

    Rectangle {
      id: disabledDialog
      visible: false
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
      z: 200
      MouseArea { anchors.fill: parent; onClicked: {} }

      BorderSurface {
        id: disabledDialogSurface
        anchors.centerIn: parent
        width: Math.min(Style.space(560), parent.width - Style.gapsOut * 4)
        height: Math.min(Style.space(520), parent.height - Style.gapsOut * 4)
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.popupPadding

        ColumnLayout {
          anchors.fill: parent
          anchors.topMargin: disabledDialogSurface.contentTopInset
          anchors.rightMargin: disabledDialogSurface.contentRightInset
          anchors.bottomMargin: disabledDialogSurface.contentBottomInset
          anchors.leftMargin: disabledDialogSurface.contentLeftInset
          spacing: 0

          RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Rectangle {
              width: Style.space(6)
              height: disabledDialogTitle.implicitHeight
              radius: Style.space(3)
              color: root.urgent
            }

            Text {
              id: disabledDialogTitle
              text: "⚠ Disabled Keybindings (" + root.disabledBindings.length + ")"
              font.pixelSize: Style.font.heading
              font.bold: true
              font.family: root.fontFamily
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

          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.bottomMargin: Style.spacing.sm }

          Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.spacing.md
            height: Style.space(40)
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
                font.pixelSize: Style.font.subtitle
                color: root.urgent
              }
              Text {
                Layout.fillWidth: true
                text: "These keybindings are disabled via hl.unbind(). Click Re-enable to restore the default binding."
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: Style.spacing.md
            spacing: Style.spacing.sm

            RowLayout {
              spacing: Style.spacing.sm
              Rectangle {
                width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.15)
                Text {
                  anchors.centerIn: parent; text: root.disabledBindings.length
                  color: root.urgent; font.family: root.fontFamily
                  font.pixelSize: Style.font.caption; font.bold: true
                }
              }
              Text {
                text: "Disabled bindings"
                font.pixelSize: Style.font.body; font.bold: true
                font.family: root.fontFamily; color: root.foreground
              }
            }

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
                  height: Style.space(52)
                  color: disabledHover.containsMouse
                    ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.06)
                    : "transparent"
                  radius: Style.cornerRadius
                  border.width: 1
                  border.color: disabledHover.containsMouse
                    ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.3)
                    : Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12)

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: Style.spacing.sm
                    spacing: Style.spacing.md

                    Column {
                      spacing: 2
                      Layout.fillWidth: true

                      Text {
                        text: modelData.keys
                        textFormat: Text.PlainText
                        color: root.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        text: modelData.desc || "Disabled keybinding"
                        textFormat: Text.PlainText
                        color: Qt.darker(root.foreground, 1.5)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Rectangle {
                      id: reEnableBtn
                      width: reEnableBtnLabel.implicitWidth + Style.space(24)
                      height: Style.space(30)
                      radius: Style.cornerRadius
                      color: reEnableBtnHover.containsMouse
                        ? Qt.lighter(root.accent, 1.15)
                        : root.accent
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        id: reEnableBtnLabel
                        anchors.centerIn: parent
                        text: "↻ Re-enable"
                        color: root.background
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      MouseArea {
                        id: reEnableBtnHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.reEnableBinding(modelData.keys)
                        }
                      }
                    }
                  }

                  MouseArea {
                    id: disabledHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                  }
                }

                Rectangle {
                  anchors.centerIn: parent
                  visible: disabledListView.count === 0
                  width: parent.width
                  height: 80
                  color: "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: "No disabled bindings — all defaults are active"
                    color: Qt.darker(root.foreground, 1.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.topMargin: Style.spacing.sm }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Text {
              Layout.fillWidth: true
              text: root.disabledBindings.length + " binding" + (root.disabledBindings.length === 1 ? "" : "s") + " disabled"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Rectangle {
              id: disabledCloseBtn
              width: disabledCloseLabel.implicitWidth + Style.space(28)
              height: Style.space(36)
              radius: Style.cornerRadius
              color: disabledCloseHover.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                : "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

              Text {
                id: disabledCloseLabel
                anchors.centerIn: parent
                text: "Close"
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: disabledCloseHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { disabledDialog.visible = false }
              }
            }
          }
        }
      }
    }

    // FIX 2: Redesigned conflict dialog overlay
    Rectangle {
      id: conflictDialog
      visible: root.showConflictDialog
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
      z: 200
      MouseArea { anchors.fill: parent; onClicked: {} }

      BorderSurface {
        id: conflictDialogSurface
        anchors.centerIn: parent
        width: Math.min(Style.space(480), parent.width - Style.gapsOut * 4)
        height: Math.min(Style.space(320), parent.height - Style.gapsOut * 4)
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.popupPadding

        ColumnLayout {
          anchors.fill: parent
          anchors.topMargin: conflictDialogSurface.contentTopInset
          anchors.rightMargin: conflictDialogSurface.contentRightInset
          anchors.bottomMargin: conflictDialogSurface.contentBottomInset
          anchors.leftMargin: conflictDialogSurface.contentLeftInset
          spacing: 0

          RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Rectangle {
              width: Style.space(6)
              height: conflictDialogTitle.implicitHeight
              radius: Style.space(3)
              color: root.urgent
            }

            Text {
              id: conflictDialogTitle
              text: "⚠ Key Conflict Detected"
              font.pixelSize: Style.font.heading
              font.bold: true
              font.family: root.fontFamily
              color: root.urgent
              Layout.fillWidth: true
            }

            PanelActionButton {
              iconText: "X"
              tooltipText: "Close"
              foreground: root.foreground
              onClicked: { root.showConflictDialog = false; root.pendingNewBind = null }
            }
          }

          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.bottomMargin: Style.spacing.sm }

          Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.spacing.md
            height: Style.space(64)
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
                font.pixelSize: Style.font.subtitle
                color: root.urgent
              }
              Text {
                Layout.fillWidth: true
                text: "This key combination is already used by another custom binding. Overriding it will replace the existing binding."
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.spacing.md
            spacing: Style.spacing.xxs

            Text {
              text: "Existing Binding:"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(40)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
              
              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.spacing.sm
                spacing: Style.spacing.sm
                
                Text {
                  text: root.conflictBindings.length > 0 ? root.conflictBindings[0].keys : "Unknown"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                
                Text {
                  Layout.fillWidth: true
                  text: root.conflictBindings.length > 0 ? root.conflictBindings[0].desc : "Unknown"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }
            }
          }

          Item { Layout.fillHeight: true }

          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.topMargin: Style.spacing.sm }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Item { Layout.fillWidth: true }

            Rectangle {
              id: conflictCancelBtn
              width: conflictCancelLabel.implicitWidth + Style.space(28)
              height: Style.space(36)
              radius: Style.cornerRadius
              color: conflictCancelHover.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                : "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

              Text {
                id: conflictCancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: conflictCancelHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.showConflictDialog = false; root.pendingNewBind = null }
              }
            }

            Rectangle {
              id: conflictOverrideBtn
              width: conflictOverrideLabel.implicitWidth + Style.space(32)
              height: Style.space(36)
              radius: Style.cornerRadius
              color: conflictOverrideHover.containsMouse
                ? Qt.lighter(root.urgent, 1.15)
                : root.urgent

              Text {
                id: conflictOverrideLabel
                anchors.centerIn: parent
                text: "Override"
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              MouseArea {
                id: conflictOverrideHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmConflictOverride()
              }
            }
          }
        }
      }
    }

    Rectangle {
      id: helpDialog
      visible: false
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
      z: 200
      MouseArea { anchors.fill: parent; onClicked: {} }

      BorderSurface {
        id: helpDialogSurface
        anchors.centerIn: parent
        width: Math.min(Style.space(640), parent.width - Style.gapsOut * 4)
        height: Math.min(Style.space(580), parent.height - Style.gapsOut * 4)
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.spacing.popupPadding

        ColumnLayout {
          anchors.fill: parent
          anchors.topMargin: helpDialogSurface.contentTopInset
          anchors.rightMargin: helpDialogSurface.contentRightInset
          anchors.bottomMargin: helpDialogSurface.contentBottomInset
          anchors.leftMargin: helpDialogSurface.contentLeftInset
          spacing: 0

          RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Rectangle {
              width: Style.space(6)
              height: helpDialogTitle.implicitHeight
              radius: Style.space(3)
              color: root.accent
            }

            Text {
              id: helpDialogTitle
              text: "AuraBind Help"
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
              onClicked: { helpDialog.visible = false }
            }
          }

          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.bottomMargin: Style.spacing.sm }

          ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
              width: parent.width
              spacing: Style.spacing.md

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.xs

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "ℹ"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Overview"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                Text {
                  Layout.fillWidth: true
                  width: parent.width
                  text: "AuraBind manages your Hyprland keybindings. Edit existing bindings, create custom ones, \nor disable defaults. Changes are saved to your bindings.lua file \nand applied immediately."
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.xs

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "🔍"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Finding installed programs"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: "Use these commands to find the exact name of programs you want to bind:"
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: cmdList.implicitHeight + Style.space(16)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                  border.width: 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                  ColumnLayout {
                    id: cmdList
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    spacing: Style.spacing.sm

                    Text {
                      Layout.fillWidth: true
                      text: "• pacman -Qs bitwarden"
                      color: root.accent
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                    Text {
                      Layout.fillWidth: true
                      text: "  Search installed Arch packages"
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      Layout.fillWidth: true
                      text: "• flatpak list | grep -i bitwarden"
                      color: root.accent
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                    Text {
                      Layout.fillWidth: true
                      text: "  Search Flatpak applications"
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      Layout.fillWidth: true
                      text: "• which bitwarden"
                      color: root.accent
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                    Text {
                      Layout.fillWidth: true
                      text: "  Find executable in PATH"
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      Layout.fillWidth: true
                      text: "• whereis bitwarden"
                      color: root.accent
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                    Text {
                      Layout.fillWidth: true
                      text: "  Find binary, source, and manual"
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: "Example: If you installed Bitwarden via Flatpak, use 'flatpak run com.bitwarden.desktop' as the command."
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.xs

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "⌨"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Hyprland modifiers"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: "• SUPER = Windows/Command key\n• ALT = Alt key\n• CTRL = Control key\n• SHIFT = Shift key"
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.xs

                RowLayout {
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: Style.space(22); height: Style.space(22); radius: Style.space(11)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    Text {
                      anchors.centerIn: parent; text: "💡"
                      color: root.accent; font.family: root.fontFamily
                      font.pixelSize: Style.font.caption; font.bold: true
                    }
                  }
                  Text {
                    text: "Tips"
                    font.pixelSize: Style.font.body; font.bold: true
                    font.family: root.fontFamily; color: root.foreground
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: "• Use 'hl.dsp:exec_cmd(\"command\")' for advanced Lua dispatchers\n• 'killactive' kills the focused window\n• Custom bindings override defaults\n• Disabled bindings are stored as hl.unbind() calls"
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground; Layout.fillWidth: true; Layout.topMargin: Style.spacing.sm }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.spacing.md
            spacing: Style.spacing.sm

            Item { Layout.fillWidth: true }

            Rectangle {
              id: helpCloseBtn
              width: helpCloseLabel.implicitWidth + Style.space(28)
              height: Style.space(36)
              radius: Style.cornerRadius
              color: helpCloseHover.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                : "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

              Text {
                id: helpCloseLabel
                anchors.centerIn: parent
                text: "Close"
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: helpCloseHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { helpDialog.visible = false }
              }
            }
          }
        }
      }
    }

    IpcHandler {
      target: "thatpikaga.aurabind"
      function open() { root.open("{}") }
      function close() { root.dismiss() }
      function toggle() { root.toggle() }
    }
  }
}