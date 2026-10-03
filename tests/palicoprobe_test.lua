local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local MODULE_PATH = "reframework/autorun/MyHuntReport/PalicoProbe.lua"

local HOOKS = {
    playing = "app.cQuestPlaying.enter()",
    resultInfo = "app.cGUIQuestResultInfo.execute()",
    detail = "app.cEnemyStockDamage.stockDamageDetail(app.HitInfo)",
    hitMark = "app.cEnemyStockDamage.mcEnemyHitMarkManager.playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
    blast = "app.cEnemyBadConditionBlast.onActivate",
    setParam = "app.cEnemyStockDamage.cBadConditionDamageInfo.setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)",
    poison = "app.cEnemyBadConditionPoison.onUpdateActive",
    external = "app.cEnemyStockDamage.stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)",
}

local touched = 0

local function raising()
    return setmetatable({}, { __index = function(_, key)
        touched = touched + 1
        error("touched " .. tostring(key))
    end })
end

local function ppLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] pp ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function gameObject(name, address)
    return {
        name = name,
        get_Name = function() return name end,
        get_address = function() return address end,
    }
end

local MASTER = gameObject("MasterPlayer", 0x1000)
local REPLICA = gameObject("Player_Replica_1", 0x2000)

local function palico(name, address, owner, flags)
    flags = flags or {}
    local object = gameObject(name, address)
    local context = {
        get_IsNPC = function() return flags.npc == true end,
        get_IsPartnerNpcOtomo = function() return flags.partnerNpc == true end,
    }
    object.otomo = {
        get_IsMaster = function() return flags.mine == true end,
        get_IsMasterMyOtomo = function() return flags.mine == true end,
        get_ContextHolder = function()
            return { get_IsMaster = function() return flags.mine == true end, get_Otomo = function() return context end }
        end,
        get_OtomoContext = function()
            if flags.noContextGetter then error("no get_OtomoContext") end
            return context
        end,
        get_OwnerHunterCharacter = function() return { get_GameObject = function() return owner end } end,
        get_StableQuestMemberIndex = function() return flags.stableIndex or 0 end,
    }
    object.flags = flags
    return object
end

local function enemyOwner(index)
    return { em = { get_UniqueIndex = function() return index end } }
end

local function hitInfo(attacker, enemy, attackObjName, dataType, address)
    return {
        get_address = function() return address end,
        getActualAttackOwner = function() return attacker end,
        get_DamageOwner = function() return enemy end,
        get_AttackObj = function() return { get_Name = function() return attackObjName end } end,
        get_AttackData = function()
            return { get_type_definition = function() return { get_full_name = function() return dataType end } end }
        end,
    }
end

local function condition(enemyIndex, invoker)
    return { _This = { Category = 1, UniqueIndex = enemyIndex }, _Invoker = invoker }
end

local function withProbe(callback)
    local hook, callStatic, singleton = Game.hook, Game.callStatic, Game.singleton
    local componentOf, enemyContext, masterAddress, uptime = Game.componentOf, Game.enemyContext, Game.masterAddress, Game.uptime
    local toManaged, toValue, toFloat, findType = sdk.to_managed_object, sdk.to_valuetype, sdk.to_float, sdk.find_type_definition
    local hooks = {}
    local c = { hooks = hooks, now = 100.0, characters = {}, masterOtomo = nil, host = true, masterAddress = 0x1000 }
    touched = 0
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        Log.resetCounts()
        stubs.reset()
        Game.hook = function(typeName, signature, pre, post)
            hooks[typeName .. "." .. signature] = { pre = pre, post = post }
            return true
        end
        Game.callStatic = function(_, signature, key)
            local found = c.characters[key.Category .. "/" .. key.UniqueIndex]
            if not found then return nil end
            if signature == "getHunterCharacter(app.TARGET_ACCESS_KEY)" and key.Category == 2 then return nil end
            return { get_GameObject = function() return found end }
        end
        Game.singleton = function(name)
            if name ~= "app.OtomoManager" or not c.masterOtomo then return nil end
            return { getMasterOtomoInfo = function()
                return { get_Character = function() return { get_GameObject = function() return c.masterOtomo end } end }
            end }
        end
        Game.componentOf = function(object, typeName)
            if object and typeName == "app.OtomoCharacter" then return object.otomo end
            return nil
        end
        Game.enemyContext = function(object) return object and object.em or nil end
        Game.masterAddress = function() return c.masterAddress end
        Game.uptime = function() return c.now end
        sdk.to_managed_object = function(value) return value end
        sdk.to_valuetype = function(value) return value end
        sdk.to_float = function(value)
            if type(value) ~= "number" then error("not a float") end
            return value
        end
        sdk.find_type_definition = function(name)
            if name ~= "app.OtomoUtil" then return nil end
            return { get_method = function(_, method)
                if method ~= "isMultiplayHost" then return nil end
                return { call = function() return c.host end }
            end }
        end
        c.probe = assert(loadfile(MODULE_PATH))()
        c.probe.install(true)
        function c.pre(name, args)
            hooks[HOOKS[name]].pre(args)
        end
        function c.post(name)
            hooks[HOOKS[name]].post(nil)
        end
        function c.hit(attacker, final)
            c.hitAddress = (c.hitAddress or 0x9000) + 16
            local info = hitInfo(attacker, enemyOwner(7), "Sh200_0", "app.cAttackParamOt", c.hitAddress)
            c.pre("detail", { nil, nil, info })
            c.pre("hitMark", { nil, nil, { FinalDamage = final }, info })
        end
        callback(c)
    end)
    Game.hook, Game.callStatic, Game.singleton = hook, callStatic, singleton
    Game.componentOf, Game.enemyContext, Game.masterAddress, Game.uptime = componentOf, enemyContext, masterAddress, uptime
    sdk.to_managed_object, sdk.to_valuetype, sdk.to_float, sdk.find_type_definition = toManaged, toValue, toFloat, findType
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

local function withDeveloperProbe(callback)
    withProbe(function(c)
        Log.setDeveloperMode(true)
        callback(c)
    end)
end

function T.formatValueRoundsFloatsAndNamesNil()
    withProbe(function(c)
        assert(c.probe.formatValue(nil) == "nil")
        assert(c.probe.formatValue(true) == "true")
        assert(c.probe.formatValue(7) == "7")
        assert(c.probe.formatValue(12.34) == "12.3")
        assert(c.probe.formatValue("Otomo_00") == "Otomo_00")
    end)
end

function T.identityTextPrintsEveryFieldInOrderAndMarksMissingOnes()
    withProbe(function(c)
        local text = c.probe.identityText({ name = "Otomo_00", isMaster = "true", ctxVia = "get_OtomoContext" })
        assert(text == "name=Otomo_00 isMaster=true isMasterMyOtomo=? holderIsMaster=? ownerIsMaster=? ownerName=?"
            .. " npc=? partnerNpc=? ctxVia=get_OtomoContext stableIndex=? masterOtomo=?", text)
    end)
end

function T.summaryLinesComeFromPlainState()
    withProbe(function(c)
        local line = c.probe.summaryLine({
            id = "Otomo_00@3000", identity = { isMasterMyOtomo = "true", ownerIsMaster = "true", npc = "false" },
            detail = 4, mark = 3, positive = 2, matched = 3, unkeyed = 1, damage = 61.5,
            blast = 100, blastCount = 1, poison = 30, poisonCount = 2,
        })
        assert(line == "summary id=Otomo_00@3000 mine=true ownerIsMaster=true npc=false detail=4 mark=3 positive=2"
            .. " matched=3 unmatchedDetail=1 unmatchedMark=0 unkeyed=1 damage=61.5 blast=100.0 blastCount=1 poison=30.0 poisonCount=2", line)
        local bare = c.probe.summaryLine({
            id = "Otomo_01@4000", detail = 1, mark = 0, positive = 0, matched = 0, unkeyed = 0, damage = 0,
            blast = 0, blastCount = 0, poison = 0, poisonCount = 0,
        })
        assert(bare:find("mine=? ownerIsMaster=? npc=? detail=1 mark=0 positive=0 matched=0 unmatchedDetail=1 unmatchedMark=0", 1, true), bare)
        local tail = c.probe.summaryEndLine(2, {
            hits = 5, blastBrackets = 2, blastLines = 1, poisonBrackets = 9, poisonLines = 2, unresolved = 0,
        })
        assert(tail == "summary-end palicos=2 hits=5 blastBrackets=2 blastLines=1 poisonBrackets=9 poisonLines=2 unresolved=0", tail)
    end)
end

function T.installsTheHooksAndSkipsPoisonHooksWhenAskedTo()
    withProbe(function(c)
        for _, name in ipairs({ "playing", "resultInfo", "detail", "hitMark", "blast", "setParam", "poison", "external" }) do
            assert(c.hooks[HOOKS[name]], name)
        end
        local hook = Game.hook
        local seen = {}
        Game.hook = function(typeName, signature)
            seen[typeName .. "." .. signature] = true
            return true
        end
        assert(loadfile(MODULE_PATH))().install(false)
        Game.hook = hook
        assert(seen[HOOKS.detail] and seen[HOOKS.blast] and seen[HOOKS.setParam])
        assert(seen[HOOKS.poison] == nil and seen[HOOKS.external] == nil)
    end)
end

function T.palicoHitsAccumulatePerPalicoAndLogIdentityOnce()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        local other = palico("Otomo_01", 0x4000, REPLICA, { stableIndex = 1 })
        c.masterOtomo = mine
        c.hit(mine, 12.5)
        c.hit(mine, 0)
        c.hit(other, 20)
        c.hit(MASTER, 300)
        local lines = ppLines()
        assert(#lines == 5, #lines)
        assert(lines[1] == "[MyHuntReport] pp identity t=100.00 id=Otomo_00@3000 name=Otomo_00 isMaster=true"
            .. " isMasterMyOtomo=true holderIsMaster=true ownerIsMaster=true ownerName=MasterPlayer npc=false"
            .. " partnerNpc=false ctxVia=get_OtomoContext stableIndex=0 masterOtomo=true", lines[1])
        assert(lines[2] == "[MyHuntReport] pp hit t=100.00 em=7 id=Otomo_00@3000 final=12.5 matched=true obj=Sh200_0"
            .. " data=app.cAttackParamOt mine=true", lines[2])
        assert(lines[3]:find("pp hit t=100.00 em=7 id=Otomo_00@3000 final=0 matched=true ", 1, true), lines[3])
        assert(lines[4]:find("pp identity t=100.00 id=Otomo_01@4000 ", 1, true), lines[4])
        assert(lines[4]:find("isMasterMyOtomo=false", 1, true) and lines[4]:find("ownerIsMaster=false", 1, true))
        assert(lines[4]:find("ownerName=Player_Replica_1", 1, true) and lines[4]:find("masterOtomo=false", 1, true))
        assert(lines[5]:find("id=Otomo_01@4000 final=20 ", 1, true) and lines[5]:find("mine=false", 1, true), lines[5])
        local entry = c.probe.entry(0x3000)
        assert(entry.detail == 2 and entry.mark == 2 and entry.positive == 1 and entry.matched == 2 and entry.damage == 12.5)
        assert(c.probe.entry(0x4000).damage == 20 and c.probe.entry(0x1000) == nil)
        assert(c.probe.counters().hits == 3)
    end)
end

function T.identityIsLoggedAgainWhenAFieldChanges()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        c.hit(mine, 5)
        mine.flags.stableIndex = 2
        c.hit(mine, 5)
        c.hit(mine, 5)
        local identities = 0
        for _, line in ipairs(ppLines()) do
            if line:find("pp identity ", 1, true) then identities = identities + 1 end
        end
        assert(identities == 2, identities)
    end)
end

function T.identityFallsBackToTheHolderContextAndMarksFailedReads()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true, noContextGetter = true })
        mine.otomo.get_IsMasterMyOtomo = nil
        mine.otomo.get_IsMaster = function() return nil end
        c.hit(mine, 5)
        local line = ppLines()[1]
        assert(line:find(" isMaster=? isMasterMyOtomo=? ", 1, true), line)
        assert(line:find("npc=false partnerNpc=false ctxVia=get_ContextHolder", 1, true), line)
        assert(line:find("masterOtomo=?", 1, true), line)
    end)
end

function T.blastLinesAppearOnlyInsideABlastBracketAndCreditThePalico()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        c.characters["2/0"] = mine
        c.characters["0/0"] = MASTER
        local palicoKey = { Category = 2, UniqueIndex = 0 }
        c.pre("setParam", { nil, nil, 4.0, palicoKey })
        assert(#ppLines() == 0)
        c.pre("blast", { nil, condition(7, palicoKey) })
        assert(c.probe.bracketDepth() == 1)
        c.pre("setParam", { nil, nil, 100.0, palicoKey })
        c.pre("setParam", { nil, nil, 100.0, { Category = 0, UniqueIndex = 0 } })
        c.pre("setParam", { nil, nil, 50.0, { Category = 2, UniqueIndex = 9 } })
        c.pre("setParam", { nil, nil, "broken", palicoKey })
        c.pre("setParam", { nil, nil, 25.0, { UniqueIndex = 0 } })
        c.post("blast")
        assert(c.probe.bracketDepth() == 0)
        c.pre("setParam", { nil, nil, 100.0, palicoKey })
        local lines = ppLines()
        assert(#lines == 7, #lines)
        assert(lines[1] == "[MyHuntReport] pp blast-activate t=100.00 em=7 invoker=2/0 master=false", lines[1])
        assert(lines[2]:find("pp identity t=100.00 id=Otomo_00@3000 ", 1, true), lines[2])
        assert(lines[3]:find("pp blast t=100.00 em=7 value=100.0 key=2/0 master=false id=Otomo_00@3000 name=Otomo_00 ", 1, true), lines[3])
        assert(lines[4] == "[MyHuntReport] pp blast t=100.00 em=7 value=100.0 key=0/0 master=true", lines[4])
        assert(lines[5] == "[MyHuntReport] pp blast t=100.00 em=7 value=50.0 key=2/9 master=false id=?", lines[5])
        assert(lines[6]:find("pp blast t=100.00 em=7 value=? key=2/0 master=false id=Otomo_00@3000 ", 1, true), lines[6])
        assert(lines[7] == "[MyHuntReport] pp blast t=100.00 em=7 value=25.0 key=?/0 master=?", lines[7])
        local entry = c.probe.entry(0x3000)
        assert(entry.blast == 100.0 and entry.blastCount == 2 and entry.mark == 0)
        local counters = c.probe.counters()
        assert(counters.blastBrackets == 1 and counters.blastLines == 5 and counters.unresolved == 1)
    end)
end

function T.poisonLinesAppearOnlyInsideAPoisonBracketAndUseTheInvoker()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        c.characters["2/0"] = mine
        c.characters["0/0"] = MASTER
        local palicoKey, masterKey = { Category = 2, UniqueIndex = 0 }, { Category = 0, UniqueIndex = 0 }
        local nullable = { _HasValue = false, _Value = { Category = 0, UniqueIndex = 0 } }
        c.pre("external", { nil, nil, 15.0, nil, nullable })
        assert(#ppLines() == 0)
        c.pre("blast", { nil, condition(7, palicoKey) })
        c.pre("external", { nil, nil, 15.0, nil, nullable })
        c.post("blast")
        assert(#ppLines() == 1)
        stubs.logLines = {}
        c.pre("poison", { nil, condition(7, palicoKey) })
        c.pre("external", { nil, nil, 15.0, nil, nullable })
        c.post("poison")
        c.pre("poison", { nil, condition(7, palicoKey) })
        c.post("poison")
        c.pre("poison", { nil, condition(7, masterKey) })
        c.pre("external", { nil, nil, 15.0, nil, nullable })
        c.post("poison")
        local lines = ppLines()
        assert(#lines == 5, #lines)
        assert(lines[1] == "[MyHuntReport] pp poison-active t=100.00 em=7 invoker=2/0 master=false", lines[1])
        assert(lines[2]:find("pp identity t=100.00 id=Otomo_00@3000 ", 1, true), lines[2])
        assert(lines[3]:find("pp poison t=100.00 em=7 value=15.0 invoker=2/0 hasKey=false key=0/0 master=false id=Otomo_00@3000 ", 1, true), lines[3])
        assert(lines[4] == "[MyHuntReport] pp poison-active t=100.00 em=7 invoker=0/0 master=true", lines[4])
        assert(lines[5] == "[MyHuntReport] pp poison t=100.00 em=7 value=15.0 invoker=0/0 hasKey=false key=0/0 master=true", lines[5])
        local entry = c.probe.entry(0x3000)
        assert(entry.poison == 15.0 and entry.poisonCount == 1)
        local counters = c.probe.counters()
        assert(counters.poisonBrackets == 3 and counters.poisonLines == 2 and c.probe.bracketDepth() == 0)
    end)
end

function T.failedReadsPrintAQuestionMarkInsteadOfADefiniteValue()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        local info = hitInfo(mine, nil, "Sh200_0", "app.cAttackParamOt")
        info.get_DamageOwner = function() error("no damage owner") end
        c.masterAddress = nil
        c.pre("hitMark", { nil, nil, { FinalDamage = 9.0 }, info })
        local lines = ppLines()
        assert(lines[1]:find(" ownerIsMaster=? ownerName=MasterPlayer ", 1, true), lines[1])
        assert(lines[2] == "[MyHuntReport] pp hit t=100.00 em=? id=Otomo_00@3000 final=9.0 matched=? obj=Sh200_0"
            .. " data=app.cAttackParamOt mine=true", lines[2])
        c.masterAddress = 0x1000
        local unreadable = gameObject("Player_Replica_2", 0x5000)
        unreadable.get_address = function() error("no address") end
        local other = palico("Otomo_02", 0x6000, unreadable)
        c.hit(other, 3)
        lines = ppLines()
        assert(lines[3]:find("id=Otomo_02@6000 ", 1, true), lines[3])
        assert(lines[3]:find(" ownerIsMaster=? ownerName=Player_Replica_2 ", 1, true), lines[3])
        assert(c.probe.entry(0x3000).damage == 9.0 and c.probe.entry(0x6000).damage == 3)
        local addressless = gameObject("Player_Replica_3", nil)
        c.masterOtomo = gameObject("Otomo_00", nil)
        c.hit(palico("Otomo_03", 0x7000, addressless), 1)
        lines = ppLines()
        assert(lines[5]:find("id=Otomo_03@7000 ", 1, true), lines[5])
        assert(lines[5]:find(" ownerIsMaster=? ownerName=Player_Replica_3 ", 1, true), lines[5])
        assert(lines[5]:find(" masterOtomo=?", 1, true), lines[5])
    end)
end

function T.aFailedEnemyIndexReadPrintsAQuestionMarkInStatusLines()
    withDeveloperProbe(function(c)
        c.characters["0/0"] = MASTER
        local masterKey = { Category = 0, UniqueIndex = 0 }
        local broken = { _Invoker = masterKey }
        setmetatable(broken, { __index = function(_, key) error("no " .. tostring(key)) end })
        c.pre("blast", { nil, broken })
        c.pre("setParam", { nil, nil, 100.0, masterKey })
        c.post("blast")
        c.pre("poison", { nil, { _This = {}, _Invoker = masterKey } })
        c.pre("external", { nil, nil, 15.0, nil, { _HasValue = false, _Value = masterKey } })
        c.post("poison")
        local lines = ppLines()
        assert(#lines == 4, #lines)
        assert(lines[1] == "[MyHuntReport] pp blast-activate t=100.00 em=? invoker=0/0 master=true", lines[1])
        assert(lines[2] == "[MyHuntReport] pp blast t=100.00 em=? value=100.0 key=0/0 master=true", lines[2])
        assert(lines[3] == "[MyHuntReport] pp poison-active t=100.00 em=? invoker=0/0 master=true", lines[3])
        assert(lines[4] == "[MyHuntReport] pp poison t=100.00 em=? value=15.0 invoker=0/0 hasKey=false key=0/0 master=true", lines[4])
        assert(c.probe.bracketDepth() == 0)
    end)
end

function T.anActivationWithoutADamageCallIsStillVisible()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        c.characters["2/0"] = mine
        c.pre("blast", { nil, condition(7, { Category = 2, UniqueIndex = 0 }) })
        c.post("blast")
        c.pre("poison", { nil, condition(8, { Category = 2, UniqueIndex = 0 }) })
        c.post("poison")
        local lines = ppLines()
        assert(#lines == 2, #lines)
        assert(lines[1] == "[MyHuntReport] pp blast-activate t=100.00 em=7 invoker=2/0 master=false", lines[1])
        assert(lines[2] == "[MyHuntReport] pp poison-active t=100.00 em=8 invoker=2/0 master=false", lines[2])
        stubs.logLines = {}
        c.post("resultInfo")
        assert(ppLines()[1] == "[MyHuntReport] pp summary-end palicos=0 hits=0 blastBrackets=1 blastLines=0"
            .. " poisonBrackets=1 poisonLines=0 unresolved=0", ppLines()[1])
    end)
end

function T.unmatchedDetailAndMarkCallsAreCountedPerPalico()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        local first = hitInfo(mine, enemyOwner(7), "Otomo_00", "app.cAttackParamOt", 0xA000)
        local second = hitInfo(mine, enemyOwner(7), "Otomo_00", "app.cAttackParamOt", 0xB000)
        c.pre("detail", { nil, nil, first })
        c.pre("detail", { nil, nil, second })
        c.pre("hitMark", { nil, nil, { FinalDamage = 10.0 }, first })
        c.pre("hitMark", { nil, nil, { FinalDamage = 10.0 }, first })
        c.pre("hitMark", { nil, nil, {}, second })
        local lines = ppLines()
        assert(lines[2]:find(" final=10.0 matched=true ", 1, true), lines[2])
        assert(lines[3]:find(" final=10.0 matched=false ", 1, true), lines[3])
        assert(lines[4]:find(" final=? matched=true ", 1, true), lines[4])
        stubs.logLines = {}
        c.pre("detail", { nil, nil, first })
        c.post("resultInfo")
        assert(ppLines()[1]:find("detail=3 mark=3 positive=2 matched=2 unmatchedDetail=1 unmatchedMark=1 unkeyed=0 damage=20.0", 1, true), ppLines()[1])
    end)
end

function T.hitsWithoutAReadableIdentityNeverCountAsMatched()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        local addressless = hitInfo(mine, enemyOwner(7), "Otomo_00", "app.cAttackParamOt", nil)
        local throwing = hitInfo(mine, enemyOwner(7), "Otomo_00", "app.cAttackParamOt", nil)
        throwing.get_address = function() error("no address") end
        c.pre("detail", { nil, nil, addressless })
        c.pre("detail", { nil, nil, throwing })
        c.pre("hitMark", { nil, nil, { FinalDamage = 10.0 }, addressless })
        c.pre("hitMark", { nil, nil, { FinalDamage = 10.0 }, throwing })
        local lines = ppLines()
        assert(lines[2]:find(" final=10.0 matched=? ", 1, true), lines[2])
        assert(lines[3]:find(" final=10.0 matched=? ", 1, true), lines[3])
        stubs.logLines = {}
        c.post("resultInfo")
        assert(ppLines()[1]:find("detail=2 mark=2 positive=2 matched=0 unmatchedDetail=2 unmatchedMark=2 unkeyed=4 damage=20.0", 1, true), ppLines()[1])
    end)
end

function T.hitsAndStatusDamageForOnePalicoShareOneEntry()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        c.characters["2/0"] = mine
        local palicoKey = { Category = 2, UniqueIndex = 0 }
        c.hit(mine, 12.5)
        c.pre("blast", { nil, condition(7, palicoKey) })
        c.pre("setParam", { nil, nil, 100.0, palicoKey })
        c.post("blast")
        c.pre("poison", { nil, condition(7, palicoKey) })
        c.pre("external", { nil, nil, 15.0, nil, { _HasValue = false, _Value = { Category = 0, UniqueIndex = 0 } } })
        c.post("poison")
        local entry = c.probe.entry(0x3000)
        assert(entry.mark == 1 and entry.damage == 12.5)
        assert(entry.blast == 100.0 and entry.blastCount == 1 and entry.poison == 15.0 and entry.poisonCount == 1)
        local lines = ppLines()
        assert(#lines == 6, #lines)
        for _, index in ipairs({ 2, 4, 6 }) do assert(lines[index]:find(" id=Otomo_00@3000 ", 1, true), lines[index]) end
        stubs.logLines = {}
        c.post("resultInfo")
        lines = ppLines()
        assert(#lines == 2, #lines)
        assert(lines[1]:find("detail=1 mark=1 positive=1 matched=1 unmatchedDetail=0 unmatchedMark=0 unkeyed=0 damage=12.5"
            .. " blast=100.0 blastCount=1 poison=15.0 poisonCount=1", 1, true), lines[1])
        assert(lines[2] == "[MyHuntReport] pp summary-end palicos=1 hits=1 blastBrackets=1 blastLines=1"
            .. " poisonBrackets=1 poisonLines=1 unresolved=0", lines[2])
    end)
end

function T.questStartResetsStateAndLogsTheHostRead()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        c.hit(mine, 5)
        c.pre("blast", { nil, condition(7, { Category = 0, UniqueIndex = 0 }) })
        stubs.logLines = {}
        c.pre("playing", raising())
        assert(c.probe.entry(0x3000) == nil and c.probe.counters().hits == 0 and c.probe.bracketDepth() == 0)
        assert(ppLines()[1] == "[MyHuntReport] pp state host=true", ppLines()[1])
        sdk.find_type_definition = function() return nil end
        stubs.logLines = {}
        c.pre("playing", raising())
        assert(ppLines()[1] == "[MyHuntReport] pp state host=?", ppLines()[1])
        assert(touched == 0, touched)
    end)
end

function T.resultLogsOneSummaryPerPalicoInFirstSeenOrder()
    withDeveloperProbe(function(c)
        local mine = palico("Otomo_00", 0x3000, MASTER, { mine = true })
        local other = palico("Otomo_01", 0x4000, REPLICA)
        c.hit(other, 20)
        c.hit(mine, 12.5)
        stubs.logLines = {}
        c.post("resultInfo")
        c.post("resultInfo")
        local lines = ppLines()
        assert(#lines == 6, #lines)
        assert(lines[1]:find("pp summary id=Otomo_01@4000 mine=false ownerIsMaster=false npc=false detail=1 mark=1 positive=1", 1, true), lines[1])
        assert(lines[1]:find(" unmatchedDetail=0 unmatchedMark=0 unkeyed=0 damage=20.0 ", 1, true), lines[1])
        assert(lines[2]:find("pp summary id=Otomo_00@3000 mine=true ownerIsMaster=true npc=false detail=1 mark=1 positive=1", 1, true), lines[2])
        assert(lines[2]:find(" unmatchedDetail=0 unmatchedMark=0 unkeyed=0 damage=12.5 ", 1, true), lines[2])
        assert(lines[3] == "[MyHuntReport] pp summary-end palicos=2 hits=2 blastBrackets=0 blastLines=0"
            .. " poisonBrackets=0 poisonLines=0 unresolved=0", lines[3])
        assert(lines[4] == lines[1] and lines[6] == lines[3])
    end)
end

function T.nothingIsReadOrLoggedWhenDeveloperModeIsOff()
    withProbe(function(c)
        for _, name in ipairs({ "detail", "hitMark", "blast", "setParam", "poison", "external" }) do
            c.pre(name, raising())
        end
        c.post("blast")
        c.post("poison")
        c.post("resultInfo")
        c.pre("playing", raising())
        assert(#ppLines() == 0)
        assert(touched == 0, touched)
        assert(c.probe.bracketDepth() == 0)
        for _, name in ipairs(c.probe.COUNTER_ORDER) do assert(c.probe.counters()[name] == 0, name) end
    end)
end

function T.bracketsOpenedWhileDeveloperModeIsOffStayBalancedAndSilent()
    withDeveloperProbe(function(c)
        c.characters["0/0"] = MASTER
        local masterKey = { Category = 0, UniqueIndex = 0 }
        local nullable = { _HasValue = false, _Value = masterKey }
        c.pre("blast", { nil, condition(7, masterKey) })
        Log.setDeveloperMode(false)
        c.pre("poison", raising())
        assert(c.probe.bracketDepth() == 2)
        Log.setDeveloperMode(true)
        c.pre("external", { nil, nil, 15.0, nil, nullable })
        c.pre("setParam", { nil, nil, 100.0, masterKey })
        c.post("poison")
        assert(c.probe.bracketDepth() == 1)
        c.pre("setParam", { nil, nil, 100.0, masterKey })
        c.post("blast")
        assert(c.probe.bracketDepth() == 0 and touched == 0)
        local lines = ppLines()
        assert(#lines == 2, #lines)
        assert(lines[1] == "[MyHuntReport] pp blast-activate t=100.00 em=7 invoker=0/0 master=true", lines[1])
        assert(lines[2] == "[MyHuntReport] pp blast t=100.00 em=7 value=100.0 key=0/0 master=true", lines[2])
        c.post("blast")
        assert(c.probe.bracketDepth() == 0)
    end)
end

return T
