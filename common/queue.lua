local Queue = {}
local queue = {}

function queue.new()
    local self = {
        queue = {},
        first = 1,
        last = 1,
    }
    setmetatable(self, { __index = Queue })
    return self
end

function Queue:push(data)
    self.queue[self.last] = data
    self.last = self.last + 1
end

function Queue:pop()
    local data = self.queue[self.first]

    if not data then return nil end

    self.queue[self.first] = nil
    self.first = self.first + 1

    return data
end

function Queue:lookup(fn)
    for _, data in pairs(self.queue) do
        if fn(data) then
            return true
        end
    end

    return false
end

function Queue:length()
    return self.last - self.first
end

function Queue:sort(fn)
    table.sort(self.queue, fn)
end

function Queue:get()
    return self.queue
end

return queue