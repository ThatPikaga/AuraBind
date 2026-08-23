.pragma library

// AuraBind managed block handler.
//
// Renders and parses the managed block inside ~/.config/hypr/bindings.lua.
// The block contains o.bind() and hl.unbind() calls that AuraBind owns.
// Whatever is outside the fences is left untouched.
//
// The block lines are one of:
//   o.bind("KEYS", "DESC", "COMMAND")
//   o.bind("KEYS", "DESC", hl.dsp...())          -- Lua dispatcher as raw code
//   hl.unbind("KEYS")
//
// parseBindings reads tab-separated records from read.lua's stdout.

var BEGIN_FENCE = "-- >>> aurabind managed keybindings block >>>"
var END_FENCE = "-- <<< aurabind managed keybindings block <<<"

// -------------------------------------------------------------------- split

function splitBlock(text) {
  var source = String(text || "")
  var begin = source.indexOf(BEGIN_FENCE)
  if (begin === -1) return { found: false, before: source, body: "", after: "" }
  var endFence = source.indexOf(END_FENCE, begin)
  if (endFence === -1) return { found: false, before: source, body: "", after: "" }
  return {
    found: true,
    before: source.substring(0, begin),
    body: source.substring(begin + BEGIN_FENCE.length, endFence),
    after: source.substring(endFence + END_FENCE.length)
  }
}

// -------------------------------------------------------------------- apply

// An empty body removes the block entirely.
function applyBlock(text, body) {
  var split = splitBlock(text)

  if (!body) {
    if (!split.found) return String(text || "")
    var joined = split.before.replace(/\n+$/, "\n") + split.after.replace(/^\n+/, "")
    return joined.replace(/\n{3,}$/, "\n")
  }

  var block = renderBlock(body)
  if (split.found) return split.before + block + split.after

  var head = String(text || "")
  if (head.length > 0 && head[head.length - 1] !== "\n") head += "\n"
  return head + "\n" + block + "\n"
}

// ----------------------------------------------------------------- render

function renderBlock(body) {
  var header = BEGIN_FENCE + "\n"
    + "-- Written by AuraBind. Safe to hand-edit: the app re-reads this block\n"
    + "-- every time it opens, and only ever rewrites what's between the fences.\n"
  if (!body) return header + END_FENCE
  return header + body + "\n" + END_FENCE
}

// ----------------------------------------------------------------- parse managed block

// Parse a single managed-block line into a binding object.
// Handles:
//   o.bind("KEYS", "DESC", "PLAIN_COMMAND")
//   o.bind("KEYS", "DESC", hl.dsp...())       -- Lua dispatcher
//   hl.unbind("KEYS")
function parseManagedLine(line) {
  var s = line.trim()
  if (s === "" || s.startsWith("--")) return null

  // hl.unbind("KEYS")
  var m = s.match(/^hl\.unbind\("([^"]+)"\)$/)
  if (m) {
    return {
      type: "unbind",
      keys: m[1],
      desc: "Disable Default",
      command: "",
      source: "custom"
    }
  }

  // o.bind("KEYS", "DESC", "COMMAND_OR_DSP")
  // The third argument can be a quoted string or a hl.dsp expression.
  // Try the plain quoted-string form first.
  m = s.match(/^o\.bind\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\)$/)
  if (m) {
    return {
      type: "bind",
      keys: m[1],
      desc: m[2] || "",
      command: m[3] || "",
      source: "custom",
      kind: detectStoredKind(m[3] || "")
    }
  }

  // Try the Lua-dispatcher form: o.bind("KEYS", "DESC", hl.dsp...())
  m = s.match(/^o\.bind\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(.+)\)\s*$/)
  if (m) {
    return {
      type: "bind",
      keys: m[1],
      desc: m[2] || "",
      command: m[3] || "",
      source: "custom",
      kind: "lua"
    }
  }

  return null
}

function detectStoredKind(command) {
  if (!command) return "exec"
  if (command.indexOf("omarchy-launch-webapp") >= 0) return "webapp"
  if (command.indexOf("omarchy-launch-") >= 0) return "omarchy"
  if (command.indexOf("omarchy-shell shell toggle ") >= 0) return "plugin"
  if (command.indexOf("omarchy-menu") >= 0) return "menu"
  if (command.indexOf("omarchy-toggle-") >= 0) return "toggle"
  if (command.indexOf("hl.dsp") >= 0 || command.indexOf("hl.dispatch") >= 0) return "lua"
  if (command.indexOf("uwsm-app") >= 0) return "launch"
  if (command.indexOf("omarchy-launch-or-focus") >= 0) return "launch"
  return "exec"
}

// ----------------------------------------------------------------- parse scanner output

function parseBindings(records) {
  // Parse tab-separated records from read.lua
  // Format: b  <modmask>  <key>  <description>  <kind>  <arg>
  // Format: u  <modmask>  <key>
  var bindings = []
  var lines = String(records || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    var parts = line.split("\t")
    if (parts[0] === "b" && parts.length >= 3) {
      bindings.push({
        type: "bind",
        modmask: parseInt(parts[1]) || 0,
        key: parts[2],
        desc: parts[3] || "",
        kind: parts[4] || "",
        arg: parts[5] || "",
        command: buildCommand(parts[4] || "", parts[5] || ""),
        keys: modmaskToKeys(parseInt(parts[1]) || 0, parts[2]),
        source: "default"  // will be overridden in merge
      })
    } else if (parts[0] === "u" && parts.length >= 3) {
      bindings.push({
        type: "unbind",
        modmask: parseInt(parts[1]) || 0,
        key: parts[2],
        desc: "Disable default",
        kind: "unbind",
        arg: "",
        command: "UNBIND",
        keys: modmaskToKeys(parseInt(parts[1]) || 0, parts[2]),
        source: "custom"
      })
    }
  }
  return bindings
}

// --------------------------------------------------------- key helpers

function modmaskToKeys(modmask, key) {
  var parts = []
  // Numeric modifier flags from read.lua:
  // SHIFT=1, CTRL=4, ALT=8, SUPER=64
  if (modmask & 64) parts.push("SUPER")
  if (modmask & 8) parts.push("ALT")
  if (modmask & 4) parts.push("CTRL")
  if (modmask & 1) parts.push("SHIFT")
  parts.push(key)
  return parts.join(" + ")
}

function buildCommand(kind, arg) {
  switch (kind) {
    case "exec": return arg || ""
    case "omarchy": return arg ? "omarchy-launch-" + arg : ""
    case "webapp": return arg ? "open webapp " + arg : ""
    case "launch": return arg || ""
    case "tui": return arg ? "terminal TUI: " + arg : ""
    case "toggle": return arg || ""
    case "plugin": return arg ? "shell toggle " + arg : ""
    case "menu": return arg || ""
    case "lua": return arg || ""
    default: return arg || ""
  }
}

// -------------------------------------------------------------------- merge

// Merge default bindings (from scanner) with managed user bindings.
// User bindings with same (keys, desc) replace defaults.
// Extra user bindings are appended.
// Returns { merged, userBindings }
function mergeBindings(defaults, managedLines) {
  var userBindings = []
  for (var i = 0; i < managedLines.length; i++) {
    var parsed = parseManagedLine(managedLines[i])
    if (parsed) userBindings.push(parsed)
  }

  var userByKey = {}
  for (var i2 = 0; i2 < userBindings.length; i2++) {
    var u = userBindings[i2]
    u.source = "custom"
    // For unbinds, also track by just the keys
    if (u.type === "unbind") {
      userByKey[u.keys + "||__unbind__"] = u
    } else {
      userByKey[u.keys + "|" + u.desc] = u
    }
  }

  var merged = []
  var seen = {}
  for (var j = 0; j < defaults.length; j++) {
    var b = defaults[j]
    var key2 = b.keys + "|" + b.desc
    // Check if there's a user override for this exact keys+desc
    if (userByKey[key2]) {
      if (!seen[key2]) {
        var u2 = userByKey[key2]
        u2.source = "custom"
        merged.push(u2)
        seen[key2] = true
      }
      delete userByKey[key2]
    } else {
      // Check if this key combo is unbound by user
      var unbindKey = b.keys + "||__unbind__"
      if (userByKey[unbindKey]) {
        // Skip this default binding - it's been unbound
      } else if (!seen[key2]) {
        merged.push(b)
        seen[key2] = true
      }
    }
  }

  // Add remaining user bindings that weren't matched
  for (var k in userByKey) {
    if (!seen[k] && k.indexOf("||__unbind__") === -1) {
      userByKey[k].source = "custom"
      merged.push(userByKey[k])
      seen[k] = true
    }
  }

  // Sort: custom bindings first, then defaults
  var customs = []
  var defaults2 = []
  for (var i3 = 0; i3 < merged.length; i3++) {
    if (merged[i3].source === "custom") {
      customs.push(merged[i3])
    } else {
      defaults2.push(merged[i3])
    }
  }

  return { merged: customs.concat(defaults2), userBindings: userBindings }
}

// -------------------------------------------------------------------- desktop entries

function parseDesktopEntries(text) {
  var entries = []
  if (!text) return entries
  var blocks = String(text).split("---ENTRY---")
  for (var bi = 0; bi < blocks.length; bi++) {
    var block = blocks[bi].trim()
    if (!block) continue
    var lines = block.split("\n")
    var current = null
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.match(/^\[Desktop Entry\]/)) {
        if (current) entries.push(current)
        current = { name: "", exec: "", icon: "", categories: "", comment: "" }
      } else if (current) {
        var m = line.match(/^Name=(.+)$/)
        if (m) current.name = m[1]
        m = line.match(/^Exec=(.+)$/)
        if (m) current.exec = m[1].replace(/ %[fFuUdDnNickvm]/, "")
        m = line.match(/^Icon=(.+)$/)
        if (m) current.icon = m[1]
        m = line.match(/^Categories=(.+)$/)
        if (m) current.categories = m[1]
        m = line.match(/^Comment=(.+)$/)
        if (m) current.comment = m[1]
      }
    }
    if (current) entries.push(current)
  }
  return entries
}