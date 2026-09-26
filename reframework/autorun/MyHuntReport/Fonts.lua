local Log = require("MyHuntReport.Log")

local Fonts = {}

local FILES = {
    regular = "MyHuntReport/Pretendard-Regular.otf",
    semibold = "MyHuntReport/Pretendard-SemiBold.otf",
}

local ROLES = {
    header = { file = "semibold", ratio = 26 / 18 },
    body = { file = "regular", ratio = 1 },
    meta = { file = "regular", ratio = 1 },
    small = { file = "regular", ratio = 1 },
}

local ROLE_ORDER = { "header", "body", "meta", "small" }

local RANGES = {
    0x0020, 0x00FF,
    0x1100, 0x11FF,
    0x2605, 0x2605,
    0x3000, 0x303F,
    0x3130, 0x318F,
    0xAC00, 0xD7A3,
    0xFF00, 0xFFEF,
    0,
}

local cache = {}
local status = { loaded = false, lastError = nil, sizes = {} }

local function load(path, size)
    local key = path .. ":" .. size
    if cache[key] ~= nil then
        if cache[key] == false then return nil end
        return cache[key]
    end
    if type(imgui.load_font) ~= "function" then
        cache[key] = false
        status.sizes[key] = false
        status.lastError = "imgui.load_font unavailable"
        Log.error("font load skipped: imgui.load_font unavailable", "font:api")
        return nil
    end
    local ok, font = pcall(imgui.load_font, path, size, RANGES)
    if not ok or not font then
        cache[key] = false
        status.sizes[key] = false
        status.lastError = tostring(font)
        Log.error("font load failed for " .. key .. ": " .. tostring(font), "font:" .. key)
        return nil
    end
    cache[key] = font
    status.sizes[key] = true
    status.loaded = true
    return font
end

function Fonts.size(role, base)
    local spec = ROLES[role]
    if not spec then error("unknown font role " .. tostring(role), 2) end
    return math.floor(base * spec.ratio + 0.5)
end

function Fonts.centerNudge(size)
    return math.floor(size * 0.07 + 0.5)
end

local function roleFont(role)
    return function(base)
        return load(FILES[ROLES[role].file], Fonts.size(role, base))
    end
end

Fonts.header = roleFont("header")
Fonts.body = roleFont("body")
Fonts.meta = roleFont("meta")
Fonts.small = roleFont("small")

function Fonts.preload(base)
    for _, role in ipairs(ROLE_ORDER) do Fonts[role](base) end
end

function Fonts.push(font)
    if not font then return false end
    local ok = pcall(imgui.push_font, font)
    return ok
end

function Fonts.pop(pushed)
    if pushed then pcall(imgui.pop_font) end
end

function Fonts.status()
    return status
end

return Fonts
