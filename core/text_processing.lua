local globals = require('core.globals')
local settings = globals.default_settings
local get_styles = require('config.styles')
local tab_styles = get_styles(settings)
local tabs_lib = require('core.tabs') -- Added tabs_lib
local battle_ids = globals.battle_ids
local duplidoc_ids = globals.duplidoc_ids
local filter_ids = globals.filter_ids
local pause_ids = globals.pause_ids
local chat_tables = globals.chat_tables
local battle_table = globals.battle_table
local archive_table = globals.archive_table
local assist_flags = globals.assist_flags
local chat_log_env = globals.chat_log_env
local tab_ids = globals.tab_ids
local all_tabs = globals.all_tabs

-- Helper: Check if value in set/list
local function contains(list, val)
    if not list then return false end
    for _, v in ipairs(list) do
        if v == val then return true end
    end
    return false
end

-- Helper: Strip colors (simplified for now)
local function strip_colors(text)
    -- Remove \cs(...) and \cr
    text = string.gsub(text, '\\cs%([%d,]+%)', '')
    text = string.gsub(text, '\\cr', '')
    return text
end

local function split(s, delimiter)
    local result = {}
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

local function check_mentions(id, chat)
    local chat_type = nil
    if battle_ids[id] then
        chat_type = globals.battle_tabname
    elseif globals.tab_ids[tostring(id)] then
        chat_type = globals.tab_ids[tostring(id)]
    end

    local sfind = string.find
    local all_tabname = globals.all_tabname
    local battle_tabname = globals.battle_tabname
    
    -- Check All tab mentions
    if not (chat_type == battle_tabname and settings.battle_all == false) then
        if settings.mentions[all_tabname] then
            local stripped = string.gsub(chat,'[^A-Za-z%s]','')
            local splitted = split(stripped,' ')
            local chat_low = chat:lower()
            local player_name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0):lower()
            
            for v, _ in pairs(settings.mentions[all_tabname]) do
                v = v:lower()
                if sfind(chat_low,v) then
                    if v == player_name then
                        if splitted[1] and splitted[1]:lower() == v then
                            return
                        end
                    end
                    chat_log_env['mention_found'] = true
                    chat_log_env['mention_count'] = os.clock()+30
                    chat_log_env['last_mention_tab'] = all_tabname
                    chat_log_env['notification_text'] = "New Mention @ \\cs(255,69,0)All\\cr: \\cs(0,255,0)"..v.."\\cr"
                    return
                end
            end
        end
    end

    -- Check specific tab mentions
    if chat_type and settings.mentions[chat_type] then
        if settings.battle_flash and chat_type == battle_tabname then
            -- force process
        else
            if globals.current_tab == chat_type then
                return
            end
        end
        
        local stripped = string.gsub(chat,'[^A-Za-z%s]','')
        local splitted = split(stripped,' ')
        local chat_low = chat:lower()
        local player_name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0):lower()
        
        for v, _ in pairs(settings.mentions[chat_type]) do
            v = v:lower()
            if sfind(chat_low,v) then
                if v == player_name then
                    if splitted[1] and splitted[1]:lower() == v then
                        return
                    end
                end
                chat_log_env['mention_found'] = true
                chat_log_env['mention_count'] = os.clock()+30
                chat_log_env['last_mention_tab'] = chat_type
                if chat_type == battle_tabname and settings.battle_flash then
                    chat_log_env['notification_text'] = "New Mention @ \\cs(255,69,0)"..chat_type.."\\cr: \\cs(0,255,0)"..v.."\\cr "..stripped
                else
                    chat_log_env['notification_text'] = "New Mention @ \\cs(255,69,0)"..chat_type.."\\cr: \\cs(0,255,0)"..v.."\\cr"
                end
                return
            end
        end
    end
end

local function log_debug(msg)
    local path = string.format('%s/addons/chatter/debug.log', AshitaCore:GetInstallPath())
    local f = io.open(path, 'a+')
    if f then
        f:write('[' .. os.date() .. '] ' .. tostring(msg) .. '\n')
        f:close()
    else
        print('[Chatter] Failed to open log: ' .. path)
    end
end

-- Test log on load
log_debug("Chatter text_processing loaded")

local function normalize(text)
    -- Remove specific artifact first: 0x7F followed by digit
    -- Lua 5.1 pattern for 0x7F is \127
    local clean = string.gsub(text, "\127%d+", "") 
    
    -- Remove all whitespace and control characters for comparison
    clean = string.gsub(clean, "%s+", "")
    clean = string.gsub(clean, "%c", "") -- Remove control characters
    
    -- Remove trailing '1' if present (legacy artifact check)
    if string.sub(clean, -1) == "1" then
        clean = string.sub(clean, 1, -2)
    end
    return clean
end

local function is_duplicate(tbl, id, chat)
    if not tbl or #tbl == 0 then return false end
    local last = tbl[#tbl]
    
    local last_raw = (type(last) == 'table') and last.raw or last
    
    -- Find the second colon manually to handle newlines in chat content
    local first_colon = string.find(last_raw, ":")
    if not first_colon then return false end
    local second_colon = string.find(last_raw, ":", first_colon + 1)
    if not second_colon then return false end
    
    local last_id = string.sub(last_raw, first_colon + 1, second_colon - 1)
    local last_chat = string.sub(last_raw, second_colon + 1)
    
    -- Check for exact match first
    if last_id == tostring(id) and last_chat == chat then
        return true
    end
    
    -- Check normalized match (ignoring whitespace differences)
    if last_id == tostring(id) and normalize(last_chat) == normalize(chat) then
        log_debug(string.format("Duplicate blocked by normalize: ID %s", tostring(id)))
        return true
    end

    -- Debug: Log near-misses or all checks for NPC IDs (range 100-200 usually)
    if tonumber(id) and tonumber(id) >= 120 and tonumber(id) <= 130 then
        log_debug(string.format("is_duplicate CHECK FAIL: ID=%s", tostring(id)))
        log_debug(string.format("  Last: '%s' (Norm: '%s')", last_chat, normalize(last_chat)))
        log_debug(string.format("  Curr: '%s' (Norm: '%s')", chat, normalize(chat)))
    end

    return false
end

local function add_to_table(tbl, id, chat, limit)
    if not tbl then return false end
    if is_duplicate(tbl, id, chat) then return true end
    
    local raw_str = os.time()..':'..id..':'..chat
    local entry = {
        raw = raw_str,
        timestamp = os.time(),
        id = id,
        text = chat
    }
    
    table.insert(tbl, entry)
    if #tbl > (limit or 1000) then
        table.remove(tbl, 1)
    end
    return true
end

local function chat_add(id, chat)
    -- Handle mentor flags and rank (simplified port from ruptchat)
    if id == 221 or id == 222 then -- Tell
        -- Basic rank parsing omitted for brevity, keeping it simple
        table.insert(archive_table, os.date('[%x@%X]')..':'..id..':'..chat)
        
        -- Clean up some chars
        chat = string.gsub(chat,"ü","")
    end

    if not settings.vanilla_mode then
        -- chat = strip_colors(chat) -- If we want to restyle, strip first?
        -- Ruptchat strips colors if not vanilla mode
    end

    -- Ruptchat does some char replacements
    chat = string.gsub(chat, string.char(0xEF, 0x27), '{:')
    chat = string.gsub(chat, string.char(0xEF, 0x28)..'.', ':}')
    
    -- Cleanup standard junk
    chat = string.gsub(chat, string.char(0x07), '\n') -- Replace 0x07 with newline
    chat = string.gsub(chat, '\r', '') -- Remove CR

    if globals.debug_mode then log_debug('ID: '..id..' Txt: '..chat) end

    check_mentions(id, chat)

    -- Battle IDs processing
    if battle_ids[id] then
        -- Battlemod duplicate check
        if id == 20 and globals.battlemod_loaded and (string.find(chat,'scores.') or string.find(chat,'uses') or string.find(chat,'hits') or string.match(chat,'.*spikes deal.*') or string.find(chat,'misses') or string.find(chat,'cures') or string.find(chat,'additional') or string.find(chat,'retaliates')) then
            return
        end

        if not contains(tabs_lib['Battle_Exclusions'], id) then
            add_to_table(battle_table, id, chat, globals.rupt_table_length)
        end

        if settings.battle_all then
             -- Add to All/General tab if enabled
             if chat_tables['General'] then -- Assuming 'General' is the 'All' tab
                 add_to_table(chat_tables['General'], id, chat, globals.rupt_table_length)
             end
        end
    else
        -- Non-battle IDs
        local added_to_general = false
        if not contains(tabs_lib['All_Exclusions'], id) then
            -- Add to All/General tab
             if chat_tables['General'] then
                 add_to_table(chat_tables['General'], id, chat, globals.rupt_table_length)
                 added_to_general = true
             end
        end

        -- Add to specific tab based on ID mapping
        local tab_name = tab_ids[tostring(id)]
        if tab_name then
            if tab_name == 'General' and added_to_general then
                -- Skip, already handled above
            else
                if chat_tables[tab_name] then
                     add_to_table(chat_tables[tab_name], id, chat, globals.rupt_subtable_length or 500)
                end
            end
        end
    end
end

local function process_incoming_text(original, modified, orig_id, id, blocked)
    -- Log ALL incoming text to find the correct ID (Disabled to reduce spam)
    -- log_debug(string.format("INCOMING: ID=%d OrigID=%d Msg='%s'", id, orig_id, string.sub(modified, 1, 50)))

    local is_duplicate_msg = false

    -- Duplicate check
    if duplidoc_ids[id] then
        local norm_modified = normalize(modified)
        -- Compare with normalized last line
        if norm_modified == chat_log_env['last_text_line'] then
            if globals.debug_mode then
                log_debug(string.format("  -> DETECTED DUPLICATE ID %d - Skipping Chatter add, passing to game", id))
            end
            is_duplicate_msg = true
        else
            if globals.debug_mode then
                log_debug(string.format("  -> PASS (Not duplicate) ID %d", id))
                log_debug(string.format("     Last: '%s' (len:%d)", chat_log_env['last_text_line'] or "nil", #(chat_log_env['last_text_line'] or "")))
                log_debug(string.format("     Curr: '%s' (len:%d)", norm_modified, #norm_modified))
            end
            chat_log_env['last_text_line'] = norm_modified
        end
    else
        -- Log IDs that might be NPC but missed by duplidoc
        if id >= 120 and id <= 130 and globals.debug_mode then
            log_debug(string.format("Possible NPC ID missed by duplidoc: %d", id))
        end
    end

    -- Battlemod check
    if battle_ids[id] then
        globals.battlemod_loaded = true
    end

    if settings.battle_off and battle_ids[id] then
        -- Skip processing
    else
        -- Only add to Chatter if not a duplicate
        if not is_duplicate_msg then
            if not filter_ids[id] then
                 -- Ruptchat logic: if not battlemod_loaded then modified = original end
                 -- But we are replacing battlemod?
                 
                 modified = string.gsub(modified,'\\','\\\\')
                 -- modified = string.gsub(modified,'[\r\n]','') -- MOVED cleaning to chat_add to preserve newlines for NPC logic?
                 -- Actually, ruptchat removes newlines here.
                 -- But we need 0x07 for newlines later. 
                 -- string.gsub(modified, '[\r\n]', '') removes CR and LF. 0x07 is untouched.
                 modified = string.gsub(modified,'[\r\n]','')
                 -- modified = string.gsub(modified,'[\\]+$','') -- fix trailing slash?
    
                 chat_add(id, modified)
            end
        end
    end

    if settings.incoming_pause then
        if battle_ids[id] or pause_ids[id] then
            return true -- Block from vanilla log
        end
    end
    
    return false -- Don't block by default
end

local function convert_text(txt, tab_style, id)
    local timestamp, text_id, clean_text
    
    -- Parse header: timestamp:id:text or timestamp:text
    -- Handle negative IDs (Ashita sometimes sends signed ints)
    local ts, tid, msg = string.match(txt, '^(%d+):([%-%d]+):(.*)')
    local ts_val
    if ts then
        ts_val = tonumber(ts)
        id = tonumber(tid)
        clean_text = msg
    else
        local ts2, msg2 = string.match(txt, '^(%d+):(.*)')
        if ts2 then
            ts_val = tonumber(ts2)
            clean_text = msg2
        else
            ts_val = os.time()
            clean_text = txt
        end
    end

    if settings.time_format == '12h' then
        timestamp = os.date('[%I:%M:%S %p]', ts_val)
    else
        timestamp = os.date('[%H:%M:%S]', ts_val)
    end

    if not settings.vanilla_mode then
        txt = timestamp .. ' ' .. clean_text
    else
        txt = clean_text
    end

    -- Remove control characters (using decimal escapes for Lua 5.1 compatibility)
    -- \x1E -> \030, \x1F -> \031, \x7F -> \127
    txt = string.gsub(txt, '[\030\031\127].', '')
    txt = string.gsub(txt, '[^%z\001-\127]', '')

    -- Apply styles
    if not settings.vanilla_mode then
        local styles
        if tab_styles[id] then
            styles = tab_styles[id]
        elseif battle_ids and battle_ids[id] then
            -- styles = tab_styles['battle'] -- 'battle' key not present in styles table I ported?
            -- styles.lua has [20], [21] etc.
            styles = tab_styles[id] -- Just use id
        else
            -- styles = tab_styles['default']
        end

        if styles then
            for i=1, #styles, 2 do
                -- Attempt basic substitution
                local p, r = styles[i], styles[i+1]
                if p and r then
                    -- Lua pattern substitution
                    local status, res = pcall(string.gsub, txt, p, r)
                    if status then
                        txt = res
                    else
                        if globals.debug_mode then log_debug('Pattern error: '..p) end
                    end
                end
            end
        end
    end
    
    return txt
end

local function update_styles()
    tab_styles = get_styles(settings)
end

return {
    convert_text = convert_text,
    process_incoming_text = process_incoming_text,
    chat_add = chat_add,
    update_styles = update_styles
}
