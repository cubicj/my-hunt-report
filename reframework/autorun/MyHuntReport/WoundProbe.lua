local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local MotionNames = require("MyHuntReport.MotionNames")

local WoundProbe = {}

WoundProbe.COUNTER_ORDER = { "external", "scar", "windows", "hpChanges", "hitsInWindow" }
WoundProbe.WATCH_SECONDS = 1.0

local NULLABLE_KEY_TYPE = "System.Nullable`1<app.TARGET_ACCESS_KEY>"
local HUNTER_CATEGORIES = { [0] = true, [5] = true }

local counters = {}
local owners = {}
local watches = {}
local installed = false

local function resetQuestState()
    for _, name in ipairs(WoundProbe.COUNTER_ORDER) do counters[name] = 0 end
    owners = {}
    watches = {}
end

resetQuestState()

function WoundProbe.formatValue(value)
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
    if ok then return WoundProbe.formatValue(value) end
    return "?"
end

local function trace(text)
    Log.trace("wb " .. text)
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

local function enemyIndex(stock)
    local ok, index = pcall(function() return stock:get_Context():get_Em():get_UniqueIndex() end)
    if ok then return index end
    return nil
end

local function healthOf(index)
    if index == nil then return nil, nil end
    local owner = owners[index]
    if owner == nil then return nil, nil end
    local character = Game.componentOf(owner, "app.EnemyCharacter")
    if not character then return nil, nil end
    local okHealth, health = pcall(function() return character:get_HealthMgr():get_Health() end)
    local okMaxHealth, maxHealth = pcall(function() return character:get_HealthMgr():get_MaxHealth() end)
    if not okHealth then health = nil end
    if not okMaxHealth then maxHealth = nil end
    return health, maxHealth
end

local function hpText(index)
    local health, maxHealth = healthOf(index)
    return WoundProbe.formatValue(health) .. "/" .. WoundProbe.formatValue(maxHealth)
end

function WoundProbe.summaryLine(values)
    local parts = {}
    for _, name in ipairs(WoundProbe.COUNTER_ORDER) do
        parts[#parts + 1] = name .. "=" .. tostring(values[name] or 0)
    end
    return "summary " .. table.concat(parts, " ")
end

function WoundProbe.counters()
    return counters
end

function WoundProbe.reset()
    resetQuestState()
end

function WoundProbe.owner(index)
    return owners[index]
end

function WoundProbe.watch(index)
    return watches[index]
end

local function onQuestStart()
    resetQuestState()
    if not Log.isDeveloperMode() then return end
    trace("state weapon=" .. readValue(function() return Game.masterHunter():get_WeaponType() end))
end

local function onResultPost()
    if not Log.isDeveloperMode() then return end
    trace(WoundProbe.summaryLine(counters))
end

local function onStockDamageDetailPre(args)
    if not Log.isDeveloperMode() then return end
    local hitInfo = managedArg(args, 3)
    if not hitInfo then return end
    local okOwner, owner = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okOwner or owner == nil then return end
    local em = Game.enemyContext(owner)
    if not em then return end
    local okIndex, index = pcall(function() return em:get_UniqueIndex() end)
    if okIndex and index ~= nil then owners[index] = owner end
end

function WoundProbe.int32(value)
    if type(value) ~= "number" then return nil end
    local masked = math.tointeger(value) and (math.tointeger(value) & 0xFFFFFFFF) or nil
    if masked == nil then return nil end
    if masked >= 0x80000000 then return masked - 0x100000000 end
    return masked
end

local function readControllerAction(hunter, getter)
    local ok, action = pcall(function()
        local controller = hunter:call(getter)
        if not controller then return nil end
        return controller:get_CurrentAction()
    end)
    if ok then return action end
    return nil
end

local function actionText()
    local hunter = Game.masterHunter()
    if not hunter then return "base=nil/nil sub=nil" end
    local baseClass, baseGuideId = MotionNames.describe(readControllerAction(hunter, "get_BaseActionController"))
    local subClass = MotionNames.describe(readControllerAction(hunter, "get_SubActionController"))
    return "base=" .. tostring(baseClass) .. "/" .. tostring(baseGuideId) .. " sub=" .. tostring(subClass)
end

local function keyTexts(pointer)
    local okKey, nullable = pcall(function() return sdk.to_valuetype(pointer, NULLABLE_KEY_TYPE) end)
    if not okKey or nullable == nil then return "?", "?", "?" end
    local hasKey = readValue(function() return nullable._HasValue end)
    local key = readValue(function() return nullable._Value.Category end) .. "/" .. readValue(function() return nullable._Value.UniqueIndex end)
    local okMaster, master = pcall(function()
        if nullable._HasValue ~= true then return nil end
        local inner = nullable._Value
        if not HUNTER_CATEGORIES[inner.Category] then return false end
        local character = Game.callStatic("app.TargetAccessKeyUtil", "getHunterCharacter(app.TARGET_ACCESS_KEY)", inner)
        if not character then return nil end
        local gameObject = character:get_GameObject()
        if not gameObject then return nil end
        local masterAddress = Game.masterAddress()
        if masterAddress == nil then return nil end
        return gameObject:get_address() == masterAddress
    end)
    local masterText = "?"
    if okMaster and master ~= nil then masterText = tostring(master) end
    return hasKey, key, masterText
end

local function scarStateText(stock, scar)
    return readValue(function() return stock:get_Context():get_Em().Scar._ScarParts:Get(scar):get_State() end)
end

local function openWatch(index, label, now)
    local health = healthOf(index)
    watches[index] = { index = index, label = label, startedAt = now, openHealth = health, lastHealth = health }
    bump("windows")
end

local function markInvocation(fields)
    pcall(function() thread.get_hook_storage().wb = fields end)
end

local function takeInvocation()
    local ok, storage = pcall(thread.get_hook_storage)
    if not ok or type(storage) ~= "table" then return nil end
    local fields = storage.wb
    storage.wb = nil
    return fields
end

local function onExternalPre(args)
    if not Log.isDeveloperMode() then return end
    bump("external")
    local now = Game.uptime()
    local stock = managedArg(args, 2)
    local index = stock and enemyIndex(stock) or nil
    local value = readValue(function() return sdk.to_float(args[3]) end)
    local hasKey, key, master = keyTexts(args[5])
    trace("external t=" .. timeText(now) .. " em=" .. tostring(index) .. " value=" .. value
        .. " hasKey=" .. hasKey .. " key=" .. key .. " master=" .. master
        .. " hp=" .. hpText(index) .. " " .. actionText())
    if index ~= nil then openWatch(index, "external:" .. value, now) end
    markInvocation({ index = index })
end

local function onExternalPost()
    local fields = takeInvocation()
    if not fields then return end
    trace("external-post em=" .. tostring(fields.index) .. " hp=" .. WoundProbe.formatValue((healthOf(fields.index))))
end

local function onScarPre(args)
    if not Log.isDeveloperMode() then return end
    bump("scar")
    local now = Game.uptime()
    local stock = managedArg(args, 2)
    local index = stock and enemyIndex(stock) or nil
    local okScar, scar = pcall(function() return WoundProbe.int32(sdk.to_int64(args[3])) end)
    if not okScar then scar = nil end
    local scarText = scar ~= nil and tostring(scar) or "?"
    local value = readValue(function() return sdk.to_float(args[4]) end)
    local hasKey, key, master = keyTexts(args[7])
    local state = stock and scar ~= nil and scarStateText(stock, scar) or "?"
    trace("scar t=" .. timeText(now) .. " em=" .. tostring(index) .. " scar=" .. scarText .. " value=" .. value
        .. " hasKey=" .. hasKey .. " key=" .. key .. " master=" .. master .. " state=" .. state
        .. " hp=" .. hpText(index) .. " " .. actionText())
    if index ~= nil then openWatch(index, "scar:" .. value, now) end
    markInvocation({ index = index, scar = scar, stock = stock })
end

local function onScarPost()
    local fields = takeInvocation()
    if not fields then return end
    local state = fields.stock and fields.scar ~= nil and scarStateText(fields.stock, fields.scar) or "?"
    trace("scar-post em=" .. tostring(fields.index) .. " scar=" .. (fields.scar ~= nil and tostring(fields.scar) or "?")
        .. " state=" .. state .. " hp=" .. WoundProbe.formatValue((healthOf(fields.index))))
end

local function onHitMarkPre(args)
    if not Log.isDeveloperMode() or next(watches) == nil then return end
    local hitInfo = managedArg(args, 3)
    if not hitInfo then return end
    local okOwner, owner = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okOwner or owner == nil then return end
    local em = Game.enemyContext(owner)
    if not em then return end
    local okIndex, index = pcall(function() return em:get_UniqueIndex() end)
    if not okIndex or index == nil then return end
    local watch = watches[index]
    if watch == nil then return end
    local now = Game.uptime()
    bump("hitsInWindow")
    local calc = managedArg(args, 2)
    trace("hit t=" .. timeText(now) .. " em=" .. tostring(index)
        .. " final=" .. readValue(function() return calc.FinalDamage end)
        .. " hp=" .. WoundProbe.formatValue((healthOf(index))))
end

function WoundProbe.update()
    if not Log.isDeveloperMode() then
        watches = {}
        return
    end
    if next(watches) == nil then return end
    local now = Game.uptime()
    for index, watch in pairs(watches) do
        local health = healthOf(index)
        if health ~= nil and watch.lastHealth ~= nil and health ~= watch.lastHealth then
            bump("hpChanges")
            trace(string.format("hp t=%s em=%s after=%s dt=%.3f hp=%s delta=%s",
                timeText(now), tostring(index), watch.label, now - watch.startedAt,
                WoundProbe.formatValue(health), WoundProbe.formatValue(watch.lastHealth - health)))
        end
        if health ~= nil then watch.lastHealth = health end
        if now - watch.startedAt >= WoundProbe.WATCH_SECONDS then
            local drop = nil
            if watch.openHealth ~= nil and health ~= nil then drop = watch.openHealth - health end
            trace(string.format("watch-end em=%s after=%s dt=%.3f drop=%s",
                tostring(index), watch.label, now - watch.startedAt, WoundProbe.formatValue(drop)))
            watches[index] = nil
        end
    end
end

local function installFlowHooks()
    Game.hook("app.cQuestPlaying", "enter()", onQuestStart)
    Game.hook("app.cGUIQuestResultInfo", "execute()", nil, onResultPost)
end

local function installDamageHooks()
    Game.hook("app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)", onStockDamageDetailPre)
    Game.hook("app.cEnemyStockDamage",
        "stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)",
        onExternalPre, onExternalPost)
    Game.hook("app.cEnemyStockDamage",
        "stockExternalDamageScar(System.Int32, System.Single, System.Boolean, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean)",
        onScarPre, onScarPost)
    Game.hook("app.cEnemyStockDamage.mcEnemyHitMarkManager",
        "playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
        onHitMarkPre)
end

function WoundProbe.install()
    if installed then return end
    installed = true
    installFlowHooks()
    installDamageHooks()
end

return WoundProbe
