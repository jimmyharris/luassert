local s = require 'say'
local astate = require 'luassert.state'
local obj   -- the returned module table

-- list of namespaces
local namespace = {}

local errorlevel = function()
  -- find the first level, not defined in the same file as this
  -- code file to properly report the error
  local level = 1
  local info = debug.getinfo(level)
  local thisfile = (info or {}).source
  while thisfile and thisfile == (info or {}).source do
    level = level + 1
    info = debug.getinfo(level)
  end
  if level > 1 then level = level - 1 end -- deduct call to errorlevel() itself
  return level
end

local function extract_keys(tokens)
  -- find valid keys by coalescing tokens as needed, starting from the end
  local keys = {}
  local key = nil
  for i = #tokens, 1, -1 do
    local token = tokens[i]
    key = key and (token .. '_' .. key) or token
    if namespace.modifier[key] or namespace.assertion[key] then
      table.insert(keys, 1, key)
      key = nil
    end
  end

  -- if there's anything left we didn't recognize it
  if key then
    error("luassert: unknown modifier/assertion: '" .. key .."'", errorlevel())
  end

  return keys
end

local __state_meta = {

  __call = function(self, ...)
    local keys = extract_keys(self.tokens)

    local assertion

    for _, key in ipairs(keys) do
      assertion = namespace.assertion[key] or assertion
    end

    if assertion then
      for _, key in ipairs(keys) do
        if namespace.modifier[key] then
          namespace.modifier[key].callback(self)
        end
      end

      local arguments = {...}
      arguments.n = select('#', ...) -- add argument count for trailing nils
      local val = assertion.callback(self, arguments)

      if not val == self.mod then
        local message = self.mod and assertion.positive_message or assertion.negative_message
        error(s(message, obj:format(arguments)) or "assertion failed!", errorlevel())
      end
    else
      self.payload = ...
    end

    return self
  end,

  __index = function(self, key)
    for token in key:lower():gmatch('[^_]+') do
      table.insert(self.tokens, token)
    end

    return self
  end
}

obj = {
  state = function() return setmetatable({mod=true, tokens={}}, __state_meta) end,

  -- registers a function in namespace
  register = function(self, nspace, name, callback, positive_message, negative_message)
    -- register
    local lowername = name:lower()
    if not namespace[nspace] then
      namespace[nspace] = {}
    end
    namespace[nspace][lowername] = {
      callback = callback,
      name = lowername,
      positive_message=positive_message,
      negative_message=negative_message
    }
  end,

  -- registers a formatter
  -- a formatter takes a single argument, and converts it to a string, or returns nil if it cannot format the argument
  add_formatter = function(self, callback)
    astate.add_formatter(callback)
  end,

  -- unregisters a formatter
  remove_formatter = function(self, fmtr)
    astate.remove_formatter(fmtr)
  end,

  format = function(self, args)
    -- args.n specifies the number of arguments in case of 'trailing nil' arguments which get lost
    local nofmt = args.nofmt or {}  -- arguments in this list should not be formatted
    for i = 1, (args.n or #args) do -- cannot use pairs because table might have nils
      if not nofmt[i] then
        local val = args[i]
        local valfmt = astate.format_argument(val)
        if valfmt == nil then valfmt = tostring(val) end -- no formatter found
        args[i] = valfmt
      end
    end
    return args
  end,

  set_parameter = function(self, name, value)
    astate.set_parameter(name, value)
  end,
  
  get_parameter = function(self, name)
    return astate.get_parameter(name)
  end,  
  
  add_spy = function(self, spy)
    astate.add_spy(spy)
  end,
  
  snapshot = function(self)
    return astate.snapshot()
  end,
}

local __meta = {

  __call = function(self, bool, message, ...)
    if not bool then
      error(message or "assertion failed!", 2)
    end
    return bool , message , ...
  end,

  __index = function(self, key)
    return rawget(self, key) or self.state()[key]
  end,

}

return setmetatable(obj, __meta)
