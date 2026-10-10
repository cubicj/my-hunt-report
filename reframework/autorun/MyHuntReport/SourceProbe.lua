local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local MotionNames = require("MyHuntReport.MotionNames")
local ShellTracker = require("MyHuntReport.ShellTracker")

local SourceProbe = {}

local SUMMARY_EVERY = 50
local PATH_LIMIT = 5
local WEAPON_SWITCH_AXE = 8
local WEAPON_CHARGE_BLADE = 9
local NO_SHELL = "shell=none hash=- root=- path=- depth=- owner=- age=- setupBase=- setupSub=- setupWp=- row=-"
local UNKNOWN_SHELL = "shell=? hash=? root=? path=? depth=? owner=? age=? setupBase=? setupSub=? setupWp=? row=?"

local shells = {}
local observationGap = false
local counters = { hits = 0, shellHits = 0, noSetup = 0, dead = 0 }
local weaponCounts = {}
local weaponOrder = {}
local lastWeapon = nil
local installed = false

local function read(getter)
    local ok, value = pcall(getter)
    if ok then return value end
    return nil
end

local function trace(text)
    Log.trace("srcp " .. text)
end

local function beginObservation()
    if not Log.isDeveloperMode() then
        observationGap = true
        return false
    end
    if observationGap then
        shells = {}
        observationGap = false
    end
    return true
end

function SourceProbe.formatValue(value)
    if value == nil then return "?" end
    if math.type(value) == "float" then return string.format("%.2f", value) end
    return tostring(value)
end

function SourceProbe.formatAddress(address)
    if math.type(address) == "integer" then return string.format("0x%X", address) end
    return "?"
end

local show = SourceProbe.formatValue

local function seconds(value)
    if type(value) ~= "number" then return "?" end
    return string.format("%.3f", value)
end

function SourceProbe.lineage(hash, parentRecord, hasParent, parentHash)
    if hasParent == nil then return nil, nil, { "?", show(hash) } end
    if not hasParent then return 0, hash, { show(hash) } end
    if parentRecord == nil then return nil, parentHash, { show(parentHash), show(hash) } end
    local path = {}
    for _, entry in ipairs(parentRecord.path) do path[#path + 1] = entry end
    path[#path + 1] = show(hash)
    while #path > PATH_LIMIT do table.remove(path, 1) end
    local depth = nil
    if type(parentRecord.depth) == "number" then depth = parentRecord.depth + 1 end
    return depth, parentRecord.root, path
end

function SourceProbe.pathText(path)
    return table.concat(path, ">")
end

function SourceProbe.weaponState(handling, weaponType)
    local function get(name)
        if handling == nil then return "?" end
        return show(read(function() return handling:call(name) end))
    end
    if weaponType == WEAPON_SWITCH_AXE then
        return "mode=" .. get("get_Mode") .. ",sword=" .. get("get_IsSwordAwaken") .. ",axe=" .. get("get_IsAxeEnhanced")
    end
    if weaponType == WEAPON_CHARGE_BLADE then
        return "mode=" .. get("get_Mode") .. ",shield=" .. get("get_IsShieldEnhanced")
            .. ",sword=" .. get("get_IsSwordEnhanced") .. ",axe=" .. get("get_IsAxeEnhanced")
            .. ",bins=" .. get("get_SwordBinNum") .. ",energy=" .. get("get_SwordEnergyState")
    end
    return "-"
end

local function describeAction(action)
    if action == nil then return nil, nil end
    local className = MotionNames.className(action)
    if className == nil then return nil, nil end
    local guideId = read(function() return action._ActionGuideID end)
    if type(guideId) ~= "number" then guideId = nil end
    return className, guideId
end

local function actionText(className, guideId)
    return show(className) .. "/" .. show(guideId)
end

local function hunterState(hunter)
    local state = {}
    if hunter == nil then return state end
    state.weapon = read(function() return hunter:get_WeaponType() end)
    state.baseClass, state.baseGuide = describeAction(ShellTracker.readControllerAction(hunter, "get_BaseActionController"))
    state.subClass, state.subGuide = describeAction(ShellTracker.readControllerAction(hunter, "get_SubActionController"))
    return state
end

local function addressOf(object)
    if object == nil then return nil end
    return read(function() return object:get_address() end)
end

local function onSetUp(args)
    if not beginObservation() then return end
    local shell = sdk.to_managed_object(args[2])
    if not shell then return end
    local address = addressOf(shell)
    if address == nil then return end
    local hash = read(function() return shell:call("get_NameHash") end)
    local parentOk, parent = pcall(function() return shell:get_ParentShell() end)
    if not parentOk then parent = nil end
    local parentAddress = addressOf(parent)
    local parentHash = nil
    if parent ~= nil then parentHash = read(function() return parent:call("get_NameHash") end) end
    local parentRecord = parentAddress and shells[parentAddress] or nil
    local hasParent = nil
    if parentOk then hasParent = parent ~= nil end
    local depth, root, path = SourceProbe.lineage(hash, parentRecord, hasParent, parentHash)
    local record = {
        hash = hash,
        uid = read(function() return shell._ShellUniqueIndex end),
        chain = read(function() return shell._ChainShellID end),
        owner = read(function() return shell:get_ShellOwner():get_Name() end),
        depth = depth,
        root = root,
        path = path,
        t = Game.uptime(),
        state = hunterState(Game.masterHunter()),
    }
    shells[address] = record
    if type(record.owner) ~= "string" or not record.owner:find("^it") then return end
    local parentText = "none/-"
    if not parentOk then parentText = "?/?" end
    if parent ~= nil then parentText = SourceProbe.formatAddress(parentAddress) .. "/" .. show(parentHash) end
    trace(string.format("setup t=%s addr=%s hash=%s uid=%s chain=%s owner=%s parent=%s root=%s depth=%s path=%s base=%s sub=%s wp=%s",
        seconds(record.t), SourceProbe.formatAddress(address), show(hash), show(record.uid), show(record.chain),
        show(record.owner), parentText, show(root), show(depth), SourceProbe.pathText(path),
        actionText(record.state.baseClass, record.state.baseGuide), actionText(record.state.subClass, record.state.subGuide),
        show(record.state.weapon)))
end

local function onDestroy(args)
    if not beginObservation() then return end
    local address = addressOf(sdk.to_managed_object(args[2]))
    if address ~= nil then shells[address] = nil end
end

local function field(object, name)
    if object == nil then return nil end
    return read(function() return object[name] end)
end

local function shellText(attackObj, shell, now)
    counters.shellHits = counters.shellHits + 1
    local address = addressOf(shell)
    local hash = read(function() return shell:call("get_NameHash") end)
    local rowKey, _, hitTime = ShellTracker.nameForAttackObject(attackObj)
    local row = rowKey or (hitTime and "hitTime") or "-"
    local record = address and shells[address] or nil
    if record ~= nil and record.hash ~= hash then record = nil end
    if record == nil then
        counters.noSetup = counters.noSetup + 1
        return string.format("shell=%s hash=%s root=? path=? depth=? owner=? age=? setupBase=? setupSub=? setupWp=? row=%s",
            SourceProbe.formatAddress(address), show(hash), tostring(row))
    end
    return string.format("shell=%s hash=%s root=%s path=%s depth=%s owner=%s age=%s setupBase=%s setupSub=%s setupWp=%s row=%s",
        SourceProbe.formatAddress(address), show(hash), show(record.root), SourceProbe.pathText(record.path),
        show(record.depth), show(record.owner), seconds(now - record.t),
        actionText(record.state.baseClass, record.state.baseGuide), actionText(record.state.subClass, record.state.subGuide),
        show(record.state.weapon), tostring(row))
end

local function printSummary()
    local parts = {}
    for _, weapon in ipairs(weaponOrder) do parts[#parts + 1] = weapon .. ":" .. weaponCounts[weapon] end
    trace(string.format("summary hits=%d shellHits=%d noSetup=%d dead=%d byWp=%s",
        counters.hits, counters.shellHits, counters.noSetup, counters.dead, table.concat(parts, ",")))
end

function SourceProbe.handleHit(hitInfo)
    if hitInfo == nil then return end
    local owner = read(function() return hitInfo:getActualAttackOwner() end)
    if not Game.isMasterGameObject(owner) then return end
    local target = read(function() return hitInfo:get_DamageOwner() end)
    local em = Game.enemyContext(target)
    if em == nil then return end
    if read(function() return em:get_IsBoss() end) ~= true then return end
    local now = Game.uptime()
    local dead = Game.enemyIsDead(target)
    local attackObjOk, attackObj = pcall(function() return hitInfo:get_AttackObj() end)
    if not attackObjOk then attackObj = nil end
    local objectName = nil
    if attackObj ~= nil then objectName = read(function() return attackObj:get_Name() end) end
    local data = read(function() return hitInfo:get_AttackData() end)
    local index = read(function() return hitInfo:get_AttackIndex() end)
    local weaponType = field(data, "_WeaponType")
    local key = show(weaponType) .. ":" .. show(field(index, "_Resource")) .. ":" .. show(field(index, "_Index"))
    local hunter = Game.masterHunter()
    local state = hunterState(hunter)
    local handling = nil
    if hunter ~= nil then handling = read(function() return hunter:get_WeaponHandling() end) end
    local shell = attackObj and Game.componentOf(attackObj, "app.AppShell") or nil
    local lineage = attackObjOk and NO_SHELL or UNKNOWN_SHELL
    if shell ~= nil then lineage = shellText(attackObj, shell, now) end
    counters.hits = counters.hits + 1
    if dead then counters.dead = counters.dead + 1 end
    local weaponKey = show(state.weapon)
    if weaponCounts[weaponKey] == nil then
        weaponCounts[weaponKey] = 0
        weaponOrder[#weaponOrder + 1] = weaponKey
    end
    weaponCounts[weaponKey] = weaponCounts[weaponKey] + 1
    trace(string.format("hit t=%s em=%s dead=%s obj=%s wt=%s act=%s special=%s mv=%s key=%s wp=%s base=%s sub=%s state=%s %s",
        seconds(now), show(read(function() return em:get_UniqueIndex() end)), tostring(dead), show(objectName),
        show(weaponType), show(field(data, "_ActionType")), show(field(data, "_SpecialType")),
        show(field(data, "_OriginalAttackAdjust")), key, weaponKey,
        actionText(state.baseClass, state.baseGuide), actionText(state.subClass, state.subGuide),
        SourceProbe.weaponState(handling, state.weapon), lineage))
    local switched = lastWeapon ~= nil and lastWeapon ~= weaponKey
    lastWeapon = weaponKey
    if counters.hits % SUMMARY_EVERY == 0 or switched then printSummary() end
end

local function onHit(args)
    if not beginObservation() then return end
    SourceProbe.handleHit(sdk.to_managed_object(args[3]))
end

function SourceProbe.install()
    if installed then return end
    installed = true
    Game.hook("app.AppShell", "doOnSetUp", onSetUp)
    Game.hook("app.AppShell", "doOnDestroy", onDestroy)
    Game.hook("app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)", onHit)
end

return SourceProbe
