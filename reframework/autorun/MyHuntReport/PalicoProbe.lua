local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local PalicoProbe = {}

PalicoProbe.COUNTER_ORDER = { "hits", "blastLines", "poisonLines", "unresolved" }
PalicoProbe.IDENTITY_ORDER = {
    "name", "isMaster", "isMasterMyOtomo", "holderIsMaster", "ownerIsMaster", "ownerName",
    "npc", "partnerNpc", "ctxVia", "stableIndex", "masterOtomo",
}

local counters = {}
local palicos = {}
local order = {}
local installed = false

local function resetQuestState()
    for _, name in ipairs(PalicoProbe.COUNTER_ORDER) do counters[name] = 0 end
    palicos = {}
    order = {}
end

resetQuestState()

function PalicoProbe.formatValue(value)
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
    if ok then return PalicoProbe.formatValue(value) end
    return "?"
end

local function trace(text)
    Log.trace("pp " .. text)
end

local function bump(name)
    counters[name] = (counters[name] or 0) + 1
end

local function managedArg(args, index)
    local ok, object = pcall(function() return sdk.to_managed_object(args[index]) end)
    if ok then return object end
    return nil
end

local function timeText(now)
    return string.format("%.2f", now)
end

function PalicoProbe.identityText(identity)
    local parts = {}
    for _, name in ipairs(PalicoProbe.IDENTITY_ORDER) do
        local value = identity[name]
        if value == nil then value = "?" end
        parts[#parts + 1] = name .. "=" .. tostring(value)
    end
    return table.concat(parts, " ")
end

function PalicoProbe.summaryLine(entry)
    local identity = entry.identity or {}
    return string.format(
        "summary id=%s mine=%s ownerIsMaster=%s npc=%s detail=%d mark=%d damage=%.1f blast=%.1f blastCount=%d poison=%.1f poisonCount=%d",
        entry.id, identity.isMasterMyOtomo or "?", identity.ownerIsMaster or "?", identity.npc or "?",
        entry.detail, entry.mark, entry.damage, entry.blast, entry.blastCount, entry.poison, entry.poisonCount)
end

function PalicoProbe.summaryEndLine(palicoCount, values)
    local parts = { "palicos=" .. tostring(palicoCount) }
    for _, name in ipairs(PalicoProbe.COUNTER_ORDER) do
        parts[#parts + 1] = name .. "=" .. tostring(values[name] or 0)
    end
    return "summary-end " .. table.concat(parts, " ")
end

function PalicoProbe.counters()
    return counters
end

function PalicoProbe.reset()
    resetQuestState()
end

function PalicoProbe.entry(address)
    return palicos[address]
end

local function addressIsMaster(gameObject)
    local master = Game.masterAddress()
    local address = gameObject:get_address()
    if master == nil or address == nil then error("address unavailable") end
    return address == master
end

local function readContext(otomo)
    local ok, context = pcall(function() return otomo:get_OtomoContext() end)
    if ok and context ~= nil then return context, "get_OtomoContext" end
    ok, context = pcall(function() return otomo:get_ContextHolder():get_Otomo() end)
    if ok and context ~= nil then return context, "get_ContextHolder" end
    return nil, "?"
end

local function masterOtomoAddress()
    local manager = Game.singleton("app.OtomoManager")
    if not manager then error("no otomo manager") end
    local address = manager:getMasterOtomoInfo():get_Character():get_GameObject():get_address()
    if address == nil then error("no master otomo address") end
    return address
end

local function readIdentity(gameObject, otomo)
    local context, via = readContext(otomo)
    return {
        name = readValue(function() return gameObject:get_Name() end),
        isMaster = readValue(function() return otomo:get_IsMaster() end),
        isMasterMyOtomo = readValue(function() return otomo:get_IsMasterMyOtomo() end),
        holderIsMaster = readValue(function() return otomo:get_ContextHolder():get_IsMaster() end),
        ownerIsMaster = readValue(function()
            return addressIsMaster(otomo:get_OwnerHunterCharacter():get_GameObject())
        end),
        ownerName = readValue(function() return otomo:get_OwnerHunterCharacter():get_GameObject():get_Name() end),
        npc = readValue(function() return context:get_IsNPC() end),
        partnerNpc = readValue(function() return context:get_IsPartnerNpcOtomo() end),
        ctxVia = via,
        stableIndex = readValue(function() return otomo:get_StableQuestMemberIndex() end),
        masterOtomo = readValue(function() return gameObject:get_address() == masterOtomoAddress() end),
    }
end

local function ensureEntry(gameObject)
    local okAddress, address = pcall(function() return gameObject:get_address() end)
    if not okAddress or type(address) ~= "number" then return nil end
    local entry = palicos[address]
    if entry then return entry end
    entry = {
        id = readValue(function() return gameObject:get_Name() end) .. "@" .. string.format("%x", address),
        detail = 0, mark = 0, damage = 0, blast = 0, blastCount = 0, poison = 0, poisonCount = 0,
    }
    palicos[address] = entry
    order[#order + 1] = address
    return entry
end

local function refreshIdentity(entry, gameObject, otomo, now)
    local identity = readIdentity(gameObject, otomo)
    local text = PalicoProbe.identityText(identity)
    if entry.identityText == text then return end
    entry.identity, entry.identityText = identity, text
    trace("identity t=" .. timeText(now) .. " id=" .. entry.id .. " " .. text)
end

local function palicoOwner(hitInfo)
    local ok, owner = pcall(function() return hitInfo:getActualAttackOwner() end)
    if not ok or owner == nil then return nil, nil end
    local otomo = Game.componentOf(owner, "app.OtomoCharacter")
    if not otomo then return nil, nil end
    return owner, otomo
end

local function enemyIndexText(hitInfo)
    return readValue(function() return Game.enemyContext(hitInfo:get_DamageOwner()):get_UniqueIndex() end)
end

local function hostText()
    return readValue(function()
        return sdk.find_type_definition("app.OtomoUtil"):get_method("isMultiplayHost"):call(nil)
    end)
end

local function onQuestStart()
    resetQuestState()
    if not Log.isDeveloperMode() then return end
    trace("state host=" .. hostText())
end

local function onResultPost()
    if not Log.isDeveloperMode() then return end
    for _, address in ipairs(order) do
        trace(PalicoProbe.summaryLine(palicos[address]))
    end
    trace(PalicoProbe.summaryEndLine(#order, counters))
end

local function onStockDamageDetailPre(args)
    if not Log.isDeveloperMode() then return end
    local hitInfo = managedArg(args, 3)
    if not hitInfo then return end
    local owner = palicoOwner(hitInfo)
    if not owner then return end
    local entry = ensureEntry(owner)
    if entry then entry.detail = entry.detail + 1 end
end

local function onHitMarkPre(args)
    if not Log.isDeveloperMode() then return end
    local hitInfo = managedArg(args, 4)
    if not hitInfo then return end
    local owner, otomo = palicoOwner(hitInfo)
    if not owner then return end
    local entry = ensureEntry(owner)
    if not entry then return end
    local now = Game.uptime()
    refreshIdentity(entry, owner, otomo, now)
    local calc = managedArg(args, 3)
    local okFinal, final = pcall(function() return calc.FinalDamage end)
    if not okFinal then final = nil end
    entry.mark = entry.mark + 1
    if type(final) == "number" and final > 0 then entry.damage = entry.damage + final end
    bump("hits")
    trace("hit t=" .. timeText(now) .. " em=" .. enemyIndexText(hitInfo) .. " id=" .. entry.id
        .. " final=" .. (okFinal and PalicoProbe.formatValue(final) or "?")
        .. " obj=" .. readValue(function() return hitInfo:get_AttackObj():get_Name() end)
        .. " data=" .. readValue(function() return hitInfo:get_AttackData():get_type_definition():get_full_name() end)
        .. " mine=" .. tostring(entry.identity.isMasterMyOtomo))
end

local function installFlowHooks()
    Game.hook("app.cQuestPlaying", "enter()", onQuestStart)
    Game.hook("app.cGUIQuestResultInfo", "execute()", nil, onResultPost)
end

local function installHitHooks()
    Game.hook("app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)", onStockDamageDetailPre)
    Game.hook("app.cEnemyStockDamage.mcEnemyHitMarkManager",
        "playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
        onHitMarkPre)
end

function PalicoProbe.install()
    if installed then return end
    installed = true
    installFlowHooks()
    installHitHooks()
end

return PalicoProbe
