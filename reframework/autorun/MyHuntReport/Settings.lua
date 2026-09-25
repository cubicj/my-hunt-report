local Log = require("MyHuntReport.Log")

local Settings = {}

Settings.FILE = "MyHuntReport/settings.json"

local DEFAULTS = {
    autoPopup = true,
    closeOnQuestStart = true,
    toggleKey = 118,
    fontSize = 18,
    windowX = -1,
    windowY = -1,
    language = "auto",
    developerMode = false,
}

local RANGES = {
    toggleKey = { 1, 254 },
    fontSize = { 14, 36 },
}

local INTEGER_KEYS = { toggleKey = true, fontSize = true }
local LANGUAGES = { auto = true, en = true, ko = true }

local current = {}
local pendingBackupText = nil

local function clamp(key, value)
    if INTEGER_KEYS[key] then value = math.floor(value + 0.5) end
    local range = RANGES[key]
    if not range then return value end
    if value < range[1] then return range[1] end
    if value > range[2] then return range[2] end
    return value
end

local function sanitize(raw)
    local result = {}
    for key, default in pairs(DEFAULTS) do
        local value = raw[key]
        if type(value) ~= type(default) then
            value = default
        elseif type(value) == "number" then
            value = clamp(key, value)
        elseif key == "language" and not LANGUAGES[value] then
            value = default
        end
        result[key] = value
    end
    return result
end

local function backupCorruptFile(text)
    local backupPath = string.format("MyHuntReport/settings.invalid-%d.json", os.time())
    local ok, err = pcall(fs.write, backupPath, text)
    if not ok or err == false then
        Log.error("settings backup failed: " .. tostring(err))
        return false
    end
    return true
end

local function applyDefaultsAfterCorruption(text)
    Log.error("settings file could not be parsed; defaults restored")
    local backedUp = backupCorruptFile(text)
    if backedUp then
        pendingBackupText = nil
    else
        pendingBackupText = text
    end
    current = sanitize({})
    Log.setDeveloperMode(current.developerMode)
    if backedUp then Settings.save() end
    return current
end

function Settings.load()
    local ok, data = pcall(json.load_file, Settings.FILE)
    if not ok then
        Log.error("settings load failed: " .. tostring(data))
        data = nil
    end
    if data == nil then
        local okRead, text = pcall(fs.read, Settings.FILE)
        if okRead and type(text) == "string" and text:match("%S") then
            return applyDefaultsAfterCorruption(text)
        end
        pendingBackupText = nil
        current = sanitize({})
        Log.setDeveloperMode(current.developerMode)
        if okRead and type(text) == "string" then Settings.save() end
        return current
    end
    if type(data) ~= "table" then
        local okRead, text = pcall(fs.read, Settings.FILE)
        if not okRead or type(text) ~= "string" then
            Log.error("settings file could not be parsed and could not be read back; defaults applied in memory")
            current = sanitize({})
            Log.setDeveloperMode(current.developerMode)
            return current
        end
        return applyDefaultsAfterCorruption(text)
    end
    pendingBackupText = nil
    local legacyScale = data.fontScale
    local migrated = data.fontSize == nil and type(legacyScale) == "number"
    if migrated then data.fontSize = math.floor(18 * legacyScale + 0.5) end
    current = sanitize(data)
    Log.setDeveloperMode(current.developerMode)
    if migrated then Settings.save() end
    return current
end

function Settings.save()
    if pendingBackupText ~= nil then
        if not backupCorruptFile(pendingBackupText) then
            Log.error("settings save skipped: original file not backed up yet", "settings:pending-backup")
            return false
        end
        pendingBackupText = nil
    end
    local ok, result = pcall(json.dump_file, Settings.FILE, current)
    if not ok or result ~= true then
        Log.error("settings save failed: " .. tostring(result), "settings:save")
        return false
    end
    return true
end

function Settings.get()
    return current
end

function Settings.set(key, value)
    if DEFAULTS[key] == nil then return false end
    local merged = {}
    for k, v in pairs(current) do merged[k] = v end
    merged[key] = value
    current = sanitize(merged)
    Log.setDeveloperMode(current.developerMode)
    return Settings.save()
end

function Settings.defaults()
    local copy = {}
    for k, v in pairs(DEFAULTS) do copy[k] = v end
    return copy
end

return Settings
