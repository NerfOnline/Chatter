local chat_manager = {}

-- The main storage for chat lines
-- Each line is a table: { text = "string", color = 0xFFFFFFFF, timestamp = 1234567890 }
chat_manager.lines = {}
chat_manager.max_lines = 5000

-- Adds a new line to the chat log
function chat_manager.add_line(text, color)
    local line = {
        text = text,
        color = color or 0xFFFFFFFF,
        timestamp = os.time()
    }
    table.insert(chat_manager.lines, line)
    
    -- Prune if we exceed max lines
    if #chat_manager.lines > chat_manager.max_lines then
        table.remove(chat_manager.lines, 1)
    end
end

-- Retrieves a slice of lines for rendering
-- offset: 0 = newest lines. 1 = shifted up by 1 line (older).
-- count: Number of lines to retrieve
-- Returns: Array of lines, where index 1 is the TOP rendered line (oldest in the view), and index 'count' is the BOTTOM (newest in the view)
function chat_manager.get_visible_lines(offset, count)
    local result = {}
    local total_lines = #chat_manager.lines
    
    -- We want to display lines ending at (total_lines - offset)
    -- And starting at (total_lines - offset - count + 1)
    
    local end_index = total_lines - offset
    local start_index = end_index - count + 1
    
    for i = start_index, end_index do
        if i >= 1 and i <= total_lines then
            table.insert(result, chat_manager.lines[i])
        else
            -- Fill empty space with nil or empty placeholder if needed, 
            -- but the renderer handles count mismatch usually.
        end
    end
    
    return result
end

function chat_manager.get_line_count()
    return #chat_manager.lines
end

function chat_manager.clear()
    chat_manager.lines = {}
end

return chat_manager
