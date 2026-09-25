local Format = {}

function Format.integer(value)
    local rounded = math.floor((tonumber(value) or 0) + 0.5)
    local text = tostring(rounded)
    local sign = ""
    if text:sub(1, 1) == "-" then
        sign = "-"
        text = text:sub(2)
    end
    local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if grouped:sub(1, 1) == "," then grouped = grouped:sub(2) end
    return sign .. grouped
end

function Format.percent(share)
    local value = tonumber(share) or 0
    local text = string.format("%.1f", value * 100)
    if value > 0 and text == "0.0" then return "<0.1%" end
    return text .. "%"
end

function Format.duration(seconds)
    local total = math.floor(tonumber(seconds) or 0)
    if total < 0 then total = 0 end
    local hours = total // 3600
    local minutes = (total % 3600) // 60
    local secs = total % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%d:%02d", minutes, secs)
end

function Format.clock(epoch)
    return os.date("%Y-%m-%d %H:%M", epoch)
end

function Format.decimal(value, digits)
    if type(value) ~= "number" then return "-" end
    return string.format("%." .. tostring(digits or 1) .. "f", value)
end

function Format.rate(share)
    if type(share) ~= "number" then return "-" end
    return Format.percent(share)
end

return Format
