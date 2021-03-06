-- computer.shutdown stuff --

do
  local shutdown = computer.shutdown
  local closeAll = kernel.filesystem.closeAll
  kernel.filesystem.closeAll = nil
  function computer.shutdown(reboot)
    checkArg(1, reboot, "boolean", "nil")
    kernel.logger.setShown(true)
    local running = kernel.thread.threads()
    computer.pushSignal("shutdown")
    kernel.logger.log("shutting down")
    coroutine.yield()
    kernel.logger.log("close all file handles")
    pcall(closeAll)
    -- clear all GPUs
    kernel.logger.log("clear all the screens")
    for addr, _ in component.list("gpu") do
      local w, h = component.invoke(addr, "getResolution")
      component.invoke(addr, "fill", 1, 1, w, h, " ")
    end
    kernel.logger.log("shut down")
    shutdown(reboot)
  end
end
