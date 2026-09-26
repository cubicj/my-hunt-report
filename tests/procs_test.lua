local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")

local T = {}

local BRACKETS = {
    blast = "app.cEnemyBadConditionBlast.onActivate",
    poison = "app.cEnemyBadConditionPoison.onUpdateActive",
    flayer = "app.cEnemyBadConditionSkillStabbing.onActivate",
    elementConvert = "app.cEnemyBadConditionSkillRyuki.onActivate",
}
local SET_PARAM = "app.cEnemyStockDamage.cBadConditionDamageInfo.setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)"
local EXTERNAL = "app.cEnemyStockDamage.stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)"
local GETTERS = {
    stabbing = "app.cHunterSkill.getSkillStabbingAddDamage(app.cEnemyContextHolder)",
    ryuki = "app.cHunterSkill.getSkillRyukiAddDamage(app.cEnemyContextHolder, System.Single, System.Single)",
}

local function withProcs(callback)
    local hook, addProc, uptime = Game.hook, Session.addProc, Game.uptime
    local callStatic, isMasterGameObject, masterHunter = Game.callStatic, Game.isMasterGameObject, Game.masterHunter
    local toManaged, toFloat, toValue = sdk.to_managed_object, sdk.to_float, sdk.to_valuetype
    local developerMode = Log.isDeveloperMode()
    local hooks, recorded = {}, {}
    local c_callStaticCalls = {}
    local master = { Category = 0, UniqueIndex = 7 }
    local other = { Category = 0, UniqueIndex = 8 }
    local masterObject = { get_Name = function() return "MasterPlayer" end }
    local otherObject = { get_Name = function() return "OtherPlayer" end }
    local masterSkill = { get_address = function() return 123 end }
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        Log.resetCounts()
        Game.hook = function(typeName, signature, pre, post)
            hooks[typeName .. "." .. signature] = { pre = pre, post = post }
        end
        Game.uptime = function() return 12.5 end
        Game.callStatic = function(typeName, signature, key)
            assert(typeName == "app.TargetAccessKeyUtil")
            assert(signature == "getHunterCharacter(app.TARGET_ACCESS_KEY)")
            c_callStaticCalls[#c_callStaticCalls + 1] = key
            if key == master then return { get_GameObject = function() return masterObject end } end
            if key == other then return { get_GameObject = function() return otherObject end } end
        end
        Game.isMasterGameObject = function(object) return object == masterObject end
        Game.masterHunter = function() return { get_HunterSkill = function() return masterSkill end } end
        Session.addProc = function(proc) recorded[#recorded + 1] = proc end
        sdk.to_managed_object = function(value) return value end
        sdk.to_float = function(value) return value end
        sdk.to_valuetype = function(value, typeName)
            assert(typeName == "app.TARGET_ACCESS_KEY" or typeName == "System.Nullable`1<app.TARGET_ACCESS_KEY>")
            return value
        end
        local procs = assert(loadfile("reframework/autorun/MyHuntReport/Procs.lua"))()
        procs.install()
        local context = { procs = procs, hooks = hooks, recorded = recorded, master = master, other = other, callStaticCalls = c_callStaticCalls }
        function context.enter(kind, key)
            hooks[BRACKETS[kind]].pre({ [2] = { _Invoker = key } })
        end
        function context.leave(kind) hooks[BRACKETS[kind]].post() end
        function context.setParam(value, key) hooks[SET_PARAM].pre({ [3] = value, [4] = key }) end
        function context.external(value, key) hooks[EXTERNAL].pre({ [3] = value, [5] = key }) end
        callback(context)
    end)
    Game.hook, Session.addProc, Game.uptime = hook, addProc, uptime
    Game.callStatic, Game.isMasterGameObject, Game.masterHunter = callStatic, isMasterGameObject, masterHunter
    sdk.to_managed_object, sdk.to_float, sdk.to_valuetype = toManaged, toFloat, toValue
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    if not ok then error(err, 0) end
end

function T.blastProcPassesKindWithoutLocalizedName()
    withProcs(function(c)
        c.enter("blast", c.other)
        c.setParam(100, c.master)
        c.leave("blast")
        assert(#c.recorded == 1)
        local recorded = c.recorded[1]
        assert(recorded.kind == "blast" and recorded.damage == 100 and recorded.name == nil)
        assert(recorded.time == 12.5)
    end)
end

function T.setParamOutsideBracketIsIgnored()
    withProcs(function(c)
        c.setParam(100, c.master)
        assert(#c.recorded == 0)
    end)
end

function T.setParamInsideFlayerIsIgnored()
    withProcs(function(c)
        c.enter("flayer", c.master)
        c.setParam(100, c.master)
        c.leave("flayer")
        assert(#c.recorded == 0)
    end)
end

function T.flayerUsesInvokerWithoutNullableAttacker()
    withProcs(function(c)
        c.enter("flayer", c.master)
        c.external(160.25, { _HasValue = false })
        c.leave("flayer")
        assert(#c.recorded == 1)
        assert(c.recorded[1].kind == "flayer" and c.recorded[1].damage == 160.25 and c.recorded[1].time == 12.5)
    end)
end

function T.externalDamageRejectsOtherInvokerDespiteMasterNullableKey()
    withProcs(function(c)
        for _, kind in ipairs({ "flayer", "poison", "elementConvert" }) do
            c.enter(kind, c.other)
            c.external(160, { _HasValue = true, _Value = c.master })
            c.leave(kind)
        end
        assert(#c.recorded == 0)
    end)
end

function T.externalDamageOutsideBracketIsIgnored()
    withProcs(function(c)
        c.external(30, { _HasValue = true, _Value = c.master })
        assert(#c.recorded == 0)
    end)
end

function T.poisonRecordsOneProcPerTickBracket()
    withProcs(function(c)
        for i = 1, 2 do
            c.enter("poison", c.master)
            c.external(15, { _HasValue = true, _Value = c.other })
            c.external(15)
            c.leave("poison")
            assert(#c.recorded == i)
            assert(c.recorded[i].kind == "poison" and c.recorded[i].damage == 15)
        end
    end)
end

function T.elementConvertDeduplicatesBothDamagePathsInEitherOrder()
    withProcs(function(c)
        c.enter("elementConvert", c.master)
        c.setParam(100, c.master)
        c.external(200)
        c.leave("elementConvert")
        assert(#c.recorded == 1 and c.recorded[1].kind == "elementConvert" and c.recorded[1].damage == 100)
        c.enter("elementConvert", c.master)
        c.external(200)
        c.setParam(100, c.master)
        c.leave("elementConvert")
        assert(#c.recorded == 2 and c.recorded[2].kind == "elementConvert" and c.recorded[2].damage == 200)
    end)
end

function T.failedInvokerReadUnwindsWithoutAttribution()
    withProcs(function(c)
        c.enter("poison", c.master)
        c.hooks[BRACKETS.flayer].pre({ [2] = setmetatable({}, { __index = function() error("unavailable") end }) })
        assert(c.procs.activeKind() == "flayer")
        c.external(160)
        c.leave("flayer")
        assert(c.procs.activeKind() == "poison" and #c.recorded == 0)
        c.external(15)
        c.leave("poison")
        assert(c.procs.activeKind() == nil and #c.recorded == 1)
        assert(c.recorded[1].kind == "poison")
    end)
end

function T.resetClearsNestedBrackets()
    withProcs(function(c)
        c.enter("blast", c.master)
        c.enter("flayer", c.master)
        c.procs.reset()
        assert(c.procs.activeKind() == nil)
        c.setParam(100, c.master)
        c.external(160)
        c.leave("flayer")
        c.leave("blast")
        assert(c.procs.activeKind() == nil and #c.recorded == 0)
    end)
end

function T.nestedBracketsKeepKindAndRecordedStateSeparate()
    withProcs(function(c)
        c.enter("blast", c.master)
        c.enter("flayer", c.master)
        c.setParam(100, c.master)
        c.external(160)
        c.leave("flayer")
        assert(c.procs.activeKind() == "blast")
        c.setParam(100, c.master)
        c.setParam(100, c.master)
        c.external(160)
        c.leave("blast")
        assert(c.procs.activeKind() == nil and #c.recorded == 2)
        assert(c.recorded[1].kind == "flayer" and c.recorded[2].kind == "blast")
    end)
end

function T.blastSetParamRequiresMasterCallKey()
    withProcs(function(c)
        c.enter("blast", c.master)
        c.setParam(100, c.other)
        c.setParam(100, nil)
        c.leave("blast")
        assert(#c.recorded == 0)
    end)
end

local function checkGetterAttribution(kind, path)
    withProcs(function(c)
        local getter = kind == "flayer" and GETTERS.stabbing or GETTERS.ryuki
        local function damage(key)
            if path == "setParam" then c.setParam(160, key) else c.external(160, { _HasValue = false }) end
        end
        c.enter(kind, c.other)
        c.hooks[getter].pre({ [2] = { get_address = function() return 123 end } })
        damage(c.other)
        c.leave(kind)
        assert(#c.recorded == 1 and c.recorded[1].kind == kind and c.recorded[1].damage == 160)
        c.enter(kind, c.master)
        c.hooks[getter].pre({ [2] = { get_address = function() return 456 end } })
        damage(c.master)
        c.leave(kind)
        assert(#c.recorded == 1)
        c.enter(kind, c.master)
        damage(c.other)
        c.leave(kind)
        assert(#c.recorded == 2 and c.recorded[2].kind == kind)
        c.enter(kind, c.other)
        damage(c.master)
        c.leave(kind)
        assert(#c.recorded == 2)
        assert(Log.isDeveloperMode() == false and #stubs.logLines == 0)
    end)
end

function T.flayerExternalPrefersGetterIdentityWithInvokerFallback()
    checkGetterAttribution("flayer", "external")
end

function T.elementConvertSetParamPrefersGetterIdentityWithInvokerFallback()
    checkGetterAttribution("elementConvert", "setParam")
end

function T.elementConvertExternalPrefersGetterIdentityWithInvokerFallback()
    checkGetterAttribution("elementConvert", "external")
end

function T.gettersOutsideMatchingBracketDoNotAffectAttribution()
    withProcs(function(c)
        local masterArgs = { [2] = { get_address = function() return 123 end } }
        local otherArgs = { [2] = { get_address = function() return 456 end } }
        for _, getter in pairs(GETTERS) do c.hooks[getter].pre(masterArgs) end
        c.enter("flayer", c.other)
        c.external(160)
        c.leave("flayer")
        c.enter("elementConvert", c.other)
        c.setParam(160, c.master)
        c.leave("elementConvert")
        assert(#c.recorded == 0)
        c.enter("flayer", c.other)
        c.enter("poison", c.other)
        for _, getter in pairs(GETTERS) do c.hooks[getter].pre(masterArgs) end
        c.external(15)
        c.leave("poison")
        c.external(160)
        c.leave("flayer")
        assert(#c.recorded == 0)
        c.enter("poison", c.master)
        for _, getter in pairs(GETTERS) do c.hooks[getter].pre(otherArgs) end
        c.external(15)
        c.leave("poison")
        assert(#c.recorded == 1 and c.recorded[1].kind == "poison")
        c.enter("flayer", c.master)
        c.hooks[GETTERS.ryuki].pre(otherArgs)
        c.external(160)
        c.leave("flayer")
        c.enter("elementConvert", c.master)
        c.hooks[GETTERS.stabbing].pre(otherArgs)
        c.setParam(160, c.other)
        c.leave("elementConvert")
        assert(#c.recorded == 3)
    end)
end

function T.failedGetterIdentityRejectsMasterInvoker()
    withProcs(function(c)
        for _, kind in ipairs({ "flayer", "elementConvert" }) do
            local getter = kind == "flayer" and GETTERS.stabbing or GETTERS.ryuki
            for _, readAddress in ipairs({
                function() error("address unavailable") end,
                function() return nil end,
            }) do
                c.enter(kind, c.master)
                c.hooks[getter].pre({ [2] = { get_address = readAddress } })
                c.setParam(160, c.master)
                c.external(160)
                c.leave(kind)
            end
        end
        assert(#c.recorded == 0 and #stubs.logLines == 0)
    end)
end

function T.nestedGetterAttributionStaysWithInnermostBracket()
    withProcs(function(c)
        c.enter("flayer", c.other)
        c.hooks[GETTERS.stabbing].pre({ [2] = { get_address = function() return 123 end } })
        c.enter("flayer", c.master)
        c.hooks[GETTERS.stabbing].pre({ [2] = { get_address = function() return 456 end } })
        c.external(160)
        c.leave("flayer")
        assert(#c.recorded == 0)
        c.external(160)
        c.external(160)
        c.leave("flayer")
        assert(#c.recorded == 1 and c.recorded[1].kind == "flayer")
    end)
end

function T.nonpositiveAndInvalidDamageDoNotConsumeBracket()
    withProcs(function(c)
        for _, kind in ipairs({ "blast", "poison", "flayer", "elementConvert" }) do
            c.enter(kind, c.master)
            local record = kind == "blast" and function(value) c.setParam(value, c.master) end or c.external
            for _, value in ipairs({ 0, -1, "invalid", false }) do record(value) end
            record(nil)
            local count = #c.recorded
            record(15.5)
            c.leave(kind)
            assert(#c.recorded == count + 1)
            assert(c.recorded[#c.recorded].kind == kind and c.recorded[#c.recorded].damage == 15.5)
        end
        assert(#c.recorded == 4)
    end)
end

function T.attributionHelperRemainsOverridableAfterInstall()
    withProcs(function(c)
        c.procs.attackerIsMaster = function(key) return key == c.other end
        c.enter("flayer", c.other)
        c.external(160)
        c.leave("flayer")
        c.enter("blast", c.master)
        c.setParam(100, c.other)
        c.leave("blast")
        assert(#c.recorded == 2)
    end)
end

function T.diagnosticsAreGatedAndUseSharedLogKeys()
    withProcs(function(c)
        local sameSkill = { get_address = function() return 123 end }
        local otherSkill = { get_address = function() return 456 end }
        local function probe()
            for _, kind in ipairs({ "blast", "poison", "flayer", "elementConvert" }) do
                c.enter(kind, c.master)
                c.external(0, { _HasValue = false })
                if kind == "blast" or kind == "elementConvert" then c.setParam(0, c.master) end
                c.hooks[GETTERS.stabbing].pre({ [2] = sameSkill })
                c.hooks[GETTERS.ryuki].pre({ [2] = otherSkill })
                c.leave(kind)
            end
        end
        probe()
        assert(#stubs.logLines == 0 and #c.recorded == 0)
        Log.setDeveloperMode(true)
        probe()
        local lines = table.concat(stubs.logLines, "\n")
        for _, kind in ipairs({ "blast", "poison", "flayer", "elementConvert" }) do
            assert(lines:find("proc " .. kind .. " invoker Category=0 UniqueIndex=7 GameObject=MasterPlayer", 1, true))
            assert(lines:find("proc " .. kind .. " external value=0 _HasValue=false", 1, true))
            assert(lines:find("proc getter stabbing master=true kind=" .. kind, 1, true))
            assert(lines:find("proc getter ryuki master=false kind=" .. kind, 1, true))
            assert(Log.count("proc:" .. kind .. ":invoker") == 1)
            assert(Log.count("proc:" .. kind .. ":external") == 1)
            if kind == "blast" or kind == "elementConvert" then
                assert(lines:find("proc " .. kind .. " setParam value=0 master=true", 1, true))
                assert(Log.count("proc:" .. kind .. ":setParam") == 1)
            end
        end
        assert(Log.count("proc:getter:stabbing") == 4 and Log.count("proc:getter:ryuki") == 4)
        assert(#c.recorded == 0)
    end)
end

function T.getterDiagnosticsReturnBeforeReadingWhenDisabled()
    withProcs(function(c)
        sdk.to_managed_object = function() error("must not decode") end
        Game.masterHunter = function() error("must not read hunter") end
        for _, name in pairs(GETTERS) do c.hooks[name].pre({}) end
        assert(#stubs.logLines == 0 and #c.recorded == 0)
    end)
end

function T.diagnosticReadFailuresUseQuestionMarksAndKeepRecording()
    withProcs(function(c)
        Log.setDeveloperMode(true)
        c.master.Category = nil
        c.master.UniqueIndex = nil
        Game.callStatic = function() error("name unavailable") end
        c.procs.attackerIsMaster = function(key) return key == c.master end
        c.enter("flayer", c.master)
        sdk.to_valuetype = function() error("nullable unavailable") end
        c.external(160)
        Game.masterHunter = function() error("hunter unavailable") end
        c.hooks[GETTERS.stabbing].pre({})
        c.leave("flayer")
        local lines = table.concat(stubs.logLines, "\n")
        assert(lines:find("invoker Category=? UniqueIndex=? GameObject=?", 1, true))
        assert(lines:find("external value=160 _HasValue=?", 1, true))
        assert(lines:find("getter stabbing master=? kind=flayer", 1, true))
        assert(#c.recorded == 1 and c.recorded[1].kind == "flayer")
    end)
end

function T.hookArgumentsUseExactSdkDecoders()
    withProcs(function(c)
        Log.setDeveloperMode(true)
        local objectPointer, keyPointer, floatPointer, nullablePointer = {}, {}, {}, {}
        sdk.to_managed_object = function(pointer)
            assert(pointer == objectPointer)
            return { _Invoker = c.master }
        end
        sdk.to_float = function(pointer)
            assert(pointer == floatPointer)
            return 42.5
        end
        sdk.to_valuetype = function(pointer, typeName)
            if pointer == keyPointer then
                assert(typeName == "app.TARGET_ACCESS_KEY")
                return c.master
            end
            assert(pointer == nullablePointer and typeName == "System.Nullable`1<app.TARGET_ACCESS_KEY>")
            return { _HasValue = true, _Value = c.other }
        end
        c.hooks[BRACKETS.blast].pre({ [2] = objectPointer })
        c.setParam(floatPointer, keyPointer)
        c.leave("blast")
        c.hooks[BRACKETS.flayer].pre({ [2] = objectPointer })
        c.external(floatPointer, nullablePointer)
        c.leave("flayer")
        assert(#c.recorded == 2 and c.recorded[1].damage == 42.5 and c.recorded[2].damage == 42.5)
        assert(table.concat(stubs.logLines, "\n"):find("external value=42.5 _HasValue=true", 1, true))
    end)
end

function T.failedSdkDecodesDoNotCorruptStackOrRecord()
    withProcs(function(c)
        sdk.to_managed_object = function() error("bad object") end
        c.enter("flayer", c.master)
        c.external(160)
        c.leave("flayer")
        assert(c.procs.activeKind() == nil and #c.recorded == 0)
        c.enter("blast", c.master)
        sdk.to_float = function() error("bad float") end
        c.setParam(100, c.master)
        sdk.to_float = function(value) return value end
        sdk.to_valuetype = function() error("bad key") end
        c.setParam(100, c.master)
        c.leave("blast")
        assert(c.procs.activeKind() == nil and #c.recorded == 0)
    end)
end

function T.nonHunterInvokerNeverResolvesCharacter()
    withProcs(function(c)
        local otomo = { Category = 2, UniqueIndex = 0 }
        local gimmick = { Category = 4, UniqueIndex = 1 }
        local invalid = { Category = 4294967295, UniqueIndex = 4294967295 }
        for _, key in ipairs({ otomo, gimmick, invalid, {} }) do
            c.enter("poison", key)
            c.external(15)
            c.leave("poison")
            c.enter("blast", c.master)
            c.setParam(100, key)
            c.leave("blast")
        end
        assert(#c.recorded == 0)
        assert(#c.callStaticCalls == 0, "non-hunter keys must not reach the character resolver")
        assert(c.procs.attackerIsMaster(otomo) == false and #c.callStaticCalls == 0)
        assert(c.procs.attackerIsMaster(c.master) == true and #c.callStaticCalls == 1)
    end)
end

function T.invokerIsReadOnlyWhenDamageNeedsAttribution()
    withProcs(function(c)
        local reads = 0
        local this = setmetatable({}, { __index = function(_, field)
            if field == "_Invoker" then
                reads = reads + 1
                return c.master
            end
        end })
        c.hooks[BRACKETS.poison].pre({ [2] = this })
        c.leave("poison")
        assert(reads == 0 and #c.callStaticCalls == 0)
        c.hooks[BRACKETS.poison].pre({ [2] = this })
        c.external(15)
        c.external(15)
        c.leave("poison")
        assert(reads == 1 and #c.callStaticCalls == 1 and #c.recorded == 1)
    end)
end

return T
