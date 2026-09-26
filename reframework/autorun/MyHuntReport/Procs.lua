local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")

local Procs = {}

local KEY_TYPE = "app.TARGET_ACCESS_KEY"

local brackets = {}
local installed = false

function Procs.reset()
    brackets = {}
end

function Procs.activeKind()
    local bracket = brackets[#brackets]
    return bracket and bracket.kind or nil
end

function Procs.attackerIsMaster(key)
    if key == nil then return false end
    local character = Game.callStatic("app.TargetAccessKeyUtil", "getCharacter(app.TARGET_ACCESS_KEY)", key)
    if not character then return false end
    local ok, gameObject = pcall(function() return character:get_GameObject() end)
    if not ok then return false end
    return Game.isMasterGameObject(gameObject)
end

local function decodeKey(pointer)
    local ok, key = pcall(sdk.to_valuetype, pointer, KEY_TYPE)
    if ok then return key end
    return nil
end

local function onSetParam(args)
    local bracket = brackets[#brackets]
    if not bracket or (bracket.kind ~= "blast" and bracket.kind ~= "elementConvert") then return end
    local ok, value = pcall(sdk.to_float, args[3])
    local isMaster = Procs.attackerIsMaster(decodeKey(args[4]))
    Log.debug("proc " .. bracket.kind .. " setParam value=" .. (ok and tostring(value) or "?")
        .. " master=" .. tostring(isMaster), "proc:" .. bracket.kind .. ":setParam")
    if not ok or type(value) ~= "number" or value <= 0 or bracket.recorded or not isMaster then return end
    bracket.recorded = true
    Session.addProc({ kind = bracket.kind, damage = value, time = Game.uptime() })
end

local function diagnosticValue(read)
    local ok, value = pcall(read)
    if ok and value ~= nil then return tostring(value) end
    return "?"
end

local function invokerIsMaster(bracket)
    if bracket.invokerIsMaster == nil then
        bracket.invokerIsMaster = Procs.attackerIsMaster(bracket.invoker)
    end
    return bracket.invokerIsMaster
end

local function enterBracket(kind, args)
    local bracket = { kind = kind, invoker = nil, invokerIsMaster = nil, recorded = false }
    brackets[#brackets + 1] = bracket
    local ok, invoker = pcall(function()
        local this = sdk.to_managed_object(args[2])
        return this:get_Invoker()
    end)
    if not ok then invoker = nil end
    bracket.invoker = invoker
    if not Log.isDeveloperMode() then return end
    local category = diagnosticValue(function() return invoker.Category end)
    local uniqueIndex = diagnosticValue(function() return invoker.UniqueIndex end)
    local name = diagnosticValue(function()
        if invoker == nil then return nil end
        local character = Game.callStatic("app.TargetAccessKeyUtil", "getCharacter(app.TARGET_ACCESS_KEY)", invoker)
        return character:get_GameObject():get_Name()
    end)
    Log.debug("proc " .. kind .. " invoker Category=" .. category .. " UniqueIndex=" .. uniqueIndex
        .. " GameObject=" .. name, "proc:" .. kind .. ":invoker")
end

local function leaveBracket()
    brackets[#brackets] = nil
end

local function onExternalDamage(args)
    local bracket = brackets[#brackets]
    if not bracket then return end
    local ok, value = pcall(sdk.to_float, args[3])
    if Log.isDeveloperMode() then
        local hasValue = diagnosticValue(function()
            local key = sdk.to_valuetype(args[5], "System.Nullable`1<app.TARGET_ACCESS_KEY>")
            return key._HasValue
        end)
        Log.debug("proc " .. bracket.kind .. " external value=" .. (ok and tostring(value) or "?")
            .. " _HasValue=" .. hasValue, "proc:" .. bracket.kind .. ":external")
    end
    if bracket.kind ~= "poison" and bracket.kind ~= "flayer" and bracket.kind ~= "elementConvert" then return end
    if not ok or type(value) ~= "number" or value <= 0 or bracket.recorded or not invokerIsMaster(bracket) then return end
    bracket.recorded = true
    Session.addProc({ kind = bracket.kind, damage = value, time = Game.uptime() })
end

local function logGetter(method, args)
    if not Log.isDeveloperMode() then return end
    local isMaster = diagnosticValue(function()
        local this = sdk.to_managed_object(args[2])
        local masterSkill = Game.masterHunter():get_HunterSkill()
        local address = this:get_address()
        local masterAddress = masterSkill:get_address()
        if address == nil or masterAddress == nil then return nil end
        return address == masterAddress
    end)
    Log.debug("proc getter " .. method .. " master=" .. isMaster .. " kind=" .. tostring(Procs.activeKind()),
        "proc:getter:" .. method)
end

function Procs.install()
    if installed then return end
    installed = true
    Game.hook("app.cEnemyBadConditionBlast", "onActivate", function(args)
        enterBracket("blast", args)
    end, leaveBracket)
    Game.hook("app.cEnemyBadConditionPoison", "onUpdateActive", function(args)
        enterBracket("poison", args)
    end, leaveBracket)
    Game.hook("app.cEnemyBadConditionSkillStabbing", "onActivate", function(args)
        enterBracket("flayer", args)
    end, leaveBracket)
    Game.hook("app.cEnemyBadConditionSkillRyuki", "onActivate", function(args)
        enterBracket("elementConvert", args)
    end, leaveBracket)
    Game.hook("app.cEnemyStockDamage.cBadConditionDamageInfo",
        "setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)", onSetParam)
    Game.hook("app.cEnemyStockDamage",
        "stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)",
        onExternalDamage)
    Game.hook("app.cHunterSkill", "getSkillStabbingAddDamage(app.cEnemyContextHolder)", function(args)
        logGetter("stabbing", args)
    end)
    Game.hook("app.cHunterSkill", "getSkillRyukiAddDamage(app.cEnemyContextHolder, System.Single, System.Single)", function(args)
        logGetter("ryuki", args)
    end)
end

return Procs
