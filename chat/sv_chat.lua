local chat = class("chat", vRP.Extension)

RegisterServerEvent('chat:init')
RegisterServerEvent('chat:addTemplate')
RegisterServerEvent('chat:addMessage')
RegisterServerEvent('chat:addSuggestion')
RegisterServerEvent('chat:removeSuggestion')
RegisterServerEvent('_chat:messageEntered')
RegisterServerEvent('chat:clear')
RegisterServerEvent('__cfx_internal:commandFallback')

-- this is a built-in event, but somehow needs to be registered
RegisterNetEvent('playerJoining')

exports('addMessage', function(target, message)
    if not message then
        message = target
        target = -1
    end

    if not target or not message then return end

    TriggerClientEvent('chat:addMessage', target, message)
end)

local hooks = {}
local hookIdx = 1

exports('registerMessageHook', function(hook)
    local resource = GetInvokingResource()
    hooks[hookIdx + 1] = {
        fn = hook,
        resource = resource
    }

    hookIdx = hookIdx + 1
end)

local modes = {}

local function getMatchingPlayers(seObject)
    local players = GetPlayers()
    local retval = {}

    for _, v in ipairs(players) do
        if IsPlayerAceAllowed(v, seObject) then
            retval[#retval + 1] = v
        end
    end

    return retval
end

exports('registerMode', function(modeData)
    if not modeData.name or not modeData.displayName or not modeData.cb then
        return false
    end

    local resource = GetInvokingResource()
    modes[modeData.name] = modeData

    modes[modeData.name].resource = resource

    local clObj = {
        name = modeData.name,
        displayName = modeData.displayName,
        color = modeData.color or '#fff',
        isChannel = modeData.isChannel,
        isGlobal = modeData.isGlobal,
    }

    if not modeData.seObject then
        TriggerClientEvent('chat:addMode', -1, clObj)
    else
        for _, v in ipairs(getMatchingPlayers(modeData.seObject)) do
            TriggerClientEvent('chat:addMode', v, clObj)
        end
    end

    return true
end)

local function unregisterHooks(resource)
    local toRemove = {}

    for k, v in pairs(hooks) do
        if v.resource == resource then
            table.insert(toRemove, k)
        end
    end

    for _, v in ipairs(toRemove) do
        hooks[v] = nil
    end

    toRemove = {}

    for k, v in pairs(modes) do
        if v.resource == resource then
            table.insert(toRemove, k)
        end
    end

    for _, v in ipairs(toRemove) do
        TriggerClientEvent('chat:removeMode', -1, {
            name = v
        })

        modes[v] = nil
    end
end

local function routeMessage(source, author, message, mode, fromConsole)
    if source >= 1 then
        author = GetPlayerName(source)
    end

    local outMessage = {
        color = { 255, 255, 255 },
        multiline = true,
        args = { message },
        mode = mode
    }

    if author ~= "" then
        outMessage.args = { author, message }
    end

    if mode and modes[mode] then
        local modeData = modes[mode]

        if modeData.seObject and not IsPlayerAceAllowed(source, modeData.seObject) then
            return
        end
    end

    local messageCanceled = false
    local routingTarget = -1

    local hookRef = {
        updateMessage = function(t)
            -- shallow merge
            for k, v in pairs(t) do
                if k == 'template' then
                    outMessage['template'] = v:gsub('%{%}', outMessage['template'] or '@default')
                elseif k == 'params' then
                    if not outMessage.params then
                        outMessage.params = {}
                    end

                    for pk, pv in pairs(v) do
                        outMessage.params[pk] = pv
                    end
                else
                    outMessage[k] = v
                end
            end
        end,

        cancel = function()
            messageCanceled = true
        end,

        setSeObject = function(object)
            routingTarget = getMatchingPlayers(object)
        end,

        setRouting = function(target)
            routingTarget = target
        end
    }

    for _, hook in pairs(hooks) do
        if hook.fn then
            hook.fn(source, outMessage, hookRef)
        end
    end

    if modes[mode] then
        local m = modes[mode]

        m.cb(source, outMessage, hookRef)
    end

    if messageCanceled then
        return
    end

    TriggerEvent('chatMessage', source, #outMessage.args > 1 and outMessage.args[1] or '', outMessage.args[#outMessage.args])

    if not WasEventCanceled() then
        if type(routingTarget) ~= 'table' then
            TriggerClientEvent('chat:addMessage', routingTarget, outMessage)
        else
            for _, id in ipairs(routingTarget) do
                TriggerClientEvent('chat:addMessage', id, outMessage)
            end
        end
    end

    if not fromConsole then
        print(author .. '^7' .. (modes[mode] and (' (' .. modes[mode].displayName .. ')') or '') .. ': ' .. message .. '^7')
    end
end

AddEventHandler('_chat:messageEntered', function(author, color, message, mode)
    if not message or not author then
        return
    end

    local source = source

    routeMessage(source, author, message, mode)
end)

AddEventHandler('__cfx_internal:commandFallback', function(command)
    local name = GetPlayerName(source)

    -- route the message as if it were a /command
    routeMessage(source, name, '/' .. command, nil, true)

    CancelEvent()
end)

-- player join messages
AddEventHandler('playerJoining', function()
    if GetConvarInt('chat_showJoins', 1) == 0 then
        return
    end

    TriggerClientEvent('chatMessage', -1, '', { 255, 255, 255 }, '^2* ' .. GetPlayerName(source) .. ' joined.')
end)

AddEventHandler('playerDropped', function(reason)
    if GetConvarInt('chat_showQuits', 1) == 0 then
        return
    end

    TriggerClientEvent('chatMessage', -1, '', { 255, 255, 255 }, '^2* ' .. GetPlayerName(source) ..' left (' .. reason .. ')')
end)

RegisterCommand('say', function(source, args, rawCommand)
    routeMessage(source, (source == 0) and 'console' or GetPlayerName(source), rawCommand:sub(5), nil, true)
end)

-- command suggestions for clients
local function refreshCommands(player)
    if GetRegisteredCommands then
        local registeredCommands = GetRegisteredCommands()

        local suggestions = {}

        for _, command in ipairs(registeredCommands) do
            if IsPlayerAceAllowed(player, ('command.%s'):format(command.name)) then
                table.insert(suggestions, {
                    name = '/' .. command.name,
                    help = ''
                })
            end
        end

        TriggerClientEvent('chat:addSuggestions', player, suggestions)
    end
end

AddEventHandler('chat:init', function()
    local source = source
    refreshCommands(source)

    for _, modeData in pairs(modes) do
        local clObj = {
            name = modeData.name,
            displayName = modeData.displayName,
            color = modeData.color or '#fff',
            isChannel = modeData.isChannel,
            isGlobal = modeData.isGlobal,
        }

        if not modeData.seObject or IsPlayerAceAllowed(source, modeData.seObject) then
            TriggerClientEvent('chat:addMode', source, clObj)
        end
    end
end)

AddEventHandler('onServerResourceStart', function(resName)
    Wait(500)

    for _, player in ipairs(GetPlayers()) do
        refreshCommands(player)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    unregisterHooks(resName)
end)

function chat:__construct()
    vRP.Extension.__construct(self)

    self.cfg = module("chat", "cfg/cfg")
end

RegisterCommand("tpto", function(source, args, rawCommand)
    local user = vRP.users_by_source[source]
    if user:hasPermission(self.cfg.admin_permission) then -- if the user has permission from the config, then the code is executed
        local id = tonumber(user:prompt("Target ID:", ""))
        if id ~= nil and id ~= " " then
            local target = vRP.users[id]
            if target ~= nil then
                vRP.EXT.Base.remote._teleport(user.source, vRP.EXT.Base.remote.getPosition(target.source))
                vRP.EXT.Base.remote._notify(user.source, "You teleported to "..vRP.getPlayerName(target.source).." ["..target.id.."]")
                vRP.EXT.Base.remote._notify(target.source, "The admin "..vRP.getPlayerName(target.source).." ["..target.id.."] teleported to you")
            else
                vRP.EXT.Base.remote._notify(user.source, "The player is not online")
            end
        else
            vRP.EXT.Base.remote._notify(user.source, "You have not entered a valid ID")
        end
    else
        vRP.EXT.Base.remote._notify(user.source, "You do not have access to this command")
    end
end)

RegisterCommand("tptome", function(source, args, rawCommand)
    local user = vRP.users_by_source[source]
    if user:hasPermission(self.cfg.admin_permission) then -- if the user has permission from the config, then the code is executed
        local id = tonumber(user:prompt("Target ID:", ""))
        if id ~= nil and id ~= " " then
            local target = vRP.users[id]
            if target ~= nil then
                vRP.EXT.Base.remote._teleport(target.source, vRP.EXT.Base.remote.getPosition(user.source))
                vRP.EXT.Base.remote._notify(user.source, "You teleported the player "..vRP.getPlayerName(target.source).." ["..target.id.."] to you")
                vRP.EXT.Base.remote._notify(target.source, "The admin "..vRP.getPlayerName(target.source).." ["..target.id.."] teleported you to him")
            else
                vRP.EXT.Base.remote._notify(user.source, "The player is not online")
            end
        else
            vRP.EXT.Base.remote._notify(user.source, "You have not entered a valid ID")
        end
    else
        vRP.EXT.Base.remote._notify(user.source, "You do not have access to this command")
    end
end)

vRP:registerExtension(chat)