local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Draw = require("MyHuntReport.Draw")

local HdrProbe = {}

local DISPLAY = "via.render.DisplaySettings"
local OPTION = "app.OptionUtil"

HdrProbe.OPTION_IDS = { 154, 253, 254, 257, 258 }

HdrProbe.SOURCES = {
    { field = "hdrMode", type = DISPLAY, signature = "get_HDRMode()" },
    { field = "hdrEnable", type = DISPLAY, signature = "get_HDRDisplayModeEnable()" },
    { field = "colorSpace", type = DISPLAY, signature = "get_ColorSpace()" },
    { field = "rendererColorSpace", type = "via.render.Renderer", signature = "get_ColorSpace()" },
}

for _, id in ipairs(HdrProbe.OPTION_IDS) do
    HdrProbe.SOURCES[#HdrProbe.SOURCES + 1] = { field = "opt" .. id, type = OPTION, signature = "getOptionValue(app.Option.ID)", arg = id }
    HdrProbe.SOURCES[#HdrProbe.SOURCES + 1] = { field = "rate" .. id, type = OPTION, signature = "getOptionValueRate(app.Option.ID)", arg = id }
end

HdrProbe.SWATCHES = {
    { "text", "#ECE4D6" },
    { "textMuted", "#9A9083" },
    { "accent", "#D8B46B" },
    { "element", "#5BB8A5" },
    { "fixed", "#E08A45" },
    { "status", "#A88BD6" },
    { "warning", "#D9695A" },
    { "windowBg", "#1B1815" },
    { "white", "#FFFFFF" },
    { "grey", "#808080" },
}

HdrProbe.NITS_MIN = 80
HdrProbe.NITS_MAX = 500

local WINDOW_ID = "My Hunt Report HDR Probe"
local CELL_WIDTH = 120
local CELL_HEIGHT = 28
local CELL_GAP = 8

local PQ_M1 = 0.1593017578125
local PQ_M2 = 78.84375
local PQ_C1 = 0.8359375
local PQ_C2 = 18.8515625
local PQ_C3 = 18.6875

local installed = false
local previous = {}
local controls = { nits = 200, gamma = "srgb" }

local function trace(text)
    Log.trace("hdr " .. text)
end

function HdrProbe.decode(value, gamma)
    if gamma == "2.2" then return value ^ 2.2 end
    if value <= 0.04045 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
end

function HdrProbe.pqEncode(nits)
    local y = (nits / 10000) ^ PQ_M1
    return ((PQ_C1 + PQ_C2 * y) / (1 + PQ_C3 * y)) ^ PQ_M2
end

function HdrProbe.channels(hex)
    local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then error("invalid color " .. tostring(hex), 2) end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

function HdrProbe.convertChannels(hex, nits, gamma)
    local r, g, b = HdrProbe.channels(hex)
    r, g, b = HdrProbe.decode(r, gamma), HdrProbe.decode(g, gamma), HdrProbe.decode(b, gamma)
    local r2 = 0.6274 * r + 0.3293 * g + 0.0433 * b
    local g2 = 0.0691 * r + 0.9195 * g + 0.0114 * b
    local b2 = 0.0164 * r + 0.0880 * g + 0.8956 * b
    return HdrProbe.pqEncode(r2 * nits), HdrProbe.pqEncode(g2 * nits), HdrProbe.pqEncode(b2 * nits)
end

function HdrProbe.pack(r, g, b, alpha)
    local function byte(value) return math.floor(value * 255 + 0.5) end
    return (byte(alpha or 1) << 24) | (byte(b) << 16) | (byte(g) << 8) | byte(r)
end

function HdrProbe.original(hex, alpha)
    local r, g, b = HdrProbe.channels(hex)
    return HdrProbe.pack(r, g, b, alpha)
end

function HdrProbe.converted(hex, nits, gamma, alpha)
    local r, g, b = HdrProbe.convertChannels(hex, nits, gamma)
    return HdrProbe.pack(r, g, b, alpha)
end

function HdrProbe.snapshot()
    if not Log.isDeveloperMode() then return {} end
    local snapshot = {}
    for _, source in ipairs(HdrProbe.SOURCES) do
        local value
        if source.arg ~= nil then
            value = Game.callStatic(source.type, source.signature, source.arg)
        else
            value = Game.callStatic(source.type, source.signature)
        end
        if value == nil then value = "?" end
        snapshot[source.field] = value
    end
    return snapshot
end

function HdrProbe.formatSnapshot(snapshot)
    local parts = {}
    for _, source in ipairs(HdrProbe.SOURCES) do
        parts[#parts + 1] = source.field .. "=" .. tostring(snapshot[source.field])
    end
    return table.concat(parts, " ")
end

function HdrProbe.controls()
    return controls
end

function HdrProbe.install()
    if installed then return end
    installed = true
    if not Log.isDeveloperMode() then return end
    previous = HdrProbe.snapshot()
    trace("snapshot at " .. tostring(Game.uptime()) .. " " .. HdrProbe.formatSnapshot(previous))
end

local function logChanges()
    local snapshot = HdrProbe.snapshot()
    local now = nil
    for _, source in ipairs(HdrProbe.SOURCES) do
        local field = source.field
        if snapshot[field] ~= previous[field] then
            now = now or tostring(Game.uptime())
            trace("change " .. field .. " " .. tostring(previous[field]) .. " -> " .. tostring(snapshot[field]) .. " at " .. now)
        end
    end
    previous = snapshot
end

local function drawControls()
    local changedNits, nits = imgui.slider_int("Reference white (nits)", controls.nits, HdrProbe.NITS_MIN, HdrProbe.NITS_MAX)
    local changedGamma, pure = imgui.checkbox("Pure gamma 2.2 decode", controls.gamma == "2.2")
    if changedNits then controls.nits = nits end
    if changedGamma then controls.gamma = pure and "2.2" or "srgb" end
    if changedNits or changedGamma then
        trace("control nits=" .. tostring(controls.nits) .. " gamma=" .. controls.gamma)
    end
end

local function drawSwatches()
    imgui.text("original | converted")
    for _, swatch in ipairs(HdrProbe.SWATCHES) do
        local name, hex = swatch[1], swatch[2]
        local screen = imgui.get_cursor_screen_pos()
        imgui.invisible_button("##hdrswatch" .. name, { CELL_WIDTH * 2 + CELL_GAP, CELL_HEIGHT })
        Draw.rect("hdrorig" .. name, screen.x, screen.y, CELL_WIDTH, CELL_HEIGHT, HdrProbe.original(hex), 0)
        Draw.rect("hdrconv" .. name, screen.x + CELL_WIDTH + CELL_GAP, screen.y, CELL_WIDTH, CELL_HEIGHT,
            HdrProbe.converted(hex, controls.nits, controls.gamma), 0)
        imgui.same_line()
        imgui.text(name)
    end
end

local function pushOpaque()
    local enum = imgui.ImGuiStyleVar
    if type(enum) ~= "table" or type(enum.Alpha) ~= "number" then return false end
    return (pcall(imgui.push_style_var, enum.Alpha, 1.0))
end

local function drawWindow()
    local pushed = pushOpaque()
    local okBegin, err = pcall(imgui.begin_window, WINDOW_ID, true, 0)
    if not okBegin then
        Log.error("hdr probe window begin failed: " .. tostring(err), "hdrprobe:begin")
        if pushed then pcall(imgui.pop_style_var, 1) end
        return
    end
    local okDraw, drawErr = pcall(function()
        drawControls()
        drawSwatches()
    end)
    pcall(imgui.end_window)
    if pushed then pcall(imgui.pop_style_var, 1) end
    if not okDraw then Log.error("hdr probe draw failed: " .. tostring(drawErr), "hdrprobe:draw") end
end

function HdrProbe.update()
    if not Log.isDeveloperMode() then return end
    logChanges()
    drawWindow()
end

function HdrProbe.resetForTests()
    installed = false
    previous = {}
    controls = { nits = 200, gamma = "srgb" }
end

return HdrProbe
