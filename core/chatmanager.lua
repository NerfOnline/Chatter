local chatmanager = {}

-- Structure of Arrays (SoA) for memory efficiency
chatmanager.data = {
    text = {},
    color = {},
    timestamp = {},
    id = {}
}
chatmanager.count = 0
chatmanager.max_lines = 50000
chatmanager.next_id = 1
chatmanager.start_index = 1 -- Index of the oldest message in the ring buffer

-- Adds a new line to the chat log
function chatmanager.add_line(text, color)
    local idx
    
    if chatmanager.count < chatmanager.max_lines then
        -- Filling up
        chatmanager.count = chatmanager.count + 1
        idx = chatmanager.count
    else
        -- Ring buffer wrap
        idx = chatmanager.start_index
        chatmanager.start_index = chatmanager.start_index + 1
        if chatmanager.start_index > chatmanager.max_lines then
            chatmanager.start_index = 1
        end
    end
    
    chatmanager.data.text[idx] = text
    chatmanager.data.color[idx] = color or 0xFFFFFFFF
    chatmanager.data.timestamp[idx] = os.time()
    chatmanager.data.id[idx] = chatmanager.next_id
    
    chatmanager.next_id = chatmanager.next_id + 1
end

-- Helper to map virtual index (1..count) to real index in storage
local function get_real_index(index)
    if index < 1 or index > chatmanager.count then return nil end
    
    -- If we haven't wrapped yet, virtual == real
    if chatmanager.count < chatmanager.max_lines then
        return index
    end
    
    -- If we have wrapped, real index starts at start_index
    local real = chatmanager.start_index + index - 1
    if real > chatmanager.max_lines then
        real = real - chatmanager.max_lines
    end
    return real
end

function chatmanager.get_line_text(index)
    local real = get_real_index(index)
    if not real then return nil end
    return chatmanager.data.text[real]
end

function chatmanager.get_line_color(index)
    local real = get_real_index(index)
    if not real then return nil end
    return chatmanager.data.color[real]
end

function chatmanager.get_line_id(index)
    local real = get_real_index(index)
    if not real then return nil end
    return chatmanager.data.id[real]
end

function chatmanager.get_line_count()
    return chatmanager.count
end

function chatmanager.clear()
    chatmanager.data.text = {}
    chatmanager.data.color = {}
    chatmanager.data.timestamp = {}
    chatmanager.data.id = {}
    chatmanager.count = 0
    chatmanager.next_id = 1
    chatmanager.start_index = 1
end

function chatmanager.save_history(filepath)
    local f = io.open(filepath, "w")
    if not f then return end
    
    -- Format: timestamp|color|id|text
    -- We use a pipe delimiter. Text might contain newlines or pipes.
    -- We should escape the text.
    
    for i = 1, chatmanager.count do
        local txt = chatmanager.get_line_text(i)
        local col = chatmanager.get_line_color(i)
        -- Access raw data for timestamp/id if helpers missing, but we should add them or just use get_line_id
        -- We added get_line_id. We need get_line_timestamp.
        -- Let's add it or just duplicate logic here.
        local real = get_real_index(i)
        local ts = chatmanager.data.timestamp[real]
        local id = chatmanager.data.id[real]
        
        -- Escape newlines and pipes
        txt = txt:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("|", "\\|")
        
        f:write(string.format("%d|%d|%d|%s\n", ts, col, id, txt))
    end
    f:close()
end

function chatmanager.load_history(filepath)
    local f = io.open(filepath, "r")
    if not f then return end
    
    -- Clear current
    chatmanager.clear()
    
    local max_id = 0
    
    for line in f:lines() do
        -- Parse: ts|col|id|text
        -- We find the first 3 pipes
        local p1 = line:find("|", 1, true)
        if p1 then
            local p2 = line:find("|", p1 + 1, true)
            if p2 then
                local p3 = line:find("|", p2 + 1, true)
                if p3 then
                    local ts = tonumber(line:sub(1, p1 - 1))
                    local col = tonumber(line:sub(p1 + 1, p2 - 1))
                    local id = tonumber(line:sub(p2 + 1, p3 - 1))
                    local txt = line:sub(p3 + 1)
                    
                    -- Unescape
                    txt = txt:gsub("\\|", "|"):gsub("\\n", "\n"):gsub("\\\\", "\\")
                    
                    -- Use add_line to respect ring buffer
                    -- But we need to set timestamp and id manually after adding
                    -- because add_line uses current time and next_id.
                    
                    chatmanager.add_line(txt, col)
                    
                    -- Overwrite with loaded data
                    -- add_line puts it at logical end (count)
                    -- which corresponds to internal index... 
                    -- We can just find the index of the last added item.
                    -- Which is... wait, add_line updates count/start_index.
                    -- The index we just wrote to is the one before next_id? No.
                    
                    -- Actually, add_line doesn't return the index.
                    -- But we know it's the last one.
                    local last_real_idx
                    if chatmanager.count < chatmanager.max_lines then
                        last_real_idx = chatmanager.count
                    else
                        -- If full, add_line wrote to (start_index - 1) wrapped?
                        -- No, add_line: idx = start_index (before increment)
                        -- Then start_index++.
                        -- So the index we wrote to is start_index - 1 (wrapped).
                        local prev_start = chatmanager.start_index - 1
                        if prev_start < 1 then prev_start = chatmanager.max_lines end
                        last_real_idx = prev_start
                    end
                    
                    chatmanager.data.timestamp[last_real_idx] = ts
                    chatmanager.data.id[last_real_idx] = id
                    
                    if id > max_id then max_id = id end
                end
            end
        end
    end
    
    chatmanager.next_id = max_id + 1
    f:close()
end

-- Helper to get a "line object" like before, but transient
-- This creates a table, so use sparingly in tight loops.
-- Prefer accessing fields directly if possible.
function chatmanager.get_line(index)
    local real = get_real_index(index)
    if not real then return nil end
    return {
        text = chatmanager.data.text[real],
        color = chatmanager.data.color[real],
        timestamp = chatmanager.data.timestamp[real],
        id = chatmanager.data.id[real]
    }
end

return chatmanager
