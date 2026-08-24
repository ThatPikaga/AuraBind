.pragma library
// AuraBind v3.0 — binding manager. NON-EXECUTING PARSER.

var BEGIN_FENCE = "-- >>> aurabind managed keybindings block >>>"
var END_FENCE = "-- <<< aurabind managed keybindings block <<<"

function splitBlock(text) {
  var source = String(text || "")
  var begin = source.indexOf(BEGIN_FENCE)
  if (begin === -1) return { found: false, before: source, body: "", after: "" }
  var endFence = source.indexOf(END_FENCE, begin)
  if (endFence === -1) return { found: false, before: source, body: "", after: "" }
  return { found: true, before: source.substring(0, begin), body: source.substring(begin + BEGIN_FENCE.length, endFence), after: source.substring(endFence + END_FENCE.length) }
}

function applyBlock(text, body) {
  var split = splitBlock(text)
  if (!body) { if (!split.found) return String(text || ""); var joined = split.before.replace(/\n+$/, "\n") + split.after.replace(/^\n+/, ""); return joined.replace(/\n{3,}$/, "\n") }
  var block = renderBlock(body)
  if (split.found) return split.before + block + split.after
  var head = String(text || "")
  if (head.length > 0 && head[head.length - 1] !== "\n") head += "\n"
  return head + "\n" + block + "\n"
}

function renderBlock(body) {
  var header = BEGIN_FENCE + "\n" + "-- Written by AuraBind. Safe to hand-edit: the app re-reads this block\n" + "-- every time it opens, and only ever rewrites what's between the fences.\n"
  if (!body) return header + END_FENCE
  return header + body + "\n" + END_FENCE
}

var ACTION_COMMENT_RE = /^\s*--\s+@aurabind\s+action=(\d+)\s*$/

function extractActionHint(line) { var m = line.trim().match(ACTION_COMMENT_RE); if (m) return parseInt(m[1]); return -1 }
function makeActionHint(at) { return "-- @aurabind action=" + at }

function detectActionType(binding) {
  if (!binding || binding.type === "unbind") return 4
  var cmd = (binding.command || "").toLowerCase()
  if (cmd === "killactive") return 1
  if (cmd.indexOf("hl.dsp") >= 0 || cmd.indexOf("hl.dispatch") >= 0) return 2
  if (cmd.indexOf("omarchy-launch-webapp") >= 0) return 3
  return 0
}

function esc(s) { return String(s || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"') }

function renderCmd(b, at) {
  switch(at) {
    case 0: return b.command||""
    case 1: return "killactive"
    case 2: return b.command||""
    case 3: return b.command||""
    case 4: return ""
    default: return b.command||""
  }
}

function hasDefaultForKey(keys, d) { if (!d) return false; for (var i=0;i<d.length;i++) { if (d[i].keys===keys) return true } return false }
function findDefaultForKey(keys, d) { if (!d) return null; for (var i=0;i<d.length;i++) { if (d[i].keys===keys) return d[i] } return null }

function renderBindingLine(defaults, binding, ah) {
  if (binding.type === "unbind") return ['hl.unbind("' + esc(binding.keys) + '")']
  var at = ah !== undefined ? ah : (binding.actionType !== undefined ? binding.actionType : 0)
  var c = renderCmd(binding, at)
  var isLua = at === 2 || binding.kind === "lua"
  var bl = isLua ? 'o.bind("'+esc(binding.keys)+'","'+esc(binding.desc)+'",'+c+')' : 'o.bind("'+esc(binding.keys)+'","'+esc(binding.desc)+'","'+esc(c)+'")'
  if (defaults && hasDefaultForKey(binding.keys, defaults)) { var dup = findDefaultForKey(binding.keys, defaults); if (dup && (dup.desc !== binding.desc || dup.command !== c)) { return [makeActionHint(at),'hl.unbind("'+esc(binding.keys)+'")',bl] } }
  if (at >= 0) return [makeActionHint(at), bl]
  return [bl]
}

function parseManagedLine(line) {
  var s = line.trim()
  if (s === "" || s.startsWith("--")) return null
  var m = s.match(/^hl\.unbind\("([^"]+)"\)$/)
  if (m) return { type:"unbind", keys:m[1], desc:"Disable Default", command:"", source:"custom", actionType:4 }
  m = s.match(/^o\.bind\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\)$/)
  if (m) return { type:"bind", keys:m[1], desc:m[2]||"", command:m[3]||"", source:"custom", kind:"exec", actionType:-1 }
  m = s.match(/^o\.bind\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(.+)\)\s*$/)
  if (m) return { type:"bind", keys:m[1], desc:m[2]||"", command:m[3]||"", source:"custom", kind:"lua", actionType:-1 }
  return null
}

function parseManagedBlock(body) {
  var lines = String(body || "").split("\n")
  var result = []
  var pendingHint = -1
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var hint = extractActionHint(line)
    if (hint >= 0) { pendingHint = hint; continue }
    var b = parseManagedLine(line)
    if (b) { if (b.actionType < 0 && pendingHint >= 0) b.actionType = pendingHint; pendingHint = -1; result.push(b) }
  }
  return result
}

// ============= NON-EXECUTING LUA BINDING PARSER =============

function parseLuaSourceForBindings(text, sk) {
  var bindings = []
  if (!text) return bindings
  var clean = cleanLua(text)
  var re = /hl\.unbind\s*\(\s*"([^"]+)"\s*\)/g, m
  while ((m = re.exec(clean)) !== null) {
    var k = normKey(m[1]); if (!exists(bindings,k,"unbind")) bindings.push({type:"unbind",keys:k,desc:"Disable default",command:"",kind:"unbind",arg:"",source:sk||"default"})
  }
  bindings = bindings.concat(parseCalls(clean, sk))
  return bindings
}

function exists(list, keys, type) { for (var i=0;i<list.length;i++) { if (list[i].keys===keys && list[i].type===type) return true } return false }

function cleanLua(t) {
  var s=String(t||"")
  // Remove block comments --[[ ... ]]
  s=s.replace(/--\[\[[\s\S]*?\]\]/g,"")
  // Remove multi-line literal strings [[ ... ]]
  s=s.replace(/\[\[[\s\S]*?\]\]/g,function(m){return m.replace(/[^\n]/g," ")})
  // Remove line comments -- that are NOT inside string literals.
  // Walk the string char-by-char tracking string state.
  var result = ""
  var inStr = false, strChar = ""
  var i = 0
  while (i < s.length) {
    if (inStr) {
      if (s[i] === "\\") { result += s[i] + (s[i+1]||""); i += 2; continue }
      if (s[i] === strChar) inStr = false
      result += s[i]; i++
    } else {
      // Check for comment start
      if (s[i] === '-' && s[i+1] === '-') {
        // Skip to end of line
        while (i < s.length && s[i] !== '\n') i++
        // Add the newline back (to preserve line numbers)
        if (i < s.length && s[i] === '\n') { result += '\n'; i++ }
        continue
      }
      if (s[i] === '"' || s[i] === "'") { inStr = true; strChar = s[i] }
      result += s[i]; i++
    }
  }
  return result
}

function normKey(r) { if (!r) return ""; var p=r.split("+"),n=[]; for(var i=0;i<p.length;i++){var v=p[i].trim();if(v)n.push(v)} return n.join(" + ") }
function sw(s,p){while(p<s.length&&/\s/.test(s[p]))p++;return p}

function es(s,p){
  if(p>=s.length)return null;var c=s[p]
  if(c!=='"'&&c!=="'")return null
  var v="",i=p+1
  while(i<s.length&&s[i]!==c){if(s[i]==="\\"){v+=s[i+1]||"";i+=2}else{v+=s[i];i++}}
  if(i>=s.length)return null; return{value:v,endPos:i+1}
}

function et(s,p){
  if(p>=s.length||s[p]!=="{")return null
  var d=1,i=p+1,_i=false,sc=""
  while(i<s.length&&d>0){
    if(_i){if(s[i]==="\\"){i+=2;continue}if(s[i]===sc)_i=false}
    if(s[i]==='"'||s[i]==="'"){_i=true;sc=s[i]}
    else if(s[i]==="{")d++
    else if(s[i]==="}")d--
    i++
  }
  if(d!==0)return null; return{value:s.substring(p,i),endPos:i}
}

function ed(s,p){
  if(p>=s.length)return null; var i=p
  while(i<s.length&&(/\w/.test(s[i])||s[i]==="."))i++
  if(i>=s.length||s[i]!=="(")return null
  var n=s.substring(p,i)
  if(n.indexOf("hl.dsp")!==0&&n.indexOf("hl.dispatch")!==0)return null
  var d=1,j=i+1,_i=false,sc=""
  while(j<s.length&&d>0){
    if(_i){if(s[j]==="\\"){j+=2;continue}if(s[j]===sc)_i=false}
    if(s[j]==='"'||s[j]==="'"){_i=true;sc=s[j]}
    else if(s[j]==="(")d++
    else if(s[j]===")")d--
    j++
  }
  if(d!==0)return null; return{value:s.substring(p,j),endPos:j}
}

function parseTableDisp(txt) {
  var inner = txt.replace(/^\s*\{\s*/, "").replace(/\s*\}\s*$/, "")
  if (!inner) return ""
  var t = {}, pairs = inner.split(",")
  for (var i = 0; i < pairs.length; i++) {
    var p = pairs[i].trim(); var eq = p.indexOf("="); if (eq < 0) continue
    var k = p.substring(0, eq).trim(); var v = p.substring(eq + 1).trim()
    if ((v.indexOf('"')===0||v.indexOf("'")===0) && v.length>=2) v = v.substring(1,v.length-1)
    t[k] = v
  }
  if (t.omarchy) return "omarchy-launch-" + t.omarchy
  if (t.webapp) return "omarchy-launch-webapp " + (t.webapp ? "'" + t.webapp + "'" : "")
  if (t.launch) return "uwsm-app -- " + t.launch
  if (t.tui) return "omarchy-launch-tui " + t.tui
  return ""
}

function parseCalls(source, sk) {
  var results = []
  var re = /(?:o\.bind_toggle|o\.bind|hl\.bind)\s*\(/g, match
  while ((match = re.exec(source)) !== null) {
    var pos = match.index + match[0].length; pos = sw(source, pos)
    var a1 = es(source, pos); if (!a1) continue
    pos = sw(source, a1.endPos); if (pos>=source.length||source[pos]!==",") continue; pos = sw(source, pos+1)
    var a2 = null; var peek = sw(source, pos)
    if (peek < source.length && (source[peek]==='"'||source[peek]==="'")) { a2 = es(source,pos); if(a2){pos=sw(source,a2.endPos);if(pos<source.length&&source[pos]===",")pos=sw(source,pos+1)} }
    else if (peek < source.length && source.substring(peek,peek+3)==="nil") { a2={value:"",endPos:peek+3}; pos=sw(source,peek+3); if(pos<source.length&&source[pos]===",")pos=sw(source,pos+1) }
    else if (peek < source.length && source[peek]==="{") { a2={value:"",endPos:pos}; pos=peek }
    var isTog = match[0].indexOf("bind_toggle") >= 0; var disp = null
    if (pos < source.length) {
      var ds = es(source,pos); var dt = et(source,pos); var dc = ed(source,pos)
      if (ds) { disp={type:"string",value:ds.value}; pos=ds.endPos }
      else if (dt) { disp={type:"table",value:dt.value}; pos=dt.endPos }
      else if (dc) { disp={type:"lua",value:dc.value}; pos=dc.endPos }
    }
    if (!disp) continue
    var keys = normKey(a1.value); var desc = a2?a2.value:""
    if (isTog && disp.type==="string") results.push({type:"bind",keys:keys,desc:desc,command:"omarchy-toggle-"+disp.value,kind:"exec",arg:"omarchy-toggle-"+disp.value,source:sk||"default"})
    else if (disp.type==="string") results.push({type:"bind",keys:keys,desc:desc,command:disp.value,kind:"exec",arg:disp.value,source:sk||"default"})
    else if (disp.type==="table") results.push({type:"bind",keys:keys,desc:desc,command:parseTableDisp(disp.value),kind:"exec",arg:disp.value,source:sk||"default"})
    else if (disp.type==="lua") results.push({type:"bind",keys:keys,desc:desc,command:disp.value,kind:"lua",arg:disp.value,source:sk||"default"})
  }
  return results
}

// ------------------------------------------------------------- merge

function mergeBindings(defaults, managedLines) {
  var userBindings = parseManagedBlock(managedLines.join("\n"))
  var userByKey = {}
  for (var i2 = 0; i2 < userBindings.length; i2++) {
    var u = userBindings[i2]; u.source = "custom"
    if (u.type === "unbind") userByKey[u.keys + "||__unbind__"] = u
    else userByKey[u.keys + "|" + u.desc] = u
  }
  var merged = [], seen = {}
  for (var j = 0; j < defaults.length; j++) {
    var b = defaults[j], key2 = b.keys + "|" + b.desc
    if (userByKey[key2]) {
      if (!seen[key2]) {
        var u2 = userByKey[key2]
        merged.push((u2.command === b.command) ? b : (u2.source="custom", u2))
        seen[key2] = true
      }
      delete userByKey[key2]
    } else {
      var unbindKey = b.keys + "||__unbind__"
      if (!userByKey[unbindKey] && !seen[key2]) { merged.push(b); seen[key2] = true }
    }
  }
  for (var k in userByKey) { if (!seen[k] && k.indexOf("||__unbind__")===-1) { userByKey[k].source="custom"; merged.push(userByKey[k]); seen[k]=true } }
  var cst=[],def2=[]
  for (var i3=0;i3<merged.length;i3++){if(merged[i3].source==="custom")cst.push(merged[i3]);else def2.push(merged[i3])}
  return {merged:cst.concat(def2), userBindings:userBindings}
}

function hasRealBindings(body) { if(!body)return false;var l=String(body||"").split("\n");for(var i=0;i<l.length;i++){if(parseManagedLine(l[i]))return true}return false }

function renderManagedBody(defaults, userBindings) {
  var lines = []
  for (var i = 0; i < userBindings.length; i++) {
    var b = userBindings[i]
    var rendered = renderBindingLine(defaults, b)
    for (var j = 0; j < rendered.length; j++) lines.push(rendered[j])
  }
  return lines.join("\n")
}

function findDisabledBindings(text) {
  var result = [], lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^hl\.unbind\("([^"]+)"\)$/)
    if (m) result.push({ keys: m[1], lineText: lines[i] })
  }
  return result
}
