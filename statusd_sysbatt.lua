-- statusd_sysbatt.lua: statusd battery information module
-- Copyright (C) 2013  Jurij Smakov <jurij@wooyd.org>
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
--
--
-- See README file for notes and usage details. 

local defaults={
    update_interval = 30 * 1000,
    important_threshold = 30,
    critical_threshold = 10,
}

local settings = defaults
if statusd ~= nil then
    settings = table.join(statusd.get_config("sysbatt"), defaults)
end

local function read_file(name)
    local fh = io.open(name, 'r')
    if fh == nil then
        return nil
    end
    local data = fh:read("*a");
    fh:close()
    data = string.gsub(data, '^%s+', '')
    data = string.gsub(data, '%s+$', '')
    return data
end

local function find_battery_path()
    local base_dir = '/sys/class/power_supply/BAT'
    for index = 0,9 do
        local device_dir = base_dir .. index
        local device_type = read_file(device_dir .. '/type')
        if device_type ~= nil and string.lower(device_type) == 'battery' then
            local device_present = read_file(device_dir .. '/present')
            if device_present == "1" then
                return device_dir
            end
        end
    end
    return nil
end           

local function get_percent_charged(params)
    if params.capacity ~= nil then
        return tonumber(params.capacity)
    elseif params.charge_now ~= nil and params.charge_full ~= nil then
        local capacity_now = tonumber(params.charge_now)
        local capacity_full = tonumber(params.charge_full)
        return 100.0 * capacity_now / capacity_full
    elseif params.energy_now ~= nil and params.energy_full ~= nil then
        local capacity_now = tonumber(params.energy_now)
        local capacity_full = tonumber(params.energy_full)
        return 100.0 * capacity_now / capacity_full
    else
        return nil
    end
end

local function get_hint(percent_charged, status)
    if percent_charged == nil or status == nil then
        return nil
    end
    local hint = nil
    if status == 'discharging' then
        if percent_charged < settings.critical_threshold then
            hint = 'critical'
        elseif percent_charged < settings.important_threshold then
            hint = 'important'
        end
    end
    return hint
end

local function get_time_remaining(params)
    local capacity_now, capacity_full, rate, time_hours, suffix
    if params.charge_now ~= nil and params.charge_full ~= nil and params.current_now ~= nil then
        capacity_now = tonumber(params.charge_now)
        capacity_full = tonumber(params.charge_full)
        rate = tonumber(params.current_now)
    elseif params.energy_now ~= nil and params.energy_full ~= nil and params.power_now ~= nil then
        capacity_now = tonumber(params.energy_now)
        capacity_full = tonumber(params.energy_full)
        rate = tonumber(params.power_now)
    else
        return nil
    end

    if params.status == 'discharging' then
        time_hours = capacity_now / rate
        suffix = 'remaining'
    elseif params.status == 'charging' then
        time_hours = (capacity_full - capacity_num) / rate
        suffix = 'until charged'
    else
        return nil
    end

    local hours_num = math.floor(time_hours)
    local minutes_num = math.floor((time_hours - hours_num) * 60)
    local seconds_num = math.floor((time_hours - hours_num) * 3600 - minutes_num * 60)
    local hours_str = string.format('%02d', hours_num)
    local minutes_str = string.format('%02d', minutes_num)
    local seconds_str = string.format('%02d', seconds_num)
    local time_str = hours_str .. ':' .. minutes_str .. ':' .. seconds_str
    return time_str .. ' ' .. suffix
end

local function read_params(path)
    local params = {
        charge_now = read_file(path .. '/charge_now'),
        charge_full = read_file(path .. '/charge_full'),
        current_now = read_file(path .. '/current_now'),
        energy_now = read_file(path .. '/energy_now'),
        energy_full = read_file(path .. '/energy_full'),
        power_now = read_file(path .. '/power_now'),
        capacity = read_file(path .. '/capacity'),
        status = read_file(path .. '/status'),
    }
    if params.status ~= nil then
        params.status = string.lower(params.status)
    end
    return params
end

local function get_battery_info(path)
    local info = {
        status = 'not available',
        percent_charged = 'unknown',
        hint = 'normal',
        time_remaining = 'no time estimate'
    }
    if path == nil then
        return info
    end

    local params = read_params(path)

    local percent_charged = get_percent_charged(params)
    if percent_charged ~= nil then
        info.percent_charged = string.format('%.1f%%', percent_charged)
    end

    local hint = get_hint(percent_charged, params.status)
    if hint ~= nil then
        info.hint = hint
    end

    local time_remaining = get_time_remaining(params)
    if time_remaining ~= nil then
        info.time_remaining = time_remaining
    end

    if params.status == 'unknown' and percent_charged ~= nil and percent_charged > 99.0 then
        info.status = 'full'
    else
        info.status = params.status
    end

    return info
end

local sysbatt_timer = nil
if statusd ~= nil then
    sysbatt_timer = statusd.create_timer()
end

local function update_battery_info()
    local battery_path = find_battery_path()
    local battery_info = get_battery_info(battery_path)

    if statusd ~= nil then
        statusd.inform('sysbatt_status', battery_info.status)
        statusd.inform('sysbatt_percent_charged', battery_info.percent_charged)
        statusd.inform('sysbatt_hint', battery_info.hint)
        statusd.inform('sysbatt_time_remaining', battery_info.time_remaining)
        sysbatt_timer:set(settings.update_interval, update_battery_info)
    else
        io.stdout:write('status          = ' .. battery_info.status .. '\n')
        io.stdout:write('hint            = ' .. battery_info.hint .. '\n')
        io.stdout:write('percent_charged = ' .. battery_info.percent_charged .. '\n')
        io.stdout:write('time_remaining  = ' .. battery_info.time_remaining .. '\n')
    end
end

update_battery_info()
