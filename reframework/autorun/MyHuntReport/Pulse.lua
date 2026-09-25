local Game = require("MyHuntReport.Game")
local Session = require("MyHuntReport.Session")
local Quest = require("MyHuntReport.Quest")
local SkillState = require("MyHuntReport.SkillState")

local Pulse = {}

local MAX_STEP = 0.5

local lastTime = nil

function Pulse.reset()
    lastTime = nil
end

function Pulse.step(now, active, inCombat)
    local previous = lastTime
    lastTime = now
    if not active or previous == nil or not inCombat then return 0 end
    local dt = now - previous
    if dt <= 0 then return 0 end
    if dt > MAX_STEP then dt = MAX_STEP end
    Session.addFightingTime(dt)
    return dt
end

function Pulse.inCombat()
    local hunter = Game.masterHunter()
    if not hunter then return false end
    local ok, value = pcall(function() return hunter:get_IsCombatBoss() end)
    return ok and value == true
end

function Pulse.tick()
    local phase = Quest.phase()
    local active = phase == "playing" or phase == "training"
    local now = Game.uptime()
    Pulse.step(now, active, active and Pulse.inCombat())
    SkillState.pollEquipped(now, phase)
end

return Pulse
