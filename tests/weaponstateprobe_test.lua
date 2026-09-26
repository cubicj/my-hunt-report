local stubs = require("stubs")
local WeaponStateProbe = require("MyHuntReport.WeaponStateProbe")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local function withHunter(hunter, callback)
    local masterHunter = Game.masterHunter
    Game.masterHunter = function() return hunter end
    WeaponStateProbe.reset()
    local ok, err = pcall(callback)
    Game.masterHunter = masterHunter
    WeaponStateProbe.reset()
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

local function handlingOf(typeName, members)
    local handling = {
        get_type_definition = function() return { get_name = function() return typeName end } end,
        call = function(self, name, ...)
            local member = members[name]
            if member == nil then error("no method " .. name) end
            return member(self, ...)
        end,
    }
    for key, value in pairs(members) do
        if type(value) ~= "function" then handling[key] = value end
    end
    return handling
end

function T.formatValueCoversScalarsAndHolders()
    assert(WeaponStateProbe.formatValue(true) == "true")
    assert(WeaponStateProbe.formatValue(false) == "false")
    assert(WeaponStateProbe.formatValue(nil) == "nil")
    assert(WeaponStateProbe.formatValue(4) == "4")
    assert(WeaponStateProbe.formatValue(87.456) == "87.5")
    assert(WeaponStateProbe.formatValue({ get_Value = function() return 12.34 end }) == "12.3")
    assert(WeaponStateProbe.formatValue({ get_type_definition = function() return { get_name = function() return "cEnergyParts" end } end }) == "cEnergyParts")
    assert(WeaponStateProbe.formatValue("text") == "text")
end

function T.serializeStripsGetPrefixAndMarksErrors()
    local handling = handlingOf("app.cHunterWp02Handling", {
        get_IsKijinOn = function() return true end,
        get_IsKijinEnhancement = function() return false end,
        get_KijinGauge = function() return { get_Value = function() return 87.5 end } end,
        get_KijinComboLv = function() error("boom") end,
        _EnergyPartsState = 2,
    })
    local line = WeaponStateProbe.serialize(handling, { "get_IsKijinOn", "get_IsKijinEnhancement", "get_KijinGauge", "get_KijinComboLv", "_EnergyPartsState", "get_Missing" })
    assert(line == "IsKijinOn=true IsKijinEnhancement=false KijinGauge=87.5 KijinComboLv=err _EnergyPartsState=2 Missing=err", line)
end

function T.serializeInvokesGettersThroughCallNotLuaFunctions()
    local handling = handlingOf("app.cHunterWp03Handling", { get_AuraLevel = function() return 4 end })
    assert(rawget(handling, "get_AuraLevel") == nil)
    assert(WeaponStateProbe.serialize(handling, { "get_AuraLevel" }) == "AuraLevel=4")
end

function T.serializeWalksDottedPathsThroughNestedObjects()
    local snipe = handlingOf("app.Wp12Def.cSnipeAmmo", { get_CurrentAmmo = function() return 3 end, _ChargeTimer = 1.25 })
    local handling = handlingOf("app.cHunterWp12Handling", {
        get_SnipeAmmo = function() return snipe end,
        get_EnergyBulletInfo = function() return nil end,
    })
    local line = WeaponStateProbe.serialize(handling, { "get_SnipeAmmo.get_CurrentAmmo", "get_SnipeAmmo._ChargeTimer", "get_EnergyBulletInfo.get_CharageLevel", "get_Missing.get_Value" })
    assert(line == "SnipeAmmo.CurrentAmmo=3 SnipeAmmo._ChargeTimer=1.2 EnergyBulletInfo.CharageLevel=nil Missing.Value=err", line)
end

function T.gettersCoverTheSpecWeapons()
    for _, weaponType in ipairs({ 2, 3, 8, 9, 10, 12 }) do
        assert(type(WeaponStateProbe.GETTERS[weaponType]) == "table" and #WeaponStateProbe.GETTERS[weaponType] > 0, tostring(weaponType))
    end
    assert(WeaponStateProbe.GETTERS[3][1] == "get_AuraLevel")
    assert(WeaponStateProbe.GETTERS[2][2] == "get_IsKijinEnhancement")
end

function T.updateDoesNothingOutsideDeveloperMode()
    local hunter = { get_WeaponType = function() return 2 end, get_WeaponHandling = function() error("must not be called") end }
    withHunter(hunter, function()
        Log.setDeveloperMode(false)
        WeaponStateProbe.update()
        assert(#stubs.logLines == 0)
    end)
end

function T.updateLogsClassOnceAndStateOnChange()
    local kijinOn = false
    local handling = handlingOf("app.cHunterWp02Handling", {
        get_IsKijinOn = function() return kijinOn end,
        get_IsKijinEnhancement = function() return false end,
        get_IsMikiriBuff = function() return false end,
        get_KijinGauge = function() return { get_Value = function() return 0.0 end } end,
        get_KijinComboLv = function() return 0 end,
    })
    local hunter = { get_WeaponType = function() return 2 end, get_WeaponHandling = function() return handling end }
    withHunter(hunter, function()
        Log.setDeveloperMode(true)
        WeaponStateProbe.update()
        WeaponStateProbe.update()
        assert(#stubs.logLines == 2, "got " .. #stubs.logLines)
        assert(stubs.logLines[1] == "[MyHuntReport] wpstate class=app.cHunterWp02Handling wp=2", stubs.logLines[1])
        assert(stubs.logLines[2] == "[MyHuntReport] wpstate wp=2 IsKijinOn=false IsKijinEnhancement=false IsMikiriBuff=false KijinGauge=0.0 KijinComboLv=0", stubs.logLines[2])
        kijinOn = true
        WeaponStateProbe.update()
        assert(#stubs.logLines == 3)
        assert(stubs.logLines[3]:find("IsKijinOn=true", 1, true), stubs.logLines[3])
    end)
end

function T.updateLogsClassAgainWhenWeaponChangesAndSkipsUnlistedWeapons()
    local weaponType = 3
    local handling = handlingOf("app.cHunterWp03Handling", { get_AuraLevel = function() return 4 end })
    local hunter = { get_WeaponType = function() return weaponType end, get_WeaponHandling = function() return handling end }
    withHunter(hunter, function()
        Log.setDeveloperMode(true)
        WeaponStateProbe.update()
        assert(#stubs.logLines == 2)
        assert(stubs.logLines[2] == "[MyHuntReport] wpstate wp=3 AuraLevel=4", stubs.logLines[2])
        weaponType = 0
        handling = handlingOf("app.cHunterWp00Handling", {})
        WeaponStateProbe.update()
        WeaponStateProbe.update()
        assert(#stubs.logLines == 3, "got " .. #stubs.logLines)
        assert(stubs.logLines[3] == "[MyHuntReport] wpstate class=app.cHunterWp00Handling wp=0", stubs.logLines[3])
    end)
end

function T.updateSurvivesMissingHunterOrHandling()
    withHunter(nil, function()
        Log.setDeveloperMode(true)
        WeaponStateProbe.update()
        assert(#stubs.logLines == 0)
    end)
    local hunter = { get_WeaponType = function() return 2 end, get_WeaponHandling = function() return nil end }
    withHunter(hunter, function()
        Log.setDeveloperMode(true)
        WeaponStateProbe.update()
        assert(#stubs.logLines == 0)
    end)
    local broken = { get_WeaponType = function() error("no weapon") end, get_WeaponHandling = function() return {} end }
    withHunter(broken, function()
        Log.setDeveloperMode(true)
        WeaponStateProbe.update()
        assert(#stubs.logLines == 0)
    end)
end

return T
