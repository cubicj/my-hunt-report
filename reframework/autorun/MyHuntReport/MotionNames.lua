local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Locale = require("MyHuntReport.Locale")

local MotionNames = {}

local WEAPON_TYPE_COUNT = 14
local SUFFIXES = { "Land", "NoCombo", "WeakHit", "Front", "Back", "Left", "Right", "Loop", "End" }

local GUIDE_ALIASES = { [-90670656] = 1763677568 }

local guides = nil
local names = {}

local function scanGuideList(list, table_)
    if not list then return end
    local values = list:getValues()
    for index = 0, values:get_Count() - 1 do
        local entry = values:get_Item(index)
        if entry then
            local guideId, guid = entry._Action, entry._ActionName
            if type(guideId) == "number" and guid ~= nil then table_[guideId] = guid end
        end
    end
end

local function loadGuides()
    local table_ = {}
    local manager = Game.singleton("app.VariousDataManager")
    if not manager then
        Log.error("VariousDataManager unavailable for action guide names", "motion:manager")
        return table_, false
    end
    local ok, err = pcall(function()
        local dataset = manager._Setting._ActionGuideSetting
        if not dataset then return end
        scanGuideList(dataset._ActionGuideName_Common, table_)
        for weaponType = 0, WEAPON_TYPE_COUNT - 1 do
            scanGuideList(dataset[string.format("_ActionGuideName_Wp%02d", weaponType)], table_)
        end
    end)
    if not ok then Log.error("action guide scan failed: " .. tostring(err), "motion:guides") end
    local count = 0
    for _ in pairs(table_) do count = count + 1 end
    Log.debug("action guide names loaded: " .. count)
    return table_, ok
end

function MotionNames.guideGuid(guideId)
    if guides == nil then
        local table_, ok = loadGuides()
        if ok then guides = table_ end
    end
    if guides == nil then return nil, false end
    return guides[guideId], true
end

function MotionNames.className(action)
    local ok, name = pcall(function() return action:get_type_definition():get_name() end)
    if ok and type(name) == "string" and #name > 0 then return name end
    return nil
end

function MotionNames.describe(action)
    if action == nil then return nil, nil end
    local key = MotionNames.className(action)
    if not key then return nil, nil end
    local okGuide, guideId = pcall(function() return action._ActionGuideID end)
    if not okGuide or type(guideId) ~= "number" then guideId = -1 end
    return key, guideId
end

local function guideText(guideId)
    local guid, available = MotionNames.guideGuid(guideId)
    local text = Game.messageText(guid)
    if Game.isUsableText(text) then return text, available end
    return nil, available
end

function MotionNames.nameFor(key, guideId)
    local cacheKey = Locale.textKey() .. ":" .. key .. ":" .. tostring(guideId)
    local cached = names[cacheKey]
    if cached then return cached, "guide" end
    local name = nil
    local source = "guide"
    local available = false
    if guideId ~= -1 then
        name, available = guideText(guideId)
        local alias = GUIDE_ALIASES[guideId]
        if not name and alias then name, available = guideText(alias) end
    end
    if name then
        if available then names[cacheKey] = name end
    elseif key:find("^cPorterRide") then
        name = Locale.text("motion_riding")
        source = "fixed"
    elseif key:find("^cDamageCatch") then
        name = Locale.text("motion_pinned")
        source = "fixed"
    elseif key:find("^cBattleRide") then
        name = Locale.text("motion_mounting")
        source = "fixed"
    else
        for _, suffix in ipairs(SUFFIXES) do
            if key:sub(-#suffix) == suffix then
                local sibling = key:sub(1, #key - #suffix)
                local prefix = Locale.textKey() .. ":" .. sibling .. ":"
                for siblingKey, siblingName in pairs(names) do
                    if siblingKey:sub(1, #prefix) == prefix then
                        name = siblingName
                        source = "sibling"
                        break
                    end
                end
                break
            end
        end
        if not name then
            name = Locale.text("motion_unmapped")
            source = "unmapped"
        end
    end
    Log.debug(string.format("motion guide=%d class=%s -> %s", guideId, key, name), "motion:" .. cacheKey)
    return name, source
end

function MotionNames.reset()
    guides = nil
    names = {}
end

return MotionNames
