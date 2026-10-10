local Theme = require("MyHuntReport.Theme")

local T = {}

function T.rgbPacksImU32InAbgrOrder()
    assert(Theme.rgb("#D8B46B") == 0xFF6BB4D8, string.format("%08X", Theme.rgb("#D8B46B")))
    assert(Theme.rgb("D8B46B") == 0xFF6BB4D8)
    assert(Theme.rgb("#1B1815", 0.95) == 0xF215181B, string.format("%08X", Theme.rgb("#1B1815", 0.95)))
    assert(Theme.rgb("#000000", 0) == 0x00000000)
    assert(Theme.rgb("#FFFFFF") == 0xFFFFFFFF)
    assert(not pcall(Theme.rgb, "#12345"))
    assert(not pcall(Theme.rgb, "#GG0000"))
end

function T.paletteMatchesTheSpec()
    local c = Theme.colors
    assert(c.windowBg == 0xF215181B and c.rule == 0xFF2A3035 and c.barTrack == 0xFF20252A)
    assert(c.text == 0xFFD6E4EC and c.textMuted == 0xFF83909A)
    assert(c.accent == 0xFF6BB4D8 and c.accentDim == 0xFF2A3F4A and c.physical == c.accent)
    assert(c.element == 0xFFA5B85B and c.fixed == 0xFF458AE0 and c.status == 0xFFD68BA8)
    assert(c.warning == 0xFF5A69D9 and c.childBg == 0 and c.scrollbarBg == 0 and c.transparent == 0)
    assert(c.border == nil and c.clear == nil and c.fail == nil and c.neutral == nil)
end

function T.metricsMatchTheSpec()
    local m = Theme.metrics
    assert(m.padding == 24 and m.rounding == 6 and m.itemSpacing == 10 and m.rowSpacing == 9)
    assert(m.barHeight == 8 and m.barGap == 2 and m.columnGap == 32 and m.percentColumnWidth == 72)
    assert(m.scrollbarWidth == 14 and m.minWindowWidth == 720 and m.topBarHeight == 36 and m.titleGap == 12)
    assert(m.tileGap == 16)
    assert(m.iconButton == 36 and m.navButtonWidth == 92 and m.chipGap == 14)
    assert(m.iconSize == 20 and m.iconStroke == 2)
    assert(m.sectionGap == 16 and m.labelGap == 2 and m.ruleGap == 12 and m.footerGap == 12)
    assert(m.dotRadius == 4 and m.legendGap == 28 and m.procGap == 20)
    assert(m.historyRowHeight == 36 and m.historyPadding == 10 and m.historyTimeWidth == 132)
    assert(m.historyStarsWidth == 48 and m.historyGap == 16)
    assert(m.childIndent == 16)
end

function T.rowStripeMatchesTheSpec()
    assert(Theme.colors.rowStripe == Theme.rgb("#FFFFFF", 0.04))
    assert(Theme.colors.rowStripe == 0x0AFFFFFF)
    assert(Theme.metrics.stripeRounding == 3)
end

function T.paletteSourceCoversEveryColour()
    local count = 0
    for name, source in pairs(Theme.PALETTE) do
        count = count + 1
        assert(Theme.colors[name] == Theme.rgb(source[1], source[2]), name)
    end
    assert(count == 17, count)
    for name in pairs(Theme.colors) do assert(Theme.PALETTE[name] ~= nil, name) end
    assert(Theme.PALETTE.windowBg[1] == "#1B1815" and Theme.PALETTE.windowBg[2] == 0.95)
    assert(Theme.PALETTE.rowStripe[1] == "#FFFFFF" and Theme.PALETTE.rowStripe[2] == 0.04)
end

function T.applyRewritesTheSameTableForHdrAndRestoresSdr()
    local Hdr = require("MyHuntReport.Hdr")
    local colors = Theme.colors
    local ok, err = pcall(function()
        assert(Theme.apply(455) == true)
        assert(Theme.colors == colors)
        for name, source in pairs(Theme.PALETTE) do
            assert(colors[name] == Hdr.convert(source[1], source[2], 455), name)
        end
        assert(colors.text ~= Theme.rgb("#ECE4D6") and colors.windowBg >> 24 == 0xF2 and colors.transparent == 0)
        assert(Theme.apply(455) == false)
        assert(Theme.apply(200) == true)
        assert(colors.text == Hdr.convert("#ECE4D6", 1, 200))
        assert(Theme.apply(nil) == true)
        assert(Theme.colors == colors)
        for name, source in pairs(Theme.PALETTE) do
            assert(colors[name] == Theme.rgb(source[1], source[2]), name)
        end
        assert(Theme.apply(nil) == false)
    end)
    Theme.apply(nil)
    if not ok then error(err, 0) end
end

function T.applySkipsTheRewriteWhenTheValueIsUnchanged()
    local ok, err = pcall(function()
        Theme.apply(455)
        Theme.colors.text = 1
        assert(Theme.apply(455) == false and Theme.colors.text == 1)
        assert(Theme.apply(nil) == true and Theme.colors.text == Theme.rgb("#ECE4D6"))
    end)
    Theme.apply(nil)
    if not ok then error(err, 0) end
end

function T.applyRetriesAfterAFailedConversion()
    local Hdr = require("MyHuntReport.Hdr")
    local convert = Hdr.convert
    local ok, err = pcall(function()
        Hdr.convert = function() error("boom") end
        assert(not pcall(Theme.apply, 455))
        Hdr.convert = convert
        assert(Theme.apply(455) == true)
        assert(Theme.colors.text == convert("#ECE4D6", 1, 455))
    end)
    Hdr.convert = convert
    Theme.apply(nil)
    if not ok then error(err, 0) end
end

local function withStyleRecorder(callback)
    local original = imgui
    local colors, vars = {}, {}
    local underflow = false
    local ok, err = pcall(function()
        imgui = setmetatable({
            ImGuiStyleVar = { Alpha = 0, WindowPadding = 2, WindowRounding = 3, WindowBorderSize = 4,
                FrameRounding = 12, FrameBorderSize = 13, ItemSpacing = 14, ButtonTextAlign = 23 },
            push_style_color = function(index, color) colors[#colors + 1] = { index, color } end,
            pop_style_color = function(count) for _ = 1, count do if not table.remove(colors) then underflow = true end end end,
            push_style_var = function(index, value) vars[#vars + 1] = { index, value } end,
            pop_style_var = function(count) for _ = 1, count do if not table.remove(vars) then underflow = true end end end,
        }, { __index = original })
        callback(colors, vars, function() return underflow end)
    end)
    imgui = original
    if not ok then error(err, 0) end
end

local function byIndex(list)
    local map = {}
    for _, item in ipairs(list) do map[item[1]] = item[2] end
    return map
end

function T.windowStyleUsesGhostButtonsAndRuleBorder()
    withStyleRecorder(function(colors, vars, underflow)
        local token = Theme.pushWindow()
        local c, v = byIndex(colors), byIndex(vars)
        assert(c[2] == Theme.colors.windowBg and c[5] == Theme.colors.rule and c[0] == Theme.colors.text)
        assert(c[21] == 0 and c[22] == Theme.colors.accentDim and c[23] == Theme.colors.accentDim)
        assert(c[7] == Theme.colors.barTrack and c[15] == Theme.colors.rule)
        assert(c[27] == nil, "separator color must not be pushed")
        assert(v[3] == 6 and v[4] == 1 and v[12] == 4 and v[13] == 1)
        assert(v[2].x == 24 and v[2].y == 24 and v[14].x == 10 and v[14].y == 10)
        Theme.popWindow(token)
        assert(underflow() == false, "style stack underflow")
        assert(#colors == 0 and #vars == 0)
    end)
end

function T.listRowStyleIsTransparentUntilHovered()
    withStyleRecorder(function(colors, vars, underflow)
        local token = Theme.pushListRows()
        local c, v = byIndex(colors), byIndex(vars)
        assert(c[21] == 0 and c[22] == Theme.colors.accentDim and c[23] == Theme.colors.accentDim)
        assert(v[13] == 0 and v[12] == 4 and v[14].x == 0 and v[14].y == 0)
        assert(v[23] == nil, "no text alignment push; row texts are drawn separately")
        Theme.popListRows(token)
        assert(underflow() == false, "style stack underflow")
        assert(#colors == 0 and #vars == 0)
    end)
end

function T.barStyleFillsButtonsWithTheGivenColor()
    withStyleRecorder(function(colors, vars, underflow)
        local token = Theme.pushBar(Theme.colors.element, 4)
        local c, v = byIndex(colors), byIndex(vars)
        assert(c[21] == Theme.colors.element and c[22] == Theme.colors.element and c[23] == Theme.colors.element)
        assert(v[12] == 4 and v[13] == 0 and v[14].x == 0 and v[14].y == 0)
        Theme.popBar(token)
        assert(underflow() == false, "style stack underflow")
        assert(#colors == 0 and #vars == 0)
    end)
end

function T.rowStyleMatchesRowAreaSpacing()
    withStyleRecorder(function(colors, vars, underflow)
        local token = Theme.pushRows()
        local v = byIndex(vars)
        assert(#colors == 0 and #vars == 1)
        assert(v[14].x == 10 and v[14].y == 9)
        Theme.popRows(token)
        assert(underflow() == false, "style stack underflow")
        assert(#colors == 0 and #vars == 0)
    end)
end

return T
