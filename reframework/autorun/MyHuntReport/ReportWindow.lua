local Theme = require("MyHuntReport.Theme")
local Draw = require("MyHuntReport.Draw")
local Fonts = require("MyHuntReport.Fonts")
local Locale = require("MyHuntReport.Locale")
local Format = require("MyHuntReport.Format")
local Settings = require("MyHuntReport.Settings")
local Log = require("MyHuntReport.Log")
local History = require("MyHuntReport.History")
local HistoryFilter = require("MyHuntReport.HistoryFilter")
local HistoryFilterWindow = require("MyHuntReport.HistoryFilterWindow")
local Game = require("MyHuntReport.Game")
local Hdr = require("MyHuntReport.Hdr")
local ReportLayout = require("MyHuntReport.ReportLayout")
local ReportText = require("MyHuntReport.ReportText")
local UiText = require("MyHuntReport.UiText")

local ReportWindow = {}

ReportWindow.placement = ReportLayout.placement
ReportWindow.rowAreaLayout = ReportLayout.rowAreaLayout
ReportWindow.barSegments = ReportLayout.barSegments
ReportWindow.historyColumns = ReportLayout.historyColumns
ReportWindow.tileLayout = ReportLayout.tileLayout
ReportWindow.wrapBreaks = ReportLayout.wrapBreaks
ReportWindow.statTiles = ReportText.statTiles
ReportWindow.resultText = ReportText.resultText
ReportWindow.outcomeText = ReportText.outcomeText
ReportWindow.headerWeaponText = ReportText.headerWeaponText
ReportWindow.metaText = ReportText.metaText
ReportWindow.versionText = ReportText.versionText
ReportWindow.historyRow = ReportText.historyRow
ReportWindow.shareText = ReportText.shareText
ReportWindow.skillDamageName = ReportText.skillDamageName

local WINDOW_ID = "##MyHuntReportWindow"
local COND_APPEARING = 8
local REFRESH_INTERVAL = 0.25
local POSITION_SETTLE_SECONDS = 1.0

local state = {
    open = false,
    snapshot = nil,
    notSaved = false,
    liveSnapshot = nil,
    liveNotSaved = nil,
    view = "report",
    entries = nil,
    fromHistory = false,
    forwardHistory = false,
    forwardSnapshot = nil,
    provider = nil,
    relabeler = nil,
    nameResolver = nil,
    historySelection = { weapons = {}, levels = {}, species = {}, variants = {} },
    historyOptions = nil,
    historyLabels = nil,
    historyChips = {},
    historyActive = false,
    filterOpen = false,
    filterBounds = nil,
    filteredEntries = nil,
    filterChangeCount = 0,
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
    local textW = UiText.width(text) or 0
    Fonts.pop(pushed)
    local origin = imgui.get_cursor_pos()
    UiText.inFont(ctx.fonts.small, text, Theme.colors.textMuted)
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
    UiText.inFont(ctx.fonts.body, name)
    sameLineGap(LABEL_VALUE_GAP)
    moveCursor(0, ctx.sizes.body - ctx.sizes.meta)
    UiText.inFont(ctx.fonts.meta, value, Theme.colors.textMuted)
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

local function clearForward()
    state.forwardHistory, state.forwardSnapshot = false, nil
end

local function close()
    state.filterOpen, state.filterBounds = false, nil
    clearForward()
    state.open = false
    ReportWindow.persistPosition()
end

local function displayHeight()
    local ok, display = pcall(imgui.get_display_size)
    if ok and display and type(display.y) == "number" and display.y > 0 then return display.y end
    return 1080
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
                local w = UiText.width(percent)
                local nameWidth = rightEdge - math.max(percentWidth, w or 0) - 8
                imgui.text(UiText.clip(tostring(row.name), nameWidth))
                imgui.same_line()
                local x = w and (rightEdge - w) or (rightEdge - percentWidth)
                imgui.set_cursor_pos(Vector2f.new(x, imgui.get_cursor_pos().y))
                UiText.colored(percent, Theme.colors.text)
            end)
            imgui.pop_id()
            if not okRow then error(rowErr, 0) end
        end
    end)
    pcall(imgui.end_child_window)
    Theme.popRows(token)
    if not ok then error(err, 0) end
end

local function headerBodyText(ctx, text, color)
    imgui.same_line()
    moveCursor(Theme.metrics.chipGap - Theme.metrics.itemSpacing, ctx.sizes.header - ctx.sizes.body)
    UiText.inFont(ctx.fonts.body, text, color)
end

local function drawHeader(snapshot, ctx)
    local quest = snapshot.quest or {}
    UiText.inFont(ctx.fonts.header, ReportText.headerWeaponText(quest))
    local label, color = ReportText.resultText(quest)
    headerBodyText(ctx, label, color)
    local outcome, outcomeColor = ReportText.outcomeText(quest)
    if outcome then headerBodyText(ctx, outcome, outcomeColor) end
end

local function drawMeta(snapshot, ctx)
    UiText.inFont(ctx.fonts.meta, ReportText.metaText(snapshot), Theme.colors.textMuted)
end

local function drawVersion(snapshot, ctx)
    UiText.inFont(ctx.fonts.meta, ReportText.versionText(snapshot), Theme.colors.textMuted)
end

local function drawStats(snapshot, ctx)
    verticalGap(Theme.metrics.sectionGap)
    local tiles = ReportText.statTiles(snapshot)
    local widths, measured = {}, true
    for index, tile in ipairs(tiles) do
        local pushed = Fonts.push(ctx.fonts.small)
        local labelWidth = UiText.width(tile.label)
        Fonts.pop(pushed)
        pushed = Fonts.push(ctx.fonts.header)
        local valueWidth = UiText.width(tile.value)
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
    local layout = ReportLayout.tileLayout(widths, ctx.width, minGap)
    local origin = imgui.get_cursor_pos()
    local first = 1
    while first <= #tiles do
        if first > 1 then verticalGap(Theme.metrics.sectionGap) end
        local labelY = imgui.get_cursor_pos().y
        local last = first
        while last < #tiles and layout[last + 1].row == layout[first].row do last = last + 1 end
        for index = first, last do
            imgui.set_cursor_pos(Vector2f.new(origin.x + layout[index].x, labelY))
            UiText.inFont(ctx.fonts.small, tiles[index].label, Theme.colors.textMuted)
        end
        local valueY = imgui.get_cursor_pos().y
        for index = first, last do
            imgui.set_cursor_pos(Vector2f.new(origin.x + layout[index].x, valueY))
            UiText.inFont(ctx.fonts.header, tiles[index].value)
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
    local layout = ReportLayout.barSegments(ctx.width, shares, m.barGap)
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
        labeledValue(ctx, L(kind.key), ReportText.shareText(damage[kind.field], total))
    end
end

local function drawSkillDamage(snapshot, ctx)
    local items, widths, measured = {}, {}, true
    for _, row in ipairs(snapshot.sources or {}) do
        items[#items + 1] = { name = row.name, value = Format.percent(row.share) }
    end
    if type(snapshot.skillDamage) == "table" then
        for _, row in ipairs(snapshot.skillDamage) do
            items[#items + 1] = { name = ReportText.skillDamageName(row.kind), value = Format.percent(row.share) }
        end
    end
    local palico = snapshot.palico
    if type(palico) == "table" and type(palico.share) == "number" and palico.share > 0 then
        items[#items + 1] = { name = L("palico_share"), value = Format.percent(palico.share) }
    end
    if #items == 0 then return end
    for index, item in ipairs(items) do
        local pushed = Fonts.push(ctx.fonts.body)
        local nameWidth = UiText.width(item.name)
        Fonts.pop(pushed)
        pushed = Fonts.push(ctx.fonts.meta)
        local valueWidth = UiText.width(item.value)
        Fonts.pop(pushed)
        if nameWidth and valueWidth then
            widths[index] = math.ceil(nameWidth + LABEL_VALUE_GAP + valueWidth)
        else
            measured = false
        end
    end
    local breaks = measured and ReportLayout.wrapBreaks(widths, ctx.width, Theme.metrics.procGap) or {}
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
    local layout = ReportLayout.rowAreaLayout(math.max(#skills, #motions), displayHeight(), ctx.scale)
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
    state.filterOpen, state.filterBounds = false, nil
    if state.view == "history" then
        state.snapshot = state.liveSnapshot
        state.notSaved = state.liveNotSaved
        state.liveSnapshot = nil
        state.liveNotSaved = nil
        state.view = "report"
        state.fromHistory = false
        state.entries = nil
        state.forwardHistory = true
    elseif state.fromHistory then
        state.forwardSnapshot = state.snapshot
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
                local width = UiText.width(label) or 0
                Draw.text("history", screen.x + (m.navButtonWidth - width) / 2,
                    screen.y + (m.iconButton - ctx.sizes.body) / 2 - Fonts.centerNudge(ctx.sizes.body), color, label)
                Fonts.pop(fontPushed)
            end
        end
        if state.view == "history" then
            imgui.set_cursor_pos({ m.padding + ctx.width - m.iconButton * 2 - 8, top.y })
            local screen = imgui.get_cursor_screen_pos()
            local active = Draw.active()
            local color = state.historyActive and Theme.colors.accent or Theme.colors.textMuted
            local colored = pcall(imgui.push_style_color, 0, color)
            local okButton, clicked = pcall(imgui.button, active and "##filter" or L("history_filter"), { m.iconButton, m.iconButton })
            if colored then pcall(imgui.pop_style_color, 1) end
            if not okButton then error(clicked, 0) end
            if active then
                local okHover, hovered = pcall(imgui.is_item_hovered)
                if not state.historyActive and okHover and hovered then color = Theme.colors.text end
                local inset = (m.iconButton - m.iconSize) / 2
                Draw.icon("filter", "filter", screen.x + inset, screen.y + inset, m.iconSize, color, m.iconStroke)
            end
            if clicked then
                action = function()
                    state.filterOpen = not state.filterOpen
                    state.filterBounds = nil
                end
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
        UiText.inFont(ctx.fonts.meta, L("not_saved"), Theme.colors.warning)
    end
    if showDiagnostics then
        local d = snapshot.diagnostics
        UiText.inFont(ctx.fonts.small, string.format("%s: weightFallbacks=%d droppedPending=%d fightingFallback=%s",
            L("diagnostics"), d.weightFallbacks or 0, d.droppedPending or 0,
            tostring(d.fightingFallback == true)), Theme.colors.textMuted)
        local a, n = d.attribution or {}, d.names or {}
        UiText.inFont(ctx.fonts.small, string.format("attribution: action=%d shell=%d kinsect=%d slinger=%d",
            a.action or 0, a.shell or 0, a.kinsect or 0, a.slinger or 0), Theme.colors.textMuted)
        UiText.inFont(ctx.fonts.small, string.format("weapon-1=%d lastAttack=%d nonattack=%d",
            a.weaponMinus1 or 0, a.lastAttack or 0, a.nonattack or 0), Theme.colors.textMuted)
        UiText.inFont(ctx.fonts.small, string.format("names: sibling=%d unmapped=%d", n.sibling or 0, n.unmapped or 0), Theme.colors.textMuted)
    end
end

local function relabelSnapshot(value)
    if not state.relabeler or type(value) ~= "table" then return end
    local ok, err = pcall(state.relabeler, value)
    if not ok then Log.error("snapshot relabel failed: " .. tostring(err), "report:relabel") end
end

local FILTER_AXES = { "weapons", "levels", "species", "variants" }

local function filterName(label, id)
    if state.nameResolver then
        local ok, name = pcall(state.nameResolver, label)
        if ok and type(name) == "string" and #name > 0 then return name end
    end
    return "#" .. tostring(id)
end

local function updateFilteredHistory(changed)
    state.filteredEntries = HistoryFilter.apply(state.entries, state.historySelection)
    state.historyActive = HistoryFilter.isActive(state.historySelection)
    state.historyChips = {}
    local selected = {}
    for _, axis in ipairs(FILTER_AXES) do
        local values = {}
        for _, value in ipairs(state.historyOptions[axis]) do
            if state.historySelection[axis][value] then
                state.historyChips[#state.historyChips + 1] = {
                    axis = axis, value = value, text = state.historyLabels[axis][value],
                    id = "##historyChip" .. axis .. ":" .. tostring(value),
                }
                values[#values + 1] = tostring(value)
            end
        end
        selected[#selected + 1] = axis .. "=[" .. table.concat(values, ",") .. "]"
    end
    if changed and Log.isDeveloperMode() then
        state.filterChangeCount = state.filterChangeCount + 1
        Log.debug(string.format("history filter %s shown=%d/%d", table.concat(selected, " "),
            #state.filteredEntries, #state.entries), "history:filter:" .. state.filterChangeCount)
    end
end

local function changeHistoryFilter(axis, value, checked)
    local changed
    if value == nil then
        changed = HistoryFilter.clear(state.historySelection, axis)
    else
        local selected = state.historySelection[axis]
        changed = (selected[value] == true) ~= (checked == true)
        selected[value] = checked and true or nil
    end
    if changed then updateFilteredHistory(true) end
end

local function rebuildHistoryFilters()
    if state.entries == nil then return end
    local options = HistoryFilter.options(state.entries)
    local names = { weapons = {}, levels = {}, species = {}, variants = {} }
    for _, id in ipairs(options.weapons) do names.weapons[id] = filterName({ kind = "weapon", type = id }, id) end
    for _, id in ipairs(options.species) do names.species[id] = filterName({ kind = "monster", emId = id }, id) end
    for _, level in ipairs(options.levels) do names.levels[level] = "★" .. level end
    for _, variant in ipairs(options.variants) do names.variants[variant] = L("history_variant_" .. variant) end
    table.sort(options.species, function(a, b)
        if names.species[a] == names.species[b] then return a < b end
        return names.species[a] < names.species[b]
    end)
    local changed = HistoryFilter.prune(state.historySelection, options)
    state.historyOptions, state.historyLabels = options, names
    updateFilteredHistory(changed)
end

local function drawHistoryChips(ctx)
    if not state.historyActive then return end
    local pushed = Fonts.push(ctx.fonts.body)
    local ok, err = pcall(function()
        local m = Theme.metrics
        local origin = imgui.get_cursor_pos()
        local x, y = 0, origin.y
        local height = ctx.sizes.body + m.itemSpacing
        for _, chip in ipairs(state.historyChips) do
            local suffix = " ×"
            local suffixWidth = UiText.width(suffix) or ctx.sizes.body
            local text = UiText.clip(chip.text, ctx.width - m.itemSpacing * 2 - suffixWidth) .. suffix
            local width = math.min(ctx.width, (UiText.width(text) or ctx.width - m.itemSpacing * 2) + m.itemSpacing * 2)
            if x > 0 and x + width > ctx.width then
                x, y = 0, y + height + m.itemSpacing
            end
            imgui.set_cursor_pos(Vector2f.new(origin.x + x, y))
            if imgui.button(text .. chip.id, { width, height }) then changeHistoryFilter(chip.axis, chip.value, false) end
            x = x + width + m.historyGap
        end
        imgui.set_cursor_pos(Vector2f.new(origin.x, y + height + m.itemSpacing))
    end)
    Fonts.pop(pushed)
    if not ok then error(err, 0) end
end

local function loadHistory()
    if state.entries ~= nil then return end
    local entries = History.readAll()
    state.entries = {}
    for index = #entries, 1, -1 do
        local entry = entries[index]
        relabelSnapshot(entry)
        state.entries[#state.entries + 1] = entry
    end
    rebuildHistoryFilters()
end

local function drawHistory(ctx)
    if #state.entries == 0 then
        UiText.inFont(ctx.fonts.meta, L("history_empty"), Theme.colors.textMuted)
        return
    end
    drawHistoryChips(ctx)
    local m = Theme.metrics
    local layout = ReportLayout.rowAreaLayout(#state.filteredEntries, displayHeight(), ctx.scale, m.historyRowHeight)
    local columns = ReportLayout.historyColumns(ctx.width, ctx.scale, layout.scrolls)
    local token = Theme.pushListRows()
    local okBegin, beginErr = pcall(imgui.begin_child_window, "history##rows", { ctx.width, layout.height }, false, 0)
    if not okBegin then
        Theme.popListRows(token)
        error(beginErr, 0)
    end
    local ok, err = pcall(function()
        if #state.filteredEntries == 0 then
            UiText.inFont(ctx.fonts.meta, L("history_no_matches"), Theme.colors.textMuted)
        end
        for index, entry in ipairs(state.filteredEntries) do
            local top = imgui.get_cursor_pos()
            if imgui.button("##history" .. index, { columns.buttonWidth, layout.rowHeight }) then
                state.pendingAction = function()
                    clearForward()
                    state.filterOpen, state.filterBounds = false, nil
                    state.snapshot = entry
                    state.view = "report"
                    state.fromHistory = true
                end
            end
            local row = ReportText.historyRow(entry)
            local bodyY = top.y + math.floor((layout.rowHeight - ctx.sizes.body) / 2)
            local metaY = top.y + math.floor((layout.rowHeight - ctx.sizes.meta) / 2)
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.time.x, metaY))
            UiText.inFont(ctx.fonts.meta, row.time, Theme.colors.textMuted)
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.weapons.x, bodyY))
            UiText.inFont(ctx.fonts.body, UiText.clip(row.weapons, columns.weapons.width))
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.stars.x, bodyY))
            UiText.inFont(ctx.fonts.body, row.stars, Theme.colors.accent)
            imgui.set_cursor_pos(Vector2f.new(top.x + columns.monsters.x, bodyY))
            UiText.inFont(ctx.fonts.body, UiText.clip(row.monsters, columns.monsters.width))
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
    if state.view == "history" then loadHistory() end
    ReportWindow.drawTopBar(ctx)
    if state.view == "history" then
        UiText.inFont(ctx.fonts.header, L("history_title"))
        drawHistory(ctx)
        return
    end
    local snapshot = state.snapshot
    if not snapshot or not snapshot.damage or (snapshot.damage.total or 0) <= 0 then
        UiText.inFont(ctx.fonts.header, L("report_title"))
        UiText.inFont(ctx.fonts.meta, L("no_data"), Theme.colors.textMuted)
        drawFooter(snapshot, ctx)
        return
    end
    drawHeader(snapshot, ctx)
    drawMeta(snapshot, ctx)
    drawVersion(snapshot, ctx)
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
    state.filterOpen, state.filterBounds = false, nil
    clearForward()
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

local function enterHistory()
    if state.view ~= "history" and not state.fromHistory then
        state.liveSnapshot = state.snapshot
        state.liveNotSaved = state.notSaved
    end
    state.view = "history"
    state.fromHistory = false
    state.entries = nil
    state.open = true
end

function ReportWindow.showHistory()
    clearForward()
    enterHistory()
end

function ReportWindow.onHistoryCleared()
    state.entries = nil
    clearForward()
end

function ReportWindow.returnFromHistory()
    returnFromHistory()
end

function ReportWindow.screen()
    if not state.open then return nil end
    if state.view == "history" then return "history" end
    if state.fromHistory then return "past" end
    return "live"
end

function ReportWindow.back()
    local screen = ReportWindow.screen()
    if screen == nil or screen == "live" then return false end
    returnFromHistory()
    return true
end

function ReportWindow.forward()
    local screen = ReportWindow.screen()
    if screen == "live" then
        if not state.forwardHistory then return false end
        state.forwardHistory = false
        enterHistory()
        return true
    end
    if screen == "history" then
        local snapshot = state.forwardSnapshot
        if snapshot == nil then return false end
        state.forwardSnapshot = nil
        state.filterOpen, state.filterBounds = false, nil
        relabelSnapshot(snapshot)
        state.snapshot = snapshot
        state.view = "report"
        state.fromHistory = true
        return true
    end
    return false
end

function ReportWindow.debugState()
    return {
        view = state.view,
        snapshot = state.snapshot,
        notSaved = state.notSaved,
        fromHistory = state.fromHistory,
        forwardHistory = state.forwardHistory,
        forwardSnapshot = state.forwardSnapshot,
    }
end

function ReportWindow.setRelabeler(relabeler)
    state.relabeler = relabeler
end

function ReportWindow.setNameResolver(resolve)
    state.nameResolver = resolve
    rebuildHistoryFilters()
end

function ReportWindow.onLanguageChanged()
    relabelSnapshot(state.snapshot)
    relabelSnapshot(state.liveSnapshot)
    for _, entry in ipairs(state.entries or {}) do relabelSnapshot(entry) end
    rebuildHistoryFilters()
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

function ReportWindow.filterBounds()
    local bounds = state.filterBounds
    if not state.open or state.view ~= "history" or not state.filterOpen or not bounds then return nil end
    return bounds.x, bounds.y, bounds.width, bounds.height
end

function ReportWindow.draw()
    state.filterBounds = nil
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
        local place = ReportLayout.placement(settings, display)
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
    if not state.open or state.view ~= "history" then state.filterOpen = false end
    if state.filterOpen then
        local ctx = { fonts = fonts, sizes = sizes, scale = size / 18 }
        state.filterOpen, state.filterBounds = HistoryFilterWindow.draw(ctx, state.historyOptions, state.historyLabels,
            state.historySelection, changeHistoryFilter, state.bounds)
    end
end

return ReportWindow
