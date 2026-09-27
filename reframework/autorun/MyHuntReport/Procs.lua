local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")

local Procs = {}

local KEY_TYPE = "app.TARGET_ACCESS_KEY"
local HUNTER_CATEGORIES = { [0] = true, [5] = true }
local PACKET_TTL_SECONDS = 1.0

local brackets = {}
local installed = false
local skillProcsInstalled = false
local extendedInstalled = false
local packetDamage = {}

function Procs.reset()
    brackets = {}
    packetDamage = {}
end

function Procs.activeKind()
    local bracket = brackets[#brackets]
    return bracket and bracket.kind or nil
end

function Procs.pendingPacketDamage(kind)
    local pending = packetDamage[kind]
    return pending and pending.damage or nil
end

local function takePacketDamage(kind)
    local pending = packetDamage[kind]
    packetDamage[kind] = nil
    if not pending then return nil end
    if Game.uptime() - pending.time > PACKET_TTL_SECONDS then return nil end
    return pending.damage
end

local function isHunterKey(key)
    if key == nil then return false end
    local ok, category = pcall(function() return key.Category end)
    return ok and HUNTER_CATEGORIES[category] == true
end

function Procs.attackerIsMaster(key)
    if not isHunterKey(key) then return false end
    local character = Game.callStatic("app.TargetAccessKeyUtil", "getHunterCharacter(app.TARGET_ACCESS_KEY)", key)
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

local function readInvoker(bracket)
    if bracket.invokerRead then return bracket.invoker end
    bracket.invokerRead = true
    local ok, invoker = pcall(function() return bracket.this._Invoker end)
    if ok then bracket.invoker = invoker end
    return bracket.invoker
end

local function invokerIsMaster(bracket)
    if bracket.invokerIsMaster == nil then
        bracket.invokerIsMaster = Procs.attackerIsMaster(readInvoker(bracket))
    end
    return bracket.invokerIsMaster
end

local function attributedToMaster(bracket)
    if (bracket.kind == "flayer" or bracket.kind == "elementConvert") and bracket.getterIsMaster ~= nil then
        return bracket.getterIsMaster == true
    end
    return invokerIsMaster(bracket)
end

local function onSetParam(args)
    local bracket = brackets[#brackets]
    if not bracket or (bracket.kind ~= "blast" and bracket.kind ~= "elementConvert") then return end
    local ok, value = pcall(sdk.to_float, args[3])
    local isMaster
    if bracket.kind == "blast" then
        isMaster = Procs.attackerIsMaster(decodeKey(args[4]))
    else
        isMaster = attributedToMaster(bracket)
    end
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

local function enterBracket(kind, args)
    local bracket = { kind = kind, this = nil, invoker = nil, invokerRead = false, invokerIsMaster = nil, recorded = false }
    brackets[#brackets + 1] = bracket
    local ok, this = pcall(sdk.to_managed_object, args[2])
    if ok then bracket.this = this end
    local pending = takePacketDamage(kind)
    if pending and attributedToMaster(bracket) then
        bracket.recorded = true
        Session.addProc({ kind = kind, damage = pending, time = Game.uptime() })
    end
    if not Log.isDeveloperMode() then return end
    local invoker = readInvoker(bracket)
    local category = diagnosticValue(function() return invoker.Category end)
    local uniqueIndex = diagnosticValue(function() return invoker.UniqueIndex end)
    local name = diagnosticValue(function()
        if not isHunterKey(invoker) then return nil end
        local character = Game.callStatic("app.TargetAccessKeyUtil", "getHunterCharacter(app.TARGET_ACCESS_KEY)", invoker)
        return character:get_GameObject():get_Name()
    end)
    Log.debug("proc " .. kind .. " invoker Category=" .. category .. " UniqueIndex=" .. uniqueIndex
        .. " GameObject=" .. name .. " pending=" .. tostring(pending) .. " recorded=" .. tostring(bracket.recorded),
        "proc:" .. kind .. ":invoker")
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
    if not ok or type(value) ~= "number" or value <= 0 or bracket.recorded or not attributedToMaster(bracket) then return end
    bracket.recorded = true
    Session.addProc({ kind = bracket.kind, damage = value, time = Game.uptime() })
end

local function onActivatePacket(kind)
    return function(args)
        local ok, value = pcall(function() return sdk.to_managed_object(args[3]).Damage end)
        if ok and type(value) == "number" and value > 0 then
            packetDamage[kind] = { damage = value, time = Game.uptime() }
        else
            packetDamage[kind] = nil
        end
        Log.debug("proc " .. kind .. " packet damage=" .. (ok and tostring(value) or "?"), "proc:" .. kind .. ":packet")
    end
end

local function onGetter(kind, args)
    local bracket = brackets[#brackets]
    local matching = bracket and bracket.kind == kind
    if not matching and not Log.isDeveloperMode() then return end
    local ok, isMaster = pcall(function()
        local this = sdk.to_managed_object(args[2])
        local masterSkill = Game.masterHunter():get_HunterSkill()
        local address = this:get_address()
        local masterAddress = masterSkill:get_address()
        if address == nil or masterAddress == nil then return nil end
        return address == masterAddress
    end)
    if matching then bracket.getterIsMaster = ok and isMaster == true end
    if not Log.isDeveloperMode() then return end
    local method = kind == "flayer" and "stabbing" or "ryuki"
    local identity = ok and isMaster ~= nil and tostring(isMaster) or "?"
    Log.debug("proc getter " .. method .. " master=" .. identity .. " kind=" .. tostring(Procs.activeKind()),
        "proc:getter:" .. method)
end

function Procs.install()
    if installed then return end
    installed = true
    Game.hook("app.cEnemyBadConditionBlast", "onActivate", function(args)
        enterBracket("blast", args)
    end, leaveBracket)
    Game.hook("app.cEnemyStockDamage.cBadConditionDamageInfo",
        "setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)", onSetParam)
end

function Procs.installSkillProcs()
    if skillProcsInstalled then return end
    skillProcsInstalled = true
    Game.hook("app.cEnemyBadConditionSkillStabbing", "onActivate", function(args)
        enterBracket("flayer", args)
    end, leaveBracket)
    Game.hook("app.cEnemyBadConditionSkillRyuki", "onActivate", function(args)
        enterBracket("elementConvert", args)
    end, leaveBracket)
    Game.hook("app.cEnemyStockDamage",
        "stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)",
        onExternalDamage)
    Game.hook("app.cEnemyBadConditionSkillStabbing",
        "receiveActivatePacket(app.net_packet.cEmSkillActivateStabbing)",
        onActivatePacket("flayer"))
    Game.hook("app.cEnemyBadConditionSkillRyuki",
        "receiveActivatePacket(app.net_packet.cEmSkillActivateRyuki)",
        onActivatePacket("elementConvert"))
end

function Procs.skillProcsInstalled()
    return skillProcsInstalled
end

function Procs.installExtended()
    if extendedInstalled then return end
    extendedInstalled = true
    Game.hook("app.cEnemyBadConditionPoison", "onUpdateActive", function(args)
        enterBracket("poison", args)
    end, leaveBracket)
    Game.hook("app.cHunterSkill", "getSkillStabbingAddDamage(app.cEnemyContextHolder)", function(args)
        onGetter("flayer", args)
    end)
    Game.hook("app.cHunterSkill", "getSkillRyukiAddDamage(app.cEnemyContextHolder, System.Single, System.Single)", function(args)
        onGetter("elementConvert", args)
    end)
end

return Procs
