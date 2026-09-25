local stubs = {}

local function serialize(value)
    local kind = type(value)
    if kind == "table" then
        local parts = {}
        if #value > 0 then
            for _, item in ipairs(value) do
                parts[#parts + 1] = serialize(item)
            end
        else
            local keys = {}
            for key in pairs(value) do
                keys[#keys + 1] = key
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, key in ipairs(keys) do
                parts[#parts + 1] = "[" .. serialize(key) .. "]=" .. serialize(value[key])
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif kind == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function stubs.encode(value)
    return serialize(value)
end

function stubs.decode(text)
    local chunk = load("return " .. tostring(text), "stub-json", "t", {})
    if not chunk then return nil end
    local ok, value = pcall(chunk)
    if ok then return value end
    return nil
end

local function fakeFile(name, mode)
    local file = { name = name }
    if mode:find("a", 1, true) then
        file.buffer = stubs.files[name] or ""
    elseif mode:find("w", 1, true) then
        file.buffer = ""
    else
        if stubs.files[name] == nil then
            return nil, name .. ": No such file or directory"
        end
        file.buffer = stubs.files[name]
    end
    function file:write(...)
        for _, piece in ipairs({ ... }) do
            self.buffer = self.buffer .. tostring(piece)
        end
        return self
    end
    function file:read(format)
        if format == "a" or format == "*a" then return self.buffer end
        return nil
    end
    function file:lines()
        if self.buffer == "" then return function() return nil end end
        local text = self.buffer
        if text:sub(-1) ~= "\n" then text = text .. "\n" end
        return text:gmatch("(.-)\n")
    end
    function file:close()
        stubs.files[self.name] = self.buffer
        return true
    end
    return file
end

function stubs.reset()
    stubs.logLines = {}
    stubs.files = {}
    stubs.jsonFiles = {}
    stubs.keysDown = {}
    stubs.openFails = false
    stubs.now = 1700000000
end

function stubs.install()
    stubs.reset()
    log = {
        info = function(message) table.insert(stubs.logLines, message) end,
        error = function(message) table.insert(stubs.logLines, message) end,
        warn = function(message) table.insert(stubs.logLines, message) end,
        debug = function(message) table.insert(stubs.logLines, message) end,
    }
    json = {
        dump_string = function(value) return stubs.encode(value) end,
        load_string = function(text) return stubs.decode(text) end,
        load_file = function(path) return stubs.jsonFiles[path] end,
        dump_file = function(path, value)
            stubs.jsonFiles[path] = stubs.decode(stubs.encode(value))
            return true
        end,
    }
    fs = {
        read = function(path)
            local text = stubs.files[path]
            if text == nil then error("file not found: " .. tostring(path)) end
            return text
        end,
        write = function(path, data) stubs.files[path] = data end,
        glob = function() return {} end,
    }
    io.open = function(name, mode)
        if stubs.openFails then return nil, "sandbox rejected " .. tostring(mode) end
        return fakeFile(name, mode or "r")
    end
    re = {
        on_frame = function() end,
        on_draw_ui = function() end,
        on_config_save = function() end,
        on_script_reset = function() end,
    }
    imgui = setmetatable({
        get_cursor_pos = function() return { x = 0, y = 0 } end,
        get_cursor_screen_pos = function() return { x = 0, y = 0 } end,
        set_cursor_pos = function() end,
        set_cursor_screen_pos = function() end,
        calc_text_size = function() return { x = 0, y = 0 } end,
        get_window_pos = function() return { x = 0, y = 0 } end,
        get_display_size = function() return { x = 1920, y = 1080 } end,
        invisible_button = function() return false end,
    }, { __index = function() return function() return false end end })
    reframework = {
        is_key_down = function(key) return stubs.keysDown[key] == true end,
        is_drawing_ui = function() return false end,
    }
    sdk = setmetatable({}, { __index = function() return function() return nil end end })
    Vector2f = { new = function(x, y) return { x = x, y = y } end }
    stubs.realTime = stubs.realTime or os.time
    os.time = function(...)
        if select("#", ...) > 0 then return stubs.realTime(...) end
        return stubs.now
    end
    sdk.typeof = function(name) return { typeName = name } end
end

function stubs.drawList()
    local list = { calls = {} }
    local function record(name)
        return function(self, ...)
            assert(self == list, "draw list methods must be called with a colon")
            self.calls[#self.calls + 1] = { name = name, ... }
        end
    end
    list.add_rect_filled = record("add_rect_filled")
    list.add_circle_filled = record("add_circle_filled")
    list.add_line = record("add_line")
    list.add_text = record("add_text")
    return list
end

return stubs
