local initial_setup = require("initial_setup")
local logger = require("common.logger")
local app = require("app")

-- Logger
logger:add_handler(logger.file_handler("/emcu/log.log"))
logger:set_level(logger.level_trace)

-- Settings
settings.define("emcu.landings", {
    type = "number",
})

-- Check whether we need to run initial setup
if not settings.get("emcu.landings") then -- TODO: add better checking for settings
    initial_setup()
else
    local app = app.new()
    app:run()
end