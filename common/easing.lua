local easing = {}

function easing.easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local f = -2 * t + 2
        return 1 - (f * f * f) / 2
    end
end

return easing