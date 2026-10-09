local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local MotionNames = require("MyHuntReport.MotionNames")
local ShellTracker = require("MyHuntReport.ShellTracker")

local KinsectProbe = {}

local WEAPON_GLAIVE = 10
local SUMMARY_EVERY = 20
local COUNTER_ORDER = { "hits", "noRecord", "unseenStart", "mismatchedOpen", "startNonAttack", "differ", "spanned" }
local GETTERS = {
    { name = "main", label = "HunterCharacter.get_Wp10Insect",
        read = function(hunter) return hunter:call("get_Wp10Insect") end },
    { name = "reserve", label = "HunterCharacter.get_ReserveWp10Insect",
        read = function(hunter) return hunter:call("get_ReserveWp10Insect") end },
    { name = "handling", label = "cHunterWp10Handling.get_Insect",
        read = function(hunter) return hunter:get_WeaponHandling():call("get_Insect") end },
}

local instances = {}
local hunterAction = nil
local knownHunter = nil
local lastAttack = nil
local record = nil
local wasGlaive = false
local counters = {}
local classCounts = {}
local classOrder = {}
local installed = false

for _, name in ipairs(COUNTER_ORDER) do counters[name] = 0 end

local function clearTracking()
    instances = {}
    hunterAction = nil
    knownHunter = nil
    lastAttack = nil
    record = nil
    wasGlaive = false
end

function KinsectProbe.formatValue(value)
    if value == nil then return "?" end
    if math.type(value) == "float" then return string.format("%.2f", value) end
    return tostring(value)
end

function KinsectProbe.formatAddress(address)
    if address == nil then return "nil" end
    if math.type(address) == "integer" then return string.format("0x%X", address) end
    return "?"
end

function KinsectProbe.isAttack(className)
    return type(className) == "string" and not ShellTracker.isNonAttackAction(className)
end

function KinsectProbe.attackState(className)
    if type(className) ~= "string" then return nil end
    return KinsectProbe.isAttack(className)
end

function KinsectProbe.ruleS(current, last)
    if current == nil or current.startAttack == nil then return nil end
    if current.startAttack then return current.startClass end
    return last and last.class or nil
end

function KinsectProbe.ruleH(hitClass, last)
    if type(hitClass) ~= "string" then return nil end
    if KinsectProbe.isAttack(hitClass) then return hitClass end
    return last and last.class or nil
end

local function trace(text)
    Log.trace("kp " .. text)
end

local function show(value)
    return KinsectProbe.formatValue(value)
end

local function actionText(className, guideId)
    return show(className) .. "/" .. show(guideId)
end

local function seconds(value)
    if value == nil then return "?" end
    return string.format("%.2f", value)
end

local function controllerAction(owner, getter)
    local ok, current = pcall(function()
        local controller = owner:call(getter)
        return controller and controller:get_CurrentAction()
    end)
    if ok then return current end
    return nil
end

local function describeAction(current)
    local className = MotionNames.className(current)
    if className == nil then return nil, nil end
    local ok, guideId = pcall(function() return current._ActionGuideID end)
    if ok and type(guideId) == "number" then return className, guideId end
    return className, nil
end

local function sameAction(previous, className, guideId)
    if previous == nil or previous.class ~= className then return false end
    return previous.guide == nil or guideId == nil or previous.guide == guideId
end

local function kinsectClass(insect)
    if insect == nil then return nil end
    local ok, current = pcall(function() return insect._ActionController:get_CurrentAction() end)
    if not ok or current == nil then return nil end
    return MotionNames.className(current)
end

local function readField(read)
    local ok, value = pcall(read)
    if ok then return value end
    return nil
end

local function printSummary()
    local parts = {}
    for _, name in ipairs(COUNTER_ORDER) do parts[#parts + 1] = name .. "=" .. counters[name] end
    trace("summary " .. table.concat(parts, " "))
    for _, className in ipairs(classOrder) do
        local entry = classCounts[className]
        trace(string.format("summary-class %s hits=%d differ=%d spanned=%d",
            className, entry.hits, entry.differ, entry.spanned))
    end
end

local function updateInstances(hunter, now)
    for _, getter in ipairs(GETTERS) do
        local ok, object = pcall(getter.read, hunter)
        local entry = { object = nil, address = nil, text = "?" }
        if ok and object == nil then
            entry.text = "nil"
        elseif ok then
            entry.object = object
            local okAddress, address = pcall(function() return object:get_address() end)
            if okAddress then
                entry.address = address
                entry.text = KinsectProbe.formatAddress(address)
            end
        end
        local previous = instances[getter.name]
        if previous == nil or previous.text ~= entry.text then
            trace(string.format("instance t=%.2f via=%s addr=%s", now, getter.label, entry.text))
        end
        instances[getter.name] = entry
    end
end

local function updateHunter(hunter, now)
    local className, guideId = describeAction(controllerAction(hunter, "get_BaseActionController"))
    local subClass = MotionNames.className(controllerAction(hunter, "get_SubActionController"))
    local wasUnknown = hunterAction ~= nil and hunterAction.class == nil
    hunterAction = { class = className, guide = guideId, sub = subClass }
    local attack = KinsectProbe.attackState(className)
    local function line(suffix)
        trace(string.format("hunter t=%.2f base=%s sub=%s attack=%s%s",
            now, actionText(className, guideId), show(subClass), show(attack), suffix))
    end
    if className == nil then
        if not wasUnknown then line("") end
        return
    end
    if sameAction(knownHunter, className, guideId) then
        if guideId ~= nil then knownHunter.guide = guideId end
        if wasUnknown then line(" recovered=same") end
        return
    end
    local first = knownHunter == nil
    knownHunter = { class = className, guide = guideId }
    if wasUnknown then
        line(first and " recovered=first" or " recovered=changed")
    else
        line("")
    end
    if attack then
        lastAttack = { class = className, guide = guideId }
        if record and not first then record.spans = record.spans + 1 end
    end
end

local function activeInsect()
    for _, name in ipairs({ "main", "handling" }) do
        local entry = instances[name]
        if entry and entry.object ~= nil then
            for _, getter in ipairs(GETTERS) do
                if getter.name == name then return entry.object, getter.label end
            end
        end
    end
    return nil, nil
end

local function updateKinsect(now)
    local insect, via = activeInsect()
    local className = kinsectClass(insect)
    local address = insect and readField(function() return insect:get_address() end) or nil
    if className == nil or address == nil then
        if record ~= nil then
            trace(string.format("kact t=%.2f via=%s from=%s to=? dur=%s spans=%s",
                now, show(via), record.class, seconds(now - record.start), show(record.spans)))
            record = nil
        end
        return
    end
    local seen = record ~= nil and record.insect == address
    if seen and record.class == className then return end
    local actType = show(readField(function() return insect._ActType end))
    local start = seen and hunterAction or {}
    local startAttack = KinsectProbe.attackState(start.class)
    trace(string.format("kact t=%.2f via=%s from=%s to=%s dur=%s spans=%s actType=%s start=%s sub=%s attack=%s last=%s seen=%s",
        now, via, show(record and record.class), className,
        seconds(record and (now - record.start)), show(record and record.spans), actType,
        actionText(start.class, start.guide), show(start.sub), show(startAttack),
        actionText(lastAttack and lastAttack.class, lastAttack and lastAttack.guide), tostring(seen)))
    record = {
        class = className, insect = address, seen = seen, start = now, startClass = start.class,
        startGuide = start.guide, startSub = start.sub, startAttack = startAttack, spans = 0,
    }
end

function KinsectProbe.update()
    if not Log.isDeveloperMode() then
        clearTracking()
        return
    end
    local hunter = Game.masterHunter()
    local okType, weaponType = false, nil
    if hunter then okType, weaponType = pcall(function() return hunter:get_WeaponType() end) end
    if not okType or weaponType ~= WEAPON_GLAIVE then
        if wasGlaive then printSummary() end
        clearTracking()
        return
    end
    wasGlaive = true
    local now = Game.uptime()
    updateInstances(hunter, now)
    updateHunter(hunter, now)
    updateKinsect(now)
end

local function countHit(open, kact, differ)
    counters.hits = counters.hits + 1
    if open == nil then counters.noRecord = counters.noRecord + 1 end
    if open and not open.seen then counters.unseenStart = counters.unseenStart + 1 end
    if open and kact ~= nil and kact ~= open.class then counters.mismatchedOpen = counters.mismatchedOpen + 1 end
    if open and open.startAttack == false then counters.startNonAttack = counters.startNonAttack + 1 end
    if differ then counters.differ = counters.differ + 1 end
    local spanned = open ~= nil and open.spans > 0
    if spanned then counters.spanned = counters.spanned + 1 end
    local key = kact or "?"
    local entry = classCounts[key]
    if not entry then
        entry = { hits = 0, differ = 0, spanned = 0 }
        classCounts[key] = entry
        classOrder[#classOrder + 1] = key
    end
    entry.hits = entry.hits + 1
    if differ then entry.differ = entry.differ + 1 end
    if spanned then entry.spanned = entry.spanned + 1 end
end

local function equalText(address)
    if address == nil then return "?" end
    local equal, unknown = {}, false
    for _, getter in ipairs(GETTERS) do
        local entry = instances[getter.name]
        if entry == nil or entry.text == "?" then
            unknown = true
        elseif entry.address == address then
            equal[#equal + 1] = getter.name
        end
    end
    if #equal > 0 then return table.concat(equal, ",") end
    if unknown then return "?" end
    return "none"
end

function KinsectProbe.handleHit(insect, hitInfo)
    local now = Game.uptime()
    local kact = kinsectClass(insect)
    local objectName = readField(function() return hitInfo:get_AttackObj():get_Name() end)
    local enemyIndex = readField(function() return Game.enemyContext(hitInfo:get_DamageOwner()):get_UniqueIndex() end)
    local motionValue = readField(function() return hitInfo:get_AttackData()._OriginalAttackAdjust end)
    local address = readField(function() return insect:get_address() end)
    local hitClass, hitGuide, hitSub = nil, nil, nil
    local hunter = Game.masterHunter()
    if hunter then
        hitClass, hitGuide = describeAction(controllerAction(hunter, "get_BaseActionController"))
        hitSub = MotionNames.className(controllerAction(hunter, "get_SubActionController"))
    end
    local open = record
    if open and (address == nil or open.insect ~= address) then open = nil end
    local ruleS = KinsectProbe.ruleS(open, lastAttack)
    local ruleH = KinsectProbe.ruleH(hitClass, lastAttack)
    local same = nil
    if ruleS ~= nil and ruleH ~= nil then same = ruleS == ruleH end
    trace(string.format(
        "hit t=%.2f em=%s obj=%s mv=%s kact=%s open=%s age=%s eq=%s start=%s startAttack=%s spans=%s seen=%s hit=%s sub=%s last=%s S=%s H=%s same=%s",
        now, show(enemyIndex), show(objectName), show(motionValue), show(kact), show(open and open.class),
        seconds(open and (now - open.start)), equalText(address),
        actionText(open and open.startClass, open and open.startGuide),
        show(open and open.startAttack), show(open and open.spans), show(open and open.seen),
        actionText(hitClass, hitGuide), show(hitSub),
        actionText(lastAttack and lastAttack.class, lastAttack and lastAttack.guide),
        show(ruleS), show(ruleH), show(same)))
    countHit(open, kact, same == false)
    if counters.hits % SUMMARY_EVERY == 0 then printSummary() end
end

local function onAttackPostProcess(args)
    if not Log.isDeveloperMode() then return end
    local hitInfo = sdk.to_managed_object(args[3])
    if hitInfo == nil then return end
    local okOwner, owner = pcall(function() return hitInfo:getActualAttackOwner() end)
    if not okOwner or not Game.isMasterGameObject(owner) then return end
    KinsectProbe.handleHit(sdk.to_managed_object(args[2]), hitInfo)
end

function KinsectProbe.install()
    if installed then return end
    installed = true
    Game.hook("app.Wp10Insect", "evAttackPostProcess(app.HitInfo)", onAttackPostProcess)
end

return KinsectProbe
