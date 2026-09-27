local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local GuestProbe = {}

GuestProbe.COUNTER_ORDER = {
    "own", "replica", "other", "toPacket", "netDamage", "calcNet", "calcInsideNetWithOwnPending",
    "markNet", "markAddrMismatch", "deadOwn", "deadReadFail", "woundReadFail", "meatReadFail",
    "receiveDamage", "receiveCond", "netCond", "extCond", "external", "setParam",
}

local OWN_LINE_BUDGET = 400
local RECEIVE_LINE_BUDGET = 20
local RESULT_KEY = "mhr_gp_result"

local counters = {}
local ownPending = {}
local netDepth = 0
local procStack = {}
local poisonLogged = {}
local receiveCondLines = 0
local ownLines = 0
local receiveLines = 0
local stateLogged = false
local installed = false

local function resetCounters()
    for _, name in ipairs(GuestProbe.COUNTER_ORDER) do counters[name] = 0 end
end

local function resetQuestState()
    resetCounters()
    ownPending = {}
    netDepth = 0
    procStack = {}
    poisonLogged = {}
    receiveCondLines = 0
    ownLines = 0
    receiveLines = 0
end

resetQuestState()

function GuestProbe.formatValue(value)
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
    if ok then return GuestProbe.formatValue(value) end
    return "?"
end

local function trace(text)
    Log.trace("gp " .. text)
end

local function bump(name)
    counters[name] = (counters[name] or 0) + 1
end

function GuestProbe.summaryLine(values)
    local parts = {}
    for index, name in ipairs(GuestProbe.COUNTER_ORDER) do
        parts[index] = name .. "=" .. tostring(values[name] or 0)
    end
    return "summary " .. table.concat(parts, " ")
end

function GuestProbe.counters()
    return counters
end

function GuestProbe.reset()
    resetQuestState()
    stateLogged = false
end

function GuestProbe.netDepth()
    return netDepth
end

function GuestProbe.classifyOwner(name, isMaster)
    if isMaster then return "own" end
    if type(name) == "string" and name:sub(1, 14) == "Player_Replica" then return "replica" end
    return "other"
end

local function derefObject(pointer)
    local ok, object = pcall(function()
        local slot = sdk.to_valuetype(pointer, "System.UInt64")
        local address = slot and slot:get_field("m_value") or nil
        if not address or address == 0 then return nil end
        return sdk.to_managed_object(address)
    end)
    if ok then return object end
    return nil
end

local function enemyIndexOf(gameObject)
    local ok, index = pcall(function()
        local em = Game.enemyContext(gameObject)
        if not em then return nil end
        return em:get_UniqueIndex()
    end)
    if ok then return index end
    return nil
end

local function unreadable(handler, step)
    Log.debug("gp " .. handler .. " unreadable step=" .. step, "gp:unreadable:" .. handler .. ":" .. step)
end

local function packetLine(packet)
    return "em=" .. readValue(function() return packet.UniqueIndex end)
        .. " attacker=" .. readValue(function() return packet.AttackerIndex end)
        .. " attack=" .. readValue(function() return packet.Attack end)
        .. " fix=" .. readValue(function() return packet.FixAttack end)
        .. " attr=" .. readValue(function() return packet.AttackAttr end) .. "/" .. readValue(function() return packet.AttrValue end)
end

local function onDetail(args)
    if not Log.isDeveloperMode() then return end
    local okHit, hitInfo = pcall(function() return sdk.to_managed_object(args[3]) end)
    if not okHit or not hitInfo then return unreadable("detail", "hitInfo") end
    local okOwner, owner = pcall(function() return hitInfo:getActualAttackOwner() end)
    if not okOwner or not owner then return unreadable("detail", "owner") end
    local okOwnerAddress, ownerAddress = pcall(function() return owner:get_address() end)
    local okMasterAddress, masterAddress = pcall(Game.masterAddress)
    if not okOwnerAddress or ownerAddress == nil or not okMasterAddress or masterAddress == nil then
        return unreadable("detail", "owner")
    end
    local isMaster = ownerAddress == masterAddress
    local okName, name = pcall(function() return owner:get_Name() end)
    if not isMaster and not okName then return unreadable("detail", "owner") end
    local kind = GuestProbe.classifyOwner(okName and name or nil, isMaster)
    if kind ~= "own" then
        bump(kind)
        return
    end
    local okTarget, target = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okTarget or not target then return unreadable("detail", "target") end
    local index = enemyIndexOf(target)
    if index == nil then return unreadable("detail", "index") end
    bump(kind)
    local okDead, isDead = pcall(function()
        return Game.componentOf(target, "app.EnemyCharacter"):get_HealthMgr():get_IsDead()
    end)
    if not okDead or isDead == nil then
        bump("deadReadFail")
    elseif isDead == true then
        bump("deadOwn")
    end
    local address
    local addressText = readValue(function()
        address = hitInfo:get_address()
        return address
    end)
    local okTime, time = pcall(Game.uptime)
    ownPending[index] = { address = address, time = okTime and time or nil }
    if ownLines >= OWN_LINE_BUDGET then return end
    ownLines = ownLines + 1
    trace("own detail em=" .. tostring(index) .. " addr=" .. addressText)
end

local function onNetPre(args)
    if not Log.isDeveloperMode() then return end
    netDepth = netDepth + 1
    bump("netDamage")
    local okPacket, packet = pcall(function() return sdk.to_managed_object(args[3]) end)
    if not okPacket or not packet then return unreadable("net", "packet") end
    trace("net damage " .. packetLine(packet)
        .. " act=" .. readValue(function() return packet.ActionType end)
        .. " parts=" .. readValue(function() return packet.PartsIndex end)
        .. " scar=" .. readValue(function() return packet.ScarIndex end)
        .. " cond=" .. readValue(function() return packet.AttackCond end) .. "/" .. readValue(function() return packet.CondValue end)
        .. " add=" .. readValue(function() return packet.SkillAdditionalDamage end))
end

local function onNetPost()
    if netDepth > 0 then netDepth = netDepth - 1 end
end

local function checkFreshness(em, preCalc)
    local okWound = pcall(function()
        local scarIndex = preCalc.Common.ScarIndex
        if scarIndex ~= -1 then
            local state = em.Scar._ScarParts:Get(scarIndex):get_State()
            if type(state) ~= "number" then error("wound state") end
        end
    end)
    if not okWound then bump("woundReadFail") end
    local okMeat = pcall(function()
        local meat = em.Parts._ParamParts._MeatArray._DataArray[preCalc.Common.MeatIndex._Value]
        if meat == nil then error("meat") end
    end)
    if not okMeat then bump("meatReadFail") end
end

local function onCalc(args)
    if not Log.isDeveloperMode() then return end
    local okThis, this = pcall(function() return sdk.to_managed_object(args[2]) end)
    if not okThis or not this then return unreadable("calc", "this") end
    local okPreCalc, preCalc = pcall(function() return derefObject(args[4]) end)
    if not okPreCalc or not preCalc then return unreadable("calc", "preCalc") end
    local okEm, em, index = pcall(function()
        local context = this:get_Context():get_Em()
        return context, context:get_UniqueIndex()
    end)
    if not okEm or index == nil then return unreadable("calc", "context") end
    local inNet = netDepth > 0
    local hasOwn = ownPending[index] ~= nil
    if inNet then bump("calcNet") end
    if inNet and hasOwn then bump("calcInsideNetWithOwnPending") end
    if hasOwn and not inNet then checkFreshness(em, preCalc) end
    trace("calc em=" .. tostring(index) .. " net=" .. tostring(inNet) .. " ownPending=" .. tostring(hasOwn)
        .. " attacker=" .. readValue(function() return preCalc.Common.Attacker.Category end) .. "/" .. readValue(function() return preCalc.Common.Attacker.UniqueIndex end)
        .. " attack=" .. readValue(function() return preCalc.Attack end)
        .. " fix=" .. readValue(function() return preCalc.FixAttack end)
        .. " attr=" .. readValue(function() return preCalc.AttackAttr end) .. "/" .. readValue(function() return preCalc.AttrValue end)
        .. " scar=" .. readValue(function() return preCalc.Common.ScarIndex end)
        .. " parts=" .. readValue(function() return preCalc.Common.PartsIndex end))
    if hasOwn and not inNet then
        local nonpositive = true
        for _, field in ipairs({ "Attack", "FixAttack", "AttrValue" }) do
            local ok, value = pcall(function() return preCalc[field] end)
            if not ok or (tonumber(value) or 0) > 0 then nonpositive = false end
        end
        if nonpositive then ownPending[index] = nil end
    end
end

local function onMark(args)
    if not Log.isDeveloperMode() then return end
    local okHit, hitInfo = pcall(function() return sdk.to_managed_object(args[4]) end)
    if not okHit or not hitInfo then return unreadable("mark", "hitInfo") end
    local okTarget, target = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okTarget or not target then return unreadable("mark", "target") end
    local index = enemyIndexOf(target)
    if index == nil then return unreadable("mark", "index") end
    local inNet = netDepth > 0
    if inNet then bump("markNet") end
    local pending = ownPending[index]
    local match = false
    local matchText = readValue(function()
        local address = hitInfo:get_address()
        match = pending ~= nil and address == pending.address
        return match
    end)
    if pending and not match then bump("markAddrMismatch") end
    if pending then ownPending[index] = nil end
    trace("mark em=" .. tostring(index) .. " net=" .. tostring(inNet) .. " addrMatch=" .. matchText
        .. " final=" .. readValue(function() return sdk.to_managed_object(args[3]).FinalDamage end))
end

local function onToPacketPost(retval)
    if not Log.isDeveloperMode() then return end
    bump("toPacket")
    local okPacket, packet = pcall(function() return sdk.to_managed_object(retval) end)
    if not okPacket or not packet then return unreadable("toPacket", "packet") end
    trace("toPacket " .. packetLine(packet)
        .. " scar=" .. readValue(function() return packet.ScarIndex end)
        .. " parts=" .. readValue(function() return packet.PartsIndex end))
end

local function onReceiveDamage(args)
    if not Log.isDeveloperMode() then return end
    bump("receiveDamage")
    local okPacket, packet = pcall(function() return sdk.to_managed_object(args[3]) end)
    if not okPacket or not packet then return unreadable("receive", "packet") end
    if receiveLines >= RECEIVE_LINE_BUDGET then return end
    receiveLines = receiveLines + 1
    trace("receive damage " .. packetLine(packet))
end

local function installHitHooks()
    Game.hook("app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)", onDetail)
    Game.hook("app.cEnemyStockDamage", "stockDamageNet(app.net_packet.cEmDamage)", onNetPre, onNetPost)
    Game.hook("app.cEnemyStockDamage",
        "calcStockDamage(app.cEnemyStockDamage.cCalcDamage, app.cEnemyStockDamage.cPreCalcDamage, app.cEnemyStockDamage.cDamageRate, System.Boolean)",
        onCalc)
    Game.hook("app.cEnemyStockDamage.mcEnemyHitMarkManager",
        "playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)", onMark)
    Game.hook("app.cEnemyStockDamage.cPreCalcDamage", "toPacket(app.cEnemyContextHolder)", nil, onToPacketPost)
    Game.hook("app.EnemyCharacter", "receivePacket_Damage(app.net_packet.cEmDamage)", onReceiveDamage)
end

local CONDITION_NAMES = {
    [0] = "ANGRY", [1] = "TIRED", [2] = "DEPLETION", [3] = "POISON", [4] = "POISON_EM", [5] = "PARALYSE", [6] = "PARALYSE_EM",
    [7] = "SLEEP", [8] = "SLEEP_EM", [9] = "BLAST", [10] = "BLAST_REACTION", [11] = "BLAST_EM", [12] = "BLAST_REACTION_EM",
    [13] = "RIDE", [14] = "STAMINA", [15] = "STUN", [16] = "STUN_EM", [17] = "CAPTURE", [18] = "FLASH", [19] = "FLASH_EM",
    [20] = "EAR", [21] = "KOYASI", [22] = "WEAK_ATTR_SLINGER", [23] = "WEAK_ATTR_BOOST", [24] = "LIGHT_PLANT", [25] = "PARRY",
    [26] = "PARRY_NPC", [27] = "BLOCK", [28] = "BLOCK_NPC", [29] = "SAND_DIG", [30] = "SCAR", [31] = "FIELD_PITFALL",
    [32] = "SMOKE_BALL", [33] = "EM_LEAD", [34] = "SKILL_STABBING_PL1", [35] = "SKILL_STABBING_PL2", [36] = "SKILL_STABBING_PL3",
    [37] = "SKILL_STABBING_PL4", [38] = "SKILL_RYUKI", [39] = "TRAP_FALL", [40] = "TRAP_PARALYSE", [41] = "TRAP_IVY",
    [42] = "TRAP_PARALYSE_ANIMAL", [43] = "TRAP_PARALYSE_OTOMO", [44] = "TRAP_BOUND_NPC", [45] = "SLINGER",
}
local KEY_TYPE = "app.TARGET_ACCESS_KEY"
local NULLABLE_KEY_TYPE = "System.Nullable`1<app.TARGET_ACCESS_KEY>"
local HUNTER_CATEGORIES = { [0] = true, [5] = true }

function GuestProbe.conditionName(value)
    local name = type(value) == "number" and CONDITION_NAMES[value] or nil
    return (name or "?") .. "(" .. tostring(value) .. ")"
end

function GuestProbe.activeProcKind()
    return procStack[#procStack]
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
    if ok then return GuestProbe.formatValue(name) end
    return "?"
end

local function bracketText()
    return tostring(GuestProbe.activeProcKind() or "none")
end

local function onProcEnter(kind)
    return function(args)
        if not Log.isDeveloperMode() then return end
        procStack[#procStack + 1] = kind
        local okThis, this = pcall(function() return sdk.to_managed_object(args[2]) end)
        if not okThis or not this then return unreadable("proc " .. kind, "this") end
        local okInvoker, invoker = pcall(function() return this._Invoker end)
        if kind == "poison" then
            if not okInvoker or invoker == nil then
                Log.debug("gp proc poison invoker unreadable", "gp:proc:poison:invoker")
                return
            end
            local okAddress, address = pcall(function() return this:get_address() end)
            if okAddress and address ~= nil then
                local key = tostring(address)
                if poisonLogged[key] then return end
                poisonLogged[key] = true
            end
        end
        local invokerText = okInvoker and invoker and keyText(invoker) or "?"
        local objectText = okInvoker and (invoker and keyObjectName(invoker) or "nil") or "?"
        trace("proc " .. kind .. " invoker=" .. invokerText .. " obj=" .. objectText)
    end
end

local function onProcLeave()
    if #procStack > 0 then procStack[#procStack] = nil end
end

local function onNetCond(args)
    if not Log.isDeveloperMode() then return end
    bump("netCond")
    local okPacket, packet = pcall(function() return sdk.to_managed_object(args[3]) end)
    if not okPacket or not packet then return unreadable("net cond", "packet") end
    trace("net cond attacker=" .. readValue(function() return packet.AttackerIndex end)
        .. " cond=" .. readValue(function() return packet.AttackCond end)
        .. " value=" .. readValue(function() return packet.CondValue end)
        .. " limit=" .. readValue(function() return packet.ActivateLimit end))
end

local function onExtCond(args)
    if not Log.isDeveloperMode() then return end
    bump("extCond")
    local okCond, condition = pcall(function() return sdk.to_int64(args[3]) end)
    local value = readValue(function() return sdk.to_float(args[4]) end)
    local okObject, object = pcall(function() return sdk.to_managed_object(args[7]) end)
    local objectName = "?"
    if okObject then
        objectName = object and readValue(function() return object:get_Name() end) or "nil"
    end
    trace("ext cond=" .. GuestProbe.conditionName(okCond and condition or nil)
        .. " value=" .. value
        .. " obj=" .. objectName .. " net=" .. tostring(netDepth > 0))
end

local function onReceiveCond(args)
    if not Log.isDeveloperMode() then return end
    bump("receiveCond")
    local okPacket, packet = pcall(function() return sdk.to_managed_object(args[3]) end)
    if not okPacket or not packet then return unreadable("receive cond", "packet") end
    if receiveCondLines >= RECEIVE_LINE_BUDGET then return end
    receiveCondLines = receiveCondLines + 1
    trace("receive cond attacker=" .. readValue(function() return packet.AttackerIndex end)
        .. " cond=" .. readValue(function() return packet.AttackCond end)
        .. " value=" .. readValue(function() return packet.CondValue end))
end

local function onExternal(args)
    if not Log.isDeveloperMode() then return end
    bump("external")
    local value = readValue(function() return sdk.to_float(args[3]) end)
    local okKey, nullable = pcall(function() return sdk.to_valuetype(args[5], NULLABLE_KEY_TYPE) end)
    if not okKey or not nullable then return unreadable("external", "key") end
    local hasKey = readValue(function() return nullable._HasValue end)
    local key = readValue(function() return nullable._Value.Category end) .. "/" .. readValue(function() return nullable._Value.UniqueIndex end)
    trace("external value=" .. value .. " hasKey=" .. hasKey .. " key=" .. key
        .. " bracket=" .. bracketText() .. " net=" .. tostring(netDepth > 0))
end

local function onSetParam(args)
    if not Log.isDeveloperMode() then return end
    bump("setParam")
    local value = readValue(function() return sdk.to_float(args[3]) end)
    local okKey, key = pcall(function() return sdk.to_valuetype(args[4], KEY_TYPE) end)
    if not okKey or not key then return unreadable("setParam", "key") end
    trace("setParam value=" .. value .. " key=" .. keyText(key) .. " bracket=" .. bracketText())
end

local function onGetter(name)
    return function(args)
        if not Log.isDeveloperMode() then return end
        local okThis, this = pcall(function() return sdk.to_managed_object(args[2]) end)
        if not okThis or not this then return unreadable("getter " .. name, "this") end
        local master = readValue(function()
            return this:get_address() == Game.masterHunter():get_HunterSkill():get_address()
        end)
        trace("getter " .. name .. " master=" .. master .. " bracket=" .. bracketText())
    end
end

local function installProcHooks()
    Game.hook("app.cEnemyStockDamage", "stockExternalBadConditionDamageNet(app.net_packet.cEmDamageExternalCondition)", onNetCond)
    Game.hook("app.cEnemyStockDamage",
        "stockExternalBadConditionDamage(app.EnemyDef.CONDITION, System.Single, app.cHorizontalUDDirection, System.Boolean, via.GameObject, System.Boolean)",
        onExtCond)
    Game.hook("app.EnemyCharacter", "receivePacket_DamageExternalCondition(app.net_packet.cEmDamageExternalCondition)", onReceiveCond)
    Game.hook("app.cEnemyStockDamage",
        "stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)",
        onExternal)
    Game.hook("app.cEnemyStockDamage.cBadConditionDamageInfo", "setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)", onSetParam)
    Game.hook("app.cEnemyBadConditionBlast", "onActivate", onProcEnter("blast"), onProcLeave)
    Game.hook("app.cEnemyBadConditionSkillStabbing", "onActivate", onProcEnter("flayer"), onProcLeave)
    Game.hook("app.cEnemyBadConditionSkillRyuki", "onActivate", onProcEnter("elementConvert"), onProcLeave)
    Game.hook("app.cEnemyBadConditionPoison", "onUpdateActive", onProcEnter("poison"), onProcLeave)
    Game.hook("app.cHunterSkill", "getSkillStabbingAddDamage(app.cEnemyContextHolder)", onGetter("stabbing"))
    Game.hook("app.cHunterSkill", "getSkillRyukiAddDamage(app.cEnemyContextHolder, System.Single, System.Single)", onGetter("ryuki"))
end

local function unresolvedOr(read)
    local ok, value = pcall(read)
    if ok and value ~= nil then return GuestProbe.formatValue(value) end
    return "unresolved"
end

local function logState()
    local director = nil
    pcall(function() director = Game.singleton("app.MissionManager"):get_QuestDirector() end)
    local playing = unresolvedOr(function() return Game.singleton("app.MissionManager"):get_IsPlayingQuest() end)
    local elapsed = unresolvedOr(function() return director:get_QuestElapsedTime() end)
    local hostStarted = unresolvedOr(function() return director["<Param>k__BackingField"].IsHostQuestStarted end)
    local lateJoinStarted = unresolvedOr(function() return director["<Param>k__BackingField"].IsLateJoinQuestStarted end)
    trace("state playing=" .. playing .. " elapsed=" .. elapsed .. " hostStarted=" .. hostStarted .. " lateJoinStarted=" .. lateJoinStarted)
    local masterName = unresolvedOr(function() return Game.masterHunter():get_GameObject():get_Name() end)
    trace("master name=" .. masterName)
end

local function onFlow(name)
    return function()
        if not Log.isDeveloperMode() then return end
        if name == "playing" then resetQuestState() end
        local ok, time = pcall(Game.callStatic, "via.Application", "get_UpTimeSecond")
        local timestamp = ok and type(time) == "number" and GuestProbe.formatValue(time) or "?"
        trace("flow " .. name .. " t=" .. timestamp)
        if name == "playing" or name == "result" then logState() end
        if name == "result" then trace(GuestProbe.summaryLine(counters)) end
    end
end

local function onResultInfoPre(args)
    if not Log.isDeveloperMode() then return end
    local storage = thread.get_hook_storage()
    storage[RESULT_KEY] = nil
    local ok, info = pcall(function() return sdk.to_managed_object(args[2]) end)
    if ok then storage[RESULT_KEY] = info end
end

local function onResultInfoPost()
    if not Log.isDeveloperMode() then return end
    local storage = thread.get_hook_storage()
    local info = storage[RESULT_KEY]
    storage[RESULT_KEY] = nil
    trace("result endType=" .. readValue(function() return info:get_QuestEndType() end)
        .. " failedType=" .. readValue(function() return info:get_QuestFailedType() end)
        .. " clearTimeMs=" .. readValue(function() return info:get_ClearTime() end)
        .. " joinMemberNum=" .. readValue(function() return info:get_JoinMemberNum() end)
        .. " lateJoin=" .. readValue(function() return info["<IsLateJoin>k__BackingField"] end)
        .. " questLevel=" .. readValue(function() return info:get_QuestLevel() end))
    trace(GuestProbe.summaryLine(counters))
end

function GuestProbe.update()
    if stateLogged or not Log.isDeveloperMode() then return end
    stateLogged = true
    logState()
end

local function installFlowHooks()
    Game.hook("app.cQuestPlaying", "enter()", onFlow("playing"))
    Game.hook("app.cQuestClear", "enter()", onFlow("clear"))
    Game.hook("app.cQuestFailed", "enter()", onFlow("failed"))
    Game.hook("app.cQuestResult", "enter()", onFlow("result"))
    Game.hook("app.cGUIQuestResultInfo", "execute()", onResultInfoPre, onResultInfoPost)
end

function GuestProbe.install()
    if installed then return end
    installed = true
    installFlowHooks()
    installHitHooks()
    installProcHooks()
end

return GuestProbe
