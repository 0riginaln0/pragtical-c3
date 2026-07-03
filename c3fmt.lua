-- mod-version:3
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local common = require "core.common"


-------------------
-- Configuration --
-------------------

local C3FMT_PATH
if PLATFORM == "Windows" then C3FMT_PATH = "C:\\PLEASE\\PROVIDE\\PATH\\FOR\\c3fmt.exe"
else                          C3FMT_PATH = "/home/PLEASE/PROVIDE/PATH/FOR/c3fmt" end

local C3FMT_CONFIG = {
  use_tabs = false,
  tab_size = 2,
  indent_width = 2,
  max_blank_line_between_statements = 2,
  max_line_length = 120,
  brace_style = "K&R", -- ALLMAN or K&R.
  else_on_newline = false,
  align_assignments = false,
  align_comments = true,
}

-----------------------
-- Configuration end --
-----------------------


-----------------------
-- Utility functions --
-----------------------

local function table_contains(t, element)
  for _, value in pairs(t) do
    if value == element then
      return true
    end
  end
  return false
end

---------------------------
-- Utility functions end --
---------------------------


---------------
-- Constants --
---------------

local TMP_CONFIG_PATH = USERDIR .. "/style.c3fmt"

local function config_to_string(config)
  local order = {
    "use_tabs",
    "tab_size",
    "indent_width",
    "max_blank_line_between_statements",
    "max_line_length",
    "brace_style",
    "else_on_newline",
    "align_assignments",
    "align_comments",
  }
  local lines = {}
  for i, key in ipairs(order) do
    lines[#lines + 1] = string.format("%s: %s", key, tostring(config[key]))
  end
  return table.concat(lines, "\n")
end


local function generate_config()
  local config_string = config_to_string(C3FMT_CONFIG)
  local fp, err = io.open(TMP_CONFIG_PATH, "w")
  if not fp then
    core.error("Failed to write c3fmt config file: "..err)
    return false
  end
  fp:write(config_string)
  fp:close()
  return true
end

---Sometimes the autoreload plugin doesn't detect the file change, so we
---need our own reload_doc function to reload document after formatting it.
---@param doc core.doc
local function reload_doc(doc)
  local fp = io.open(doc.abs_filename, "r")
  if not fp then
    core.error("Could not open '%s' for formatting", doc.filename)
    return
  end
  local text = fp:read("*a")
  fp:close()

  -- TODO: check text has changed

  local sel = {doc:get_selection()}
  doc:remove(1, 1, math.huge, math.huge)
  doc:insert(1, 1, text:gsub("\r", ""):gsub("\n$", ""))
  doc:set_selection(table.unpack(sel))

  -- prevent autoreload from kicking in to keep undo history
  doc.skip_format = true
  doc:save()
end

local function save_format_and_reload(doc, do_after)
  core.add_thread(function()
    -- cause stale coroutine to stop after reload
    -- and therefore not fail because of cache invalidation
    -- (happens on format_selection)
    -- related discussion https://deepwiki.com/search/in-my-plugin-i-do-lua-for-line_77b71641-3e41-4975-a0d1-965ea04c2df9
    doc.highlighter.max_wanted_line = 0
    doc.skip_format = true
    doc:save()

    -- local cmd = string.format("%s %q --config=%q --in-place", C3FMT_PATH, doc.abs_filename, TMP_CONFIG_PATH)
    local p, errmsg = process.start({
      C3FMT_PATH,
      doc.abs_filename,
      "--config="..TMP_CONFIG_PATH,
      "--in-place"
    })

    if not p then
      core.error("could not execute formatter '%s'\n%s", "c3c", errmsg)
      return
    end

    while not p:wait(0) do coroutine.yield() end

    reload_doc(doc)

    if do_after then do_after(); reload_doc(doc) end
  end)
end

local function in_c3_file()
  local doc = core.active_view.doc
  local filename = doc:get_name()
  local extension = filename and filename:match("%.([^%.]+)$") or ""
  return table_contains({"c3", "c3i"}, extension)
end

local function format()
  if not in_c3_file() then return end

  local doc = core.active_view.doc
  if not doc.filename then
    core.error("Cannot format unsaved document")
    return
  end

  if not generate_config() then return end

  save_format_and_reload(doc)
end

local function format_selection()
  if not in_c3_file() then return end

  local doc = core.active_view.doc
  if not doc.filename then
    core.error("Cannot format unsaved document")
    return
  end

  local line1, c1, line2, c2 = doc:get_selection()
  if line1 == line2 and c1 == c2 then
    core.error("No selection to format")
    return
  end
  if line1 > line2 then
    local temp_line, temp_c = line1, c1
    line1, c1 = line2, c2
    line2, c2 = temp_line, temp_c
  end

  local line2_last_col = #doc.lines[line2]

  if not generate_config() then return end

  local C3FMT_OFF = "// c3fmt off "
  local C3FMT_ON = "// c3fmt on "
  local BULDYGA_ON_TOP = "BULDYGA ON TOP"
  local BULDYGA_BEFORE_SELECTION = "BULDYGA BEFORE SELECTION"
  local BULDYGA_AFTER_SELECTION = "BULDYGA AFTER SELECTION"


  doc:insert(1, 1, C3FMT_OFF..BULDYGA_ON_TOP.."\n")
  line1 = line1 + 1; line2 = line2 + 1

  doc:insert(line1, 1, C3FMT_ON..BULDYGA_BEFORE_SELECTION.."\n")
  line2 = line2 + 1
  doc:insert(line2, line2_last_col, "\n"..C3FMT_OFF..BULDYGA_AFTER_SELECTION)

  save_format_and_reload(doc, (function()
    local lines_to_remove = {}
    for i = #doc.lines, 1, -1 do
      local line_text = doc.lines[i]:sub(1, -2) -- remove trailing newline
      if line_text:find(BULDYGA_ON_TOP) or
        line_text:find(BULDYGA_BEFORE_SELECTION) or
        line_text:find(BULDYGA_AFTER_SELECTION) then
        table.insert(lines_to_remove, i)
      end
    end

    for _, line_num in ipairs(lines_to_remove) do
      doc:remove(line_num, 1, line_num + 1, 1)
    end
    doc.skip_format = true
    doc:save()
  end))
end


command.add("core.docview", {
  ["c3:format"] = format,
  ["c3:format_selection"] = format_selection,
})

