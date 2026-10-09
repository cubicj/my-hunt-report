local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local MotionNames = require("MyHuntReport.MotionNames")
local ShellTracker = require("MyHuntReport.ShellTracker")

local KinsectTracker = {}

local WEAPON_GLAIVE = 10
local SUMMARY_EVERY = 20
local INHERIT_FROM = { cAimAttackPre = true, cAimAttackAirPre = true, cPreDiveAttack = true, cHit = true, cWander = true }
local INHERIT_TO = { cHit = true, cWander = true }
local COUNTER_ORDER = {
    "hits", "trigger", "noRecord", "otherKinsect", "stale", "unknownTrigger", "unreadable",
    "inherit", "sub", "base", "last",
}

local record = nil
local knownBase = nil
local lastAttack = nil
local wasGlaive = false
local counters = {}

for _, name in ipairs(COUNTER_ORDER) do counters[name] = 0 end

local function readField(read)
    local ok, value = pcall(read)
    if ok then return value end
    return nil
end

local function show(value)
    if value == nil then return "?" end
    if math.type(value) == "float" then return string.format("%.2f", value) end
    return tostring(value)
end

local function actionText(className, guideId)
    return show(className) .. "/" .. show(guideId)
end

local function elapsed(now, start)
    if now == nil or start == nil then return "?" end
    return string.format("%.2f", now - start)
end

local function trace(text)
    Log.trace("kinsect " .. text)
end

local function clearTracking()
    record = nil
    knownBase = nil
    lastAttack = nil
    wasGlaive = false
end

function KinsectTracker.isAttackBase(className)
    if type(className) ~= "string" then return false end
    if ShellTracker.isNonAttackAction(className) then return false end
    return not (className:find("^cIdle") or className:find("^cMoveStop") or className:find("^cDown"))
end

function KinsectTracker.decide(previous, className, seen, hunter, last)
    if not seen then return nil, "unseen" end
    if INHERIT_FROM[previous.class] or INHERIT_TO[className] then return previous.trigger, "inherit" end
    if hunter.baseClass == nil or hunter.subClass == nil then return nil, "unreadable" end
    if hunter.subClass:find("^cInsect") then
        return { className = hunter.subClass, guideId = hunter.subGuide }, "sub"
    end
    if KinsectTracker.isAttackBase(hunter.baseClass) then
        return { className = hunter.baseClass, guideId = hunter.baseGuide }, "base"
    end
    if last then return { className = last.className, guideId = last.guideId }, "last" end
    return nil, "last"
end

local function kinsectClass(insect)
    local current = readField(function() return insect._ActionController:get_CurrentAction() end)
    if current == nil then return nil end
    return MotionNames.className(current)
end

local function readHunter(hunter)
    local baseClass, baseGuide = MotionNames.describe(ShellTracker.readControllerAction(hunter, "get_BaseActionController"))
    local subClass, subGuide = MotionNames.describe(ShellTracker.readControllerAction(hunter, "get_SubActionController"))
    return { baseClass = baseClass, baseGuide = baseGuide, subClass = subClass, subGuide = subGuide }
end

local function trackHunter(state)
    if state.baseClass == nil then return end
    local changed = knownBase == nil or knownBase.className ~= state.baseClass
        or (knownBase.guideId ~= -1 and state.baseGuide ~= -1 and knownBase.guideId ~= state.baseGuide)
    if not changed then return end
    local first = knownBase == nil
    knownBase = { className = state.baseClass, guideId = state.baseGuide }
    if not KinsectTracker.isAttackBase(state.baseClass) then return end
    lastAttack = { className = state.baseClass, guideId = state.baseGuide }
    if record and not first then record.spans = record.spans + 1 end
end

local function readKinsect(hunter)
    local insect = readField(function() return hunter:call("get_Wp10Insect") end)
    if insect == nil then insect = readField(function() return hunter:get_WeaponHandling():call("get_Insect") end) end
    if insect == nil then return nil, nil end
    return readField(function() return insect:get_address() end), kinsectClass(insect)
end

local function printSummary()
    if not Log.isDeveloperMode() then return end
    local parts = {}
    for _, name in ipairs(COUNTER_ORDER) do parts[#parts + 1] = name .. "=" .. counters[name] end
    trace("summary " .. table.concat(parts, " "))
end

local function closeUnreadable()
    if record == nil then return end
    if Log.isDeveloperMode() then
        local now = Game.uptime()
        trace(string.format("act t=%.2f from=%s to=? dur=%s spans=%d", now, record.class, elapsed(now, record.start), record.spans))
    end
    record = nil
end

function KinsectTracker.update()
    local hunter = Game.masterHunter()
    local weaponType = hunter and readField(function() return hunter:get_WeaponType() end) or nil
    if weaponType ~= WEAPON_GLAIVE then
        if wasGlaive then printSummary() end
        clearTracking()
        return
    end
    wasGlaive = true
    local state = readHunter(hunter)
    trackHunter(state)
    local address, className = readKinsect(hunter)
    if address == nil or className == nil then
        closeUnreadable()
        return
    end
    local seen = record ~= nil and record.insect == address
    if seen and record.class == className then return end
    local trigger, rule = KinsectTracker.decide(record, className, seen, state, lastAttack)
    local now = nil
    if Log.isDeveloperMode() then
        now = Game.uptime()
        trace(string.format("act t=%.2f from=%s to=%s dur=%s spans=%s base=%s sub=%s seen=%s rule=%s trigger=%s",
            now, show(record and record.class), className,
            elapsed(now, record and record.start), show(record and record.spans),
            actionText(state.baseClass, state.baseGuide), actionText(state.subClass, state.subGuide),
            tostring(seen), rule, actionText(trigger and trigger.className, trigger and trigger.guideId)))
    end
    record = { insect = address, class = className, trigger = trigger, rule = rule, start = now, spans = 0 }
end

local function traceHit(kact, reason)
    if not Log.isDeveloperMode() then return end
    local hunter = Game.masterHunter()
    local hitBase = hunter and MotionNames.describe(ShellTracker.readControllerAction(hunter, "get_BaseActionController")) or nil
    local now = Game.uptime()
    trace(string.format("hit t=%.2f kact=%s open=%s age=%s rule=%s trigger=%s hitBase=%s result=%s",
        now, show(kact), show(record and record.class),
        elapsed(now, record and record.start), show(record and record.rule),
        actionText(record and record.trigger and record.trigger.className, record and record.trigger and record.trigger.guideId),
        show(hitBase), reason and ("fallback:" .. reason) or "trigger"))
end

function KinsectTracker.triggerFor(attackObj)
    local insect = Game.componentOf(attackObj, "app.Wp10Insect")
    local address = insect and readField(function() return insect:get_address() end) or nil
    local kact = insect and kinsectClass(insect) or nil
    local reason = nil
    if record == nil then
        reason = "noRecord"
    elseif address == nil or kact == nil then
        reason = "unreadable"
    elseif address ~= record.insect then
        reason = "otherKinsect"
    elseif kact ~= record.class then
        reason = "stale"
    elseif record.trigger == nil then
        reason = "unknownTrigger"
    end
    counters.hits = counters.hits + 1
    if reason then
        counters[reason] = counters[reason] + 1
    else
        counters.trigger = counters.trigger + 1
        counters[record.rule] = counters[record.rule] + 1
    end
    traceHit(kact, reason)
    if counters.hits % SUMMARY_EVERY == 0 then printSummary() end
    if reason then return nil end
    return record.trigger.className, record.trigger.guideId
end

return KinsectTracker
