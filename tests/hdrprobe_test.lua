local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Draw = require("MyHuntReport.Draw")

local T = {}

local function hdrLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] hdr ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function near(actual, expected, tolerance)
    return math.abs(actual - expected) <= tolerance
end

local function withProbe(callback)
    local callStatic, uptime = Game.callStatic, Game.uptime
    local c = { now = 100.0, values = {}, calls = 0, argCounts = {} }
    local ok, err = pcall(function()
        stubs.reset()
        Log.setDeveloperMode(true)
        Log.resetCounts()
        Draw.resetForTests()
        Game.callStatic = function(typeName, signature, ...)
            c.calls = c.calls + 1
            local arg = ...
            local key = typeName .. "." .. signature
            c.argCounts[key] = select("#", ...)
            if arg ~= nil then key = key .. "#" .. tostring(arg) end
            return c.values[key]
        end
        Game.uptime = function() return c.now end
        c.probe = assert(loadfile("reframework/autorun/MyHuntReport/HdrProbe.lua"))()
        callback(c)
    end)
    Game.callStatic, Game.uptime = callStatic, uptime
    Log.setDeveloperMode(false)
    Draw.resetForTests()
    if not ok then error(err, 0) end
end

function T.pqEncodeMatchesTheReferencePoints()
    withProbe(function(c)
        assert(near(c.probe.pqEncode(100), 0.508, 0.001), c.probe.pqEncode(100))
        assert(near(c.probe.pqEncode(1000), 0.752, 0.001), c.probe.pqEncode(1000))
        assert(near(c.probe.pqEncode(10000), 1.0, 0.000001), c.probe.pqEncode(10000))
        assert(c.probe.pqEncode(0) < 0.000001, c.probe.pqEncode(0))
    end)
end

function T.decodeUsesThePiecewiseCurveOrPureGamma()
    withProbe(function(c)
        assert(c.probe.decode(0, "srgb") == 0 and c.probe.decode(0, "2.2") == 0)
        assert(near(c.probe.decode(1, "srgb"), 1, 0.000001) and near(c.probe.decode(1, "2.2"), 1, 0.000001))
        assert(near(c.probe.decode(0.04045, "srgb"), 0.04045 / 12.92, 0.000001))
        assert(near(c.probe.decode(0.5, "srgb"), 0.2140, 0.0001), c.probe.decode(0.5, "srgb"))
        assert(near(c.probe.decode(0.5, "2.2"), 0.2176, 0.0001), c.probe.decode(0.5, "2.2"))
    end)
end

function T.whiteConvertsToThePqCodeOfTheReferenceWhiteOnEveryChannel()
    withProbe(function(c)
        for _, nits in ipairs({ 80, 200, 500 }) do
            local expected = c.probe.pqEncode(nits)
            local r, g, b = c.probe.convertChannels("#FFFFFF", nits, "srgb")
            assert(near(r, expected, 0.0001) and near(g, expected, 0.0001) and near(b, expected, 0.0001),
                nits .. ": " .. r .. " " .. g .. " " .. b .. " vs " .. expected)
        end
    end)
end

function T.blackStaysBlack()
    withProbe(function(c)
        local r, g, b = c.probe.convertChannels("#000000", 200, "srgb")
        assert(r < 0.000001 and g < 0.000001 and b < 0.000001)
        assert(c.probe.converted("#000000", 200, "srgb") == 0xFF000000)
    end)
end

function T.saturatedRedIsPulledInsideTheWiderGamut()
    withProbe(function(c)
        local r, g, b = c.probe.convertChannels("#FF0000", 200, "srgb")
        assert(near(r, c.probe.pqEncode(0.6274 * 200), 0.0001), r)
        assert(near(g, c.probe.pqEncode(0.0691 * 200), 0.0001), g)
        assert(near(b, c.probe.pqEncode(0.0164 * 200), 0.0001), b)
        assert(g > 0 and b > 0)
    end)
end

function T.packWritesAbgrAndPassesAlphaThrough()
    withProbe(function(c)
        assert(c.probe.original("#D8B46B") == 0xFF6BB4D8)
        assert(c.probe.original("#D8B46B", 0.5) == 0x806BB4D8)
        assert(c.probe.converted("#FFFFFF", 200, "srgb", 0.5) >> 24 == 0x80)
        local code = math.floor(c.probe.pqEncode(200) * 255 + 0.5)
        assert(c.probe.converted("#FFFFFF", 200, "srgb") == (0xFF << 24) | (code << 16) | (code << 8) | code)
    end)
end

function T.sourcesCoverTheConfirmedGettersAndTheOptionPairs()
    withProbe(function(c)
        local fields = {}
        for index, source in ipairs(c.probe.SOURCES) do fields[index] = source.field end
        assert(table.concat(fields, " ") == "hdrMode hdrEnable colorSpace rendererColorSpace "
            .. "opt154 rate154 opt253 rate253 opt254 rate254 opt257 rate257 opt258 rate258", table.concat(fields, " "))
        assert(c.probe.SOURCES[1].type == "via.render.DisplaySettings" and c.probe.SOURCES[1].signature == "get_HDRMode()")
        assert(c.probe.SOURCES[2].signature == "get_HDRDisplayModeEnable()")
        assert(c.probe.SOURCES[3].type == "via.render.DisplaySettings" and c.probe.SOURCES[3].signature == "get_ColorSpace()")
        assert(c.probe.SOURCES[4].type == "via.render.Renderer" and c.probe.SOURCES[4].signature == "get_ColorSpace()")
        assert(c.probe.SOURCES[5].type == "app.OptionUtil" and c.probe.SOURCES[5].signature == "getOptionValue(app.Option.ID)" and c.probe.SOURCES[5].arg == 154)
        assert(c.probe.SOURCES[6].signature == "getOptionValueRate(app.Option.ID)" and c.probe.SOURCES[6].arg == 154)
    end)
end

function T.snapshotPrintsQuestionMarkForFailedReads()
    withProbe(function(c)
        c.values["via.render.DisplaySettings.get_HDRMode()"] = false
        c.values["via.render.DisplaySettings.get_ColorSpace()"] = 1
        c.values["app.OptionUtil.getOptionValue(app.Option.ID)#258"] = 12
        local text = c.probe.formatSnapshot(c.probe.snapshot())
        assert(text:find("hdrMode=false hdrEnable=? colorSpace=1 rendererColorSpace=? opt154=?", 1, true), text)
        assert(text:find("opt258=12 rate258=?", 1, true), text)
    end)
end

function T.snapshotPassesNoArgumentToTheParameterlessGetters()
    withProbe(function(c)
        c.probe.snapshot()
        assert(c.argCounts["via.render.DisplaySettings.get_HDRMode()"] == 0)
        assert(c.argCounts["via.render.Renderer.get_ColorSpace()"] == 0)
        assert(c.argCounts["app.OptionUtil.getOptionValue(app.Option.ID)"] == 1)
        assert(c.argCounts["app.OptionUtil.getOptionValueRate(app.Option.ID)"] == 1)
    end)
end

function T.snapshotReadsNothingWithDeveloperModeOff()
    withProbe(function(c)
        Log.setDeveloperMode(false)
        local snapshot = c.probe.snapshot()
        assert(c.calls == 0, c.calls)
        assert(next(snapshot) == nil)
    end)
end

function T.installLogsOneSnapshotLineOnce()
    withProbe(function(c)
        c.values["via.render.DisplaySettings.get_HDRMode()"] = true
        c.now = 12.5
        c.probe.install()
        c.probe.install()
        local lines = hdrLines()
        assert(#lines == 1, #lines)
        assert(lines[1]:find("hdr snapshot at 12.5 hdrMode=true hdrEnable=?", 1, true), lines[1])
        c.probe.update()
        assert(#hdrLines() == 1, #hdrLines())
    end)
end

function T.updateLogsOneLinePerChangedFieldAndNothingWhenUnchanged()
    withProbe(function(c)
        c.values["via.render.DisplaySettings.get_HDRMode()"] = false
        c.values["via.render.DisplaySettings.get_ColorSpace()"] = 1
        c.probe.install()
        c.probe.update()
        assert(#hdrLines() == 1, #hdrLines())
        c.now = 101.0
        c.values["via.render.DisplaySettings.get_HDRMode()"] = true
        c.values["via.render.DisplaySettings.get_ColorSpace()"] = 3
        c.probe.update()
        local lines = hdrLines()
        assert(#lines == 3, #lines)
        assert(lines[2]:find("hdr change hdrMode false -> true at 101.0", 1, true), lines[2])
        assert(lines[3]:find("hdr change colorSpace 1 -> 3 at 101.0", 1, true), lines[3])
        c.values["via.render.DisplaySettings.get_HDRMode()"] = nil
        c.probe.update()
        assert(#hdrLines() == 4 and hdrLines()[4]:find("hdr change hdrMode true -> ? at 101.0", 1, true), hdrLines()[4])
    end)
end

function T.installWithDeveloperModeOffDefersTheFirstReadingToUpdate()
    withProbe(function(c)
        Log.setDeveloperMode(false)
        c.probe.install()
        c.probe.update()
        assert(c.calls == 0, c.calls)
        assert(#hdrLines() == 0)
        Log.setDeveloperMode(true)
        c.values["via.render.DisplaySettings.get_HDRMode()"] = false
        c.probe.update()
        local lines = hdrLines()
        assert(#lines == #c.probe.SOURCES, #lines)
        assert(lines[1]:find("hdr change hdrMode nil -> false at 100.0", 1, true), lines[1])
    end)
end

function T.updateDrawsTwoCellsPerSwatchWithTheConvertedColour()
    withProbe(function(c)
        local list = stubs.drawList()
        local getList, beginWindow, endWindow = imgui.get_window_draw_list, imgui.begin_window, imgui.end_window
        local events = {}
        imgui.get_window_draw_list = function() return list end
        imgui.begin_window = function(name, open, flags) events[#events + 1] = "begin:" .. name return true end
        imgui.end_window = function() events[#events + 1] = "end" end
        local ok, err = pcall(function()
            c.probe.update()
            assert(table.concat(events, " ") == "begin:My Hunt Report HDR Probe end", table.concat(events, " "))
            assert(#list.calls == #c.probe.SWATCHES * 2, #list.calls)
            assert(list.calls[1][3] == c.probe.original("#ECE4D6"))
            assert(list.calls[2][3] == c.probe.converted("#ECE4D6", 200, "srgb"))
            assert(list.calls[2][1][1] == 128 and list.calls[2][2][1] == 248, list.calls[2][1][1])
        end)
        imgui.get_window_draw_list, imgui.begin_window, imgui.end_window = getList, beginWindow, endWindow
        if not ok then error(err, 0) end
    end)
end

function T.controlsUpdateTheConversionAndLogTheChange()
    withProbe(function(c)
        local slider, checkbox = imgui.slider_int, imgui.checkbox
        local sliderArgs
        imgui.slider_int = function(label, value, min, max)
            sliderArgs = { label, value, min, max }
            return true, 320
        end
        imgui.checkbox = function(label, value) return true, true end
        local ok, err = pcall(function()
            c.probe.update()
            assert(sliderArgs[2] == 200 and sliderArgs[3] == 80 and sliderArgs[4] == 500)
            assert(c.probe.controls().nits == 320 and c.probe.controls().gamma == "2.2")
            local lines = hdrLines()
            assert(lines[#lines]:find("hdr control nits=320 gamma=2.2", 1, true), lines[#lines])
            imgui.checkbox = function(label, value) return true, false end
            imgui.slider_int = function() return false, 320 end
            c.probe.update()
            assert(c.probe.controls().gamma == "srgb")
            assert(hdrLines()[#hdrLines()]:find("hdr control nits=320 gamma=srgb", 1, true))
        end)
        imgui.slider_int, imgui.checkbox = slider, checkbox
        if not ok then error(err, 0) end
    end)
end

function T.updateIsSilentAndDrawsNothingWithDeveloperModeOff()
    withProbe(function(c)
        Log.setDeveloperMode(false)
        local beginWindow = imgui.begin_window
        local begun = 0
        imgui.begin_window = function() begun = begun + 1 return true end
        c.probe.update()
        imgui.begin_window = beginWindow
        assert(begun == 0 and c.calls == 0 and #hdrLines() == 0)
    end)
end

return T
