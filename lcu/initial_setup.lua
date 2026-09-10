local socket_client = require("common.socket_client")
local logger = require("common.logger")
local config = require("config")

-- Logger
local setup_log = logger.new("Setup")

local function initial_setup()
    -- Modem setup
    local modem = peripheral.wrap(config.MODEM_SIDE)

    if not modem then
        setup_log:error("Failed to wrap modem")
        print("Failed to find modem, check your hardware and config")
        return false
    end

    -- Socket client
    local client = socket_client.new(config.DEVICE_NAME, modem)
    client:set_channel(config.CHANNEL)

    -- "TUI"
    -- TODO: Make some nice TUI

    term.clear()
    term.setCursorPos(1, 1)
    print("Settings not found, initialization")
    print("Searching for EMCUs")

    local emcus = client:lookup("EMCU")

    if #emcus == 0 then
        print("EMCUs not found, check you hardware")

        return false
    else
        print("Found", #emcus, "EMCUs, select yours:\n")

        for i, emcu in ipairs(emcus) do
            local first_part = tostring(i) .. ") "

            print(string.format("%sComputer ID: %d", first_part, emcu.computer_id))
            if emcu.computer_label then
                print(string.format("%sLabel: %s", string.rep(" ", #first_part), emcu.computer_label))
            end
            print("---------")
        end

        print("\nType number of EMCU")
        write("> ")
        local selected_emcu = tonumber(read())

        settings.set("lcu.emcu_computer_id", emcus[selected_emcu].computer_id)
        settings.save()

        print("\nSet label for this landing (useful to recognize)")
        write("> ")
        local label = read()

        os.setComputerLabel(label)

        print("\nSetup done")
        setup_log:info("Setup done")

        return true
    end
end

return initial_setup