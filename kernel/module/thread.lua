-- big fancy scheduler --

do
  kernel.logger.log("initializing scheduler")
  local thread, tasks, sbuf, last, cur = {}, {}, {}, 0, 0

  local function checkDead(thd)
    local p = tasks[thd.parent] or {dead = false, coro = coroutine.create(function()end)}
    if thd.dead or p.dead or coroutine.status(thd.coro) == "dead" or coroutine.status(p.coro) == "dead" then
      return true
    end
    return false
  end

  local function getMinTimeout()
    local min = math.huge
    for pid, thd in pairs(tasks) do
      if computer.uptime() - thd.deadline < min then
        min = computer.uptime() - thd.deadline
      end
      if min <= 0 then
        min = 0
        break
      end
    end
    return min
  end

  local function cleanup()
    local dead = {}
    for pid, thd in pairs(tasks) do
      if checkDead(thd) then
        computer.pushSignal("thread_died", pid)
        dead[#dead + 1] = pid
      end
    end
    for i=1, #dead, 1 do
      tasks[dead[i]] = nil
    end

    local timeout = getMinTimeout()
    local sig = {computer.pullSignal(timeout)}
    if #sig > 0 then
      sbuf[#sbuf + 1] = sig
    end
  end

  local function getHandler(thd)
    local p = tasks[thd.parent] or {handler = kernel.logger.panic}
    return thd.handler or p.handler or getHandler(p)
  end

  local function handleProcessError(thd, err)
    local h = getHandler(thd)
    tasks[thd.pid] = nil
    computer.pushSignal("thread_errored", thd.pid, err)
    h(err)
  end

  local global_env = {}

  function thread.spawn(func, name, handler, env, stdin, stdout, priority)
    checkArg(1, func, "function")
    checkArg(2, name, "string")
    checkArg(3, handler, "function", "nil")
    checkArg(4, env, "table", "nil")
    checkArg(5, stdin, "table", "nil")
    checkArg(6, stdout, "table", "nil")
    last = last + 1
    env = setmetatable(env or {}, {__index = (tasks[cur] and tasks[cur].env) or global_env})
    stdin = stdin or {}
    stdour = stdout or {}
    priority = priority or math.huge
    local new = {
      coro = coroutine.create( -- the thread itself
        function()
          return xpcall(func, debug.traceback)
        end
      ),
      pid = last, -- process/thread ID
      name = name, -- thread name
      handler = handler, -- error handler
      user = kernel.users.uid(), -- current user
      users = {} -- user history
      owner = kernel.users.uid(), -- thread owner
      sig = {}, -- signal buffer
      ipc = {}, -- IPC buffer
      env = env, -- environment variables
      stdin = stdin, -- thread STDIN handle
      stdout = stdout, -- thread STDOUT handle
      deadline = computer.uptime(), -- signal deadline
      priority = priority, -- thread priority
      uptime = 0, -- thread uptime
      started = computer.uptime() -- time of thread creation
    }
    if not new.env.PWD then
      new.env.PWD = "/"
    end
    tasks[last] = new
    return last
  end

  function os.setenv(var, val)
    checkArg(1, var, "string", "number")
    checkArg(2, val, "string", "number", "boolean", "table", "nil", "function")
    if tasks[cur] then
      tasks[cur].env[var] = val
    else
      global_env[var] = val
    end
  end

  function os.getenv(var)
    checkArg(1, var, "string", "number")
    if tasks[cur] then
      tasks[cur].env[var] = val
    else
      global_env[var] = val
    end
  end

  function thread.stdin(stdin)
    checkArg(1, stdin, "table", "nil")
    if threads[cur] then
      if stdin then
        threads[cur].stdin = stdin
      end
      return threads[cur].stdin
    end
  end

  function thread.stdout(stdout)
    checkArg(1, stdout, "table", "nil")
    if threads[cur] then
      if stdout then
        threads[cur].stdout = stdout
      end
      return threads[cur].stdout
    end
  end

  -- (re)define kernel.users stuff to be thread-local. Not done in module/users.lua as it requires low-level thread access.
  local ulogin, ulogout, uuid = kernel.users.login, kernel.users.logout, kernel.users.uid
  function kernel.users.login(uid, password)
    checkArg(1, uid, "number")
    checkArg(2, password, "string")
    local ok, err = kernel.users.authenticate(uid, password)
    if not ok then
      return nil, err
    end
    if threads[cur] then
      table.insert(threads[cur].users, 1, threads[cur].user)
      threads[cur].user = uid
      return true
    end
    return ulogin(uid, password)
  end

  function kernel.users.logout()
    if tasks[cur] then
      tasks[cur].user = -1
      if #tasks[cur].users > 0 then
        tasks[cur].user = table.remove(tasks[cur].users, 1)
      end
      return true
    end
    return false -- kernel is always root
  end

  function kernel.users.uid()
    if tasks[cur] then
      return tasks[cur].user
    else
      return 0 -- again, kernel is always root
    end
  end

  function thread.threads()
    local t = {}
    for pid, _ in pairs(tasks) do
      t[#t + 1] = pid
    end
    return t
  end

  function thread.info(pid)
    checkArg(1, pid, "number")
    if not tasks[pid] then
      return nil, "no such thread"
    end
    local t = tasks[pid]
    local inf = {
      name = t.name,
      owner = t.owner,
      priority = thd.priority,
      uptime = thd.uptime,
      started = thd.started
    }
  end

  function thread.signal(pid, sig)
    checkArg(1, pid, "number")
    checkArg(2, sig, "number")
    if not tasks[pid] then
      return nil, "no such thread"
    end
    local msg = {
      "signal",
      cur,
      sig
    }
    table.insert(tasks[pid].sig, msg)
    return true
  end

  function thread.ipc(pid, ...)
    checkArg(1, pid, "number")
    if not tasks[pid] then
      return nil, "no such thread"
    end
    local ipc = {
      "ipc",
      cur,
      ...
    }
    table.insert(tasks[pid].ipc, ipc)
    return true
  end

  thread.signals = {
    interrupt = 2,
    quit      = 3,
    term      = 15,
    usr1      = 65,
    usr2      = 66,
    kill      = 9
  }

  function thread.start()
    thread.start = nil
    while #tasks > 0 do
      local run = {}
      for pid, thd in pairs(tasks) do
        if thd.deadline <= computer.uptime() or #sbuf > 0 or #thd.ipc > 0 or #thd.sig > 0 then
          run[#run + 1] = thd
        end
      end

      table.sort(run, function(a, b)
        if a.priority > b.priority then
          return a, b
        elseif a.prioroty < b.priority then
          return b, a
        else
          return a, b
        end
      end)

      local sig = table.remove(sbuf, 1)

      for i, thd in ipairs(run) do
        cur = thd.pid
        local ok, p1, p2
        if #thd.ipc > 0 then
          local ipc = table.remove(thd.ipc, 1)
          ok, p1, p2 = coroutine.resume(thd.coro, table.unpack(ipc))
        elseif #thd.sig > 0 then
          local nsig = table.remove(thd.sig, 1)
          ok, p1, p2 = coroutine.resume(thd.coro, table.unpack(nsig))
          if nsig[3] == thread.signals.kill then
            thd.dead = true
          end
        elseif #sig > 0 then
          ok, p1, p2 = coroutine.resume(thd.coro, table.unpack(sig))
        else
          ok, p1, p2 = coroutine.resume(thd.coro)
        end
        if not ok and p1 then
          handleProcessError(thd.pid, p1)
        elseif ok then
          if p1 and type(p1) == "number" then
            thd.deadline = thd.deadline + p1
          else
            thd.deadline = math.huge
          end
          thd.uptime = computer.uptime() - thd.started
        end
      end

      cleanup()
    end
    kernel.logger.panic("all tasks died")
  end

  kernel.thread = thread
end
