local initial_setup = require("initial_setup")
local logger = require("common.logger")
local app = require("app")
local config = require("config")

-- Logger
if config.LOG_TO_FILE then
    logger:add_handler(logger.file_handler("/emcu/log.log"))
end
logger:set_level(config.LOG_LEVEL)

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