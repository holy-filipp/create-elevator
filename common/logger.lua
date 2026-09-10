local pretty = require("cc.pretty")

local Logger = {}
local logger = {
    handlers = {},
}

logger.level_info = 1
logger.level_warn = 2
logger.level_error = 3
logger.level_debug = 4
logger.level_trace = 5
logger.level = logger.level_error

local LEVELS = {
    [logger.level_info] = "INFO",
    [logger.level_warn] = "WARN",
    [logger.level_error] = "ERROR",
    [logger.level_debug] = "DEBUG",
    [logger.level_trace] = "TRACE",
}

local LEVEL_COLORS = {
    [logger.level_info] = colors.green,
    [logger.level_warn] = colors.orange,
    [logger.level_error] = colors.red,
    [logger.level_debug] = colors.magenta,
    [logger.level_trace] = colors.lightGray,
}

local os_clock = os.clock
local os_date = os.date

local function message_to_documents(message)
    local message_parts = {}

    for i, part in ipairs(message) do
        if type(part) == "string" then
            message_parts[#message_parts+1] = pretty.text(part, colors.white)
        else
            message_parts[#message_parts+1] = pretty.pretty(part)
        end

        if i ~= #message then
            message_parts[#message_parts+1] = " " 
        end
    end

    return message_parts
end

function logger.new(module, ...)
    local self = {
        handlers = { ... },
        module = module or "DEFAULT",
    }
    setmetatable(self, { __index = Logger })
    return self
end

function logger:add_handler(handler)
    self.handlers[#self.handlers+1] = handler
end

function logger:set_level(level)
    self.level = level 
end

function logger.terminal_handler()
    return {
        handle = function (log)
            local uptime = pretty.text(string.format("[%.1f]", log.uptime), colors.gray)
            local module = pretty.text(string.format("[%s]", log.module), colors.yellow)
            local level = pretty.text(string.format("[%s]", LEVELS[log.level]), LEVEL_COLORS[log.level])

            local document = pretty.concat(uptime, module, level, " ", table.unpack(message_to_documents(log.message)))

            pretty.print(document)
        end,
    }
end

function logger.file_handler(path)
    path = path or string.format("/logs/%s.log", os_date("%d-%m-%Y"))
    local file = fs.open(path, "a")

    local handler = {
        handle = function (log)
            local document = pretty.concat(table.unpack(message_to_documents(log.message)))

            file.writeLine(string.format("[%.3f][%s][%s][%s] %s", log.uptime, log.date, log.module, LEVELS[log.level], pretty.render(document, 20)))
        end,
    }

    return handler
end

function Logger:log(level, ...)
    if level > logger.level then return end

    local log = {
        level = level,
        message = { ... },
        module = self.module,
        uptime = os_clock(),
        date = os_date("%T %d.%m.%Y"),
    }

    for _, handler in ipairs(logger.handlers) do
        handler.handle(log)
    end
end

function Logger:info(...)
    self:log(logger.level_info, ...)
end

function Logger:warn(...)
    self:log(logger.level_warn, ...)
end

function Logger:error(...)
    self:log(logger.level_error, ...)
end

function Logger:debug(...)
    self:log(logger.level_debug, ...)
end

function Logger:trace(...)
    self:log(logger.level_trace, ...)
end

return logger