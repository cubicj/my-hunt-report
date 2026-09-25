local Hotkey = {}

local CANDIDATE_CODES = {
    8, 9, 13, 16, 17, 18, 19, 20,
    32, 33, 34, 35, 36, 37, 38, 39, 40, 45, 46,
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
    65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
    78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
    96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123,
    124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135,
    144, 145, 186, 187, 188, 189, 190, 191, 192, 219, 220, 221, 222,
}

local KEY_NAMES = {
    [8] = "Backspace", [9] = "Tab", [13] = "Enter", [16] = "Shift",
    [17] = "Ctrl", [18] = "Alt", [19] = "Pause", [20] = "CapsLock",
    [27] = "Esc", [32] = "Space", [33] = "PageUp", [34] = "PageDown",
    [35] = "End", [36] = "Home", [37] = "Left", [38] = "Up",
    [39] = "Right", [40] = "Down", [45] = "Insert", [46] = "Delete",
    [106] = "Num*", [107] = "Num+", [109] = "Num-", [110] = "Num.", [111] = "Num/",
    [144] = "NumLock", [145] = "ScrollLock", [186] = ";", [187] = "=",
    [188] = ",", [189] = "-", [190] = ".", [191] = "/", [192] = "`",
    [219] = "[", [220] = "\\", [221] = "]", [222] = "'",
}

local capturing = false
local armed = nil
local wasDown = false

function Hotkey.beginCapture()
    capturing = true
end

function Hotkey.cancelCapture()
    capturing = false
end

function Hotkey.isCapturing()
    return capturing
end

function Hotkey.update(isKeyDown, toggleKey)
    if capturing then
        if isKeyDown(27) then
            capturing = false
            armed = 27
            return { cancelled = true }
        end
        for _, code in ipairs(CANDIDATE_CODES) do
            if isKeyDown(code) then
                capturing = false
                armed = code
                return { captured = code }
            end
        end
        return nil
    end
    if armed then
        if not isKeyDown(armed) then
            armed = nil
            wasDown = false
        end
        return nil
    end
    local down = isKeyDown(toggleKey) == true
    local toggle = down and not wasDown
    wasDown = down
    if toggle then return { toggle = true } end
    return nil
end

function Hotkey.name(code)
    if KEY_NAMES[code] then return KEY_NAMES[code] end
    if code >= 48 and code <= 57 or code >= 65 and code <= 90 then
        return string.char(code)
    end
    if code >= 96 and code <= 105 then return "Num" .. (code - 96) end
    if code >= 112 and code <= 135 then return "F" .. (code - 111) end
    return "VK " .. tostring(code)
end

return Hotkey
