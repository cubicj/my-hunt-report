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
    assert(Fonts.header(18) == 1 and Fonts.body(18) == 2 and Fonts.meta(18) == 2 and Fonts.small(18) == 2)
    assert(#loads == 2, "cached fonts must not reload")
    Fonts.preload(18)
    assert(#loads == 2)
    assert(Fonts.status().loaded == true)
    assert(Fonts.status().sizes["MyHuntReport/Pretendard-SemiBold.otf:26"] == true)
end

return T
