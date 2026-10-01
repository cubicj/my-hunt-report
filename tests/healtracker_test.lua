local HealTracker = require("MyHuntReport.HealTracker")

local T = {}

local function snap(overrides)
    local base = { hp = 100, maxHp = 150, red = 100, autoTimer = 1.0, accHits = 0, at = 10.0 }
    for key, value in pairs(overrides or {}) do base[key] = value end
    return base
end

function T.hastenRecoveryNeedsCounterDropAndHpJumpWithinGap()
    local previous = snap({ hp = 100, accHits = 4, at = 10.0 })
    local pre = snap({ hp = 106, accHits = 0, at = 10.02 })
    local found = HealTracker.detect(pre, nil, previous)
    assert(#found == 1, #found)
    assert(found[1].kind == "hastenRecovery")
    assert(found[1].amount == 6 and found[1].maxHp == 150)
    assert(found[1].from == 100 and found[1].to == 106)
end

function T.hastenRecoveryIgnoresCounterResetWithoutHeal()
    local previous = snap({ hp = 100, accHits = 1, at = 10.0 })
    local pre = snap({ hp = 100, accHits = 0, at = 10.02 })
    assert(#HealTracker.detect(pre, nil, previous) == 0)
end

function T.hastenRecoveryIgnoresFrameGapOverOneSecond()
    local previous = snap({ hp = 100, accHits = 4, at = 10.0 })
    local pre = snap({ hp = 106, accHits = 0, at = 11.5 })
    assert(#HealTracker.detect(pre, nil, previous) == 0)
end

function T.hastenRecoveryIgnoresHpBelowMinimumDelta()
    local previous = snap({ hp = 100, accHits = 4, at = 10.0 })
    local pre = snap({ hp = 100.3, accHits = 0, at = 10.02 })
    assert(#HealTracker.detect(pre, nil, previous) == 0)
end

function T.hastenRecoveryNeedsPrevious()
    local pre = snap({ hp = 106, accHits = 0 })
    assert(#HealTracker.detect(pre, nil, nil) == 0)
end

function T.superRecoveryNeedsTimerResetAtRedMark()
    local pre = snap({ hp = 100, red = 100, autoTimer = 2.0 })
    local post = snap({ hp = 101, red = 101, autoTimer = 0.0, maxHp = 160 })
    local found = HealTracker.detect(pre, post, nil)
    assert(#found == 1, #found)
    assert(found[1].kind == "superRecovery")
    assert(found[1].amount == 1 and found[1].maxHp == 160)
    assert(found[1].from == 100 and found[1].to == 101)
end

function T.superRecoveryIgnoresNaturalRedRegeneration()
    local pre = snap({ hp = 90, red = 100, autoTimer = 1.3 })
    local post = snap({ hp = 91, red = 100, autoTimer = 1.3 })
    assert(#HealTracker.detect(pre, post, nil) == 0)
end

function T.superRecoveryIgnoresPotionHeal()
    local pre = snap({ hp = 100, red = 100, autoTimer = 0.7 })
    local post = snap({ hp = 100.3, red = 100.3, autoTimer = 0.7 })
    assert(#HealTracker.detect(pre, post, nil) == 0)
end

function T.superRecoveryIgnoresTimerResetWhileHpBelowRed()
    local pre = snap({ hp = 90, red = 100, autoTimer = 2.0 })
    local post = snap({ hp = 91, red = 100, autoTimer = 0.0 })
    assert(#HealTracker.detect(pre, post, nil) == 0)
end

function T.superRecoveryIgnoresZeroDeltaAtFullHp()
    local pre = snap({ hp = 150, red = 150, autoTimer = 2.0 })
    local post = snap({ hp = 150, red = 150, autoTimer = 0.0 })
    assert(#HealTracker.detect(pre, post, nil) == 0)
end

function T.detectReturnsBothKindsInOrder()
    local previous = snap({ hp = 100, accHits = 2, at = 10.0 })
    local pre = snap({ hp = 105, red = 105, accHits = 0, autoTimer = 2.0, at = 10.02 })
    local post = snap({ hp = 106, red = 106, autoTimer = 0.0, at = 10.02 })
    local found = HealTracker.detect(pre, post, previous)
    assert(#found == 2)
    assert(found[1].kind == "hastenRecovery" and found[1].amount == 5)
    assert(found[2].kind == "superRecovery" and found[2].amount == 1)
end

function T.resetIsCallable()
    HealTracker.reset()
    HealTracker.reset()
end

local Game = require("MyHuntReport.Game")
local Session = require("MyHuntReport.Session")

local function fakeHealth(spec)
    local info = { _AccHealHitCount = spec.accHits or 0, _DKAccHealHitCount = spec.dkAccHits or 0 }
    local status = { _Skill = { _HunterSkillParamInfo = info } }
    function status:get_IsMaster() return spec.master == true end
    local health = { _AutoRecoverTimerSkill = spec.autoTimer or 0, statusCalls = 0 }
    function health:get_HealthMgr()
        return { get_Health = function() return spec.hp end, get_MaxHealth = function() return spec.maxHp end }
    end
    function health:get_RedHealth() return spec.red end
    function health:get_Status()
        self.statusCalls = self.statusCalls + 1
        return status
    end
    function health:get_address() return spec.address or 1 end
    return health
end

local function withTracker(callback)
    local hook, uptime, addHeal, toManaged = Game.hook, Game.uptime, Session.addHeal, sdk.to_managed_object
    local hooks, recorded, now = {}, {}, 10.0
    local ok, err = pcall(function()
        Game.hook = function(typeName, signature, pre, post)
            hooks[#hooks + 1] = { name = typeName .. "." .. signature, pre = pre, post = post }
        end
        Game.uptime = function() return now end
        Session.addHeal = function(heal) recorded[#recorded + 1] = heal return true end
        sdk.to_managed_object = function(value) return value end
        local tracker = assert(loadfile("reframework/autorun/MyHuntReport/HealTracker.lua"))()
        tracker.install()
        tracker.install()
        local context = { tracker = tracker, hooks = hooks, recorded = recorded }
        function context.update(health, mutate)
            hooks[1].pre({ [2] = health })
            if mutate then mutate() end
            hooks[1].post(nil)
        end
        function context.advance(seconds) now = now + seconds end
        callback(context)
    end)
    Game.hook, Game.uptime, Session.addHeal, sdk.to_managed_object = hook, uptime, addHeal, toManaged
    if not ok then error(err, 0) end
end

function T.installRegistersOneUpdateHookOnce()
    withTracker(function(c)
        assert(#c.hooks == 1, #c.hooks)
        assert(c.hooks[1].name == "app.cHunterHealth.update(System.Single, System.Boolean)", c.hooks[1].name)
        assert(type(c.hooks[1].pre) == "function" and type(c.hooks[1].post) == "function")
    end)
end

function T.snapshotReadsEveryFieldAndFailsClosed()
    local health = fakeHealth({ hp = 90, maxHp = 150, red = 100, autoTimer = 1.25, accHits = 3, dkAccHits = 1 })
    local uptime = Game.uptime
    Game.uptime = function() return 42 end
    local s = HealTracker.snapshot(health)
    Game.uptime = uptime
    assert(s.hp == 90 and s.maxHp == 150 and s.red == 100 and s.autoTimer == 1.25 and s.accHits == 4 and s.at == 42)
    assert(HealTracker.snapshot({}) == nil)
    assert(HealTracker.snapshot(fakeHealth({ maxHp = 150, red = 100 })) == nil)
end

function T.updateRecordsSuperRecoveryForMasterOnly()
    withTracker(function(c)
        local spec = { master = true, hp = 100, maxHp = 150, red = 100, autoTimer = 2.0, address = 7 }
        local master = fakeHealth(spec)
        c.update(master, function()
            spec.hp, spec.red, master._AutoRecoverTimerSkill = 101, 101, 0.0
        end)
        assert(#c.recorded == 1, #c.recorded)
        assert(c.recorded[1].kind == "superRecovery" and c.recorded[1].amount == 1 and c.recorded[1].maxHp == 150)
        local otherSpec = { master = false, hp = 50, maxHp = 150, red = 50, autoTimer = 2.0, address = 8 }
        local other = fakeHealth(otherSpec)
        c.update(other, function()
            otherSpec.hp, otherSpec.red, other._AutoRecoverTimerSkill = 51, 51, 0.0
        end)
        assert(#c.recorded == 1, #c.recorded)
    end)
end

function T.updateRecordsHastenRecoveryAcrossFrames()
    withTracker(function(c)
        local spec = { master = true, hp = 100, maxHp = 150, red = 100, autoTimer = 0.5, accHits = 4, address = 7 }
        local master = fakeHealth(spec)
        c.update(master)
        c.advance(0.02)
        spec.hp, spec.red, spec.accHits = 106, 106, 0
        master:get_Status()._Skill._HunterSkillParamInfo._AccHealHitCount = 0
        c.update(master)
        assert(#c.recorded == 1, #c.recorded)
        assert(c.recorded[1].kind == "hastenRecovery" and c.recorded[1].amount == 6 and c.recorded[1].maxHp == 150)
    end)
end

function T.masterCheckIsCachedPerAddressUntilReset()
    withTracker(function(c)
        local spec = { master = true, hp = 100, maxHp = 150, red = 100, autoTimer = 0.5, address = 7 }
        local master = fakeHealth(spec)
        c.update(master)
        local afterFirst = master.statusCalls
        c.update(master)
        assert(master.statusCalls == afterFirst + 2, master.statusCalls)
        c.tracker.reset()
        c.update(master)
        assert(master.statusCalls == afterFirst + 5, master.statusCalls)
    end)
end

function T.postWithoutPendingIsIgnored()
    withTracker(function(c)
        c.hooks[1].post(nil)
        assert(#c.recorded == 0)
    end)
end

function T.masterCheckRetriesAfterTransientStatusFailure()
    withTracker(function(c)
        local spec = { master = true, hp = 100, maxHp = 150, red = 100, autoTimer = 2.0, address = 7 }
        local master = fakeHealth(spec)
        local getStatus = master.get_Status
        function master:get_Status()
            if self.statusCalls == 0 then
                self.statusCalls = self.statusCalls + 1
                error("transient status failure")
            end
            return getStatus(self)
        end
        c.update(master)
        assert(master.statusCalls == 1, master.statusCalls)
        assert(#c.recorded == 0, #c.recorded)
        c.update(master, function()
            spec.hp, spec.red, master._AutoRecoverTimerSkill = 101, 101, 0.0
        end)
        assert(master.statusCalls == 4, "expected retry and two snapshots, got " .. master.statusCalls)
        assert(#c.recorded == 1, #c.recorded)
        assert(c.recorded[1].kind == "superRecovery" and c.recorded[1].amount == 1)
    end)
end

return T
