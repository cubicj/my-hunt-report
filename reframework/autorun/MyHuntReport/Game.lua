local Log = require("MyHuntReport.Log")
local Locale = require("MyHuntReport.Locale")

local Game = {}

local typeCache = {}
local methodCache = {}

function Game.typeDefinition(name)
    local cached = typeCache[name]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local ok, td = pcall(sdk.find_type_definition, name)
    if not ok or td == nil then
        typeCache[name] = false
        Log.error("type not found: " .. name, "type:" .. name)
        return nil
    end
    typeCache[name] = td
    return td
end

function Game.method(typeName, signature)
    local key = typeName .. "::" .. signature
    local cached = methodCache[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local td = Game.typeDefinition(typeName)
    local method = nil
    if td then
        local ok, found = pcall(td.get_method, td, signature)
        if ok then method = found end
    end
    if method == nil then
        methodCache[key] = false
        Log.error("method not found: " .. key, "method:" .. key)
        return nil
    end
    methodCache[key] = method
    return method
end

function Game.hook(typeName, signature, pre, post)
    local method = Game.method(typeName, signature)
    if not method then return false end
    local label = typeName .. "." .. signature
    local function safePre(args)
        if pre then
            local ok, err = pcall(pre, args)
            if not ok then Log.error("hook pre failed " .. label .. ": " .. tostring(err), "hookpre:" .. label) end
        end
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    local function safePost(retval)
        if post then
            local ok, err = pcall(post, retval)
            if not ok then Log.error("hook post failed " .. label .. ": " .. tostring(err), "hookpost:" .. label) end
        end
        return retval
    end
    local ok, err = pcall(sdk.hook, method, safePre, safePost)
    if not ok then
        Log.error("hook install failed " .. label .. ": " .. tostring(err), "hook:" .. label)
        return false
    end
    Log.debug("hook installed " .. label)
    return true
end

function Game.singleton(name)
    local ok, object = pcall(sdk.get_managed_singleton, name)
    if ok and object ~= nil then return object end
    return nil
end

function Game.masterHunter()
    local manager = Game.singleton("app.PlayerManager")
    if not manager then return nil end
    local ok, hunter = pcall(function()
        local info = manager:getMasterPlayer()
        if not info then return nil end
        return info:get_Character()
    end)
    if ok then return hunter end
    return nil
end

function Game.callStatic(typeName, signature, ...)
    local method = Game.method(typeName, signature)
    if not method then return nil, "method missing " .. typeName .. "::" .. signature end
    local ok, value = pcall(function(...) return method:call(nil, ...) end, ...)
    if ok then return value end
    return nil, tostring(value)
end

function Game.isUsableText(text)
    return type(text) == "string" and text ~= ""
        and not text:find("#Rejected#", 1, true) and not text:find("---", 1, true)
end

function Game.messageText(guid)
    if guid == nil then return nil end
    local language = Locale.viaLanguage()
    local text
    if language then
        text = Game.callStatic("via.gui.message", "get(System.Guid, via.Language)", guid, language)
    else
        text = Game.callStatic("via.gui.message", "get(System.Guid)", guid)
    end
    if type(text) ~= "string" or #text == 0 then return nil end
    return text
end

function Game.resetCaches()
    typeCache = {}
    methodCache = {}
end

local LANGUAGE_KOREAN = 9

function Game.languageCode()
    local value = Game.callStatic("app.OptionUtil", "getTextLanguage()")
    if type(value) ~= "number" then return nil, nil end
    if value == LANGUAGE_KOREAN then return "ko", value end
    return "en", value
end

function Game.componentOf(gameObject, typeName)
    if gameObject == nil then return nil end
    local ok, component = pcall(function()
        return gameObject:call("getComponent(System.Type)", sdk.typeof(typeName))
    end)
    if ok then return component end
    return nil
end

function Game.masterAddress()
    local hunter = Game.masterHunter()
    if not hunter then return nil end
    local ok, address = pcall(function()
        return hunter:get_GameObject():get_address()
    end)
    if ok then return address end
    return nil
end

function Game.isMasterGameObject(gameObject)
    if gameObject == nil then return false end
    local master = Game.masterAddress()
    if not master then return false end
    local ok, address = pcall(function() return gameObject:get_address() end)
    return ok and address == master
end

function Game.enemyContext(gameObject)
    local enemy = Game.componentOf(gameObject, "app.EnemyCharacter")
    if not enemy then return nil end
    local ok, em = pcall(function()
        local holder = enemy._Context
        if not holder then return nil end
        return holder._Em
    end)
    if ok then return em end
    return nil
end

function Game.enemyIsDead(gameObject)
    local enemy = Game.componentOf(gameObject, "app.EnemyCharacter")
    if not enemy then return false end
    local ok, dead = pcall(function()
        return enemy:get_HealthMgr():get_IsDead()
    end)
    return ok and dead == true
end

function Game.uptime()
    local value = Game.callStatic("via.Application", "get_UpTimeSecond")
    if type(value) == "number" then return value end
    return os.clock()
end

return Game
