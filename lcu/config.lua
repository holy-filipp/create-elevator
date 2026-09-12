local logger = require("common.logger")

local config = {}

config.LOG_TO_FILE = false
config.LOG_LEVEL = logger.level_info

config.DEVICE_NAME = "LCU"
config.CHANNEL = 1337
config.MODEM_SIDE = "top"
config.SENSOR_REDSTONE_SIDE = "bottom"
config.MONITOR_PERIPHERAL_NAME = "back"

return config