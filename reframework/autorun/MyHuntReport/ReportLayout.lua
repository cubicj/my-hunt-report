local Theme = require("MyHuntReport.Theme")

local ReportLayout = {}

local EDGE_MARGIN = 64

function ReportLayout.placement(settings, display)
    local x, y = tonumber(settings.windowX) or -1, tonumber(settings.windowY) or -1
    if x < 0 or y < 0 then return { centered = true } end
    local maxX = math.max(0, (display and display.x or 0) - EDGE_MARGIN)
    local maxY = math.max(0, (display and display.y or 0) - EDGE_MARGIN)
    return { centered = false, x = math.min(x, maxX), y = math.min(y, maxY) }
end

function ReportLayout.rowAreaLayout(rowCount, displayHeight_, scale, rowHeightPx)
    scale = scale or 1
    local count = rowCount or 0
    local rowHeight
    if rowHeightPx then
        rowHeight = math.floor(rowHeightPx * scale + 0.5)
    else
        rowHeight = math.floor(18 * scale + 0.5) + Theme.metrics.rowSpacing
    end
    local cap = math.max(1, math.floor((displayHeight_ or 1080) * 0.5 / rowHeight))
    local visible = math.max(1, math.min(count, cap))
    return {
        rowHeight = rowHeight,
        visibleRows = visible,
        scrolls = count > cap,
        height = rowHeight * visible + 4,
        scale = scale,
    }
end

function ReportLayout.barSegments(width, shares, gap)
    local segments = {}
    for _, item in ipairs(shares or {}) do
        local w = math.floor((item.share or 0) * width)
        if w >= 1 then segments[#segments + 1] = { id = item.id, color = item.color, width = w } end
    end
    local gaps = math.max(0, #segments - 1) * gap
    local used = gaps
    for _, segment in ipairs(segments) do used = used + segment.width end
    while used > width and #segments > 0 do
        local last = segments[#segments]
        local trimmed = last.width - (used - width)
        if trimmed >= 1 then
            last.width = trimmed
            used = width
        else
            used = used - last.width
            if #segments > 1 then used = used - gap end
            table.remove(segments)
        end
    end
    local x = 0
    for index, segment in ipairs(segments) do
        segment.x = x
        x = x + segment.width
        if index < #segments then x = x + gap end
    end
    return { segments = segments, track = { x = x, width = math.max(0, width - x) } }
end

function ReportLayout.historyColumns(width, scale, scrolls, outcomeWidth)
    local m = Theme.metrics
    local buttonWidth = width - (scrolls and m.scrollbarWidth or 0)
    local inner = buttonWidth - m.historyPadding * 2
    local time = math.floor(m.historyTimeWidth * scale + 0.5)
    local stars = math.floor(m.historyStarsWidth * scale + 0.5)
    local rest = inner - time - stars - m.historyGap * 3
    local weapons = math.floor(rest * m.historyWeaponShare)
    local x = m.historyPadding
    local columns = { buttonWidth = buttonWidth }
    columns.time = { x = x, width = time }
    x = x + time + m.historyGap
    columns.weapons = { x = x, width = weapons }
    x = x + weapons + m.historyGap
    columns.stars = { x = x, width = stars }
    x = x + stars + m.historyGap
    columns.monsters = { x = x, width = rest - weapons - outcomeWidth - m.historyGap }
    columns.outcome = { x = buttonWidth - m.historyPadding - outcomeWidth, width = outcomeWidth }
    return columns
end

function ReportLayout.tileLayout(widths, totalWidth, minGap)
    local layout = {}
    local count = #widths
    if count == 0 then return layout end
    local maxWidth = 0
    for _, width in ipairs(widths) do
        if width > maxWidth then maxWidth = width end
    end
    local columns = count
    if maxWidth + minGap > math.floor(totalWidth / count) then
        columns = math.max(1, math.floor(totalWidth / (maxWidth + minGap)))
    end
    local columnWidth = math.floor(totalWidth / columns)
    for index = 1, count do
        layout[index] = { row = (index - 1) // columns + 1, x = columnWidth * ((index - 1) % columns) }
    end
    return layout
end

function ReportLayout.wrapBreaks(widths, totalWidth, gap)
    local breaks = {}
    local used = 0
    for index, width in ipairs(widths) do
        if index == 1 then
            breaks[index] = false
            used = width
        elseif used + gap + width > totalWidth then
            breaks[index] = true
            used = width
        else
            breaks[index] = false
            used = used + gap + width
        end
    end
    return breaks
end

return ReportLayout
