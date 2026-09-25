local PREFIX = "[MyHuntReport]"
local MAX_REPEATS = 5

local Log = {}

local developerMode = false
local counts = {}

local function emit(level, key, message)
    local count = (counts[key] or 0) + 1
    counts[key] = count
    if count > MAX_REPEATS then return false end
    local suffix = ""
    if count == MAX_REPEATS then suffix = " (further repeats suppressed)" end
    if level == "error" then
        log.error(PREFIX .. " Error: " .. message .. suffix)
    else
        log.info(PREFIX .. " " .. message .. suffix)
    end
    return true
end

function Log.setDeveloperMode(enabled)
    developerMode = enabled == true
end

function Log.isDeveloperMode()
    return developerMode
end

function Log.error(message, key)
    local text = tostring(message)
    return emit("error", key or text, text)
end

function Log.debug(message, key)
    if not developerMode then return false end
    local text = tostring(message)
    return emit("debug", key or text, text)
end

function Log.trace(message)
    if not developerMode then return false end
    log.info(PREFIX .. " " .. tostring(message))
    return true
end

function Log.resetCounts()
    counts = {}
end

function Log.count(key)
    return counts[key] or 0
end

return Log
