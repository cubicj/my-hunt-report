local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local function atkLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] atk ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function withAttackLog(callback)
    local masterHunter, uptime = Game.masterHunter, Game.uptime
    local developerMode = Log.isDeveloperMode()
    local c = { now = 100.0, reads = 0, lookups = 0, clockReads = 0, values = {} }
    c.power = {
        call = function(_, signature)
            c.reads = c.reads + 1
            local value = c.values[signature]
            if value == "error" then error("boom") end
            return value
        end,
    }
    c.master = {
        get_HunterStatus = function() return { get_AttackPower = function() return c.power end } end,
    }
    local ok, err = pcall(function()
        stubs.reset()
        Log.setDeveloperMode(true)
        Game.masterHunter = function()
            c.lookups = c.lookups + 1
            return c.master
        end
        Game.uptime = function()
            c.clockReads = c.clockReads + 1
            return c.now
        end
        c.logger = assert(loadfile("reframework/autorun/MyHuntReport/AttackLog.lua"))()
        callback(c)
    end)
    Game.masterHunter, Game.uptime = masterHunter, uptime
    Log.setDeveloperMode(developerMode)
    if not ok then error(err, 0) end
end

local function setPower(c, weapon, current, add, rate)
    c.values["get_WeaponAttackPower()"] = weapon
    c.values["get_CurrentAttackPower()"] = current
    c.values["get_CurrentAttackAdd()"] = add
    c.values["get_CurrentAttackRate()"] = rate
end

function T.fieldsContainOnlyTheFourOrderedGetters()
    withAttackLog(function(c)
        assert(stubs.encode(c.logger.FIELDS) == stubs.encode({
            { "weapon", "get_WeaponAttackPower()" },
            { "current", "get_CurrentAttackPower()" },
            { "add", "get_CurrentAttackAdd()" },
            { "rate", "get_CurrentAttackRate()" },
        }))
    end)
end

function T.updateLogsOneLinePerChangedFieldAndNothingWhenUnchanged()
    withAttackLog(function(c)
        setPower(c, 220.0, 235.0, 15.0, 1.0)
        c.logger.update()
        local first = atkLines()
        assert(#first == 4, #first)
        assert(first[1] == "[MyHuntReport] atk change weapon nil -> 220.0 at 100.0", first[1])
        assert(first[2] == "[MyHuntReport] atk change current nil -> 235.0 at 100.0", first[2])
        assert(first[3] == "[MyHuntReport] atk change add nil -> 15.0 at 100.0", first[3])
        assert(first[4] == "[MyHuntReport] atk change rate nil -> 1.0 at 100.0", first[4])
        c.logger.update()
        assert(#atkLines() == 4)
        assert(c.reads == 8 and c.clockReads == 1)
        c.now = 101.0
        c.values["get_CurrentAttackPower()"] = 245.0
        c.logger.update()
        local lines = atkLines()
        assert(#lines == 5, #lines)
        assert(lines[5] == "[MyHuntReport] atk change current 235.0 -> 245.0 at 101.0", lines[5])
    end)
end

function T.updateLogsANanReadingOnce()
    withAttackLog(function(c)
        setPower(c, 220.0, 235.0, 15.0, 1.0)
        c.logger.update()
        local nan = 0 / 0
        c.values["get_CurrentAttackRate()"] = nan
        c.logger.update()
        c.logger.update()
        c.logger.update()
        local lines = atkLines()
        assert(#lines == 5, #lines)
        assert(lines[5] == "[MyHuntReport] atk change rate 1.0 -> " .. tostring(nan) .. " at 100.0", lines[5])
    end)
end

function T.failedGetterPrintsQuestionMarkOnce()
    withAttackLog(function(c)
        setPower(c, 220.0, 235.0, 15.0, 1.0)
        c.logger.update()
        c.values["get_CurrentAttackAdd()"] = "error"
        c.logger.update()
        c.logger.update()
        local lines = atkLines()
        assert(#lines == 5, #lines)
        assert(lines[5] == "[MyHuntReport] atk change add 15.0 -> ? at 100.0", lines[5])
    end)
end

function T.aGetterWhoseLookupRaisesPrintsQuestionMarksOnce()
    withAttackLog(function(c)
        c.power = setmetatable({}, { __index = function() error("lookup failed") end })
        c.logger.update()
        c.logger.update()
        local lines = atkLines()
        assert(#lines == 4, #lines)
        for index, name in ipairs({ "weapon", "current", "add", "rate" }) do
            assert(lines[index] == "[MyHuntReport] atk change " .. name .. " nil -> ? at 100.0", lines[index])
        end
    end)
end

function T.updatePrintsQuestionMarksWithoutAMasterHunter()
    withAttackLog(function(c)
        c.master = nil
        c.logger.update()
        c.logger.update()
        local lines = atkLines()
        assert(#lines == 4, #lines)
        for index, name in ipairs({ "weapon", "current", "add", "rate" }) do
            assert(lines[index] == "[MyHuntReport] atk change " .. name .. " nil -> ? at 100.0", lines[index])
        end
        assert(c.reads == 0, c.reads)
    end)
end

function T.developerModeOffReadsNothingAndForgetsPreviousValues()
    withAttackLog(function(c)
        setPower(c, 220.0, 235.0, 15.0, 1.0)
        Log.setDeveloperMode(false)
        c.logger.update()
        assert(c.reads == 0 and c.lookups == 0 and c.clockReads == 0)
        assert(#stubs.logLines == 0)
        Log.setDeveloperMode(true)
        c.logger.update()
        local first = atkLines()
        assert(#first == 4)
        local reads, lookups, clockReads, logs = c.reads, c.lookups, c.clockReads, #stubs.logLines
        Log.setDeveloperMode(false)
        c.logger.update()
        c.logger.update()
        assert(c.reads == reads and c.lookups == lookups and c.clockReads == clockReads)
        assert(#stubs.logLines == logs)
        Log.setDeveloperMode(true)
        c.logger.update()
        local lines = atkLines()
        assert(#lines == 8, #lines)
        for index = 1, 4 do assert(lines[index + 4] == first[index], lines[index + 4]) end
    end)
end

function T.resetForTestsForgetsPreviousValues()
    withAttackLog(function(c)
        setPower(c, 220.0, 235.0, 15.0, 1.0)
        c.logger.update()
        c.logger.resetForTests()
        c.logger.update()
        local lines = atkLines()
        assert(#lines == 8, #lines)
        for index = 1, 4 do assert(lines[index + 4] == lines[index], lines[index + 4]) end
    end)
end

return T
