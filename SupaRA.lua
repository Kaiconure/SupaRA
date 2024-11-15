__version = '1.0.1'
__name = 'SupaRA'
__shortName = 'sra'
__author = '@Kaiconure'
__commands = { 'sra', 'supara' }

_addon.version = __version
_addon.name = __name
_addon.shortName = __shortName
_addon.author = __author
_addon.commands = __commands

require('sets')
require('vectors')

local packets = require('packets')
local resources = require('resources')
local config = require('config')

local CATEGORY_RA_START_OR_INTERRUPT    = 12
local CATEGORY_RA_END                   = 2

local PARAM_START                       = 24931
local PARAM_INTERRUPT                   = 28787

local STATUS_IDLE                       = 0
local STATUS_ENGAGED                    = 1

local SPAWN_TYPE_MOB                    = 16

local ANGLE_TOLERANCE                   = (10 * math.pi / 180.0)
local FORWARD_VECTOR                    = V({1, 0})

local SLOT_RANGE    = 2
local SLOT_AMMO     = 3

--
-- Clamp a number n between a min and max range, inclusive.
--
math.clamp = math.clamp or function (n, min, max)
    local _min = math.min(min, max)
    local _max = math.max(min, max)
    return math.min(_max, math.max(_min, n))
end

--
-- Info about bags, indexed by bag id
--
local BagsById = 
{
    [0] = { field = "inventory" },
    [8] = { field = "wardrobe" },
    [10] = { field = "wardrobe2" },
    [11] = { field = "wardrobe3" },
    [12] = { field = "wardrobe4" },
    [13] = { field = "wardrobe5" },
    [14] = { field = "wardrobe6" },
    [15] = { field = "wardrobe7" },
    [16] = { field = "wardrobe8" },
}

-- 
-- Persistent settings.
--
local DefaultSettings = {
    interval = 3.0  -- This is really only here for experimentation purposes. Consider 3.0 to be the
                    -- optimal, constant value. It's the amount of time to wait between one ranged
                    -- attack completing and the next starting.
}

local settings = config.load(DefaultSettings)

--
-- Global volatile state.
--
local globals = {
    kill = false,
    in_ra = false,
    last_ra = 0,
    paused = true
}

--
-- Write a message to the chat log.
--
local function log(msg)
    windower.add_to_chat(15, '[%s] %s':format(__shortName, msg))
end

--
-- Send a command back to this addon.
--
local function send_to_self(command)
    windower.send_command('%s %s;':format(
        __shortName,
        command
    ))
end

-- 
-- Determine the angle between two vectors. If only the first vector is
-- provided, a compass heading for that vector will be returned.
--
local function vector_angle(v, from)
    v = v:normalize()
    from = (from or FORWARD_VECTOR):normalize()

    -- Calculate the dot product and determinant
    local dot = vector.dot(from, v)
    local det = (from[1] * v[2]) - (from[2] * v[1])

    -- Calculate the angle delta
    return -math.atan2(det, dot)
end

--
-- Find the actual item resource represented by the specified bag location.
--
local function find_item_resource(items, bagId, localId)
    if localId <= 0 then
        return
    end
    
    -- Find the containing bag
    local bagInfo = BagsById[bagId]
    if bagInfo == nil then
        return
    end

    -- Find the item in the bag
    local bagName = bagInfo.field
    local bagItem = items[bagName] and items[bagName][localId]
    if bagItem == nil then
        return
    end

    -- Find the actual item info
    return resources.items[bagItem.id]    
end

--
-- Determine if appropriate ranged attack gear is equipped. Note that this will NOT register 
-- for consumable thrown items (i.e. it will not let you throw your Rare/Ex sachet).
--
local function has_ranged_equipped()
    local items = windower.ffxi.get_items()
    if items then
        local range = find_item_resource(items, items.equipment.range_bag, items.equipment.range)
        local ammo = find_item_resource(items, items.equipment.ammo_bag, items.equipment.ammo)

        -- Can't do anything if there's no ranged weapon equipped
        if range == nil then return end

        local category = range.category
        if category == 'Weapon' then
            local range_type = range.range_type
            local ammo_type = ammo and ammo.ammo_type
            if range_type == 'Bow' and ammo_type == 'Arrow' then
                return true
            elseif range_type == 'Crossbow' and ammo_type == 'Bolt' then
                return true
            elseif range_type == 'Gun' and ammo_type == 'Bullet' then
                return true
            elseif range_type == nil then
                -- It seems that throwing weapons have no range type...maybe they used to be ammo.
                -- This includes boomerangs and chakrams
                return true
            end
        end
    end
end

--
-- Execute one iteration of the ranged attack scheduler.
--
local function scheduler_iteration(t)

    -- Don't fire if we're still firing or haven't reached our spacing interval yet.
    if
        globals.in_ra or
        t < (globals.last_ra + settings.interval) 
    then
        return 0.5
    end

    -- Only fire if we're standing around idle or if we're engaged.
    local player = windower.ffxi.get_player()
    if
        player.status ~= STATUS_IDLE and
        player.status ~= STATUS_ENGAGED
    then
        local status = resources.statuses[player.status]
        status = status.name or 'Unknown'

        log('Ranged attacking is not allowed while in state: %s':format(status))
        send_to_self('stop')

        return 2.0
    end

    -- Only fire if we're targeting a valid, living mob
    local target = windower.ffxi.get_mob_by_target('t')
    if
        not target or
        not target.valid_target or
        target.hpp == 0 or
        target.spawn_type ~= SPAWN_TYPE_MOB or  -- It must be a valid, targetable mob
        target.distance > (25 * 25)             -- It must be in ranged attack range
    then
        return
    end

    -- Calculate some vectors between us and the target
    local me = windower.ffxi.get_mob_by_target('me')
    local vme = V({me.x, me.y})
    local vtarget = V({target.x, target.y})
    local vto = vtarget:subtract(vme)

    -- Determine the angle theta to the target mob. If our own heading is too far off,
    -- we'll point ourselves at it to ensure we get a clear shot. Note that This will
    -- not actually function if we are target locked.
    local theta = vector_angle(vto)
    if math.abs(theta - me.heading) > ANGLE_TOLERANCE then
        windower.ffxi.turn(theta)
        coroutine.sleep(0.125)
    end
    
    -- Finally, fire the shot
    if not has_ranged_equipped() then
        log('No appropriate ranged attack gear was equipped.')
        send_to_self('stop')

        return 2.0
    end

    -- Finally, fire away
    windower.send_command('input /ra <t>')
end

--
-- Manage invocations of the ranged attack scheduler.
--
local function cr_scheduler()
    while not globals.kill do
        local t = os.clock()

        if not globals.paused then
            local sleep = scheduler_iteration(t) or 1
            coroutine.sleep(sleep)
        else
            coroutine.sleep(1.0)
        end
    end
end

--
-- Addon load handler
--
windower.register_event('load', function ()
    -- Statr the scheduler immediately
    coroutine.schedule(cr_scheduler, 0)

    -- Bind Ctrl+D to the toggle command
    windower.send_command('bind ^d sra toggle')
end)

windower.register_event('unload', function ()
    globals.kill = true
end)

--
-- Addon command handler
--
windower.register_event('addon command', function (command, ...)
    command = (command or ''):lower()
    local args = {...}

    if
        command == 'toggle'
    then
        send_to_self(globals.paused and 'start' or 'stop')
    elseif 
        command == 'stop' or
        command == 'pause'
    then
        log('Automatic ranged attack has paused.')
        globals.paused = true
    elseif
        command == 'start' or
        command == 'run' or 
        command == 'play'
    then
        log('Automatic ranged attack is running.')
        globals.paused = false
    elseif
        command == 'show' 
    then
        log('Automatic ranged attack is currently %s':format(globals.paused and 'paused' or 'running'))
    elseif
        command == 'help'
    then
        log('SupaRA: A new and improved automated ranged attack addon. You could almost call it super.')
        log('  Usage')
        log('    supara <command> <arguments> -OR-')
        log('    sra <command> <arguments>')
        log('  Commands')
        log('    show: Shows the current automation status.')
        log('    start: Starts the automatic ranged attack sequence.')
        log('    stop: Starts the automatic ranged attack sequence.')
        log('    toggle: Toggles the automatic ranged attack sequence.')
        log('  Notes')
        log('     Use Ctrl+D to toggle automatic ranged attacks on or off.')
        log('')
    end
end)

--
-- Logout handler
--
windower.register_event('logout', function ()
    -- Disable auto-attack on logout
    send_to_self('disable')
end)

--
-- Zone change handler
--
windower.register_event('zone change', function ()
    -- Disable auto-attack on zone change
    send_to_self('disable')
end)

--
-- Incoming chunk handler
--
windower.register_event('incoming chunk', function (id, data)
    if id == 0x028 then
        local packet = packets.parse('incoming', data)

        -- Fetch the category, and bail out if it's not something related to ranged attack.
        local category = tonumber(packet['Category']) or 0
        if
            category ~= CATEGORY_RA_START_OR_INTERRUPT and
            category ~= CATEGORY_RA_END
        then
            return
        end

        -- Fetch the actor, and bail if it's not us.
        local me = windower.ffxi.get_mob_by_target('me')
        local actorId = tonumber(packet['Actor']) or 0
        if actorId ~= me.id then
            return
        end

        local raStart = false
        local raInterrupt = false
        local raSuccess = false
        local raCompleted = false

        local param = tonumber(packet['Param']) or 0

        if category == CATEGORY_RA_START_OR_INTERRUPT then
            if param == PARAM_START then
                raStart = true
                --log('Ranged attack initiated.')
            elseif param == PARAM_INTERRUPT then
                raInterrupt = true
                raCompleted = true
                --log('Ranged attack interrupted.')
            end
        elseif category == CATEGORY_RA_END then
            raSuccess = true
            raCompleted = true
            --log('Ranged attack completed.')
        end

        if raStart then
            globals.in_ra = true
            globals.last_ra = 0
        elseif raCompleted then
            globals.in_ra = false
            globals.last_ra = os.clock()
        end
    end
end)