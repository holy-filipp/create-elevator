local button = require("common.button")
local draw_utils = require("common.draw_utils")
local morefonts = require("common.morefonts")
local logger = require("common.logger")

local LEFT_ARROW_CHAR = string.char(tonumber("0x11"))
local RIGHT_ARROW_CHAR = string.char(tonumber("0x10"))
local UP_ARROW_CHAR = string.char(tonumber("0x1E"))
local DOWN_ARROW_CHAR = string.char(tonumber("0x1F"))
local HORIZONTAL_SEP_CHAR = string.char(tonumber("0x8C"))
local DIRECTION_INDICATORS = {
    up = UP_ARROW_CHAR,
    down = DOWN_ARROW_CHAR,
    none = "",
}
local COLUMNS = 4
local BUTTONS_PER_COLUMN = 6
local BUTTONS_PER_PAGE = BUTTONS_PER_COLUMN * COLUMNS

local Display = {}
local display = {}

function display.new(monitor)
    local self = {
        monitor = monitor,
        floor = "--",
        direction = "none",
        events = {},
        buttons = {},
        log = logger.new("Display"),
        page = 1,
        leds = {},
    }
    setmetatable(self, { __index = Display })
    
    self:init()
    
    return self
end

function Display:init()
    self.monitor.setTextScale(0.5)
    self.w, self.h = self.monitor.getSize()

    -- Add buttons
    self.door_open_btn = button.new(3, self.h - 1, 3, 1, colors.black, colors.lightGray, string.format("%s|%s", LEFT_ARROW_CHAR, RIGHT_ARROW_CHAR))
    self.door_open_btn:on("click", function ()
        self:trigger_event("doors_open")
    end)

    self.doors_close_btn = button.new(self.w - 4, self.h - 1, 3, 1, colors.black, colors.lightGray, string.format("%s|%s", RIGHT_ARROW_CHAR, LEFT_ARROW_CHAR))
    self.doors_close_btn:on("click", function ()
        self:trigger_event("doors_close")
    end)

    self.btn_prev = button.new(7, self.h - 1, 1, 1, colors.black, colors.lightGray, LEFT_ARROW_CHAR)
    self.btn_prev:on("click", function ()
        self:change_page("prev")
    end)
    
    self.btn_next = button.new(9, self.h - 1, 1, 1, colors.black, colors.lightGray, RIGHT_ARROW_CHAR)
    self.btn_next:on("click", function ()
        self:change_page("next")
    end)
end

function Display:set_floor(floor)
    self.floor = floor
    self:render()
end

function Display:set_direction(direction)
    self.direction = direction
    self:render()
end

function Display:on(name, callback_fn)
    self.events[#self.events+1] = {
        name = name,
        callback_function = callback_fn,
    }
end

function Display:trigger_event(name, ...)
    for _, event in ipairs(self.events) do
        if event.name == name then
            event.callback_function(...)
        end
    end
end

function Display:render()
    self.monitor.setBackgroundColor(colors.white)
    self.monitor.clear()
    self.monitor.setTextColor(colors.black)
    morefonts.writeOn(self.monitor, string.format("%s%s", DIRECTION_INDICATORS[self.direction], self.floor), nil, 5)

    button.render(self.monitor)

    -- Separator
    self.monitor.setBackgroundColor(colors.white)
    self.monitor.setTextColor(colors.lightGray)
    self.monitor.setCursorPos(3, self.h - 2)
    self.monitor.write(string.rep(HORIZONTAL_SEP_CHAR, self.w - 4))
end

function Display:set_floors(floors)
    self.floors = floors
    self.total_pages = math.floor(#floors / BUTTONS_PER_PAGE + 0.5) + 1
    self.log:debug("Floors updated, total pages", self.total_pages)

    self:draw_buttons_page(1)
end

function Display:is_floor_led_on(floor)
    return self.leds and self.leds[floor] or false
end

function Display:draw_buttons_page(page)
    self.log:debug("Drawing buttons page", page)

    -- Clear buttons
    if #self.buttons ~= 0 then
        for _, btn in ipairs(self.buttons) do
            btn:remove()
        end
    end
    self.buttons = {}

    local start = ((page - 1) * BUTTONS_PER_PAGE) + 1
    local floors = {table.unpack(self.floors, start, start + BUTTONS_PER_PAGE - 1)}

    local x, y = 3, self.h - 3
    local counter = 0

    for _, floor in ipairs(floors) do
        local btn = button.new(x, y, 2, 1, colors.black, self:is_floor_led_on(floor.floor) and colors.lime or colors.lightGray, floor.floor_name)
        btn:on("click", function ()
            self:trigger_event("car_call", floor)
        end)
        btn.meta = floor
        self.buttons[#self.buttons+1] = btn

        counter = counter + 1
        y = y - 2

        if counter == BUTTONS_PER_COLUMN then
            counter = 0
            x = x + 3
            y = self.h - 3
        end
    end

    self:render()
end

function Display:change_page(direction)
    if direction == "prev" and self.page > 1 then
        self.page = self.page - 1
        self:draw_buttons_page(self.page)
    end

    if direction == "next" and self.page < self.total_pages then
        self.page = self.page + 1
        self:draw_buttons_page(self.page)
    end
end

function Display:update_leds()
    for _, btn in ipairs(self.buttons) do
        if self:is_floor_led_on(btn.meta.floor) then
            btn:set_text_color(colors.lime)
        else
            btn:set_text_color(colors.lightGray)
        end
    end

    self:render()
end

function Display:set_leds(leds)
    self.leds = leds
    self:update_leds()
end

return display