local stubs = require("stubs")
local Log = require("MyHuntReport.Log")

local T = {}

function T.errorWritesPrefixedLine()
    Log.resetCounts()
    Log.error("boom")
    assert(#stubs.logLines == 1, "expected one line, got " .. #stubs.logLines)
    assert(stubs.logLines[1] == "[MyHuntReport] Error: boom", stubs.logLines[1])
end

function T.debugIsGatedByDeveloperMode()
    Log.resetCounts()
    Log.setDeveloperMode(false)
    assert(Log.debug("hidden") == false)
    assert(#stubs.logLines == 0)
    Log.setDeveloperMode(true)
    assert(Log.debug("shown") == true)
    assert(stubs.logLines[1] == "[MyHuntReport] shown", stubs.logLines[1])
    Log.setDeveloperMode(false)
end

function T.repeatsStopAfterFive()
    Log.resetCounts()
    for _ = 1, 8 do Log.error("same") end
    assert(#stubs.logLines == 5, "got " .. #stubs.logLines)
    assert(stubs.logLines[5]:find("further repeats suppressed", 1, true), stubs.logLines[5])
    assert(Log.count("same") == 8)
end

function T.explicitKeyGroupsDifferentMessages()
    Log.resetCounts()
    for i = 1, 7 do Log.error("hit " .. i, "hit") end
    assert(#stubs.logLines == 5)
    assert(Log.count("hit") == 7)
end

function T.traceIsGatedAndNeverDeduplicated()
    Log.resetCounts()
    Log.setDeveloperMode(false)
    assert(Log.trace("repeated") == false)
    assert(#stubs.logLines == 0)
    Log.setDeveloperMode(true)
    for _ = 1, 8 do assert(Log.trace("repeated") == true) end
    Log.setDeveloperMode(false)
    assert(#stubs.logLines == 8)
    for _, line in ipairs(stubs.logLines) do assert(line == "[MyHuntReport] repeated") end
    assert(Log.count("repeated") == 0)
end

return T
