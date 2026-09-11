local logger = require("common.logger")
local config = require("config")
local socket_server = require("common.socket_server")
local vfd = require("common.vfd")
local easing = require("common.easing")
local bundled_io = require("common.bundled_io")
local queue = require("common.queue")

local App = {}
local app = {}

function app.new()
    local self = {
        log = logger.new("App"),
        landings = settings.get("emcu.landings"),
        connected_lcus = {},
        connected_lcus_count = 0,
        up_queue = queue.new(),
        down_queue = queue.new(),
    }
    setmetatable(self, { __index = App })

    self:prepare_request_handlers()

    return self
end

function App:load_hardware_memory()
    local file = fs.open(".emcu_hardware_memory.json", "r")
    self.emcu_hardware_memory = textutils.unserializeJSON(file.readAll())

    self.log:debug(self.emcu_hardware_memory)
end

function App:save_hardware_memory()
    local file = fs.open(".emcu_hardware_memory.json", "w")
    file.write(textutils.serializeJSON(self.emcu_hardware_memory))
end

function App:is_lcus_learned()
    for _, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
        if not lcu.position then
            return false
        end
    end

    return true
end

function App:learn_lcus()
    self.log:info("Starting LCUs learn")

    -- Go to zero point
    -- Firstly need to check if we already on zero point (LFL)
    if self.bio:check(config.LFL_COLOR) then
        self.log:info("Searching LCU on LFL")
        
        -- We already on zero point, let's check which LCU is it
        self.server:broadcast({
            type = "$GET SENSOR STATE",
        })

        -- Callback will return zero point LCU computer id
        self.learning = {
            state = "ALREADY ON ZERO POINT",
            callback_function = function (computer_id)
                self.log:info("Lower Final Limit LCU found", computer_id)
                
                -- Writing computer id to memory
                self.emcu_hardware_memory.final_limit_lcus = {
                    lower = computer_id,
                }
                
                -- And now we know that this LCU is on position 0
                for _, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
                    if lcu.computer_id == computer_id then
                        -- Set position 0
                        lcu.position = 0
                        break
                    end
                end
                
                -- And save
                self:save_hardware_memory()

                self.learning.state = ""

                -- Next step of learning
                self:learn_lcus_positions()
            end,
        }
    else
        self.log:info("Moving car down to LFL")
        self.vfd:stupid_move("rev", config.LEARNING_RPM)

        -- Wait until LFL sensor triggers, check LCUs
        self.learning = {
            state = "MOVING TO ZERO POINT",
            callback_function = function ()
                if self.learning.lfl and self.learning.lcu then
                    self.log:info("Lower Final Limit and LCU found")
                    self.vfd:stupid_stop()

                    -- Writing computer id to memory
                    self.emcu_hardware_memory.final_limit_lcus = {
                        lower = self.learning.lcu,
                    }
                    
                    -- And now we know that this LCU is on position 0
                    for _, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
                        if lcu.computer_id == self.learning.lcu then
                            -- Set position 0
                            lcu.position = 0
                            break
                        end
                    end
                    
                    -- And save
                    self:save_hardware_memory()

                    self.learning.state = ""

                    -- Next step of learning
                    self:learn_lcus_positions()
                end
            end,
        }
    end
end

function App:learn_lcus_positions()
    self.log:info("Now we need to acknowledge landings positions")

    -- To acknowledge LCUs positions, we need to move car up and listen for sensors on LCU, and when car reaches upper landing, it will trigger Upper Final Limit, after that we stop car
    os.sleep(1)
    -- Move car up
    self.vfd:stupid_move("fwd", config.LEARNING_RPM)

    self.learning = {
        state = "CALCULATING POSITIONS",
        old_lcu = -1,
        lcu_count = 1, -- Includes zero point LCU
        -- This callback calls when LCU sensor triggered or UFL
        callback_function = function ()
            if self.learning.old_lcu ~= self.learning.lcu then
                -- VFD provides to us position from stupid move start
                local position = math.floor(self.vfd:stupid_blocks_passed() + 0.5)

                self.log:debug("LCU with computer id", self.learning.lcu, "is on", position)

                -- Set position of LCU
                for _, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
                    if lcu.computer_id == self.learning.lcu then
                        lcu.position = position
                        break
                    end
                end

                self.learning.lcu_count = self.learning.lcu_count + 1
                self.learning.old_lcu = self.learning.lcu

                if self.learning.lcu_count == self.landings then
                    self.learning.last_lcu = true
                end
            end

            if self.learning.last_lcu and self.learning.ufl then
                self.log:debug("UFL LCU found", self.learning.lcu)
                
                self.vfd:stupid_stop()

                self.emcu_hardware_memory.current_floor_lcu = self.learning.lcu
                self.emcu_hardware_memory.final_limit_lcus.upper = self.learning.lcu
                self:save_hardware_memory()

                self.log:info("Learning done")
                self.learning = nil
                self:ready()
            end
        end,
    }
end

function App:pre_ready()
    self.log:info("Pre ready")

    self.log:info("Checking LCUs for learning")
    if not self:is_lcus_learned() then
        self.log:info("LCUs not learned")

        self:learn_lcus()
    else
        self:ready()
    end 
end

function App:find_lcu_by_id(id)
    for _, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
        if lcu.computer_id == id then
            return lcu
        end
    end

    return false
end

function App:ready()
    self.log:info("Ready")

    self.ready = true

    -- Get current floor
    local current_floor_lcu = self:find_lcu_by_id(self.emcu_hardware_memory.current_floor_lcu)
    local current_floor = current_floor_lcu.floor
    local current_floor_name = current_floor_lcu.floor_name

    self.current_floor = current_floor
    self.old_current_floor = current_floor
    self.current_floor_name = current_floor_name
    self.current_direction = "none"
    self.doors_state = "closed"
    self.doors_close_time = os.clock()
    self.should_open_doors = false
    self.is_doors_open_pending = false
    self.is_doors_close_pending = false
    self.car_leds = {}
    self.hall_leds = {}

    self.log:info("Floor and position restored from memory, position:", current_floor_lcu.position, "floor:", current_floor)

    self.vfd:set_position(current_floor_lcu.position)

    self.server:broadcast({
        type = "$UPDATE HALL POSITION INDICATOR",
        direction = "none",
        floor = current_floor_name,
    })

    if self.ccu then
        self:update_ccu()
    end

    self.server:send(self.emcu_hardware_memory.final_limit_lcus.lower, {
        type = "$SET AS FINAL",
        side = "lower",
    })

    self.server:send(self.emcu_hardware_memory.final_limit_lcus.upper, {
        type = "$SET AS FINAL",
        side = "upper",
    })

    self.spawn_thread(function ()
        self:scheduler_loop()
    end)

    self.spawn_thread(function ()
        while true do
            self:draw_term()
            os.sleep(0.5)
        end
    end)
end

function App:update_ccu()
    local floors = {}

    for i, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
        floors[i] = {
            floor = lcu.floor,
            floor_name = lcu.floor_name,
            lcu_id = lcu.computer_id,
        }
    end

    table.sort(floors, function (a, b)
        return a.floor < b.floor
    end)

    self.server:send(self.ccu, {
        type = "$SEND CAR FLOORS",
        floors = floors,
    })

    self.server:send(self.ccu, {
        type = "$UPDATE CAR POSITION INDICATOR",
        floor = self.current_floor_name,
        direction = self.current_direction,
    })

    self.server:send(self.ccu, {
        type = "$UPDATE CAR BUTTON LEDS",
        leds = self.car_leds,
    })
end

function App:socket_on_connect(computer)
    if computer.device_name == "LCU" then
        if not self:find_lcu_by_id(computer.computer_id) then
            self.log:warn("Unknown LCU connected to us")
            return
        end
    
        self.connected_lcus[computer.computer_id] = computer
        self.connected_lcus_count = self.connected_lcus_count + 1

        if self.connected_lcus_count == self.landings then
            self:pre_ready()
        end
    end

    if computer.device_name == "CCU" then
        self.ccu = computer.computer_id

        if self.ready then
            self:update_ccu()
        end
    end
end

function App:socket_on_disconnect(computer, reason)
    self.connected_lcus[computer.computer_id] = nil
    self.connected_lcus_count = self.connected_lcus_count - 1
end

function App:get_sensor_state_response(payload, computer, reply)
    if self.learning and self.learning.state == "ALREADY ON ZERO POINT" then
        if payload.state then
            self.learning.callback_function(computer.computer_id)
        end
    end
end

function App:bio_lfl(state)
    if state and self.learning and self.learning.state == "MOVING TO ZERO POINT" then
        self.learning.lfl = true
        self.learning.callback_function()
    end
end

function App:bio_ufl(state)
    if state and self.learning and self.learning.state == "CALCULATING POSITIONS" then
        self.learning.ufl = true
        self.learning.callback_function()
    end
end

function App:sensor_state_update(payload, computer, reply)
    if self.learning and self.learning.state == "MOVING TO ZERO POINT" and payload.state then
        self.learning.lcu = computer.computer_id
        self.learning.callback_function()
    end

    if self.learning and self.learning.state == "CALCULATING POSITIONS" and payload.state then
        self.learning.lcu = computer.computer_id
        self.learning.callback_function()
    end
end

function App:doors_have_finished_moving(payload, computer, reply)
    if payload.direction == "close" then
        self.is_doors_close_pending = false
        self.doors_state = "closed"

        if self.up_queue:length() == 0 and self.down_queue:length() == 0 and self.current_direction ~= "none" and not self.pending_pickup_direction then
            self.current_direction = "none"
        end
    end
    
    if payload.direction == "open" then
        self.doors_close_time = os.clock() + config.DOORS_WAIT_TIME
        self.doors_state = "open"
        self.is_doors_open_pending = false
        self.should_open_doors = false
    end
end

function App:car_doors_request(payload, computer, reply)
    self:new_request({
        action = "DOORS",
        state = payload.state,
    })
end

function App:car_call(payload, computer, reply)
    self:new_request({
        action = "CAR CALL",
        floor = payload.floor.floor,
    })
end

function App:hall_call(payload, computer, reply)
    local lcu = self:find_lcu_by_id(computer.computer_id)
    
    if not lcu then
        return
    end

    self:new_request({
        action = "HALL CALL",
        direction = payload.direction,
        floor = lcu.floor,
    })
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
    self.motor = peripheral.wrap(config.MOTOR_PERIPHERAL_NAME)
    
    if not self.motor then
        self.log:error("Failed to wrap motor")
        print("Failed to find motor, check your hardware and config")
        return
    end

    -- LCUs
    self:load_hardware_memory()

    -- VFD
    self.vfd = vfd.new(self.motor)
    self.vfd:set_acceleration_time(config.VFD_ACCELERATION_TIME)
    self.vfd:set_deceleration_time(config.VFD_DECELERATION_TIME)
    self.vfd:set_easing_function(easing.easeInOutCubic)

    -- Bundled IO
    self.bio = bundled_io.new(config.BUNDLED_SIDE)
    self.bio:listen(function (state)
        self:bio_lfl(state)
    end, config.LFL_COLOR)
    self.bio:listen(function (state)
        self:bio_ufl(state)
    end, config.UFL_COLOR)

    -- Socket
    self.server = socket_server.new(config.DEVICE_NAME, self.modem)
    self.server:set_channel(config.CHANNEL)
    self.server:accept("LCU")
    self.server:accept("CCU")
    self.server:on("connect", function (computer)
        self:socket_on_connect(computer)
    end)
    self.server:on("disconnect", function (computer, reason)
        self:socket_on_disconnect(computer, reason)
    end)

    local handlers = {
        ["$GET SENSOR STATE RESPONSE"] = function (...)
            self:get_sensor_state_response(...)
        end,
        ["$SENSOR STATE UPDATE"] = function (...)
            self:sensor_state_update(...)
        end,
        ["$CAR CALL"] = function (...)
            self:car_call(...)
        end,
        ["$CAR DOORS REQUEST"] = function (...)
            self:car_doors_request(...)
        end,
        ["$HALL CALL"] = function (...)
            self:hall_call(...)
        end,
        ["$DOORS HAVE FINISHED MOVING"] = function (...)
            self:doors_have_finished_moving(...) 
        end,
    }

    self.server:on("message", function (payload, computer, reply)
        local type = payload.type

        if handlers[type] then
            handlers[type](payload, computer, reply)
        end
    end)
    
    parallel.waitForAll(function (spawn)
        self.spawn_thread = spawn
        self.server:listen(spawn)
    end, function ()
        self.bio:loop()
    end)
end

function App:add_to_queue(data)
    self.log:debug("Task has been added to queue", data)
    self.queue:push(data)
end

function App:find_lcu_by_floor(floor)
    for _, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
        if lcu.floor == floor then
            return lcu
        end
    end

    return false
end

function App:get_direction(current_floor, target_floor)
    return target_floor > current_floor and "fwd" or "rev"
end

local function compare_descending(a, b)
    return a.floor > b.floor
end

local function compare_ascending(a, b)
    return b.floor > a.floor
end

function App:set_hall_led(floor, direction, state)
    if not self.hall_leds[floor] then
        self.hall_leds[floor] = {}
    end

    self.hall_leds[floor][direction] = state
end

function App:set_car_led(floor, state)
    self.car_leds[floor] = state
end

function App:prepare_request_handlers()
    self.request_handlers = {
        ["HALL CALL"] = function (data)
            if data.floor == self.current_floor and self.vfd:is_finished() then
                self.should_open_doors = true
                self.log:debug("Hall call made when car was there, opening doors")
                return
            end

            if data.direction == "up" then
                self:set_hall_led(data.floor, "up", true)
               
                if self.up_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end
                if self.down_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end
                
                if self.target_floor == data.floor then return end

                if self.current_direction == "none" then
                    self.pending_pickup_direction = "up"

                    if data.floor < self.current_floor then
                        self.down_queue:push(data)
                    else
                        self.up_queue:push(data)
                    end
                else
                    self.up_queue:push(data)
                    self.up_queue:sort(compare_ascending)
                end
            end

            if data.direction == "down" then
                self:set_hall_led(data.floor, "down", true)

                if self.up_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end
                if self.down_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end

                if self.target_floor == data.floor then return end

                if self.current_direction == "none" then
                    self.pending_pickup_direction = "down"
                end

                if self.current_direction == "none" then
                    self.pending_pickup_direction = "down"

                    if data.floor < self.current_floor then
                        self.down_queue:push(data)
                    else
                        self.up_queue:push(data)
                    end
                else
                    self.down_queue:push(data)
                    self.down_queue:sort(compare_descending)
                end
            end
        end,
        ["CAR CALL"] = function (data)
            if data.floor > self.current_floor then
                self:set_car_led(data.floor, true)

                if self.up_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end
                if self.down_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end

                if self.target_floor == data.floor then return end

                self.up_queue:push(data)
                self.up_queue:sort(compare_ascending)
            end

            if data.floor < self.current_floor then
                self:set_car_led(data.floor, true)

                if self.up_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end
                if self.down_queue:lookup(function (call)
                    return call.floor == data.floor
                end) then return end

                if self.target_floor == data.floor then return end

                self.down_queue:push(data)
                self.down_queue:sort(compare_descending)
            end
        end,
        ["DOORS"] = function (data)
            if not self.vfd:is_finished() then return end

            if data.state == "open" then
                if self.doors_state == "open" then
                    self.doors_close_time = os.clock() + config.DOORS_WAIT_TIME
                end

                if self.doors_state == "closed" then
                    self.should_open_doors = true
                end
            end

            if data.state == "close" then
                if self.doors_state == "open" then
                    self.doors_close_time = os.clock()
                end
            end
        end,
    }
end

function App:new_request(data)
    self.log:debug("New request", data)

    local action = data.action

    if self.request_handlers[action] then
        self.request_handlers[action](data)

        self:update_leds()

        self.log:debug("Request handled")
        self.log:debug("Up queue:")

        for _, req in pairs(self.up_queue.queue) do
            self.log:debug(req.action, "|", req.floor)
        end

        self.log:debug("Down queue:")

        for _, req in pairs(self.down_queue.queue) do
            self.log:debug(req.action, "|", req.floor)
        end
    end
end

function App:update_indicators()
    self.server:broadcast({
        type = "$UPDATE HALL POSITION INDICATOR",
        direction = self.current_direction,
        floor = self.current_floor_name,
    })

    self.server:send(self.ccu, {
        type = "$UPDATE CAR POSITION INDICATOR",
        direction = self.current_direction,
        floor = self.current_floor_name,
    })
end

function App:number_of_blocks(from, to)
    local from_lcu = self:find_lcu_by_floor(from)
    local to_lcu = self:find_lcu_by_floor(to)

    if not from_lcu or not to_lcu then
        self.log:error("Failed to get number of blocks between floor", from, "and", to)
        return 0
    end

    return math.abs(from_lcu.position - to_lcu.position)
end

function App:get_lcu_by_position(pos)
    for _, lcu in ipairs(self.emcu_hardware_memory.known_lcus) do
        if lcu.position + 3 > pos and lcu.position - 3 < pos then
            return lcu
        end
    end

    return false
end

function App:scheduler_loop()
    self.log:debug("Scheduler loop")

    while true do
        local up_queue_len = self.up_queue:length()
        local down_queue_len = self.down_queue:length()
        local vfd_busy = not self.vfd:is_finished()
        local doors_closed = self.doors_state == "closed"

        if self.current_direction == "none" then
            if up_queue_len > 0 then
                self.current_direction = "up"
                self.log:debug("Set the current direction to up")
            end

            if down_queue_len > 0 then
                self.current_direction = "down"
                self.log:debug("Set the current direction to down")
            end

            self:update_indicators()
        end

        if self.current_direction ~= "up" and up_queue_len > 0 and down_queue_len == 0 then
                self.current_direction = "up"
                self:update_indicators()
        end

        if self.current_direction ~= "down" and down_queue_len > 0 and up_queue_len == 0 then
            self.current_direction = "down"
            self:update_indicators()
        end

        if self.current_direction == "up" and up_queue_len > 0 and not vfd_busy and doors_closed and not self.should_open_doors then
            local call = self.up_queue:pop()
            local blocks_to_pass = self:number_of_blocks(self.current_floor, call.floor)
            local direction = self:get_direction(self.current_floor, call.floor)

            self.target_floor = call.floor

            self.log:info("Starting move from", self.current_floor, "to", call.floor, "; blocks to pass:", blocks_to_pass, "direction:", direction)

            self.vfd:move(direction, blocks_to_pass, config.NORMAL_RPM)
            self.move_start_time = os.clock()
        end

        if self.current_direction == "down" and down_queue_len > 0 and not vfd_busy and doors_closed and not self.should_open_doors then
            local call = self.down_queue:pop()
            local blocks_to_pass = self:number_of_blocks(self.current_floor, call.floor)
            local direction = self:get_direction(self.current_floor, call.floor)

            self.target_floor = call.floor

            self.log:info("Starting move from", self.current_floor, "to", call.floor, "; blocks to pass:", blocks_to_pass, "direction:", direction)

            self.vfd:move(direction, blocks_to_pass, config.NORMAL_RPM)
            self.move_start_time = os.clock()
        end

        if vfd_busy then
            self.vfd:eval(os.clock() - self.move_start_time)

            local current_lcu = self:get_lcu_by_position(self.vfd:get_position())
            
            if current_lcu then
                self.current_floor = current_lcu.floor
                self.current_floor_name = current_lcu.floor_name

                if self.current_floor ~= self.old_current_floor then
                    self:update_indicators()

                    self.emcu_hardware_memory.current_floor_lcu = current_lcu.computer_id
                    self:save_hardware_memory()

                    self.old_current_floor = self.current_direction
                end
            end

            self.should_open_doors = true
        end
        
        if not doors_closed and self.doors_close_time <= os.clock() and not self.is_doors_close_pending then
            self.server:send(self.ccu, {
                type = "$MOVE DOORS",
                direction = "close",
            })

            self.is_doors_close_pending = true
        end

        if not vfd_busy and self.should_open_doors and not self.is_doors_open_pending then
            if self.target_floor then
                self:set_car_led(self.target_floor, false)
                self:set_hall_led(self.target_floor, "up", false)
                self:set_hall_led(self.target_floor, "down", false)
            
                self:update_leds()
            end

            self.server:send(self.ccu, {
                type = "$MOVE DOORS",
                direction = "open",
            })

            self.is_doors_open_pending = true

            if up_queue_len == 0 and down_queue_len == 0 and self.current_direction ~= "none" then
                self.current_direction = "none"
                self:update_indicators()
            end

            if self.pending_pickup_direction then
                self.current_direction = self.pending_pickup_direction
                self.pending_pickup_direction = nil
                self:update_indicators()
            end
        end

        os.sleep(0.1)
    end
end

function App:update_leds()
    -- Hall
    for floor, state in pairs(self.hall_leds) do
        local lcu = self:find_lcu_by_floor(floor)

        if lcu then
            self.server:send(lcu.computer_id, {
                type = "$UPDATE HALL BUTTON LED",
                button = "up",
                state = state.up,
            })

            self.server:send(lcu.computer_id, {
                type = "$UPDATE HALL BUTTON LED",
                button = "down",
                state = state.down,
            })
        end
    end

    -- Car
    self.server:send(self.ccu, {
        type = "$UPDATE CAR BUTTON LEDS",
        leds = self.car_leds,
    })
end

function App:draw_term()
    term.clear()
    term.setCursorPos(1, 1)

    local pending = "-"

    if self.is_doors_close_pending then
        pending = "CLOSING"
    end

    if self.is_doors_open_pending then
        pending = "OPENING"
    end

    local lines = {
        "CURRENT FLOOR: " .. self.current_floor,
        "CURRENT FLOOR NAME: " .. self.current_floor_name,
        "CURRENT DIRECTION: " .. self.current_direction,
        "DOORS STATE: " .. self.doors_state .. "; " .. pending,
        "SHOULD OPEN DOORS: " .. tostring(self.should_open_doors),
        "UP QUEUE ENTRIES LENGTH: " .. self.up_queue:length(),
        "DOWN QUEUE ENTRIES LENGTH: " .. self.down_queue:length(),
        "POSITION: " .. self.vfd:get_position(),
        "MOVING: " .. tostring(not self.vfd:is_finished())
    }
    
    for _, line in ipairs(lines) do
        print(line)
    end
end

return app