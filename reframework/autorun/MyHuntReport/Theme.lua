local Hdr = require("MyHuntReport.Hdr")

local Theme = {}

function Theme.rgb(hex, alpha)
    local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then error("invalid color " .. tostring(hex), 2) end
    local a = math.floor((alpha or 1) * 255 + 0.5)
    return (a << 24) | (tonumber(b, 16) << 16) | (tonumber(g, 16) << 8) | tonumber(r, 16)
end

local rgb = Theme.rgb

Theme.PALETTE = {
    windowBg = { "#1B1815", 0.95 },
    rule = { "#35302A", 1 },
    barTrack = { "#2A2520", 1 },
    rowStripe = { "#FFFFFF", 0.04 },
    text = { "#ECE4D6", 1 },
    textMuted = { "#9A9083", 1 },
    accent = { "#D8B46B", 1 },
    accentDim = { "#4A3F2A", 1 },
    physical = { "#D8B46B", 1 },
    element = { "#5BB8A5", 1 },
    fixed = { "#E08A45", 1 },
    status = { "#A88BD6", 1 },
    warning = { "#D9695A", 1 },
    childBg = { "#000000", 0 },
    scrollbarBg = { "#000000", 0 },
    transparent = { "#000000", 0 },
}

Theme.colors = {}

local appliedNits = nil

local function fill(nits)
    for name, source in pairs(Theme.PALETTE) do
        if nits then
            Theme.colors[name] = Hdr.convert(source[1], source[2], nits)
        else
            Theme.colors[name] = rgb(source[1], source[2])
        end
    end
end

fill(nil)

function Theme.apply(nits)
    if nits == appliedNits then return false end
    fill(nits)
    appliedNits = nits
    return true
end

Theme.metrics = {
    padding = 24,
    rounding = 6,
    itemSpacing = 10,
    rowSpacing = 9,
    stripeRounding = 3,
    barHeight = 8,
    barGap = 2,
    columnGap = 32,
    percentColumnWidth = 72,
    scrollbarWidth = 14,
    minWindowWidth = 720,
    topBarHeight = 36,
    titleGap = 12,
    iconButton = 36,
    iconSize = 20,
    iconStroke = 2,
    navButtonWidth = 92,
    chipGap = 14,
    sectionGap = 16,
    tileGap = 16,
    labelGap = 2,
    ruleGap = 12,
    footerGap = 12,
    dotRadius = 4,
    legendGap = 28,
    procGap = 20,
    historyRowHeight = 36,
    historyPadding = 10,
    historyTimeWidth = 150,
    historyStarsWidth = 48,
    historyGap = 16,
    historyWeaponShare = 0.4,
}

Theme.WINDOW_FLAGS = 1 | 2 | 8 | 32 | 64 | 256

local COL_TEXT = 0
local COL_WINDOW_BG = 2
local COL_CHILD_BG = 3
local COL_BORDER = 5
local COL_FRAME_BG = 7
local COL_SCROLLBAR_BG = 14
local COL_SCROLLBAR_GRAB = 15
local COL_BUTTON = 21
local COL_BUTTON_HOVERED = 22
local COL_BUTTON_ACTIVE = 23

local function pushColor(token, index, color)
    local ok = pcall(imgui.push_style_color, index, color)
    if ok then token.colors = token.colors + 1 end
end

local function pushVar(token, name, value)
    local enum = imgui.ImGuiStyleVar
    if type(enum) ~= "table" then return end
    local index = enum[name]
    if type(index) ~= "number" then return end
    local ok = pcall(imgui.push_style_var, index, value)
    if ok then token.vars = token.vars + 1 end
end

local function pushVectorVar(token, name, x, y)
    local ok, value = pcall(Vector2f.new, x, y)
    if ok then pushVar(token, name, value) end
end

local function popToken(token)
    if token.colors > 0 then pcall(imgui.pop_style_color, token.colors) end
    if token.vars > 0 then pcall(imgui.pop_style_var, token.vars) end
end

function Theme.pushWindow()
    local token = { colors = 0, vars = 0 }
    local c, m = Theme.colors, Theme.metrics
    pushColor(token, COL_WINDOW_BG, c.windowBg)
    pushColor(token, COL_CHILD_BG, c.childBg)
    pushColor(token, COL_BORDER, c.rule)
    pushColor(token, COL_TEXT, c.text)
    pushColor(token, COL_FRAME_BG, c.barTrack)
    pushColor(token, COL_SCROLLBAR_BG, c.scrollbarBg)
    pushColor(token, COL_SCROLLBAR_GRAB, c.rule)
    pushColor(token, COL_BUTTON, c.transparent)
    pushColor(token, COL_BUTTON_HOVERED, c.accentDim)
    pushColor(token, COL_BUTTON_ACTIVE, c.accentDim)
    pushVar(token, "Alpha", 1.0)
    pushVar(token, "WindowRounding", m.rounding)
    pushVar(token, "WindowBorderSize", 1)
    pushVectorVar(token, "WindowPadding", m.padding, m.padding)
    pushVar(token, "FrameRounding", 4)
    pushVar(token, "FrameBorderSize", 1)
    pushVectorVar(token, "ItemSpacing", m.itemSpacing, m.itemSpacing)
    return token
end

function Theme.popWindow(token)
    popToken(token)
end

function Theme.pushRows()
    local token = { colors = 0, vars = 0 }
    pushVectorVar(token, "ItemSpacing", Theme.metrics.itemSpacing, Theme.metrics.rowSpacing)
    return token
end

function Theme.popRows(token)
    popToken(token)
end

function Theme.pushListRows()
    local token = { colors = 0, vars = 0 }
    pushColor(token, COL_BUTTON, Theme.colors.transparent)
    pushColor(token, COL_BUTTON_HOVERED, Theme.colors.accentDim)
    pushColor(token, COL_BUTTON_ACTIVE, Theme.colors.accentDim)
    pushVar(token, "FrameBorderSize", 0)
    pushVar(token, "FrameRounding", 4)
    pushVectorVar(token, "ItemSpacing", 0, 0)
    return token
end

function Theme.popListRows(token)
    popToken(token)
end

function Theme.pushBar(color, rounding)
    local token = { colors = 0, vars = 0 }
    pushColor(token, COL_BUTTON, color)
    pushColor(token, COL_BUTTON_HOVERED, color)
    pushColor(token, COL_BUTTON_ACTIVE, color)
    pushVar(token, "FrameRounding", rounding or 0)
    pushVar(token, "FrameBorderSize", 0)
    pushVectorVar(token, "ItemSpacing", 0, 0)
    return token
end

function Theme.pushWarningButton()
    local token = { colors = 0, vars = 0 }
    pushColor(token, COL_BUTTON, Theme.colors.warning)
    pushColor(token, COL_BUTTON_HOVERED, Theme.colors.warning)
    pushColor(token, COL_BUTTON_ACTIVE, Theme.colors.warning)
    return token
end

function Theme.popBar(token)
    popToken(token)
end

return Theme
