local Theme = require("MyHuntReport.Theme")
local Fonts = require("MyHuntReport.Fonts")

local UiText = {}

local ELLIPSIS = "…"
local CACHE_LIMIT = 4096

local widths, clips, cached = {}, {}, 0

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

function UiText.resetCache()
    widths, clips, cached = {}, {}, 0
end

local function reserve()
    if cached >= CACHE_LIMIT then UiText.resetCache() end
    cached = cached + 1
end

local function bucket(store, key)
    local found = store[key]
    if found == nil then
        found = {}
        store[key] = found
    end
    return found
end

function UiText.width(text)
    if type(text) ~= "string" then return measure(text) end
    local context = Fonts.context()
    local known = widths[context]
    local width = known and known[text]
    if width ~= nil then return width end
    width = measure(text)
    if width == nil then return nil end
    reserve()
    bucket(widths, context)[text] = width
    return width
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

local function clipText(text, maxWidth)
    local width = measure(text)
    if not width then return text, false end
    if width <= maxWidth then return text, true end
    local body = text
    while #body > 0 do
        body = trimUtf8(body)
        local candidate = body .. ELLIPSIS
        local w = measure(candidate)
        if not w then return text, false end
        if w <= maxWidth then return candidate, true end
    end
    return ELLIPSIS, true
end

function UiText.clip(text, maxWidth)
    if type(text) ~= "string" then return (clipText(text, maxWidth)) end
    local context = Fonts.context()
    local byContext = clips[context]
    local byWidth = byContext and byContext[maxWidth]
    local clipped = byWidth and byWidth[text]
    if clipped ~= nil then return clipped end
    local complete
    clipped, complete = clipText(text, maxWidth)
    if not complete then return clipped end
    reserve()
    bucket(bucket(clips, context), maxWidth)[text] = clipped
    return clipped
end

return UiText
