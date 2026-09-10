local REPO_BASE_URL = "https://api.github.com/repos/holy-filipp/create-elevator/contents"
local COMMON_PATH = "/common"
local INSTALL_OPTIONS = {
    {
        name = "Elevator Main Controller Unit (EMCU)",
        description = "The \"brain\" of elevator.",
        path = "/emcu",
    },
    {
        name = "Car Controller Unit (CCU)",
        description = "The controller, which is fitted to the elevator car, controls the doors and the display panel inside the car.",
        path = "/ccu",
    },
    {
        name = "Landing Controller Unit (LCU)",
        description = "The controller, which installed on each floor, is responsible foor on-floor display.",
        path = "/lcu",
    },
}
local ARROW_RIGHT = string.char(tonumber("0x10"))

local selected_option = 1

local function create_startup(path)
    local f = fs.open("startup.lua", "w")
    f.write(string.format("shell.run(\"%s\")", path))
end

local function draw_menu()
    term.clear()
    term.setCursorPos(1, 1)

    print("CC: Tweaked Create Elevator installer")
    print("Use arrows to navigate")
    print("")

    for i, option in ipairs(INSTALL_OPTIONS) do
        local before = i == selected_option and ARROW_RIGHT .. " " or ""

        print(before .. option.name)

        if i == selected_option then
            print(option.description)
        end

        print()
    end
end

local function draw_status(path)
    term.clear()
    term.setCursorPos(1, 1)
    print("Downloading", path)
end

local function remove_installer()
    fs.delete("/installer.lua")
end

local function download_file(url, path_to_save)
    draw_status(path_to_save)

    local request = http.get(url)
    local code, _ = request.getResponseCode()

    if code ~= 200 then
        print("Failed to get", url)
        return
    end

    local content = request.readAll()

    local f = fs.open(path_to_save, "w")
    f.write(content)
    f.close()
end

local function download_folder(path, custom_path)
    local request = http.get(REPO_BASE_URL .. path)
    local code, _ = request.getResponseCode()

    if code ~= 200 then
        print("Failed to get", REPO_BASE_URL .. path)
        return
    end

    local data = textutils.unserializeJSON(request.readAll())

    for _, object in ipairs(data) do
        if object.type == "file" then
            download_file(object.download_url, custom_path and fs.combine(custom_path, object.path) or object.path)
        end

        if object.type == "folder" then
            download_folder(object.url, custom_path)
        end
    end
end

local function proceed_install()
    local option = INSTALL_OPTIONS[selected_option]

    download_folder(option.path)
    download_folder(COMMON_PATH, fs.combine("/", option.path))

    term.clear()
    term.setCursorPos(1, 1)
    print("Creating startup.lua")

    create_startup(fs.combine("/", option.path, "main.lua"))

    print("Removing installer")

    remove_installer()

    print("Done")
end

draw_menu()

while true do
    local _, key = os.pullEvent("key")

    if key == keys.down then
        selected_option = selected_option + 1

        if selected_option > #INSTALL_OPTIONS then
            selected_option = 1
        end
    end

    if key == keys.up then
        selected_option = selected_option - 1

        if selected_option < 1 then
            selected_option = #INSTALL_OPTIONS
        end
    end

    if key == keys.enter then
        proceed_install()

        break
    end

    draw_menu()
end