-- mod-version:3
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local common = require "core.common"

-- TODO: `add std directory into project` command
-- TODO: regression tests for REGEX queries


-------------------
-- Configuration --
-------------------

local include_list = {
  "**.c3",
  "**.c3i",
}
local exclude_list = {
  --"build/*",
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


-----------------------------
-- Regex builders & runner --
-----------------------------

local function regex_callable(word, kwds)
  local preprefix
  if not kwds then
    preprefix = "(fn|macro)"
  else
    preprefix = "("..table.concat(kwds, "|")..")"
  end
  return "\\b"..preprefix.."\\s+(?:[\\w[\\]*:.<>?]+\\s+)?"..word.."(?=\\()"
end

local function regex_method(struct_name, method_name, kwds)
  return regex_callable(struct_name.."."..method_name, kwds)
end

local function regex_types(word, kwds)
  local preprefix
  if not kwds then
    preprefix = "(struct|union|interface|enum|bitstruct|alias|typedef|constdef)"
  else
    preprefix = "("..table.concat(kwds, "|")..")"
  end
  return preprefix.."\\s+\\b"..word.."\\b"
end

local function regex_module(word)
  return "module .*?\\b"..word.."\\b(?!::).*;"
end

local function regex_faultdef(word)
  return "(?<!::)\\b"..word.."\\b(?=\\s*(?:@\\w+\\s*)?[,;])"
end

local function regex_const(word)
  return "\\bconst\\b[^=]*\\b"..word.."\\b(?=\\s*=)"
end

local function regex_word_space(word)
  return word.." "
end


local function run_regex_query(regex_query)
  -- open global search
  command.perform "project-search:find"

  -- get a reference to the current view
  ---@type core.view | widget
  local current_view = core.active_view
  core.add_thread(function()
    -- wait until project search becomes active active
    while not current_view.parent do
      coroutine.yield()
      current_view = core.active_view
    end
    ---@type plugins.projectsearch.resultsview
    local search_view = current_view.parent -- this holds the ref to searchview
    search_view.regex_toggle:set_toggle(true)
    search_view.sensitive_toggle:set_toggle(true)
    search_view.find_text:set_text(regex_query)

    search_view.filters_toggle:set_toggle(true)
    search_view.includes_text:set_text(table.concat(include_list, ", "))
    search_view.excludes_text:set_text(table.concat(exclude_list, ", "))

    search_view:refresh()
    -- wait until there are search results.
    while search_view.searching do coroutine.yield() end

    -- select first result
    search_view:swap_active_child()
    search_view.results_list:select_next()
    search_view.results_list:select_next()

    if search_view.results_list.total_results == 1 then
      search_view:open_selected_result()
      command.perform "project-search:find"
    end
  end)
end

---------------------------------
-- Regex builders & runner end --
---------------------------------


------------------------------------------
-- Input handling & identifier dispatch --
------------------------------------------

--[[
    ```
     kwords   | naming               | surroundings
    ----------|----------------------|----------------------------------------
     fn macro | snake_case*          |
     types    | PascalCase           |
     modules  | snake_case           | `module` at the beginning of the line
     faultdef | SCREAMING_SNAKE_CASE | `~` after the word
     const    | SCREAMING_SNAKE_CASE |
     method   | snake_case           | `.` before the word

    *fn can also be camelCased
    ```
]]
local function identify_identifier(id)
  -- Basic validity checks
  if #id > 127 then
    core.log("C3 id can't be more than 127")
    return nil
  end
  if not id:match("^[A-Za-z0-9_]+$") then
    core.log("Identifier contains invalid characters")
    return nil
  end
  if id:match("^%d") then
    core.log("Identifier can't start with the digit")
    return nil
  end

  -- Find the first non-underscore character
  local first = id:match("^_*([A-Za-z0-9])")
  -- Only underscores (or empty) -> invalid
  if not first then
    if first == "" then
      core.log("Identifier can't be empty")
    else
      core.log("Identifier can't be only of underscores lol")
    end
    return nil
  end

  -- First non-underscore cannot be a digit
  if first:match("%d") then
    core.log("First non-underscore character can't be a digit")
    return nil
  end

  -- Classify based on first character and presence of lowercase letters
  if first:match("%l") then
    -- Starts with lowercase -> variable / parameter / function / macro
    -- I'm aware that at this point we also store camelCased ids as snake_case
    -- but it's ok since extern fns can be camselCased and so we will
    -- find it because of dispatching into callable regex
    return "snake_case"
  elseif first:match("%u") then
   -- Starts with uppercase -> either type or constant
    if id:match("[a-z]") then
      -- Contains at least one lowercase -> type
      return "PascalCase"
    else
      -- No lowercase -> global constant / enum member / fault
      return "SCREAMING_SNAKE_CASE"
    end
  else
    core.log("Unknown identifier")
    return nil
  end
end

local function escape(s)
  return (s:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]','%%%1'))
end

-- TODO: Sometimes (of course) incorrectly infers method_struct_type
local function get_method_struct_and_method_struct_type(dv, res, method_pos)
  local translate = require "core.doc.translate"
  local struct_start_line, struct_start_col = translate.start_of_word(dv.doc, method_pos.line1, method_pos.col1 - 1)
  res.method_struct = dv.doc:get_text(struct_start_line, struct_start_col, method_pos.line1, method_pos.col1 - 1)
  if res.method_struct then
    local pattern = "(%u[%w]*)%s*%*?%s?"..escape(res.method_struct)
    for line = struct_start_line, 1, -1 do
      local line_text = dv.doc.lines[line]
      local matched_type = line_text:match(pattern)
      if matched_type then
        res.method_struct_type = matched_type
        break
      end
    end
  end
end

local function get_identifier_under_cursor(dv)
  ---@cast dv core.docview
  command.perform "doc:select-word"
  local res = {}
  res.word = dv.doc:get_selection_text(1)
  local naming = identify_identifier(res.word)
  if not naming then
    core.log("Failed to get identifier under cursor")
    return nil
  end
  res.naming = naming

  local line1, col1, line2, col2 = dv.doc:get_selection(true)
  local line_text = dv.doc.lines[line1]

  res.module_at_line_start = line_text:match("^%s*module ")
  res.import_at_line_start = line_text:match("^%s*import ")
  res.char_after = dv.doc:get_char(line2, col2)
  res.char_after_after = dv.doc:get_char(line2, col2+1)
  res.char_before = dv.doc:get_char(line1, col1 - 1)
  if res.char_before == "." and res.char_after == "(" then
    get_method_struct_and_method_struct_type(dv, res, {line1=line1,col1=col1,line2=line2,col2=col2})
  end
  
  return res
end

local function handle_method_search(id)
  if id.method_struct_type then
    run_regex_query(regex_method(id.method_struct_type, id.word))
    return
  end

  -- Could not infer the method obj type. Ask user for it.
  local structs_in_current_doc = {}
  local doc = core.active_view.doc
  local symbol_pattern = doc:get_symbol_pattern()
  local seen = {}
  for i = 1, #doc.lines do
    for sym in doc.lines[i]:gmatch(symbol_pattern) do
      local naming = identify_identifier(sym)
      if naming == "PascalCase" and not seen[sym] then
        table.insert(structs_in_current_doc, sym)
        seen[sym] = true
      end
    end
  end

  core.command_view:enter("Struct Name", {
    submit = function(struct_name)
      if struct_name and #struct_name > 0 then
        run_regex_query(regex_method(struct_name, id.word))
      end
    end,
    suggest = function(text)
      local matched = common.fuzzy_match(structs_in_current_doc, text)
      local res = {}
      for i, name in ipairs(matched) do
        res[i] = { text = name }
      end
      return res
    end,
  })
end

local function in_c3_file()
  local doc = core.active_view.doc
  local filename = doc:get_name()
  local extension = filename and filename:match("%.([^%.]+)$") or ""
  return table_contains({"c3", "c3i"}, extension)
end

local function find(dv)
  if not in_c3_file() then return end

  local id = get_identifier_under_cursor(dv)
  if not id then return end

  if id.naming == "PascalCase" then
    return run_regex_query(regex_types(id.word))
  end

  if id.naming == "SCREAMING_SNAKE_CASE" then
    if id.char_after == "~" then
      return run_regex_query(regex_faultdef(id.word))
    end
    return run_regex_query(regex_word_space(id.word))
  end

  if id.naming == "snake_case" then
    if id.char_before == "." then
      return handle_method_search(id)
    end
    if id.module_at_line_start or id.import_at_line_start
       or (id.char_after == ":" and id.char_after_after == ":") then
      return run_regex_query(regex_module(id.word))
    end

    return run_regex_query(regex_callable(id.word))
  end

  core.log("idk how to query for "..id.word)
end

local function find_exactly(dv)
  if not in_c3_file() then return end

  local id = get_identifier_under_cursor(dv)
  if not id then return end

  local things_i_can_find = {
    "fn", "macro", "struct", "union", "interface", "enum", "bitstruct",
    "alias", "typedef", "constdef", "module", "faultdef", "const",

    "method",
  }
  local type_things = {
    "struct", "union", "interface", "enum", "bitstruct", "alias", "typedef",
    "constdef",
  }

  core.command_view:enter("Search for", {
    submit = function(wannafind)
      if not table_contains(things_i_can_find, wannafind) then
        core.log("I don't know how to find `"..wannafind.."`")
        return
      end
      if table_contains({"fn", "macro"}, wannafind) then
        run_regex_query(regex_callable(id.word, {wannafind}))
      elseif table_contains(type_things, wannafind) then
        run_regex_query(regex_types(id.word, {wannafind}))
      elseif wannafind == "module" then
        run_regex_query(regex_module(id.word))
      elseif wannafind == "faultdef" then
        run_regex_query(regex_faultdef(id.word))
      elseif wannafind == "const" then
        run_regex_query(regex_const(id.word))
      elseif wannafind == "method" then
        handle_method_search(id)
      else
        core.log("How did I end up like this?")
      end
    end,
    suggest = function(text)
      local matched = common.fuzzy_match(things_i_can_find, text)
      local res = {}
      for i, name in ipairs(matched) do
        res[i] = { text = name }
      end
      return res
    end,
    validate = function(text)
      return table_contains(things_i_can_find, text)
    end
  })
end

command.add("core.docview", {
  ["c3:find"] = find,
  ["c3:find_exactly"] = find_exactly,
})

keymap.add {
  ["f12"] = "c3:find",
  ["alt+f12"] = "c3:find_exactly",
}

----------------------------------------------
-- Input handling & identifier dispatch end --
----------------------------------------------
