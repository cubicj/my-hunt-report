local Log = require("MyHuntReport.Log")

local History = {}

History.FILE = "MyHuntReport/history.jsonl"

local appendSupported = nil
local fallbackLogged = false

local function appendLine(line, path)
    local okOpen, file, openErr = pcall(io.open, path, "a")
    if not okOpen then return false, file, "open" end
    if not file then return false, openErr, "open" end
    local okWrite, written, writeErr = pcall(function()
        return file:write(line, "\n")
    end)
    local okClose, closed, closeErr = pcall(function()
        return file:close()
    end)
    if not okWrite then return false, written, "write" end
    if not written then return false, writeErr, "write" end
    if not okClose then return false, closed, "write" end
    if not closed then return false, closeErr, "write" end
    return true
end

local function rewriteWithLine(line, path)
    local okRead, existing = pcall(fs.read, path)
    local text = ""
    if okRead and type(existing) == "string" then
        text = existing
    else
        local pattern = path:gsub("%.", [[\.]]):gsub("/", [[\\]])
        local okGlob, matches = pcall(fs.glob, pattern)
        if not okGlob or type(matches) ~= "table" or next(matches) ~= nil then
            return false, "history file exists but could not be read; append skipped", "history:unreadable"
        end
    end
    if #text > 0 and text:sub(-1) ~= "\n" then text = text .. "\n" end
    local ok, result = pcall(fs.write, path, text .. line .. "\n")
    if not ok or result == false then return false, result end
    return true
end

local function withoutDiagnostics(snapshot)
    if type(snapshot) ~= "table" or snapshot.diagnostics == nil then return snapshot end
    local copy = {}
    for key, value in pairs(snapshot) do
        if key ~= "diagnostics" then copy[key] = value end
    end
    return copy
end

function History.append(snapshot)
    local path = History.FILE
    local okEncode, line = pcall(json.dump_string, withoutDiagnostics(snapshot), -1)
    if not okEncode or type(line) ~= "string" or #line == 0 then
        Log.error("history encode failed: " .. tostring(line), "history:encode")
        return false
    end
    if appendSupported ~= false then
        local ok, err, stage = appendLine(line, path)
        if ok then
            appendSupported = true
            return true
        end
        if stage == "write" then
            Log.error("history append failed after open: " .. tostring(err), "history:partial")
            return false
        end
        if not fallbackLogged then
            Log.error("history append mode unavailable, using rewrite: " .. tostring(err), "history:append")
            fallbackLogged = true
        end
        appendSupported = false
    end
    local ok, err, key = rewriteWithLine(line, path)
    if not ok then
        if key == "history:unreadable" then
            Log.error(err, key)
        else
            Log.error("history write failed: " .. tostring(err), "history:write")
        end
        return false
    end
    return true
end

function History.clear()
    local ok, err = pcall(fs.write, History.FILE, "")
    if not ok or err == false then
        Log.error("history clear failed: " .. tostring(err), "history:clear")
        return false
    end
    return true
end

function History.readAll()
    local path = History.FILE
    local entries = {}
    local okRead, text = pcall(fs.read, path)
    if not okRead or type(text) ~= "string" then return entries, 0 end
    local skipped = 0
    for line in text:gmatch("[^\n]+") do
        if line:match("%S") then
            local okParse, value = pcall(json.load_string, line)
            if okParse and type(value) == "table" then
                entries[#entries + 1] = value
            else
                skipped = skipped + 1
            end
        end
    end
    if skipped > 0 then
        Log.error("history: skipped " .. skipped .. " unreadable lines", "history:skipped")
    end
    return entries, skipped
end

function History.appendMode()
    return appendSupported
end

function History.resetForTests()
    appendSupported = nil
    fallbackLogged = false
end

return History
