local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local MODULE_PATH = "reframework/autorun/MyHuntReport/KinsectProbe.lua"
local HOOK = "app.Wp10Insect.evAttackPostProcess(app.HitInfo)"

local function kpLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] kp ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function linesWith(prefix)
    local found = {}
    for _, line in ipairs(kpLines()) do
        if line:find("[MyHuntReport] kp " .. prefix, 1, true) then found[#found + 1] = line end
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

local function kinsect(c, address)
    return {
        _ActType = 3,
        get_address = function() return address end,
        _ActionController = { get_CurrentAction = function()
            if c.kinsectFails then error("no current action") end
            return c.kinsectAction
        end },
    }
end

local function hunter(c)
    return {
        get_WeaponType = function() return c.weapon end,
        get_WeaponHandling = function()
            return { call = function(_, name)
                if name == "get_Insect" then return c.handlingInsect end
                return nil
            end }
        end,
        call = function(_, name)
            if name == "get_Wp10Insect" then
                if c.mainFails then error("no get_Wp10Insect") end
                return c.mainInsect
            end
            if name == "get_ReserveWp10Insect" then return c.reserveInsect end
            if name == "get_BaseActionController" then
                return { get_CurrentAction = function() return c.base end }
            end
            if name == "get_SubActionController" then
                return { get_CurrentAction = function() return c.sub end }
            end
            return nil
        end,
    }
end

local function hitInfo(owner, name, mv)
    return {
        getActualAttackOwner = function() return owner end,
        get_AttackObj = function() return { get_Name = function() return name end } end,
        get_DamageOwner = function() return { em = { get_UniqueIndex = function() return 7 end } } end,
        get_AttackData = function() return { _OriginalAttackAdjust = mv } end,
    }
end

local function withProbe(callback)
    local saved = {
        masterHunter = Game.masterHunter, isMaster = Game.isMasterGameObject, uptime = Game.uptime,
        enemyContext = Game.enemyContext, hook = Game.hook, toManaged = sdk.to_managed_object,
    }
    local c = { weapon = 10, now = 10.0, hooks = {}, masterReads = 0 }
    c.mainInsect = kinsect(c, 0x500)
    c.handlingInsect = c.mainInsect
    c.reserveInsect = kinsect(c, 0x600)
    c.hunter = hunter(c)
    c.master = { get_address = function() return 0x1000 end }
    c.other = { get_address = function() return 0x2000 end }
    c.fire = function(insect, info)
        c.hooks[HOOK]({ [2] = insect, [3] = info })
    end
    c.hit = function(mv)
        c.fire(c.mainInsect, hitInfo(c.master, "it1003_0021_0", mv or 30))
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
        Game.uptime = function() return c.now end
        Game.enemyContext = function(object) return object and object.em or nil end
        Game.hook = function(typeName, signature, pre)
            c.hooks[typeName .. "." .. signature] = pre
            return true
        end
        sdk.to_managed_object = function(value) return value end
        c.probe = dofile(MODULE_PATH)
        c.probe.install()
        callback(c)
    end)
    Game.masterHunter = saved.masterHunter
    Game.isMasterGameObject = saved.isMaster
    Game.uptime = saved.uptime
    Game.enemyContext = saved.enemyContext
    Game.hook = saved.hook
    sdk.to_managed_object = saved.toManaged
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

function T.pureHelpersFormatAndApplyTheRules()
    local probe = dofile(MODULE_PATH)
    assert(probe.formatValue(nil) == "?")
    assert(probe.formatValue(1.5) == "1.50")
    assert(probe.formatValue(3) == "3")
    assert(probe.formatAddress(nil) == "nil")
    assert(probe.formatAddress(0x500) == "0x500")
    assert(probe.isAttack("cSlash1") == true)
    assert(probe.isAttack("cDodgeFront") == false)
    assert(probe.isAttack(nil) == false)
    local last = { class = "cSlash1", guide = 5 }
    assert(probe.ruleS(nil, last) == nil)
    assert(probe.ruleS({ startAttack = true, startClass = "cSlash2" }, last) == "cSlash2")
    assert(probe.ruleS({ startAttack = false, startClass = "cDodgeFront" }, last) == "cSlash1")
    assert(probe.ruleS({ startAttack = false, startClass = "cDodgeFront" }, nil) == nil)
    assert(probe.ruleS({ startAttack = nil, startClass = nil }, last) == nil)
    assert(probe.attackState(nil) == nil)
    assert(probe.attackState("cSlash1") == true)
    assert(probe.attackState("cDodgeFront") == false)
    assert(probe.ruleH("cSlash3", last) == "cSlash3")
    assert(probe.ruleH("cDodgeFront", last) == "cSlash1")
    assert(probe.ruleH(nil, last) == nil)
end

function T.developerModeOffReadsNothingAndLogsNothing()
    withProbe(function(c)
        Log.setDeveloperMode(false)
        local touched = 0
        local raising = setmetatable({}, { __index = function(_, key)
            touched = touched + 1
            error("touched " .. tostring(key))
        end })
        c.hooks[HOOK](raising)
        c.probe.update()
        assert(touched == 0)
        assert(c.masterReads == 0)
        assert(#kpLines() == 0)
    end)
end

function T.instanceLinesPrintOnlyOnAddressChanges()
    withProbe(function(c)
        c.reserveInsect = nil
        c.probe.update()
        c.probe.update()
        local lines = linesWith("instance ")
        assert(#lines == 3)
        assert(has(lines[1], "via=HunterCharacter.get_Wp10Insect addr=0x500"))
        assert(has(lines[2], "via=HunterCharacter.get_ReserveWp10Insect addr=nil"))
        assert(has(lines[3], "via=cHunterWp10Handling.get_Insect addr=0x500"))
        c.mainFails = true
        c.probe.update()
        lines = linesWith("instance ")
        assert(#lines == 4)
        assert(has(lines[4], "via=HunterCharacter.get_Wp10Insect addr=?"))
    end)
end

function T.hunterLinesTrackAttacksAndTheLastAttack()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cIdle")
        c.probe.update()
        c.now = 10.5
        c.base = classed("cDodgeFront", 12)
        c.probe.update()
        local lines = linesWith("hunter ")
        assert(#lines == 2)
        assert(has(lines[1], "base=cSlash1/11"))
        assert(has(lines[1], "attack=true"))
        assert(has(lines[2], "base=cDodgeFront/12"))
        assert(has(lines[2], "attack=false"))
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        local kact = linesWith("kact ")
        assert(#kact == 2)
        assert(has(kact[2], "from=cIdle to=cAttack"))
        assert(has(kact[2], "start=cDodgeFront/12"))
        assert(has(kact[2], "attack=false"))
        assert(has(kact[2], "last=cSlash1/11 seen=true"))
    end)
end

function T.kinsectActionLinesCarryDurationAndSpans()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.now = 10.5
        c.base = classed("cSlash2", 21)
        c.probe.update()
        c.now = 11.0
        c.kinsectAction = classed("cPassSpin")
        c.probe.update()
        local lines = linesWith("kact ")
        assert(#lines == 2)
        assert(has(lines[1], "via=HunterCharacter.get_Wp10Insect"))
        assert(has(lines[1], "from=? to=cAttack dur=? spans=?"))
        assert(has(lines[1], "actType=3 start=?/? sub=? attack=? last=cSlash1/11 seen=false"))
        assert(has(lines[2], "from=cAttack to=cPassSpin dur=1.00 spans=1"))
        assert(has(lines[2], "start=cSlash2/21"))
        assert(has(lines[2], "seen=true"))
    end)
end

function T.kinsectReadFallsBackToTheHandlingGetter()
    withProbe(function(c)
        c.mainInsect = nil
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        local lines = linesWith("kact ")
        assert(#lines == 1)
        assert(has(lines[1], "via=cHunterWp10Handling.get_Insect"))
    end)
end

function T.hitLinesApplyBothRules()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cIdle")
        c.probe.update()
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.now = 10.4
        c.base = classed("cSlash2", 21)
        c.probe.update()
        c.now = 10.6
        c.hit(24)
        local lines = linesWith("hit ")
        assert(#lines == 1)
        assert(has(lines[1], "em=7 obj=it1003_0021_0 mv=24 kact=cAttack open=cAttack age=0.60"))
        assert(has(lines[1], "eq=main,handling"))
        assert(has(lines[1], "start=cSlash1/11 startAttack=true spans=1 seen=true"))
        assert(has(lines[1], "hit=cSlash2/21"))
        assert(has(lines[1], "last=cSlash2/21 S=cSlash1 H=cSlash2 same=false"))
    end)
end

function T.hitOnANonAttackStartUsesTheLastAttack()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cIdle")
        c.probe.update()
        c.base = classed("cDodgeFront", 12)
        c.kinsectAction = classed("cAutoAttack")
        c.probe.update()
        c.hit()
        local line = linesWith("hit ")[1]
        assert(has(line, "startAttack=false"))
        assert(has(line, "S=cSlash1 H=cSlash1 same=true"))
    end)
end

function T.hitWithoutARecordAndWithAStaleRecordAreCounted()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.hit()
        assert(has(linesWith("hit ")[1], "kact=? open=? age=? eq=? start=?/? startAttack=? spans=?"))
        assert(has(linesWith("hit ")[1], "S=? H=cSlash1 same=?"))
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.kinsectAction = classed("cPassSpin")
        c.hit()
        assert(has(linesWith("hit ")[2], "kact=cPassSpin open=cAttack"))
        for _ = 3, 20 do c.hit() end
        local summary = linesWith("summary ")
        assert(#summary == 1)
        assert(has(summary[1], "hits=20 noRecord=1 unseenStart=19 mismatchedOpen=19 startNonAttack=0 differ=0 spanned=0"))
        local classes = linesWith("summary-class ")
        assert(#classes == 2)
        assert(has(classes[1], "summary-class ? hits=1 differ=0 spanned=0"))
        assert(has(classes[2], "summary-class cPassSpin hits=19 differ=0 spanned=0"))
    end)
end

function T.unreadableHunterActionStaysUnknown()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cIdle")
        c.probe.update()
        c.base = nil
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        assert(has(linesWith("hunter ")[2], "base=?/? sub=? attack=?"))
        assert(has(linesWith("kact ")[2], "start=?/? sub=? attack=? last=cSlash1/11 seen=true"))
        c.hit()
        local line = linesWith("hit ")[1]
        assert(has(line, "startAttack=?"))
        assert(has(line, "hit=?/? sub=? last=cSlash1/11 S=? H=? same=?"))
        for _ = 2, 20 do c.hit() end
        assert(has(linesWith("summary ")[1], "startNonAttack=0 differ=0"))
    end)
end

function T.unreadableKinsectActionEndsTheRecordWithoutCountingAMismatch()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.kinsectFails = true
        c.hit()
        assert(has(linesWith("hit ")[1], "kact=? open=cAttack"))
        c.now = 10.5
        c.probe.update()
        c.probe.update()
        local kact = linesWith("kact ")
        assert(#kact == 2)
        assert(has(kact[2], "from=cAttack to=? dur=0.50 spans=0"))
        c.hit()
        assert(has(linesWith("hit ")[2], "kact=? open=? age=?"))
        c.kinsectFails = false
        c.now = 11.0
        c.base = classed("cSlash2", 21)
        c.probe.update()
        kact = linesWith("kact ")
        assert(#kact == 3)
        assert(has(kact[3], "from=? to=cAttack dur=? spans=?"))
        assert(has(kact[3], "start=?/? sub=? attack=? last=cSlash2/21 seen=false"))
        c.hit()
        assert(has(linesWith("hit ")[3], "open=cAttack age=0.00 eq=main,handling start=?/? startAttack=? spans=0 seen=false"))
        assert(has(linesWith("hit ")[3], "S=? H=cSlash2 same=?"))
        for _ = 4, 20 do c.hit() end
        assert(has(linesWith("summary ")[1], "hits=20 noRecord=1 unseenStart=19 mismatchedOpen=0"))
    end)
end

function T.addressMatchIsUnknownUnlessEveryGetterWasRead()
    withProbe(function(c)
        local stranger = kinsect(c, 0x800)
        c.fire(stranger, hitInfo(c.master, "it1003_0021_0", 30))
        assert(has(linesWith("hit ")[1], "eq=?"))
        c.probe.update()
        c.fire(stranger, hitInfo(c.master, "it1003_0021_0", 30))
        assert(has(linesWith("hit ")[2], "eq=none"))
        c.mainFails = true
        c.probe.update()
        c.fire(stranger, hitInfo(c.master, "it1003_0021_0", 30))
        assert(has(linesWith("hit ")[3], "eq=?"))
        c.fire(c.handlingInsect, hitInfo(c.master, "it1003_0021_0", 30))
        assert(has(linesWith("hit ")[4], "eq=handling"))
        local unreadable = { _ActionController = stranger._ActionController,
            get_address = function() error("no address") end }
        c.fire(unreadable, hitInfo(c.master, "it1003_0021_0", 30))
        assert(has(linesWith("hit ")[5], "eq=?"))
    end)
end

function T.unreadableGuideStaysUnknownAndIsNotAMoveChange()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.base = classed("cSlash1")
        c.probe.update()
        c.base = classed("cSlash1", 11)
        c.probe.update()
        assert(#linesWith("hunter ") == 1)
        c.base = classed("cSlash2")
        c.probe.update()
        local hunterLines = linesWith("hunter ")
        assert(#hunterLines == 2)
        assert(has(hunterLines[2], "base=cSlash2/? sub=? attack=true"))
        c.hit()
        local line = linesWith("hit ")[1]
        assert(has(line, "spans=1 seen=false hit=cSlash2/? sub=? last=cSlash2/?"))
    end)
end

function T.kinsectStartDuringAGuideFailureRecordsAnUnknownGuide()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.base = classed("cSlash1")
        c.kinsectAction = classed("cPassSpin")
        c.probe.update()
        local kact = linesWith("kact ")
        assert(#kact == 2)
        assert(has(kact[2], "start=cSlash1/? sub=? attack=true"))
        assert(#linesWith("hunter ") == 1)
        c.base = classed("cSlash1", 12)
        c.probe.update()
        local hunterLines = linesWith("hunter ")
        assert(#hunterLines == 2)
        assert(has(hunterLines[2], "base=cSlash1/12"))
    end)
end

function T.replacedKinsectStartsAnUnseenRecordAndOldHitsHaveNone()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cIdle")
        c.probe.update()
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        local old = c.mainInsect
        c.mainInsect = kinsect(c, 0x900)
        c.handlingInsect = c.mainInsect
        c.now = 12.2
        c.base = classed("cSlash2", 21)
        c.probe.update()
        local kact = linesWith("kact ")
        assert(#kact == 3)
        assert(has(kact[3], "from=cAttack to=cAttack dur=2.20 spans=1"))
        assert(has(kact[3], "start=?/? sub=? attack=? last=cSlash2/21 seen=false"))
        c.hit()
        assert(has(linesWith("hit ")[1], "open=cAttack age=0.00 eq=main,handling start=?/? startAttack=? spans=0 seen=false"))
        assert(has(linesWith("hit ")[1], "S=? H=cSlash2 same=?"))
        c.fire(old, hitInfo(c.master, "it1003_0021_0", 30))
        assert(has(linesWith("hit ")[2], "open=? age=? eq=none start=?/? startAttack=? spans=? seen=?"))
    end)
end

function T.hunterReadRecoveryIsNotAnAttackChange()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cIdle")
        c.probe.update()
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.base = nil
        c.probe.update()
        c.probe.update()
        c.base = classed("cSlash1", 11)
        c.probe.update()
        local lines = linesWith("hunter ")
        assert(#lines == 3)
        assert(has(lines[2], "base=?/? sub=? attack=?"))
        assert(has(lines[3], "base=cSlash1/11 sub=? attack=true recovered=same"))
        c.hit()
        assert(has(linesWith("hit ")[1], "start=cSlash1/11 startAttack=true spans=0 seen=true"))
        c.base = nil
        c.probe.update()
        c.base = classed("cSlash3", 31)
        c.probe.update()
        lines = linesWith("hunter ")
        assert(#lines == 5)
        assert(has(lines[5], "base=cSlash3/31 sub=? attack=true recovered=changed"))
        c.hit()
        assert(has(linesWith("hit ")[2], "spans=1 seen=true"))
        assert(has(linesWith("hit ")[2], "last=cSlash3/31 S=cSlash1 H=cSlash3 same=false"))
    end)
end

function T.firstReadableHunterActionIsNotAChange()
    withProbe(function(c)
        c.kinsectAction = classed("cIdle")
        c.probe.update()
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.base = classed("cSlash1", 11)
        c.probe.update()
        local lines = linesWith("hunter ")
        assert(#lines == 2)
        assert(has(lines[1], "base=?/? sub=? attack=?"))
        assert(has(lines[2], "base=cSlash1/11 sub=? attack=true recovered=first"))
        c.hit()
        assert(has(linesWith("hit ")[1], "start=?/? startAttack=? spans=0 seen=true"))
        assert(has(linesWith("hit ")[1], "last=cSlash1/11 S=? H=cSlash1 same=?"))
    end)
end

function T.nonMasterHitsAreIgnored()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.fire(c.reserveInsect, hitInfo(c.other, "it1003_0021_1", 30))
        assert(#linesWith("hit ") == 0)
    end)
end

function T.leavingTheGlaivePrintsTheSummaryAndClearsTheRecord()
    withProbe(function(c)
        c.base = classed("cSlash1", 11)
        c.kinsectAction = classed("cAttack")
        c.probe.update()
        c.hit()
        c.weapon = 3
        c.probe.update()
        c.probe.update()
        assert(#linesWith("summary ") == 1)
        assert(has(linesWith("summary ")[1], "hits=1 noRecord=0"))
        c.hit()
        assert(has(linesWith("hit ")[2], "open=? age=?"))
        assert(has(linesWith("hit ")[2], "S=?"))
    end)
end

return T
