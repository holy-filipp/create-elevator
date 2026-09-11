local config = {}

config.CHANNEL = 1337
config.DEVICE_NAME = "EMCU"
config.MODEM_SIDE = "top"
config.MOTOR_PERIPHERAL_NAME = "left"
config.BUNDLED_SIDE = "right"
config.VFD_ACCELERATION_TIME = 1
config.VFD_DECELERATION_TIME = 1
config.UFL_COLOR = colors.black -- Upper Final Limit
config.LFL_COLOR = colors.white -- Lower Final Limit
config.LEARNING_RPM = 48
config.NORMAL_RPM = 60
config.DOORS_WAIT_TIME = 8

return config