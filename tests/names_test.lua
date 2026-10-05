local Game = require("MyHuntReport.Game")
local Locale = require("MyHuntReport.Locale")
local Log = require("MyHuntReport.Log")
local MotionNames = require("MyHuntReport.MotionNames")
local SkillState = require("MyHuntReport.SkillState")
local stubs = require("stubs")

local T = {}

local function withNames(callback)
    local Names = require("MyHuntReport.Names")
    local call, text, motion, skill = Game.callStatic, Game.messageText, MotionNames.nameFor, SkillState.skillName
    local developerMode = Log.isDeveloperMode()
    Locale.init({})
    Locale.resolve("en")
    Names.reset()
    Log.resetCounts()
    local calls = {}
    Game.callStatic = function(typeName, signature, id)
        calls[#calls + 1] = { typeName, signature, id }
        return typeName .. ":" .. tostring(id)
    end
    Game.messageText = function(guid) return Locale.textKey() .. ":" .. tostring(guid) end
    local ok, err = pcall(callback, Names, calls)
    Game.callStatic, Game.messageText, MotionNames.nameFor, SkillState.skillName = call, text, motion, skill
    Log.setDeveloperMode(developerMode)
    Names.reset()
    if not ok then error(err, 0) end
end

function T.resolvesEveryLabelKind()
    withNames(function(Names, calls)
        MotionNames.nameFor = function(className, guideId)
            assert(className == "cAttackHigh" and guideId == 9328)
            return "Overhead Slash"
        end
        SkillState.skillName = function(id)
            assert(id == "burst:stage2")
            return "Burst Stage 2"
        end
        assert(Names.resolve({ kind = "monster", emId = 26 }) == "via:1:app.EnemyDef:26")
        assert(calls[1][2] == "EnemyName(app.EnemyDef.ID)")
        assert(Names.resolve({ kind = "motion", className = "cAttackHigh", guideId = 9328 }) == "Overhead Slash")
        assert(Names.resolve({ kind = "kinsect" }) == "Kinsect")
        assert(Names.resolve({ kind = "slinger" }) == "Slinger")
        assert(Names.resolve({ kind = "proc", proc = "blast" }) == Locale.text("proc_blast"))
        assert(Names.resolve({ kind = "skill", id = "burst:stage2" }) == "Burst Stage 2")
        assert(Names.resolve({ kind = "weapon", type = 13 }) == "via:1:app.WeaponUtil:13")
        assert(calls[2][2] == "getWeaponTypeName(app.WeaponDef.TYPE)")
        Locale.resolve("ko")
        assert(Names.resolve({ kind = "kinsect" }) == "조충 공격")
        assert(Names.resolve({ kind = "slinger" }) == "슬링어")
        assert(Names.resolve({ kind = "proc", proc = "blast" }) == "폭파")
    end)
end

function T.itemUsesGuidBeforeNameString()
    withNames(function(Names, calls)
        assert(Names.item(1234) == "via:1:app.ItemDef:1234")
        assert(#calls == 1 and calls[1][1] == "app.ItemDef" and calls[1][2] == "Name(app.ItemDef.ID)")
    end)
end

function T.itemFallsBackToNameStringThenIdentifier()
    withNames(function(Names, calls)
        Game.messageText = function() return nil end
        Game.callStatic = function(typeName, signature, id)
            calls[#calls + 1] = signature
            if signature == "NameString(app.ItemDef.ID)" then return id == 1234 and "Normal Ammo" or "" end
            return "guid"
        end
        assert(Names.item(1234) == "Normal Ammo")
        assert(calls[1] == "Name(app.ItemDef.ID)" and calls[2] == "NameString(app.ItemDef.ID)")
        assert(Names.item(5678) == "#5678")
    end)
end

function T.motionAppendsResolvedItem()
    withNames(function(Names)
        MotionNames.nameFor = function(className, guideId)
            assert(className == "cShootRapidLight" and guideId == -1)
            return "Rapid Fire"
        end
        assert(Names.resolve({ kind = "motion", className = "cShootRapidLight", guideId = -1, itemId = 1234 })
            == "Rapid Fire via:1:app.ItemDef:1234")
    end)
end

function T.ammoNameOmitsOrdinaryAction()
    withNames(function(Names)
        Game.messageText = function() return "Normal Ammo Lv1" end
        MotionNames.nameFor = function() error("ordinary ammo must not resolve an action name") end
        for _, className in ipairs({ "cShootRapidLight", "cShootFullAutoLight" }) do
            assert(Names.resolve({ kind = "motion", className = className, guideId = 4001,
                itemId = 1234, itemRole = "ammo" }) == "Normal Ammo Lv1")
        end
    end)
end

function T.ammoVariableNameAppendsTechnique()
    withNames(function(Names)
        Game.messageText = function() return "Normal Ammo Lv1" end
        MotionNames.nameFor = function(className, guideId)
            assert(className == "cShootNormalVariableLight" and guideId == 4002)
            return "Chaser Shot"
        end
        assert(Names.resolve({ kind = "motion", className = "cShootNormalVariableLight", guideId = 4002,
            itemId = 1234, itemRole = "ammo" }) == "Normal Ammo Lv1 - Chaser Shot")
    end)
end

function T.ammoStepDodgeNameAppendsTechnique()
    withNames(function(Names)
        Game.messageText = function() return "Normal Ammo Lv1" end
        MotionNames.nameFor = function(className, guideId)
            assert(className == "cShootStepDodgeLight" and guideId == 4003)
            return "Step Shot"
        end
        assert(Names.resolve({ kind = "motion", className = "cShootStepDodgeLight", guideId = 4003,
            itemId = 1234, itemRole = "ammo" }) == "Normal Ammo Lv1 - Step Shot")
    end)
end

function T.ammoRapidNameFollowsLocale()
    withNames(function(Names)
        Game.messageText = function()
            return Locale.current() == "ko" and "통상탄 Lv1" or "Normal Ammo Lv1"
        end
        MotionNames.nameFor = function() error("rapid ammo must not resolve an action name") end
        local label = { kind = "motion", className = "cShootRapidLight", guideId = 4001,
            itemId = 1234, itemRole = "ammo", rapid = true }
        assert(Names.resolve(label) == "Normal Ammo Lv1 (Rapid Fire)")
        Locale.resolve("ko")
        assert(Names.resolve(label) == "통상탄 Lv1 (속사)")
    end)
end

function T.ammoTechniqueTakesPrecedenceOverRapidSuffix()
    withNames(function(Names)
        Game.messageText = function() return "Normal Ammo Lv1" end
        MotionNames.nameFor = function() return "Technique" end
        for _, className in ipairs({ "cShootNormalVariableLight", "cShootStepDodgeLight" }) do
            assert(Names.resolve({ kind = "motion", className = className, guideId = 4002,
                itemId = 1234, itemRole = "ammo", rapid = true }) == "Normal Ammo Lv1 - Technique")
        end
    end)
end

function T.coatingNameBracketsResolvedItem()
    withNames(function(Names)
        Game.messageText = function() return "Power Coating" end
        MotionNames.nameFor = function(className, guideId)
            assert(className == "cShotNormal" and guideId == 4001)
            return "Shot"
        end
        assert(Names.resolve({ kind = "motion", className = "cShotNormal", guideId = 4001,
            itemId = 5678, itemRole = "coating" }) == "Shot [Power Coating]")
    end)
end

function T.cachesUseTextKeyAndReset()
    withNames(function(Names, calls)
        local monster = { kind = "monster", emId = 26 }
        local weapon = { kind = "weapon", type = 13 }
        for _, setting in ipairs({ "en", "ko", "auto" }) do
            Locale.resolve(setting)
            for _ = 1, 2 do
                assert(Names.resolve(monster) == Locale.textKey() .. ":app.EnemyDef:26")
                assert(Names.item(1234) == Locale.textKey() .. ":app.ItemDef:1234")
                assert(Names.resolve(weapon) == Locale.textKey() .. ":app.WeaponUtil:13")
            end
        end
        assert(#calls == 9)
        Names.reset()
        Names.resolve(monster)
        Names.item(1234)
        Names.resolve(weapon)
        assert(#calls == 12)
    end)
end

function T.monsterFallbackKeepsErrorKey()
    withNames(function(Names)
        Game.messageText = function() return nil end
        assert(Names.resolve({ kind = "monster", emId = 26 }) == "#26")
        assert(Names.resolve({ kind = "monster", emId = 26 }) == "#26")
        assert(Log.count("hit:name:26") == 1)
    end)
end

function T.monsterReadFailureIsContained()
    withNames(function(Names)
        Game.callStatic = function() error("unavailable") end
        assert(Names.resolve({ kind = "monster", emId = 26 }) == "#26")
        assert(Log.count("hit:name:26") == 1)
    end)
end

function T.monsterVariantsUseDistinctNameString()
    withNames(function(Names)
        Locale.resolve("auto")
        Game.messageText = function() return "Ajarakan" end
        for _, variant in ipairs({ { 0, 1 }, { 0, 2 }, { 3, 0 }, { 3, 2 } }) do
            local calls = 0
            Game.callStatic = function(typeName, signature, emId, roleId, legendaryId)
                assert(typeName == "app.EnemyDef" and emId == 26)
                calls = calls + 1
                if calls == 1 then
                    assert(signature == "EnemyName(app.EnemyDef.ID)")
                    return "guid"
                end
                assert(signature == "NameString(app.EnemyDef.ID, app.EnemyDef.ROLE_ID, app.EnemyDef.LEGENDARY_ID)")
                assert(roleId == variant[1] and legendaryId == variant[2])
                return "Variant Ajarakan"
            end
            assert(Names.resolve({ kind = "monster", emId = 26, roleId = variant[1], legendaryId = variant[2] })
                == "Variant Ajarakan")
            assert(calls == 2)
        end
    end)
end

function T.monsterVariantsPrefixBaseOrFailedOrUnusableNameString()
    withNames(function(Names)
        for _, language in ipairs({ "en", "ko", "auto" }) do
            Locale.resolve(language)
            local base = language == "ko" and "아자라칸" or "Ajarakan"
            local prefixes = language == "ko" and { "역전 ", "역전왕 ", "광룡화 " }
                or { "Tempered ", "Arch-tempered ", "Frenzied " }
            local variantSignature = language == "auto"
                and "NameString(app.EnemyDef.ID, app.EnemyDef.ROLE_ID, app.EnemyDef.LEGENDARY_ID)"
                or "Name(app.EnemyDef.ID, app.EnemyDef.ROLE_ID, app.EnemyDef.LEGENDARY_ID)"
            for _, result in ipairs({ "base", "throw", "nil", false, 123, "", "#Rejected#guid", "name---" }) do
                Names.reset()
                local function variantResult()
                    if result == "throw" then error("name unavailable") end
                    if result == "nil" then return nil end
                    if result == "base" then return base end
                    return result
                end
                Game.callStatic = function(_, signature)
                    if signature == "EnemyName(app.EnemyDef.ID)" then return "guid" end
                    assert(signature == variantSignature, signature)
                    if language == "auto" then return variantResult() end
                    return "variantGuid"
                end
                Game.messageText = function(guid)
                    if guid == "variantGuid" then return variantResult() end
                    return base
                end
                for _, variant in ipairs({ { 0, 1, 1 }, { 0, 2, 2 }, { 3, 0, 3 }, { 3, 1, 1 }, { 3, 2, 2 } }) do
                    assert(Names.resolve({ kind = "monster", emId = 26, roleId = variant[1], legendaryId = variant[2] })
                        == prefixes[variant[3]] .. base)
                end
            end
        end
    end)
end

function T.monsterPlainAndOtherRolesKeepBaseName()
    withNames(function(Names, calls)
        for _, roleId in ipairs({ 0, 1, 2, 4, 5 }) do
            assert(Names.resolve({ kind = "monster", emId = 26, roleId = roleId, legendaryId = 0 })
                == "via:1:app.EnemyDef:26")
        end
        assert(Names.resolve({ kind = "monster", emId = 26 }) == "via:1:app.EnemyDef:26")
        assert(#calls == 5)
        for _, call in ipairs(calls) do assert(call[2] == "EnemyName(app.EnemyDef.ID)") end
    end)
end

function T.monsterCacheSeparatesLocaleEnemyRoleAndLegendary()
    withNames(function(Names)
        local calls = 0
        Game.callStatic = function(_, signature, emId, roleId, legendaryId)
            calls = calls + 1
            if signature == "EnemyName(app.EnemyDef.ID)" then return emId end
            return Locale.textKey() .. ":" .. emId .. ":" .. roleId .. ":" .. legendaryId
        end
        Game.messageText = function(value)
            if type(value) == "string" then return value end
            return "Base " .. value
        end
        for _, language in ipairs({ "en", "ko", "auto" }) do
            Locale.resolve(language)
            for _, emId in ipairs({ 26, 27 }) do
                for _, variant in ipairs({ { 0, 1 }, { 0, 2 }, { 3, 0 }, { 3, 1 }, { 3, 2 } }) do
                    local label = { kind = "monster", emId = emId, roleId = variant[1], legendaryId = variant[2] }
                    for _ = 1, 2 do
                        assert(Names.resolve(label) == Locale.textKey() .. ":" .. emId .. ":" .. variant[1] .. ":" .. variant[2])
                    end
                end
            end
        end
        assert(calls == 60)
    end)
end

function T.monsterDebugReportsEachResolutionPathOncePerCachedKey()
    withNames(function(Names)
        Log.setDeveloperMode(true)
        Game.messageText = function(guid) return guid == "kingGuid" and "Arch-tempered Ajarakan" or "Ajarakan" end
        Game.callStatic = function(_, signature, _, _, legendaryId)
            if signature == "EnemyName(app.EnemyDef.ID)" then return "guid" end
            if signature == "Name(app.EnemyDef.ID, app.EnemyDef.ROLE_ID, app.EnemyDef.LEGENDARY_ID)" then
                return legendaryId == 2 and "kingGuid" or "guid"
            end
            return legendaryId == 2 and "Arch-tempered Ajarakan" or "Ajarakan"
        end
        for _, variant in ipairs({ { 0, "EnemyName" }, { 1, "prefix" }, { 2, "Name" } }) do
            local label = { kind = "monster", emId = 26, legendaryId = variant[1] }
            for _ = 1, 2 do Names.resolve(label) end
            local key = "via:1:26:0:" .. variant[1]
            assert(stubs.logLines[#stubs.logLines] == "[MyHuntReport] monster name " .. key .. " via " .. variant[2])
            assert(Log.count("monster:name:" .. key) == 1)
        end
        assert(#stubs.logLines == 3)
        Locale.resolve("auto")
        Names.resolve({ kind = "monster", emId = 26, legendaryId = 2 })
        assert(stubs.logLines[#stubs.logLines] == "[MyHuntReport] monster name " .. Locale.textKey() .. ":26:0:2 via NameString")
        Locale.resolve("en")
        local logged = #stubs.logLines
        Log.setDeveloperMode(false)
        Names.resolve({ kind = "monster", emId = 27, legendaryId = 2 })
        assert(#stubs.logLines == logged)
    end)
end

function T.monsterVariantsFollowTheForcedLanguageThroughTheGuidName()
    withNames(function(Names)
        local signatures = {}
        Game.callStatic = function(_, signature, emId, roleId, legendaryId)
            signatures[#signatures + 1] = signature
            if signature == "EnemyName(app.EnemyDef.ID)" then return "guid" end
            assert(emId == 26 and roleId == 0 and legendaryId == 1)
            return "variantGuid"
        end
        Game.messageText = function(guid)
            return guid == "variantGuid" and "Tempered Ajarakan (guid)" or "Ajarakan"
        end
        assert(Names.resolve({ kind = "monster", emId = 26, roleId = 0, legendaryId = 1 }) == "Tempered Ajarakan (guid)")
        assert(#signatures == 2)
        assert(signatures[2] == "Name(app.EnemyDef.ID, app.EnemyDef.ROLE_ID, app.EnemyDef.LEGENDARY_ID)")
    end)
end

function T.echoWaveResolvesGuidAndCachesByLocaleAndFrequency()
    withNames(function(Names)
        local calls = 0
        Game.callStatic = function(typeName, signature, skill, highFreq)
            assert(typeName == "app.Wp05Def")
            assert(signature == "MusicSkillName(app.Wp05Def.WP05_MUSIC_SKILL_TYPE, app.Wp05Def.WP05_MUSIC_SKILL_HIGH_FREQ_TYPE)")
            assert(skill == 48)
            calls = calls + 1
            return { highFreq = highFreq }
        end
        Game.messageText = function(guid) return Locale.textKey() .. ":wave:" .. guid.highFreq end
        for _, language in ipairs({ "en", "ko", "auto" }) do
            Locale.resolve(language)
            for highFreq = 1, 2 do
                local label = { kind = "echoWave", highFreq = highFreq, weaponType = 5 }
                for _ = 1, 2 do
                    assert(Names.resolve(label) == Locale.textKey() .. ":wave:" .. highFreq)
                end
            end
        end
        assert(calls == 6)
        Names.reset()
        Names.resolve({ kind = "echoWave", highFreq = 1 })
        assert(calls == 7)
    end)
end

function T.echoWaveRejectsInvalidTextAndUsesLocalizedFallback()
    withNames(function(Names)
        for _, language in ipairs({ "en", "ko" }) do
            Locale.resolve(language)
            for _, value in ipairs({ false, 123, "", "#Rejected#guid", "name---" }) do
                Names.reset()
                Game.messageText = function() return value end
                assert(Names.resolve({ kind = "echoWave", highFreq = 1 }) == (language == "ko" and "향주파" or "Echo Wave"))
            end
        end
    end)
end

function T.echoWaveContainsLookupFailure()
    withNames(function(Names)
        Game.callStatic = function() return nil end
        Game.messageText = function(guid) assert(guid == nil); return nil end
        assert(Names.resolve({ kind = "echoWave", highFreq = 1 }) == "Echo Wave")
        Names.reset()
        Game.callStatic = function() error("unavailable") end
        assert(Names.resolve({ kind = "echoWave", highFreq = 1 }) == "Echo Wave")
    end)
end

function T.weaponMissingTextReturnsNil()
    withNames(function(Names, calls)
        Game.messageText = function() return nil end
        assert(Names.resolve({ kind = "weapon", type = 13 }) == nil)
        assert(Names.resolve({ kind = "weapon", type = 13 }) == nil)
        assert(#calls == 1)
        assert(Names.resolve({ kind = "weapon" }) == nil)
        assert(#calls == 1)
    end)
end

function T.weaponStateRowsArePrefixedWithTheWeaponName()
    withNames(function(Names)
        SkillState.skillName = function(id) return "state:" .. tostring(id) end
        assert(Names.resolve({ kind = "skill", id = 4092 }) == "via:1:app.WeaponUtil:9: state:4092", Names.resolve({ kind = "skill", id = 4092 }))
        assert(Names.resolve({ kind = "skill", id = 63 }) == "state:63")
        Game.messageText = function() return nil end
        Names.reset()
        assert(Names.resolve({ kind = "skill", id = 4021 }) == "state:4021", Names.resolve({ kind = "skill", id = 4021 }))
    end)
end

function T.healLabelsResolveThroughLocale()
    withNames(function(Names)
        assert(Names.resolve({ kind = "heal", heal = "hastenRecovery" }) == "Hasten Recovery")
        assert(Names.resolve({ kind = "heal", heal = "superRecovery" }) == "Super Recovery")
        Locale.resolve("ko")
        assert(Names.resolve({ kind = "heal", heal = "hastenRecovery" }) == "가속 재생")
        assert(Names.resolve({ kind = "heal", heal = "superRecovery" }) == "슈퍼 회복력")
    end)
end

return T
