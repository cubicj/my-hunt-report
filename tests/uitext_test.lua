local UiText = require("MyHuntReport.UiText")

local T = {}

local function withImgui(overrides, callback)
    UiText.resetCache()
    local original = imgui
    imgui = setmetatable(overrides, { __index = original })
    local ok, err = pcall(callback)
    imgui = original
    UiText.resetCache()
    if not ok then error(err, 0) end
end

local function byCharacters(text)
    return { x = utf8.len(text) * 10, y = 18 }
end

function T.coloredPopsTheColorAndRethrowsTextErrors()
    local colors = 0
    withImgui({
        push_style_color = function() colors = colors + 1 end,
        pop_style_color = function(count) colors = colors - count end,
        text = function(value) if value == "bad" then error("text failed") end end,
    }, function()
        UiText.colored("good", 1)
        assert(colors == 0)
        local ok, err = pcall(UiText.colored, "bad", 1)
        assert(not ok and tostring(err):find("text failed", 1, true) and colors == 0, tostring(err))
    end)
end

function T.inFontPopsTheFontAfterATextError()
    local Fonts = require("MyHuntReport.Fonts")
    local mode = Fonts.mode()
    local fonts = {}
    local ok, err = pcall(withImgui, {
        push_font = function(font) fonts[#fonts + 1] = font end,
        pop_font = function() assert(table.remove(fonts)) end,
        text = function() error("text failed") end,
    }, function()
        Fonts.setMode(true)
        local drawn, drawErr = pcall(UiText.inFont, { handle = "probe", size = 18 }, "value")
        assert(not drawn and tostring(drawErr):find("text failed", 1, true))
        assert(#fonts == 0)
    end)
    Fonts.setMode(mode == "bundled")
    if not ok then error(err, 0) end
end

function T.widthReturnsNilWhenMeasurementFails()
    withImgui({ calc_text_size = function() error("no font") end }, function()
        assert(UiText.width("width probe") == nil)
    end)
    withImgui({ calc_text_size = function() return { x = 42, y = 18 } end }, function()
        assert(UiText.width("width probe") == 42)
    end)
end

function T.clipKeepsTextThatFits()
    withImgui({ calc_text_size = byCharacters }, function()
        assert(UiText.clip("가나다", 30) == "가나다")
    end)
end

function T.clipTrimsWholeUtf8CharactersBeforeTheEllipsis()
    withImgui({ calc_text_size = byCharacters }, function()
        assert(UiText.clip("가나다라", 35) == "가나…")
        assert(UiText.clip("abc", 5) == "…")
    end)
end

function T.clipReturnsTheOriginalTextWhenAMeasurementFails()
    local calls = 0
    withImgui({ calc_text_size = function()
        calls = calls + 1
        if calls > 1 then return nil end
        return { x = 100, y = 18 }
    end }, function()
        assert(UiText.clip("가나다", 30) == "가나다")
        assert(calls == 2)
    end)
end

function T.widthIsMeasuredOncePerTextAndFontContext()
    local Fonts = require("MyHuntReport.Fonts")
    local calls = 0
    withImgui({ calc_text_size = function(text) calls = calls + 1 return { x = #text * 10, y = 18 } end }, function()
        assert(UiText.width("abc") == 30 and UiText.width("abc") == 30 and calls == 1, calls)
        local token = Fonts.push({ size = 22 })
        assert(token == "size")
        assert(UiText.width("abc") == 30 and UiText.width("abc") == 30 and calls == 2, calls)
        Fonts.pop(token)
        assert(UiText.width("abc") == 30 and calls == 2, calls)
        UiText.resetCache()
        assert(UiText.width("abc") == 30 and calls == 3, calls)
    end)
end

function T.failedMeasurementsAreNeverCached()
    local calls, fail = 0, true
    withImgui({ calc_text_size = function()
        calls = calls + 1
        if fail then return nil end
        return { x = 40, y = 18 }
    end }, function()
        assert(UiText.width("abc") == nil and UiText.width("abc") == nil and calls == 2, calls)
        assert(UiText.clip("abc", 10) == "abc" and calls == 3, calls)
        fail = false
        assert(UiText.width("abc") == 40 and calls == 4, calls)
        assert(UiText.clip("abc", 50) == "abc" and calls == 5, calls)
        assert(UiText.clip("abc", 50) == "abc" and calls == 5, calls)
    end)
end

function T.clippedTextIsCachedPerWidthAndFontContext()
    local Fonts = require("MyHuntReport.Fonts")
    local calls = 0
    withImgui({ calc_text_size = function(text) calls = calls + 1 return byCharacters(text) end }, function()
        assert(UiText.clip("가나다라", 35) == "가나…")
        local measured = calls
        assert(UiText.clip("가나다라", 35) == "가나…" and calls == measured)
        assert(UiText.clip("가나다라", 25) == "가…" and calls > measured)
        measured = calls
        local token = Fonts.push({ size = 22 })
        assert(UiText.clip("가나다라", 35) == "가나…" and calls > measured)
        Fonts.pop(token)
    end)
end

function T.measurementCacheIsBounded()
    local calls = 0
    withImgui({ calc_text_size = function() calls = calls + 1 return { x = 1, y = 18 } end }, function()
        UiText.width("first")
        for index = 1, 4096 do UiText.width("filler" .. index) end
        local measured = calls
        UiText.width("first")
        assert(calls == measured + 1, calls)
    end)
end

return T
