local Theme = require("MyHuntReport.Theme")
local Draw = require("MyHuntReport.Draw")
local Fonts = require("MyHuntReport.Fonts")
local Locale = require("MyHuntReport.Locale")
local Format = require("MyHuntReport.Format")
local Settings = require("MyHuntReport.Settings")
local Log = require("MyHuntReport.Log")
local History = require("MyHuntReport.History")
local Game = require("MyHuntReport.Game")
local Hdr = require("MyHuntReport.Hdr")

local ReportWindow = {}

local WINDOW_ID = "##MyHuntReportWindow"
local COND_APPEARING = 8
local REFRESH_INTERVAL = 0.25
local POSITION_SETTLE_SECONDS = 1.0
local ELEMENT_LABELS = {
    [1] = "avg_hitzone_fire", [2] = "avg_hitzone_water", [3] = "avg_hitzone_thunder",
    [4] = "avg_hitzone_ice", [5] = "avg_hitzone_dragon",
}

local state = {
    open = false,
    snapshot = nil,
    notSaved = false,
    liveSnapshot = nil,
    liveNotSaved = nil,
    view = "report",
    entries = nil,
    fromHistory = false,
    provider = nil,
    relabeler = nil,
    pendingAction = nil,
    liveRefreshAt = nil,
    bounds = nil,
    livePosition = nil,
    positionSettledAt = nil,
    placementLogged = false,
}

local function L(key)
    return Locale.text(key)
end

local function coloredText(text, color)
    local pushed = pcall(imgui.push_style_color, 0, color)
    local ok, err = pcall(imgui.text, text)
    if pushed then pcall(imgui.pop_style_color, 1) end
    if not ok then error(err, 0) end
end

local function textWidth(text)
    local ok, size = pcall(imgui.calc_text_size, text)
    if ok and size and type(size.x) == "number" then return size.x end
    return nil
end

local function trimUtf8(text)
    local length = #text
    if length == 0 then return text end
    local cut = length
    while cut > 1 do
        local byte = text:byte(cut)
        if byte < 0x80 or byte > 0xBF then break end
        cut = cut - 1
    end
    return text:sub(1, cut - 1)
end

local function clipName(text, maxWidth)
    local width = textWidth(text)
    if not width or width <= maxWidth then return text end
    local ellipsis = "…"
    local body = text
    while #body > 0 do
        body = trimUtf8(body)
        local candidate = body .. ellipsis
        local w = textWidth(candidate)
        if not w then return text end
        if w <= maxWidth then return candidate end
    end
    return ellipsis
end

local function textIn(font, text, color)
    local pushed = Fonts.push(font)
    local ok, err = pcall(coloredText, text, color or Theme.colors.text)
    Fonts.pop(pushed)
    if not ok then error(err, 0) end
end

local function moveCursor(dx, dy)
    local pos = imgui.get_cursor_pos()
    imgui.set_cursor_pos(Vector2f.new(pos.x + dx, pos.y + dy))
end

local function verticalGap(pixels)
    moveCursor(0, pixels)
end

local function sameLineGap(pixels)
    imgui.same_line()
    moveCursor(pixels - Theme.metrics.itemSpacing, 0)
end

local function sectionLabel(id, text, ctx, width)
    verticalGap(Theme.metrics.sectionGap)
    local pushed = Fonts.push(ctx.fonts.small)
    local textW = textWidth(text) or 0
    Fonts.pop(pushed)
    local origin = imgui.get_cursor_pos()
    textIn(ctx.fonts.small, text, Theme.colors.textMuted)
    imgui.same_line()
    imgui.set_cursor_pos(Vector2f.new(origin.x + textW + Theme.metrics.ruleGap, origin.y))
    local screen = imgui.get_cursor_screen_pos()
    local ruleWidth = math.max(1, (width or ctx.width) - textW - Theme.metrics.ruleGap)
    imgui.invisible_button("##rule" .. id, { ruleWidth, ctx.sizes.small })
    Draw.line("rule" .. id, screen.x, screen.y + ctx.sizes.small / 2, screen.x + ruleWidth, screen.y + ctx.sizes.small / 2, Theme.colors.rule)
    verticalGap(Theme.metrics.labelGap)
end

local LABEL_VALUE_GAP = 6

local function labeledValue(ctx, name, value)
    textIn(ctx.fonts.body, name)
    sameLineGap(LABEL_VALUE_GAP)
    moveCursor(0, ctx.sizes.body - ctx.sizes.meta)
    textIn(ctx.fonts.meta, value, Theme.colors.textMuted)
end

local EDGE_MARGIN = 64

function ReportWindow.placement(settings, display)
    local x, y = tonumber(settings.windowX) or -1, tonumber(settings.windowY) or -1
    if x < 0 or y < 0 then return { centered = true } end
    local maxX = math.max(0, (display and display.x or 0) - EDGE_MARGIN)
    local maxY = math.max(0, (display and display.y or 0) - EDGE_MARGIN)
    return { centered = false, x = math.min(x, maxX), y = math.min(y, maxY) }
end

function ReportWindow.rememberPosition(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    state.livePosition = { x = x, y = y }
end

function ReportWindow.trackPosition(x, y, now)
    local previous = state.livePosition
    ReportWindow.rememberPosition(x, y)
    local current = state.livePosition
    if not current then return false end
    if not previous or previous.x ~= current.x or previous.y ~= current.y then
        state.positionSettledAt = now
        return false
    end
    if state.positionSettledAt and now - state.positionSettledAt >= POSITION_SETTLE_SECONDS then
        state.positionSettledAt = nil
        return ReportWindow.persistPosition()
    end
    return false
end

function ReportWindow.persistPosition()
    local pos = state.livePosition
    if not pos then return false end
    local settings = Settings.get()
    local x, y = math.floor(pos.x + 0.5), math.floor(pos.y + 0.5)
    if settings.windowX == x and settings.windowY == y then return false end
    Settings.set("windowX", x)
    Settings.set("windowY", y)
    return true
end

local function close()
    state.open = false
    ReportWindow.persistPosition()
end

local function displayHeight()
    local ok, display = pcall(imgui.get_display_size)
    if ok and display and type(display.y) == "number" and display.y > 0 then return display.y end
    return 1080
end

function ReportWindow.rowAreaLayout(rowCount, displayHeight_, scale, rowHeightPx)
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

function ReportWindow.barSegments(width, shares, gap)
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

function ReportWindow.historyColumns(width, scale, scrolls)
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
    columns.stars = { x = x, width = stars }
    x = x + stars + m.historyGap
    columns.weapons = { x = x, width = weapons }
    x = x + weapons + m.historyGap
    columns.monsters = { x = x, width = rest - weapons }
    return columns
end

function ReportWindow.statTiles(snapshot)
    local stats = snapshot.stats or {}
    local tiles = {}
    if not (snapshot.quest and snapshot.quest.result == "training") then
        tiles[#tiles + 1] = { label = L("combat_dps"), value = Format.decimal(stats.combatDps, 1) }
    end
    tiles[#tiles + 1] = { label = L("crit_rate"), value = Format.rate(stats.critRate) }
    if type(stats.negativeCritRate) == "number" and stats.negativeCritRate > 0 then
        tiles[#tiles + 1] = { label = L("negative_crit_rate"), value = Format.rate(stats.negativeCritRate) }
    end
    tiles[#tiles + 1] = { label = L("avg_attack"), value = Format.decimal(stats.avgAttack, 1) }
    tiles[#tiles + 1] = { label = L("avg_hitzone"), value = Format.decimal(stats.avgHitzone, 1) }
    if stats.attributeHitzones then
        for _, entry in ipairs(stats.attributeHitzones) do
            tiles[#tiles + 1] = { label = L(ELEMENT_LABELS[entry.attribute] or "avg_attribute_hitzone"), value = Format.decimal(entry.avgHitzone, 1) }
        end
    elseif (stats.attribute or 0) > 0 then
        local key = ELEMENT_LABELS[stats.attribute] or "avg_attribute_hitzone"
        tiles[#tiles + 1] = { label = L(key), value = Format.decimal(stats.avgAttributeHitzone, 1) }
    end
    return tiles
end

function ReportWindow.tileLayout(widths, totalWidth, minGap)
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

function ReportWindow.wrapBreaks(widths, totalWidth, gap)
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

local function resultLabel(result)
    if result == "training" then return L("result_training"), Theme.colors.accent end
    return L("result_quest"), Theme.colors.accent
end

function ReportWindow.resultText(quest)
    quest = quest or {}
    local label, color = resultLabel(quest.result)
    local stars = ""
    if quest.result ~= "training" and type(quest.level) == "number" and quest.level > 0 then
        stars = "★" .. quest.level
        label = label .. " " .. stars
    end
    return label, color, stars
end

local function weaponNames(quest)
    quest = quest or {}
    local names = {}
    for _, weapon in ipairs(type(quest.weapons) == "table" and quest.weapons or {}) do
        if type(weapon.name) == "string" and #weapon.name > 0 then names[#names + 1] = weapon.name end
    end
    if #names > 0 then return table.concat(names, ", ") end
    if type(quest.weapon) == "table" and type(quest.weapon.name) == "string" and #quest.weapon.name > 0 then
        return quest.weapon.name
    end
    return L("weapon_unknown")
end

local function monsterNames(list)
    local names = {}
    for _, monster in ipairs(type(list) == "table" and list or {}) do
        names[#names + 1] = tostring(monster.name or monster.id)
    end
    return table.concat(names, ", ")
end

function ReportWindow.headerWeaponText(quest)
    return weaponNames(quest)
end

function ReportWindow.metaText(snapshot)
    snapshot = snapshot or {}
    local quest = snapshot.quest or {}
    local time = Format.duration(quest.elapsedSeconds or 0)
    local monsters = monsterNames(snapshot.monsters)
    if monsters == "" then return time end
    return monsters .. " · " .. time
end

function ReportWindow.historyRow(entry)
    entry = entry or {}
    local quest = entry.quest or {}
    local _, _, stars = ReportWindow.resultText(quest)
    return {
        time = Format.clock(quest.endedAt or 0),
        stars = stars,
        weapons = weaponNames(quest),
        monsters = monsterNames(entry.monsters),
    }
end

function ReportWindow.shareText(value, total)
    if type(value) ~= "number" then return "-" end
    return Format.percent(total > 0 and value / total or 0)
end

function ReportWindow.skillDamageName(kind)
    return L("skill_damage_" .. tostring(kind))
end

local function drawRows(idPrefix, rows, columnWidth, layout)
    local token = Theme.pushRows()
    local okBegin, beginErr = pcall(imgui.begin_child_window, idPrefix .. "##rows", { columnWidth, layout.height }, false, 0)
    if not okBegin then
        Theme.popRows(token)
        error(beginErr, 0)
    end
    local ok, err = pcall(function()
        local rightEdge = columnWidth - 4 - (layout.scrolls and Theme.metrics.scrollbarWidth or 0)
        local percentWidth = math.floor(Theme.metrics.percentColumnWidth * layout.scale)
        for index, row in ipairs(rows) do
            imgui.push_id(idPrefix .. index)
            local okRow, rowErr = pcall(function()
                local screen = imgui.get_cursor_screen_pos()
                if index % 2 == 1 then
                    Draw.rect("stripe" .. idPrefix .. index, screen.x, screen.y - Theme.metrics.rowSpacing / 2,
                        columnWidth - (layout.scrolls and Theme.metrics.scrollbarWidth or 0), layout.rowHeight,
                        Theme.colors.rowStripe, Theme.metrics.stripeRounding, Draw.CORNERS.all)
                end
                local percent = Format.percent(row.share)
                if row.valueKind == "hp" then percent = "HP " .. percent end
                local w = textWidth(percent)
                local nameWidth = rightEdge - math.max(percentWidth, w or 0) - 8
                imgui.text(clipName(tostring(row.name), nameWidth))
                imgui.same_line()
                local x = w and (rightEdge - w) or (rightEdge - percentWidth)
                imgui.set_cursor_pos(Vector2f.new(x, imgui.get_cursor_pos().y))
                coloredText(percent, Theme.colors.text)
            end)
            imgui.pop_id()
            if not okRow then error(rowErr, 0) end
        end
    end)
    pcall(imgui.end_child_window)
    Theme.popRows(token)
    if not ok then error(err, 0) end
end

local function drawHeader(snapshot, ctx)
    local quest = snapshot.quest or {}
    textIn(ctx.fonts.header, ReportWindow.headerWeaponText(quest))
    imgui.same_line()
    moveCursor(Theme.metrics.chipGap - Theme.metrics.itemSpacing, ctx.sizes.header - ctx.sizes.body)
    local label, color = ReportWindow.resultText(quest)
    textIn(ctx.fonts.body, label, color)
end

local function drawMeta(snapshot, ctx)
    textIn(ctx.fonts.meta, ReportWindow.metaText(snapshot), Theme.colors.textMuted)
end

local function drawStats(snapshot, ctx)
    verticalGap(Theme.metrics.sectionGap)
    local tiles = ReportWindow.statTiles(snapshot)
    local widths, measured = {}, true
    for index, tile in ipairs(tiles) do
        local pushed = Fonts.push(ctx.fonts.small)
        local labelWidth = textWidth(tile.label)
        Fonts.pop(pushed)
        pushed = Fonts.push(ctx.fonts.header)
        local valueWidth = textWidth(tile.value)
        Fonts.pop(pushed)
        if labelWidth and valueWidth then
            widths[index] = math.ceil(math.max(labelWidth, valueWidth))
        else
            measured = false
        end
    end
    local minGap = math.floor(Theme.metrics.tileGap * ctx.scale)
    if not measured then
        for index = 1, #tiles do widths[index] = 0 end
        minGap = 0
    end
    local layout = ReportWindow.tileLayout(widths, ctx.width, minGap)
    local origin = imgui.get_cursor_pos()
    local first = 1
    while first <= #tiles do
        if first > 1 then verticalGap(Theme.metrics.sectionGap) end
        local labelY = imgui.get_cursor_pos().y
        local last = first
        while last < #tiles and layout[last + 1].row == layout[first].row do last = last + 1 end
        for index = first, last do
            imgui.set_cursor_pos(Vector2f.new(origin.x + layout[index].x, labelY))
            textIn(ctx.fonts.small, tiles[index].label, Theme.colors.textMuted)
        end
        local valueY = imgui.get_cursor_pos().y
        for index = first, last do
            imgui.set_cursor_pos(Vector2f.new(origin.x + layout[index].x, valueY))
            textIn(ctx.fonts.header, tiles[index].value)
        end
        first = last + 1
    end
end

local DAMAGE_TYPES = {
    { id = "phys", key = "physical", field = "physical", color = "physical" },
    { id = "elem", key = "element", field = "element", color = "element" },
    { id = "fixed", key = "fixed", field = "fixed", color = "fixed" },
    { id = "stat", key = "status", field = "status", color = "status" },
}

local function drawDamageBar(damage, ctx)
    local m = Theme.metrics
    local total = damage.total or 0
    local shares = {}
    for index, kind in ipairs(DAMAGE_TYPES) do
        local value = damage[kind.field] or 0
        shares[index] = { id = kind.id, color = Theme.colors[kind.color], share = total > 0 and value / total or 0 }
    end
    local layout = ReportWindow.barSegments(ctx.width, shares, m.barGap)
    local screen = imgui.get_cursor_screen_pos()
    imgui.invisible_button("##damagebar", { ctx.width, m.barHeight })
    local radius = m.barHeight / 2
    Draw.rect("bartrack", screen.x, screen.y, ctx.width, m.barHeight, Theme.colors.barTrack, radius, Draw.CORNERS.all)
    local count = #layout.segments
    for index, segment in ipairs(layout.segments) do
        local corners = Draw.CORNERS.none
        if count == 1 then
            corners = Draw.CORNERS.all
        elseif index == 1 then
            corners = Draw.CORNERS.left
        elseif index == count then
            corners = Draw.CORNERS.right
        end
        Draw.rect("bar" .. segment.id, screen.x + segment.x, screen.y, segment.width, m.barHeight, segment.color, radius, corners)
    end
end

local function drawLegend(damage, ctx)
    local m = Theme.metrics
    local total = damage.total or 0
    for index, kind in ipairs(DAMAGE_TYPES) do
        if index > 1 then sameLineGap(m.legendGap) end
        local origin = imgui.get_cursor_pos()
        local screen = imgui.get_cursor_screen_pos()
        imgui.invisible_button("##dot" .. kind.id, { m.dotRadius * 2, ctx.sizes.body })
        Draw.dot("dot" .. kind.id, screen.x + m.dotRadius, screen.y + ctx.sizes.body / 2, m.dotRadius, Theme.colors[kind.color])
        imgui.set_cursor_pos(Vector2f.new(origin.x + m.dotRadius * 2 + 8, origin.y))
        labeledValue(ctx, L(kind.key), ReportWindow.shareText(damage[kind.field], total))
    end
end

local function drawSkillDamage(snapshot, ctx)
    local items, widths, measured = {}, {}, true
    if type(snapshot.skillDamage) == "table" then
        for index, row in ipairs(snapshot.skillDamage) do
            items[index] = { name = ReportWindow.skillDamageName(row.kind), value = Format.percent(row.share) }
        end
    end
    local palico = snapshot.palico
    if type(palico) == "table" and type(palico.share) == "number" and palico.share > 0 then
        items[#items + 1] = { name = L("palico_share"), value = Format.percent(palico.share) }
    end
    if #items == 0 then return end
    for index, item in ipairs(items) do
        local pushed = Fonts.push(ctx.fonts.body)
        local nameWidth = textWidth(item.name)
        Fonts.pop(pushed)
        pushed = Fonts.push(ctx.fonts.meta)
        local valueWidth = textWidth(item.value)
        Fonts.pop(pushed)
        if nameWidth and valueWidth then
            widths[index] = math.ceil(nameWidth + LABEL_VALUE_GAP + valueWidth)
        else
            measured = false
        end
    end
    local breaks = measured and ReportWindow.wrapBreaks(widths, ctx.width, Theme.metrics.procGap) or {}
    for index, item in ipairs(items) do
        if index > 1 and not breaks[index] then sameLineGap(Theme.metrics.procGap) end
        labeledValue(ctx, item.name, item.value)
    end
end

local function drawDamage(snapshot, ctx)
    local damage = snapshot.damage or {}
    sectionLabel("damage", L("damage_types"), ctx)
    drawDamageBar(damage, ctx)
    drawLegend(damage, ctx)
    drawSkillDamage(snapshot, ctx)
end

local function drawBody(snapshot, ctx)
    local columnWidth = math.floor((ctx.width - Theme.metrics.columnGap) / 2)
    local skills, motions = snapshot.skills or {}, snapshot.motions or {}
    local layout = ReportWindow.rowAreaLayout(math.max(#skills, #motions), displayHeight(), ctx.scale)
    imgui.begin_group()
    local ok, err = pcall(function()
        sectionLabel("skills", L("skills_header"), ctx, columnWidth)
        drawRows("skill", skills, columnWidth, layout)
    end)
    imgui.end_group()
    if not ok then error(err, 0) end
    imgui.same_line()
    moveCursor(Theme.metrics.columnGap - Theme.metrics.itemSpacing, 0)
    imgui.begin_group()
    ok, err = pcall(function()
        sectionLabel("motions", L("motions_header"), ctx, columnWidth)
        drawRows("motion", motions, columnWidth, layout)
    end)
    imgui.end_group()
    if not ok then error(err, 0) end
end

local function returnFromHistory()
    if state.view == "history" then
        state.snapshot = state.liveSnapshot
        state.notSaved = state.liveNotSaved
        state.liveSnapshot = nil
        state.liveNotSaved = nil
        state.view = "report"
        state.fromHistory = false
        state.entries = nil
    elseif state.fromHistory then
        state.view = "history"
        state.fromHistory = false
    end
end

function ReportWindow.drawTopBar(ctx)
    local top = imgui.get_cursor_pos()
    local m = Theme.metrics
    local action
    if state.view == "history" or state.fromHistory then
        imgui.set_cursor_pos({ m.padding, top.y })
        local screen = imgui.get_cursor_screen_pos()
        local active = Draw.active()
        local pushed = pcall(imgui.push_style_color, 0, Theme.colors.textMuted)
        local ok, clicked = pcall(imgui.button, active and "##back" or "<##back", { m.iconButton, m.iconButton })
        if pushed then pcall(imgui.pop_style_color, 1) end
        if not ok then error(clicked, 0) end
        if active then
            local okHover, hovered = pcall(imgui.is_item_hovered)
            local color = okHover and hovered and Theme.colors.text or Theme.colors.textMuted
            local inset = (m.iconButton - m.iconSize) / 2
            Draw.icon("back", "back", screen.x + inset, screen.y + inset, m.iconSize, color, m.iconStroke)
        end
        if clicked then action = returnFromHistory end
    end
    local showHistory = state.view == "report" and not state.fromHistory
    local pushed = pcall(imgui.push_style_color, 0, Theme.colors.textMuted)
    local ok, err = pcall(function()
        if showHistory then
            imgui.set_cursor_pos({ m.padding + ctx.width - m.iconButton - 8 - m.navButtonWidth, top.y })
            local screen = imgui.get_cursor_screen_pos()
            local active = Draw.active()
            local label = L("history")
            if imgui.button(active and "##history" or label, { m.navButtonWidth, m.iconButton }) then action = ReportWindow.showHistory end
            if active then
                local okHover, hovered = pcall(imgui.is_item_hovered)
                local color = okHover and hovered and Theme.colors.text or Theme.colors.textMuted
                local fontPushed = Fonts.push(ctx.fonts.body)
                local width = textWidth(label) or 0
                Draw.text("history", screen.x + (m.navButtonWidth - width) / 2,
                    screen.y + (m.iconButton - ctx.sizes.body) / 2 - Fonts.centerNudge(ctx.sizes.body), color, label)
                Fonts.pop(fontPushed)
            end
        end
        imgui.set_cursor_pos({ m.padding + ctx.width - m.iconButton, top.y })
        local screen = imgui.get_cursor_screen_pos()
        local active = Draw.active()
        if imgui.button(active and "##close" or "X##close", { m.iconButton, m.iconButton }) then action = close end
        if active then
            local okHover, hovered = pcall(imgui.is_item_hovered)
            local color = okHover and hovered and Theme.colors.text or Theme.colors.textMuted
            local inset = (m.iconButton - m.iconSize) / 2
            Draw.icon("close", "close", screen.x + inset, screen.y + inset, m.iconSize, color, m.iconStroke)
        end
    end)
    if pushed then pcall(imgui.pop_style_color, 1) end
    if not ok then error(err, 0) end
    imgui.set_cursor_pos({ m.padding, top.y + m.topBarHeight + m.titleGap })
    if action then state.pendingAction = action end
end

local function drawFooter(snapshot, ctx)
    local showNotSaved = state.notSaved and state.view == "report" and not state.fromHistory
    local showDiagnostics = Log.isDeveloperMode() and snapshot and snapshot.diagnostics
    if not showNotSaved and not showDiagnostics then return end
    verticalGap(Theme.metrics.footerGap)
    local screen = imgui.get_cursor_screen_pos()
    imgui.invisible_button("##footerrule", { ctx.width, 1 })
    Draw.line("footer", screen.x, screen.y, screen.x + ctx.width, screen.y, Theme.colors.rule)
    if showNotSaved then
        textIn(ctx.fonts.meta, L("not_saved"), Theme.colors.warning)
    end
    if showDiagnostics then
        local d = snapshot.diagnostics
        textIn(ctx.fonts.small, string.format("%s: weightFallbacks=%d droppedPending=%d fightingFallback=%s",
            L("diagnostics"), d.weightFallbacks or 0, d.droppedPending or 0,
            tostring(d.fightingFallback == true)), Theme.colors.textMuted)
        local a, n = d.attribution or {}, d.names or {}
        textIn(ctx.fonts.small, string.format("attribution: action=%d shell=%d kinsect=%d slinger=%d",
            a.action or 0, a.shell or 0, a.kinsect or 0, a.slinger or 0), Theme.colors.textMuted)
        textIn(ctx.fonts.small, string.format("weapon-1=%d lastAttack=%d nonattack=%d",
            a.weaponMinus1 or 0, a.lastAttack or 0, a.nonattack or 0), Theme.colors.textMuted)
        textIn(ctx.fonts.small, string.format("names: sibling=%d unmapped=%d", n.sibling or 0, n.unmapped or 0), Theme.colors.textMuted)
    end
end

local function relabelSnapshot(value)
    if not state.relabeler or type(value) ~= "table" then return end
    local ok, err = pcall(state.relabeler, value)
    if not ok then Log.error("snapshot relabel failed: " .. tostring(err), "report:relabel") end
end

local function drawHistory(ctx)
    if state.entries == nil then
        local entries = History.readAll()
        state.entries = {}
        for index = #entries, 1, -1 do
            local entry = entries[index]
            relabelSnapshot(entry)
            state.entries[#state.entries + 1] = entry
        end
    end
    if #state.entries == 0 then
        textIn(ctx.fonts.meta, L("history_empty"), Theme.colors.textMuted)
        return
    end
    local m = Theme.metrics
    local layout = ReportWindow.rowAreaLayout(#state.entries, displayHeight(), ctx.scale, m.historyRowHeight)
    local columns = ReportWindow.historyColumns(ctx.width, ctx.scale, layout.scrolls)
    local token = Theme.pushListRows()
    local okBegin, beginErr = pcall(imgui.begin_child_window, "history##rows", { ctx.width, layout.height }, false, 0)
    if not okBegin then
        Theme.popListRows(token)
        error(beginErr, 0)
    end
    local ok, err = pcall(function()
        for index, entry in ipairs(state.entries) do
            local top = imgui.get_cursor_pos()
            if imgui.button("##history" .. index, { columns.buttonWidth, layout.rowHeight }) then
                state.pendingAction = function()
                    state.snapshot = entry
                    state.view = "report"
                    state.fromHistory = true
                end
            end
            local row = ReportWindow.historyRow(entry)
            local bodyY = top.y + math.floor((layout.rowHeight - ctx.sizes.body) / 2)
            local metaY = top.y + math.floor((layout.rowHeight - ctx.sizes.meta) / 2)
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.time.x, metaY))
            textIn(ctx.fonts.meta, row.time, Theme.colors.textMuted)
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.stars.x, bodyY))
            textIn(ctx.fonts.body, row.stars, Theme.colors.accent)
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.weapons.x, bodyY))
            textIn(ctx.fonts.body, clipName(row.weapons, columns.weapons.width))
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.monsters.x, bodyY))
            textIn(ctx.fonts.body, clipName(row.monsters, columns.monsters.width))
            imgui.set_cursor_pos(Vector2f.new(top.x, top.y + layout.rowHeight))
        end
    end)
    pcall(imgui.end_child_window)
    Theme.popListRows(token)
    if not ok then error(err, 0) end
end

local function drawContents(settings, fonts, sizes)
    local scale = (settings.fontSize or 18) / 18
    local ctx = { fonts = fonts, sizes = sizes, width = math.floor(Theme.metrics.minWindowWidth * scale), scale = scale }
    ReportWindow.drawTopBar(ctx)
    if state.view == "history" then
        textIn(ctx.fonts.header, L("history_title"))
        drawHistory(ctx)
        return
    end
    local snapshot = state.snapshot
    if not snapshot or not snapshot.damage or (snapshot.damage.total or 0) <= 0 then
        textIn(ctx.fonts.header, L("report_title"))
        textIn(ctx.fonts.meta, L("no_data"), Theme.colors.textMuted)
        drawFooter(snapshot, ctx)
        return
    end
    drawHeader(snapshot, ctx)
    drawMeta(snapshot, ctx)
    drawStats(snapshot, ctx)
    drawDamage(snapshot, ctx)
    drawBody(snapshot, ctx)
    drawFooter(snapshot, ctx)
end

function ReportWindow.isLiveSnapshot(snapshot)
    local result = snapshot and snapshot.quest and snapshot.quest.result
    return result == "running" or result == "training"
end

function ReportWindow.refreshLive(now)
    if not state.open or state.view ~= "report" or state.fromHistory then return false end
    if not state.provider or not ReportWindow.isLiveSnapshot(state.snapshot) then return false end
    if state.liveRefreshAt and now - state.liveRefreshAt < REFRESH_INTERVAL then return false end
    state.liveRefreshAt = now
    local ok, produced = pcall(state.provider)
    if not ok then
        Log.error("snapshot provider failed: " .. tostring(produced), "report:provider")
        return false
    end
    if produced then state.snapshot = produced end
    return true
end

function ReportWindow.show(snapshot)
    Locale.refresh()
    state.placementLogged = false
    state.positionSettledAt = nil
    state.snapshot = snapshot
    state.liveSnapshot = nil
    state.liveNotSaved = nil
    state.view = "report"
    state.fromHistory = false
    state.entries = nil
    state.liveRefreshAt = nil
    state.open = true
end

function ReportWindow.onSessionStart(snapshot)
    if state.open and Settings.get().closeOnQuestStart then
        close()
        return "closed"
    end
    return ReportWindow.replaceLiveView(snapshot)
end

function ReportWindow.replaceLiveView(snapshot)
    if not state.open or state.view ~= "report" or state.fromHistory then return false end
    state.snapshot = snapshot
    state.notSaved = false
    state.liveRefreshAt = nil
    return true
end

function ReportWindow.showHistory()
    if state.view ~= "history" and not state.fromHistory then
        state.liveSnapshot = state.snapshot
        state.liveNotSaved = state.notSaved
    end
    state.view = "history"
    state.fromHistory = false
    state.entries = nil
    state.open = true
end

function ReportWindow.onHistoryCleared()
    state.entries = nil
end

function ReportWindow.returnFromHistory()
    returnFromHistory()
end

function ReportWindow.debugState()
    return {
        view = state.view,
        snapshot = state.snapshot,
        notSaved = state.notSaved,
        fromHistory = state.fromHistory,
    }
end

function ReportWindow.setRelabeler(relabeler)
    state.relabeler = relabeler
end

function ReportWindow.onLanguageChanged()
    relabelSnapshot(state.snapshot)
    relabelSnapshot(state.liveSnapshot)
    for _, entry in ipairs(state.entries or {}) do relabelSnapshot(entry) end
    state.liveRefreshAt = nil
end

function ReportWindow.setSnapshotProvider(provider)
    state.provider = provider
end

function ReportWindow.hide()
    close()
end

function ReportWindow.toggle(snapshot)
    if state.open then
        close()
        return
    end
    if snapshot == nil and state.provider then
        local ok, produced = pcall(state.provider)
        if ok then snapshot = produced else Log.error("snapshot provider failed: " .. tostring(produced), "report:provider") end
    end
    ReportWindow.show(snapshot)
end

function ReportWindow.isOpen()
    return state.open
end

function ReportWindow.setNotSaved(flag)
    state.notSaved = flag == true
end

function ReportWindow.bounds()
    local bounds = state.bounds
    if not state.open or not bounds then return nil end
    return bounds.x, bounds.y, bounds.width, bounds.height
end

function ReportWindow.draw()
    state.bounds = nil
    if not state.open then return end
    local settings = Settings.get()
    Theme.apply(Hdr.targetNits(settings.hdrCorrection))
    local textKey = Locale.textKey()
    Locale.refresh()
    if Locale.textKey() ~= textKey then ReportWindow.onLanguageChanged() end
    ReportWindow.refreshLive(Game.uptime())
    local size = settings.fontSize or 18
    Fonts.setMode(Locale.bundledFontCovers())
    local fonts = { header = Fonts.header(size), body = Fonts.body(size), meta = Fonts.meta(size), small = Fonts.small(size) }
    local sizes = { header = Fonts.size("header", size), body = size, meta = Fonts.size("meta", size), small = Fonts.size("small", size) }
    pcall(function()
        local display = imgui.get_display_size()
        local place = ReportWindow.placement(settings, display)
        if not state.placementLogged then
            state.placementLogged = true
            Log.debug(string.format("window placement centered=%s x=%s y=%s settings=%s,%s display=%s,%s",
                tostring(place.centered), tostring(place.x), tostring(place.y),
                tostring(settings.windowX), tostring(settings.windowY), tostring(display.x), tostring(display.y)))
        end
        if place.centered then
            imgui.set_next_window_pos({ display.x / 2, display.y / 2 }, COND_APPEARING, { 0.5, 0.5 })
        else
            imgui.set_next_window_pos({ place.x, place.y }, COND_APPEARING, { 0, 0 })
        end
    end)
    local token = Theme.pushWindow()
    local okBegin, opened = pcall(imgui.begin_window, WINDOW_ID, state.open, Theme.WINDOW_FLAGS)
    if okBegin then
        state.open = opened
        local okPos, pos = pcall(imgui.get_window_pos)
        if okPos and pos and type(pos.x) == "number" and type(pos.y) == "number" then
            ReportWindow.trackPosition(pos.x, pos.y, Game.uptime())
            local okExtent, extent = pcall(imgui.get_window_size)
            if okExtent and extent and type(extent.x) == "number" and type(extent.y) == "number" then
                state.bounds = { x = pos.x, y = pos.y, width = extent.x, height = extent.y }
            end
        end
        if not opened then ReportWindow.persistPosition() end
        local pushedBody = Fonts.push(fonts.body)
        local okDraw, err = pcall(drawContents, settings, fonts, sizes)
        Fonts.pop(pushedBody)
        pcall(imgui.end_window)
        if not okDraw then
            Log.error("report window draw failed: " .. tostring(err), "report:draw")
            close()
        end
    else
        Log.error("report window begin failed: " .. tostring(opened), "report:begin")
        close()
    end
    Theme.popWindow(token)
    local pending = state.pendingAction
    if pending then
        state.pendingAction = nil
        pending()
    end
end

return ReportWindow
