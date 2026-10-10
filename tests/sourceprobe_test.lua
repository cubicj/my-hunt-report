local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local ShellTracker = require("MyHuntReport.ShellTracker")

local T = {}

local MODULE_PATH = "reframework/autorun/MyHuntReport/SourceProbe.lua"
local SETUP = "app.AppShell.doOnSetUp"
local DESTROY = "app.AppShell.doOnDestroy"
local HIT = "app.cEnemyStockDamage.stockDamageDetail(app.HitInfo)"

local function linesWith(prefix)
    local found = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] srcp " .. prefix, 1, true) then found[#found + 1] = line end
    end
    return found
end

local function has(line, text)
    return line ~= nil and line:find(text, 1, true) ~= nil
end

local function classed(name, guide)
    return {
        _ActionGuideID = guide,
        get_type_definition = function() return { get_name = function() return name end } end,
    }
end

local function shellObject(address, hash, owner, parent)
    return {
        _ShellUniqueIndex = 3,
        _ChainShellID = 9,
        get_address = function() return address end,
        call = function(_, name)
            if name == "get_NameHash" then return hash end
            return nil
        end,
        get_ParentShell = function() return parent end,
        get_ShellOwner = function() return { get_Name = function() return owner end } end,
    }
end

local function handling(values)
    return { call = function(_, name)
        local value = values[name]
        if value == "fail" then error("no " .. name) end
        return value
    end }
end

local function withProbe(callback)
    local saved = {
        masterHunter = Game.masterHunter, isMaster = Game.isMasterGameObject, enemyContext = Game.enemyContext,
        enemyIsDead = Game.enemyIsDead, componentOf = Game.componentOf, uptime = Game.uptime, hook = Game.hook,
        nameFor = ShellTracker.nameForAttackObject, toManaged = sdk.to_managed_object,
    }
    local c = { weapon = 7, now = 100.0, hooks = {}, masterReads = 0, rows = {} }
    c.master = { get_address = function() return 0x1000 end }
    c.other = { get_address = function() return 0x2000 end }
    c.boss = { em = { get_IsBoss = function() return true end, get_UniqueIndex = function() return 4 end } }
    c.small = { em = { get_IsBoss = function() return false end, get_UniqueIndex = function() return 5 end } }
    c.deadBoss = { dead = true, em = c.boss.em }
    c.base = classed("cShoot", 21)
    c.sub = classed("cNothing", nil)
    c.hunter = {
        get_WeaponType = function() return c.weapon end,
        get_WeaponHandling = function() return c.handling end,
        call = function(_, name)
            if name == "get_BaseActionController" then
                return { get_CurrentAction = function() return c.base end }
            end
            if name == "get_SubActionController" then
                return { get_CurrentAction = function() return c.sub end }
            end
            return nil
        end,
    }
    c.setup = function(shell) c.hooks[SETUP]({ [2] = shell }) end
    c.destroy = function(shell) c.hooks[DESTROY]({ [2] = shell }) end
    c.object = function(name, shell) return { get_Name = function() return name end, shell = shell } end
    c.hit = function(opts)
        opts = opts or {}
        local info = {
            getActualAttackOwner = function() return opts.owner or c.master end,
            get_DamageOwner = function() return opts.target or c.boss end,
            get_AttackObj = function() return opts.obj or c.object("it0700_0027_0") end,
            get_AttackData = function()
                return { _WeaponType = opts.wt or 7, _ActionType = opts.act or 1, _SpecialType = opts.special or 0,
                    _OriginalAttackAdjust = opts.mv or 30.0 }
            end,
            get_AttackIndex = function()
                if opts.indexFails then error("no attack index") end
                return { _Resource = 0, _Index = opts.index or 12 }
            end,
        }
        c.hooks[HIT]({ [3] = info })
    end
    local ok, err = pcall(function()
        Log.setDeveloperMode(true)
        Log.resetCounts()
        stubs.reset()
        Game.masterHunter = function()
            c.masterReads = c.masterReads + 1
            return c.hunter
        end
        Game.isMasterGameObject = function(object) return object == c.master end
        Game.enemyContext = function(object) return object and object.em or nil end
        Game.enemyIsDead = function(object) return object ~= nil and object.dead == true end
        Game.componentOf = function(object, typeName)
            assert(typeName == "app.AppShell")
            return object and object.shell or nil
        end
        Game.uptime = function() return c.now end
        Game.hook = function(typeName, signature, pre)
            c.hooks[typeName .. "." .. signature] = pre
            return true
        end
        ShellTracker.nameForAttackObject = function(object)
            local row = c.rows[object]
            if row == "hitTime" then return nil, nil, true end
            return row, row and { kind = "motion" } or nil, nil
        end
        sdk.to_managed_object = function(value) return value end
        c.probe = dofile(MODULE_PATH)
        c.probe.install()
        callback(c)
    end)
    Game.masterHunter = saved.masterHunter
    Game.isMasterGameObject = saved.isMaster
    Game.enemyContext = saved.enemyContext
    Game.enemyIsDead = saved.enemyIsDead
    Game.componentOf = saved.componentOf
    Game.uptime = saved.uptime
    Game.hook = saved.hook
    ShellTracker.nameForAttackObject = saved.nameFor
    sdk.to_managed_object = saved.toManaged
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

function T.pureHelpersFormatLineageAndWeaponState()
    local probe = dofile(MODULE_PATH)
    assert(probe.formatValue(nil) == "?")
    assert(probe.formatValue(11.25) == "11.25")
    assert(probe.formatValue(7) == "7")
    assert(probe.formatValue(true) == "true")
    assert(probe.formatAddress(0x500) == "0x500")
    assert(probe.formatAddress(nil) == "?")
    local depth, root, path = probe.lineage(10, nil, false, nil)
    assert(depth == 0 and root == 10 and probe.pathText(path) == "10")
    depth, root, path = probe.lineage(20, nil, true, 10)
    assert(depth == nil and root == 10 and probe.pathText(path) == "10>20")
    depth, root, path = probe.lineage(20, nil, true, nil)
    assert(depth == nil and root == nil and probe.pathText(path) == "?>20")
    local parent = { depth = 1, root = 10, path = { "10", "15" } }
    depth, root, path = probe.lineage(20, parent, true, 15)
    assert(depth == 2 and root == 10 and probe.pathText(path) == "10>15>20")
    assert(probe.pathText(parent.path) == "10>15")
    local long = { depth = 5, root = 1, path = { "1", "2", "3", "4", "5" } }
    depth, root, path = probe.lineage(6, long, true, 5)
    assert(depth == 6 and root == 1 and probe.pathText(path) == "2>3>4>5>6")
    depth = probe.lineage(2, { depth = nil, root = 1, path = { "1" } }, true, 1)
    assert(depth == nil)
    assert(probe.weaponState(handling({ get_Mode = 1, get_IsSwordAwaken = true, get_IsAxeEnhanced = false }), 8)
        == "mode=1,sword=true,axe=false")
    assert(probe.weaponState(handling({ get_Mode = 0, get_IsShieldEnhanced = true, get_IsSwordEnhanced = false,
        get_IsAxeEnhanced = "fail", get_SwordBinNum = 4.5, get_SwordEnergyState = 2 }), 9)
        == "mode=0,shield=true,sword=false,axe=?,bins=4.50,energy=2")
    assert(probe.weaponState(nil, 8) == "mode=?,sword=?,axe=?")
    assert(probe.weaponState(handling({}), 7) == "-")
    assert(probe.weaponState(nil, nil) == "-")
end

function T.developerModeOffReadsNothingStoresNothingAndLogsNothing()
    withProbe(function(c)
        Log.setDeveloperMode(false)
        local touched = 0
        local raising = setmetatable({}, { __index = function(_, key)
            touched = touched + 1
            error("touched " .. tostring(key))
        end })
        c.hooks[SETUP](raising)
        c.hooks[DESTROY](raising)
        c.hooks[HIT](raising)
        assert(touched == 0)
        assert(c.masterReads == 0)
        local shell = shellObject(0x700, 1853117018, "it0700_0027_0", nil)
        c.setup(shell)
        assert(c.masterReads == 0)
        assert(#stubs.logLines == 0)
        Log.setDeveloperMode(true)
        c.hit({ obj = c.object("Wp07Shell", shell) })
        local hits = linesWith("hit ")
        assert(#hits == 1)
        assert(has(hits[1], "shell=0x700 hash=1853117018 root=? path=? depth=?"))
    end)
end

function T.setupRecordsLineageAndLogsWeaponOwnedShells()
    withProbe(function(c)
        local root = shellObject(0x700, 543483591, "it0700_0027_0", nil)
        c.setup(root)
        c.now = 100.25
        c.base = classed("cBulletFire", 33)
        local child = shellObject(0x701, 3858449010, "it0700_0027_0", root)
        c.setup(child)
        local monster = shellObject(0x900, 4242, "Em0001_00", nil)
        c.setup(monster)
        local lines = linesWith("setup ")
        assert(#lines == 2)
        assert(has(lines[1], "t=100.000 addr=0x700 hash=543483591 uid=3 chain=9 owner=it0700_0027_0 parent=none/- root=543483591 depth=0 path=543483591 base=cShoot/21 sub=cNothing/? wp=7"))
        assert(has(lines[2], "t=100.250 addr=0x701 hash=3858449010"))
        assert(has(lines[2], "parent=0x700/543483591 root=543483591 depth=1 path=543483591>3858449010 base=cBulletFire/33"))
        local orphanParent = shellObject(0x800, 777, "it0700_0027_0", nil)
        c.setup(shellObject(0x801, 778, "it0700_0027_0", orphanParent))
        lines = linesWith("setup ")
        assert(has(lines[3], "parent=0x800/777 root=777 depth=? path=777>778"))
        c.setup(shellObject(0x901, 4343, "it9999_0000_0", monster))
        lines = linesWith("setup ")
        assert(has(lines[4], "root=4242 depth=1 path=4242>4343"))
    end)
end

function T.nonShellHitLogsAttackIdentityHunterStateAndWeaponState()
    withProbe(function(c)
        c.weapon = 9
        c.base = classed("cSwordSlash1", 44)
        c.sub = classed("cNothing", -1)
        c.handling = handling({ get_Mode = 0, get_IsShieldEnhanced = true, get_IsSwordEnhanced = true,
            get_IsAxeEnhanced = false, get_SwordBinNum = 3.0, get_SwordEnergyState = 1 })
        c.hit({ obj = c.object("it0900_0025_0"), wt = 9, act = 1, special = 0, mv = 24.0, index = 5 })
        local lines = linesWith("hit ")
        assert(#lines == 1)
        assert(has(lines[1], "t=100.000 em=4 dead=false obj=it0900_0025_0 wt=9 act=1 special=0 mv=24.00 key=9:0:5 wp=9 base=cSwordSlash1/44 sub=cNothing/-1 state=mode=0,shield=true,sword=true,axe=false,bins=3.00,energy=1"))
        assert(has(lines[1], "shell=none hash=- root=- path=- depth=- owner=- age=- setupBase=- setupSub=- setupWp=- row=-"))
    end)
end

function T.shellHitJoinsTheSetupRecordAndTheProductionRow()
    withProbe(function(c)
        c.base = classed("cBulletFire", 33)
        local root = shellObject(0x700, 543483591, "it0700_0027_0", nil)
        c.setup(root)
        local child = shellObject(0x701, 3858449010, "it0700_0027_0", root)
        c.setup(child)
        c.destroy(root)
        c.now = 100.5
        c.base = classed("cRyuugekiIdle", 55)
        local object = c.object("Wp07Shell", child)
        c.rows[object] = "cBulletFire"
        c.hit({ obj = object, wt = 7, act = 1, special = 6, mv = 7.0, index = 30 })
        local line = linesWith("hit ")[1]
        assert(has(line, "obj=Wp07Shell wt=7 act=1 special=6 mv=7.00 key=7:0:30 wp=7 base=cRyuugekiIdle/55"))
        assert(has(line, "state=- shell=0x701 hash=3858449010 root=543483591 path=543483591>3858449010 depth=1 owner=it0700_0027_0 age=0.500 setupBase=cBulletFire/33 setupSub=cNothing/? setupWp=7 row=cBulletFire"))
        local bubble = shellObject(0x720, 2441209651, "it0500_0001_0", nil)
        c.setup(bubble)
        local bubbleObject = c.object("Wp05Shell", bubble)
        c.rows[bubbleObject] = "hitTime"
        c.hit({ obj = bubbleObject, wt = 5 })
        assert(has(linesWith("hit ")[2], "row=hitTime"))
        c.destroy(child)
        c.hit({ obj = c.object("Wp07Shell", child) })
        assert(has(linesWith("hit ")[3], "shell=0x701 hash=3858449010 root=? path=? depth=? owner=? age=? setupBase=? setupSub=? setupWp=? row=-"))
    end)
end

function T.hitsFromOthersOrOnSmallMonstersAreIgnoredAndDeadHitsAreMarked()
    withProbe(function(c)
        c.hit({ owner = c.other })
        c.hit({ target = c.small })
        assert(#linesWith("hit ") == 0)
        c.hit({ target = c.deadBoss })
        local lines = linesWith("hit ")
        assert(#lines == 1)
        assert(has(lines[1], "dead=true"))
    end)
end

function T.failedReadsPrintQuestionMarks()
    withProbe(function(c)
        c.base = nil
        c.sub = nil
        c.hit({ indexFails = true, wt = 7 })
        local line = linesWith("hit ")[1]
        assert(has(line, "key=7:?:?"))
        assert(has(line, "base=?/? sub=?/?"))
    end)
end

function T.summaryPrintsEveryFiftyHitsAndOnWeaponChange()
    withProbe(function(c)
        c.hit({ obj = c.object("Wp07Shell", shellObject(0x730, 1, "it0700_0027_0", nil)) })
        for _ = 1, 48 do c.hit() end
        assert(#linesWith("summary ") == 0)
        c.hit({ target = c.deadBoss })
        local summaries = linesWith("summary ")
        assert(#summaries == 1)
        assert(has(summaries[1], "summary hits=50 shellHits=1 noSetup=1 dead=1 byWp=7:50"))
        c.weapon = 8
        c.hit()
        summaries = linesWith("summary ")
        assert(#summaries == 2)
        assert(has(summaries[2], "summary hits=51 shellHits=1 noSetup=1 dead=1 byWp=7:50,8:1"))
        c.hit()
        assert(#linesWith("summary ") == 2)
    end)
end

function T.throwingParentReadKeepsLineageUnknown()
    withProbe(function(c)
        local shell = shellObject(0x700, 20, "it0700_0027_0", nil)
        shell.get_ParentShell = function() error("no parent read") end
        c.setup(shell)
        local line = linesWith("setup ")[1]
        assert(has(line, "parent=?/? root=? depth=? path=?>20"), line)
        c.hit({ obj = c.object("Wp07Shell", shell) })
        line = linesWith("hit ")[1]
        assert(has(line, "shell=0x700 hash=20 root=? path=?>20 depth=?"), line)
        local child = shellObject(0x701, 30, "it0700_0027_0", shell)
        c.setup(child)
        line = linesWith("setup ")[2]
        assert(has(line, "parent=0x700/20 root=? depth=? path=?>20>30"), line)
    end)
end

function T.throwingAttackObjectReadKeepsShellUnknownWithoutCountingIt()
    withProbe(function(c)
        local info = {
            getActualAttackOwner = function() return c.master end,
            get_DamageOwner = function() return c.boss end,
            get_AttackObj = function() error("no attack object") end,
        }
        c.hooks[HIT]({ [3] = info })
        local line = linesWith("hit ")[1]
        assert(has(line, "obj=?"), line)
        assert(has(line, "shell=? hash=? root=? path=? depth=? owner=? age=? setupBase=? setupSub=? setupWp=? row=?"), line)
        info.get_AttackObj = function() return nil end
        c.hooks[HIT]({ [3] = info })
        line = linesWith("hit ")[2]
        assert(has(line, "shell=none hash=- root=- path=- depth=- owner=- age=- setupBase=- setupSub=- setupWp=- row=-"), line)
        for _ = 1, 48 do c.hit() end
        line = linesWith("summary ")[1]
        assert(has(line, "summary hits=50 shellHits=0 noSetup=0 dead=0 byWp=7:50"), line)
    end)
end

function T.observationGapInvalidatesReusedAddressesBeforeAnyEnabledHandler()
    for _, disabledHook in ipairs({ SETUP, DESTROY, HIT }) do
        for _, enabledHook in ipairs({ SETUP, DESTROY, HIT }) do
            for _, hash in ipairs({ 10, 20 }) do
                withProbe(function(c)
                    local old = shellObject(0x700, 10, "it0700_0027_0", nil)
                    c.setup(old)
                    Log.setDeveloperMode(false)
                    local touched = 0
                    local raising = setmetatable({}, { __index = function()
                        touched = touched + 1
                        error("disabled argument read")
                    end })
                    local reads, lines = c.masterReads, #stubs.logLines
                    c.hooks[disabledHook](raising)
                    assert(touched == 0 and c.masterReads == reads and #stubs.logLines == lines)
                    local reused = shellObject(0x700, hash, "it0700_0027_0", nil)
                    if disabledHook == DESTROY and enabledHook == HIT then
                        c.destroy(old)
                        c.setup(reused)
                        assert(c.masterReads == reads and #stubs.logLines == lines)
                    end
                    c.base = classed("cBulletFire", 33)
                    c.now = 101.0
                    Log.setDeveloperMode(true)
                    if enabledHook == SETUP then
                        c.setup(shellObject(0x701, 30, "it0700_0027_0", reused))
                        local line = linesWith("setup ")[2]
                        assert(has(line, "root=" .. hash .. " depth=? path=" .. hash .. ">30"), line)
                    elseif enabledHook == DESTROY then
                        c.destroy(shellObject(0x900, 90, "it0700_0027_0", nil))
                    end
                    c.hit({ obj = c.object("Wp07Shell", reused) })
                    local line = linesWith("hit ")[1]
                    assert(has(line, "shell=0x700 hash=" .. hash .. " root=? path=? depth=? owner=? age=? setupBase=? setupSub=? setupWp=? row=-"), line)
                    c.setup(reused)
                    c.hit({ obj = c.object("Wp07Shell", reused) })
                    line = linesWith("hit ")[2]
                    assert(has(line, "root=" .. hash .. " path=" .. hash .. " depth=0"), line)
                    assert(has(line, "setupBase=cBulletFire/33"), line)
                    for _ = 1, 48 do c.hit() end
                    line = linesWith("summary ")[1]
                    assert(has(line, "summary hits=50 shellHits=2 noSetup=1 dead=0 byWp=7:50"), line)
                end)
            end
        end
    end
end

function T.hashMismatchRejectsCachedSetupIdentity()
    withProbe(function(c)
        c.setup(shellObject(0x700, 10, "it0700_0027_0", nil))
        local reused = shellObject(0x700, 20, "it0700_0027_0", nil)
        local object = c.object("Wp07Shell", reused)
        c.rows[object] = "cBulletFire"
        c.hit({ obj = object })
        local line = linesWith("hit ")[1]
        assert(has(line, "shell=0x700 hash=20 root=? path=? depth=? owner=? age=? setupBase=? setupSub=? setupWp=? row=cBulletFire"), line)
        for _ = 1, 49 do c.hit() end
        line = linesWith("summary ")[1]
        assert(has(line, "summary hits=50 shellHits=1 noSetup=1 dead=0 byWp=7:50"), line)
    end)
end

return T
