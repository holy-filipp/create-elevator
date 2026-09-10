local BundledIO = {}
local bundled_io = {}

function bundled_io.new(side)
    local self = {
        side = side,
        listeners = {},
    }
    setmetatable(self, { __index = BundledIO })
    return self
end

function BundledIO:listen(fn, ...)
    local colors_to_match = colors.combine(...)
    local listener = {
        colors_to_match = colors_to_match,
        callback_function = fn,
        triggered = colors.test(redstone.getBundledInput(self.side), colors_to_match),
    }

    if listener.triggered then
        listener.callback_function(true)
    end

    self.listeners[#self.listeners+1] = listener
end

function BundledIO:check(...)
    return colors.test(redstone.getBundledInput(self.side), ...)
end

function BundledIO:loop()
    while true do
        os.pullEvent("redstone")

        local input_colors = redstone.getBundledInput(self.side)
        
        for _, listener in ipairs(self.listeners) do
            local test = colors.test(input_colors, listener.colors_to_match)

            if test and not listener.triggered then
                listener.triggered = true
                listener.callback_function(true)
            elseif not test and listener.triggered then
                listener.triggered = false
                listener.callback_function(false)
            end
        end
    end
end

return bundled_io