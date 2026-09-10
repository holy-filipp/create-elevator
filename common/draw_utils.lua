local draw_utils = {}

function draw_utils.center(panel_w, object_w)
    return math.floor((panel_w - object_w) / 2)
end

return draw_utils