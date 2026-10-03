local Game = require("MyHuntReport.Game")

local Hdr = {}

Hdr.FALLBACK_NITS = 200

local DISPLAY = "via.render.DisplaySettings"

local PQ_M1 = 0.1593017578125
local PQ_M2 = 78.84375
local PQ_C1 = 0.8359375
local PQ_C2 = 18.8515625
local PQ_C3 = 18.6875

local function decode(value)
    if value <= 0.04045 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
end

local function pqEncode(nits)
    local y = (nits / 10000) ^ PQ_M1
    return ((PQ_C1 + PQ_C2 * y) / (1 + PQ_C3 * y)) ^ PQ_M2
end

local function byte(value)
    return math.floor(value * 255 + 0.5)
end

function Hdr.active()
    return Game.callStatic(DISPLAY, "get_HDRMode()") == true
end

function Hdr.referenceWhite()
    local nits = Game.callStatic(DISPLAY, "get_WhitePaperNitsForOverlay()")
    if type(nits) == "number" and nits > 0 then return nits end
    return Hdr.FALLBACK_NITS
end

function Hdr.targetNits(setting)
    if setting == "off" then return nil end
    if setting == "on" or Hdr.active() then return Hdr.referenceWhite() end
    return nil
end

function Hdr.convert(hex, alpha, nits)
    local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then error("invalid color " .. tostring(hex), 2) end
    r, g, b = decode(tonumber(r, 16) / 255), decode(tonumber(g, 16) / 255), decode(tonumber(b, 16) / 255)
    local red = pqEncode((0.6274 * r + 0.3293 * g + 0.0433 * b) * nits)
    local green = pqEncode((0.0691 * r + 0.9195 * g + 0.0114 * b) * nits)
    local blue = pqEncode((0.0164 * r + 0.0880 * g + 0.8956 * b) * nits)
    return (byte(alpha or 1) << 24) | (byte(blue) << 16) | (byte(green) << 8) | byte(red)
end

return Hdr
