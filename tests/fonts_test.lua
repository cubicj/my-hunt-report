local T = {}

function T.fontCenterNudgeMatchesPretendardSizes()
    local Fonts = require("MyHuntReport.Fonts")
    assert(Fonts.centerNudge(18) == 1)
    assert(Fonts.centerNudge(20) == 1)
    assert(Fonts.centerNudge(28) == 2)
end

function T.fontsLoadTwoSizesAndCacheByFileAndSize()
    local loads = {}
    local environment = setmetatable({
        imgui = {
            load_font = function(path, size)
                loads[#loads + 1] = path:gsub("MyHuntReport/Pretendard%-", "") .. ":" .. size
                return #loads
            end,
        },
    }, { __index = _G })
    local Fonts = assert(loadfile("reframework/autorun/MyHuntReport/Fonts.lua", "t", environment))()
    assert(Fonts.size("header", 18) == 26 and Fonts.size("body", 18) == 18)
    assert(Fonts.size("meta", 18) == 18 and Fonts.size("small", 18) == 18)
    assert(Fonts.size("header", 24) == 35 and Fonts.size("meta", 24) == 24 and Fonts.size("small", 24) == 24)
    assert(Fonts.size("header", 14) == 20 and Fonts.size("meta", 14) == 14 and Fonts.size("small", 14) == 14)
    Fonts.preload(18)
    assert(table.concat(loads, ",") == "SemiBold.otf:26,Regular.otf:18", table.concat(loads, ","))
    assert(Fonts.header(18).handle == 1 and Fonts.body(18).handle == 2 and Fonts.meta(18).handle == 2 and Fonts.small(18).handle == 2)
    assert(Fonts.header(18).size == 26 and Fonts.body(18).size == 18 and Fonts.meta(18).size == 18 and Fonts.small(18).size == 18)
    assert(#loads == 2, "cached fonts must not reload")
    Fonts.preload(18)
    assert(#loads == 2)
    assert(Fonts.status().loaded == true)
    assert(Fonts.status().sizes["MyHuntReport/Pretendard-SemiBold.otf:26"] == true)
end

local function loadFontsWith(imguiOverrides, removedKeys)
    local calls = {}
    local fakeImgui = {
        load_font = function(path, size) return 7 end,
        push_font = function(font) calls[#calls + 1] = "push_font:" .. tostring(font) end,
        pop_font = function() calls[#calls + 1] = "pop_font" end,
        push_font_size = function(size) calls[#calls + 1] = "push_font_size:" .. tostring(size) end,
        pop_font_size = function() calls[#calls + 1] = "pop_font_size" end,
    }
    for key, value in pairs(imguiOverrides or {}) do fakeImgui[key] = value end
    for _, key in ipairs(removedKeys or {}) do fakeImgui[key] = nil end
    local environment = setmetatable({ imgui = fakeImgui }, { __index = _G })
    local Fonts = assert(loadfile("reframework/autorun/MyHuntReport/Fonts.lua", "t", environment))()
    return Fonts, calls
end

function T.fontsDefaultToBundledModeAndPushLoadedHandles()
    local Fonts, calls = loadFontsWith()
    assert(Fonts.mode() == "bundled")
    local token = Fonts.push(Fonts.body(18))
    assert(token == "font")
    Fonts.pop(token)
    assert(table.concat(calls, ",") == "push_font:7,pop_font", table.concat(calls, ","))
end

function T.fontsDefaultModePushesTheDescriptorSizeOnly()
    local Fonts, calls = loadFontsWith()
    Fonts.setMode(false)
    assert(Fonts.mode() == "default")
    local token = Fonts.push(Fonts.header(18))
    assert(token == "size")
    Fonts.pop(token)
    assert(table.concat(calls, ",") == "push_font_size:26,pop_font_size", table.concat(calls, ","))
    Fonts.setMode(true)
    assert(Fonts.mode() == "bundled")
end

function T.fontsMissingHandleFallsThroughToSizePush()
    local Fonts, calls = loadFontsWith({ load_font = function() return nil end })
    local token = Fonts.push(Fonts.body(20))
    assert(token == "size")
    Fonts.pop(token)
    assert(table.concat(calls, ",") == "push_font_size:20,pop_font_size", table.concat(calls, ","))
end

function T.fontsWithoutSizeApiPushNothing()
    local Fonts, calls = loadFontsWith({ load_font = function() return nil end }, { "push_font_size", "pop_font_size" })
    local token = Fonts.push(Fonts.body(18))
    assert(token == false)
    Fonts.pop(token)
    assert(#calls == 0)
    assert(Fonts.push(nil) == false)
end

function T.fontsPushFontFailureFallsThroughToSizePush()
    local Fonts, calls = loadFontsWith({ push_font = function() error("boom") end })
    local token = Fonts.push(Fonts.body(18))
    assert(token == "size", "a failed push_font falls through to push_font_size")
    Fonts.pop(token)
    assert(table.concat(calls, ",") == "push_font_size:18,pop_font_size", table.concat(calls, ","))
end

return T
