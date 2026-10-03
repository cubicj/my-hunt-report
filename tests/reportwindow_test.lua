local stubs = require("stubs")
local ReportWindow = require("MyHuntReport.ReportWindow")
local Locale = require("MyHuntReport.Locale")

local T = {}

local function snapshot(result)
    return { version = 2, quest = { result = result }, damage = { total = 1, hits = 1 }, stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} }
end

local function withNavigation(callback)
    local History = require("MyHuntReport.History")
    local Log = require("MyHuntReport.Log")
    local Settings = require("MyHuntReport.Settings")
    local originalImgui, readAll = imgui, History.readAll
    local developerMode, language, fontSize = Log.isDeveloperMode(), Locale.current(), Settings.get().fontSize
    local ui = { events = {}, buttons = {}, entries = {}, positions = {}, colors = {}, vars = {} }
    local function event(kind, value)
        local textColor
        for _, item in ipairs(ui.colors) do
            if item[1] == 0 then textColor = item[2] end
        end
        ui.events[#ui.events + 1] = { kind = kind, value = value, positionCount = #ui.positions, textColor = textColor }
    end
    function ui.draw(click)
        ui.events, ui.buttons, ui.positions = {}, {}, {}
        ui.click = click
        ReportWindow.draw()
    end
    local ok, err = pcall(function()
        Locale.resolve("ko")
        Log.setDeveloperMode(false)
        Settings.get().fontSize = 18
        ReportWindow.setNotSaved(false)
        History.readAll = function() return ui.entries end
        imgui = setmetatable({
            ImGuiStyleVar = { ItemSpacing = 14, ButtonTextAlign = 23, FrameRounding = 12, FrameBorderSize = 13 },
            begin_window = function() return true end,
            get_cursor_pos = function() return { x = 18, y = 20 } end,
            set_cursor_pos = function(pos) ui.positions[#ui.positions + 1] = pos end,
            text = function(text) event("text", text) end,
            separator = function() event("separator") end,
            invisible_button = function(id, size) event("reserve", id) return false end,
            get_cursor_screen_pos = function() return { x = 100, y = 200 } end,
            push_id = function(id) event("row", id) end,
            push_style_color = function(index, color) ui.colors[#ui.colors + 1] = { index, color } end,
            pop_style_color = function(count)
                for _ = 1, count do assert(table.remove(ui.colors)) end
            end,
            push_style_var = function(index, value) ui.vars[#ui.vars + 1] = { index, value } end,
            pop_style_var = function(count)
                for _ = 1, count do assert(table.remove(ui.vars)) end
            end,
            button = function(label, size)
                ui.buttons[#ui.buttons + 1] = label
                event("button", label)
                if ui.onButton then ui.onButton(label, size) end
                return label == ui.click
            end,
        }, { __index = originalImgui })
        callback(ui)
        assert(#ui.colors == 0 and #ui.vars == 0, "unbalanced styles")
    end)
    imgui, History.readAll = originalImgui, readAll
    Settings.get().fontSize = fontSize
    Locale.resolve(language)
    Log.setDeveloperMode(developerMode)
    ReportWindow.hide()
    ReportWindow.setNotSaved(false)
    if not ok then error(err, 0) end
end

local function assertNavigation(ui, expected)
    local navigation = {}
    for _, label in ipairs(ui.buttons) do
        if not label:find("##bar", 1, true) and not label:find("^##history%d") and not label:find("^##draw") then
            navigation[#navigation + 1] = label
        end
    end
    assert(table.concat(navigation, "|") == expected, table.concat(navigation, "|"))
    local bodyStarted = false
    for _, event in ipairs(ui.events) do
        if event.kind == "row" or (event.kind == "button" and event.value:find("##bar", 1, true)) then
            bodyStarted = true
        elseif event.kind == "button" and not event.value:find("^##draw") then
            assert(not bodyStarted, "navigation button after body: " .. event.value)
        end
    end
end

local function withIconNavigation(callback)
    local Draw = require("MyHuntReport.Draw")
    Draw.resetForTests()
    local ok, err = pcall(function()
        withNavigation(function(ui)
            local list = stubs.drawList()
            imgui.get_window_draw_list = function() return list end
            ReportWindow.showHistory()
            callback(ui, list, Draw)
        end)
    end)
    Draw.resetForTests()
    if not ok then error(err, 0) end
end

function T.topBarDrawsCenteredIconsWithHiddenLabels()
    local Theme = require("MyHuntReport.Theme")
    withIconNavigation(function(ui, list)
        local screen = { x = 100, y = 200 }
        imgui.get_cursor_screen_pos = function() return { x = screen.x, y = screen.y } end
        ui.onButton = function(label, size)
            assert(label == "##back" or label == "##close")
            assert(size[1] == 28 and size[2] == 28)
            screen = { x = 300, y = 400 }
        end
        ui.draw()
        assertNavigation(ui, "##back|##close")
        local expected = {
            { 116, 218, 112, 214 }, { 112, 214, 116, 210 },
            { 318, 410, 310, 418 }, { 310, 410, 318, 418 },
        }
        assert(#list.calls == 4)
        for index, points in ipairs(expected) do
            local call = list.calls[index]
            assert(call.name == "add_line" and call[3] == Theme.colors.textMuted and call[4] == 2)
            assert(call[1][1] == points[1] and call[1][2] == points[2])
            assert(call[2][1] == points[3] and call[2][2] == points[4])
        end
        assert(ui.events[1].textColor == Theme.colors.textMuted)
        assert(ui.events[2].textColor == Theme.colors.textMuted)
    end)
end

function T.topBarIconsReadHoverForEachButton()
    local Theme = require("MyHuntReport.Theme")
    for _, hovered in ipairs({ "##back", "##close" }) do
        withIconNavigation(function(ui, list)
            local reads = {}
            imgui.is_item_hovered = function()
                local label = ui.buttons[#ui.buttons]
                reads[#reads + 1] = label
                return label == hovered
            end
            ui.draw()
            assert(table.concat(reads, "|") == "##back|##close")
            assert(#list.calls == 4)
            for index, call in ipairs(list.calls) do
                local label = index <= 2 and "##back" or "##close"
                assert(call[3] == (label == hovered and Theme.colors.text or Theme.colors.textMuted))
            end
        end)
    end
end

function T.topBarIconsDefaultToMutedWhenHoverFailsOrIsMissing()
    local Theme = require("MyHuntReport.Theme")
    for _, hover in ipairs({ false, function() error("hover failed") end }) do
        withIconNavigation(function(ui, list)
            imgui.is_item_hovered = hover
            ui.draw()
            assertNavigation(ui, "##back|##close")
            assert(#list.calls == 4)
            for _, call in ipairs(list.calls) do assert(call[3] == Theme.colors.textMuted) end
        end)
    end
end

function T.topBarUsesTextWhenDrawListIsAbsentOrForcedOff()
    for _, forced in ipairs({ false, true }) do
        withIconNavigation(function(ui, list, Draw)
            local getters, hovers = 0, 0
            imgui.get_window_draw_list = function() getters = getters + 1 if forced then return list end end
            imgui.is_item_hovered = function() hovers = hovers + 1 return true end
            Draw.setForced(forced)
            ui.draw()
            assertNavigation(ui, "<##back|X##close")
            assert(#list.calls == 0 and hovers == 0 and getters == (forced and 0 or 1))
        end)
    end
end

function T.topBarUsesTextAfterAnIconDrawFailure()
    withIconNavigation(function(ui, list, Draw)
        list.add_line = function() error("icon failed") end
        ui.draw()
        assert(Draw.statusText() == "failed")
        assertNavigation(ui, "##back|X##close")
        ui.draw()
        assertNavigation(ui, "<##back|X##close")
    end)
end

function T.resultTextAddsStarsOnlyForPositiveQuestLevels()
    assert(ReportWindow.resultText({ result = "clear" }) == Locale.text("result_quest"))
    assert(ReportWindow.resultText({ result = "clear", level = 5 }) == Locale.text("result_quest") .. " ★5")
    assert(ReportWindow.resultText({ result = "training", level = 5 }) == Locale.text("result_training"))
    for _, level in ipairs({ 0, -1, "5", false }) do
        assert(ReportWindow.resultText({ result = "clear", level = level }) == Locale.text("result_quest"))
    end
end

function T.headerDrawsWeaponThenQuestLevelThenMeta()
    withNavigation(function(ui)
        local shown = snapshot("clear")
        shown.quest.level = 5
        shown.quest.weapons = { { name = "태도" } }
        shown.quest.elapsedSeconds = 754
        shown.monsters = { { name = "미즈츠네" } }
        ReportWindow.show(shown)
        ui.draw()
        local texts = {}
        for _, event in ipairs(ui.events) do
            if event.kind == "text" then texts[#texts + 1] = event.value end
        end
        assert(texts[1] == "태도", texts[1])
        assert(texts[2] == Locale.text("result_quest") .. " ★5", texts[2])
        assert(texts[3] == "미즈츠네 · 12:34", texts[3])
        for _, event in ipairs(ui.events) do
            assert(event.kind ~= "separator", "separator drawn")
        end
    end)
end

function T.historyRowsDrawFourColumnsOverATransparentButton()
    withNavigation(function(ui)
        local entry = snapshot("clear")
        entry.quest.endedAt = os.time({ year = 2026, month = 9, day = 23, hour = 21, min = 36, sec = 0 })
        entry.quest.weapons = { { name = "조충곤" } }
        entry.monsters = { { name = "아자라칸" } }
        entry.quest.level = 5
        ui.entries = { entry }
        ReportWindow.showHistory()
        ui.draw()
        assert(ui.buttons[3] == "##history1", tostring(ui.buttons[3]))
        local texts = {}
        local afterRow = false
        for _, event in ipairs(ui.events) do
            if event.kind == "button" and event.value == "##history1" then afterRow = true end
            if afterRow and event.kind == "text" then texts[#texts + 1] = event.value end
        end
        assert(table.concat(texts, "|") == "2026-09-23 21:36|★5|조충곤|아자라칸", table.concat(texts, "|"))
        local columns = ReportWindow.historyColumns(680, 1, false)
        local xs = {}
        for _, pos in ipairs(ui.positions) do xs[pos.x or pos[1]] = true end
        assert(xs[18 + columns.time.x] and xs[18 + columns.stars.x] and xs[18 + columns.weapons.x] and xs[18 + columns.monsters.x])
    end)
end

function T.reportNavigationPrecedesBodyRows()
    withNavigation(function(ui)
        local shown = snapshot("clear")
        shown.skills = { { name = "skill", share = 1 } }
        shown.motions = { { name = "motion", share = 1 } }
        for _, language in ipairs({ "ko", "en" }) do
            Locale.resolve(language)
            ReportWindow.show(shown)
            ui.draw()
            assert(ReportWindow.isOpen())
            assertNavigation(ui, Locale.text("history") .. "|X##close")
            assert(ui.buttons[1] == Locale.text("history") and ui.buttons[2] == "X##close")
        end
    end)
end

function T.historyNavigationHasBackAndCloseOnly()
    withNavigation(function(ui)
        for _, entries in ipairs({ {}, { snapshot("clear") } }) do
            ui.entries = entries
            ReportWindow.show(snapshot("clear"))
            ReportWindow.showHistory()
            ui.draw()
            assert(ReportWindow.isOpen())
            assertNavigation(ui, "<##back|X##close")
            assert(ui.buttons[1] == "<##back" and ui.buttons[2] == "X##close")
        end
    end)
end

function T.selectedHistoryReportNavigationHasBackAndCloseOnly()
    withNavigation(function(ui)
        ui.entries = { snapshot("clear") }
        ReportWindow.show(snapshot("running"))
        ReportWindow.showHistory()
        ui.draw()
        ui.draw(ui.buttons[3])
        assert(ReportWindow.debugState().fromHistory)
        ui.draw()
        assertNavigation(ui, "<##back|X##close")
    end)
end

function T.topBarButtonsNavigateAndCloseEveryView()
    withNavigation(function(ui)
        local live = snapshot("clear")
        ui.entries = { snapshot("clear") }
        ReportWindow.show(live)
        ui.draw("기록")
        assert(ReportWindow.debugState().view == "history")
        ui.draw()
        ui.draw(ui.buttons[3])
        assert(ReportWindow.debugState().fromHistory)
        ui.draw("<##back")
        assert(ReportWindow.debugState().view == "history")
        ui.draw("<##back")
        assert(ReportWindow.debugState().view == "report" and ReportWindow.debugState().snapshot == live)
        for _, view in ipairs({ "report", "history", "selected", "empty" }) do
            ReportWindow.show(view ~= "empty" and live or nil)
            if view == "history" or view == "selected" then ReportWindow.showHistory() end
            if view == "selected" then
                ui.draw()
                ui.draw(ui.buttons[3])
                assert(ReportWindow.debugState().fromHistory)
            end
            ui.draw("X##close")
            assert(not ReportWindow.isOpen(), "X did not close " .. view)
        end
    end)
end

function T.noDataDrawsHistoryAndCloseBeforeTitleAndMessage()
    withNavigation(function(ui)
        for _, shown in ipairs({ false, { damage = { total = 0 } } }) do
            ReportWindow.show(shown or nil)
            ui.draw()
            assertNavigation(ui, "기록|X##close")
            assert(ui.events[1].value == "기록")
            assert(ui.events[2].value == "X##close")
            assert(ui.events[3].value == Locale.text("report_title"))
            assert(ui.events[4].value == Locale.text("no_data"))
            assert(#ui.events == 4)
        end
    end)
end

function T.topBarPositionsButtonsAndTitlesInSeparateRows()
    withNavigation(function(ui)
        ui.onButton = function(label, size)
            if label == "기록" then assert(size[1] == 72 and size[2] == 28) end
            if label == "X##close" or label == "<##back" then assert(size[1] == 28 and size[2] == 28) end
        end
        local shown = snapshot("clear")
        shown.quest.weapons = { { name = "태도" } }
        ui.entries = { shown }
        for _, view in ipairs({ "report", "history", "selected", "empty" }) do
            ReportWindow.show(view ~= "empty" and shown or nil)
            if view == "history" or view == "selected" then ReportWindow.showHistory() end
            if view == "selected" then ui.draw("##history1") end
            ui.draw()
            local expected = (view == "history" or view == "selected")
                and { ["<##back"] = 24, ["X##close"] = 676 }
                or { ["기록"] = 596, ["X##close"] = 676 }
            local title = view == "history" and Locale.text("history_title")
                or view == "empty" and Locale.text("report_title") or "태도"
            local buttons, titles = 0, 0
            for _, event in ipairs(ui.events) do
                local pos = ui.positions[event.positionCount]
                if event.kind == "button" and expected[event.value] then
                    assert(pos[1] == expected[event.value] and pos[2] == 20, event.value)
                    buttons = buttons + 1
                elseif event.kind == "text" and event.value == title then
                    assert(buttons == 2, "title must follow the tab row")
                    assert(pos[1] == 24 and pos[2] == 60, view .. " title position")
                    titles = titles + 1
                end
            end
            assert(buttons == 2 and titles == 1)
        end
    end)
end

function T.topBarTitleGapIsFixedAtEveryFontSize()
    withNavigation(function(ui)
        local Settings = require("MyHuntReport.Settings")
        for _, size in ipairs({ 14, 18, 20, 28 }) do
            Settings.get().fontSize = size
            ReportWindow.show(snapshot("clear"))
            ui.draw()
            assert(ReportWindow.isOpen())
            local title
            for _, event in ipairs(ui.events) do
                if event.kind == "text" and event.value == Locale.text("weapon_unknown") then
                    title = ui.positions[event.positionCount]
                end
            end
            assert(title and title[1] == 24 and title[2] == 60, "title cursor at font size " .. size)
        end
    end)
end

function T.topBarDrawsOnlyButtonsAndCentersHistoryWithTheBodyFont()
    local Theme = require("MyHuntReport.Theme")
    for _, size in ipairs({ 18, 20, 28 }) do
        for _, hovered in ipairs({ false, true }) do
            withIconNavigation(function(ui, list)
                ReportWindow.show(nil)
                local cursor, fonts = { x = 24, y = 20 }, {}
                imgui.set_cursor_pos = function(pos) cursor = { x = pos[1], y = pos[2] } end
                imgui.get_cursor_pos = function() return cursor end
                imgui.get_cursor_screen_pos = function() return { x = cursor.x + 100, y = cursor.y + 200 } end
                imgui.same_line = function() error("tab row must use explicit positions") end
                imgui.push_font = function(font) fonts[#fonts + 1] = font end
                imgui.pop_font = function() assert(table.remove(fonts)) end
                imgui.calc_text_size = function(label)
                    assert(label == "기록" and fonts[#fonts] == "body")
                    return { x = size * 2, y = size }
                end
                imgui.is_item_hovered = function() return hovered end
                local addText = list.add_text
                list.add_text = function(self, ...)
                    assert(fonts[#fonts] == "body")
                    addText(self, ...)
                end
                ui.onButton = function(label, dimensions)
                    assert(cursor.x == (label == "##history" and 596 or 676) and cursor.y == 20)
                    assert(dimensions[1] == (label == "##history" and 72 or 28) and dimensions[2] == 28)
                    cursor = { x = 999, y = 999 }
                end
                ReportWindow.drawTopBar({ width = 680, fonts = { body = { handle = "body", size = size } }, sizes = { body = size } })
                assertNavigation(ui, "##history|##close")
                assert(#ui.events == 2 and #fonts == 0)
                assert(cursor.x == 24 and cursor.y == 60)
                assert(#list.calls == 3)
                local label = list.calls[1]
                assert(label.name == "add_text" and label[3] == "기록")
                assert(label[1][1] == 696 + (72 - size * 2) / 2)
                local nudge = size == 28 and 2 or 1
                assert(label[1][2] == 220 + (28 - size) / 2 - nudge)
                assert(label[2] == (hovered and Theme.colors.text or Theme.colors.textMuted))
                assert(list.calls[2][1][1] == 794 and list.calls[2][1][2] == 230)
            end)
        end
    end
end

function T.historyLabelUsesPlainButtonWhenDrawListIsAbsentOrForcedOff()
    for _, forced in ipairs({ false, true }) do
        withIconNavigation(function(ui, list, Draw)
            imgui.get_window_draw_list = function() if forced then return list end end
            Draw.setForced(forced)
            ReportWindow.show(nil)
            ui.draw("기록")
            assertNavigation(ui, "기록|X##close")
            assert(#list.calls == 0)
            assert(ReportWindow.debugState().view == "history")
        end)
    end
end

function T.historyDrawListLabelNavigatesAndFallsBackAfterFailure()
    withIconNavigation(function(ui, list, Draw)
        ReportWindow.show(nil)
        ui.draw("##history")
        assertNavigation(ui, "##history|##close")
        assert(ReportWindow.debugState().view == "history")
        ReportWindow.show(nil)
        local fonts = {}
        imgui.push_font = function(font) fonts[#fonts + 1] = font end
        imgui.pop_font = function() assert(table.remove(fonts)) end
        list.add_text = function()
            assert(fonts[#fonts] == "body")
            error("label failed")
        end
        ui.events, ui.buttons, ui.positions = {}, {}, {}
        ReportWindow.drawTopBar({ width = 680, fonts = { body = { handle = "body", size = 18 } }, sizes = { body = 18 } })
        assert(#fonts == 0)
        assert(Draw.statusText() == "failed")
        assertNavigation(ui, "##history|X##close")
        ui.draw()
        assertNavigation(ui, "기록|X##close")
    end)
end

function T.historyLabelDefaultsToMutedWhenHoverFailsOrIsMissing()
    local Theme = require("MyHuntReport.Theme")
    for _, hover in ipairs({ false, function() error("hover failed") end }) do
        withIconNavigation(function(ui, list)
            ReportWindow.show(nil)
            imgui.is_item_hovered = hover
            ui.draw()
            assertNavigation(ui, "##history|##close")
            assert(list.calls[1].name == "add_text" and list.calls[1][2] == Theme.colors.textMuted)
        end)
    end
end

function T.ghostButtonsUseMutedTextAndHeadersKeepBodyColor()
    withNavigation(function(ui)
        local Theme = require("MyHuntReport.Theme")
        local shown = snapshot("clear")
        shown.quest.weapons = { { name = "태도" } }
        ReportWindow.show(shown)
        for _, history in ipairs({ false, true }) do
            if history then ReportWindow.showHistory() end
            ui.draw()
            assert(ReportWindow.isOpen())
            local buttons, headers = 0, 0
            for _, event in ipairs(ui.events) do
                if event.kind == "button" and (event.value == "기록" or event.value == "X##close" or event.value == "<##back") then
                    assert(event.textColor == Theme.colors.textMuted, "ghost label must be muted: " .. event.value)
                    buttons = buttons + 1
                elseif event.kind == "text" and event.value == (history and Locale.text("history_title") or "태도") then
                    assert(event.textColor == Theme.colors.text, "header must retain body color")
                    headers = headers + 1
                end
            end
            assert(buttons == 2 and headers == 1)
        end
    end)
end

function T.historyChildEntryErrorsBalanceStylesAndCloseWindow()
    withNavigation(function(ui)
        ui.entries = { snapshot("clear") }
        imgui.begin_child_window = function(name)
            assert(name == "history##rows")
            error("child entry failed")
        end
        ReportWindow.showHistory()
        ui.draw()
        assert(#ui.colors == 0 and #ui.vars == 0, "history child entry leaked styles")
        assert(ReportWindow.isOpen() == false)
    end)
end

function T.skillChildEntryErrorsBalanceStylesAndCloseWindow()
    withNavigation(function(ui)
        imgui.begin_child_window = function(name)
            assert(name == "skill##rows")
            error("child entry failed")
        end
        ReportWindow.show(snapshot("clear"))
        ui.draw()
        assert(#ui.colors == 0 and #ui.vars == 0, "skill child entry leaked styles")
        assert(ReportWindow.isOpen() == false)
    end)
end

function T.rowBodyErrorsEndChildrenAndBalanceStyles()
    for _, childName in ipairs({ "history##rows", "skill##rows", "motion##rows" }) do
        withNavigation(function(ui)
            local child, ended = nil, 0
            local shown = snapshot("clear")
            shown.skills = { { name = "Skill", share = 0.5 } }
            shown.motions = { { name = "Motion", share = 0.5 } }
            ui.entries = { shown }
            imgui.begin_child_window = function(name) child = name end
            imgui.end_child_window = function()
                if child == childName then ended = ended + 1 end
                child = nil
            end
            imgui.text = function()
                if child == childName then error("row text failed") end
            end
            if childName == "history##rows" then ReportWindow.showHistory() else ReportWindow.show(shown) end
            ui.draw()
            assert(#ui.colors == 0 and #ui.vars == 0, "row body leaked styles: " .. childName)
            assert(not ReportWindow.isOpen() and ended == 1 and child == nil)
        end)
    end
end

function T.childEndErrorsStillReleaseRowStyles()
    for _, history in ipairs({ false, true }) do
        withNavigation(function(ui)
            local ended = 0
            ui.entries = { snapshot("clear") }
            imgui.end_child_window = function()
                ended = ended + 1
                error("child end failed")
            end
            if history then ReportWindow.showHistory() else ReportWindow.show(snapshot("clear")) end
            ui.draw()
            assert(#ui.colors == 0 and #ui.vars == 0, "child end leaked styles")
            assert(ReportWindow.isOpen() and ended == (history and 1 or 2))
        end)
    end
end

function T.ghostButtonErrorsStillReleaseTextColor()
    for _, label in ipairs({ "기록", "X##close", "<##back" }) do
        withNavigation(function(ui)
            ui.onButton = function(button)
                if button == label then error("ghost button failed") end
            end
            if label == "<##back" then ReportWindow.showHistory() else ReportWindow.show(snapshot("clear")) end
            ui.draw()
            assert(#ui.colors == 0 and #ui.vars == 0, "ghost button leaked styles: " .. label)
            assert(not ReportWindow.isOpen())
        end)
    end
end

function T.reportRowsUseTheSpacingAssumedByRowAreaLayout()
    withNavigation(function(ui)
        local child, rows = nil, {}
        local shown = snapshot("clear")
        for index = 1, 20 do
            shown.skills[index] = { name = "Skill " .. index, share = 0.5 }
            shown.motions[index] = { name = "Motion " .. index, share = 0.5 }
        end
        imgui.begin_child_window = function(name) child = name end
        imgui.end_child_window = function() child = nil end
        imgui.text = function()
            if not child then return end
            local spacing
            for _, item in ipairs(ui.vars) do
                if item[1] == 14 then spacing = item[2] end
            end
            rows[#rows + 1] = { child = child, spacing = spacing }
        end
        ReportWindow.show(shown)
        ui.draw()
        assert(ReportWindow.isOpen() and child == nil and #rows == 80)
        local counts = {}
        for _, row in ipairs(rows) do
            assert(row.spacing.x == 10 and row.spacing.y == 9, "report row spacing must be 10 x 9")
            counts[row.child] = (counts[row.child] or 0) + 1
        end
        assert(counts["skill##rows"] == 40 and counts["motion##rows"] == 40)
    end)
end

local function checkRowStripes(fontSize, scrolls, fallback, count)
    local Draw = require("MyHuntReport.Draw")
    local Theme = require("MyHuntReport.Theme")
    Draw.resetForTests()
    local ok, err = pcall(function()
        withNavigation(function(ui)
            require("MyHuntReport.Settings").get().fontSize = fontSize
            local list = stubs.drawList()
            imgui.get_window_draw_list = function()
                if fallback then return nil end
                return list
            end
            imgui.get_display_size = function() return { x = 1920, y = scrolls and 108 or 1080 } end
            imgui.calc_text_size = function(text) return { x = #text * 8, y = fontSize } end
            local child, cursor, lastText, rowId
            local children = {}
            local getCursor, setCursor = imgui.get_cursor_pos, imgui.set_cursor_pos
            local getScreen, setScreen = imgui.get_cursor_screen_pos, imgui.set_cursor_screen_pos
            local text, sameLine, button = imgui.text, imgui.same_line, imgui.button
            local stride = fontSize + 9
            local width = math.floor((math.floor(680 * fontSize / 18) - 32) / 2) - (scrolls and 14 or 0)
            imgui.begin_child_window = function(name, size)
                child = { name = name, x = name == "skill##rows" and 100 or 500, y = 200, texts = 0, stripes = {} }
                children[#children + 1] = child
                cursor = { x = 0, y = 0 }
                assert(size[1] == width + (scrolls and 14 or 0))
            end
            imgui.end_child_window = function() child = nil end
            imgui.push_id = function(id) rowId = id end
            imgui.get_cursor_pos = function()
                if child then return { x = cursor.x, y = cursor.y } end
                return getCursor()
            end
            imgui.set_cursor_pos = function(pos)
                if child then cursor = { x = pos.x or pos[1], y = pos.y or pos[2] } else setCursor(pos) end
            end
            imgui.get_cursor_screen_pos = function()
                if child then return { x = child.x + cursor.x, y = child.y + cursor.y } end
                return getScreen()
            end
            imgui.set_cursor_screen_pos = function(pos)
                if child then cursor = { x = pos[1] - child.x, y = pos[2] - child.y } else setScreen(pos) end
            end
            local function stripe(call)
                if not child then return end
                local index = child.texts / 2 + 1
                assert(index % 2 == 1, "stripe must precede an odd row's text")
                assert(call[1][1] == child.x and call[1][2] == child.y + (index - 1) * stride - 4.5)
                assert(call[2][1] == child.x + width and call[2][2] == call[1][2] + stride)
                assert(call[3] == 0x0AFFFFFF and call[4] == 3 and call[5] == 240)
                child.stripes[#child.stripes + 1] = index
            end
            local addRect = list.add_rect_filled
            list.add_rect_filled = function(self, ...)
                addRect(self, ...)
                stripe(self.calls[#self.calls])
            end
            imgui.button = function(label, size)
                if not child then return button(label, size) end
                assert(fallback and label == "##drawstripe" .. rowId)
                local colors, vars = {}, {}
                for _, item in ipairs(ui.colors) do colors[item[1]] = item[2] end
                for _, item in ipairs(ui.vars) do vars[item[1]] = item[2] end
                assert(colors[21] == colors[22] and colors[21] == colors[23], "stripe hover must not change color")
                stripe({ { child.x + cursor.x, child.y + cursor.y },
                    { child.x + cursor.x + size[1], child.y + cursor.y + size[2] }, colors[21], vars[12], 240 })
                cursor = { x = 0, y = cursor.y + size[2] }
                return false
            end
            imgui.text = function(value)
                if not child then return text(value) end
                local index = math.floor(child.texts / 2) + 1
                assert(#child.stripes == math.ceil(index / 2), "missing stripe before text")
                assert(cursor.y == (index - 1) * stride, "stripe moved the text cursor")
                assert(cursor.x == (child.texts % 2 == 0 and 0 or width - 4 - #value * 8))
                lastText = { x = cursor.x, y = cursor.y }
                cursor = { x = 0, y = cursor.y + stride }
                child.texts = child.texts + 1
            end
            imgui.same_line = function()
                if child then cursor = { x = lastText.x, y = lastText.y } else sameLine() end
            end
            local shown = snapshot("clear")
            for index = 1, count do
                shown.skills[index] = { name = "Skill " .. index, share = 0.5 }
                shown.motions[index] = { name = "Motion " .. index, share = 0.25 }
            end
            ReportWindow.show(shown)
            ui.draw()
            assert(ReportWindow.isOpen() and #children == 2 and child == nil)
            for _, recorded in ipairs(children) do
                assert(recorded.texts == count * 2)
                assert(#recorded.stripes == (count == 0 and 0 or 2))
                if count > 0 then assert(recorded.stripes[1] == 1 and recorded.stripes[2] == 3) end
            end
            if fallback then assert(#list.calls == 0) end
        end)
    end)
    Draw.resetForTests()
    if not ok then error(err, 0) end
end

function T.oddRowStripesMatchBothColumnGeometriesAtBothScales()
    for _, fontSize in ipairs({ 18, 28 }) do
        for _, scrolls in ipairs({ false, true }) do
            checkRowStripes(fontSize, scrolls, false, 3)
        end
    end
end

function T.rowStripeFallbackDrawsBeforeTextAndRestoresCursor()
    for _, fontSize in ipairs({ 18, 28 }) do
        for _, scrolls in ipairs({ false, true }) do
            checkRowStripes(fontSize, scrolls, true, 3)
        end
    end
end

function T.emptyRowListsDrawNoStripes()
    for _, fallback in ipairs({ false, true }) do
        checkRowStripes(18, false, fallback, 0)
    end
end

function T.rowStripeCursorErrorsBalanceIdsChildrenAndStyles()
    for _, target in ipairs({ "skill##rows", "motion##rows" }) do
        withNavigation(function(ui)
            local child, ended, ids = nil, 0, 0
            imgui.begin_child_window = function(name) child = name end
            imgui.end_child_window = function()
                if child == target then ended = ended + 1 end
                child = nil
            end
            imgui.push_id = function() ids = ids + 1 end
            imgui.pop_id = function() ids = ids - 1 end
            imgui.get_cursor_screen_pos = function()
                if child == target then error("row screen cursor failed") end
                return { x = 100, y = 200 }
            end
            local shown = snapshot("clear")
            shown.skills = { { name = "Skill", share = 0.5 } }
            shown.motions = { { name = "Motion", share = 0.25 } }
            ReportWindow.show(shown)
            ui.draw()
            assert(not ReportWindow.isOpen() and child == nil and ended == 1 and ids == 0)
            assert(#ui.colors == 0 and #ui.vars == 0)
        end)
    end
end

function T.historyRowsUseTransparentHoverStyle()
    withNavigation(function(ui)
        local Theme = require("MyHuntReport.Theme")
        local checked = false
        ui.entries = { snapshot("clear") }
        ui.onButton = function(label, size)
            if not label:find("^##history%d") then return end
            local colors = {}
            for _, item in ipairs(ui.colors) do colors[item[1]] = item[2] end
            local vars = {}
            for _, item in ipairs(ui.vars) do vars[item[1]] = item[2] end
            assert(colors[21] == 0x00000000, "history row background must be transparent")
            assert(colors[22] == Theme.colors.accentDim and colors[23] == Theme.colors.accentDim)
            assert(vars[13] == 0 and vars[12] == 4)
            assert(vars[14].x == 0 and vars[14].y == 0)
            assert(size[1] == 680 and size[2] == 36)
            checked = true
        end
        ReportWindow.showHistory()
        ui.draw()
        assert(ReportWindow.isOpen() and checked)
    end)
end

function T.footerRuleOnlyAppearsWithWarningOrDiagnostics()
    withNavigation(function(ui)
        local Log = require("MyHuntReport.Log")
        local shown = snapshot("clear")
        shown.diagnostics = { weightFallbacks = 2 }
        for _, flags in ipairs({ { false, false, 0 }, { true, false, 1 }, { false, true, 1 }, { true, true, 1 } }) do
            ReportWindow.show(shown)
            ReportWindow.setNotSaved(flags[1])
            Log.setDeveloperMode(flags[2])
            ui.draw()
            local rules, warning, diagnostics = 0, false, false
            for _, event in ipairs(ui.events) do
                if event.kind == "reserve" and event.value == "##footerrule" then rules = rules + 1 end
                if event.kind == "separator" then error("separator drawn") end
                if event.kind == "text" then
                    warning = warning or event.value:find(Locale.text("not_saved"), 1, true) ~= nil
                    diagnostics = diagnostics or event.value:find("weightFallbacks=2", 1, true) ~= nil
                end
            end
            assert(rules == flags[3], "footer rule count: " .. rules)
            assert(warning == flags[1] and diagnostics == flags[2])
        end
    end)
end

function T.attributionFooterShowsCountersAndLegacyZerosOnlyInDeveloperMode()
    withNavigation(function(ui)
        local Log = require("MyHuntReport.Log")
        local Theme = require("MyHuntReport.Theme")
        local shown = snapshot("clear")
        shown.diagnostics = {
            attribution = { action = 1, shell = 2, kinsect = 3, slinger = 9, weaponMinus1 = 4, lastAttack = 5, nonattack = 6 },
            names = { sibling = 7, unmapped = 8 },
        }
        for _, enabled in ipairs({ false, true }) do
            Log.setDeveloperMode(enabled)
            ReportWindow.show(shown)
            ui.draw()
            local count = 0
            for index, event in ipairs(ui.events) do
                if event.kind == "text" and event.value:find("attribution:", 1, true) then
                    count = count + 1
                    assert(event.value == "attribution: action=1 shell=2 kinsect=3 slinger=9", event.value)
                    assert(event.textColor == Theme.colors.textMuted)
                    assert(ui.events[index - 1].value:find("weightFallbacks=", 1, true))
                    assert(ui.events[index + 1].value == "weapon-1=4 lastAttack=5 nonattack=6", ui.events[index + 1].value)
                    assert(ui.events[index + 2].value == "names: sibling=7 unmapped=8", ui.events[index + 2].value)
                end
            end
            assert(count == (enabled and 1 or 0))
        end
        shown.diagnostics = {}
        ui.draw()
        local found = false
        for _, event in ipairs(ui.events) do
            if event.kind == "text" and event.value:find("attribution:", 1, true) then
                assert(event.value == "attribution: action=0 shell=0 kinsect=0 slinger=0")
                found = true
            end
        end
        assert(found)
    end)
end

function T.damageLegendDrawsEveryTypeWithDotAndPercent()
    withNavigation(function(ui)
        local shown = snapshot("clear")
        shown.damage = { total = 1000, physical = 784, element = 162, fixed = 31, status = 23, hits = 10 }
        shown.skillDamage = { { kind = "violent", share = 0.042 } }
        ReportWindow.show(shown)
        ui.draw()
        local texts, reserved = {}, {}
        for _, event in ipairs(ui.events) do
            if event.kind == "text" then texts[#texts + 1] = event.value end
            if event.kind == "reserve" then reserved[event.value] = true end
        end
        local drawn = table.concat(texts, "\n")
        for _, pair in ipairs({ { "physical", "78.4%" }, { "element", "16.2%" }, { "fixed", "3.1%" }, { "status", "2.3%" } }) do
            assert(drawn:find(Locale.text(pair[1]) .. "\n" .. pair[2], 1, true), pair[1])
        end
        assert(drawn:find(Locale.text("skill_damage_violent") .. "\n4.2%", 1, true))
        assert(reserved["##damagebar"] and reserved["##dotphys"] and reserved["##dotstat"])
        local events = {}
        for _, event in ipairs(ui.events) do
            if event.kind ~= "button" or not event.value:find("^##draw") then events[#events + 1] = event end
        end
        local names = { ["##dotphys"] = "physical", ["##dotelem"] = "element", ["##dotfixed"] = "fixed", ["##dotstat"] = "status" }
        local checked = 0
        for index, event in ipairs(events) do
            local name = event.kind == "reserve" and names[event.value]
            if name then
                local nextEvent = events[index + 1]
                assert(nextEvent and nextEvent.kind == "text" and nextEvent.value == Locale.text(name), event.value)
                local positioned = false
                for position = event.positionCount + 1, nextEvent.positionCount do
                    local pos = ui.positions[position]
                    if pos.x == 18 + 8 + 8 and pos.y == 20 then positioned = true end
                end
                assert(positioned, "legend name origin missing: " .. name)
                checked = checked + 1
            end
        end
        assert(checked == 4)
    end)
end

function T.bodyColumnsReserveRulesWithoutMovingUp()
    withNavigation(function(ui)
        local groupStarts = {}
        imgui.begin_group = function() groupStarts[#groupStarts + 1] = #ui.positions end
        ReportWindow.show(snapshot("clear"))
        ui.draw()
        local skills, motions
        for _, event in ipairs(ui.events) do
            if event.kind == "reserve" and event.value == "##ruleskills" then skills = event end
            if event.kind == "reserve" and event.value == "##rulemotions" then motions = event end
        end
        assert(skills and motions, "column rule reservations missing")
        assert(#groupStarts == 2)
        local beforeGroup = ui.positions[groupStarts[1]]
        assert(beforeGroup.y ~= 20 + 16, "extra leading section gap")
        for index = skills.positionCount + 1, motions.positionCount do
            local pos = ui.positions[index]
            assert((pos.y or pos[2]) >= 20, "motion column moved above row start")
        end
    end)
end

function T.sectionRulesReserveImmediatelyAfterHeaderText()
    withNavigation(function(ui)
        ReportWindow.show(snapshot("clear"))
        ui.draw()
        local headers = { [Locale.text("damage_types")] = "##ruledamage", [Locale.text("skills_header")] = "##ruleskills", [Locale.text("motions_header")] = "##rulemotions" }
        local checked = 0
        for index, event in ipairs(ui.events) do
            local id = event.kind == "text" and headers[event.value]
            if id then
                local nextEvent = ui.events[index + 1]
                assert(nextEvent and nextEvent.kind == "reserve" and nextEvent.value == id, "rule reservation missing after " .. event.value)
                assert(nextEvent.positionCount > event.positionCount)
                local pos = ui.positions[nextEvent.positionCount]
                assert(pos.x == 18 + require("MyHuntReport.Theme").metrics.ruleGap and pos.y == 20, "rule cursor must follow text by ruleGap")
                checked = checked + 1
            end
        end
        assert(checked == 3)
    end)
end

function T.sectionRulesMeasureWithSmallFontAndSpanTheRemainingWidth()
    local Fonts = require("MyHuntReport.Fonts")
    local small = Fonts.small
    local ok, err = pcall(function()
        Fonts.small = function() return { handle = "small-font", size = 18 } end
        withNavigation(function(ui)
            local fontStack, measurements, reservations = {}, {}, {}
            local list = stubs.drawList()
            local Draw = require("MyHuntReport.Draw")
            Draw.resetForTests()
            imgui.get_window_draw_list = function() return list end
            imgui.push_font = function(font) fontStack[#fontStack + 1] = font end
            imgui.pop_font = function() table.remove(fontStack) end
            local headers = { [Locale.text("damage_types")] = true, [Locale.text("skills_header")] = true, [Locale.text("motions_header")] = true }
            imgui.calc_text_size = function(text)
                if headers[text] then measurements[#measurements + 1] = fontStack[#fontStack] or false end
                return { x = 40, y = 14 }
            end
            imgui.invisible_button = function(id, size)
                if id:find("^##rule") then reservations[#reservations + 1] = { size = size, pos = ui.positions[#ui.positions] } end
                return false
            end
            ReportWindow.show(snapshot("clear"))
            ui.draw()
            Draw.resetForTests()
            assert(ReportWindow.isOpen() and #fontStack == 0)
            assert(#measurements == 3 and #reservations == 3)
            for _, font in ipairs(measurements) do assert(font == "small-font", "section measured without small font") end
            local lines = {}
            for _, call in ipairs(list.calls) do
                if call.name == "add_line" and call[3] == require("MyHuntReport.Theme").colors.rule then lines[#lines + 1] = call end
            end
            assert(#lines == 3)
            for index, width in ipairs({ 680, 324, 324 }) do
                local ruleWidth = width - 40 - 12
                assert(reservations[index].pos.x == 18 + 40 + 12)
                assert(reservations[index].size[1] == ruleWidth and reservations[index].size[2] == 18)
                assert(lines[index][1][1] == 100 and lines[index][2][1] == 100 + ruleWidth)
                assert(lines[index][1][2] == 209 and lines[index][2][2] == 209)
            end
        end)
    end)
    Fonts.small = small
    if not ok then error(err, 0) end
end

function T.liveSnapshotDetection()
    assert(ReportWindow.isLiveSnapshot(snapshot("running")) == true)
    assert(ReportWindow.isLiveSnapshot(snapshot("training")) == true)
    assert(ReportWindow.isLiveSnapshot(snapshot("clear")) == false)
    assert(ReportWindow.isLiveSnapshot(nil) == false)
end

function T.liveSnapshotRefreshesOnInterval()
    local calls = 0
    ReportWindow.setSnapshotProvider(function()
        calls = calls + 1
        return snapshot("running")
    end)
    ReportWindow.show(snapshot("running"))
    assert(ReportWindow.refreshLive(10) == true)
    assert(ReportWindow.refreshLive(10.1) == false)
    assert(ReportWindow.refreshLive(10.3) == true)
    assert(calls == 2)
    ReportWindow.hide()
    ReportWindow.setSnapshotProvider(nil)
end

function T.finishedSnapshotNeverRefreshes()
    local calls = 0
    ReportWindow.setSnapshotProvider(function()
        calls = calls + 1
        return snapshot("running")
    end)
    ReportWindow.show(snapshot("clear"))
    assert(ReportWindow.refreshLive(10) == false)
    assert(ReportWindow.refreshLive(11) == false)
    assert(calls == 0)
    ReportWindow.hide()
    ReportWindow.setSnapshotProvider(nil)
end

function T.closedWindowNeverRefreshes()
    local calls = 0
    ReportWindow.setSnapshotProvider(function()
        calls = calls + 1
        return snapshot("running")
    end)
    ReportWindow.show(snapshot("running"))
    ReportWindow.hide()
    assert(ReportWindow.refreshLive(10) == false and calls == 0)
    ReportWindow.setSnapshotProvider(nil)
end

function T.liveRefreshFreezesWhenProviderReportsResult()
    local results = { "running", "unknown" }
    local calls = 0
    ReportWindow.setSnapshotProvider(function()
        calls = calls + 1
        return snapshot(results[calls] or "unknown")
    end)
    ReportWindow.show(snapshot("running"))
    assert(ReportWindow.refreshLive(10) == true)
    assert(ReportWindow.refreshLive(10.5) == true)
    assert(ReportWindow.refreshLive(11) == false)
    assert(calls == 2)
    ReportWindow.hide()
    ReportWindow.setSnapshotProvider(nil)
end

function T.skillDamageNamesComeFromLocale()
    Locale.init({})
    Locale.resolve("en")
    assert(ReportWindow.skillDamageName("violent") == "Violent Strike")
    assert(ReportWindow.skillDamageName("flare") == "Rathalos's Flare")
    assert(ReportWindow.skillDamageName("fury") == "Lagiacrus's Fury")
    assert(ReportWindow.skillDamageName("darkWave") == "Dark Knight")
    assert(ReportWindow.skillDamageName("flayer") == "Flayer")
    assert(ReportWindow.skillDamageName("elementConvert") == "Element Convert")
    Locale.resolve("ko")
    assert(ReportWindow.skillDamageName("mirrorBlade") == "거울대검")
    assert(ReportWindow.skillDamageName("flare") == "화룡의 힘")
    assert(ReportWindow.skillDamageName("fury") == "해룡의 와뢰")
    assert(ReportWindow.skillDamageName("darkWave") == "암흑기사")
    assert(ReportWindow.skillDamageName("flayer") == "쇄인자격")
    assert(ReportWindow.skillDamageName("elementConvert") == "속성 변환")
end

function T.headerWeaponTextJoinsUsedWeapons()
    Locale.init({})
    Locale.resolve("ko")
    assert(ReportWindow.headerWeaponText({ weapons = { { type = 0, name = "대검" }, { type = 13, name = "라이트보우건" } } })
        == "대검, 라이트보우건")
    assert(ReportWindow.headerWeaponText({ weapons = {}, weapon = { type = 13, name = "라이트보우건" } }) == "라이트보우건")
    assert(ReportWindow.headerWeaponText({ weapon = { type = 13, name = "라이트보우건" } }) == "라이트보우건")
    assert(ReportWindow.headerWeaponText({}) == "알 수 없는 무기")
    Locale.resolve("en")
    assert(ReportWindow.headerWeaponText({ weapons = { { type = 0, name = "Great Sword" } } }) == "Great Sword")
    assert(ReportWindow.headerWeaponText({}) == "Unknown weapon")
    assert(Locale.text("used_weapons") == "used_weapons", "used_weapons key must be gone")
end

function T.metaTextJoinsMonstersAndTime()
    assert(ReportWindow.metaText({ monsters = { { name = "미즈츠네" } }, quest = { elapsedSeconds = 754 } }) == "미즈츠네 · 12:34")
    assert(ReportWindow.metaText({ monsters = { { name = "A" }, { id = 7 } }, quest = { elapsedSeconds = 5 } }) == "A, 7 · 0:05")
    assert(ReportWindow.metaText({ monsters = {}, quest = { elapsedSeconds = 65 } }) == "1:05")
    assert(ReportWindow.metaText({}) == "0:00")
end

function T.historyRowSplitsTimeStarsWeaponsMonsters()
    Locale.init({})
    Locale.resolve("ko")
    local entry = snapshot("clear")
    entry.quest.endedAt = os.time({ year = 2026, month = 9, day = 23, hour = 21, min = 36, sec = 0 })
    entry.quest.weapons = { { name = "조충곤" }, { name = "라이트보우건" } }
    entry.quest.weapon = { name = "대검" }
    entry.monsters = { { name = "아자라칸" }, { id = 3 } }
    entry.quest.level = 5
    local row = ReportWindow.historyRow(entry)
    assert(row.time == "2026-09-23 21:36" and row.stars == "★5")
    assert(row.weapons == "조충곤, 라이트보우건" and row.monsters == "아자라칸, 3")
    entry.quest.weapons = {}
    assert(ReportWindow.historyRow(entry).weapons == "대검")
    entry.quest.weapon = nil
    assert(ReportWindow.historyRow(entry).weapons == "알 수 없는 무기")
    entry.quest.result = "training"
    assert(ReportWindow.historyRow(entry).stars == "")
    entry.quest.result = "clear"
    entry.quest.level = nil
    assert(ReportWindow.historyRow(entry).stars == "")
    assert(ReportWindow.historyRow({}).monsters == "" and ReportWindow.historyRow({}).time == require("MyHuntReport.Format").clock(0))
end

function T.skillsHeaderReadsUptimeInKorean()
    Locale.init({})
    Locale.resolve("ko")
    assert(Locale.text("skills_header") == "스킬 업타임")
end

function T.replaceLiveViewIgnoresHistoryEntry()
    local History = require("MyHuntReport.History")
    local live, historical = snapshot("running"), snapshot("clear")
    ReportWindow.show(live)
    ReportWindow.showHistory()
    assert(ReportWindow.replaceLiveView(snapshot("training")) == false)
    assert(ReportWindow.debugState().view == "history")
    local readAll, originalImgui = History.readAll, imgui
    local ok, err = pcall(function()
        History.readAll = function() return { historical } end
        imgui = setmetatable({
            begin_window = function() return true end,
            button = function(label) return label:find("##history1", 1, true) ~= nil end,
        }, { __index = originalImgui })
        ReportWindow.draw()
        assert(ReportWindow.debugState().fromHistory == true)
        assert(ReportWindow.debugState().snapshot == historical)
        assert(ReportWindow.replaceLiveView(snapshot("training")) == false)
        assert(ReportWindow.debugState().snapshot == historical)
        assert(ReportWindow.debugState().fromHistory == true)
        ReportWindow.returnFromHistory()
        ReportWindow.returnFromHistory()
        assert(ReportWindow.debugState().snapshot == live)
    end)
    History.readAll, imgui = readAll, originalImgui
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.returnFromHistoryResumesLiveRefresh()
    local calls = 0
    ReportWindow.setSnapshotProvider(function()
        calls = calls + 1
        return snapshot("running")
    end)
    ReportWindow.show(snapshot("running"))
    assert(ReportWindow.refreshLive(10) == true)
    ReportWindow.showHistory()
    assert(ReportWindow.refreshLive(10.5) == false)
    ReportWindow.returnFromHistory()
    assert(ReportWindow.refreshLive(11) == true)
    assert(calls == 2)
    ReportWindow.hide()
    ReportWindow.setSnapshotProvider(nil)
end

function T.replaceLiveViewClearsSaveWarningAndRefreshDeadline()
    local calls = 0
    ReportWindow.setSnapshotProvider(function()
        calls = calls + 1
        return snapshot("running")
    end)
    ReportWindow.show(snapshot("running"))
    assert(ReportWindow.refreshLive(10) == true)
    ReportWindow.setNotSaved(true)
    local next_ = snapshot("training")
    assert(ReportWindow.replaceLiveView(next_) == true)
    assert(ReportWindow.debugState().snapshot == next_)
    assert(ReportWindow.debugState().notSaved == false)
    assert(ReportWindow.refreshLive(10.1) == true and calls == 2)
    local current = ReportWindow.debugState().snapshot
    ReportWindow.hide()
    assert(ReportWindow.replaceLiveView(snapshot("training")) == false)
    assert(ReportWindow.debugState().snapshot == current)
    ReportWindow.setSnapshotProvider(nil)
end

function T.shareTextPrintsDashForMissingValues()
    assert(ReportWindow.shareText(nil, 100) == "-")
    assert(ReportWindow.shareText(25, 100) == "25.0%")
    assert(ReportWindow.shareText(0, 0) == "0.0%")
end

function T.developerDiagnosticsNeverShowAbsoluteDamage()
    local Log = require("MyHuntReport.Log")
    local originalImgui, developerMode = imgui, Log.isDeveloperMode()
    local shown = snapshot("clear")
    shown.damage = { total = 654321, physical = 456789, element = 123456, fixed = 34567, status = 39509, hits = 1 }
    shown.diagnostics = { weightFallbacks = 2, droppedPending = 3, fightingFallback = true }
    local lines = {}
    local ok, err = pcall(function()
        imgui = setmetatable({
            begin_window = function() return true end,
            text = function(text) lines[#lines + 1] = text end,
        }, { __index = originalImgui })
        Log.setDeveloperMode(true)
        ReportWindow.show(shown)
        ReportWindow.draw()
        assert(ReportWindow.isOpen() == true)
        local drawn = table.concat(lines, "\n")
        assert(drawn:find("weightFallbacks=2", 1, true))
        assert(drawn:find("droppedPending=3", 1, true))
        assert(drawn:find("fightingFallback=true", 1, true))
        for _, amount in ipairs({ "654321", "456789", "123456", "34567", "39509" }) do
            assert(not drawn:find(amount, 1, true))
        end
    end)
    imgui = originalImgui
    Log.setDeveloperMode(developerMode)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.historyEntriesStayFooterFreeAfterLanguageChangeInDeveloperMode()
    local Log = require("MyHuntReport.Log")
    local Session = require("MyHuntReport.Session")
    local originalImgui, developerMode = imgui, Log.isDeveloperMode()
    local entry = snapshot("clear")
    entry.motions = { { label = { kind = "motion", className = "cSlash", guideId = -1 }, damage = 1, hits = 1, share = 1 } }
    local lines = {}
    local ok, err = pcall(function()
        imgui = setmetatable({
            begin_window = function() return true end,
            text = function(text) lines[#lines + 1] = text end,
        }, { __index = originalImgui })
        Log.setDeveloperMode(true)
        ReportWindow.setRelabeler(function(shown) return Session.relabel(shown, function(label) return label.className or label.kind end) end)
        ReportWindow.show(entry)
        ReportWindow.onLanguageChanged()
        ReportWindow.draw()
        assert(entry.diagnostics == nil)
        assert(not table.concat(lines, "\n"):find("weightFallbacks=", 1, true))
    end)
    imgui = originalImgui
    Log.setDeveloperMode(developerMode)
    ReportWindow.setRelabeler(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.barSegmentsFloorGapAndDrop()
    local Theme = require("MyHuntReport.Theme")
    local shares = {
        { id = "phys", color = Theme.colors.physical, share = 0.784 },
        { id = "elem", color = Theme.colors.element, share = 0.162 },
        { id = "fixed", color = Theme.colors.fixed, share = 0.031 },
        { id = "stat", color = Theme.colors.status, share = 0.023 },
    }
    local layout = ReportWindow.barSegments(800, shares, 2)
    assert(#layout.segments == 4)
    assert(layout.segments[1].x == 0 and layout.segments[1].width == 627)
    assert(layout.segments[2].x == 629 and layout.segments[2].width == 129)
    assert(layout.segments[3].x == 760 and layout.segments[3].width == 24)
    assert(layout.segments[4].x == 786 and layout.segments[4].width == 14)
    assert(layout.track.x == 800 and layout.track.width == 0)
    local total = 0
    for _, segment in ipairs(layout.segments) do total = total + segment.width end
    assert(total + 3 * 2 == 800)
    local sparse = ReportWindow.barSegments(100, {
        { id = "phys", share = 0.5 }, { id = "elem", share = 0.004 }, { id = "fixed", share = 0 }, { id = "stat", share = 0.25 },
    }, 2)
    assert(#sparse.segments == 2 and sparse.segments[1].id == "phys" and sparse.segments[2].id == "stat")
    assert(sparse.segments[2].x == 52 and sparse.segments[2].width == 25)
    assert(sparse.track.x == 77 and sparse.track.width == 23)
    local overflow = ReportWindow.barSegments(100, {
        { id = "phys", share = 0.98 }, { id = "elem", share = 0.01 }, { id = "fixed", share = 0.01 },
    }, 2)
    for _, segment in ipairs(overflow.segments) do
        assert(segment.width >= 1 and segment.x + segment.width <= 100)
    end
    assert(overflow.track.x + overflow.track.width == 100)
    assert(#overflow.segments == 1 and overflow.segments[1].id == "phys")
    assert(overflow.segments[1].x == 0 and overflow.segments[1].width == 98)
    assert(overflow.track.x == 98 and overflow.track.width == 2)
    local full = ReportWindow.barSegments(100, { { id = "phys", share = 1 } }, 2)
    assert(#full.segments == 1 and full.segments[1].width == 100 and full.track.width == 0)
    local empty = ReportWindow.barSegments(100, {}, 2)
    assert(#empty.segments == 0 and empty.track.x == 0 and empty.track.width == 100)
end

function T.historyColumnsSplitTheRow()
    local columns = ReportWindow.historyColumns(680, 1, false)
    assert(columns.buttonWidth == 680)
    assert(columns.time.x == 10 and columns.time.width == 150)
    assert(columns.stars.x == 176 and columns.stars.width == 48)
    assert(columns.weapons.x == 240 and columns.weapons.width == 207)
    assert(columns.monsters.x == 463 and columns.monsters.width == 207)
    assert(columns.monsters.x + columns.monsters.width == 680 - 10)
    local scrolling = ReportWindow.historyColumns(680, 1, true)
    assert(scrolling.buttonWidth == 666 and scrolling.weapons.width == 200 and scrolling.monsters.width == 200)
    assert(scrolling.monsters.x + scrolling.monsters.width == 666 - 10)
    local scaled = ReportWindow.historyColumns(1057, 28 / 18, false)
    assert(scaled.time.width == 233 and scaled.stars.width == 75)
    assert(scaled.weapons.width == 340 and scaled.monsters.width == 341)
end

function T.rowAreaLayoutGrowsToTheDataAndCapsAtHalfScreen()
    local small = ReportWindow.rowAreaLayout(3, 1080, 1)
    assert(small.visibleRows == 3 and small.scrolls == false and small.height == 27 * 3 + 4)
    local big = ReportWindow.rowAreaLayout(40, 1080, 1)
    assert(big.visibleRows == 20 and big.scrolls == true, tostring(big.visibleRows))
    local scaled = ReportWindow.rowAreaLayout(40, 1080, 1.5)
    assert(scaled.visibleRows == 15 and scaled.rowHeight == 36)
    local smaller = ReportWindow.rowAreaLayout(40, 1080, 0.8)
    assert(smaller.visibleRows == 23 and smaller.rowHeight == 23)
    local pixels = ReportWindow.rowAreaLayout(40, 1080, 24 / 18)
    assert(pixels.rowHeight == 24 + require("MyHuntReport.Theme").metrics.rowSpacing)
    assert(pixels.visibleRows == 16 and pixels.scrolls == true)
    local empty = ReportWindow.rowAreaLayout(0, 1080, 1)
    assert(empty.visibleRows == 1 and empty.scrolls == false)
    local history = ReportWindow.rowAreaLayout(22, 1080, 1, 36)
    assert(history.rowHeight == 36 and history.visibleRows == 15 and history.scrolls == true and history.height == 36 * 15 + 4)
    local historyScaled = ReportWindow.rowAreaLayout(3, 1080, 24 / 18, 36)
    assert(historyScaled.rowHeight == 48 and historyScaled.visibleRows == 3 and historyScaled.scrolls == false)
end

function T.statTilesFollowTheSnapshot()
    Locale.init({})
    Locale.resolve("en")
    local tiles = ReportWindow.statTiles({ stats = { combatDps = 45.66, critRate = 0.293, negativeCritRate = 0, avgHitzone = 77.7, attribute = 0 } })
    assert(#tiles == 4)
    assert(tiles[1].label == "Combat DPS" and tiles[1].value == "45.7")
    assert(tiles[2].value == "29.3%" and tiles[3].value == "0.0%" and tiles[4].value == "77.7")
    local withElement = ReportWindow.statTiles({ stats = { attribute = 1, avgAttributeHitzone = 29.2 } })
    assert(#withElement == 5 and withElement[5].value == "29.2" and withElement[1].value == "-")
    assert(withElement[5].label == "Fire hitzone", withElement[5].label)
    local training = ReportWindow.statTiles({ quest = { result = "training" }, stats = { combatDps = 45.66, critRate = 0.293, attribute = 0 } })
    assert(#training == 3 and training[1].label == "Crit" and training[1].value == "29.3%")
    assert(ReportWindow.statTiles({ stats = { attribute = 4, avgAttributeHitzone = 10 } })[5].label == "Ice hitzone")
    assert(ReportWindow.statTiles({ stats = { attribute = 9, avgAttributeHitzone = 10 } })[5].label == "Avg elem. hitzone")
    Locale.resolve("ko")
    assert(ReportWindow.statTiles({ stats = { combatDps = 45.66 } })[1].label == "전투 DPS")
    Locale.resolve("en")
end

function T.renderedReportHasNoRowBarsHitsFightingTimeOrMonsterShare()
    local originalImgui = imgui
    local shown = snapshot("clear")
    shown.quest = { result = "clear", elapsedSeconds = 130, weapons = { { type = 0, name = "Great Sword" } } }
    shown.stats = { fightingSeconds = 122, combatDps = 45.7, critRate = 0.29, negativeCritRate = 0, avgHitzone = 77.7, attribute = 0 }
    shown.damage = { total = 1000, physical = 890, element = 110, fixed = 0, status = 0, hits = 78 }
    shown.monsters = { { id = 1, name = "Barrel", damage = 1000, share = 1 } }
    shown.skills = { { id = 115, name = "Burst", share = 0.88, weight = 88 } }
    shown.motions = { { key = "0:cAttack", name = "Overhead Slash", share = 0.41, damage = 410, hits = 3 } }
    local texts, buttons = {}, {}
    local Draw = require("MyHuntReport.Draw")
    local list = stubs.drawList()
    local child, childCalls, rowButtons = nil, nil, 0
    local rowDraws, children = 0, 0
    Draw.resetForTests()
    local ok, err = pcall(function()
        imgui = setmetatable({
            begin_window = function() return true end,
            text = function(text) texts[#texts + 1] = text end,
            button = function(label)
                buttons[#buttons + 1] = label
                if child then rowButtons = rowButtons + 1 end
                return false
            end,
            get_window_draw_list = function() return list end,
            begin_child_window = function(name)
                assert(name == "skill##rows" or name == "motion##rows")
                child, childCalls = name, #list.calls
                children = children + 1
            end,
            end_child_window = function()
                for index = childCalls + 1, #list.calls do
                    local call = list.calls[index]
                    assert(call.name == "add_rect_filled" and call[3] == require("MyHuntReport.Theme").colors.rowStripe)
                end
                rowDraws = rowDraws + #list.calls - childCalls
                child = nil
            end,
        }, { __index = originalImgui })
        Locale.init({})
        Locale.resolve("en")
        ReportWindow.show(shown)
        ReportWindow.draw()
        assert(ReportWindow.isOpen() == true)
        local drawn = table.concat(texts, "\n")
        assert(drawn:find("Great Sword", 1, true) and not drawn:find("Weapons:", 1, true))
        assert(drawn:find("Damage breakdown", 1, true))
        assert(drawn:find("Barrel", 1, true) and not drawn:find("100.0%", 1, true))
        assert(not drawn:find("Hits", 1, true) and not drawn:find("78", 1, true))
        assert(not drawn:find("Fight", 1, true) and not drawn:find("2:02", 1, true))
        assert(drawn:find("Skill uptime", 1, true) and drawn:find("Burst", 1, true) and drawn:find("88.0%", 1, true))
        assert(drawn:find("Overhead Slash", 1, true) and drawn:find("41.0%", 1, true))
        assert(children == 2 and child == nil and #list.calls > 0)
        assert(rowButtons == 0, "button drawn inside report rows")
        assert(rowDraws == 2, "each column's first row must draw only its stripe")
        for _, label in ipairs(buttons) do
            assert(not label:find("^##bar"), "row bar drawn: " .. label)
        end
    end)
    Draw.resetForTests()
    imgui = originalImgui
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.historyButtonStrideMatchesRowAreaLayout()
    local History = require("MyHuntReport.History")
    local settings = require("MyHuntReport.Settings").get()
    local readAll, originalImgui, fontSize = History.readAll, imgui, settings.fontSize
    local entries, buttons, pushes, spacingStack = {}, {}, {}, {}
    local childOpen = false
    for index = 1, 22 do entries[index] = snapshot("clear") end
    local layout = ReportWindow.rowAreaLayout(#entries, 1080, 1, 36)
    local ok, err = pcall(function()
        settings.fontSize = 18
        History.readAll = function() return entries end
        imgui = setmetatable({
            ImGuiStyleVar = { ItemSpacing = 14 },
            begin_window = function() return true end,
            get_display_size = function() return { x = 1920, y = 1080 } end,
            push_style_var = function(index, value)
                pushes[#pushes + 1] = { index = index, value = value }
                spacingStack[#spacingStack + 1] = value
            end,
            pop_style_var = function(count)
                for _ = 1, count do table.remove(spacingStack) end
            end,
            begin_child_window = function(name)
                assert(name == "history##rows")
                childOpen = true
            end,
            end_child_window = function() childOpen = false end,
            button = function(label, size)
                if label:find("##history", 1, true) then
                    buttons[#buttons + 1] = { size = size, spacing = spacingStack[#spacingStack], childOpen = childOpen }
                end
                return false
            end,
        }, { __index = originalImgui })
        ReportWindow.show(snapshot("clear"))
        ReportWindow.showHistory()
        ReportWindow.draw()
        assert(ReportWindow.isOpen() == true)
        assert(#buttons == #entries)
        assert(layout.rowHeight == 36 and layout.scrolls == true)
        for _, button in ipairs(buttons) do
            assert(button.size[2] == layout.rowHeight, "history button height: " .. tostring(button.size[2]))
            assert(button.childOpen and button.spacing.x == 0 and button.spacing.y == 0)
        end
        local zeroSpacing = false
        for _, push in ipairs(pushes) do
            if push.index == 14 and push.value.y == 0 then zeroSpacing = true end
        end
        assert(zeroSpacing)
        assert(not childOpen and #spacingStack == 0)
    end)
    History.readAll, imgui, settings.fontSize = readAll, originalImgui, fontSize
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.placementCentersUntilAPositionIsSaved()
    local display = { x = 1920, y = 1080 }
    assert(ReportWindow.placement({ windowX = -1, windowY = -1 }, display).centered == true)
    assert(ReportWindow.placement({ windowX = 100, windowY = -1 }, display).centered == true)
    local placed = ReportWindow.placement({ windowX = 100, windowY = 200 }, display)
    assert(placed.centered == false and placed.x == 100 and placed.y == 200)
    local clamped = ReportWindow.placement({ windowX = 5000, windowY = 3000 }, display)
    assert(clamped.x == 1920 - 64 and clamped.y == 1080 - 64, tostring(clamped.x) .. "," .. tostring(clamped.y))
end

function T.settledPositionPersistsWithoutClosing()
    local Settings = require("MyHuntReport.Settings")
    Settings.load()
    ReportWindow.show(snapshot("clear"))
    assert(ReportWindow.trackPosition(300, 400, 10) == false)
    assert(ReportWindow.trackPosition(300, 400, 10.5) == false)
    assert(Settings.get().windowX ~= 300)
    assert(ReportWindow.trackPosition(300, 400, 11.1) == true)
    assert(Settings.get().windowX == 300 and Settings.get().windowY == 400)
    assert(ReportWindow.trackPosition(300, 400, 20) == false)
    assert(ReportWindow.trackPosition(310, 400, 21) == false)
    assert(ReportWindow.trackPosition(310, 400, 22.5) == true)
    assert(Settings.get().windowX == 310)
    ReportWindow.hide()
end

function T.sessionStartClosesTheWindowWhenTheOptionIsOn()
    local Settings = require("MyHuntReport.Settings")
    Settings.load()
    Settings.set("closeOnQuestStart", true)
    ReportWindow.show(snapshot("clear"))
    assert(ReportWindow.onSessionStart(snapshot("training")) == "closed")
    assert(ReportWindow.isOpen() == false)
    Settings.set("closeOnQuestStart", false)
    ReportWindow.show(snapshot("clear"))
    assert(ReportWindow.onSessionStart(snapshot("training")) == true)
    assert(ReportWindow.isOpen() == true)
    ReportWindow.hide()
    assert(ReportWindow.onSessionStart(snapshot("training")) == false)
end

function T.closingTheWindowPersistsAMovedPosition()
    local Settings = require("MyHuntReport.Settings")
    Settings.load()
    ReportWindow.show(snapshot("clear"))
    ReportWindow.rememberPosition(100.4, 200.6)
    ReportWindow.hide()
    assert(Settings.get().windowX == 100 and Settings.get().windowY == 201)
    local writes = 0
    local originalSet = Settings.set
    Settings.set = function(...) writes = writes + 1; return originalSet(...) end
    ReportWindow.show(snapshot("clear"))
    ReportWindow.rememberPosition(100, 201)
    ReportWindow.hide()
    Settings.set = originalSet
    assert(writes == 0, "unchanged position must not write")
end

function T.errorClosurePersistsAMovedPosition()
    local Settings = require("MyHuntReport.Settings")
    local Log = require("MyHuntReport.Log")
    local originalImgui, developerMode = imgui, Log.isDeveloperMode()
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        for _, failure in ipairs({ "draw", "begin" }) do
            Settings.load()
            Settings.set("windowX", -1)
            Settings.set("windowY", -1)
            ReportWindow.show(snapshot("clear"))
            ReportWindow.rememberPosition(300, 400)
            imgui = setmetatable({
                begin_window = function()
                    if failure == "begin" then error("boom") end
                    return true
                end,
                get_window_pos = function() return { x = 300, y = 400 } end,
                text = function() error("boom") end,
            }, { __index = originalImgui })
            ReportWindow.draw()
            assert(ReportWindow.isOpen() == false)
            assert(Settings.get().windowX == 300 and Settings.get().windowY == 400, failure)
        end
    end)
    imgui = originalImgui
    Log.setDeveloperMode(developerMode)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.languageChangeRelabelsCurrentAndClearsLiveRefresh()
    local live = snapshot("running")
    local calls = 0
    ReportWindow.setSnapshotProvider(function() calls = calls + 1 return live end)
    ReportWindow.show(live)
    ReportWindow.refreshLive(10)
    ReportWindow.setRelabeler(function(value)
        assert(value == live)
        value.monsters = { { name = "English" } }
        return value
    end)
    local ok, err = pcall(function()
        ReportWindow.onLanguageChanged()
        assert(live.monsters[1].name == "English")
        assert(ReportWindow.refreshLive(10.1) == true and calls == 2)
    end)
    ReportWindow.setRelabeler(nil)
    ReportWindow.setSnapshotProvider(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.languageChangeRelabelsSelectedHistoryAndRetainedLiveWithoutSaving()
    local History = require("MyHuntReport.History")
    local Session = require("MyHuntReport.Session")
    local live, historical = snapshot("running"), snapshot("clear")
    live.monsters = { { label = { kind = "monster", emId = 26 }, name = "live ko" } }
    historical.monsters = { { label = { kind = "monster", emId = 26 }, name = "saved ko" } }
    History.resetForTests()
    assert(History.append(historical))
    local disk = stubs.encode(stubs.files)
    ReportWindow.show(live)
    ReportWindow.showHistory()
    local originalImgui = imgui
    ReportWindow.setRelabeler(function(value)
        return Session.relabel(value, function() return "en" end)
    end)
    local ok, err = pcall(function()
        imgui = setmetatable({
            begin_window = function() return true end,
            button = function(label) return label:find("##history1", 1, true) ~= nil end,
        }, { __index = originalImgui })
        ReportWindow.draw()
        assert(ReportWindow.debugState().fromHistory == true)
        local selected = ReportWindow.debugState().snapshot
        assert(selected.monsters[1].name == "en")
        ReportWindow.onLanguageChanged()
        assert(selected.monsters[1].name == "en")
        assert(live.monsters[1].name == "en")
        assert(stubs.encode(stubs.files) == disk)
        assert(History.readAll()[1].monsters[1].name == "saved ko")
        ReportWindow.returnFromHistory()
        ReportWindow.returnFromHistory()
        assert(ReportWindow.debugState().snapshot == live)
    end)
    imgui = originalImgui
    ReportWindow.setRelabeler(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.languageChangeContainsRelabelErrorsAndStillRefreshes()
    local Log = require("MyHuntReport.Log")
    Log.resetCounts()
    local live = snapshot("running")
    ReportWindow.show(live)
    ReportWindow.setSnapshotProvider(function() return live end)
    ReportWindow.refreshLive(10)
    ReportWindow.setRelabeler(function() error("relabel failure") end)
    local ok, err = pcall(function()
        ReportWindow.onLanguageChanged()
        assert(Log.count("report:relabel") == 1)
        assert(ReportWindow.refreshLive(10.1) == true)
    end)
    ReportWindow.setRelabeler(nil)
    ReportWindow.setSnapshotProvider(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.fontSizeFlowsToReportFontsAndLayout()
    local Settings = require("MyHuntReport.Settings")
    local Fonts = require("MyHuntReport.Fonts")
    local saved = { header = Fonts.header, body = Fonts.body, meta = Fonts.meta, small = Fonts.small }
    local requested, children = {}, {}
    local ok, err = pcall(function()
        for role in pairs(saved) do
            Fonts[role] = function(size) requested[role] = size end
        end
        withNavigation(function(ui)
            Settings.get().fontSize = 24
            imgui.begin_child_window = function(name, size) children[name] = size end
            ReportWindow.show(snapshot("clear"))
            ui.draw()
            assert(ReportWindow.isOpen())
            assert(requested.header == 24 and requested.body == 24 and requested.meta == 24 and requested.small == 24)
            assert(children["skill##rows"][1] == 437)
            assert(children["motion##rows"][1] == 437)
            assert(children["skill##rows"][2] == 37)
            assert(children["motion##rows"][2] == 37)
        end)
    end)
    for role, fn in pairs(saved) do Fonts[role] = fn end
    if not ok then error(err, 0) end
end

function T.historyClearedReloadsCachedEntries()
    withNavigation(function(ui)
        ui.entries = { snapshot("clear") }
        ReportWindow.showHistory()
        ui.draw()
        assert(table.concat(ui.buttons, "|"):find("##history1", 1, true))
        ui.entries = {}
        ui.draw()
        assert(table.concat(ui.buttons, "|"):find("##history1", 1, true))
        ReportWindow.onHistoryCleared()
        assert(ReportWindow.isOpen() and ReportWindow.debugState().view == "history")
        ui.draw()
        assert(not table.concat(ui.buttons, "|"):find("##history1", 1, true))
        local empty = false
        for _, event in ipairs(ui.events) do
            if event.kind == "text" and event.value == Locale.text("history_empty") then empty = true end
        end
        assert(empty)
    end)
end

function T.historyClearedPreservesOpenSnapshotsAndReturnState()
    withNavigation(function(ui)
        local live, saved = snapshot("clear"), snapshot("clear")
        ReportWindow.show(live)
        ReportWindow.setNotSaved(true)
        ReportWindow.onHistoryCleared()
        assert(ReportWindow.isOpen() and ReportWindow.debugState().snapshot == live)
        assert(ReportWindow.debugState().notSaved and not ReportWindow.debugState().fromHistory)
        ui.entries = { saved }
        ReportWindow.showHistory()
        ui.draw("##history1")
        ui.entries = {}
        ReportWindow.onHistoryCleared()
        assert(ReportWindow.isOpen() and ReportWindow.debugState().snapshot == saved)
        assert(ReportWindow.debugState().view == "report" and ReportWindow.debugState().fromHistory)
        ui.draw("<##back")
        ui.draw()
        assert(not table.concat(ui.buttons, "|"):find("##history1", 1, true))
        ui.draw("<##back")
        assert(ReportWindow.debugState().snapshot == live and ReportWindow.debugState().notSaved)
    end)
end

function T.elementTilesUseListOrderAndSuppressLegacyTileWhenListExists()
    Locale.init({})
    Locale.resolve("en")
    local stats = { attribute = 1, avgAttributeHitzone = 99, attributeHitzones = {
        { attribute = 3, avgHitzone = 22.26, hits = 3 },
        { attribute = 1, avgHitzone = 15.75, hits = 2 },
    } }
    local tiles = ReportWindow.statTiles({ stats = stats })
    assert(#tiles == 6)
    assert(tiles[5].label == "Thunder hitzone" and tiles[5].value == "22.3")
    assert(tiles[6].label == "Fire hitzone" and tiles[6].value == "15.8")
    stats.attributeHitzones = {}
    assert(#ReportWindow.statTiles({ stats = stats }) == 4)
    stats.attributeHitzones = nil
    tiles = ReportWindow.statTiles({ stats = stats })
    assert(#tiles == 5 and tiles[5].label == "Fire hitzone" and tiles[5].value == "99.0")
end

function T.reportDrawsTwoElementTilesInSnapshotOrder()
    withNavigation(function(ui)
        Locale.resolve("en")
        local shown = snapshot("clear")
        shown.stats = { attribute = 1, avgAttributeHitzone = 99, attributeHitzones = {
            { attribute = 3, avgHitzone = 22.26, hits = 3 },
            { attribute = 1, avgHitzone = 15.75, hits = 2 },
        } }
        ReportWindow.show(shown)
        ui.draw()
        local texts = {}
        for _, event in ipairs(ui.events) do
            if event.kind == "text" then texts[#texts + 1] = event.value end
        end
        local drawn = table.concat(texts, "\n")
        assert(drawn:find("Thunder hitzone\nFire hitzone", 1, true), drawn)
        assert(drawn:find("22.3\n15.8", 1, true), drawn)
        assert(not drawn:find("99.0", 1, true))
    end)
end

function T.draw_refreshesTextLanguageAndRelabelsWhenTheRawValueChanges()
    local Fonts = require("MyHuntReport.Fonts")
    local ok, err = pcall(function()
        withNavigation(function(ui)
            local code, raw, calls = "en", 11, 0
            Locale.init({ gameLanguage = function() return code, raw end })
            Locale.resolve("auto")
            ReportWindow.setRelabeler(function() calls = calls + 1 end)
            ReportWindow.show(snapshot("clear"))
            ui.draw()
            assert(Fonts.mode() == "default")
            assert(calls == 0, tostring(calls))
            code, raw = "ko", 9
            ui.draw()
            assert(calls == 1, tostring(calls))
            assert(Fonts.mode() == "bundled")
            ui.draw()
            assert(calls == 1, tostring(calls))
        end)
    end)
    ReportWindow.setRelabeler(nil)
    Fonts.setMode(true)
    Locale.init({ gameLanguage = function() return nil end })
    Locale.resolve("en")
    if not ok then error(err, 0) end
end

function T.historyEntriesAreRelabeledOnLoadAndOnLanguageChange()
    local ok, err = pcall(function()
        withNavigation(function(ui)
            ui.entries = { snapshot("clear"), snapshot("clear") }
            local retained = snapshot("clear")
            ReportWindow.show(retained)
            local calls, counts = 0, {}
            ReportWindow.setRelabeler(function(value)
                calls = calls + 1
                counts[value] = (counts[value] or 0) + 1
            end)
            ReportWindow.showHistory()
            ui.draw()
            assert(calls == 2, tostring(calls))
            assert(counts[ui.entries[1]] == 1 and counts[ui.entries[2]] == 1)
            ReportWindow.onLanguageChanged()
            assert(calls == 6, tostring(calls))
            assert(counts[ui.entries[1]] == 2 and counts[ui.entries[2]] == 2)
            assert(counts[retained] == 2, tostring(counts[retained]))
        end)
    end)
    ReportWindow.setRelabeler(nil)
    if not ok then error(err, 0) end
end

function T.draw_usesDefaultFontSizePushesWhenBundledFontDoesNotCover()
    local Fonts = require("MyHuntReport.Fonts")
    local covers = Locale.bundledFontCovers
    local ok, err = pcall(function()
        withNavigation(function(ui)
            local fontPushes, sizePushes = 0, 0
            local sizePushTotal = 0
            imgui.push_font = function() fontPushes = fontPushes + 1 end
            imgui.pop_font = function() end
            imgui.push_font_size = function(size)
                assert(type(size) == "number" and size >= 18)
                sizePushes = sizePushes + 1
                sizePushTotal = sizePushTotal + 1
            end
            imgui.pop_font_size = function() sizePushes = sizePushes - 1 end
            Locale.bundledFontCovers = function() return false end
            ReportWindow.show(snapshot("clear"))
            ui.draw()
            assert(ReportWindow.isOpen())
            assert(Fonts.mode() == "default")
            assert(fontPushes == 0, "default mode must not push Pretendard handles")
            assert(sizePushes == 0, "every push_font_size must be popped")
            assert(sizePushTotal > 0, "default mode must push font sizes")
            Locale.bundledFontCovers = function() return true end
            ui.draw()
            assert(Fonts.mode() == "bundled")
        end)
    end)
    Locale.bundledFontCovers = covers
    Fonts.setMode(true)
    if not ok then error(err, 0) end
end

function T.hpRowsCarryTheHpPrefix()
    withNavigation(function(ui)
        local shown = snapshot("clear")
        shown.skills = {
            { name = "Skill", share = 0.5 },
            { name = "Hasten Recovery", share = 0.24, valueKind = "hp" },
        }
        ReportWindow.show(shown)
        ui.draw()
        local texts, inRows = {}, false
        for _, event in ipairs(ui.events) do
            if event.kind == "row" and event.value == "skill1" then inRows = true end
            if inRows and event.kind == "text" then texts[#texts + 1] = event.value end
        end
        local joined = table.concat(texts, "|")
        assert(joined:find("Skill|50.0%|", 1, true), joined)
        assert(joined:find("Hasten Recovery|HP 24.0%", 1, true), joined)
    end)
end

function T.hpRowNamesReserveMeasuredValueWidth()
    withNavigation(function(ui)
        require("MyHuntReport.Settings").get().fontSize = 14
        local calcTextSize = imgui.calc_text_size
        imgui.calc_text_size = function(text) return { x = #text * 8, y = 18 } end
        local fullName = "Hasten Recovery with a very long skill name"
        local ordinaryName = "Ordinary skill name 12"
        local shown = snapshot("clear")
        shown.skills = {
            { name = fullName, share = 1.4, valueKind = "hp" },
            { name = ordinaryName, share = 0.5 },
        }
        ReportWindow.show(shown)
        ui.draw()
        imgui.calc_text_size = calcTextSize
        local rows, current = {}, nil
        for _, event in ipairs(ui.events) do
            if event.kind == "row" then
                current = {}
                rows[event.value] = current
            elseif current and event.kind == "text" then
                current[#current + 1] = event
                if #current == 2 then current = nil end
            end
        end
        local hp, ordinary = rows.skill1, rows.skill2
        assert(hp and #hp == 2 and ordinary and #ordinary == 2, "missing skill rows")
        local name = hp[1].value
        assert(#name < #fullName and name:sub(-#"…") == "…", name)
        assert(fullName:sub(1, #name - #"…") == name:sub(1, -#"…" - 1), name)
        assert(hp[2].value == "HP 140.0%", hp[2].value)
        local valuePosition = ui.positions[hp[2].positionCount]
        assert(#name * 8 <= valuePosition.x - 8, "clipped name overlaps HP value reservation")
        assert(ordinary[1].value == ordinaryName, ordinary[1].value)
        assert(ordinary[2].value == "50.0%", ordinary[2].value)
    end)
end

function T.drawAppliesTheHdrTargetForTheCurrentSettingOnlyWhileOpen()
    local Hdr = require("MyHuntReport.Hdr")
    local Settings = require("MyHuntReport.Settings")
    local Theme = require("MyHuntReport.Theme")
    local targetNits, apply, originalImgui = Hdr.targetNits, Theme.apply, imgui
    local settingsSeen, applied = {}, {}
    Settings.load()
    Settings.set("hdrCorrection", "on")
    ReportWindow.show(snapshot("clear"))
    local ok, err = pcall(function()
        Hdr.targetNits = function(setting)
            settingsSeen[#settingsSeen + 1] = setting
            return 455
        end
        Theme.apply = function(nits) applied[#applied + 1] = nits end
        imgui = setmetatable({ begin_window = function() return true end }, { __index = originalImgui })
        ReportWindow.draw()
        assert(#settingsSeen == 1 and settingsSeen[1] == "on", tostring(settingsSeen[1]))
        assert(#applied == 1 and applied[1] == 455)
        ReportWindow.hide()
        ReportWindow.draw()
        assert(#settingsSeen == 1 and #applied == 1)
    end)
    Hdr.targetNits, Theme.apply, imgui = targetNits, apply, originalImgui
    ReportWindow.hide()
    Settings.set("hdrCorrection", "auto")
    if not ok then error(err, 0) end
end

return T
