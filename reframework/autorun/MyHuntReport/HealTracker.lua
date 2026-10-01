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

return HealTracker
