local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")

local HealTracker = {}

local MAX_FRAME_GAP_SECONDS = 1.0
local TIMER_RESET_MIN_DROP = 0.5
local RED_EQUAL_EPSILON = 0.05
local MIN_HEAL_DELTA = 0.5

local pending = nil
local lastPost = nil
local masterByAddress = {}
local installed = false

function HealTracker.reset()
    pending = nil
    lastPost = nil
    masterByAddress = {}
end

function HealTracker.detect(pre, post, previous)
    local found = {}
    if previous and pre.at - previous.at <= MAX_FRAME_GAP_SECONDS and pre.accHits < previous.accHits then
        local gap = pre.hp - previous.hp
        if gap >= MIN_HEAL_DELTA then
            found[#found + 1] = { kind = "hastenRecovery", amount = gap, maxHp = pre.maxHp, from = previous.hp, to = pre.hp }
        end
    end
    if post and pre.autoTimer - post.autoTimer >= TIMER_RESET_MIN_DROP and math.abs(pre.hp - pre.red) <= RED_EQUAL_EPSILON then
        local delta = post.hp - pre.hp
        if delta > 0 then
            found[#found + 1] = { kind = "superRecovery", amount = delta, maxHp = post.maxHp, from = pre.hp, to = post.hp }
        end
    end
    return found
end

function HealTracker.snapshot(health)
    local s = { at = Game.uptime() }
    local ok = pcall(function()
        local manager = health:get_HealthMgr()
        s.hp = manager:get_Health()
        s.maxHp = manager:get_MaxHealth()
        s.red = health:get_RedHealth()
        s.autoTimer = health._AutoRecoverTimerSkill or 0
        local info = health:get_Status()._Skill._HunterSkillParamInfo
        s.accHits = (info._AccHealHitCount or 0) + (info._DKAccHealHitCount or 0)
    end)
    if not ok or type(s.hp) ~= "number" then return nil end
    return s
end

local function record(entries)
    for _, entry in ipairs(entries) do
        if Session.addHeal(entry) then
            Log.debug(string.format("heal %s +%.1f (hp %.1f->%.1f)", entry.kind, entry.amount, entry.from, entry.to),
                "heal:" .. entry.kind)
        end
    end
end

local function isMaster(health)
    local okAddress, address = pcall(function() return health:get_address() end)
    if not okAddress or address == nil then return false end
    local cached = masterByAddress[address]
    if cached ~= nil then return cached end
    local ok, result = pcall(function()
        local status = health:get_Status()
        if status == nil then return nil end
        return status:get_IsMaster()
    end)
    if not ok or type(result) ~= "boolean" then return false end
    masterByAddress[address] = result
    return result
end

local function onUpdatePre(args)
    local health = sdk.to_managed_object(args[2])
    if not health or not isMaster(health) then return end
    local pre = HealTracker.snapshot(health)
    if not pre then return end
    local previous = lastPost
    lastPost = nil
    record(HealTracker.detect(pre, nil, previous))
    pending = { health = health, pre = pre }
end

local function onUpdatePost()
    local update = pending
    pending = nil
    if not update then return end
    local post = HealTracker.snapshot(update.health)
    if not post then return end
    record(HealTracker.detect(update.pre, post, nil))
    lastPost = post
end

function HealTracker.install()
    if installed then return end
    installed = true
    Game.hook("app.cHunterHealth", "update(System.Single, System.Boolean)", onUpdatePre, onUpdatePost)
end

return HealTracker
