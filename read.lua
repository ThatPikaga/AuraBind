-- AuraBind binding scanner.
--
-- Loads the user's bindings.lua and every Omarchy default binding file against
-- recording stubs, then prints one tab-separated record per binding to stdout.
--
-- Usage:
--   lua /path/to/read.lua [-e <lua-body>] [<file> ...]
--
--   If -e <lua-body> is given, runs that Lua code then the files.
--   If a file argument is given, dofiles it.
--   Otherwise loads the user's full bindings.lua + Omarchy defaults.
--
-- Output format (tab-separated):
--   b  <modmask>  <key>  <description>  <kind>  <arg>
--   u  <modmask>  <key>  (for unbinds/hl.unbind)
--
-- Kind is one of: exec, lua, omarchy, webapp, launch, tui, toggle, plugin, menu
-- Arg is the dispatcher argument (command, URL, Lua expression, etc.)

-- Modifier constants
local SHIFT, CTRL, ALT, SUPER = 1, 4, 8, 64

local MODIFIERS = {
  SHIFT = 1, CTRL = 4, CONTROL = 4, ALT = 8, SUPER = 64,
  CAPS = 2, MOD2 = 16, MOD3 = 32, MOD5 = 128
}

local function parse_modmask(mod_text)
  local mask = 0
  for part in mod_text:gmatch("[^+]+") do
    local trimmed = part:match("^%s*(.-)%s*$")
    local value = MODIFIERS[trimmed:upper()]
    if value then mask = mask + value end
  end
  return mask
end

local function detect_kind(arg, desc)
  if arg == nil or arg == "" then return "", "" end
  if type(arg) == "string" then
    if arg:match("^omarchy%-launch%-") then
      return "omarchy", arg:match("^omarchy%-launch%-(.+)$") or arg
    end
    if arg:match("^omarchy%-toggle%-") then
      return "toggle", arg
    end
    if arg:match("^omarchy%-shell shell toggle ") then
      return "plugin", arg:match("^omarchy%-shell shell toggle (.+)$") or arg
    end
    if arg:match("^uwsm%-app") then
      return "launch", arg:match("uwsm%-app %-%- (.+)") or arg
    end
    if arg:match("^omarchy%-menu") then
      return "menu", arg
    end
    if arg:match("^hl%.dsp%.") or arg:match("^hl%.dispatch") then
      return "lua", arg
    end
    return "exec", arg
  end
  if type(arg) == "table" then
    if arg.omarchy then return "omarchy", arg.omarchy end
    if arg.webapp then return "webapp", arg.webapp end
    if arg.launch then return "launch", arg.launch end
    if arg.tui then return "tui", arg.tui end
    return "", ""
  end
  return "", tostring(arg)
end

-- Build a stubbed environment that records every o.bind / hl.bind / hl.unbind
local function make_stub_env(bindings)
  local noop = setmetatable({}, {
    __index = function() return noop end,
    __call = function() return noop end,
  })

  local function split_keys(keys)
    local modmask = 0
    local key = ""
    for part in string.gmatch(tostring(keys or ""), "[^+]+") do
      local trimmed = part:match("^%s*(.-)%s*$") or part
      local modifier = MODIFIERS[trimmed:upper()]
      if modifier then
        modmask = modmask + modifier
      elseif trimmed ~= "" then
        key = trimmed
      end
    end
    return modmask, key
  end

  local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
  end

  -- The dsp proxy — same pattern as omarchy-menu-keybindings
  local function dsp_proxy(path)
    return setmetatable({ path = path }, {
      __index = function(self, key)
        if key == "exec_cmd" then
          return function(cmd)
            return { __omarchy_dispatcher = true, kind = "exec", arg = cmd }
          end
        end
        return dsp_proxy(self.path .. "." .. tostring(key))
      end,
      __call = function(self, ...)
        local parts = {}
        for i = 1, select("#", ...) do
          parts[i] = tostring(select(i, ...))
        end
        return { __omarchy_dispatcher = true, kind = "lua", arg = self.path .. "(" .. table.concat(parts, ", ") .. ")" }
      end,
    })
  end

  local env = {
    _G = _G,
    o = {},
    hl = {
      bind = function(keys, dispatcher, opts)
        opts = opts or {}
        local modmask, key = split_keys(keys)

        -- Resolve dispatcher to kind+arg
        local kind, arg
        if type(dispatcher) == "table" and dispatcher.__omarchy_dispatcher then
          kind = dispatcher.kind or "lua"
          arg = dispatcher.arg or ""
        elseif type(dispatcher) == "string" then
          kind, arg = detect_kind(dispatcher, opts.description)
        else
          kind, arg = detect_kind(dispatcher, opts.description)
        end

        table.insert(bindings, {
          type = "bind", modmask = modmask, key = key,
          description = opts.description or "",
          kind = kind, arg = arg,
        })
        return noop
      end,

      unbind = function(keys)
        local modmask, key = split_keys(keys)
        table.insert(bindings, {
          type = "unbind", modmask = modmask, key = key,
          description = "", kind = "", arg = "",
        })
        return noop
      end,

      dsp = dsp_proxy("hl.dsp"),

      timer = noop,
      on = noop,
      get_config = function() return nil end,
      config = noop,
      animation = noop,
      window_rule = noop,
      exec_cmd = noop,
      get_active_window = function() return nil end,
    },
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    print = print,
    select = select,
    pcall = pcall,
    error = error,
    assert = assert,
    unpack = unpack or table.unpack,
    rawget = rawget,
    rawset = rawset,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    next = next,
    string = string,
    table = table,
    math = math,
    os = os,
    io = io,
    ipairs = ipairs,
    pairs = pairs,
  }

  setmetatable(env, { __index = _G })

  -- o.bind — mirrors the real helpers.lua o.bind
  function env.o.bind(keys, description, dispatcher, options)
    if type(dispatcher) == "table" and dispatcher.__omarchy_dispatcher then
      local modmask, key = split_keys(keys)
      table.insert(bindings, {
        type = "bind", modmask = modmask, key = key,
        description = description or "",
        kind = dispatcher.kind or "lua",
        arg = dispatcher.arg or "",
      })
      return
    end

    local opts = options or {}
    if description then opts.description = description end

    -- Translate table argument (same as helpers.lua command_from)
    if type(dispatcher) == "table" then
      if dispatcher.omarchy then
        dispatcher = "omarchy-launch-" .. dispatcher.omarchy
      elseif dispatcher.webapp then
        if dispatcher.focus then
          dispatcher = "omarchy-launch-or-focus-webapp " .. shell_quote(description or "") .. " " .. shell_quote(dispatcher.webapp)
        else
          dispatcher = "omarchy-launch-webapp " .. shell_quote(dispatcher.webapp)
        end
      elseif dispatcher.launch then
        if dispatcher.focus then
          dispatcher = "omarchy-launch-or-focus " .. shell_quote(dispatcher.focus) .. " " .. shell_quote("uwsm-app -- " .. dispatcher.launch)
        else
          dispatcher = "uwsm-app -- " .. dispatcher.launch
        end
      elseif dispatcher.tui then
        if dispatcher.focus then
          dispatcher = "omarchy-launch-or-focus-tui " .. shell_quote(dispatcher.tui)
        else
          dispatcher = "omarchy-launch-tui " .. shell_quote(dispatcher.tui)
        end
      end
    end

    if type(dispatcher) == "string" then
      dispatcher = { __omarchy_dispatcher = true, kind = "exec", arg = dispatcher }
    end

    if type(dispatcher) == "table" and dispatcher.__omarchy_dispatcher then
      local modmask, key = split_keys(keys)
      table.insert(bindings, {
        type = "bind", modmask = modmask, key = key,
        description = opts.description or "",
        kind = dispatcher.kind or "lua",
        arg = dispatcher.arg or "",
      })
    end
  end

  function env.o.bind_toggle(keys, description, toggle, options)
    env.o.bind(keys, description, "omarchy-toggle-" .. toggle, options)
  end

  function env.o.cmd_present(command) return true end
  function env.o.cmd_missing(command) return false end
  function env.o.shell_succeeds(command) return true end
  function env.o.preinstalled_bindings_enabled() return true end

  function env.o.launch(command)
    return "uwsm-app -- " .. command
  end

  function env.o.launch_webapp(url)
    return "omarchy-launch-webapp " .. shell_quote(url)
  end

  function env.o.launch_webapp_sole(name, url)
    return "omarchy-launch-or-focus-webapp " .. shell_quote(name) .. " " .. shell_quote(url)
  end

  function env.o.launch_sole(match, command)
    return "omarchy-launch-or-focus " .. shell_quote(match) .. " " .. shell_quote("uwsm-app -- " .. command)
  end

  return env
end

-- Run a file or Lua code in the stubbed environment
local function run_code(env, source, name)
  local fn, err
  if source:match("%.lua$") then
    fn, err = loadfile(source, "t", env)
  else
    fn, err = load(source, name or "explicit", "t", env)
  end
  if not fn then
    io.stderr:write("AuraBind read.lua: " .. tostring(err) .. "\n")
    return false
  end
  local ok, perr = pcall(fn)
  if not ok then
    io.stderr:write("AuraBind read.lua: error: " .. tostring(perr) .. "\n")
    return false
  end
  return true
end

-- Main
local bindings = {}
local env = make_stub_env(bindings)
local loaded_user = false
local args = { ... }

-- Parse -e <code> arguments
local i = 1
while i <= #args do
  if args[i] == "-e" and i < #args then
    run_code(env, args[i + 1], "explicit")
    loaded_user = true
    i = i + 2
  else
    break
  end
end

-- Load explicit file arguments
for j = i, #args do
  run_code(env, args[j])
  loaded_user = true
end

-- If nothing explicit, load user config + defaults
if not loaded_user then
  local home = os.getenv("HOME") or ""
  local userConfig = home .. "/.config/hypr/bindings.lua"
  local file = io.open(userConfig, "r")
  if file then
    file:close()
    run_code(env, userConfig)
  end
end

-- Always load Omarchy default binding files
local omarchyPath = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
local defaultBindDir = omarchyPath .. "/default/hypr/bindings"
local dir = io.popen("ls " .. defaultBindDir .. "/*.lua 2>/dev/null", "r")
if dir then
  for line in dir:lines() do
    local fp = line:match("^%s*(.-)%s*$")
    if fp then run_code(env, fp) end
  end
  dir:close()
end

-- Note: The main bindings.lua uses require() which doesn't work in our
-- stub environment. Since we already load all individual *.lua files from
-- the bindings/ directory directly, we have all the bindings.

-- Print results: tab-separated records
for _, binding in ipairs(bindings) do
  if binding.type == "bind" then
    io.write("b\t" .. binding.modmask .. "\t" .. binding.key .. "\t" .. binding.description .. "\t" .. binding.kind .. "\t" .. binding.arg .. "\n")
  elseif binding.type == "unbind" then
    io.write("u\t" .. binding.modmask .. "\t" .. binding.key .. "\n")
  end
end