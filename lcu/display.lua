local button = require("common.button")
local draw_utils = require("common.draw_utils")
local morefonts = require("common.morefonts")

local UP_ARROW_CHAR = string.char(tonumber("0x1E"))
local DOWN_ARROW_CHAR = string.char(tonumber("0x1F"))
local DIRECTION_INDICATORS = {
    up = UP_ARROW_CHAR,
    down = DOWN_ARROW_CHAR,
    none = "",
}

local Display = {}
local display = {}

function display.new(monitor)
    local self = {
        monitor = monitor,
        floor = "--",
        direction = "none",
        events = {},
    }
    setmetatable(self, { __index = Display })
    
    self:init()
    
    return self
end

function Display:init()
    self.monitor.setTextScale(0.5)
    self.w, self.h = self.monitor.getSize()

    -- Add buttons
    self.up_btn = button.new(draw_utils.center(self.w, 3) + 1, 16, 3, 3, colors.black, colors.white, UP_ARROW_CHAR)
    self.up_btn:on("click", function ()
        self:trigger_event("click_up")
    end)

    self.down_btn = button.new(draw_utils.center(self.w, 3) + 1, 20, 3, 3, colors.black, colors.white, DOWN_ARROW_CHAR)
    self.down_btn:on("click", function ()
        self:trigger_event("click_down")
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

function Display:change_button_led(button, state)
    if button == "up" then
        self.up_btn:set_text_color(state and colors.lime or colors.white)
    elseif button == "down" then
        self.down_btn:set_text_color(state and colors.lime or colors.white)
    end

    self:render()
end

function Display:on(name, callback_fn)
    self.events[#self.events+1] = {
        name = name,
        callback_function = callback_fn,
    }
end

function Display:set_as_final(side)
    if side == "lower" then
        self.down_btn:remove()
        self.up_btn:set_position(draw_utils.center(self.w, 3) + 1, 18)
    end

    if side == "upper" then
        self.up_btn:remove()
        self.down_btn:set_position(draw_utils.center(self.w, 3) + 1, 18)
    end
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
end

return display