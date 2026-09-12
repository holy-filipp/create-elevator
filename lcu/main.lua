local logger = require("common.logger")
local initial_setup = require("initial_setup")
local socket_client = require("common.socket_client")
local config = require("config")
local redstone_io = require("common.redstone_io")
local display = require("display")
local button = require("common.button")
local config = require("config")

-- Logger
if config.LOG_TO_FILE then
    logger:add_handler(logger.file_handler("/emcu/log.log"))
end
logger:set_level(config.LOG_LEVEL)

local main_log = logger.new("Main")

-- Settings
settings.define("lcu.emcu_computer_id", {
    type = "number",
})

-- Main function
local function main()
    -- Modem
    local modem = peripheral.wrap("top")

    if not modem then
        main_log:error("Failed to wrap modem")
        print("Failed to find modem, check your hardware and config")
        return
    end

    -- Monitor
    local monitor = peripheral.wrap(config.MONITOR_PERIPHERAL_NAME)

    if not monitor then
        main_log:error("Failed to wrap monitor")
        print("Failed to find monitor, check your hardware and config")
        return
    end

    -- Redstone IO
    local rio = redstone_io.new(config.SENSOR_REDSTONE_SIDE)

    -- Display
    local dp = display.new(monitor)
    dp:render()

    -- Socket
    local client = socket_client.new(config.DEVICE_NAME, modem)
    client:set_channel(config.CHANNEL)
    client:set_keep_connection(true)
    client:on("connect", function (computer)
        main_log:info("Connected to EMCU", computer)
    end)
    client:on("disconnect", function (computer)
        main_log:info("Disconnected from EMCU", computer)
    end)

    -- Message handlers
    local handlers = {
        ["$GET SENSOR STATE"] = function (payload)
            client:send({
                type = "$GET SENSOR STATE RESPONSE",
                state = rio:check(),
            })
        end,
        ["$UPDATE HALL BUTTON LED"] = function (payload)
            dp:change_button_led(payload.button, payload.state)
        end,
        ["$UPDATE HALL POSITION INDICATOR"] = function (payload)
            dp:set_floor(payload.floor)
            dp:set_direction(payload.direction)
        end,
        ["$SET AS FINAL"] = function (payload)
            dp:set_as_final(payload.side)
        end,
    }

    client:on("message", function (payload)
        local type = payload.type

        if handlers[type] then
            handlers[type](payload)
        end
    end)

    rio:listen(function (state)
        client:send({
            type = "$SENSOR STATE UPDATE",
            state = state,
        })
    end)

    dp:on("click_up", function ()
        client:send({
            type = "$HALL CALL",
            direction = "up",
        })
    end)
    dp:on("click_down", function ()
        client:send({
            type = "$HALL CALL",
            direction = "down",
        })
    end)

    parallel.waitForAll(function ()
        -- Connect to EMCU
        client:connect(settings.get("lcu.emcu_computer_id"))
    end, function ()
        rio:loop()
    end, function ()
        button.click_handler()
    end)
end
    
-- Check whether we need to run initial setup
if not settings.get("lcu.emcu_computer_id") then
    initial_setup()
else
    main()
end