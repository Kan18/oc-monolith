local args, opts = require("shell").parse(...)
local thread = require("thread")
local users = require("users")
local mode = args[1]
local time = require("time").formatTime -- time! time! give me more time!

local out = ""
local thd = thread.threads()
if not mode then
  print("PID  | PARENT | OWNER        | NAME")
elseif mode == "a" then
  print("PID  | PARENT | OWNER        | START    | TIME     | NAME")
else
  return require("shell").codes.argument
end
for n, pid in ipairs(thd) do
  local info = thread.info(pid)
  if not mode then
    print(string.format("%4d |   %4d | %12s | %s", pid, info.parent, users.getname(info.owner), info.name))
  elseif mode == "a" then
    print(string.format("%4d |   %4d | %12s | %8s | %8s | %s", pid, info.parent, users.getname(info.owner), time(info.started, "s", false), time(info.uptime, "s", false), info.name))
  end
end

io.write(out)
