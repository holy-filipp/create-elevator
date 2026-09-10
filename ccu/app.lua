local config = require("config")
local logger = require("common.logger")
local socket_client = require("common.socket_client")
local display = require("display")
local button = require("common.button")
local vfd = require("common.vfd")
local easing = require("common.easing")

local App = {}
local app = {}

function app.new()
    local self = {
        log = logger.new("App"),
        emcu_computer_id = settings.get("ccu.emcu_computer_id"),
    }
    setmetatable(self, { __index = App })
    return self
end

function App:move_doors(direction)
    if not self.vfd:is_finished() then return end
    
    local move_start = os.clock()

    self.vfd:move((direction == (config.INVERT_DOOR_DIRECTIONS and "close" or "open")) and "fwd" or "rev", 1, config.DOORS_RPM)

    while true do
        self.vfd:eval(os.clock() - move_start)

        if self.vfd:is_finished() then
            break
        end

        os.sleep(0.1)
    end

    self.client:send({
        type = "$DOORS HAVE FINISHED MOVING",
        direction = direction,
    })

    self.log:info("Doors", direction, "done")
end

function App:run()
    -- Modem
    self.modem = peripheral.wrap(config.MODEM_SIDE)
    
    if not self.modem then
        self.log:error("Failed to wrap modem")
        print("Failed to find modem, check your hardware and config")
        return
    end

    -- Motor
    self.motor = peripheral.wrap("Create_CreativeMotor_0")

    if not self.motor then
        self.log:error("Failed to wrap motor")
        print("Failed to find motor, check your hardware and config")
        return
    end

    -- VFD
    self.vfd = vfd.new(self.motor)
    self.vfd:set_acceleration_time(config.VFD_ACCELERATION_TIME)
    self.vfd:set_deceleration_time(config.VFD_DECELERATION_TIME)
    self.vfd:set_easing_function(easing.easeInOutCubic)

    -- Monitor
    self.monitor = peripheral.wrap(config.MONITOR_SIDE)

    if not self.monitor then
        self.log:error("Failed to wrap monitor")
        print("Failed to find monitor, check your hardware and config")
        return
    end

    -- Display
    local dp = display.new(self.monitor)
    dp:render()

    -- Socket
    self.client = socket_client.new(config.DEVICE_NAME, self.modem)
    self.client:set_channel(config.CHANNEL)
    self.client:set_keep_connection(true)
    self.client:on("connect", function (computer)
        self.log:info("Connected to EMCU", computer)
    end)
    self.client:on("disconnect", function (computer)
        self.log:info("Disconnected from EMCU", computer)
    end)

    local handlers = {
        ["$SEND CAR FLOORS"] = function (payload)
            dp:set_floors(payload.floors)
        end,
        ["$UPDATE CAR POSITION INDICATOR"] = function (payload)
            dp:set_floor(payload.floor)
            dp:set_direction(payload.direction)
        end,
        ["$UPDATE CAR BUTTON LEDS"] = function (payload)
            dp:set_leds(payload.leds)
        end,
        ["$MOVE DOORS"] = function (payload)
            self:move_doors(payload.direction)
        end,
    }

    self.client:on("message", function (payload, computer)
        if computer.computer_id ~= self.emcu_computer_id then return end

        local type = payload.type

        if handlers[type] then
            handlers[type](payload)
        end
    end)

    dp:on("car_call", function (floor)
        self.client:send({
            type = "$CAR CALL",
            floor = {
                floor = floor.floor,
                lcu_id = floor.lcu_id,
            },
        })
    end)

    dp:on("doors_open", function ()
        self.client:send({
            type = "$CAR DOORS REQUEST",
            state = "open",
        })
    end)

    dp:on("doors_close", function ()
        self.client:send({
            type = "$CAR DOORS REQUEST",
            state = "close",
        })
    end)

    parallel.waitForAll(function (spawn)
        self.client:connect(self.emcu_computer_id, spawn)
    end, function ()
        button.click_handler()
    end)
end

return app