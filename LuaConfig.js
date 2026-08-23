.pragma library

// AuraBind managed block handler.
//
// Renders and parses the managed block inside ~/.config/hypr/bindings.lua.
// The block contains o.bind() and hl.unbind() calls that AuraBind owns.
// Whatever is outside the fences is left untouched.

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

function renderBody(bindings) {
  var lines = []
  for (var i = 0; i < bindings.length; i++) {
    var b = bindings[i]
    if (b.type === "bind") {
      var keys = b.keys.replace(/"/g, '\\"')
      var desc = b.desc.replace(/"/g, '\\"')
      var cmd = b.command.replace(/"/g, '\\"')
      lines.push('o.bind("' + keys + '", "' + desc + '", "' + cmd + '")')
    } else if (b.type === "unbind") {
      lines.push('hl.unbind("' + b.keys + '")')
    }
  }
  return lines.join("\n")
}

// ---------------------------------------------------------------- parse

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
        // We reconstruct the human-readable key string from modmask + key
        modmask: parseInt(parts[1]) || 0,
        key: parts[2],
        desc: parts[3] || "",
        kind: parts[4] || "",
        arg: parts[5] || "",
        command: buildCommand(parts[4] || "", parts[5] || ""),
        keys: modmaskToKeys(parseInt(parts[1]) || 0, parts[2]),
        source: "default"  // will be overridden
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
  // Deduplicate by (keys, desc) — user overrides take priority
  var seen = {}
  var deduped = []
  for (var j = bindings.length - 1; j >= 0; j--) {
    var b2 = bindings[j]
    var key = b2.keys + "|" + b2.desc
    if (!seen[key]) {
      seen[key] = true
      b2.source = b2.source || "default"
      deduped.unshift(b2)
    }
  }
  return deduped
}

// --------------------------------------------------------- key helpers

function modmaskToKeys(modmask, key) {
  var parts = []
  if (modmask & 64) parts.push("SUPER")
  if (modmask & 4) parts.push("CTRL")
  if (modmask & 8) parts.push("ALT")
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

// -------------------------------------------------------------------- desktop entries

function parseDesktopEntries(text) {
  // Parse .desktop file entries, separated by ---ENTRY--- markers
  var entries = []
  if (!text) return entries
  // Split by entry markers
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