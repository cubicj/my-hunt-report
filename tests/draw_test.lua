local stubs = require("stubs")
local Draw = require("MyHuntReport.Draw")
local Theme = require("MyHuntReport.Theme")
local Log = require("MyHuntReport.Log")

local T = {}

local function withImgui(overrides, callback)
    local original = imgui
    Draw.resetForTests()
    local ok, err = pcall(function()
        imgui = setmetatable(overrides, { __index = original })
        callback()
    end)
    imgui = original
    Draw.resetForTests()
    if not ok then error(err, 0) end
end

function T.cornerConstantsMatchImDrawFlags()
    assert(Draw.CORNERS.none == 256 and Draw.CORNERS.left == 80 and Draw.CORNERS.right == 160 and Draw.CORNERS.all == 240)
end

function T.usesTheWindowDrawListWhenAvailable()
    local list = stubs.drawList()
    local buttons = {}
    withImgui({
        get_window_draw_list = function() return list end,
        button = function(label) buttons[#buttons + 1] = label return false end,
    }, function()
        Draw.rect("a", 10, 20, 30, 8, Theme.colors.accent, 4, Draw.CORNERS.left)
        Draw.dot("b", 5, 6, 4, Theme.colors.element)
        Draw.line("c", 0, 1, 100, 1, Theme.colors.rule)
        assert(Draw.active() == true and Draw.statusText() == "available")
        assert(#buttons == 0, "no fallback buttons when the draw list works")
        assert(#list.calls == 3)
        local rect = list.calls[1]
        assert(rect.name == "add_rect_filled" and rect[1][1] == 10 and rect[1][2] == 20 and rect[2][1] == 40 and rect[2][2] == 28)
        assert(rect[3] == Theme.colors.accent and rect[4] == 4 and rect[5] == 80)
        local dot = list.calls[2]
        assert(dot.name == "add_circle_filled" and dot[1][1] == 5 and dot[1][2] == 6 and dot[2] == 4 and dot[3] == Theme.colors.element and dot[4] == 16)
        local line = list.calls[3]
        assert(line.name == "add_line" and line[1][1] == 0 and line[2][1] == 100 and line[3] == Theme.colors.rule and line[4] == 1)
    end)
end

function T.linePassesExplicitThickness()
    local list = stubs.drawList()
    withImgui({ get_window_draw_list = function() return list end }, function()
        Draw.line("thick", 1, 2, 30, 2, Theme.colors.rule, 3)
        assert(#list.calls == 1 and list.calls[1][4] == 3)
    end)
end

function T.lineFallbackRespectsThicknessAndMinimumSize()
    local sizes = {}
    withImgui({
        get_window_draw_list = function() return nil end,
        button = function(_, size) sizes[#sizes + 1] = size return false end,
    }, function()
        Draw.line("horizontal", 30, 2, 1, 2, Theme.colors.rule, 3)
        Draw.line("vertical", 1, 30, 1, 2, Theme.colors.rule, 3)
        Draw.line("point", 1, 2, 1, 2, Theme.colors.rule, 0.5)
        assert(sizes[1][1] == 29 and sizes[1][2] == 3)
        assert(sizes[2][1] == 3 and sizes[2][2] == 28)
        assert(sizes[3][1] == 1 and sizes[3][2] == 1)
    end)
end

function T.iconsEmitScaledSegmentsInOrder()
    local expected = {
        back = { { 10, 12, 6, 8 }, { 6, 8, 10, 4 } },
        close = { { 12, 4, 4, 12 }, { 4, 4, 12, 12 } },
    }
    for name, segments in pairs(expected) do
        for _, box in ipairs({ { 0, 0, 16 }, { 30, 50, 32 } }) do
            local list = stubs.drawList()
            withImgui({ get_window_draw_list = function() return list end }, function()
                assert(Draw.icon("icon", name, box[1], box[2], box[3], Theme.colors.textMuted, 2) == true)
                assert(#list.calls == 2)
                for index, points in ipairs(segments) do
                    local call = list.calls[index]
                    assert(call.name == "add_line" and call[3] == Theme.colors.textMuted and call[4] == 2)
                    assert(call[1][1] == box[1] + points[1] * box[3] / 16)
                    assert(call[1][2] == box[2] + points[2] * box[3] / 16)
                    assert(call[2][1] == box[1] + points[3] * box[3] / 16)
                    assert(call[2][2] == box[2] + points[4] * box[3] / 16)
                end
            end)
        end
    end
end

function T.iconsReturnFalseWithoutDrawingInFallback()
    for _, forced in ipairs({ false, true }) do
        local list = stubs.drawList()
        local getters, buttons = 0, 0
        withImgui({
            get_window_draw_list = function() getters = getters + 1 if forced then return list end end,
            button = function() buttons = buttons + 1 end,
        }, function()
            Draw.setForced(forced)
            for _, name in ipairs({ "back", "close" }) do
                assert(Draw.icon("icon", name, 0, 0, 16, Theme.colors.text, 2) == false)
            end
            assert(#list.calls == 0 and buttons == 0)
            assert(getters == (forced and 0 or 1))
        end)
    end
end

function T.iconFailureDisablesDrawingOnceWithoutButtonFallback()
    for _, failAt in ipairs({ 1, 2 }) do
        local list = stubs.drawList()
        local calls, getters, buttons = 0, 0, 0
        list.add_line = function()
            calls = calls + 1
            if calls == failAt then error("icon stroke failed") end
        end
        Log.resetCounts()
        withImgui({
            get_window_draw_list = function() getters = getters + 1 return list end,
            button = function() buttons = buttons + 1 end,
        }, function()
            assert(Draw.icon("back", "back", 0, 0, 16, Theme.colors.text, 2) == false)
            assert(Draw.statusText() == "failed" and not Draw.active())
            assert(Draw.icon("close", "close", 0, 0, 16, Theme.colors.text, 2) == false)
            assert(calls == failAt and getters == 2 and buttons == 0)
            assert(Log.count("draw:fail") == 1)
        end)
    end
end

function T.textUsesTheDrawListWithoutMovingTheCursor()
    local list = stubs.drawList()
    withImgui({
        get_window_draw_list = function() return list end,
        set_cursor_pos = function() error("text must not move the cursor") end,
        set_cursor_screen_pos = function() error("text must not move the cursor") end,
    }, function()
        assert(Draw.text("label", 30, 40, Theme.colors.textMuted, "기록") == true)
        assert(#list.calls == 1)
        local call = list.calls[1]
        assert(call.name == "add_text" and call[1][1] == 30 and call[1][2] == 40)
        assert(call[2] == Theme.colors.textMuted and call[3] == "기록")
    end)
end

function T.textReturnsFalseWithoutDrawingInFallback()
    for _, forced in ipairs({ false, true }) do
        local list = stubs.drawList()
        local getters, buttons = 0, 0
        withImgui({
            get_window_draw_list = function() getters = getters + 1 if forced then return list end end,
            button = function() buttons = buttons + 1 end,
        }, function()
            Draw.setForced(forced)
            assert(Draw.text("label", 30, 40, Theme.colors.textMuted, "기록") == false)
            assert(#list.calls == 0 and buttons == 0 and getters == (forced and 0 or 1))
        end)
    end
end

function T.textFailureDisablesDrawingOnceWithoutButtonFallback()
    local list = stubs.drawList()
    local calls, buttons = 0, 0
    list.add_text = function() calls = calls + 1 error("text failed") end
    Log.resetCounts()
    withImgui({
        get_window_draw_list = function() return list end,
        button = function() buttons = buttons + 1 end,
    }, function()
        assert(Draw.text("label", 30, 40, Theme.colors.textMuted, "기록") == false)
        assert(Draw.statusText() == "failed" and not Draw.active())
        assert(Draw.text("label", 30, 40, Theme.colors.textMuted, "기록") == false)
        assert(calls == 1 and buttons == 0 and Log.count("draw:fail") == 1)
    end)
end

function T.skipsEmptyRectangles()
    local list = stubs.drawList()
    withImgui({ get_window_draw_list = function() return list end }, function()
        Draw.rect("a", 0, 0, 0, 8, Theme.colors.accent, 4, Draw.CORNERS.all)
        Draw.rect("b", 0, 0, 5, 0, Theme.colors.accent, 4, Draw.CORNERS.all)
        assert(#list.calls == 0)
    end)
end

function T.fallsBackToButtonsWithoutADrawList()
    local buttons, cursors = {}, {}
    withImgui({
        button = function(label, size) buttons[#buttons + 1] = { label = label, size = size } return false end,
        set_cursor_screen_pos = function(pos) cursors[#cursors + 1] = pos end,
        get_cursor_pos = function() return { x = 3, y = 4 } end,
        set_cursor_pos = function(pos) cursors[#cursors + 1] = { restore = true, x = pos.x, y = pos.y } end,
    }, function()
        Draw.rect("bar", 10, 20, 30, 8, Theme.colors.accent, 4, Draw.CORNERS.all)
        Draw.dot("dot", 5, 6, 4, Theme.colors.element)
        Draw.line("rule", 0, 1, 100, 1, Theme.colors.rule)
        assert(Draw.active() == false and Draw.statusText() == "unavailable")
        assert(buttons[1].label == "##drawbar" and buttons[1].size[1] == 30 and buttons[1].size[2] == 8)
        assert(buttons[2].label == "##drawdot" and buttons[2].size[1] == 8 and buttons[2].size[2] == 8)
        assert(buttons[3].label == "##drawrule" and buttons[3].size[1] == 100 and buttons[3].size[2] == 1)
        assert(cursors[1][1] == 10 and cursors[1][2] == 20)
        assert(cursors[2].restore and cursors[2].x == 3 and cursors[2].y == 4)
        assert(cursors[3][1] == 1 and cursors[3][2] == 2)
    end)
end

function T.fallsBackForTheSessionAfterOneFailure()
    Log.resetCounts()
    local list = stubs.drawList()
    list.add_rect_filled = function() error("boom") end
    local buttons = 0
    withImgui({
        get_window_draw_list = function() return list end,
        button = function() buttons = buttons + 1 return false end,
    }, function()
        Draw.rect("a", 0, 0, 10, 10, Theme.colors.accent, 0, Draw.CORNERS.all)
        assert(buttons == 1 and Draw.active() == false and Draw.statusText() == "failed")
        assert(Log.count("draw:fail") == 1)
        Draw.dot("b", 5, 5, 4, Theme.colors.accent)
        assert(buttons == 2 and #list.calls == 0)
    end)
end

function T.forcedFallbackSkipsTheDrawList()
    local list = stubs.drawList()
    local buttons = 0
    local getterCalls = 0
    withImgui({
        get_window_draw_list = function()
            getterCalls = getterCalls + 1
            return list
        end,
        button = function() buttons = buttons + 1 return false end,
    }, function()
        Draw.setForced(true)
        assert(Draw.isForced() == true)
        assert(Draw.active() == false)
        assert(getterCalls == 0, "forced active must not probe the draw list")
        assert(Draw.statusText() == "forced fallback")
        assert(getterCalls == 0, "forced status must not probe the draw list")
        Draw.rect("a", 0, 0, 10, 10, Theme.colors.accent, 0, Draw.CORNERS.all)
        assert(buttons == 1 and #list.calls == 0 and Draw.statusText() == "forced fallback")
        assert(getterCalls == 0, "forced drawing must not access the draw list")
        Draw.setForced(false)
        assert(getterCalls == 0)
        assert(Draw.active() == true and getterCalls == 1, "disabling fallback must leave the probe deferred until needed")
        assert(Draw.statusText() == "available" and getterCalls == 1, "the probe must run only once")
        Draw.rect("a", 0, 0, 10, 10, Theme.colors.accent, 0, Draw.CORNERS.all)
        assert(buttons == 1 and #list.calls == 1 and getterCalls == 2)
    end)
end

function T.probeTreatsMissingMethodsAsUnavailable()
    withImgui({ get_window_draw_list = function() return {} end }, function()
        Draw.line("a", 0, 0, 1, 0, Theme.colors.rule)
        assert(Draw.active() == false and Draw.statusText() == "unavailable")
    end)
    withImgui({ get_window_draw_list = false }, function()
        Draw.line("a", 0, 0, 1, 0, Theme.colors.rule)
        assert(Draw.statusText() == "unavailable")
    end)
end

function T.statusDoesNotConsumeTheProbe()
    local calls = 0
    withImgui({ get_window_draw_list = function()
        calls = calls + 1
        return stubs.drawList()
    end }, function()
        assert(Draw.statusText() == "not probed")
        assert(calls == 0)
        Draw.setForced(true)
        assert(Draw.statusText() == "forced fallback" and calls == 0)
        Draw.setForced(false)
        assert(Draw.statusText() == "not probed" and calls == 0)
        Draw.line("probe", 0, 0, 10, 0, Theme.colors.rule)
        assert(Draw.statusText() == "available" and calls == 2)
    end)
end

function T.probeRejectsUserdataWithoutRectMethod()
    assert(type(io.stdout) == "userdata")
    withImgui({ get_window_draw_list = function() return io.stdout end }, function()
        assert(Draw.active() == false)
        assert(Draw.statusText() == "unavailable")
    end)
end

function T.probeTreatsIndexingErrorsAsUnavailable()
    local list = setmetatable({}, { __index = function() error("index failed") end })
    withImgui({ get_window_draw_list = function() return list end }, function()
        assert(Draw.active() == false)
        assert(Draw.statusText() == "unavailable")
    end)
end

return T
