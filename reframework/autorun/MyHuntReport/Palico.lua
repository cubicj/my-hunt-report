local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")

local Palico = {}

local OTOMO_CATEGORY = 2

local pending = {}
local seen = {}
local installed = false

function Palico.reset()
    pending = {}
    seen = {}
end

function Palico.isOwnObject(gameObject)
    local otomo = Game.componentOf(gameObject, "app.OtomoCharacter")
    if not otomo then return false, nil end
    local ok, mine = pcall(function() return otomo:get_IsMasterMyOtomo() end)
    return ok and mine == true, otomo
end

function Palico.isOwnKey(key)
    local okCategory, category = pcall(function() return key.Category end)
    if not okCategory or category ~= OTOMO_CATEGORY then return false end
    local character = Game.callStatic("app.TargetAccessKeyUtil", "getCharacter(app.TARGET_ACCESS_KEY)", key)
    if not character then return false end
    local okObject, gameObject = pcall(function() return character:get_GameObject() end)
    if not okObject then return false end
    return (Palico.isOwnObject(gameObject))
end

local function noteSeen(gameObject, mine)
    if not Log.isDeveloperMode() then return end
    local ok, address, name = pcall(function() return gameObject:get_address(), gameObject:get_Name() end)
    if not ok or address == nil or seen[address] then return end
    seen[address] = true
    Log.trace("palico seen name=" .. tostring(name) .. " mine=" .. tostring(mine))
end

function Palico.handleStockDamageDetail(hitInfo)
    if not hitInfo then return end
    local okAddress, address = pcall(function() return hitInfo:get_address() end)
    if not okAddress or address == nil then return end
    pending[address] = nil
    local okOwner, owner = pcall(function() return hitInfo:getActualAttackOwner() end)
    if not okOwner or owner == nil then return end
    local mine, otomo = Palico.isOwnObject(owner)
    if not otomo then return end
    noteSeen(owner, mine)
    if not mine then return end
    local okTarget, target = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okTarget then return end
    local em = Game.enemyContext(target)
    if not em then return end
    local okBoss, isBoss = pcall(function() return em:get_IsBoss() end)
    if not okBoss or isBoss ~= true then return end
    if Game.enemyIsDead(target) then return end
    pending[address] = true
end

function Palico.handleHitMark(calc, hitInfo)
    if not hitInfo then return end
    local okAddress, address = pcall(function() return hitInfo:get_address() end)
    if not okAddress or address == nil or not pending[address] then return end
    pending[address] = nil
    local okDamage, finalDamage = pcall(function() return calc.FinalDamage end)
    if not okDamage or not Session.addPalicoHit(finalDamage) then return end
    if not Log.isDeveloperMode() then return end
    local okName, name = pcall(function() return hitInfo:get_AttackObj():get_Name() end)
    local totals = Session.palicoTotals()
    Log.trace(string.format("palico hit #%d dmg=%.1f obj=%s total=%.1f",
        totals.hits, finalDamage, okName and tostring(name) or "?", totals.direct))
end

function Palico.logSummary(snapshot)
    if not Log.isDeveloperMode() then return end
    local damage = type(snapshot) == "table" and snapshot.damage or nil
    local palico = type(snapshot) == "table" and snapshot.palico or nil
    palico = palico or { hits = 0, direct = 0, blast = 0, poison = 0, share = 0 }
    Log.trace(string.format("palico summary hits=%d direct=%.1f blast=%.1f poison=%.1f own=%.1f share=%.4f",
        palico.hits, palico.direct, palico.blast, palico.poison, damage and damage.total or 0, palico.share))
end

local function captureHitInfo(args)
    Palico.handleStockDamageDetail(sdk.to_managed_object(args[3]))
end

local function onPlayHitMarkEffect(args)
    if next(pending) == nil then return end
    Palico.handleHitMark(sdk.to_managed_object(args[3]), sdk.to_managed_object(args[4]))
end

function Palico.install()
    if installed then return end
    installed = true
    Game.hook("app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)", captureHitInfo)
    Game.hook("app.cEnemyStockDamage.mcEnemyHitMarkManager",
        "playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
        onPlayHitMarkEffect)
end

return Palico
