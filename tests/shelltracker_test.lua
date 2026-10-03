local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Locale = require("MyHuntReport.Locale")

local T = {}

local function fakeAction(className, guideId)
    return {
        get_type_definition = function() return { get_name = function() return className end } end,
        _ActionGuideID = guideId,
    }
end

local function withShellTracker(callback)
    local hook, master, component, call, managed = Game.hook, Game.masterHunter, Game.componentOf, Game.callStatic, sdk.to_managed_object
    local hunter = {
        weaponType = 13, base = fakeAction("cActBase", 100), sub = fakeAction("cShootRapidLight", 200),
        handling = { _ActionShellType = 3, SelectedBottleItem = 5678, get_BottleType = function() return 1 end },
    }
    function hunter:call(getter)
        local action = getter == "get_SubActionController" and self.sub or self.base
        return { get_CurrentAction = function() return action end }
    end
    function hunter:get_WeaponType() return self.weaponType end
    function hunter:get_WeaponHandling() return self.handling end
    local hooks = {}
    Game.hook = function(_, signature, pre) hooks[signature] = pre end
    Game.masterHunter = function() return hunter end
    Game.componentOf = function(object) return object end
    Game.callStatic = function(typeName, signature, shellType)
        assert(typeName == "app.WeaponGunDef" and signature == "getItemIDFromShellType(System.Int32)")
        assert(shellType == 3)
        return 1234
    end
    sdk.to_managed_object = function(object) return object end
    local tracker = assert(loadfile("reframework/autorun/MyHuntReport/ShellTracker.lua"))()
    tracker.install()
    local ok, err = pcall(callback, tracker, hooks, hunter)
    Game.hook, Game.masterHunter, Game.componentOf, Game.callStatic, sdk.to_managed_object = hook, master, component, call, managed
    if not ok then error(err, 0) end
end

local function shell(address, parent, hash)
    return {
        get_address = function() return address end,
        get_ParentShell = function() return parent end,
        call = function(_, getter)
            assert(getter == "get_NameHash")
            return hash
        end,
    }
end

local function assertMarkShotEntry(tracker, object)
    local key, label, hitTime = tracker.nameForAttackObject(object)
    assert(stubs.encode({ key = key, label = label, hitTime = hitTime }) == stubs.encode({
        key = "cGunShot",
        label = { kind = "motion", className = "cGunShot", guideId = -1726610048, weaponType = 10 },
    }))
end

function T.shellGlaiveMarkShotHashesOverrideMovingAndJumpingActions()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 10
        hunter.sub = fakeAction("cNothing", -1)
        for _, className in ipairs({ "cMove", "cSelfJump" }) do
            hunter.base = fakeAction(className, 100)
            for _, hash in ipairs({ 729186967, 509541477, 2205688478, 1292422029 }) do
                local object = shell(hash, nil, hash)
                hooks.doOnSetUp({ [2] = object })
                assertMarkShotEntry(tracker, object)
            end
        end
    end)
end

function T.shellGlaiveMarkShotPrecedesParentLookup()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 10
        hunter.sub = fakeAction("cNothing", -1)
        local parent = shell(1)
        hooks.doOnSetUp({ [2] = parent })
        assert(tracker.nameForAttackObject(parent) == "cActBase")
        local parentReads = 0
        local child = shell(2, parent, 1292422029)
        child.get_ParentShell = function()
            parentReads = parentReads + 1
            return parent
        end
        hooks.doOnSetUp({ [2] = child })
        assertMarkShotEntry(tracker, child)
        assert(parentReads == 0)
        hooks.doOnDestroy({ [2] = parent })
        assert(tracker.nameForAttackObject(parent) == nil)
        hunter.base = fakeAction("cSelfJump", 101)
        hooks.doOnSetUp({ [2] = child })
        assertMarkShotEntry(tracker, child)
        assert(parentReads == 0)
    end)
end

local function assertHelmbreakerEntry(tracker, object)
    local key, label, hitTime = tracker.nameForAttackObject(object)
    assert(stubs.encode({ key = key, label = label, hitTime = hitTime }) == stubs.encode({
        key = "cKabutowariLand",
        label = { kind = "motion", className = "cKabutowariLand", guideId = 1909693824, weaponType = 3 },
    }))
end

function T.shellLongSwordHelmbreakerDelayedShellsIgnoreCurrentAction()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 3
        hunter.sub = fakeAction("cNothing", -1)
        hunter.handling = { _IsKabutowariDelayHitSetup = true }
        for _, className in ipairs({ "cKabutowariLand", "cIaiWpOff", "cRenkiReleaseSlash", "cKijinSlash1" }) do
            hunter.base = fakeAction(className, 100)
            for _, hash in ipairs({ 1344756103, 3676865012, 4065868603, 1585023120 }) do
                local object = shell(hash, nil, hash)
                hooks.doOnSetUp({ [2] = object })
                assertHelmbreakerEntry(tracker, object)
            end
        end
    end)
end

function T.shellLongSwordWithoutDelayFlagKeepsCurrentAction()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 3
        hunter.sub = fakeAction("cNothing", -1)
        hunter.base = fakeAction("cIaiWpOff", -1559988736)
        for _, handling in ipairs({
            { _IsKabutowariDelayHitSetup = false },
            {},
            setmetatable({}, { __index = function() error("field unavailable") end }),
        }) do
            hunter.handling = handling
            local object = shell(4065868603, nil, 4065868603)
            hooks.doOnSetUp({ [2] = object })
            local key, label = tracker.nameForAttackObject(object)
            assert(key == "cIaiWpOff" and label.guideId == -1559988736 and label.weaponType == 3)
        end
    end)
end

function T.shellLongSwordDelayFlagOnOtherWeaponsKeepsExistingRules()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 7
        hunter.sub = fakeAction("cNothing", -1)
        hunter.handling = { _IsKabutowariDelayHitSetup = true }
        local object = shell(1344756103, nil, 1344756103)
        hooks.doOnSetUp({ [2] = object })
        local key, label = tracker.nameForAttackObject(object)
        assert(key == "cActBase" and label.guideId == 100 and label.weaponType == 7)
    end)
end

function T.shellLongSwordParentLabelPrecedesHelmbreakerFlag()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 3
        hunter.sub = fakeAction("cNothing", -1)
        hunter.handling = { _IsKabutowariDelayHitSetup = false }
        hunter.base = fakeAction("cRenkiReleaseSlash", -1093563648)
        local parent = shell(1)
        hooks.doOnSetUp({ [2] = parent })
        hunter.handling._IsKabutowariDelayHitSetup = true
        local child = shell(2, parent, 1344756103)
        hooks.doOnSetUp({ [2] = child })
        local key, label = tracker.nameForAttackObject(child)
        assert(key == "cRenkiReleaseSlash" and label.guideId == -1093563648)
    end)
end

local function assertFocusStrikeEntry(tracker, object)
    local key, label, hitTime = tracker.nameForAttackObject(object)
    assert(stubs.encode({ key = key, label = label, hitTime = hitTime }) == stubs.encode({
        key = "cWeakHitSlashDir",
        label = { kind = "motion", className = "cWeakHitSlashDir", guideId = -1840683648, weaponType = 3 },
    }))
end

function T.shellLongSwordFocusStrikeDelayedShellsIgnoreCurrentAction()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 3
        hunter.sub = fakeAction("cNothing", -1)
        hunter.handling = { _IsWeakPointBreakDelayReserve = true }
        for _, action in ipairs({
            { "cSlash1", -1997082496 }, { "cWeakHitSlashDir", -1840683648 }, { "cIaiWpOff", -1559988736 }, { "cKijinSlash1", 100 },
        }) do
            hunter.base = fakeAction(action[1], action[2])
            local object = shell(1689179270, nil, 1689179270)
            hooks.doOnSetUp({ [2] = object })
            assertFocusStrikeEntry(tracker, object)
        end
    end)
end

function T.shellLongSwordWithoutFocusStrikeFlagKeepsCurrentAction()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 3
        hunter.sub = fakeAction("cNothing", -1)
        hunter.base = fakeAction("cSlash1", -1997082496)
        for _, handling in ipairs({
            { _IsWeakPointBreakDelayReserve = false },
            {},
            setmetatable({}, { __index = function() error("field unavailable") end }),
        }) do
            hunter.handling = handling
            local object = shell(1689179270, nil, 1689179270)
            hooks.doOnSetUp({ [2] = object })
            local key, label = tracker.nameForAttackObject(object)
            assert(key == "cSlash1" and label.guideId == -1997082496 and label.weaponType == 3)
        end
    end)
end

function T.shellLongSwordHelmbreakerFlagPrecedesFocusStrikeFlag()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 3
        hunter.sub = fakeAction("cNothing", -1)
        hunter.base = fakeAction("cSlash1", -1997082496)
        hunter.handling = { _IsKabutowariDelayHitSetup = true, _IsWeakPointBreakDelayReserve = true }
        local object = shell(1689179270, nil, 1689179270)
        hooks.doOnSetUp({ [2] = object })
        assertHelmbreakerEntry(tracker, object)
    end)
end

function T.shellLongSwordFocusStrikeFlagOnOtherWeaponsKeepsExistingRules()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 7
        hunter.sub = fakeAction("cNothing", -1)
        hunter.handling = { _IsWeakPointBreakDelayReserve = true }
        local object = shell(1689179270, nil, 1689179270)
        hooks.doOnSetUp({ [2] = object })
        local key, label = tracker.nameForAttackObject(object)
        assert(key == "cActBase" and label.guideId == 100 and label.weaponType == 7)
    end)
end

function T.shellLongSwordParentLabelPrecedesFocusStrikeFlag()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 3
        hunter.sub = fakeAction("cNothing", -1)
        hunter.handling = { _IsWeakPointBreakDelayReserve = false }
        hunter.base = fakeAction("cRenkiReleaseSlash", -1093563648)
        local parent = shell(1)
        hooks.doOnSetUp({ [2] = parent })
        hunter.handling._IsWeakPointBreakDelayReserve = true
        local child = shell(2, parent, 1689179270)
        hooks.doOnSetUp({ [2] = child })
        local key, label = tracker.nameForAttackObject(child)
        assert(key == "cRenkiReleaseSlash" and label.guideId == -1093563648)
    end)
end

function T.shellGlaiveMarkShotHashesOnOtherWeaponsKeepExistingRules()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 7
        hunter.sub = fakeAction("cNothing", -1)
        for _, hash in ipairs({ 729186967, 509541477, 2205688478, 1292422029 }) do
            local object = shell(hash, nil, hash)
            hooks.doOnSetUp({ [2] = object })
            local key, label = tracker.nameForAttackObject(object)
            assert(key == "cActBase" and label.guideId == 100 and label.weaponType == 7)
            local child = shell(hash + 1, object, hash)
            hooks.doOnSetUp({ [2] = child })
            local childKey, childLabel = tracker.nameForAttackObject(child)
            assert(childKey == key and childLabel == label)
        end
    end)
end

function T.shellGlaiveUnreadableAndOtherHashesKeepExistingRules()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 10
        hunter.sub = fakeAction("cNothing", -1)
        for _, mode in ipairs({ "error", "nil", "other" }) do
            hunter.base = fakeAction("cMove", 100)
            local object = shell(1, nil, mode == "other" and 2937373860 or nil)
            if mode == "error" then object.call = function() error("hash unavailable") end end
            hooks.doOnSetUp({ [2] = object })
            local key, label = tracker.nameForAttackObject(object)
            assert(key == "cMove" and label.guideId == 100 and label.weaponType == 10)
            hunter.base = fakeAction("cSelfJump", 101)
            local child = shell(2, object)
            child.call = object.call
            hooks.doOnSetUp({ [2] = child })
            local childKey, childLabel = tracker.nameForAttackObject(child)
            assert(childKey == key and childLabel == label)
        end
    end)
end

function T.shellGlaiveUnavailableHunterOrWeaponTypeFallsThrough()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 10
        hunter.sub = fakeAction("cNothing", -1)
        hunter.get_WeaponType = function() error("weapon type unavailable") end
        local object = shell(1, nil, 729186967)
        hooks.doOnSetUp({ [2] = object })
        local key, label = tracker.nameForAttackObject(object)
        assert(key == "cActBase" and label.guideId == 100 and label.weaponType == nil)
        Game.masterHunter = function() return nil end
        local child = shell(2, object, 1292422029)
        hooks.doOnSetUp({ [2] = child })
        local childKey, childLabel = tracker.nameForAttackObject(child)
        assert(childKey == key and childLabel == label)
        hooks.doOnSetUp({ [2] = object })
        assert(tracker.nameForAttackObject(object) == nil)
    end)
end

function T.shellCurrentActionUsesShootingSubControllerOnly()
    withShellTracker(function(tracker, hooks, hunter)
        local className, guideId, source = tracker.currentAction(hunter)
        assert(className == "cShootRapidLight" and guideId == 200 and source == "sub")
        hunter.sub = fakeAction("cShotNormal", 201)
        className, guideId, source = tracker.currentAction(hunter)
        assert(className == "cShotNormal" and guideId == 201 and source == "sub")
        hunter.sub = fakeAction("cMove", 202)
        className, guideId, source = tracker.currentAction(hunter)
        assert(className == "cActBase" and guideId == 100 and source == "base")
        hunter.base = fakeAction("cDodgeFront", 203)
        className, guideId, source = tracker.currentAction(hunter, true)
        assert(className == "cDodgeFront" and guideId == 203 and source == "nonattack")
        assert(tracker.currentAction(nil) == nil)
    end)
end

function T.shellGunnerLabelsUseStableItemIds()
    withShellTracker(function(tracker, hooks, hunter)
        for _, weaponType in ipairs({ 12, 13 }) do
            hunter.weaponType = weaponType
            local object = shell(weaponType)
            Locale.resolve("ko")
            hooks.doOnSetUp({ [2] = object })
            local key, label = tracker.nameForAttackObject(object)
            assert(key == "ammo:1234")
            assert(label.kind == "motion" and label.className == "cShootRapidLight")
            assert(label.guideId == 200 and label.itemId == 1234)
            assert(label.itemRole == "ammo" and label.rapid == nil)
            Locale.resolve("en")
            hooks.doOnSetUp({ [2] = object })
            assert(tracker.nameForAttackObject(object) == key)
            hunter.sub = fakeAction("cShootFullAutoLight", 200)
            hooks.doOnSetUp({ [2] = object })
            local fullAutoKey, fullAutoLabel = tracker.nameForAttackObject(object)
            assert(fullAutoKey == key and fullAutoLabel.className == "cShootFullAutoLight")
            hunter.sub = fakeAction("cShootRapidLight", 200)
        end
    end)
end

function T.shellAmmoRapidFlagRequiresTrue()
    withShellTracker(function(tracker, hooks, hunter)
        local object = shell(1)
        for _, weaponType in ipairs({ 12, 13 }) do
            hunter.weaponType = weaponType
            for _, value in ipairs({ true, false, 1, "true" }) do
                hunter.handling._IsRapidShotBoost = value
                hooks.doOnSetUp({ [2] = object })
                local key, label = tracker.nameForAttackObject(object)
                local rapid = value == true and true or nil
                assert(label.rapid == rapid and label.itemRole == "ammo")
                assert(key == (rapid and "ammo:1234:rapid" or "ammo:1234"), key)
            end
        end
    end)
end

function T.shellAmmoTechniqueKeysUseGuideIdAndRapidVariant()
    withShellTracker(function(tracker, hooks, hunter)
        local object = shell(1)
        for _, weaponType in ipairs({ 12, 13 }) do
            hunter.weaponType = weaponType
            for _, className in ipairs({ "cShootNormalVariableLight", "cShootStepDodgeLight" }) do
                hunter.sub = fakeAction(className, 201)
                for _, rapid in ipairs({ false, true }) do
                    hunter.handling._IsRapidShotBoost = rapid
                    hooks.doOnSetUp({ [2] = object })
                    local key, label = tracker.nameForAttackObject(object)
                    assert(key == "ammo:1234:201" .. (rapid and ":rapid" or ""), key)
                    assert(label.className == className and label.guideId == 201)
                    assert(label.itemId == 1234 and label.itemRole == "ammo")
                    assert(label.rapid == (rapid and true or nil))
                end
            end
        end
    end)
end

function T.shellSpecialAndInvalidAmmoKeepActionLabel()
    withShellTracker(function(tracker, hooks, hunter)
        local object = shell(1)
        hunter.handling._IsRapidShotBoost = true
        for _, weaponType in ipairs({ 12, 13 }) do
            hunter.weaponType = weaponType
            for _, shellType in ipairs({ 27, 28 }) do
                hunter.handling._ActionShellType = shellType
                Game.callStatic = function(typeName, signature, value)
                    assert(typeName == "app.WeaponGunDef" and signature == "getItemIDFromShellType(System.Int32)")
                    assert(value == shellType)
                    return 0
                end
                hooks.doOnSetUp({ [2] = object })
                local key, label = tracker.nameForAttackObject(object)
                assert(key == "cShootRapidLight" and label.guideId == 200)
                assert(label.itemId == nil and label.itemRole == nil and label.rapid == nil)
            end
            for _, itemId in ipairs({ -1, "1234", false }) do
                Game.callStatic = function() return itemId end
                hooks.doOnSetUp({ [2] = object })
                local key, label = tracker.nameForAttackObject(object)
                assert(key == "cShootRapidLight", key)
                assert(label.itemId == nil and label.itemRole == nil and label.rapid == nil)
            end
        end
    end)
end

function T.shellUnreadableRapidFlagKeepsActionLabel()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.handling = setmetatable({ _ActionShellType = 3 }, {
            __index = function(_, field)
                assert(field == "_IsRapidShotBoost")
                error("handling unavailable")
            end,
        })
        local object = shell(1)
        hooks.doOnSetUp({ [2] = object })
        local key, label = tracker.nameForAttackObject(object)
        assert(key == "cShootRapidLight", key)
        assert(label.itemId == nil and label.itemRole == nil and label.rapid == nil)
    end)
end

function T.shellNonGunnerLabelIgnoresAmmoAndRapid()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 7
        hunter.sub = fakeAction("cMove", 202)
        hunter.handling._IsRapidShotBoost = true
        local object = shell(1)
        hooks.doOnSetUp({ [2] = object })
        local key, label = tracker.nameForAttackObject(object)
        assert(key == "cActBase" and label.className == "cActBase" and label.guideId == 100)
        assert(label.itemId == nil and label.itemRole == nil and label.rapid == nil)
    end)
end

function T.shellCoatingUsesSelectedItemWithoutBottleCache()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 11
        local object = shell(11)
        hooks.doOnSetUp({ [2] = object })
        local key, label = tracker.nameForAttackObject(object)
        assert(key == "cShootRapidLight 5678" and label.itemId == 5678)
        assert(label.itemRole == "coating" and label.rapid == nil)
        hunter.handling.SelectedBottleItem = 5679
        hooks.doOnSetUp({ [2] = object })
        key, label = tracker.nameForAttackObject(object)
        assert(key == "cShootRapidLight 5679" and label.itemId == 5679)
        assert(label.itemRole == "coating" and label.rapid == nil)
        hunter.handling.get_BottleType = function() return 0 end
        hooks.doOnSetUp({ [2] = object })
        key, label = tracker.nameForAttackObject(object)
        assert(key == "cShootRapidLight" and label.itemId == nil)
        assert(label.itemRole == nil and label.rapid == nil)
    end)
end

function T.shellChildKeepsParentLabelAndDestroyAndResetClearEntries()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.handling._IsRapidShotBoost = true
        local parent = shell(1)
        hooks.doOnSetUp({ [2] = parent })
        local parentKey, parentLabel = tracker.nameForAttackObject(parent)
        assert(parentKey == "ammo:1234:rapid" and parentLabel.itemRole == "ammo" and parentLabel.rapid == true)
        hunter.sub = fakeAction("cShootOther", 300)
        hunter.handling._IsRapidShotBoost = false
        local child = shell(2, parent)
        hooks.doOnSetUp({ [2] = child })
        local key, label = tracker.nameForAttackObject(child)
        assert(key == parentKey and label == parentLabel)
        assert(label.className == "cShootRapidLight")
        hooks.doOnDestroy({ [2] = parent })
        assert(tracker.nameForAttackObject(parent) == nil)
        assert(tracker.nameForAttackObject(child) == parentKey)
        tracker.reset()
        assert(tracker.nameForAttackObject(child) == nil)
    end)
end

function T.nonAttackClassifierMatchesOnlyEstablishedPatterns()
    withShellTracker(function(tracker)
        for _, name in ipairs({ "cDodgeFront", "cDamageSmash", "cLandSmash", "cMove", "cAimWalk", "cDash", "cUseItem", "cSlingerAim" }) do
            assert(tracker.isNonAttackAction(name) == true, name)
        end
        for _, name in ipairs({ "cMoveAttack", "cSlash", "cShot", "prefixcDodge", false, 10 }) do
            assert(tracker.isNonAttackAction(name) == false, tostring(name))
        end
        assert(tracker.isNonAttackAction(nil) == false)
    end)
end

function T.shellCurrentActionSlingerPrecedesBaseAndLaunchAmmoReads()
    withShellTracker(function(tracker, hooks, hunter)
        for _, className in ipairs({ "cSlingerShootReload", "cCatchSlingerShoot" }) do
            for _, hitTime in ipairs({ false, true }) do
                hunter.sub = fakeAction(className, 201)
                hunter.base = setmetatable({}, { __index = function() error("base unavailable") end })
                local key, guideId, source, kind = tracker.currentAction(hunter, hitTime)
                assert(key == className and guideId == 201 and source == "sub" and kind == "slinger")
                hunter.get_WeaponType = function() error("slinger must not read weapon type") end
                local object = shell(1)
                hooks.doOnSetUp({ [2] = object })
                local launchKey, label = tracker.nameForAttackObject(object)
                assert(launchKey == "slinger" and stubs.encode(label) == stubs.encode({ kind = "slinger" }))
            end
        end
    end)
end

function T.shellCurrentActionRidingUsesAnyNonNothingSubAndLaunchGuide()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.weaponType = 7
        hunter.base = fakeAction("cPorterRideRun", 100)
        for _, sub in ipairs({ "cPorterRideAttack1", "cPorterRideMusicLoop", "cPorterRideAddMusicLoop", "cChargeLoop" }) do
            hunter.sub = fakeAction(sub, 202)
            for _, hitTime in ipairs({ false, true }) do
                local key, guideId, source, kind = tracker.currentAction(hunter, hitTime)
                assert(key == sub and guideId == 202 and source == "sub" and kind == nil)
            end
            local object = shell(1)
            hooks.doOnSetUp({ [2] = object })
            local key, label = tracker.nameForAttackObject(object)
            assert(key == sub and label.kind == "motion" and label.className == sub and label.guideId == 202)
        end
        hunter.sub = fakeAction("cNothing", 203)
        local key, guideId, source, kind = tracker.currentAction(hunter)
        assert(key == "cPorterRideRun" and guideId == 100 and source == "base" and kind == nil)
        hunter.sub = fakeAction("cChargeLoop", 202)
        hunter.base = fakeAction("prefixcPorterRideRun", 100)
        key, guideId, source, kind = tracker.currentAction(hunter)
        assert(key == "prefixcPorterRideRun" and source == "base" and kind == nil)
    end)
end

function T.shellCurrentActionRidingMissingOrFailedSubKeepsBase()
    withShellTracker(function(tracker, hooks, hunter)
        hunter.base = fakeAction("cPorterRideRun", 100)
        for _, mode in ipairs({ "nil", "controller", "action", "class", "guide" }) do
            hunter.call = function(_, getter)
                if getter == "get_BaseActionController" then
                    return { get_CurrentAction = function() return hunter.base end }
                end
                if mode == "nil" then return nil end
                if mode == "controller" then error("controller unavailable") end
                return { get_CurrentAction = function()
                    if mode == "action" then error("action unavailable") end
                    return setmetatable({ get_type_definition = function()
                        if mode == "class" then error("class unavailable") end
                        return { get_name = function() return "cPorterRideAttack1" end }
                    end }, { __index = function() error("guide unavailable") end })
                end }
            end
            local key, guideId, source, kind = tracker.currentAction(hunter, true)
            assert(kind == nil)
            if mode == "guide" then
                assert(key == "cPorterRideAttack1" and guideId == -1 and source == "sub")
            else
                assert(key == "cPorterRideRun" and guideId == 100 and source == "base")
            end
        end
    end)
end

return T
