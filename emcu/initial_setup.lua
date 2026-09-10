local socket_server = require("common.socket_server")
local logger = require("common.logger")
local config = require("config")

-- Logger
local setup_log = logger.new("Setup")

local function initial_setup()
    -- Modem
    local modem = peripheral.wrap(config.MODEM_SIDE)

    if not modem then
        setup_log:error("Failed to wrap modem")
        print("Failed to find modem, check your hardware and config")
        return false
    end

    -- Socket
    local server = socket_server.new(config.DEVICE_NAME, modem) -- Elevator Main Controller Unit
    server:set_channel(config.CHANNEL)
    server:accept("LCU") -- Landing Controller Unit
    server:accept("CCU") -- Car Controller Unit

    -- UI

    term.clear()
    term.setCursorPos(1, 1)
    print("Settings not found, initialization")
    print("\nType number of landings")
    write("> ")
    local landings = tonumber(read())
    settings.set("emcu.landings", landings)
    settings.save()

    local function update_connection_info(connected_lcus, is_ccu_connected)
        term.clear()
        term.setCursorPos(1, 1)
        print(string.format("Waiting for connecting from all LCUs (%d/%d)", connected_lcus, landings))
        print(string.format("Waiting for connection from CCU (%s)", is_ccu_connected and "OK" or string.rep(string.char(tonumber("0x7F")), 2)))
    end

    local connected_landings = 0
    local is_ccu_connected = false
    update_connection_info(connected_landings, is_ccu_connected)

    local lcus = {}
    local ccu

    server:on("connect", function (computer)
        if computer.device_name == "LCU" then
            setup_log:info("LCU connected", computer)
        
            if connected_landings ~= landings then
                lcus[#lcus+1] = {
                    computer_id = computer.computer_id,
                    computer_label = computer.computer_label,
                }
                connected_landings = connected_landings + 1
                update_connection_info(connected_landings, is_ccu_connected)
            end
        end

        if computer.device_name == "CCU" then
            setup_log:info("CCU connected", computer)

            if not ccu then
                ccu = computer.computer_id
                is_ccu_connected = true

                update_connection_info(connected_landings, is_ccu_connected)
            end
        end

        if connected_landings == landings and is_ccu_connected then
            term.clear()
            term.setCursorPos(1, 1)
            print("All LCUs and CCU connected \n")

            for _, lcu in ipairs(lcus) do
                print(string.format("Configuring LCU %d, label: %s\n", lcu.computer_id, lcu.computer_label))
                print("Enter floor number, used to calculate position, only numbers accepted")
                write("> ")
                local floor = tonumber(read())

                print("Enter floor display name, same as floor number if empty")
                write("> ")
                local floor_name = read()

                lcu.floor = floor
                lcu.floor_name = floor_name == "" and tostring(floor) or floor_name

                print(string.format("Floor: %d, name: %s", lcu.floor, lcu.floor_name))

                print("----------\n")
            end

            print(string.format("Do you accept CCU %d? (y/n)", ccu))
            write("> ")
            local accept_ccu = read()

            if accept_ccu == "n" then
                print("Cancel")
                settings.clear()
                settings.save()
                server:kill()
                return
            end

            local file = fs.open(".emcu_hardware_memory.json", "w")
            file.write(textutils.serializeJSON({
                known_lcus = lcus,
                known_ccu = ccu,
            }))
            file.close()

            term.clear()
            term.setCursorPos(1, 1)
            print("Done")

            server:kill()
        end
    end)

    parallel.waitForAll(function (spawn)
       server:listen(spawn)
    end)
end

return initial_setup