local Game = require("MyHuntReport.Game")
local Locale = require("MyHuntReport.Locale")

local T = {}

function T.isUsableTextRejectsOnlyUnusableText()
    assert(Game.isUsableText(nil) == false)
    for _, value in ipairs({ false, 123, {}, "", "#Rejected#", "before#Rejected#after", "---", "name---tail" }) do
        assert(Game.isUsableText(value) == false)
    end
    for _, value in ipairs({ "Burst", "연격", " ", "-", "--", "Rejected", "#rejected#" }) do
        assert(Game.isUsableText(value) == true)
    end
end

local function withMessageStub(callback)
    local originalFind = sdk.find_type_definition
    local requested = {}
    sdk.find_type_definition = function(name)
        if name ~= "via.gui.message" then return nil end
        return {
            get_method = function(_, signature)
                return {
                    call = function(_, _, guid, language)
                        requested[#requested + 1] = signature
                        return "text:" .. tostring(guid) .. ":" .. tostring(language)
                    end,
                }
            end,
        }
    end
    Game.resetCaches()
    local ok, err = pcall(callback, requested)
    sdk.find_type_definition = originalFind
    Game.resetCaches()
    if not ok then error(err, 0) end
end

function T.messageTextUsesTheLanguageOverloadWhenForced()
    withMessageStub(function(requested)
        Locale.init({})
        Locale.resolve("ko")
        assert(Game.messageText("g1") == "text:g1:11")
        assert(requested[1] == "get(System.Guid, via.Language)")
        Locale.resolve("en")
        assert(Game.messageText("g1") == "text:g1:1")
    end)
end

function T.messageTextUsesTheGameLanguageOnAuto()
    withMessageStub(function(requested)
        Locale.init({})
        Locale.resolve("auto")
        assert(Game.messageText("g2") == "text:g2:nil")
        assert(requested[#requested] == "get(System.Guid)")
        assert(Game.messageText(nil) == nil)
    end)
end

function T.languageCodePreservesTheRawLanguage()
    local originalCall = Game.callStatic
    local value
    local ok, err = pcall(function()
        Game.callStatic = function(typeName, signature)
            assert(typeName == "app.OptionUtil" and signature == "getTextLanguage()")
            return value
        end
        for _, language in ipairs({ 9, 1, 2, 4, 0 }) do
            value = language
            local code, raw = Game.languageCode()
            assert(code == (language == 9 and "ko" or "en") and raw == language)
        end
        value = "unreadable"
        local code, raw = Game.languageCode()
        assert(code == nil and raw == nil)
        value = nil
        code, raw = Game.languageCode()
        assert(code == nil and raw == nil)
    end)
    Game.callStatic = originalCall
    if not ok then error(err, 0) end
end

function T.enemyIsDeadReadsTheHealthManager()
    local componentOf = Game.componentOf
    local ok, err = pcall(function()
        local dead = false
        Game.componentOf = function(object, typeName)
            if object == nil or typeName ~= "app.EnemyCharacter" then return nil end
            return { get_HealthMgr = function() return { get_IsDead = function() return dead end } end }
        end
        assert(Game.enemyIsDead({}) == false)
        dead = true
        assert(Game.enemyIsDead({}) == true)
        assert(Game.enemyIsDead(nil) == false)
        Game.componentOf = function() return { get_HealthMgr = function() error("boom") end } end
        assert(Game.enemyIsDead({}) == false)
    end)
    Game.componentOf = componentOf
    if not ok then error(err, 0) end
end

local function withStaticStub(answers, callback)
    local originalCall = Game.callStatic
    local calls = {}
    local ok, err = pcall(function()
        Game.callStatic = function(typeName, signature, ...)
            local key = typeName .. "::" .. signature
            calls[#calls + 1] = { key = key, ... }
            local answer = answers[key]
            if type(answer) == "function" then return answer(...) end
            return answer
        end
        callback(calls)
    end)
    Game.callStatic = originalCall
    if not ok then error(err, 0) end
end

function T.viaLanguageForPrefersTheGameConverterAndFallsBackToTheTable()
    withStaticStub({ ["app.LanguageDef::convert(app.LanguageDef.LANGUAGE_APP)"] = 26 }, function()
        assert(Game.viaLanguageFor(14) == 26)
    end)
    withStaticStub({}, function()
        assert(Game.viaLanguageFor(9) == 11 and Game.viaLanguageFor(10) == 12 and Game.viaLanguageFor(11) == 13)
        assert(Game.viaLanguageFor(1) == 1 and Game.viaLanguageFor(13) == 32 and Game.viaLanguageFor(14) == 26)
        assert(Game.viaLanguageFor(99) == nil and Game.viaLanguageFor(nil) == nil)
    end)
end

function T.textLanguageReadyComparesCurrentAndForcedWeaponNames()
    local texts = { current = "大剑", forced = "대검" }
    local answers = {
        ["app.WeaponUtil::getWeaponTypeName(app.WeaponDef.TYPE)"] = function(weaponType) assert(weaponType == 0) return "guid-gs" end,
        ["via.gui.message::get(System.Guid)"] = function(guid) assert(guid == "guid-gs") return texts.current end,
        ["via.gui.message::get(System.Guid, via.Language)"] = function(guid, language) assert(guid == "guid-gs" and language == 11) return texts.forced end,
    }
    withStaticStub(answers, function()
        assert(Game.textLanguageReady(9) == false)
        texts.current = "대검"
        assert(Game.textLanguageReady(9) == true)
        texts.current = ""
        assert(Game.textLanguageReady(9) == true, "unusable current text cannot block the switch")
    end)
    withStaticStub({}, function()
        assert(Game.textLanguageReady(9) == true, "a missing guid cannot block the switch")
        assert(Game.textLanguageReady(99) == true, "an unmapped language adopts immediately")
    end)
end

return T
