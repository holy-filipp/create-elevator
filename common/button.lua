local Button = {}
local button = {}

local buttons = {}

function button.new(x, y, w, h, bg_color, text_color, text)
    local self = {
        x = x,
        y = y,
        w = w,
        h = h,
        bg_color = bg_color,
        text_color = text_color,
        text = text,
        events = {},
        idx = #buttons+1,
    }
    setmetatable(self, { __index = Button })
    
    buttons[self.idx] = self

    return self
end

function button.render(m)
    for _, btn in pairs(buttons) do
        btn:render(m)
    end
end

function button.click_handler()
    while true do
        local event, _, x, y = os.pullEvent()

        if event == "monitor_touch" or event == "mouse_click" then
            for _, btn in pairs(buttons) do
                if btn:is_pressed(x, y) then
                    btn:trigger_event("click")
                end
            end
        end
    end
end

function Button:render(m)
    m.setBackgroundColor(self.bg_color)
    m.setTextColor(self.text_color)

    local text_w, text_x, text_y

    if self.text then
        text_w = #self.text
        text_x = math.floor((self.w - text_w) / 2)
        text_y = math.floor((self.h - 1) / 2)
    end

    for py = 0, self.h - 1 do
        local y = py + self.y
        
        for px = 0, self.w - 1 do
            local x = px + self.x

            m.setCursorPos(x, y)

            if self.text and px >= text_x and px < text_x + text_w and py == text_y then
                local char_pos = px - text_x
                local char = string.sub(self.text, char_pos + 1)
                
                m.write(char)
            else
                m.write(" ")
            end
        end
    end
end

function Button:on(name, callback_fn)
    self.events[#self.events+1] = {
        name = name,
        callback_function = callback_fn,
    }
end

function Button:trigger_event(name, ...)
    for _, event in ipairs(self.events) do
        if event.name == name then
           event.callback_function(...) 
        end
    end
end

function Button:is_pressed(x, y)
    local x_match = x >= self.x and x < self.x + self.w
    local y_match = y >= self.y and y < self.y + self.h

    return x_match and y_match
end

function Button:set_text_color(color)
    self.text_color = color
end

function Button:remove()
    buttons[self.idx] = nil
    self = nil
end

function Button:set_position(x, y)
    self.x = x
    self.y = y
end

return button