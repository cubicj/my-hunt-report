local ReportLayout = require("MyHuntReport.ReportLayout")

local T = {}

function T.layoutModuleLoadsWithoutTheReportWindow()
    local required = {}
    local environment = setmetatable({
        require = function(name)
            required[#required + 1] = name
            return require(name)
        end,
    }, { __index = _G })
    local module = assert(loadfile("reframework/autorun/MyHuntReport/ReportLayout.lua", "t", environment))()
    assert(type(module.placement) == "function" and type(ReportLayout.wrapBreaks) == "function")
    for _, name in ipairs(required) do assert(name ~= "MyHuntReport.ReportWindow", name) end
end

function T.placementCentersUntilAPositionIsSaved()
    local display = { x = 1920, y = 1080 }
    assert(ReportLayout.placement({ windowX = -1, windowY = -1 }, display).centered == true)
    assert(ReportLayout.placement({ windowX = 100, windowY = -1 }, display).centered == true)
    local placed = ReportLayout.placement({ windowX = 100, windowY = 200 }, display)
    assert(placed.centered == false and placed.x == 100 and placed.y == 200)
    local clamped = ReportLayout.placement({ windowX = 5000, windowY = 3000 }, display)
    assert(clamped.x == 1920 - 64 and clamped.y == 1080 - 64, tostring(clamped.x) .. "," .. tostring(clamped.y))
end

function T.rowAreaLayoutGrowsToTheDataAndCapsAtHalfScreen()
    local small = ReportLayout.rowAreaLayout(3, 1080, 1)
    assert(small.visibleRows == 3 and small.scrolls == false and small.height == 27 * 3 + 4)
    local big = ReportLayout.rowAreaLayout(40, 1080, 1)
    assert(big.visibleRows == 20 and big.scrolls == true, tostring(big.visibleRows))
    local scaled = ReportLayout.rowAreaLayout(40, 1080, 1.5)
    assert(scaled.visibleRows == 15 and scaled.rowHeight == 36)
    local smaller = ReportLayout.rowAreaLayout(40, 1080, 0.8)
    assert(smaller.visibleRows == 23 and smaller.rowHeight == 23)
    local pixels = ReportLayout.rowAreaLayout(40, 1080, 24 / 18)
    assert(pixels.rowHeight == 24 + require("MyHuntReport.Theme").metrics.rowSpacing)
    assert(pixels.visibleRows == 16 and pixels.scrolls == true)
    local empty = ReportLayout.rowAreaLayout(0, 1080, 1)
    assert(empty.visibleRows == 1 and empty.scrolls == false)
    local history = ReportLayout.rowAreaLayout(22, 1080, 1, 36)
    assert(history.rowHeight == 36 and history.visibleRows == 15 and history.scrolls == true and history.height == 36 * 15 + 4)
    local historyScaled = ReportLayout.rowAreaLayout(3, 1080, 24 / 18, 36)
    assert(historyScaled.rowHeight == 48 and historyScaled.visibleRows == 3 and historyScaled.scrolls == false)
end

function T.barSegmentsFloorGapAndDrop()
    local Theme = require("MyHuntReport.Theme")
    local shares = {
        { id = "phys", color = Theme.colors.physical, share = 0.784 },
        { id = "elem", color = Theme.colors.element, share = 0.162 },
        { id = "fixed", color = Theme.colors.fixed, share = 0.031 },
        { id = "stat", color = Theme.colors.status, share = 0.023 },
    }
    local layout = ReportLayout.barSegments(800, shares, 2)
    assert(#layout.segments == 4)
    assert(layout.segments[1].x == 0 and layout.segments[1].width == 627)
    assert(layout.segments[2].x == 629 and layout.segments[2].width == 129)
    assert(layout.segments[3].x == 760 and layout.segments[3].width == 24)
    assert(layout.segments[4].x == 786 and layout.segments[4].width == 14)
    assert(layout.track.x == 800 and layout.track.width == 0)
    local total = 0
    for _, segment in ipairs(layout.segments) do total = total + segment.width end
    assert(total + 3 * 2 == 800)
    local sparse = ReportLayout.barSegments(100, {
        { id = "phys", share = 0.5 }, { id = "elem", share = 0.004 }, { id = "fixed", share = 0 }, { id = "stat", share = 0.25 },
    }, 2)
    assert(#sparse.segments == 2 and sparse.segments[1].id == "phys" and sparse.segments[2].id == "stat")
    assert(sparse.segments[2].x == 52 and sparse.segments[2].width == 25)
    assert(sparse.track.x == 77 and sparse.track.width == 23)
    local overflow = ReportLayout.barSegments(100, {
        { id = "phys", share = 0.98 }, { id = "elem", share = 0.01 }, { id = "fixed", share = 0.01 },
    }, 2)
    for _, segment in ipairs(overflow.segments) do
        assert(segment.width >= 1 and segment.x + segment.width <= 100)
    end
    assert(overflow.track.x + overflow.track.width == 100)
    assert(#overflow.segments == 1 and overflow.segments[1].id == "phys")
    assert(overflow.segments[1].x == 0 and overflow.segments[1].width == 98)
    assert(overflow.track.x == 98 and overflow.track.width == 2)
    local full = ReportLayout.barSegments(100, { { id = "phys", share = 1 } }, 2)
    assert(#full.segments == 1 and full.segments[1].width == 100 and full.track.width == 0)
    local empty = ReportLayout.barSegments(100, {}, 2)
    assert(#empty.segments == 0 and empty.track.x == 0 and empty.track.width == 100)
end

function T.historyColumnsSplitTheRow()
    local columns = ReportLayout.historyColumns(680, 1, false)
    assert(columns.buttonWidth == 680)
    assert(columns.time.x == 10 and columns.time.width == 132)
    assert(columns.stars.x == 346 and columns.stars.width == 48)
    assert(columns.weapons.x == 158 and columns.weapons.width == 172)
    assert(columns.monsters.x == 410 and columns.monsters.width == 260)
    assert(columns.monsters.x + columns.monsters.width == 680 - 10)
    local scrolling = ReportLayout.historyColumns(680, 1, true)
    assert(scrolling.buttonWidth == 666 and scrolling.weapons.width == 167 and scrolling.monsters.width == 251)
    assert(scrolling.monsters.x + scrolling.monsters.width == 666 - 10)
    local scaled = ReportLayout.historyColumns(1057, 28 / 18, false)
    assert(scaled.time.width == 205 and scaled.stars.width == 75)
    assert(scaled.weapons.width == 283 and scaled.monsters.width == 426)
end

function T.tileLayoutUsesEqualColumnsAndGridWrap()
    local cases = {
        { { 100, 100, 100 }, 600, 20, { { 1, 0 }, { 1, 200 }, { 1, 400 } } },
        { { 200, 200, 200, 200 }, 600, 20, { { 1, 0 }, { 1, 300 }, { 2, 0 }, { 2, 300 } } },
        { { 700 }, 600, 20, { { 1, 0 } } },
        { { 0, 0, 0, 0 }, 680, 0, { { 1, 0 }, { 1, 170 }, { 1, 340 }, { 1, 510 } } },
        { {}, 600, 20, {} },
        { { 98, 82, 82, 82, 82, 82, 82 }, 720, 16, { { 1, 0 }, { 1, 120 }, { 1, 240 }, { 1, 360 }, { 1, 480 }, { 1, 600 }, { 2, 0 } } },
        { { 132, 100, 100, 100, 100, 100 }, 720, 16, { { 1, 0 }, { 1, 180 }, { 1, 360 }, { 1, 540 }, { 2, 0 }, { 2, 180 } } },
        { { 100, 100, 550, 100 }, 720, 16, { { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 } } },
    }
    local columnWidths = { 200, 300, 600, 170, 0, 120, 180, 720 }
    for index, case in ipairs(cases) do
        local layout = ReportLayout.tileLayout(case[1], case[2], case[3])
        assert(#layout == #case[4], "case " .. index)
        local rowCounts = {}
        for _, position in ipairs(layout) do
            rowCounts[position.row] = (rowCounts[position.row] or 0) + 1
        end
        for tile, expected in ipairs(case[4]) do
            assert(layout[tile].row == expected[1] and layout[tile].x == expected[2], "case " .. index .. " tile " .. tile)
            assert(math.type(layout[tile].x) == "integer")
            assert(layout[tile].x % columnWidths[index] == 0, "case " .. index .. " tile " .. tile .. " is off grid")
            assert(rowCounts[layout[tile].row] == 1 or layout[tile].x + case[1][tile] <= case[2],
                "case " .. index .. " tile " .. tile .. " exceeds row width")
        end
    end
end

function T.wrapBreaksStartANewLineOnlyWhenTheNextItemOverflows()
    local cases = {
        { { 100, 100, 100 }, 340, 20, { false, false, false } },
        { { 100, 100, 100 }, 339, 20, { false, false, true } },
        { { 300, 300, 300 }, 400, 20, { false, true, true } },
        { { 900, 100, 100 }, 400, 20, { false, true, false } },
        { { 100, 900, 100 }, 400, 20, { false, true, true } },
        { {}, 400, 20, {} },
    }
    for index, case in ipairs(cases) do
        local breaks = ReportLayout.wrapBreaks(case[1], case[2], case[3])
        assert(#breaks == #case[4], "case " .. index)
        for item, expected in ipairs(case[4]) do
            assert(breaks[item] == expected, "case " .. index .. " item " .. item)
        end
    end
end

return T
