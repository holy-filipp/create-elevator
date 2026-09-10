local VFD = {}
local vfd = {}

local BLOCKS_PER_REV = 2.34375
local LUT_SAMPLES = 512
local DIRECTIONS = {
    fwd = 1,
    rev = -1,
}

local function build_integral_lut(fn, samples)
    local lut = {}
    local cum = 0
    local du = 1 / samples
    local prev_v = fn(0)

    lut[1] = 0

    for i = 1, samples do
        local u = i * du
        local v = fn(u)

        cum = cum + (prev_v + v) * 0.5 * du
        lut[i + 1] = cum
        prev_v = v
    end

    return lut, cum
end

local function sample_lut(lut, samples, u)
    u = math.max(0, math.min(1, u))

    local pos = u * samples
    local i0 = math.floor(pos)
    local frac = pos - i0
    local a = lut[i0 + 1]
    local b = lut[math.min(i0 + 2, samples + 1)]

    return a + (b - a) * frac
end

local function to_rps(rpm)
    return rpm / 60
end

local function clamp_rpm(rpm)
    if rpm == 0 then
        return 0
    end

    local sign = rpm < 0 and -1 or 1

    return math.max(math.abs(rpm), 1) * sign
end

function vfd.new(motor)
    local self = {
        motor = motor,
        position = 0,
    }
    setmetatable(self, { __index = VFD })
    return self
end

function VFD:set_acceleration_time(t)
    self.acceleration_time = t
end

function VFD:set_deceleration_time(t)
    self.deceleration_time = t
end

function VFD:set_easing_function(fn)
    self.easing_function = fn
    self.lut, self.lut_k = build_integral_lut(self.easing_function, LUT_SAMPLES)
end

function VFD:move(direction, blocks_to_pass, rpm_target)
    if self.stupid_move_data then return end
    
    rpm_target = math.abs(rpm_target)

    local revs_acceleration = to_rps(rpm_target) * self.acceleration_time * self.lut_k
    local revs_decelaration = to_rps(rpm_target) * self.deceleration_time * self.lut_k
    local blocks_acceleration = revs_acceleration * BLOCKS_PER_REV
    local blocks_deceleration = revs_decelaration * BLOCKS_PER_REV
    local blocks_plateau = blocks_to_pass - blocks_acceleration - blocks_deceleration
    local rpm_actual = rpm_target
    local time_plateau

    if blocks_plateau < 0 then
        rpm_actual = (blocks_to_pass / BLOCKS_PER_REV) * 60 / (self.lut_k * (self.acceleration_time + self.deceleration_time))
        blocks_acceleration = to_rps(rpm_actual) * self.acceleration_time * self.lut_k * BLOCKS_PER_REV
        blocks_deceleration = blocks_to_pass - blocks_acceleration
        time_plateau = 0
    else
        time_plateau = blocks_plateau / BLOCKS_PER_REV * 60 / rpm_target
    end

    local time = self.acceleration_time + time_plateau + self.deceleration_time

    self.current_move = {
        time = time,
        time_plateau = time_plateau,
        direction = DIRECTIONS[direction],
        rpm_requested = rpm_target,
        rpm_target = rpm_actual,
        blocks_acceleration = blocks_acceleration,
        blocks_plateau = math.max(blocks_plateau, 0),
        blocks_deceleration = blocks_deceleration,
        blocks_to_pass = blocks_to_pass,
        was_capped = blocks_plateau < 0,
        start_position = self.position or 0,
        finished = false,
    }
end

function VFD:eval(elapsed)
    local time = math.min(elapsed, self.current_move.time)
    local position, rpm_now

    if time <= self.acceleration_time then
        local u = (self.acceleration_time > 0) and (time / self.acceleration_time) or 1
        local eu = sample_lut(self.lut, LUT_SAMPLES, u)
        local revs = to_rps(self.current_move.rpm_target) * self.acceleration_time * eu

        position = revs * BLOCKS_PER_REV
        rpm_now = self.easing_function(u) * self.current_move.rpm_target
    elseif time <= self.acceleration_time + self.current_move.time_plateau then
        local dt = time - self.acceleration_time

        position = self.current_move.blocks_acceleration + to_rps(self.current_move.rpm_target) * dt * BLOCKS_PER_REV
        rpm_now = self.current_move.rpm_target
    else
        local td = time - self.acceleration_time - self.current_move.time_plateau
        local u = math.min((self.deceleration_time > 0) and (td / self.deceleration_time) or 1, 1)
        local eu_rev = sample_lut(self.lut, LUT_SAMPLES, 1 - u)
        local revs_deceleration_so_far = to_rps(self.current_move.rpm_target) * self.deceleration_time * (self.lut_k - eu_rev)
        
        position = self.current_move.blocks_acceleration + self.current_move.blocks_plateau + revs_deceleration_so_far * BLOCKS_PER_REV
        rpm_now = self.easing_function(1 - u) * self.current_move.rpm_target
    end

    position = position * self.current_move.direction
    rpm_now = rpm_now * self.current_move.direction

    local finished = elapsed >= self.current_move.time

    if finished then
        rpm_now = 0
        position = self.current_move.blocks_to_pass * self.current_move.direction
    end

    self.current_move.rpm = rpm_now
    self.current_move.position = position
    self.current_move.finished = finished
    self.position = self.current_move.start_position + position
    
    self.motor.setGeneratedSpeed(clamp_rpm(rpm_now))
end

function VFD:is_finished()
    return not self.current_move and true or self.current_move.finished
end

function VFD:stupid_move(direction, rpm)
    direction = direction == "fwd" and 1 or -1
    
    self.stupid_move_data = {
        direction = direction,
        rpm = rpm,
        start_time = os.clock(),
    }

    self.motor.setGeneratedSpeed(math.abs(rpm) * direction)
end

function VFD:stupid_blocks_passed()
    if not self.stupid_move_data then return end

    local time = os.clock() - self.stupid_move_data.start_time
    local revs_per_second = to_rps(self.stupid_move_data.rpm)
    local revs = revs_per_second * time
    local blocks = revs * BLOCKS_PER_REV

    return blocks * self.stupid_move_data.direction
end 

function VFD:stupid_stop()
    if not self.stupid_move_data then return end

    local blocks = self:stupid_blocks_passed()
    self.stupid_move_data = nil

    self.motor.setGeneratedSpeed(0)

    return blocks
end

function VFD:set_position(pos)
    self.position = pos
end

function VFD:get_position()
    return self.position
end

return vfd