local Hotkey = require("MyHuntReport.Hotkey")
local Log = require("MyHuntReport.Log")
local ReportWindow = require("MyHuntReport.ReportWindow")

local MouseNav = {}

local BUTTONS = {
    { index = 3, name = "back" },
    { index = 4, name = "forward" },
}

local wasDown = {}

local function inside(x, y, width, height, mouse)
    return x ~= nil and mouse.x >= x and mouse.x < x + width and mouse.y >= y and mouse.y < y + height
end

local function hovered()
    local x, y, width, height = ReportWindow.bounds()
    if x == nil then return false end
    local fx, fy, fw, fh = ReportWindow.filterBounds()
    local ok, result = pcall(function()
        local mouse = imgui.get_mouse()
        return inside(x, y, width, height, mouse) or inside(fx, fy, fw, fh, mouse)
    end)
    return ok and result == true
end

local function press(button)
    local from = ReportWindow.screen()
    local hover = hovered()
    local applied, reason = false, "ok"
    if from == nil then
        reason = "not_open"
    elseif Hotkey.isCapturing() then
        reason = "capturing"
    elseif not hover then
        reason = "not_hovered"
    else
        applied = ReportWindow[button.name]() == true
        if not applied then reason = "no_target" end
    end
    Log.trace(string.format("mouse nav button=%s hover=%s from=%s to=%s applied=%s reason=%s",
        button.name, tostring(hover), from or "closed", ReportWindow.screen() or "closed", tostring(applied), reason))
end

function MouseNav.update(isDown)
    for _, button in ipairs(BUTTONS) do
        local down = isDown(button.index) == true
        if down and not wasDown[button.index] then press(button) end
        wasDown[button.index] = down
    end
end

return MouseNav
