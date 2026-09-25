local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")

local Procs = {}

local KEY_TYPE = "app.TARGET_ACCESS_KEY"

local blastDepth = 0
local installed = false

function Procs.reset()
    blastDepth = 0
end

function Procs.attackerIsMaster(key)
    if key == nil then return false end
    local character = Game.callStatic("app.TargetAccessKeyUtil", "getCharacter(app.TARGET_ACCESS_KEY)", key)
    if not character then return false end
    local ok, gameObject = pcall(function() return character:get_GameObject() end)
    if not ok then return false end
    return Game.isMasterGameObject(gameObject)
end

local function decodeKey(pointer)
    local ok, key = pcall(sdk.to_valuetype, pointer, KEY_TYPE)
    if ok then return key end
    return nil
end

local function onSetParam(args)
    if blastDepth <= 0 then return end
    local value = sdk.to_float(args[3])
    if type(value) ~= "number" or value <= 0 then return end
    if not Procs.attackerIsMaster(decodeKey(args[4])) then return end
    Session.addProc({ kind = "blast", damage = value, time = Game.uptime() })
    Log.debug("blast proc " .. tostring(value), "proc:blast")
end

function Procs.install()
    if installed then return end
    installed = true
    Game.hook("app.cEnemyBadConditionBlast", "onActivate", function()
        blastDepth = blastDepth + 1
    end, function()
        if blastDepth > 0 then blastDepth = blastDepth - 1 end
    end)
    Game.hook("app.cEnemyStockDamage.cBadConditionDamageInfo",
        "setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)", onSetParam)
end

return Procs
