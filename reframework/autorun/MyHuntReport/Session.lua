local Game = require("MyHuntReport.Game")
local MotionNames = require("MyHuntReport.MotionNames")
local Version = require("MyHuntReport.Version")

local Session = {}

local SKILL_DAMAGE_KINDS = { "flare", "fury", "violent", "ryukiExplosion", "darkWave", "mirrorBlade", "flayer", "elementConvert", "blast", "poison" }
local SKILL_PROC_KINDS = { flayer = true, elementConvert = true }
local STATUS_PROC_KINDS = { blast = true, poison = true }
local FIXED_PROC_KINDS = { woundBreak = true }
local HEAL_KINDS = { "hastenRecovery", "superRecovery" }
local PALICO_PROC_KINDS = { blast = true, poison = true }
local HEAL_KIND_SET = { hastenRecovery = true, superRecovery = true }

local state = nil

local function sortRows(rows)
    table.sort(rows, function(a, b)
        if a.share ~= b.share then return a.share > b.share end
        return tostring(a.name) < tostring(b.name)
    end)
end

function Session.reset(startTime)
    state = {
        startTime = tonumber(startTime) or 0,
        lastHitTime = nil,
        firstHitTime = nil,
        hits = 0,
        total = 0,
        weaponTypes = {},
        weaponSeen = {},
        physical = 0,
        element = 0,
        fixed = 0,
        status = 0,
        totalWeight = 0,
        crittableHits = 0,
        critHits = 0,
        negativeCritHits = 0,
        hitzoneSum = 0,
        hitzoneCount = 0,
        attackSum = 0,
        attackCount = 0,
        attributeHitzones = {},
        fightingSeconds = 0,
        skillDamage = {},
        palico = { hits = 0, direct = 0, blast = 0, poison = 0 },
        monsters = {},
        monsterOrder = {},
        skills = {},
        skillEligible = {},
        heal = {},
        motions = {},
        motionOrder = {},
        procs = {},
        procOrder = {},
        weightFallbacks = 0,
        droppedPending = 0,
        attribution = { action = 0, shell = 0, kinsect = 0, slinger = 0, weaponMinus1 = 0, lastAttack = 0, nonattack = 0 },
    }
end

Session.reset(0)

local function attributionKey(attribution)
    if type(attribution) == "string" and attribution:sub(1, 6) == "shell:" then return "shell" end
    if attribution == "weapon-1" then return "weaponMinus1" end
    if attribution == "kinsect" or attribution == "slinger" or attribution == "lastAttack" or attribution == "nonattack" then
        return attribution
    end
    return "action"
end

local function noteWeaponType(weaponType)
    if weaponType and weaponType >= 0 and not state.weaponSeen[weaponType] then
        state.weaponSeen[weaponType] = true
        state.weaponTypes[#state.weaponTypes + 1] = weaponType
    end
end

local function addDamageStats(hit, physical, element)
    if hit.fixed then
        state.fixed = state.fixed + physical
    else
        state.physical = state.physical + physical
    end
    state.element = state.element + element
    local time = tonumber(hit.time)
    if time then
        state.lastHitTime = time
        if state.firstHitTime == nil then state.firstHitTime = time end
    end
    if hit.canCrit then
        state.crittableHits = state.crittableHits + 1
        if hit.critType == 1 then
            state.critHits = state.critHits + 1
        elseif hit.critType == 2 then
            state.negativeCritHits = state.negativeCritHits + 1
        end
    end
    if not hit.fixed and physical > 0 and type(hit.baseHitzone) == "number" then
        state.hitzoneSum = state.hitzoneSum + hit.baseHitzone
        state.hitzoneCount = state.hitzoneCount + 1
    end
    if not hit.fixed and physical > 0 and type(hit.attackPower) == "number" then
        state.attackSum = state.attackSum + hit.attackPower
        state.attackCount = state.attackCount + 1
    end
    local attribute = tonumber(hit.attribute) or 0
    if attribute > 0 and element > 0 and type(hit.attributeHitzone) == "number" and hit.attributeHitzone > 0 then
        local bucket = state.attributeHitzones[attribute]
        if not bucket then
            bucket = { sum = 0, count = 0 }
            state.attributeHitzones[attribute] = bucket
        end
        bucket.sum = bucket.sum + hit.attributeHitzone
        bucket.count = bucket.count + 1
    end
    for _, extra in ipairs(hit.skillExtras or {}) do
        local amount = tonumber(extra.damage) or 0
        if type(extra.kind) == "string" and amount > 0 then
            state.skillDamage[extra.kind] = (state.skillDamage[extra.kind] or 0) + amount
        end
    end
end

local function addRows(hit, damage)
    local monster = state.monsters[hit.monsterId]
    if not monster then
        monster = { id = hit.monsterId, label = hit.monsterLabel, damage = 0 }
        state.monsters[hit.monsterId] = monster
        state.monsterOrder[#state.monsterOrder + 1] = monster
    end
    monster.damage = monster.damage + damage
    local weight = tonumber(hit.weight) or 0
    state.totalWeight = state.totalWeight + weight
    for skillId in pairs(hit.activeSkills or {}) do
        state.skills[skillId] = (state.skills[skillId] or 0) + weight
    end
    for skillId in pairs(hit.eligibleSkills or {}) do
        state.skillEligible[skillId] = (state.skillEligible[skillId] or 0) + weight
    end
    local motion = state.motions[hit.motionKey]
    if not motion then
        motion = { key = hit.motionKey, label = hit.motionLabel, damage = 0, hits = 0 }
        state.motions[hit.motionKey] = motion
        state.motionOrder[#state.motionOrder + 1] = motion
    end
    motion.damage = motion.damage + damage
    motion.hits = motion.hits + 1
end

function Session.addHit(hit)
    local damage = tonumber(hit.finalDamage) or 0
    if damage <= 0 then return false end
    local physical = tonumber(hit.physical) or 0
    local element = tonumber(hit.element) or 0
    state.hits = state.hits + 1
    local attribution = attributionKey(hit.attribution)
    state.attribution[attribution] = state.attribution[attribution] + 1
    state.total = state.total + damage
    noteWeaponType(tonumber(hit.weaponType))
    addDamageStats(hit, physical, element)
    addRows(hit, damage)
    return true
end

function Session.addFightingTime(dt)
    local seconds = tonumber(dt) or 0
    if seconds > 0 then state.fightingSeconds = state.fightingSeconds + seconds end
end

function Session.firstHitTime()
    return state.firstHitTime
end

function Session.addProc(proc)
    local damage = tonumber(proc.damage) or 0
    if damage <= 0 then return false end
    if SKILL_PROC_KINDS[proc.kind] then
        state.total = state.total + damage
        state.fixed = state.fixed + damage
        state.skillDamage[proc.kind] = (state.skillDamage[proc.kind] or 0) + damage
        return true
    end
    if STATUS_PROC_KINDS[proc.kind] then
        state.status = state.status + damage
        state.skillDamage[proc.kind] = (state.skillDamage[proc.kind] or 0) + damage
        return true
    end
    if FIXED_PROC_KINDS[proc.kind] then
        state.total = state.total + damage
        state.fixed = state.fixed + damage
    else
        state.status = state.status + damage
    end
    local row = state.procs[proc.kind]
    if not row then
        row = { kind = proc.kind, label = { kind = "proc", proc = proc.kind }, damage = 0, count = 0 }
        state.procs[proc.kind] = row
        state.procOrder[#state.procOrder + 1] = row
    end
    row.damage = row.damage + damage
    row.count = row.count + 1
    return true
end

local function positiveFinite(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

function Session.addPalicoHit(damage)
    if not positiveFinite(damage) then return false end
    state.palico.hits = state.palico.hits + 1
    state.palico.direct = state.palico.direct + damage
    return true
end

function Session.addPalicoProc(kind, damage)
    if not PALICO_PROC_KINDS[kind] or not positiveFinite(damage) then return false end
    state.palico[kind] = state.palico[kind] + damage
    return true
end

function Session.palicoTotals()
    local palico = state.palico
    return { hits = palico.hits, direct = palico.direct, blast = palico.blast, poison = palico.poison }
end

function Session.addHeal(heal)
    local amount = tonumber(heal.amount) or 0
    local maxHp = tonumber(heal.maxHp) or 0
    if amount <= 0 or maxHp <= 0 or not HEAL_KIND_SET[heal.kind] then return false end
    state.heal[heal.kind] = (state.heal[heal.kind] or 0) + amount / maxHp
    return true
end

function Session.noteWeightFallback()
    state.weightFallbacks = state.weightFallbacks + 1
end

function Session.noteDroppedPending()
    state.droppedPending = state.droppedPending + 1
end

function Session.hitCount()
    return state.hits
end

function Session.weaponTypes()
    local list = {}
    for index, weaponType in ipairs(state.weaponTypes) do list[index] = weaponType end
    return list
end

function Session.startTime()
    return state.startTime
end

function Session.lastHitTime()
    return state.lastHitTime
end

function Session.hasData()
    return state.hits > 0 or #state.procOrder > 0 or state.total > 0 or state.status > 0
end

function Session.snapshotHasData(snapshot)
    return snapshot ~= nil and snapshot.damage ~= nil and (snapshot.damage.total or 0) > 0
end

local function skillRows(equipped)
    local rows = {}
    local seen = {}
    local function add(id)
        if seen[id] then return end
        seen[id] = true
        local weight = state.skills[id] or 0
        local denominator = state.skillEligible[id] or state.totalWeight
        if weight <= 0 or denominator <= 0 then return end
        local share = weight / denominator
        rows[#rows + 1] = { id = id, label = { kind = "skill", id = id }, share = share, weight = weight }
    end
    for _, entry in ipairs(equipped or {}) do add(entry.id) end
    local credited = {}
    for id in pairs(state.skills) do credited[#credited + 1] = id end
    table.sort(credited, function(a, b)
        if type(a) == type(b) then return a < b end
        return tostring(a) < tostring(b)
    end)
    for _, id in ipairs(credited) do add(id) end
    for _, kind in ipairs(HEAL_KINDS) do
        local share = state.heal[kind] or 0
        if share > 0 then
            rows[#rows + 1] = { label = { kind = "heal", heal = kind }, share = share, valueKind = "hp" }
        end
    end
    return rows
end

local function ratio(numerator, denominator)
    if denominator > 0 then return numerator / denominator end
    return nil
end

local function skillDamageRows(total)
    local rows = {}
    for _, kind in ipairs(SKILL_DAMAGE_KINDS) do
        local damage = state.skillDamage[kind] or 0
        if damage > 0 then
            rows[#rows + 1] = { kind = kind, damage = damage, share = total > 0 and damage / total or 0 }
        end
    end
    table.sort(rows, function(a, b)
        if a.share ~= b.share then return a.share > b.share end
        return a.kind < b.kind
    end)
    return rows
end

local function palicoBlock(total)
    local palico = Session.palicoTotals()
    local damage = palico.direct + palico.blast + palico.poison
    if damage <= 0 then return nil end
    palico.damage = damage
    palico.share = damage / (total + damage)
    return palico
end

local function dominantAttribute()
    local best, bestBucket = 0, nil
    for attribute, bucket in pairs(state.attributeHitzones) do
        if not bestBucket or bucket.count > bestBucket.count or (bucket.count == bestBucket.count and attribute < best) then
            best, bestBucket = attribute, bucket
        end
    end
    return best, bestBucket
end

local function monsterRows(total)
    local monsters = {}
    for _, monster in ipairs(state.monsterOrder) do
        monsters[#monsters + 1] = {
            id = monster.id, label = monster.label, damage = monster.damage,
            share = total > 0 and monster.damage / total or 0,
        }
    end
    table.sort(monsters, function(a, b) return a.damage > b.damage end)
    return monsters
end

local function motionAndProcRows(total)
    local motions = {}
    for _, motion in ipairs(state.motionOrder) do
        motions[#motions + 1] = {
            key = motion.key, label = motion.label, damage = motion.damage, hits = motion.hits,
            share = total > 0 and motion.damage / total or 0,
        }
    end
    local procs = {}
    for _, proc in ipairs(state.procOrder) do
        procs[#procs + 1] = { kind = proc.kind, label = proc.label, damage = proc.damage, count = proc.count }
        motions[#motions + 1] = {
            key = "proc:" .. proc.kind, label = proc.label, damage = proc.damage, hits = proc.count,
            share = total > 0 and proc.damage / total or 0,
        }
    end
    return motions, procs
end

local function fightingTime()
    local fighting = state.fightingSeconds
    if fighting <= 0 and state.firstHitTime and state.lastHitTime and state.lastHitTime > state.firstHitTime then
        return state.lastHitTime - state.firstHitTime, true
    end
    return fighting, false
end

local function attributeHitzoneRows()
    local rows = {}
    for id, bucket in pairs(state.attributeHitzones) do
        if bucket.count > 0 then
            rows[#rows + 1] = { attribute = id, avgHitzone = bucket.sum / bucket.count, hits = bucket.count }
        end
    end
    table.sort(rows, function(a, b)
        if a.hits ~= b.hits then return a.hits > b.hits end
        return a.attribute < b.attribute
    end)
    return rows
end

local function weaponRows(list)
    local weapons = {}
    for index, entry in ipairs(list or {}) do
        weapons[index] = { type = entry.type, label = { kind = "weapon", type = entry.type } }
    end
    return weapons
end

local function diagnosticsBlock(fightingFallback)
    return {
        attribution = {
            action = state.attribution.action, shell = state.attribution.shell,
            kinsect = state.attribution.kinsect, weaponMinus1 = state.attribution.weaponMinus1,
            slinger = state.attribution.slinger,
            lastAttack = state.attribution.lastAttack, nonattack = state.attribution.nonattack,
        },
        weightFallbacks = state.weightFallbacks,
        droppedPending = state.droppedPending,
        fightingFallback = fightingFallback,
    }
end

function Session.snapshot(options)
    options = options or {}
    local total = state.total + state.status
    local monsters = monsterRows(total)
    local motions, procs = motionAndProcRows(total)
    local elapsed = options.elapsedSeconds
    if elapsed == nil then
        elapsed = (state.lastHitTime or state.startTime) - state.startTime
    end
    local fighting, fightingFallback = fightingTime()
    local weapon = options.weapon or {}
    local attribute, attributeBucket = dominantAttribute()
    local attributeHitzones = attributeHitzoneRows()
    local weapons = weaponRows(options.weapons)
    local snapshot = {
        version = 2,
        modVersion = Version.CURRENT,
        quest = {
            level = options.questLevel,
            result = options.result or "running",
            elapsedSeconds = elapsed,
            endedAt = options.endedAt or os.time(),
            weapon = { type = weapon.type, label = { kind = "weapon", type = weapon.type } },
            weapons = weapons,
            playerCount = options.playerCount,
        },
        monsters = monsters,
        damage = { total = total, physical = state.physical, element = state.element, fixed = state.fixed, status = state.status, hits = state.hits },
        stats = {
            fightingSeconds = fighting,
            combatDps = ratio(total, fighting),
            critRate = ratio(state.critHits, state.crittableHits),
            negativeCritRate = ratio(state.negativeCritHits, state.crittableHits),
            avgAttack = ratio(state.attackSum, state.attackCount),
            avgHitzone = ratio(state.hitzoneSum, state.hitzoneCount),
            attribute = attribute,
            attributeHitzones = attributeHitzones,
            avgAttributeHitzone = attributeBucket and ratio(attributeBucket.sum, attributeBucket.count) or nil,
        },
        skillDamage = skillDamageRows(total),
        palico = palicoBlock(total),
        skills = skillRows(options.equippedSkills),
        motions = motions,
        procs = procs,
        diagnostics = diagnosticsBlock(fightingFallback),
    }
    return Session.relabel(snapshot, options.resolveName)
end

local function defaultName(label)
    if label.kind == "motion" then return label.className end
    if label.kind == "proc" then return label.proc end
    if label.kind == "heal" then return label.heal end
    if label.kind == "monster" then return "#" .. tostring(label.emId) end
    if label.kind == "skill" then return "#" .. tostring(label.id) end
    if label.kind == "weapon" then return "#" .. tostring(label.type) end
    return label.kind
end

function Session.relabel(snapshot, resolve)
    resolve = resolve or defaultName
    local function relabel(row)
        if row.label then row.name = resolve(row.label) end
    end
    for _, field in ipairs({ "monsters", "motions", "procs", "skills" }) do
        for _, row in ipairs(snapshot[field] or {}) do relabel(row) end
    end
    local quest = snapshot.quest
    if quest then
        if quest.weapon then relabel(quest.weapon) end
        for _, weapon in ipairs(quest.weapons or {}) do relabel(weapon) end
    end
    if snapshot.motions then
        local merged, byName = {}, {}
        for _, row in ipairs(snapshot.motions) do
            local first = byName[row.name]
            if first then
                first.damage = first.damage + row.damage
                first.hits = first.hits + row.hits
                first.share = first.share + row.share
            else
                byName[row.name] = row
                merged[#merged + 1] = row
            end
        end
        snapshot.motions = merged
        sortRows(snapshot.motions)
    end
    if snapshot.diagnostics then
        local names = { sibling = 0, unmapped = 0 }
        for _, row in ipairs(snapshot.motions or {}) do
            if row.label and row.label.kind == "motion" then
                local _, source = MotionNames.nameFor(row.label.className, row.label.guideId or -1)
                if names[source] ~= nil then names[source] = names[source] + (row.hits or 0) end
            end
        end
        snapshot.diagnostics.names = names
    end
    if snapshot.skills then
        for index = #snapshot.skills, 1, -1 do
            local row = snapshot.skills[index]
            if row.label and not Game.isUsableText(row.name) then
                table.remove(snapshot.skills, index)
            end
        end
        local uptime, heals = {}, {}
        for _, row in ipairs(snapshot.skills) do
            if row.label and row.label.kind == "heal" then
                heals[#heals + 1] = row
            else
                uptime[#uptime + 1] = row
            end
        end
        sortRows(uptime)
        for _, row in ipairs(heals) do uptime[#uptime + 1] = row end
        snapshot.skills = uptime
    end
    return snapshot
end

return Session
