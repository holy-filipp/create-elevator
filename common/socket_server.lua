local SocketServer = {}
local socket_server = {}

function socket_server.new(device_name, modem)
    local self = {
        modem = modem,
        device_name = device_name,
        computer_id = os.getComputerID(),
        connected_computers = {},
        events = {},
        accepted_devices = {},
        accepted_devices_count = 0,
        computer_label = os.getComputerLabel(),
    }
    setmetatable(self, { __index = SocketServer })
    return self
end

function SocketServer:set_channel(channel)
    self.channel = channel
end

function SocketServer:send_internal(data)
    self.modem.transmit(self.channel, self.channel, data)
end

function SocketServer:accept(device_name)
    self.accepted_devices[device_name] = true
    self.accepted_devices_count = self.accepted_devices_count + 1
end

function SocketServer:kill()
    os.queueEvent("socket_server_kill")
    self.kill = true
end

function SocketServer:on(name, callback_fn)
    self.events[#self.events+1] = {
        name = name,
        callback_function = callback_fn,
    }
end

function SocketServer:trigger_event(name, ...)
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

function SocketServer:event_loop_internal()
    local handlers = {
        ["$LOOKUP"] = function (message)
            if self.device_name ~= message.device_name then return end

            self:send_internal({
                type = "$LOOKUP RESPONSE",
                computer_id = self.computer_id,
                device_name = self.device_name,
                computer_label = self.computer_label,
            })
        end,
        ["$CONNECT"] = function (message)
            if self.computer_id ~= message.destination_computer_id then return end
            if self.accepted_devices_count ~= 0 and not self.accepted_devices[message.device_name] then
                self:send_internal({
                    type = "$CONNECT REJECT",
                    destination_computer_id = message.computer_id,
                    reason = "This server doesn't accept connection from this device type",
                })
                
                return
            end

            self.connected_computers[message.computer_id] = {
                computer_id = message.computer_id,
                computer_label = message.computer_label,
                device_name = message.device_name,
                latest_ping = os.clock(),
            }

            self:send_internal({
                type = "$CONNECT ACK",
                computer_id = self.computer_id,
                device_name = self.device_name,
                destination_computer_id = message.computer_id,
            })

            self:trigger_event("connect", self.connected_computers[message.computer_id])
        end,
        ["$PING"] = function (message)
            if self.computer_id ~= message.destination_computer_id then return end

            if not self.connected_computers[message.computer_id] then return end

            self.connected_computers[message.computer_id].latest_ping = os.clock()

            self:send_internal({
                type = "$PING PONG",
                computer_id = self.computer_id,
                destination_computer_id = message.computer_id,
            })
        end,
        ["$PAYLOAD"] = function (message)
            if self.computer_id ~= message.destination_computer_id then return end
            if not self.connected_computers[message.computer_id] then return end
        
            self:trigger_event("message", message.payload, {
                computer_id = message.computer_id,
                device_name = message.device_name,
            }, function (payload)
                self:send(message.computer_id, payload)
            end)
        end,
    }

    while true do
        local event, _, _, _, message, _ = os.pullEvent()
        
        if event == "modem_message" then
           local message_type = message.type

            if handlers[message_type] then
                handlers[message_type](message)
            end 
        end

        if event == "socket_server_kill" then
            break
        end
    end
end

function SocketServer:tick_loop_internal()
    while true do
        if self.kill then break end

        for computer_id, data in pairs(self.connected_computers) do
            if data.latest_ping + 1 <= os.clock() then
                self.connected_computers[computer_id] = nil

                self:trigger_event("disconnect", data, "Timed out")
            end
        end
        
        os.sleep(0.1)
    end
end

function SocketServer:listen(spawn_fn)
    self.modem.open(self.channel)
    self.spawn_function = spawn_fn

    parallel.waitForAll(function ()
        self:event_loop_internal()
    end, function ()
        self:tick_loop_internal()
    end)
end

function SocketServer:send(computer_id, payload)
    if not self.connected_computers[computer_id] then return end

    self:send_internal({
        type = "$PAYLOAD",
        computer_id = self.computer_id,
        destination_computer_id = computer_id,
        device_name = self.device_name,
        payload = payload,
    })
end

function SocketServer:broadcast(payload)
    for _, computer in pairs(self.connected_computers) do
        self:send(computer.computer_id, payload)
    end
end

return socket_server