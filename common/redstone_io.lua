local RedstoneIO = {}
local redstone_io = {}

function redstone_io.new(side)
    local self = {
        side = side,
        listeners = {},
    }
    setmetatable(self, { __index = RedstoneIO })
    return self
end

function RedstoneIO:listen(fn)
    local listener = {
        callback_function = fn,
        triggered = redstone.getInput(self.side),
    }

    if listener.triggered then
        listener.callback_function(true)
    end

    self.listeners[#self.listeners+1] = listener
end

function RedstoneIO:check()
    return redstone.getInput(self.side)
end

function RedstoneIO:loop()
    while true do
        os.pullEvent("redstone")

        local input = redstone.getInput(self.side)
        
        for _, listener in ipairs(self.listeners) do
            if input and not listener.triggered then
                listener.triggered = true
                listener.callback_function(true)
            elseif not input and listener.triggered then
                listener.triggered = false
                listener.callback_function(false)
            end
        end
    end
end

return redstone_io