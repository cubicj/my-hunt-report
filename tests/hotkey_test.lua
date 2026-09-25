local Hotkey = require("MyHuntReport.Hotkey")

local T = {}

local function fresh()
    package.loaded["MyHuntReport.Hotkey"] = nil
    Hotkey = require("MyHuntReport.Hotkey")
    local keys = {}
    return keys, function(code) return keys[code] == true end
end

local function eventIs(event, key, value)
    assert(type(event) == "table", "expected event")
    assert(event[key] == value, "unexpected event value")
    local count = 0
    for _ in pairs(event) do count = count + 1 end
    assert(count == 1, "unexpected event fields")
end

function T.toggleFiresOncePerPress()
    local keys, down = fresh()
    assert(not Hotkey.isCapturing())
    assert(Hotkey.update(down, 118) == nil)
    keys[118] = true
    eventIs(Hotkey.update(down, 118), "toggle", true)
    assert(Hotkey.update(down, 118) == nil)
    keys[118] = false
    assert(Hotkey.update(down, 118) == nil)
    keys[118] = true
    eventIs(Hotkey.update(down, 118), "toggle", true)
end

function T.captureWaitsForReleaseBeforeNewToggle()
    local keys, down = fresh()
    Hotkey.beginCapture()
    assert(Hotkey.isCapturing())
    assert(Hotkey.update(down, 118) == nil)
    keys[65] = true
    eventIs(Hotkey.update(down, 118), "captured", 65)
    assert(not Hotkey.isCapturing())
    for _ = 1, 3 do assert(Hotkey.update(down, 65) == nil) end
    keys[65] = false
    assert(Hotkey.update(down, 65) == nil)
    keys[65] = true
    eventIs(Hotkey.update(down, 65), "toggle", true)
end

function T.captureOfCurrentToggleResetsItsOldEdge()
    local keys, down = fresh()
    keys[118] = true
    eventIs(Hotkey.update(down, 118), "toggle", true)
    Hotkey.beginCapture()
    eventIs(Hotkey.update(down, 118), "captured", 118)
    assert(Hotkey.update(down, 118) == nil)
    keys[118] = false
    assert(Hotkey.update(down, 118) == nil)
    keys[118] = true
    eventIs(Hotkey.update(down, 118), "toggle", true)
end

function T.escapeCancelsBeforeAnyCandidateAndWaitsForRelease()
    local keys, down = fresh()
    Hotkey.beginCapture()
    keys[27], keys[8], keys[118] = true, true, true
    eventIs(Hotkey.update(down, 118), "cancelled", true)
    assert(not Hotkey.isCapturing())
    for _ = 1, 3 do assert(Hotkey.update(down, 118) == nil) end
    keys[27] = false
    assert(Hotkey.update(down, 118) == nil)
    eventIs(Hotkey.update(down, 118), "toggle", true)
end

function T.mouseButtonDoesNotEndCapture()
    local keys, down = fresh()
    Hotkey.beginCapture()
    keys[1] = true
    assert(Hotkey.update(down, 118) == nil)
    assert(Hotkey.isCapturing())
    keys[65] = true
    eventIs(Hotkey.update(down, 118), "captured", 65)
end

function T.cancelButtonEndsCapture()
    local keys, down = fresh()
    Hotkey.beginCapture()
    Hotkey.cancelCapture()
    assert(not Hotkey.isCapturing())
    assert(Hotkey.update(down, 118) == nil)
    keys[118] = true
    eventIs(Hotkey.update(down, 118), "toggle", true)
end

function T.lowestCandidateWins()
    local keys, down = fresh()
    Hotkey.beginCapture()
    keys[222], keys[118], keys[65], keys[8] = true, true, true, true
    eventIs(Hotkey.update(down, 118), "captured", 8)
end

function T.onlySpecifiedCandidatesAreCaptured()
    local candidates = { [8] = true, [9] = true, [13] = true, [45] = true, [46] = true, [144] = true, [145] = true }
    for _, range in ipairs({ {16, 20}, {32, 40}, {48, 57}, {65, 90}, {96, 135}, {186, 192}, {219, 222} }) do
        for code = range[1], range[2] do candidates[code] = true end
    end
    for code = 1, 254 do
        local keys, down = fresh()
        Hotkey.beginCapture()
        keys[code] = true
        local event = Hotkey.update(down, 118)
        if candidates[code] then
            eventIs(event, "captured", code)
            assert(not Hotkey.isCapturing())
        elseif code == 27 then
            eventIs(event, "cancelled", true)
        else
            assert(event == nil, "unexpected capture of " .. code)
            assert(Hotkey.isCapturing())
        end
    end
end

function T.toggleRequiresBooleanTrue()
    fresh()
    assert(Hotkey.update(function() return 1 end, 118) == nil)
    eventIs(Hotkey.update(function() return true end, 118), "toggle", true)
end

function T.namesMatchTheDisplayContract()
    fresh()
    local names = {
        [8] = "Backspace", [9] = "Tab", [13] = "Enter", [16] = "Shift",
        [17] = "Ctrl", [18] = "Alt", [19] = "Pause", [20] = "CapsLock",
        [27] = "Esc", [32] = "Space", [33] = "PageUp", [34] = "PageDown",
        [35] = "End", [36] = "Home", [37] = "Left", [38] = "Up",
        [39] = "Right", [40] = "Down", [45] = "Insert", [46] = "Delete",
        [106] = "Num*", [107] = "Num+", [108] = "VK 108", [109] = "Num-",
        [110] = "Num.", [111] = "Num/", [118] = "F7", [144] = "NumLock",
        [145] = "ScrollLock", [186] = ";", [187] = "=", [188] = ",",
        [189] = "-", [190] = ".", [191] = "/", [192] = "`",
        [219] = "[", [220] = "\\", [221] = "]", [222] = "'", [250] = "VK 250",
    }
    for code, name in pairs(names) do assert(Hotkey.name(code) == name, "wrong name for " .. code) end
    for code = 48, 57 do assert(Hotkey.name(code) == string.char(code)) end
    for code = 65, 90 do assert(Hotkey.name(code) == string.char(code)) end
    for code = 96, 105 do assert(Hotkey.name(code) == "Num" .. (code - 96)) end
    for code = 112, 135 do assert(Hotkey.name(code) == "F" .. (code - 111)) end
end

return T
