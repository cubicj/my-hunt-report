local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")
local SkillState = require("MyHuntReport.SkillState")
local ShellTracker = require("MyHuntReport.ShellTracker")
local KinsectTracker = require("MyHuntReport.KinsectTracker")
local SkillExtras = require("MyHuntReport.SkillExtras")
local MotionNames = require("MyHuntReport.MotionNames")
local Names = require("MyHuntReport.Names")
local Sources = require("MyHuntReport.Sources")

local HitCapture = {}

local KINSECT_WEAPON_TYPE = -1
local GLAIVE_WEAPON_TYPE = 10
local KINSECT_KEY = "kinsect"
local HIDE_FIXED_THRESHOLD = 1.1
local ELEMENT_FIELDS = { [1] = "_Fire", [2] = "_Water", [3] = "_Thunder", [4] = "_Ice", [5] = "_Dragon" }
local SPECIAL_KINDS = { [11] = "darkWave", [12] = "mirrorBlade" }
local ADDITIONAL_KINDS = { [155] = "violent", [157] = "flare", [214] = "fury" }
local CRIMSON_GUIDE_IDS = { [-1997082496] = 1927826048, [1472591744] = 850992256, [-1065507968] = -1171603968 }

local pending = {}
local lastWeaponType = nil
local installed = false

function HitCapture.weightFor(motionValue, actionType, hitzone)
    local mv = tonumber(motionValue) or 0
    if actionType == 0 then return mv, false end
    if type(hitzone) == "number" then return mv * hitzone / 100, false end
    return mv, true
end

function HitCapture.isFixed(actionType, hideRate)
    if actionType == 0 then return true end
    return type(hideRate) == "number" and hideRate > HIDE_FIXED_THRESHOLD
end

function HitCapture.elementHitzone(hitzones, attribute)
    if type(hitzones) ~= "table" then return nil end
    local value = hitzones[attribute]
    if type(value) == "number" and value > 0 then return value end
    return nil
end

function HitCapture.elementHitzoneValue(hitzones, attribute)
    if type(hitzones) ~= "table" then return nil end
    local value = hitzones[attribute]
    if type(value) == "number" then return value end
    return nil
end

function HitCapture.motionKey(weaponType, name)
    return tostring(weaponType) .. ":" .. tostring(name)
end

function HitCapture.reset()
    pending = {}
    lastWeaponType = nil
end

function HitCapture.pendingCount()
    local count = 0
    for _ in pairs(pending) do count = count + 1 end
    return count
end

function HitCapture.lastWeaponType()
    return lastWeaponType
end

local function sampleActionControllers(audit)
    if not Log.isDeveloperMode() then return end
    local hunter = Game.masterHunter()
    local function describeAction(getter)
        local ok, action = pcall(function()
            local controller = hunter:call(getter)
            return controller and controller:get_CurrentAction()
        end)
        if ok then return MotionNames.describe(action) end
        return nil, nil
    end
    audit.baseClass, audit.baseGuideId = describeAction("get_BaseActionController")
    audit.subClass = describeAction("get_SubActionController")
end

local function isKinsectObject(name)
    if type(name) == "string" then return name:sub(1, 6) == "it1003" end
    return lastWeaponType == 10
end

local function crimsonGuideIdFor(weaponType, guideId)
    local crimsonGuideId = weaponType == 3 and CRIMSON_GUIDE_IDS[guideId]
    if not crimsonGuideId then return nil end
    local okAura, auraLevel = pcall(function()
        local hunter = Game.masterHunter()
        local handling = hunter and hunter:get_WeaponHandling()
        return handling and handling["<AuraLevel>k__BackingField"]
    end)
    if okAura and auraLevel == 4 then return crimsonGuideId end
    return nil
end

local function kinsectMotion(attackObj, audit)
    audit.path = "kinsect"
    local triggerClass, triggerGuideId = KinsectTracker.triggerFor(attackObj)
    if triggerClass then
        return HitCapture.motionKey(GLAIVE_WEAPON_TYPE, triggerClass),
            { kind = "motion", className = triggerClass, guideId = triggerGuideId }
    end
    return KINSECT_KEY, { kind = "kinsect" }
end

local function actionMotion(attackObj, name, weaponType, hitTime, audit)
    if weaponType == KINSECT_WEAPON_TYPE and type(name) == "string" and isKinsectObject(name) then
        return kinsectMotion(attackObj, audit)
    end
    local className, guideId, source, kind = ShellTracker.currentAction(Game.masterHunter(), hitTime)
    if kind == "slinger" then
        audit.path = "slinger"
        return "slinger", { kind = "slinger" }
    end
    if weaponType == KINSECT_WEAPON_TYPE then
        if isKinsectObject(name) then return kinsectMotion(attackObj, audit) end
        if Log.count("hit:wp-1:" .. tostring(name)) == 0 then
            Log.debug("hit weaponType=-1 object=" .. tostring(name), "hit:wp-1:" .. tostring(name))
        end
        audit.path = "weapon-1"
    elseif source == "lastAttack" or source == "nonattack" then
        audit.path = source
    else
        audit.path = "action"
    end
    local key = className or "unknown"
    local label = { kind = "motion", className = key, guideId = guideId or -1 }
    local crimsonGuideId = crimsonGuideIdFor(weaponType, guideId)
    if crimsonGuideId then
        label.guideId = crimsonGuideId
        key = key .. ":crimson"
    end
    return HitCapture.motionKey(weaponType, key), label
end

local function motionFor(hitInfo, weaponType)
    local key, label, hitTime, rootHash = nil, nil, nil, nil
    local okObj, attackObj = pcall(function() return hitInfo:get_AttackObj() end)
    if okObj and attackObj then key, label, hitTime, rootHash = ShellTracker.nameForAttackObject(attackObj) end
    local okName, name = pcall(function() return attackObj:get_Name() end)
    if not okName then name = nil end
    local audit = {
        objectName = type(name) == "string" and name or nil,
        shell = key ~= nil or hitTime == true,
        rootHash = rootHash,
    }
    sampleActionControllers(audit)
    if key then
        if label.kind == "slinger" then
            audit.path = "slinger"
            return "slinger", label, audit
        end
        audit.path = "shell:" .. key
        return HitCapture.motionKey(label.weaponType or weaponType, key), label, audit
    end
    if type(name) == "string" and (name == "Tip" or name:find("^SlingerShell")) then
        audit.path = "slinger"
        return "slinger", { kind = "slinger" }, audit
    end
    local motionKey, motionLabel = actionMotion(okObj and attackObj or nil, name, weaponType, hitTime, audit)
    return motionKey, motionLabel, audit
end

function HitCapture.handleStockDamageDetail(hitInfo)
    if not hitInfo then return end
    local okData, attackData = pcall(function() return hitInfo:get_AttackData() end)
    if not okData or not attackData then return end
    local okOwner, owner = pcall(function() return hitInfo:getActualAttackOwner() end)
    if not okOwner or not Game.isMasterGameObject(owner) then return end
    local okTarget, target = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okTarget then return end
    local em = Game.enemyContext(target)
    if not em then return end
    local okBoss, isBoss = pcall(function() return em:get_IsBoss() end)
    if not okBoss or isBoss ~= true then return end
    if Game.enemyIsDead(target) then
        Log.debug("hit on dead enemy dropped", "hit:dead")
        return
    end
    local okFields, motionValue, actionType, weaponType, uniqueIndex, hitAddress, useAdd, emId, hien = pcall(function()
        return attackData._OriginalAttackAdjust, attackData._ActionType, attackData._WeaponType,
            em:get_UniqueIndex(), hitInfo:get_address(), attackData._UseSkillAdditionalDamage == true, em:get_EmID(), attackData._IsSkillHien == true
    end)
    if not okFields or not hitAddress then return end
    local okVariant, roleId, legendaryId = pcall(function()
        return em:get_RoleID(), em:get_LegendaryID()
    end)
    if not okVariant then roleId, legendaryId = 0, 0 end
    if type(weaponType) == "number" and weaponType ~= KINSECT_WEAPON_TYPE then
        if lastWeaponType ~= nil and weaponType ~= lastWeaponType then
            local ok, err = pcall(function() SkillState.refreshEquipped() end)
            if not ok then Log.error("equipped skill refresh failed: " .. tostring(err), "hit:equipped") end
        end
        lastWeaponType = weaponType
    end
    local motionKey, motionLabel, audit = motionFor(hitInfo, weaponType)
    audit.weaponType = weaponType
    local source = Sources.classify(audit)
    local okIndex, attackIndex = pcall(function() return hitInfo:get_AttackIndex() end)
    if not okIndex then attackIndex = nil end
    local okResource, resource = pcall(function() return attackIndex._Resource end)
    local okAttackIndex, index = pcall(function() return attackIndex._Index end)
    if pending[uniqueIndex] then Session.noteDroppedPending() end
    pending[uniqueIndex] = {
        hitAddress = hitAddress,
        monsterId = uniqueIndex,
        monsterLabel = { kind = "monster", emId = emId, roleId = roleId, legendaryId = legendaryId },
        motionValue = motionValue,
        actionType = actionType,
        weaponType = weaponType,
        motionKey = motionKey,
        motionLabel = motionLabel,
        path = audit.path,
        source = source,
        rootHash = audit.rootHash,
        shell = audit.shell,
        attackResource = okResource and resource or nil,
        attackIndex = okAttackIndex and index or nil,
        objectName = audit.objectName,
        baseClass = audit.baseClass,
        baseGuideId = audit.baseGuideId,
        subClass = audit.subClass,
        hien = hien,
        wounded = false,
        hitzone = nil,
        fixed = actionType == 0,
        baseHitzone = nil,
        attackPower = nil,
        attribute = 0,
        elementHitzones = nil,
        skillExtras = useAdd and SkillExtras.take() or {},
    }
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

local function readBaseMeat(em, preCalc, actionType)
    local ok, base = pcall(function()
        local parts = em.Parts
        local paramParts = parts._ParamParts
        local partsIndex = preCalc.Common.PartsIndex
        local slot = parts._DmgParts[partsIndex]:get_MeatSlot()
        local guid = paramParts._PartsArray._DataArray[partsIndex]:getPartsMeatGuid(slot)
        local index = paramParts:getMeatIndex(guid)._Value
        local meat = paramParts._MeatArray._DataArray[index]
        if not meat then return nil end
        local elements = {}
        for attribute, field in pairs(ELEMENT_FIELDS) do elements[attribute] = meat[field] end
        local physical = nil
        if actionType ~= 0 then physical = meat:getActionMeat(actionType) end
        return { physical = physical, elements = elements }
    end)
    if ok then return base end
    return nil
end

function HitCapture.handleCalcStockDamage(this, preCalc, damageRate)
    if not this or not preCalc then return end
    local okEm, em, key = pcall(function()
        local context = this:get_Context():get_Em()
        return context, context:get_UniqueIndex()
    end)
    if not okEm or key == nil then return end
    local hit = pending[key]
    if not hit then return end
    local okAttack, attack, fixAttack, attrValue = pcall(function()
        return preCalc.Attack, preCalc.FixAttack, preCalc.AttrValue
    end)
    if okAttack and (tonumber(attack) or 0) <= 0 and (tonumber(fixAttack) or 0) <= 0 and (tonumber(attrValue) or 0) <= 0 then
        pending[key] = nil
        return
    end
    local actionType = hit.actionType
    local okType, preType = pcall(function() return preCalc.ActionType end)
    if okType and type(preType) == "number" then actionType = preType end
    local okHide, hideRate = pcall(function() return damageRate.Hide end)
    hit.fixed = HitCapture.isFixed(actionType, okHide and hideRate or nil)
    local okAttr, attackAttr = pcall(function() return preCalc.AttackAttr end)
    hit.attribute = okAttr and tonumber(attackAttr) or 0
    local okPower, power = pcall(function()
        return Game.masterHunter():get_HunterStatus():get_AttackPower():call("get_CurrentAttackPower()")
    end)
    if okPower and type(power) == "number" then
        hit.attackPower = power
    else
        Log.debug("attack power read failed: " .. tostring(power), "hit:attack")
    end
    local ok, hitzone = pcall(function()
        if actionType == 0 then return nil end
        local meatIndex = preCalc.Common.MeatIndex._Value
        local meat = em.Parts._ParamParts._MeatArray._DataArray[meatIndex]
        if not meat then return nil end
        return meat:getActionMeat(actionType)
    end)
    if ok and type(hitzone) == "number" then hit.hitzone = hitzone end
    local okWounded, wounded = pcall(function()
        local scarIndex = preCalc.Common.ScarIndex
        return scarIndex ~= -1 and em.Scar._ScarParts:Get(scarIndex):get_State() == 2
    end)
    hit.wounded = okWounded and wounded == true
    if not okWounded then Log.debug("wound read failed: " .. tostring(wounded), "hit:wound") end
    local base = readBaseMeat(em, preCalc, actionType)
    if base then
        if type(base.physical) == "number" then hit.baseHitzone = base.physical end
        hit.elementHitzones = base.elements
    end
end

function HitCapture.readAttackStats(attackData, elementHitzones, finalDamage)
    local stats = { canCrit = true, critType = 0, specialType = nil, useAdd = false, extras = {} }
    if not attackData then return stats end
    local totals = {}
    local function add(kind, damage)
        totals[kind] = (totals[kind] or 0) + damage
    end
    local okCrit, critType, noCrit, specialType, useAdd = pcall(function()
        return attackData._CriticaType, attackData._IsNoCritical, attackData._SpecialType, attackData._UseSkillAdditionalDamage
    end)
    if okCrit then
        if type(critType) == "number" then stats.critType = critType end
        stats.canCrit = noCrit ~= true
        stats.specialType = specialType
        stats.useAdd = useAdd == true
    end
    local specialKind = SPECIAL_KINDS[stats.specialType]
    if type(stats.specialType) == "number" and stats.specialType > 0 and specialKind == nil and stats.specialType ~= 6 then
        Log.debug("special type " .. tostring(stats.specialType) .. " kind=" .. tostring(specialKind) .. " dmg=" .. tostring(finalDamage),
            "special:" .. tostring(stats.specialType))
    end
    if specialKind and (tonumber(finalDamage) or 0) > 0 then add(specialKind, finalDamage) end
    if stats.useAdd then
        local okArray, entries = pcall(function()
            local array = attackData._SkillAdditinalDamageArray._Array
            local list = {}
            local count = array:get_Count()
            for i = 0, count - 1 do
                local entry = array[i]
                if entry then list[#list + 1] = { skill = entry._SkillType, damage = entry._Damage, attr = entry._Attr } end
            end
            return list
        end)
        if okArray and entries then
            for _, entry in ipairs(entries) do
                local kind = ADDITIONAL_KINDS[entry.skill]
                local damage = tonumber(entry.damage) or 0
                if kind == nil and (tonumber(entry.skill) or 0) > 0 and damage > 0 then
                    Log.debug("unmapped skill additional damage sid=" .. tostring(entry.skill) .. " dmg=" .. tostring(entry.damage)
                        .. " attr=" .. tostring(entry.attr), "extra:unmapped:" .. tostring(entry.skill))
                end
                if kind and damage > 0 then
                    local hitzone = HitCapture.elementHitzoneValue(elementHitzones, entry.attr)
                    if type(hitzone) == "number" then damage = damage * hitzone / 100 end
                    if damage > 0 then add(kind, damage) end
                end
            end
        end
    end
    for kind, damage in pairs(totals) do
        stats.extras[#stats.extras + 1] = { kind = kind, damage = damage }
    end
    table.sort(stats.extras, function(a, b) return a.kind < b.kind end)
    return stats
end

local function mergedExtras(hit, physical, stats)
    local extras = {}
    for _, extra in ipairs(hit.skillExtras) do
        if extra.damage < physical then
            extras[#extras + 1] = extra
        else
            Log.debug("skill extra dropped " .. tostring(extra.kind) .. " value=" .. tostring(extra.damage) .. " physical=" .. tostring(physical),
                "extra:dropped:" .. tostring(extra.kind))
        end
    end
    for _, extra in ipairs(stats.extras) do extras[#extras + 1] = extra end
    return extras
end

local function traceHit(hit, finalDamage, physical, element)
    if not Log.isDeveloperMode() then return end
    local name = Names.resolve(hit.motionLabel)
    local source = "guide"
    if hit.motionLabel.kind == "motion" then
        local _, nameSource = MotionNames.nameFor(hit.motionLabel.className, hit.motionLabel.guideId)
        source = nameSource
    end
    Log.trace(string.format("hit #%d dmg=%s(%s/%s) wp=%s act=%s mv=%s obj=%s base=%s/%s sub=%s row=%s via=%s name=%s mon=%s src=%s root=%s key=%s:%s:%s atk=%s",
        Session.hitCount() + 1, tostring(finalDamage), tostring(physical), tostring(element),
        tostring(hit.weaponType), tostring(hit.actionType), tostring(hit.motionValue), hit.objectName or "-",
        hit.baseClass or "-", tostring(hit.baseGuideId or -1), hit.subClass or "-", name,
        hit.path, source, tostring(hit.monsterLabel.emId), hit.source or "-",
        tostring(hit.rootHash or (hit.shell and "?" or "-")), tostring(hit.weaponType or "?"),
        tostring(hit.attackResource or "?"), tostring(hit.attackIndex or "?"), tostring(hit.attackPower)))
end

function HitCapture.handlePlayHitMarkEffect(calc, hitInfo)
    local okTarget, target = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okTarget then return end
    local em = Game.enemyContext(target)
    if not em then return end
    local okKey, key = pcall(function() return em:get_UniqueIndex() end)
    if not okKey or key == nil then return end
    local hit = pending[key]
    if not hit then return end
    pending[key] = nil
    local okAddress, hitAddress = pcall(function() return hitInfo:get_address() end)
    if not okAddress or hitAddress ~= hit.hitAddress then
        Session.noteDroppedPending()
        return
    end
    local okData, attackData = pcall(function() return hitInfo:get_AttackData() end)
    local ok, finalDamage, physical, element = pcall(function()
        return calc.FinalDamage, calc.Physical, calc.Element
    end)
    if not ok or type(finalDamage) ~= "number" or finalDamage <= 0 then return end
    physical = physical or 0
    element = element or 0
    local weight, fallback = HitCapture.weightFor(hit.motionValue, hit.actionType, hit.hitzone)
    if fallback then Session.noteWeightFallback() end
    local stats = HitCapture.readAttackStats(okData and attackData or nil, hit.elementHitzones, finalDamage)
    local extras = mergedExtras(hit, physical, stats)
    local activeSkills, eligibleSkills = SkillState.activeSet({
        rawHitzone = hit.baseHitzone,
        wounded = hit.wounded,
        hien = hit.hien,
        shell = type(hit.path) == "string" and hit.path:sub(1, 6) == "shell:",
        kinsect = hit.path == "kinsect",
        weaponType = hit.weaponType,
    })
    traceHit(hit, finalDamage, physical, element)
    Session.addHit({
        attribution = hit.path,
        source = hit.source,
        monsterId = hit.monsterId,
        monsterLabel = hit.monsterLabel,
        weaponType = hit.weaponType,
        finalDamage = finalDamage,
        physical = physical,
        element = element,
        weight = weight,
        hitzone = hit.hitzone,
        motionKey = hit.motionKey,
        motionLabel = hit.motionLabel,
        activeSkills = activeSkills,
        eligibleSkills = eligibleSkills,
        time = Game.uptime(),
        fixed = hit.fixed,
        canCrit = stats.canCrit,
        critType = stats.critType,
        specialType = stats.specialType,
        baseHitzone = hit.baseHitzone,
        attackPower = hit.attackPower,
        attribute = hit.attribute,
        attributeHitzone = HitCapture.elementHitzone(hit.elementHitzones, hit.attribute),
        skillExtras = extras,
    })
end

local function captureHitInfo(args)
    HitCapture.handleStockDamageDetail(sdk.to_managed_object(args[3]))
end

local function attachDamageCalc(args)
    if next(pending) == nil then return end
    HitCapture.handleCalcStockDamage(sdk.to_managed_object(args[2]), derefObject(args[4]), derefObject(args[5]))
end

local function onPlayHitMarkEffect(args)
    if next(pending) == nil then return end
    HitCapture.handlePlayHitMarkEffect(sdk.to_managed_object(args[3]), sdk.to_managed_object(args[4]))
end

function HitCapture.install()
    if installed then return end
    installed = true
    Game.hook("app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)", captureHitInfo)
    Game.hook("app.cEnemyStockDamage",
        "calcStockDamage(app.cEnemyStockDamage.cCalcDamage, app.cEnemyStockDamage.cPreCalcDamage, app.cEnemyStockDamage.cDamageRate, System.Boolean)",
        attachDamageCalc)
    Game.hook("app.cEnemyStockDamage.mcEnemyHitMarkManager",
        "playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
        onPlayHitMarkEffect)
end

return HitCapture
