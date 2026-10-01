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

return T
