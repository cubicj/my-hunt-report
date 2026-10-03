local Game = require("MyHuntReport.Game")
local Hdr = require("MyHuntReport.Hdr")

local T = {}

local function withReadings(readings, callback)
    local callStatic = Game.callStatic
    local calls = {}
    Game.callStatic = function(typeName, signature, ...)
        assert(typeName == "via.render.DisplaySettings", typeName)
        assert(select("#", ...) == 0, signature)
        calls[#calls + 1] = signature
        return readings[signature]
    end
    local ok, err = pcall(callback, calls)
    Game.callStatic = callStatic
    if not ok then error(err, 0) end
end

local function channels(color)
    return color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF, (color >> 24) & 0xFF
end

function T.convertPlacesWhiteAtThePqCodeOfTheReferenceWhite()
    for nits, code in pairs({ [100] = 130, [1000] = 192, [10000] = 255 }) do
        local r, g, b, a = channels(Hdr.convert("#FFFFFF", 1, nits))
        assert(r == code and g == code and b == code and a == 255, nits .. ": " .. r .. " " .. g .. " " .. b)
    end
end

function T.convertKeepsBlackAtZero()
    assert(Hdr.convert("#000000", 1, 455) == 0xFF000000)
    assert(Hdr.convert("#000000", 0, 455) == 0)
end

function T.convertPullsSaturatedRedInsideTheWiderGamut()
    local r, g, b = channels(Hdr.convert("#FF0000", 1, 200))
    assert(r > g and g > b and b > 0, r .. " " .. g .. " " .. b)
end

function T.convertDimsTheThemeTextColourBelowItsSrgbBytes()
    local r, g, b, a = channels(Hdr.convert("#ECE4D6", 1, 200))
    assert(r == 142 and g == 141 and b == 138 and a == 255, r .. " " .. g .. " " .. b)
    assert(Hdr.convert("ECE4D6", 1, 200) == Hdr.convert("#ECE4D6", 1, 200))
end

function T.convertPassesAlphaThroughAndDefaultsToOpaque()
    assert(Hdr.convert("#FFFFFF", 0.04, 200) >> 24 == 0x0A)
    assert(Hdr.convert("#1B1815", 0.95, 200) >> 24 == 0xF2)
    assert(Hdr.convert("#1B1815", nil, 200) >> 24 == 0xFF)
end

function T.convertRejectsAnInvalidColour()
    assert(not pcall(Hdr.convert, "#12345", 1, 200))
    assert(not pcall(Hdr.convert, "#GG0000", 1, 200))
end

function T.activeIsTrueOnlyForATrueReading()
    for _, case in ipairs({ { true, true }, { false, false }, { nil, false }, { 1, false } }) do
        withReadings({ ["get_HDRMode()"] = case[1] }, function()
            assert(Hdr.active() == case[2], tostring(case[1]))
        end)
    end
end

function T.referenceWhiteReturnsTheEngineValueOrTheFallback()
    assert(Hdr.FALLBACK_NITS == 200)
    withReadings({ ["get_WhitePaperNitsForOverlay()"] = 455.0 }, function()
        assert(Hdr.referenceWhite() == 455.0)
    end)
    for _, bad in ipairs({ 0, -1.0, 0 / 0, "455", true }) do
        withReadings({ ["get_WhitePaperNitsForOverlay()"] = bad }, function()
            assert(Hdr.referenceWhite() == 200, tostring(bad))
        end)
    end
    withReadings({}, function()
        assert(Hdr.referenceWhite() == 200)
    end)
end

function T.targetNitsFollowsTheSettingAndTheHdrState()
    local on = { ["get_HDRMode()"] = true, ["get_WhitePaperNitsForOverlay()"] = 455.0 }
    local off = { ["get_HDRMode()"] = false, ["get_WhitePaperNitsForOverlay()"] = 455.0 }
    withReadings(on, function()
        assert(Hdr.targetNits("auto") == 455.0)
        assert(Hdr.targetNits("on") == 455.0)
        assert(Hdr.targetNits("off") == nil)
        assert(Hdr.targetNits(nil) == 455.0)
    end)
    withReadings(off, function()
        assert(Hdr.targetNits("auto") == nil)
        assert(Hdr.targetNits("on") == 455.0)
        assert(Hdr.targetNits("off") == nil)
    end)
end

function T.targetNitsReadsOnlyWhatItNeeds()
    local readings = { ["get_HDRMode()"] = false, ["get_WhitePaperNitsForOverlay()"] = 455.0 }
    withReadings(readings, function(calls)
        Hdr.targetNits("off")
        assert(#calls == 0, #calls)
        Hdr.targetNits("auto")
        assert(#calls == 1 and calls[1] == "get_HDRMode()", table.concat(calls, ","))
    end)
    withReadings(readings, function(calls)
        Hdr.targetNits("on")
        assert(#calls == 1 and calls[1] == "get_WhitePaperNitsForOverlay()", table.concat(calls, ","))
    end)
end

return T
