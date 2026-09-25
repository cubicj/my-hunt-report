local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local MotionNames = require("MyHuntReport.MotionNames")

local ShellTracker = {}

local WEAPON_HORN = 5
local ECHO_BUBBLE_HASH = 2691864323
local ECHO_WAVE_HASH = 824610146
local WEAPON_GLAIVE = 10
local MARK_SHOT_GUIDE_ID = -1726610048
local MARK_SHOT_HASHES = {
    [729186967] = true,
    [509541477] = true,
    [2205688478] = true,
    [1292422029] = true,
}
local WEAPON_BOW = 11
local WEAPON_HEAVY_BOWGUN = 12
local WEAPON_LIGHT_BOWGUN = 13

local launches = {}
local hitTimeCount = 0
local lastAttackClass = nil
local lastAttackGuideId = nil
local installed = false

local function isNonAttackAction(className)
    if type(className) ~= "string" then return false end
    return (className:find("^cDodge") or className:find("^cDamage")
        or className:find("^cLandSmash") or className:find("^cMove$")
        or className:find("^cAimWalk") or className:find("^cDash")
        or className:find("^cUseItem") or className:find("^cSlinger")) ~= nil
end

ShellTracker.isNonAttackAction = isNonAttackAction

local function readControllerAction(hunter, getter)
    local ok, action = pcall(function()
        local controller = hunter:call(getter)
        if not controller then return nil end
        return controller:get_CurrentAction()
    end)
    if ok then return action end
    return nil
end

function ShellTracker.currentAction(hunter, hitTime)
    if not hunter then return nil, nil, "base" end
    local sub = readControllerAction(hunter, "get_SubActionController")
    local subKey, subGuideId = MotionNames.describe(sub)
    if subKey and (subKey:find("^cSlinger") or subKey:find("^cCatchSlinger")) then
        return subKey, subGuideId, "sub", "slinger"
    end
    if subKey and (subKey:find("^cShot") or subKey:find("^cShoot")) then return subKey, subGuideId, "sub" end
    local className, guideId = MotionNames.describe(readControllerAction(hunter, "get_BaseActionController"))
    if className and className:find("^cPorterRide") and subKey and subKey ~= "cNothing" then
        return subKey, subGuideId, "sub"
    end
    if hitTime and isNonAttackAction(className) and lastAttackClass then
        return lastAttackClass, lastAttackGuideId, "lastAttack"
    end
    return className, guideId, isNonAttackAction(className) and "nonattack" or "base"
end

function ShellTracker.update()
    if hitTimeCount == 0 then return end
    local hunter = Game.masterHunter()
    if not hunter then return end
    local className, guideId = MotionNames.describe(readControllerAction(hunter, "get_BaseActionController"))
    if className and not isNonAttackAction(className) then
        lastAttackClass, lastAttackGuideId = className, guideId
    end
end

local function ammoItem(hunter)
    local ok, itemId, rapid = pcall(function()
        local handling = hunter:get_WeaponHandling()
        if not handling then return nil end
        local shellType = handling._ActionShellType
        local rapid = handling._IsRapidShotBoost == true and true or nil
        if type(shellType) ~= "number" then return nil end
        local itemId = Game.callStatic("app.WeaponGunDef", "getItemIDFromShellType(System.Int32)", shellType)
        if type(itemId) ~= "number" or itemId <= 0 then return nil end
        return itemId, rapid
    end)
    if ok then return itemId, rapid end
    return nil
end

local function coatingItem(hunter)
    local ok, itemId = pcall(function()
        local handling = hunter:get_WeaponHandling()
        if not handling then return nil end
        local bottleType = handling:get_BottleType()
        if type(bottleType) ~= "number" or bottleType <= 0 then return nil end
        local itemId = handling.SelectedBottleItem
        if type(itemId) ~= "number" then return nil end
        return itemId
    end)
    if ok then return itemId end
    return nil
end

local function launchName()
    local hunter = Game.masterHunter()
    if not hunter then return nil, nil end
    local className, guideId, _, kind = ShellTracker.currentAction(hunter)
    if kind == "slinger" then return "slinger", { kind = "slinger" } end
    if not className then return nil, nil end
    local label = { kind = "motion", className = className, guideId = guideId }
    local okType, weaponType = pcall(function() return hunter:get_WeaponType() end)
    if not okType or type(weaponType) ~= "number" then return className, label end
    label.weaponType = weaponType
    if weaponType == WEAPON_LIGHT_BOWGUN or weaponType == WEAPON_HEAVY_BOWGUN then
        label.itemId, label.rapid = ammoItem(hunter)
        if label.itemId ~= nil then
            label.itemRole = "ammo"
            local key = "ammo:" .. label.itemId
            if className:find("Variable", 1, true) or className:find("StepDodge", 1, true) then
                key = key .. ":" .. (guideId ~= -1 and tostring(guideId) or className)
            end
            if label.rapid then key = key .. ":rapid" end
            return key, label
        end
    elseif weaponType == WEAPON_BOW then
        label.itemId = coatingItem(hunter)
        if label.itemId ~= nil then label.itemRole = "coating" end
    end
    if label.itemId ~= nil then return className .. " " .. label.itemId, label end
    return className, label
end

local function addressOf(object)
    local ok, address = pcall(function() return object:get_address() end)
    if ok then return address end
    return nil
end

local function glaiveEntry(shell)
    local hunter = Game.masterHunter()
    if not hunter then return nil end
    local okHash, hash = pcall(function()
        if hunter:get_WeaponType() ~= WEAPON_GLAIVE then return nil end
        return shell:call("get_NameHash")
    end)
    if not okHash or not MARK_SHOT_HASHES[hash] then return nil end
    return { key = "cGunShot",
        label = { kind = "motion", className = "cGunShot", guideId = MARK_SHOT_GUIDE_ID, weaponType = WEAPON_GLAIVE } }
end

local function hornEntry(shell)
    local hunter = Game.masterHunter()
    if not hunter then return nil end
    local okHash, hash = pcall(function()
        if hunter:get_WeaponType() ~= WEAPON_HORN then return nil end
        return shell:call("get_NameHash")
    end)
    if not okHash then return nil end
    if hash == ECHO_BUBBLE_HASH then return { hitTime = true } end
    if hash ~= ECHO_WAVE_HASH then return nil end
    local okFreq, highFreq = pcall(function()
        return hunter:call("get_WeaponHandling"):call("get_HighFreqSkill")
    end)
    if okFreq and type(highFreq) == "number" and highFreq > 0 then
        return { key = "echowave:" .. highFreq,
            label = { kind = "echoWave", highFreq = highFreq, weaponType = WEAPON_HORN } }
    end
    return nil
end

local function setEntry(address, entry)
    if launches[address] and launches[address].hitTime then hitTimeCount = hitTimeCount - 1 end
    launches[address] = entry
    if entry and entry.hitTime then hitTimeCount = hitTimeCount + 1 end
    if hitTimeCount == 0 then lastAttackClass, lastAttackGuideId = nil, nil end
end

local function onSetUp(args)
    local shell = sdk.to_managed_object(args[2])
    if not shell then return end
    local address = addressOf(shell)
    if not address then return end
    local entry = glaiveEntry(shell)
    if not entry then
        local okParent, parent = pcall(function() return shell:get_ParentShell() end)
        local parentAddress = okParent and parent and addressOf(parent) or nil
        local parentEntry = parentAddress and launches[parentAddress] or nil
        entry = parentEntry or hornEntry(shell)
    end
    if not entry then
        local key, label = launchName()
        if key then entry = { key = key, label = label } end
    end
    setEntry(address, entry)
    if entry and Log.isDeveloperMode() then
        local key = entry.hitTime and "hitTime" or entry.key
        local okOwner, owner = pcall(function() return shell:get_ShellOwner():get_Name() end)
        local okHash, hash = pcall(function() return shell:call("get_NameHash") end)
        local origin = (okOwner and tostring(owner) or "?") .. "/" .. (okHash and tostring(hash) or "?")
        Log.debug("shell setup " .. tostring(address) .. " -> " .. key .. " owner=" .. origin, "shell:setup:" .. key .. ":" .. origin)
    end
end

local function onDestroy(args)
    local shell = sdk.to_managed_object(args[2])
    if not shell then return end
    local address = addressOf(shell)
    if address then setEntry(address, nil) end
end

function ShellTracker.install()
    if installed then return end
    installed = true
    Game.hook("app.AppShell", "doOnSetUp", onSetUp)
    Game.hook("app.AppShell", "doOnDestroy", onDestroy)
end

function ShellTracker.nameForAttackObject(attackObj)
    local shell = Game.componentOf(attackObj, "app.AppShell")
    if not shell then return nil, nil end
    local address = addressOf(shell)
    if not address then return nil, nil end
    local entry = launches[address]
    if entry then return entry.key, entry.label, entry.hitTime end
    return nil, nil
end

function ShellTracker.reset()
    launches = {}
    hitTimeCount = 0
    lastAttackClass, lastAttackGuideId = nil, nil
end

return ShellTracker
