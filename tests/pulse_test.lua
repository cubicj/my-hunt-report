local Pulse = require("MyHuntReport.Pulse")
local Session = require("MyHuntReport.Session")

local T = {}

function T.firstStepAddsNothing()
    Session.reset(0)
    Pulse.reset()
    assert(Pulse.step(10, true, true) == 0)
    assert(Session.snapshot().stats.fightingSeconds == 0)
end

function T.stepsAccumulateOnlyInCombat()
    Session.reset(0)
    Pulse.reset()
    Pulse.step(10, true, true)
    assert(math.abs(Pulse.step(10.1, true, true) - 0.1) < 1e-9)
    assert(Pulse.step(10.2, true, false) == 0)
    assert(math.abs(Pulse.step(10.3, true, true) - 0.1) < 1e-9)
    assert(math.abs(Session.snapshot().stats.fightingSeconds - 0.2) < 1e-9)
end

function T.largeGapsAreClamped()
    Session.reset(0)
    Pulse.reset()
    Pulse.step(10, true, true)
    assert(Pulse.step(20, true, true) == 0.5)
end

function T.inactivePhaseAddsNothingButTracksTime()
    Session.reset(0)
    Pulse.reset()
    Pulse.step(10, false, true)
    assert(Pulse.step(10.1, false, true) == 0)
    assert(math.abs(Pulse.step(10.2, true, true) - 0.1) < 1e-9)
end

function T.resetForgetsLastTime()
    Session.reset(0)
    Pulse.reset()
    Pulse.step(10, true, true)
    Pulse.reset()
    assert(Pulse.step(10.1, true, true) == 0)
end

function T.tickPollsAfterFightingStepWithUptimeAndPhase()
    local Game = require("MyHuntReport.Game")
    local Quest = require("MyHuntReport.Quest")
    local SkillState = require("MyHuntReport.SkillState")
    local uptime, phase, inCombat, poll = Game.uptime, Quest.phase, Pulse.inCombat, SkillState.pollEquipped
    local currentPhase, now = "training", 10.25
    local calls = 0
    Game.uptime = function() return now end
    Quest.phase = function() return currentPhase end
    Pulse.inCombat = function() return true end
    SkillState.pollEquipped = function(time, actualPhase)
        calls = calls + 1
        assert(time == now and actualPhase == currentPhase)
        local expected = currentPhase == "training" and 0.25 or 0
        assert(Session.snapshot().stats.fightingSeconds == expected)
    end
    local ok, err = pcall(function()
        for _, value in ipairs({ "training", "playing", "idle", "result" }) do
            currentPhase = value
            Session.reset(0)
            Pulse.reset()
            if value == "training" then Pulse.step(10, true, true) end
            Pulse.tick()
        end
        assert(calls == 4)
    end)
    Game.uptime, Quest.phase, Pulse.inCombat, SkillState.pollEquipped = uptime, phase, inCombat, poll
    Pulse.reset()
    if not ok then error(err, 0) end
end

return T
