-- common editor functions --

local ed = {}
ed.buffers = {}

ed.buffer = {}

function ed.buffer:load(file)
  checkArg(1, file, "string")
  local handle, err = io.open(file, "r")
  if not handle then
    return nil, err
  end
  local lines = {}
  for line in handle:lines() do
    lines[#lines + 1] = line:gsub("\n", "") .. "\n"
  end
  handle:close()
  self.lines = lines
  return true
end

function ed.buffer:save(file)
  checkArg(1, file, "string", "nil")
  if not self.name or self.name == "" then
    checkArg(1, file, "string")
  end
  local handle, err = io.open(file, "w")
  if not handle then
    return nil, err
  end
  for i, line in ipairs(self.lines) do
    handle:write(line)
  end
  handle:close()
  return true
end

local function drawline(y, n, l, L)
  l = l or ""
  n = (n and tostring(n)) or "~"
  local nl = tostring(L):len()
  io.write(string.format("\27[%dH%"..nl.."s %s", y, n, l))
end

function ed.buffer:draw()
  local w, h = ed.getScreenSize()
  local y = 1
  for i=1+self.scroll.h, 1+self.scroll.h+h, 1 do
    local line = self.lines[i] or ""
    local n = drawline(y, (self.lines[i] and i) or nil, (self.highlighter or function(e)return e end)(line:sub(1, w + self.scroll.w)), #self.lines)
    y=y+1
    if y >= h then
      break
    end
  end
end

function ed.getScreenSize()
  return io.stdout.gpu.getResolution()
end

function ed.new(file)
  checkArg(1, file, "string", "nil")
  local new = setmetatable({
    name = file,
    lines = {},
    scroll = {
      w = 0,
      h = 0
    }
  }, {__index=ed.buffer})
  if file then
    new:load(file)
  end
  local n = #ed.buffers + 1
  ed.buffers[n] = new
  return n
end

return ed
