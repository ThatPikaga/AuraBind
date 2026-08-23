.pragma library

// AuraBind v3.0 — managed block handler.
//
// Renders and parses the managed block inside ~/.config/hypr/bindings.lua.
// The block contains o.bind() and hl.unbind() calls that AuraBind owns.
// Whatever is outside the fences is left untouched.
//
// Action types (stored as @aurabind action=N comment before o.bind() lines):
//   0 = Open App    — command is the app exec string
//   1 = Custom Cmd  — command is a shell command
//   2 = Kill Active — command is "killactive"
//   3 = Plugin      — command is "omarchy-shell shell toggle <plugin>"
//   4 = Lua/Dsp     — command is a dispatcher/Lua expression
//   5 = Web App     — command is the webapp URL
//   6 = Unbind      — hl.unbind() line

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

// ------------------------------------------------------------- action type helpers

// Action hint comment:  -- @aurabind action=N
var ACTION_COMMENT_RE = /^\s*--\s+@aurabind\s+action=(\d+)\s*$/

function extractActionHint(line) {
  var m = line.trim().match(ACTION_COMMENT_RE)
  if (m) return parseInt(m[1])
  return -1
}

function makeActionHint(actionType) {
  return "-- @aurabind action=" + actionType
}

// ------------------------------------------------------------- detect action type from a binding

// Heuristic detection for bindings without an action hint comment.
function detectActionType(binding, installedApps) {
  if (!binding || binding.type === "unbind") return 6
  var cmd = (binding.command || "").toLowerCase()
  if (cmd === "killactive") return 2
  if (cmd.indexOf("omarchy-shell shell toggle ") === 0) return 3
  if (cmd.indexOf("hl.dsp") >= 0 || cmd.indexOf("hl.dispatch") >= 0) return 4
  if (cmd.indexOf("omarchy-launch-webapp") >= 0) return 5
  if (installedApps && installedApps.length > 0) {
    for (var i = 0; i < installedApps.length; i++) {
      if ((installedApps[i].exec || "").toLowerCase() === cmd) return 0
    }
  }
  return 1
}

// ------------------------------------------------------------- render a binding to managed-block lines

function renderBindingLine(defaults, binding, actionHint) {
  if (binding.type === "unbind") {
    return ['hl.unbind("' + esc(binding.keys) + '")']
  }
  var at = actionHint !== undefined ? actionHint : (binding.actionType !== undefined ? binding.actionType : 1)
  var cmd = renderCmd(binding, at)
  var isLua = at === 4 || (binding.kind === "lua")
  var bindLine = isLua
    ? 'o.bind("' + esc(binding.keys) + '", "' + esc(binding.desc) + '", ' + cmd + ')'
    : 'o.bind("' + esc(binding.keys) + '", "' + esc(binding.desc) + '", "' + esc(cmd) + '")'

  // If this custom binding overrides a default with the same key but different
  // description/command, prepend hl.unbind() to avoid duplicate registrations.
  if (defaults && hasDefaultForKey(binding.keys, defaults)) {
    var dup = findDefaultForKey(binding.keys, defaults)
    if (dup && (dup.desc !== binding.desc || dup.command !== cmd)) {
      return [makeActionHint(at), 'hl.unbind("' + esc(binding.keys) + '")', bindLine]
    }
  }

  if (at >= 0) {
    return [makeActionHint(at), bindLine]
  }
  return [bindLine]
}

// Check if any default binding uses the given key combo.
function hasDefaultForKey(keys, defaults) {
  if (!defaults) return false
  for (var i = 0; i < defaults.length; i++) {
    if (defaults[i].keys === keys) return true
  }
  return false
}

// Find the first default binding with the given key combo.
function findDefaultForKey(keys, defaults) {
  if (!defaults) return null
  for (var i = 0; i < defaults.length; i++) {
    if (defaults[i].keys === keys) return defaults[i]
  }
  return null
}

function renderCmd(binding, actionType) {
  switch (actionType) {
    case 0: return binding.command || binding.arg || ""
    case 1: return binding.command || ""
    case 2: return "killactive"
    case 3: return binding.command || ""
    case 4: return binding.command || ""
    case 5: return binding.command || ""
    case 6: return ""
    default: return binding.command || ""
  }
}

function esc(s) {
  return String(s || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"')
}

// ------------------------------------------------------------- parse managed block

// Parse a single managed-block line into a binding object.
// Returns null for comment/empty lines.
// Lines like "-- @aurabind action=N" are parsed as hints by the caller.
function parseManagedLine(line) {
  var s = line.trim()
  if (s === "" || s.startsWith("--")) return null

  // hl.unbind("KEYS")
  var m = s.match(/^hl\.unbind\("([^"]+)"\)$/)
  if (m) {
    return { type: "unbind", keys: m[1], desc: "Disable Default", command: "", source: "custom", actionType: 6 }
  }

  // o.bind("KEYS", "DESC", "COMMAND")
  m = s.match(/^o\.bind\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\)$/)
  if (m) {
    return { type: "bind", keys: m[1], desc: m[2] || "", command: m[3] || "", source: "custom", kind: "exec", actionType: -1 }
  }

  // o.bind("KEYS", "DESC", hl.dsp...())
  // No regex with variable-length lua code works here, try a relaxed match
  // o.bind(...) with 3 arguments where the last is NOT a plain string
  m = s.match(/^o\.bind\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(.+)\)\s*$/)
  if (m) {
    return { type: "bind", keys: m[1], desc: m[2] || "", command: m[3] || "", source: "custom", kind: "lua", actionType: -1 }
  }

  return null
}

// Parse the managed block with action hints.
// Returns an array of binding objects, each with actionType resolved.
function parseManagedBlock(body) {
  var lines = String(body || "").split("\n")
  var result = []
  var pendingHint = -1
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var hint = extractActionHint(line)
    if (hint >= 0) { pendingHint = hint; continue }
    var b = parseManagedLine(line)
    if (b) {
      if (b.actionType < 0 && pendingHint >= 0) b.actionType = pendingHint
      pendingHint = -1
      result.push(b)
    }
  }
  return result
}

// ------------------------------------------------------------- parse scanner output

function parseBindings(records) {
  var bindings = []
  var seenKeys = {}
  var lines = String(records || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    var parts = line.split("\t")
    if (parts[0] === "b" && parts.length >= 3) {
      var keys = modmaskToKeys(parseInt(parts[1]) || 0, parts[2])
      var desc = parts[3] || ""
      var dedupKey = keys + "|" + desc
      if (seenKeys[dedupKey]) continue  // skip duplicates
      seenKeys[dedupKey] = true
      bindings.push({
        type: "bind",
        modmask: parseInt(parts[1]) || 0,
        key: parts[2],
        desc: desc,
        kind: parts[4] || "",
        arg: parts[5] || "",
        command: buildCommand(parts[4] || "", parts[5] || ""),
        keys: keys,
        source: "default"
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

function mergeBindings(defaults, managedLines) {
  var userBindings = parseManagedBlock(managedLines.join("\n"))

  var userByKey = {}
  for (var i2 = 0; i2 < userBindings.length; i2++) {
    var u = userBindings[i2]
    u.source = "custom"
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
    if (userByKey[key2]) {
      if (!seen[key2]) {
        var u2 = userByKey[key2]
        // Distinguish true overrides from exact duplicates.
        // If command matches, this is just a re-statement of the default —
        // keep it as a default instead of marking it custom.
        var cmdMatch = (u2.command === b.command)
        if (cmdMatch) {
          merged.push(b)
        } else {
          u2.source = "custom"
          merged.push(u2)
        }
        seen[key2] = true
      }
      delete userByKey[key2]
    } else {
      var unbindKey = b.keys + "||__unbind__"
      if (userByKey[unbindKey]) {
        // Default binding is unbound, skip it
      } else if (!seen[key2]) {
        merged.push(b)
        seen[key2] = true
      }
    }
  }

  for (var k in userByKey) {
    if (!seen[k] && k.indexOf("||__unbind__") === -1) {
      userByKey[k].source = "custom"
      merged.push(userByKey[k])
      seen[k] = true
    }
  }

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

// ---------------------------------------------------------- hasRealBindings

function hasRealBindings(body) {
  if (!body) return false
  var lines = String(body || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (parseManagedLine(lines[i])) return true
  }
  return false
}

// ---------------------------------------------------------- render managed body

function renderManagedBody(defaults, userBindings) {
  var lines = []
  for (var i = 0; i < userBindings.length; i++) {
    var b = userBindings[i]
    var rendered = renderBindingLine(defaults, b)
    for (var j = 0; j < rendered.length; j++) {
      lines.push(rendered[j])
    }
  }
  return lines.join("\n")
}

// OBSOLETE: autoPopulateLines is no longer used.
// It wrote ALL default bindings into the managed block, creating duplicates
// with Omarchy's own default binding system. The managed block now stores
// ONLY custom user overrides.


// ---------------------------------------------------------- find disabled bindings from raw file

// Find all hl.unbind() lines from the raw file content (including outside the managed block).
// Returns an array of { keys, lineText } objects.
function findDisabledBindings(text) {
  var result = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^hl\.unbind\("([^"]+)"\)$/)
    if (m) result.push({ keys: m[1], lineText: lines[i] })
  }
  return result
}

// ---------------------------------------------------------- desktop entries

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