local Theme = require("MyHuntReport.Theme")
local Fonts = require("MyHuntReport.Fonts")

local UiText = {}

local ELLIPSIS = "…"

function UiText.colored(text, color)
    local pushed = pcall(imgui.push_style_color, 0, color)
    local ok, err = pcall(imgui.text, text)
    if pushed then pcall(imgui.pop_style_color, 1) end
    if not ok then error(err, 0) end
end

function UiText.inFont(font, text, color)
    local pushed = Fonts.push(font)
    local ok, err = pcall(UiText.colored, text, color or Theme.colors.text)
    Fonts.pop(pushed)
    if not ok then error(err, 0) end
end

local function measure(text)
    local ok, size = pcall(imgui.calc_text_size, text)
    if ok and size and type(size.x) == "number" then return size.x end
    return nil
end

function UiText.width(text)
    return measure(text)
end

local function trimUtf8(text)
    local length = #text
    if length == 0 then return text end
    local cut = length
    while cut > 1 do
        local byte = text:byte(cut)
        if byte < 0x80 or byte > 0xBF then break end
        cut = cut - 1
    end
    return text:sub(1, cut - 1)
end

function UiText.clip(text, maxWidth)
    local width = measure(text)
    if not width or width <= maxWidth then return text end
    local body = text
    while #body > 0 do
        body = trimUtf8(body)
        local candidate = body .. ELLIPSIS
        local w = measure(candidate)
        if not w then return text end
        if w <= maxWidth then return candidate end
    end
    return ELLIPSIS
end

return UiText
