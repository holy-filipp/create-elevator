local SocketClient = {}
local socket_client = {}

function socket_client.new(device_name, modem)
    local self = {
        modem = modem,
        computer_id = os.getComputerID(),
        computer_label = os.getComputerLabel(),
        events = {},
        last_connection_try = os.clock(),
        device_name = device_name,
    }
    setmetatable(self, { __index = SocketClient })
    return self
end

function SocketClient:send_internal(data)
    self.modem.transmit(self.channel, self.channel, data)
end

function SocketClient:set_keep_connection(keep)
    self.keep_connection = keep
end

function SocketClient:set_channel(channel)
    self.channel = channel
end

function SocketClient:lookup(device_name)
    self.modem.open(self.channel)
    
    self:send_internal({
        type = "$LOOKUP",
        device_name = device_name,
    })

    local timer = os.startTimer(2)
    local result = {}

    while true do
        local event = {os.pullEvent()}

        if event[1] == "modem_message" then
            local message = event[5]

            if message.type == "$LOOKUP RESPONSE" then
                result[#result+1] = {
                    computer_id = message.computer_id,
                    device_name = message.device_name,
                    computer_label = message.computer_label,
                }
            end
        end

        if event[1] == "timer" and event[2] == timer then
            break
        end
    end

    os.cancelTimer(timer)
    self.modem.close(self.channel)

    return result
end

function SocketClient:on(name, callback_fn)
    self.events[#self.events+1] = {
        name = name,
        callback_function = callback_fn,
    }
end

function SocketClient:trigger_event(name, ...)
    local args = {...}
    
    for _, event in ipairs(self.events) do
        if event.name == name then
            if self.spawn_function then
                self.spawn_function(function ()
                    event.callback_function(table.unpack(args))    
                end)
            else
                event.callback_function(table.unpack(args))
            end
        end
    end
end

function SocketClient:event_loop_internal()
    local handlers = {
        ["$CONNECT REJECT"] = function (message)
            if self.computer_id ~= message.destination_computer_id then return end

            self:trigger_event("error", "Failed to connect to server", message.reason)
        end,
        ["$CONNECT ACK"] = function (message)
            if self.computer_id ~= message.destination_computer_id then return end

            self.connected_computer = {
                computer_id = message.computer_id,
                device_name = message.device_name,
                latest_ping = os.clock(),
                ping_send = false,
            }

            self:trigger_event("connect", self.connected_computer)
        end,
        ["$PING PONG"] = function (message)
            if self.computer_id ~= message.destination_computer_id then return end

            if not self.connected_computer then return end

            self.connected_computer.latest_ping = os.clock()
            self.connected_computer.ping_send = false
        end,
        ["$PAYLOAD"] = function (message)
            if self.computer_id ~= message.destination_computer_id then return end
            if self.connected_computer.computer_id ~= message.computer_id then return end
        
            self:trigger_event("message", message.payload, {
                computer_id = message.computer_id,
                device_name = message.device_name,
            })
        end,
    }

    while true do
        local _, _, _, _, message, _ = os.pullEvent("modem_message")
        local message_type = message.type

        if handlers[message_type] then
            handlers[message_type](message)
        end
    end
end

function SocketClient:tick_loop_internal()
    while true do
        if self.connected_computer then
            if not self.connected_computer.ping_send then
                self:send_internal({
                    type = "$PING",
                    computer_id = self.computer_id,
                    destination_computer_id = self.connected_computer.computer_id,
                })

                self.connected_computer.ping_send = true
            end

            if self.connected_computer.latest_ping + 3 <= os.clock() then
                self:trigger_event("disconnect", self.connected_computer, "Timed out")

                self.connected_computer = nil
            end
        end

        if not self.connected_computer and self.keep_connection and self.last_connection_try + 3 <= os.clock() and self.want_to_connect_computer_id then
            self:connect_internal(self.want_to_connect_computer_id)
        end

        os.sleep(1)
    end
end

function SocketClient:connect_internal(computer_id)
    self.last_connection_try = os.clock()
    
    self:send_internal({
        type = "$CONNECT",
        computer_id = self.computer_id,
        destination_computer_id = computer_id,
        device_name = self.device_name,
        computer_label = self.computer_label,
    })
end

function SocketClient:connect(computer_id, spawn_fn)
    self.modem.open(self.channel)
    self.spawn_function = spawn_fn

    self.want_to_connect_computer_id = computer_id
    self:connect_internal(computer_id)

    parallel.waitForAll(function ()
        self:event_loop_internal()
    end, function ()
        self:tick_loop_internal()
    end)
end

function SocketClient:send(payload)
    if not self.connected_computer then return end

    self:send_internal({
        type = "$PAYLOAD",
        computer_id = self.computer_id,
        destination_computer_id = self.connected_computer.computer_id,
        device_name = self.device_name,
        payload = payload,
    })
end

return socket_client