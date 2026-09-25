local Log = require("MyHuntReport.Log")
local Theme = require("MyHuntReport.Theme")

local Draw = {}

Draw.CORNERS = { none = 256, left = 80, right = 160, all = 240 }

local DOT_SEGMENTS = 16

local state = { probed = false, available = false, failed = false, forced = false }

local function detect()
    if type(imgui.get_window_draw_list) ~= "function" then return false end
    local list = imgui.get_window_draw_list()
    return list ~= nil and list.add_rect_filled ~= nil
end

local function probe()
    if state.probed then return end
    state.probed = true
    local ok, available = pcall(detect)
    state.available = ok and available == true
    Log.debug("window draw list " .. (state.available and "available" or "unavailable"), "draw:probe")
end

function Draw.active()
    if state.forced then return false end
    probe()
    return state.available and not state.failed
end

function Draw.statusText()
    if state.forced then return "forced fallback" end
    if not state.probed then return "not probed" end
    if state.failed then return "failed" end
    if state.available then return "available" end
    return "unavailable"
end

function Draw.setForced(flag)
    state.forced = flag == true
end

function Draw.isForced()
    return state.forced
end

function Draw.resetForTests()
    state = { probed = false, available = false, failed = false, forced = false }
end

local function withList(fn)
    if not Draw.active() then return false end
    local ok, err = pcall(function()
        fn(imgui.get_window_draw_list())
    end)
    if not ok then
        state.failed = true
        Log.error("draw list call failed, using button fallback: " .. tostring(err), "draw:fail")
        return false
    end
    return true
end

local function fallbackButton(id, x, y, w, h, color, rounding)
    local ok, err = pcall(function()
        local saved = imgui.get_cursor_pos()
        imgui.set_cursor_screen_pos({ x, y })
        local token = Theme.pushBar(color, rounding or 0)
        local okButton, buttonErr = pcall(imgui.button, "##draw" .. id, { w, h })
        Theme.popBar(token)
        imgui.set_cursor_pos(Vector2f.new(saved.x, saved.y))
        if not okButton then error(buttonErr, 0) end
    end)
    if not ok then Log.error("draw fallback failed: " .. tostring(err), "draw:fallback") end
end

function Draw.rect(id, x, y, w, h, color, rounding, corners)
    if w <= 0 or h <= 0 then return end
    if withList(function(list)
        list:add_rect_filled({ x, y }, { x + w, y + h }, color, rounding or 0, corners or Draw.CORNERS.all)
    end) then return end
    fallbackButton(id, x, y, w, h, color, rounding)
end

function Draw.dot(id, cx, cy, radius, color)
    if withList(function(list)
        list:add_circle_filled({ cx, cy }, radius, color, DOT_SEGMENTS)
    end) then return end
    fallbackButton(id, cx - radius, cy - radius, radius * 2, radius * 2, color, radius)
end

function Draw.line(id, x1, y1, x2, y2, color, thickness)
    thickness = thickness or 1.0
    if withList(function(list)
        list:add_line({ x1, y1 }, { x2, y2 }, color, thickness)
    end) then return end
    fallbackButton(id, math.min(x1, x2), math.min(y1, y2), math.max(1, thickness, math.abs(x2 - x1)), math.max(1, thickness, math.abs(y2 - y1)), color, 0)
end

function Draw.text(id, x, y, color, text)
    return withList(function(list)
        list:add_text({ x, y }, color, text)
    end)
end

function Draw.icon(id, name, x, y, size, color, stroke)
    if not Draw.active() then return false end
    local function point(px, py)
        return { x + px * size / 24, y + py * size / 24 }
    end
    return withList(function(list)
        if name == "back" then
            list:add_line(point(15, 18), point(9, 12), color, stroke)
            list:add_line(point(9, 12), point(15, 6), color, stroke)
        elseif name == "close" then
            list:add_line(point(18, 6), point(6, 18), color, stroke)
            list:add_line(point(6, 6), point(18, 18), color, stroke)
        end
    end)
end

return Draw
