local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local ProcPacketProbe = {}

ProcPacketProbe.COUNTER_ORDER = {
    "packetFlayer", "packetRyuki", "toggle", "activateBlast", "activateFlayer", "activateRyuki",
    "activateInsidePacket", "setParamInsidePacket", "externalInsidePacket",
    "setParamInsideActivate", "externalInsideActivate",
}

local KEY_TYPE = "app.TARGET_ACCESS_KEY"
local NULLABLE_KEY_TYPE = "System.Nullable`1<app.TARGET_ACCESS_KEY>"
local HUNTER_CATEGORIES = { [0] = true, [5] = true }

local counters = {}
local brackets = {}
local installed = false

local function resetQuestState()
    for _, name in ipairs(ProcPacketProbe.COUNTER_ORDER) do counters[name] = 0 end
    brackets = {}
end

resetQuestState()

function ProcPacketProbe.formatValue(value)
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        if math.type(value) == "integer" then return tostring(value) end
        return string.format("%.1f", value)
    end
    return tostring(value)
end

local function readValue(read)
    local ok, value = pcall(read)
    if ok then return ProcPacketProbe.formatValue(value) end
    return "?"
end

local function unresolvedOr(read)
    local ok, value = pcall(read)
    if ok and value ~= nil then return ProcPacketProbe.formatValue(value) end
    return "unresolved"
end

local function trace(text)
    Log.trace("pp " .. text)
end

local function bump(name)
    counters[name] = (counters[name] or 0) + 1
end

local function unreadable(handler, step)
    Log.debug("pp " .. handler .. " unreadable step=" .. step, "pp:unreadable:" .. handler .. ":" .. step)
end

local function pushBracket(kind)
    brackets[#brackets + 1] = kind
end

local function popBracket()
    if #brackets > 0 then brackets[#brackets] = nil end
end

local function bracketText()
    return tostring(brackets[#brackets] or "none")
end

local function insideActivation()
    local top = brackets[#brackets]
    return top ~= nil and top:sub(1, 9) == "activate:"
end

local function managedArg(args, index)
    local ok, object = pcall(function() return sdk.to_managed_object(args[index]) end)
    if ok then return object end
    return nil
end

local function keyText(key)
    return readValue(function() return key.Category end) .. "/" .. readValue(function() return key.UniqueIndex end)
end

local function keyObjectName(key)
    local ok, name = pcall(function()
        if not HUNTER_CATEGORIES[key.Category] then return nil end
        local character, err = Game.callStatic("app.TargetAccessKeyUtil", "getHunterCharacter(app.TARGET_ACCESS_KEY)", key)
        if err then error(err) end
        if not character then return nil end
        return character:get_GameObject():get_Name()
    end)
    if ok then return ProcPacketProbe.formatValue(name) end
    return "?"
end

function ProcPacketProbe.summaryLine(values)
    local parts = {}
    for _, name in ipairs(ProcPacketProbe.COUNTER_ORDER) do
        parts[#parts + 1] = name .. "=" .. tostring(values[name] or 0)
    end
    return "summary " .. table.concat(parts, " ")
end

function ProcPacketProbe.counters()
    return counters
end

function ProcPacketProbe.reset()
    resetQuestState()
end

function ProcPacketProbe.activeBracket()
    return brackets[#brackets]
end

local function onQuestStart()
    resetQuestState()
    if not Log.isDeveloperMode() then return end
    local director = nil
    pcall(function() director = Game.singleton("app.MissionManager"):get_QuestDirector() end)
    local lateJoin = unresolvedOr(function() return director["<Param>k__BackingField"].IsLateJoinQuestStarted end)
    local host = unresolvedOr(function() return director["<Param>k__BackingField"].IsHostQuestStarted end)
    local master = unresolvedOr(function() return Game.masterHunter():get_GameObject():get_Name() end)
    trace("state lateJoinStarted=" .. lateJoin .. " hostStarted=" .. host .. " master=" .. master)
end

local function onResultPost()
    if not Log.isDeveloperMode() then return end
    trace(ProcPacketProbe.summaryLine(counters))
end

local function onPacketPre(kind, counter)
    return function(args)
        if not Log.isDeveloperMode() then return end
        pushBracket("packet:" .. kind)
        pcall(function() thread.get_hook_storage().pushed = true end)
        bump(counter)
        local packet = managedArg(args, 3)
        if not packet then return unreadable("packet " .. kind, "packet") end
        local gui = "-"
        if kind == "flayer" then gui = readValue(function() return packet.GuiState end) end
        trace("packet " .. kind .. " em=" .. readValue(function() return packet.UniqueIndex end)
            .. " damage=" .. readValue(function() return packet.Damage end)
            .. " attackerNet=" .. readValue(function() return packet.AttackerNetID end)
            .. " gui=" .. gui)
    end
end

local function onTogglePre(args)
    if not Log.isDeveloperMode() then return end
    pushBracket("toggle")
    pcall(function() thread.get_hook_storage().pushed = true end)
    bump("toggle")
    local packet = managedArg(args, 3)
    if not packet then return unreadable("toggle", "packet") end
    trace("toggle em=" .. readValue(function() return packet.UniqueIndex end)
        .. " type=" .. readValue(function() return packet.Type end)
        .. " active=" .. readValue(function() return packet.ActiveAndCount end)
        .. " invoker=" .. readValue(function() return packet.Invoker end))
end

local function onReceivePost()
    local ok, pushed = pcall(function() return thread.get_hook_storage().pushed end)
    if not ok or pushed == true then popBracket() end
    pcall(function() thread.get_hook_storage().pushed = nil end)
end

local function invokerTexts(this)
    local okInvoker, invoker = pcall(function() return this._Invoker end)
    if not okInvoker then return "?", "?" end
    if invoker == nil then return "nil", "nil" end
    return keyText(invoker), keyObjectName(invoker)
end

local function blastFields(this)
    return " count=" .. readValue(function() return this._Count end)
        .. " player=" .. readValue(function() return this._IsPlayerCondition end)
        .. " damageEm=" .. readValue(function() return this._PresetParamRef._DamageEm end)
        .. " damageExEm=" .. readValue(function() return this._PresetParamRef._DamageExEm end)
end

local function onActivate(kind, counter, extraFields)
    return function(args)
        if not Log.isDeveloperMode() then return end
        bump(counter)
        if #brackets > 0 then bump("activateInsidePacket") end
        local this = managedArg(args, 2)
        if not this then return unreadable("activate " .. kind, "this") end
        local invokerText, objectText = invokerTexts(this)
        local line = "activate " .. kind .. " invoker=" .. invokerText .. " obj=" .. objectText .. " in=" .. bracketText()
        if extraFields then line = line .. extraFields(this) end
        trace(line)
        pushBracket("activate:" .. kind)
        pcall(function() thread.get_hook_storage().pushed = true end)
    end
end

local function onSetParam(args)
    if not Log.isDeveloperMode() or #brackets == 0 then return end
    bump(insideActivation() and "setParamInsideActivate" or "setParamInsidePacket")
    local value = readValue(function() return sdk.to_float(args[3]) end)
    local okKey, key = pcall(function() return sdk.to_valuetype(args[4], KEY_TYPE) end)
    local keyLine = "?"
    if okKey and key then keyLine = keyText(key) end
    trace("setParam value=" .. value .. " key=" .. keyLine .. " in=" .. bracketText())
end

local function onExternal(args)
    if not Log.isDeveloperMode() or #brackets == 0 then return end
    bump(insideActivation() and "externalInsideActivate" or "externalInsidePacket")
    local value = readValue(function() return sdk.to_float(args[3]) end)
    local okKey, nullable = pcall(function() return sdk.to_valuetype(args[5], NULLABLE_KEY_TYPE) end)
    local hasKey, key = "?", "?"
    if okKey and nullable then
        hasKey = readValue(function() return nullable._HasValue end)
        key = readValue(function() return nullable._Value.Category end) .. "/" .. readValue(function() return nullable._Value.UniqueIndex end)
    end
    trace("external value=" .. value .. " hasKey=" .. hasKey .. " key=" .. key .. " in=" .. bracketText())
end

local function installProcHooks()
    Game.hook("app.cEnemyBadConditionSkillStabbing", "receiveActivatePacket(app.net_packet.cEmSkillActivateStabbing)", onPacketPre("flayer", "packetFlayer"), onReceivePost)
    Game.hook("app.cEnemyBadConditionSkillRyuki", "receiveActivatePacket(app.net_packet.cEmSkillActivateRyuki)", onPacketPre("elementConvert", "packetRyuki"), onReceivePost)
    Game.hook("app.cEmModuleConditions.mcUpdater", "onReceivePacket(app.net_packet.cEmToggleCondition)", onTogglePre, onReceivePost)
    Game.hook("app.cEnemyBadConditionBlast", "onActivate", onActivate("blast", "activateBlast", blastFields), onReceivePost)
    Game.hook("app.cEnemyBadConditionSkillStabbing", "onActivate", onActivate("flayer", "activateFlayer"), onReceivePost)
    Game.hook("app.cEnemyBadConditionSkillRyuki", "onActivate", onActivate("elementConvert", "activateRyuki"), onReceivePost)
    Game.hook("app.cEnemyStockDamage.cBadConditionDamageInfo", "setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)", onSetParam)
    Game.hook("app.cEnemyStockDamage", "stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)", onExternal)
end

local function installFlowHooks()
    Game.hook("app.cQuestPlaying", "enter()", onQuestStart)
    Game.hook("app.cGUIQuestResultInfo", "execute()", nil, onResultPost)
end

function ProcPacketProbe.install()
    if installed then return end
    installed = true
    installFlowHooks()
    installProcHooks()
end

return ProcPacketProbe
