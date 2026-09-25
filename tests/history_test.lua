local stubs = require("stubs")
local History = require("MyHuntReport.History")

local T = {}

function T.appendWritesOneLinePerSnapshot()
    History.resetForTests()
    assert(History.append({ id = 1 }) == true)
    assert(History.append({ id = 2 }) == true)
    local text = stubs.files[History.FILE]
    local _, lines = text:gsub("\n", "")
    assert(lines == 2, "expected 2 newline-terminated lines, got " .. lines)
    assert(History.appendMode() == true)
end

function T.readAllDecodesInFileOrder()
    History.resetForTests()
    History.append({ id = 1 })
    History.append({ id = 2 })
    local entries, skipped = History.readAll()
    assert(#entries == 2)
    assert(entries[1].id == 1 and entries[2].id == 2)
    assert(skipped == 0)
end

function T.readAllSkipsUnreadableLines()
    History.resetForTests()
    stubs.files[History.FILE] = stubs.encode({ id = 1 }) .. "\n{broken\n\n" .. stubs.encode({ id = 3 }) .. "\n"
    local entries, skipped = History.readAll()
    assert(#entries == 2, "got " .. #entries)
    assert(entries[2].id == 3)
    assert(skipped == 1)
    assert(#stubs.logLines == 1)
end

function T.readAllWithoutFileIsEmpty()
    History.resetForTests()
    local entries, skipped = History.readAll()
    assert(#entries == 0 and skipped == 0)
end

function T.fallsBackToRewriteWhenAppendIsRejected()
    History.resetForTests()
    stubs.openFails = true
    assert(History.append({ id = 1 }) == true)
    assert(History.append({ id = 2 }) == true)
    assert(History.appendMode() == false)
    local entries = History.readAll()
    assert(#entries == 2)
    assert(#stubs.logLines == 1, "fallback should be logged once")
end

local Log = require("MyHuntReport.Log")

local function countLogs(fragment)
    local count = 0
    for _, line in ipairs(stubs.logLines) do
        if line:find(fragment, 1, true) then count = count + 1 end
    end
    return count
end

function T.writeFailureClosesHandleWithoutRewrite()
    History.resetForTests()
    Log.resetCounts()
    local originalOpen = io.open
    local closed = false
    io.open = function()
        return {
            write = function() return nil, "disk full" end,
            close = function() closed = true; return true end,
        }
    end
    local ok, result = pcall(History.append, { id = 1 })
    io.open = originalOpen
    assert(ok and result == false)
    assert(closed, "failed write handle must be closed")
    assert(History.appendMode() == nil)
    assert(stubs.files[History.FILE] == nil)
    assert(#stubs.logLines == 1)
    assert(countLogs("after open: disk full") == 1)
    assert(Log.count("history:partial") == 1)
end

function T.closeFailurePreservesAppendModeWithoutRewrite()
    History.resetForTests()
    Log.resetCounts()
    assert(History.append({ id = 7 }) == true)
    local originalOpen = io.open
    io.open = function()
        return {
            write = function(self, ...)
                stubs.files[History.FILE] = stubs.files[History.FILE] .. table.concat({ ... })
                return self
            end,
            close = function() return nil, "close failed" end,
        }
    end
    local ok, result = pcall(History.append, { id = 8 })
    io.open = originalOpen
    assert(ok and result == false)
    assert(stubs.openFails == false)
    assert(History.appendMode() == true)
    assert(stubs.files[History.FILE] == stubs.encode({ id = 7 }) .. "\n"
        .. stubs.encode({ id = 8 }) .. "\n")
    assert(#stubs.logLines == 1)
    assert(countLogs("after open: close failed") == 1)
    assert(Log.count("history:partial") == 1)
end

function T.closeFailureDoesNotDuplicatePersistedLine()
    History.resetForTests()
    Log.resetCounts()
    local originalOpen = io.open
    io.open = function()
        return {
            write = function(self, ...)
                stubs.files[History.FILE] = (stubs.files[History.FILE] or "") .. table.concat({ ... })
                return self
            end,
            close = function() return nil, "close failed" end,
        }
    end
    local ok, result = pcall(History.append, { id = 8 })
    io.open = originalOpen
    assert(stubs.files[History.FILE] == stubs.encode({ id = 8 }) .. "\n")
    assert(ok and result == false)
    assert(History.appendMode() == nil)
    assert(#stubs.logLines == 1)
    assert(countLogs("after open: close failed") == 1)
    assert(Log.count("history:partial") == 1)
end

function T.rewriteFalseReturnFails()
    History.resetForTests()
    Log.resetCounts()
    stubs.openFails = true
    local originalWrite = fs.write
    fs.write = function() return false end
    local ok, result = pcall(History.append, { id = 1 })
    fs.write = originalWrite
    assert(ok and result == false)
    assert(countLogs("history write failed") == 1)
    assert(Log.count("history:write") == 1)
end

function T.rewritePreservesUnreadableFile()
    History.resetForTests()
    Log.resetCounts()
    stubs.openFails = true
    local originalText = stubs.encode({ id = 7 }) .. "\n"
    stubs.files[History.FILE] = originalText
    local originalRead, originalGlob = fs.read, fs.glob
    local pattern
    fs.read = function(path)
        if path == History.FILE then error("read denied") end
        return originalRead(path)
    end
    fs.glob = function(value) pattern = value; return { History.FILE } end
    local ok, result = pcall(History.append, { id = 1 })
    fs.read, fs.glob = originalRead, originalGlob
    assert(ok and result == false)
    assert(pattern == [[MyHuntReport\\history\.jsonl]])
    assert(stubs.files[History.FILE] == originalText)
    assert(countLogs("history file exists but could not be read; append skipped") == 1)
    assert(Log.count("history:unreadable") == 1)
end

function T.rewriteCreatesConfirmedMissingFile()
    History.resetForTests()
    Log.resetCounts()
    stubs.openFails = true
    local originalGlob = fs.glob
    local pattern
    fs.glob = function(value) pattern = value; return {} end
    local ok, result = pcall(History.append, { id = 1 })
    fs.glob = originalGlob
    assert(ok and result == true)
    assert(pattern == [[MyHuntReport\\history\.jsonl]])
    assert(stubs.files[History.FILE] == stubs.encode({ id = 1 }) .. "\n")
end

function T.lateFallbackLogsOnce()
    History.resetForTests()
    Log.resetCounts()
    assert(History.append({ id = 1 }) == true)
    stubs.openFails = true
    assert(History.append({ id = 2 }) == true)
    assert(History.appendMode() == false)
    assert(countLogs("using rewrite") == 1)
    assert(History.append({ id = 3 }) == true)
    assert(countLogs("using rewrite") == 1)
    assert(stubs.files[History.FILE] == stubs.encode({ id = 1 }) .. "\n"
        .. stubs.encode({ id = 2 }) .. "\n" .. stubs.encode({ id = 3 }) .. "\n")
end

function T.rewriteAbortsWhenAbsenceCannotBeConfirmed()
    local originalRead, originalGlob = fs.read, fs.glob
    local cases = {
        { read = function() return false end, glob = function() return { History.FILE } end },
        { read = function() error("read denied") end, glob = function() error("glob denied") end },
        { read = function() return nil end, glob = function() return false end },
    }
    for _, case in ipairs(cases) do
        History.resetForTests()
        Log.resetCounts()
        stubs.logLines = {}
        stubs.openFails = true
        stubs.files[History.FILE] = "preserve existing bytes"
        fs.read, fs.glob = case.read, case.glob
        local ok, result = pcall(History.append, { id = 1 })
        fs.read, fs.glob = originalRead, originalGlob
        assert(ok and result == false)
        assert(stubs.files[History.FILE] == "preserve existing bytes")
        assert(countLogs("could not be read") == 1)
        assert(Log.count("history:unreadable") == 1)
    end
end

function T.clearTruncatesHistoryWithoutChangingAppendState()
    for _, mode in ipairs({ "unknown", "append", "rewrite" }) do
        History.resetForTests()
        Log.resetCounts()
        stubs.logLines = {}
        stubs.openFails = mode == "rewrite"
        if mode ~= "unknown" then assert(History.append({ id = 1 })) end
        local before = History.appendMode()
        local logs = #stubs.logLines
        stubs.files[History.FILE] = "old records\n"
        assert(History.clear() == true)
        assert(stubs.files[History.FILE] == "")
        assert(#History.readAll() == 0)
        assert(History.appendMode() == before)
        assert(#stubs.logLines == logs)
        assert(History.append({ id = 2 }))
        local entries = History.readAll()
        assert(#entries == 1 and entries[1].id == 2)
        assert(#stubs.logLines == logs)
    end
end

function T.clearCreatesEmptyMissingFile()
    History.resetForTests()
    assert(stubs.files[History.FILE] == nil)
    assert(History.clear() == true)
    assert(stubs.files[History.FILE] == "")
    assert(History.appendMode() == nil)
end

function T.clearFailureReturnsFalseAndLogsOnce()
    for _, failure in ipairs({
        function() error("disk full", 0) end,
        function() return false end,
    }) do
        History.resetForTests()
        Log.resetCounts()
        stubs.logLines = {}
        assert(History.append({ id = 1 }))
        local before = stubs.files[History.FILE]
        local write = fs.write
        fs.write = failure
        local ok, result = pcall(History.clear)
        fs.write = write
        assert(ok and result == false)
        assert(stubs.files[History.FILE] == before and History.appendMode() == true)
        assert(#stubs.logLines == 1 and Log.count("history:clear") == 1)
        assert(stubs.logLines[1]:find("history clear failed: ", 1, true))
    end
end

function T.appendOmitsDiagnosticsWithoutTouchingTheSnapshot()
    History.resetForTests()
    local snapshot = { id = 1, diagnostics = { weightFallbacks = 2 } }
    assert(History.append(snapshot) == true)
    assert(snapshot.diagnostics.weightFallbacks == 2)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].id == 1)
    assert(entries[1].diagnostics == nil, "diagnostics must not be persisted")
end

return T
