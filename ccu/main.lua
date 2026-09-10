local initial_setup = require("initial_setup")
local logger = require("common.logger")
local app = require("app")

-- Logger
logger:add_handler(logger.file_handler("/ccu/log.log"))
logger:set_level(logger.level_trace)

-- Settings
settings.define("ccu.emcu_computer_id", {
    type = "number",
})

-- Check whether we need to run initial setup
if not settings.get("ccu.emcu_computer_id") then
    initial_setup()
else
    local app = app.new()
    app:run()
end