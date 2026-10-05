local Theme = require("MyHuntReport.Theme")
local Fonts = require("MyHuntReport.Fonts")
local Draw = require("MyHuntReport.Draw")
local Locale = require("MyHuntReport.Locale")
local Log = require("MyHuntReport.Log")

local HistoryFilterWindow = {}

local AXES = {
    { key = "weapons", columns = 3 },
    { key = "levels", columns = 5 },
    { key = "species", columns = 3 },
    { key = "variants", columns = 4 },
}

local function textIn(font, text, color)
    local pushed = Fonts.push(font)
    local colored = pcall(imgui.push_style_color, 0, color or Theme.colors.text)
    local ok, err = pcall(imgui.text, text)
    if colored then pcall(imgui.pop_style_color, 1) end
    Fonts.pop(pushed)
    if not ok then error(err, 0) end
end

function HistoryFilterWindow.placement(bounds, display, scale)
    if not bounds then return { centered = true, x = display.x / 2, y = display.y / 2 } end
    local width = math.floor(Theme.metrics.filterWidth * scale) + Theme.metrics.padding * 2
    local x = bounds.x + bounds.width + Theme.metrics.filterWindowGap
    if x + width > display.x then x = bounds.x - width - Theme.metrics.filterWindowGap end
    return { centered = false, x = x, y = bounds.y }
end

local function drawContents(ctx, options, labels, selection, change, clipName)
    local m = Theme.metrics
    local width = math.floor(m.filterWidth * ctx.scale)
    local top = imgui.get_cursor_pos()
    textIn(ctx.fonts.header, Locale.text("history_filter"))
    local clearText = Locale.text("history_filter_clear_all")
    local size = imgui.calc_text_size(clearText)
    local clearWidth = size.x + m.itemSpacing * 2
    imgui.set_cursor_pos(Vector2f.new(top.x + width - m.iconButton - m.historyGap - clearWidth, top.y))
    if imgui.button(clearText .. "##filterClearAll", { clearWidth, m.iconButton }) then change() end
    imgui.set_cursor_pos(Vector2f.new(top.x + width - m.iconButton, top.y))
    local screen = imgui.get_cursor_screen_pos()
    local active = Draw.active()
    local colored = pcall(imgui.push_style_color, 0, Theme.colors.textMuted)
    local ok, closed = pcall(imgui.button, active and "##filterClose" or "X##filterClose", { m.iconButton, m.iconButton })
    if colored then pcall(imgui.pop_style_color, 1) end
    if not ok then error(closed, 0) end
    if active then
        local okHover, hovered = pcall(imgui.is_item_hovered)
        local color = okHover and hovered and Theme.colors.text or Theme.colors.textMuted
        local inset = (m.iconButton - m.iconSize) / 2
        Draw.icon("filterClose", "close", screen.x + inset, screen.y + inset, m.iconSize, color, m.iconStroke)
    end
    imgui.set_cursor_pos(Vector2f.new(top.x, top.y + m.topBarHeight))
    imgui.invisible_button("##filterWidth", { width, m.titleGap })
    for axisIndex, axis in ipairs(AXES) do
        local lineTop = imgui.get_cursor_pos()
        local clearHeight = math.floor(m.filterClearHeight * ctx.scale)
        imgui.set_cursor_pos(Vector2f.new(top.x, lineTop.y + (clearHeight - ctx.sizes.small) / 2))
        textIn(ctx.fonts.small, Locale.text("history_filter_" .. axis.key), Theme.colors.textMuted)
        if next(selection[axis.key]) then
            local axisClearText = Locale.text("history_filter_clear")
            local axisClearWidth = imgui.calc_text_size(axisClearText).x + m.itemSpacing * 3
            imgui.set_cursor_pos(Vector2f.new(top.x + width - axisClearWidth, lineTop.y))
            if imgui.button(axisClearText .. "##filterClear" .. axis.key, { axisClearWidth, clearHeight }) then change(axis.key) end
        end
        imgui.set_cursor_pos(Vector2f.new(top.x, lineTop.y + clearHeight + m.itemSpacing))
        local values = options[axis.key]
        local bottom
        if #values == 0 then
            textIn(ctx.fonts.body, "-", Theme.colors.textMuted)
            bottom = imgui.get_cursor_pos().y
        else
            local origin = imgui.get_cursor_pos()
            local columnWidth = width / axis.columns
            local rowY, nextY = origin.y, origin.y
            for index, value in ipairs(values) do
                local column = (index - 1) % axis.columns
                if column == 0 then rowY = nextY end
                imgui.set_cursor_pos(Vector2f.new(origin.x + column * columnWidth, rowY))
                local label = clipName(labels[axis.key][value], columnWidth - ctx.sizes.body - m.itemSpacing * 2)
                local changed, checked = imgui.checkbox(label .. "##filter" .. axis.key .. ":" .. tostring(value), selection[axis.key][value] == true)
                if changed then change(axis.key, value, checked) end
                nextY = math.max(nextY, imgui.get_cursor_pos().y)
            end
            bottom = nextY
        end
        if axisIndex < #AXES then
            imgui.set_cursor_pos(Vector2f.new(top.x, bottom + m.sectionGap))
        end
    end
    return not closed
end

function HistoryFilterWindow.draw(ctx, options, labels, selection, change, reportBounds, clipName)
    pcall(function()
        local place = HistoryFilterWindow.placement(reportBounds, imgui.get_display_size(), ctx.scale)
        imgui.set_next_window_pos({ place.x, place.y }, 8, place.centered and { 0.5, 0.5 } or { 0, 0 })
    end)
    local token = Theme.pushWindow()
    local okBegin, opened = pcall(imgui.begin_window, "##MyHuntReportFilterWindow", true, Theme.WINDOW_FLAGS)
    local bounds
    if okBegin then
        local pushed = Fonts.push(ctx.fonts.body)
        local ok, result = pcall(drawContents, ctx, options, labels, selection, change, clipName)
        Fonts.pop(pushed)
        pcall(function()
            local pos, size = imgui.get_window_pos(), imgui.get_window_size()
            if type(pos.x) == "number" and type(pos.y) == "number" and type(size.x) == "number" and type(size.y) == "number" then
                bounds = { x = pos.x, y = pos.y, width = size.x, height = size.y }
            end
        end)
        pcall(imgui.end_window)
        opened = opened and ok and result
        if not ok then Log.error("history filter window draw failed: " .. tostring(result), "history:filterDraw") end
    else
        Log.error("history filter window begin failed: " .. tostring(opened), "history:filterBegin")
        opened = false
    end
    Theme.popWindow(token)
    return opened == true, opened and bounds or nil
end

return HistoryFilterWindow
