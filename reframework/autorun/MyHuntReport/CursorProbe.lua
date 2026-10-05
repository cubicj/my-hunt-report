local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local ReportWindow = require("MyHuntReport.ReportWindow")

local CursorProbe = {}

local MOUSE_TYPE = "via.hid.Mouse"
local GET_SHOW = "get_ShowCursor()"
local GET_IN_CLIENT = "get_InWindowClientArea()"
local SET_SHOW = "set_ShowCursor(System.Boolean)"
local FIELDS = { "show", "inClient", "menu", "hover" }
local MAX_OVERRIDE_LINES = 10

local previous = nil
local active = nil
local skipped = false

local function text(value)
    if value == nil then return "?" end
    return tostring(value)
end

local function readBoolean(signature)
    local value = Game.callStatic(MOUSE_TYPE, signature)
    if type(value) == "boolean" then return value end
    return nil
end

local function readMenu()
    local ok, drawing = pcall(reframework.is_drawing_ui, reframework)
    if ok and type(drawing) == "boolean" then return drawing end
    return nil
end

function CursorProbe.contains(x, y, width, height, pointX, pointY)
    return pointX >= x and pointX < x + width and pointY >= y and pointY < y + height
end

local function readHover()
    local x, y, width, height = ReportWindow.bounds()
    if x == nil then return false end
    local ok, inside = pcall(function()
        local mouse = imgui.get_mouse()
        return CursorProbe.contains(x, y, width, height, mouse.x, mouse.y)
    end)
    if ok and type(inside) == "boolean" then return inside end
    return nil
end

local function setShow(value)
    local _, err = Game.callStatic(MOUSE_TYPE, SET_SHOW, value)
    if err and active and not active.setFailed then
        active.setFailed = true
        Log.trace("cursor set failed " .. tostring(err))
    end
end

local function endHover(now)
    local hover = active
    setShow(hover.saved)
    active = nil
    local readback = readBoolean(GET_SHOW)
    Log.trace(string.format("cursor hover end at %.3f duration=%.3f overrides=%d restored=%s readback=%s",
        now, now - hover.startedAt, hover.overrides, text(hover.saved), text(readback)))
    return readback
end

local function startHover(now, saved)
    active = { saved = saved, startedAt = now, lastSetAt = now, overrides = 0, setFailed = false }
    setShow(true)
    local readback = readBoolean(GET_SHOW)
    Log.trace(string.format("cursor hover start at %.3f saved=%s readback=%s", now, text(saved), text(readback)))
    return readback
end

local function reassert(now)
    active.overrides = active.overrides + 1
    if active.overrides <= MAX_OVERRIDE_LINES then
        Log.trace(string.format("cursor override #%d at %.3f after=%.3f",
            active.overrides, now, now - active.lastSetAt))
    end
    setShow(true)
    active.lastSetAt = now
    return readBoolean(GET_SHOW)
end

function CursorProbe.update()
    if not Log.isDeveloperMode() then
        if active then endHover(Game.uptime()) end
        previous = nil
        skipped = false
        return
    end
    local now = Game.uptime()
    local current = {
        show = readBoolean(GET_SHOW),
        inClient = readBoolean(GET_IN_CLIENT),
        menu = readMenu(),
        hover = readHover(),
    }
    local first = previous == nil
    if first then
        Log.trace(string.format("cursor snapshot at %.3f show=%s inClient=%s menu=%s hover=%s",
            now, text(current.show), text(current.inClient), text(current.menu), text(current.hover)))
    end
    local ownShow = false
    if current.hover ~= true then skipped = false end
    if active then
        if current.hover ~= true then
            current.show = endHover(now)
            ownShow = true
        elseif current.show == false then
            current.show = reassert(now)
            ownShow = true
        end
    elseif current.hover == true and current.menu == false and not skipped then
        if current.show == nil then
            if not skipped then
                skipped = true
                Log.trace("cursor hover start skipped saved=?")
            end
        else
            current.show = startHover(now, current.show)
            ownShow = true
        end
    end
    if not first then
        for _, field in ipairs(FIELDS) do
            if current[field] ~= previous[field] and not (field == "show" and ownShow) then
                Log.trace(string.format("cursor change %s %s -> %s at %.3f",
                    field, text(previous[field]), text(current[field]), now))
            end
        end
    end
    previous = current
end

return CursorProbe
