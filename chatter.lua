addon.name    = 'Chatter'
addon.author  = 'NerfOnline'
addon.version = '0.1'

require('common')
local chatmanager = require('core.chatmanager')
local renderer = require('core.renderer')
local imgui = require('imgui')
local settings = require('settings')
local ffi = require('ffi')
local bit = require('bit')

local SAVE_DEBOUNCE_SEC = 0.5
local save_pending = false
local last_save_request = 0
local function request_save()
    save_pending = true
    last_save_request = os.clock()
end
local function get_effective_padding(value)
    if value == nil then
        value = 5
    end
    if value < 0 then
        value = 0
    elseif value > 30 then
        value = 30
    end
    return value + 5
end

-- Windows Clipboard APIs
ffi.cdef[[
    void* GlobalAlloc(unsigned uFlags, size_t dwBytes);
    void* GlobalLock(void* hMem);
    bool GlobalUnlock(void* hMem);
    void* GlobalFree(void* hMem);
    bool OpenClipboard(void* hwnd);
    bool EmptyClipboard();
    void* SetClipboardData(unsigned format, void* handle);
    bool CloseClipboard();
]]

local CF_TEXT = 1
local GHND = 0x0042
local GMEM_FIXED = 0x0000

local config = nil

local resize_icon_path = nil
local resize_icon = nil
local resize_icon_tex_id = 0

local function update_resize_icon_cache()
    if not resize_icon_path then
        return
    end
    if not resize_icon then
        resize_icon = renderer.get_texture(resize_icon_path)
        if resize_icon and resize_icon.texture then
            resize_icon_tex_id = resize_icon.tex_id or 0
        else
            resize_icon_tex_id = 0
        end
    end
end


local function copy_to_clipboard(text)
    print("[Chatter] Copying to clipboard...")
    local len = #text + 1
    local hMem = ffi.C.GlobalAlloc(GHND or GMEM_FIXED, len)
    if hMem == nil then 
        print("[Chatter] GlobalAlloc failed")
        return false 
    end
    
    local memPtr = ffi.C.GlobalLock(hMem)
    ffi.copy(memPtr, text, len)
    ffi.C.GlobalUnlock(hMem)

    if ffi.C.OpenClipboard(nil) then
        ffi.C.EmptyClipboard()
        if ffi.C.SetClipboardData(CF_TEXT, hMem) == nil then
            ffi.C.GlobalFree(hMem)
            ffi.C.CloseClipboard()
            print("[Chatter] SetClipboardData failed")
            return false
        end
        ffi.C.CloseClipboard()
        print("[Chatter] Copied successfully")
        return true
    else
        ffi.C.GlobalFree(hMem)
        print("[Chatter] OpenClipboard failed")
        return false
    end
end

config = settings.load(T{
    theme = 'Plain',
    background_asset = 'Progressive-Blue',
    border_asset = 'Silent-Reach',
    context_menu_theme = 'Progressive-Blue',
    font_family = 'Arial',
    font_size = 14,
    font_bold = true,
    font_italic = false,
    outline_enabled = true,
    window_x = 100,
    window_y = 100,
    window_w = 600,
    window_h = 400,
    lock_window = false,
    padding_x = 5,
    padding_y = 5,
    background_scale = 1.0,
    border_scale = 1.0,
    background_opacity = 1.0,
    border_opacity = 1.0,
    background_color = {1.0, 1.0, 1.0, 1.0},
    border_color = {1.0, 1.0, 1.0, 1.0},
    outline_color = {0.0, 0.0, 0.0, 1.0},
    colors = T{
        chat = T{
            say = {1.0, 1.0, 1.0, 1.0},
            tell = {0.8, 0.4, 1.0, 1.0},
            party = {0.4, 1.0, 1.0, 1.0},
            linkshell = {0.6, 1.0, 0.6, 1.0},
            linkshell2 = {0.6, 1.0, 0.6, 1.0},
            unity = {0.5, 0.8, 0.5, 1.0},
            emotes = {0.6, 0.8, 1.0, 1.0},
            messages = {1.0, 1.0, 1.0, 1.0},
            npc = {1.0, 1.0, 1.0, 1.0},
            shout = {1.0, 1.0, 0.4, 1.0},
            yell = {1.0, 0.6, 0.2, 1.0},
        },
        self = T{
            hpmp_recovered = {0.6, 1.0, 0.6, 1.0},
            hpmp_lost = {1.0, 0.2, 0.2, 1.0},
            beneficial_effects = {0.4, 0.6, 1.0, 1.0},
            detrimental_effects = {0.8, 0.4, 1.0, 1.0},
            resisted_effects = {1.0, 0.7, 0.4, 1.0},
            evaded_actions = {1.0, 0.7, 0.8, 1.0},
        },
        others = T{
            hpmp_recovered = {0.6, 1.0, 0.6, 1.0},
            hpmp_lost = {1.0, 0.2, 0.2, 1.0},
            beneficial_effects = {0.4, 0.6, 1.0, 1.0},
            detrimental_effects = {0.8, 0.4, 1.0, 1.0},
            resisted_effects = {1.0, 0.7, 0.4, 1.0},
            evaded_actions = {1.0, 0.7, 0.8, 1.0},
        },
        system = T{
            standard_battle = {0.6, 0.8, 1.0, 1.0},
            calls_for_help = {1.0, 0.6, 0.2, 1.0},
            basic_system = {0.95, 0.85, 0.6, 1.0},
        },
    },
})

if config.background_asset == nil or config.background_asset == '' then
    config.background_asset = 'Progressive-Blue'
end
if config.border_asset == nil or config.border_asset == '' then
    config.border_asset = 'Whispered-Veil'
end
if config.context_menu_theme == nil or config.context_menu_theme == '' then
    config.context_menu_theme = config.background_asset
end

if config.outline_color == nil then
    config.outline_color = {0.0, 0.0, 0.0, 1.0}
end
if config.font_style == nil or config.font_style == '' then
    if config.font_bold and config.font_italic then
        config.font_style = 'Bold Italic'
    elseif config.font_italic then
        config.font_style = 'Italic'
    else
        config.font_style = 'Bold'
        config.font_bold = true
        config.font_italic = false
    end
end
if config.font_style == 'Bold Italic' then
    config.font_bold = true
    config.font_italic = true
elseif config.font_style == 'Italic' then
    config.font_bold = false
    config.font_italic = true
elseif config.font_style == 'Bold' then
    config.font_bold = true
    config.font_italic = false
else
    config.font_style = 'Bold'
    config.font_bold = true
    config.font_italic = false
end

if config.colors and config.colors.self and config.colors.others and config.colors.self == config.colors.others then
    local copy = T{}
    for k, v in pairs(config.colors.self) do
        if type(v) == 'table' then
            copy[k] = {v[1], v[2], v[3], v[4]}
        else
            copy[k] = v
        end
    end
    config.colors.others = copy
    request_save()
end

local CHAT_MODES = {
    say = 9,
    shout = 10,
    yell = 11,
    tell = 12,
    party = 13,
    linkshell = 14,
    emote = 15,
    player = 36,
    others = 37,
    other_defeated = 44,
    synth = 121,
    battle = 122,
    misc_message2 = 142,
    misc_message3 = 144,
    item_receive = 146,
    misc_message = 148,
    message = 150,
    system = 151,
    message2 = 152,
    unity = 212,
    linkshell2 = 214,
    assist_jp = 220,
    assist_en = 222,
}

local function color_to_argb(color)
    if not color or #color < 4 then
        return 0xFFFFFFFF
    end
    local r = math.floor((color[1] or 1) * 255 + 0.5)
    local g = math.floor((color[2] or 1) * 255 + 0.5)
    local b = math.floor((color[3] or 1) * 255 + 0.5)
    local a = math.floor((color[4] or 1) * 255 + 0.5)
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(r, 16),
        bit.lshift(g, 8),
        b
    )
end

local function get_message_color(mode)
    local colors = config.colors
    if not colors then
        return 0xFFFFFFFF
    end
    local mid = bit.band(mode or 0, 0x000000FF)
    if mid == CHAT_MODES.say then
        return color_to_argb(colors.chat and colors.chat.say)
    elseif mid == CHAT_MODES.tell then
        return color_to_argb(colors.chat and colors.chat.tell)
    elseif mid == CHAT_MODES.party then
        return color_to_argb(colors.chat and colors.chat.party)
    elseif mid == CHAT_MODES.linkshell then
        return color_to_argb(colors.chat and colors.chat.linkshell)
    elseif mid == CHAT_MODES.linkshell2 then
        return color_to_argb(colors.chat and colors.chat.linkshell2)
    elseif mid == CHAT_MODES.unity then
        return color_to_argb(colors.chat and colors.chat.unity)
    elseif mid == CHAT_MODES.emote then
        return color_to_argb(colors.chat and colors.chat.emotes)
    elseif mid == CHAT_MODES.shout then
        return color_to_argb(colors.chat and colors.chat.shout)
    elseif mid == CHAT_MODES.yell then
        return color_to_argb(colors.chat and colors.chat.yell)
    elseif mid == CHAT_MODES.player
        or mid == CHAT_MODES.others
        or mid == CHAT_MODES.other_defeated
        or mid == CHAT_MODES.battle then
        return color_to_argb(colors.system and colors.system.standard_battle)
    elseif mid == CHAT_MODES.system then
        return color_to_argb(colors.system and colors.system.basic_system)
    elseif mid == CHAT_MODES.message
        or mid == CHAT_MODES.message2
        or mid == CHAT_MODES.misc_message
        or mid == CHAT_MODES.misc_message2
        or mid == CHAT_MODES.misc_message3 then
        return color_to_argb(colors.chat and colors.chat.messages)
    else
        return color_to_argb(colors.chat and colors.chat.messages)
    end
end

local function edit_color(label, tbl, key)
    if not tbl then
        return
    end
    local col = tbl[key] or {1.0, 1.0, 1.0, 1.0}
    local value = {col[1], col[2], col[3], col[4]}
    local flags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar)
    if imgui.ColorEdit4(label, value, flags) then
        tbl[key] = value
        request_save()
    end
end

local show_config = false
local current_config_section = 'General'
local is_dragging = false
local is_resizing = false
local drag_offset_x = 0
local drag_offset_y = 0
local resize_start_mouse_x = 0
local resize_start_mouse_y = 0
local resize_start_w = 0
local resize_start_h = 0
local resize_start_y = 0
local RESIZE_HANDLE_SIZE = 32
local MIN_WINDOW_W = 200
local MIN_WINDOW_H = 100
local shift_down = false
local selecting = false
local selection_start_abs = nil
local selection_end_abs = nil
local possible_selection_start = nil
local drag_threshold = 5
local anchor_start_abs = nil
local anchor_end_abs = nil
local imgui_wants_mouse = false

-- Initialize
ashita.events.register('load', 'chatter_load', function()
    show_config = false
    renderer.initialize(addon.path)
    renderer.set_background_asset(config.background_asset or 'Plain')
    renderer.set_border_asset(config.border_asset)
    renderer.update_style(
        config.font_family,
        config.font_size,
        config.font_bold,
        config.font_italic,
        config.outline_enabled,
        color_to_argb(config.outline_color or {0.0, 0.0, 0.0, 1.0})
    )
    local bg_col = config.background_color or {1.0, 1.0, 1.0, 1.0}
    local bd_col = config.border_color or {1.0, 1.0, 1.0, 1.0}
    renderer.set_background_color(color_to_argb(bg_col))
    renderer.set_border_color(color_to_argb(bd_col))
    renderer.set_background_scale(config.background_scale or 1.0)
    renderer.set_border_scale(config.border_scale or 1.0)
    renderer.set_background_opacity(config.background_opacity or 1.0)
    renderer.set_border_opacity(config.border_opacity or 1.0)
    renderer.set_chat_padding(get_effective_padding(config.padding_x), get_effective_padding(config.padding_y))

    resize_icon_path = addon.path .. 'assets\\backgrounds\\resize.png'
    update_resize_icon_cache()
    
    -- Load History
    chatmanager.load_history(addon.path .. 'chathistory.lua')
    
    -- Load welcome message
    chatmanager.add_line("Chatter v2.0 Initialized.", 0xFF00FF00)
    chatmanager.add_line("Engine: Ashita Fonts + ImGui Window", 0xFFFFFF00)
    
    -- Debug: Add 200 lines of fake chat history
    for i = 1, 200 do
        chatmanager.add_line("Debug Line #" .. i .. ": Checking performance with fake history.", 0xFFCCCCCC)
    end
end)

-- Unload
-- ashita.events.register('unload', 'chatter_unload', function()
--     chatmanager.save_history(addon.path .. 'chathistory.lua')
-- end)

-- ImGui Rendering
ashita.events.register('d3d_present', 'chatter_render_ui', function()
    if not renderer.is_assets_loaded() then
        return
    end
    -- Render the ImGui dummy window (invisible container for layout/geometry)
    imgui.SetNextWindowSize({ config.window_w, config.window_h }, ImGuiCond_Always)
    imgui.SetNextWindowPos({ config.window_x, config.window_y }, ImGuiCond_Always)

    local windowFlags = 0
    local function addFlag(flag)
        if type(flag) == 'number' then
            windowFlags = bit.bor(windowFlags, flag)
        end
    end

    addFlag(ImGuiWindowFlags_NoDecoration)
    addFlag(ImGuiWindowFlags_NoFocusOnAppearing)
    addFlag(ImGuiWindowFlags_NoNav)
    addFlag(ImGuiWindowFlags_NoBackground)
    addFlag(ImGuiWindowFlags_NoBringToFrontOnFocus)
    addFlag(ImGuiWindowFlags_NoDocking)
    addFlag(ImGuiWindowFlags_NoScrollbar)
    if config.lock_window then
        addFlag(ImGuiWindowFlags_NoMove)
    end
    
    if imgui.Begin("Chatter", true, windowFlags) then
        local pos_x, pos_y = imgui.GetCursorScreenPos()
        local avail_w, avail_h = imgui.GetContentRegionAvail()

        local pad_x = get_effective_padding(config.padding_x)
        local pad_y = get_effective_padding(config.padding_y)
        local render_x = pos_x
        local render_y = pos_y
        local render_w = math.max(0, avail_w)
        local render_h = math.max(0, avail_h)
        local content_x = pos_x + pad_x
        local content_y = pos_y + pad_y
        
        renderer.update_geometry(render_x, render_y, render_w, render_h)
        renderer.mark_geometry_ready()
        
        local win_x, win_y = imgui.GetWindowPos()
        local win_w, win_h = imgui.GetWindowSize()
        win_x = math.floor(win_x + 0.5)
        win_y = math.floor(win_y + 0.5)
        win_w = math.floor(win_w + 0.5)
        win_h = math.floor(win_h + 0.5)
        config.window_x = win_x
        config.window_y = win_y
        config.window_w = win_w
        config.window_h = win_h

        local draw_list = imgui.GetForegroundDrawList()
        if not config.lock_window then
            if not resize_icon then
                update_resize_icon_cache()
            end
            if resize_icon and resize_icon.texture and resize_icon_tex_id ~= 0 then
                local tint_u32 = 0xFFFFFFFF
                local size = 18
                local margin = -2
                local gx2 = win_x + win_w - margin
                local gy1 = win_y + margin
                local max_x = win_x + win_w
                local max_y = win_y + win_h
                local min_x = win_x
                local min_y = win_y
                if gx2 > max_x then gx2 = max_x end
                local gx1 = gx2 - size
                local gy2 = gy1 + size
                if gx1 < min_x then
                    gx1 = min_x
                    gx2 = gx1 + size
                end
                if gy1 < min_y then
                    gy1 = min_y
                    gy2 = gy1 + size
                elseif gy2 > max_y then
                    gy2 = max_y
                    gy1 = gy2 - size
                end
                draw_list:AddImage(resize_icon_tex_id, {gx1, gy1}, {gx2, gy2}, {0, 0}, {1, 1}, tint_u32)
            end
        end
        
        if imgui.IsWindowHovered() or is_resizing or is_dragging or selecting then
            local wheel = imgui.GetIO().MouseWheel
            if wheel ~= 0 then
                renderer.update_scroll(wheel * 3)
            end

            local mouse_x, mouse_y = imgui.GetMousePos()
            local rel_x = mouse_x - content_x - get_effective_padding(config.padding_x)
            local rel_y = mouse_y - content_y - get_effective_padding(config.padding_y)

            local resize_zone_x1 = win_x + win_w - RESIZE_HANDLE_SIZE + 5
            local resize_zone_y1 = win_y
            local resize_zone_y2 = win_y + RESIZE_HANDLE_SIZE - 5
            local in_resize_zone = (not config.lock_window) and (mouse_x >= resize_zone_x1) and (mouse_y >= resize_zone_y1) and (mouse_y <= resize_zone_y2)

            if imgui.IsMouseClicked(0) and in_resize_zone then
                is_resizing = true
                renderer.set_resizing(true)
                resize_start_mouse_x = mouse_x
                resize_start_mouse_y = mouse_y
                resize_start_w = config.window_w
                resize_start_h = config.window_h
                resize_start_y = config.window_y
                possible_selection_start = nil
                selecting = false
            end

            if is_resizing and imgui.IsMouseDown(0) then
                local dx = mouse_x - resize_start_mouse_x
                local dy = mouse_y - resize_start_mouse_y
                local new_w = resize_start_w + dx
                if new_w < MIN_WINDOW_W then new_w = MIN_WINDOW_W end
                local bottom_y = resize_start_y + resize_start_h
                local new_h = resize_start_h - dy
                if new_h < MIN_WINDOW_H then new_h = MIN_WINDOW_H end
                local new_y = bottom_y - new_h
                config.window_w = new_w
                config.window_h = new_h
                config.window_y = new_y
            elseif is_resizing and not imgui.IsMouseDown(0) then
                is_resizing = false
                renderer.set_resizing(false)
                request_save()
            end

            if imgui.IsMouseClicked(0) and shift_down and not in_resize_zone and not is_resizing and not config.lock_window then
                is_dragging = true
                drag_offset_x = mouse_x - config.window_x
                drag_offset_y = mouse_y - config.window_y
                possible_selection_start = nil
                selecting = false
            end

            if is_dragging and imgui.IsMouseDown(0) and shift_down then
                local new_x = mouse_x - drag_offset_x
                local new_y = mouse_y - drag_offset_y
                config.window_x = new_x
                config.window_y = new_y
            elseif is_dragging and (not imgui.IsMouseDown(0) or not shift_down) then
                is_dragging = false
                request_save()
            end

            if not is_dragging and not is_resizing then
                if imgui.IsMouseClicked(0) and not shift_down then
                    local page_size = renderer.get_page_size()
                    local line_spacing = 2
                    local line_height = config.font_size + line_spacing

                    if rel_y >= 0 then
                        local index = math.floor(rel_y / line_height) + 1
                        if index >= 1 and index <= page_size then
                            local line_index, seg_start, seg_end = renderer.get_view_line(index)
                            if line_index then
                                local full_text = chatmanager.get_line_text(line_index) or ""
                                local segment_text = ""
                                if full_text ~= "" and seg_start <= #full_text then
                                    local seg_end_clamped = math.min(seg_end, #full_text)
                                    segment_text = full_text:sub(seg_start, seg_end_clamped)
                                end
                                local rel_char = renderer.get_char_index_from_x(segment_text, rel_x)
                                if rel_char < 1 then rel_char = 1 end
                                if rel_char > #segment_text then rel_char = #segment_text end
                                local char_idx = seg_start + rel_char - 1

                                possible_selection_start = { line = line_index, char = char_idx }
                                selecting = false
                                renderer.set_selection(nil, nil)
                                selection_start_abs = nil
                                selection_end_abs = nil
                            end
                        end
                    end
                elseif imgui.IsMouseDragging(0) and possible_selection_start and not shift_down then
                    selecting = true
                    anchor_start_abs = { line = possible_selection_start.line, char = possible_selection_start.char }
                    possible_selection_start = nil
                end

                if selecting and imgui.IsMouseDown(0) and not shift_down then
                    local page_size = renderer.get_page_size()
                    local line_spacing = 2
                    local line_height = config.font_size + line_spacing

                    local index = math.floor(rel_y / line_height) + 1
                    if index < 1 then index = 1 end
                    if index > page_size then index = page_size end

                    local line_index, seg_start, seg_end = renderer.get_view_line(index)
                    local current_pos = nil

                    if line_index then
                        local full_text = chatmanager.get_line_text(line_index) or ""
                        local segment_text = ""
                        if full_text ~= "" and seg_start <= #full_text then
                            local seg_end_clamped = math.min(seg_end, #full_text)
                            segment_text = full_text:sub(seg_start, seg_end_clamped)
                        end

                        local rel_char = renderer.get_char_index_from_x(segment_text, rel_x)
                        if rel_char < 1 then rel_char = 1 end
                        if rel_char > #segment_text then rel_char = #segment_text end
                        local char_idx = seg_start + rel_char - 1

                        current_pos = { line = line_index, char = char_idx }
                    else
                        current_pos = anchor_start_abs
                    end

                    if current_pos then
                        if current_pos.line < anchor_start_abs.line or (current_pos.line == anchor_start_abs.line and current_pos.char < anchor_start_abs.char) then
                            selection_start_abs = current_pos
                            selection_end_abs = anchor_start_abs
                        else
                            selection_start_abs = anchor_start_abs
                            selection_end_abs = current_pos
                        end
                        renderer.set_selection(selection_start_abs, selection_end_abs)
                    end
                end

                if imgui.IsMouseReleased(0) then
                    selecting = false
                    possible_selection_start = nil
                end
            end

            if imgui.IsMouseClicked(1) then
                renderer.show_context_menu(mouse_x, mouse_y)
            end
            if renderer.is_context_menu_visible() and imgui.IsMouseClicked(0) then
                renderer.hide_context_menu()
            end
        end
    end
    imgui.End()
    if save_pending and (os.clock() - last_save_request) >= SAVE_DEBOUNCE_SEC then
        settings.save()
        save_pending = false
    end
end)


-- Incoming Text
ashita.events.register('text_in', 'chatter_text_in', function(e)
    local text = e.message_modified or e.message
    if not text or text == '' then
        return
    end
    local mode = e.mode_modified or e.mode or 0
    local color = get_message_color(mode)
    chatmanager.add_line(text, color)
end)

-- Mouse Input (Selection handling moved to ImGui window)
-- ashita.events.register('mouse', 'chatter_mouse', function(e)
-- end)

ashita.events.register('key_data', 'chatter_key_data', function(e)
    if e.key == 0x2A or e.key == 0x36 then
        shift_down = e.down
    end
end)

-- Configuration UI (ImGui)
ashita.events.register('d3d_present', 'chatter_config_ui', function()
    -- Cache ImGui state safely in the render loop
    local io = imgui.GetIO()
    imgui_wants_mouse = io.WantCaptureMouse
    
    if not show_config then return end
    
    local font_options = {
        'Arial',
        'Calibri',
        'Cambria',
        'Candara',
        'Comic Sans MS',
        'Consolas',
        'Courier New',
        'Franklin Gothic',
        'Georgia',
        'Impact',
        'Lucida Console',
        'Lucida Sans',
        'Lucida Sans Typewriter',
        'Lucida Sans Unicode',
        'Microsoft Sans Serif',
        'Tahoma',
        'Times New Roman',
        'Trebuchet MS',
        'Verdana',
    }

    local accent = {0.30, 0.55, 0.95, 1.0}
    local accentDark = {0.20, 0.40, 0.75, 1.0}
    local accentDarker = {0.12, 0.28, 0.55, 1.0}
    local accentLight = {0.40, 0.65, 0.98, 1.0}
    local bgDark = {0.050, 0.055, 0.070, 0.95}
    local bgMedium = {0.070, 0.080, 0.100, 1.0}
    local bgLight = {0.095, 0.105, 0.130, 1.0}
    local bgLighter = {0.120, 0.135, 0.165, 1.0}
    local textLight = {0.900, 0.920, 0.950, 1.0}
    local borderDark = {0.16, 0.24, 0.40, 1.0}

    local bgColor = bgDark
    local buttonColor = bgMedium
    local buttonHoverColor = bgLight
    local buttonActiveColor = bgLighter

    if show_config then
        imgui.PushStyleColor(ImGuiCol_WindowBg, bgColor)
        imgui.PushStyleColor(ImGuiCol_ChildBg, {0, 0, 0, 0})
        imgui.PushStyleColor(ImGuiCol_TitleBg, bgMedium)
        imgui.PushStyleColor(ImGuiCol_TitleBgActive, bgLight)
        imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, bgDark)
        imgui.PushStyleColor(ImGuiCol_FrameBg, bgMedium)
        imgui.PushStyleColor(ImGuiCol_FrameBgHovered, bgLight)
        imgui.PushStyleColor(ImGuiCol_FrameBgActive, bgLighter)
        imgui.PushStyleColor(ImGuiCol_Header, bgLight)
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, bgLighter)
        imgui.PushStyleColor(ImGuiCol_HeaderActive, {accent[1], accent[2], accent[3], 0.35})
        imgui.PushStyleColor(ImGuiCol_Border, borderDark)
        imgui.PushStyleColor(ImGuiCol_Text, textLight)
        imgui.PushStyleColor(ImGuiCol_TextDisabled, {0.55, 0.62, 0.78, 1.0})
        imgui.PushStyleColor(ImGuiCol_Button, buttonColor)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, buttonHoverColor)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, buttonActiveColor)
        imgui.PushStyleColor(ImGuiCol_CheckMark, accent)
        imgui.PushStyleColor(ImGuiCol_SliderGrab, accentDark)
        imgui.PushStyleColor(ImGuiCol_SliderGrabActive, accent)
        imgui.PushStyleColor(ImGuiCol_Tab, bgMedium)
        imgui.PushStyleColor(ImGuiCol_TabHovered, bgLight)
        imgui.PushStyleColor(ImGuiCol_TabActive, {accent[1], accent[2], accent[3], 0.35})
        imgui.PushStyleColor(ImGuiCol_TabUnfocused, bgDark)
        imgui.PushStyleColor(ImGuiCol_TabUnfocusedActive, bgMedium)
        imgui.PushStyleColor(ImGuiCol_ScrollbarBg, bgMedium)
        imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, accentDarker)
        imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, accentDark)
        imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, accent)
        imgui.PushStyleColor(ImGuiCol_ResizeGrip, {accent[1], accent[2], accent[3], 0.35})
        imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, accentLight)
        imgui.PushStyleColor(ImGuiCol_ResizeGripActive, accent)

        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {12, 12})
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {6, 4})
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 6})
        imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)
        imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
        imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0)
        imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0)
        imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0)

        imgui.SetNextWindowSize({ 900, 650 }, ImGuiCond_FirstUseEver)
        local config_open = { show_config }
        local config_visible = imgui.Begin("Chatter Config", config_open, 0)
        show_config = config_open[1]
        if not config_visible then
            imgui.End()
            imgui.PopStyleVar(8)
            imgui.PopStyleColor(31)
            return
        end

        local sidebarWidth = 180

        imgui.BeginChild("ChatterConfigLeft", {sidebarWidth, 0}, true)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {8, 6})

    local general_selected = (current_config_section == 'General')
    if general_selected then
        imgui.PushStyleColor(ImGuiCol_Button, accent)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, accentLight)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, accentDarker)
    else
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0})
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {accent[1], accent[2], accent[3], 0.25})
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {accent[1], accent[2], accent[3], 0.35})
    end
    if imgui.Button("General", {sidebarWidth - 24, 24}) then
        current_config_section = 'General'
    end
    imgui.PopStyleColor(3)

    local fonts_selected = (current_config_section == 'Fonts')
    if fonts_selected then
        imgui.PushStyleColor(ImGuiCol_Button, accent)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, accentLight)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, accentDarker)
    else
        imgui.PushStyleColor(ImGuiCol_Button, {0, 0, 0, 0})
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {accent[1], accent[2], accent[3], 0.25})
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {accent[1], accent[2], accent[3], 0.35})
    end
    if imgui.Button("Fonts", {sidebarWidth - 24, 24}) then
        current_config_section = 'Fonts'
    end
    imgui.PopStyleColor(3)

    imgui.PopStyleVar()
    imgui.EndChild()

    imgui.SameLine()

    imgui.BeginChild("ChatterConfigRight", {0, 0}, false)

    if config_visible and current_config_section == 'General' then
        if imgui.BeginTabBar("ChatterGeneralTabs") then
            if imgui.BeginTabItem("General") then
                local function scan_assets()
                    local root = addon.path .. 'assets\\backgrounds\\'
                    local function file_exists(path)
                        if ashita and ashita.fs and ashita.fs.exists then
                            return ashita.fs.exists(path)
                        end
                        local f = io.open(path, 'rb')
                        if f then
                            f:close()
                            return true
                        end
                        return false
                    end
                    local background_order = {
                        'Progressive Blue',
                        'Concrete',
                        'Interlaced Blue',
                        'Dark Matter',
                        'White Canvas',
                        'Abyss Blue',
                        'Warm Sand',
                        'Deep Ocean',
                        'Simple Geometry',
                    }
                    local border_order = {
                        'Silent Reach',
                        'Whispered Veil',
                        'Ethereal Frame',
                        'Celestial Mantle',
                        'Radiant Enclosure',
                        'Ventilated Steel',
                        'Ironclad Steel',
                        'Inset Gold',
                        'Solid Gold',
                        'Sandstorm',
                        'Sandpaper',
                        'Sea Lantern',
                        'Prismarine',
                    }
                    local backgrounds = {}
                    local borders = {}
                    for _, name in ipairs(background_order) do
                        local base = name:gsub('%s+', '-')
                        if file_exists(root .. base .. '-bg.png') then
                            table.insert(backgrounds, { base = base, display = name })
                        end
                    end
                    for _, name in ipairs(border_order) do
                        local base = name:gsub('%s+', '-')
                        if file_exists(root .. base .. '-corners.png') and file_exists(root .. base .. '-sides.png') then
                            table.insert(borders, { base = base, display = name })
                        end
                    end
                    for i, item in ipairs(backgrounds) do
                        item.display_num = string.format('%d - %s', i, item.display)
                    end
                    for i, item in ipairs(borders) do
                        item.display_num = string.format('%d - %s', i, item.display)
                    end
                    return backgrounds, borders
                end
                local function display_for(list, base)
                    if not base then
                        return ''
                    end
                    for _, it in ipairs(list) do
                        if it.base == base then
                            return it.display_num or it.display
                        end
                    end
                    return base:gsub('%-', ' ')
                end
                local bg_items, border_items = scan_assets()
                local current_bg = config.background_asset or 'Plain'
                if imgui.BeginCombo("Background Image", display_for(bg_items, current_bg)) then
                    for _, it in ipairs(bg_items) do
                        local selected = (current_bg == it.base)
                        if imgui.Selectable(it.display_num or it.display, selected) then
                            config.background_asset = it.base
                            renderer.set_background_asset(it.base)
                            request_save()
                        end
                        if selected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end
                local current_border = config.border_asset or 'Whispered-Veil'
                if imgui.BeginCombo("Border Style", display_for(border_items, current_border)) then
                    for _, it in ipairs(border_items) do
                        local selected = (current_border == it.base)
                        if imgui.Selectable(it.display_num or it.display, selected) then
                            config.border_asset = it.base
                            renderer.set_border_asset(it.base)
                            renderer.set_context_menu_border_asset(it.base)
                            request_save()
                        end
                        if selected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end
                
                local bg_scale_buf = { config.background_scale or 1.0 }
                if imgui.SliderFloat("Background Scale", bg_scale_buf, 0.1, 3.0, "%.2f") then
                    config.background_scale = bg_scale_buf[1]
                    renderer.set_background_scale(bg_scale_buf[1])
                    request_save()
                end

                local bg_opacity_buf = { config.background_opacity or 1.0 }
                if imgui.SliderFloat("Background Opacity", bg_opacity_buf, 0.0, 1.0, "%.2f") then
                    config.background_opacity = bg_opacity_buf[1]
                    renderer.set_background_opacity(bg_opacity_buf[1])
                    local bg_col = config.background_color or {1.0, 1.0, 1.0, 1.0}
                    bg_col[4] = bg_opacity_buf[1]
                    config.background_color = bg_col
                    renderer.set_background_color(color_to_argb(bg_col))
                    request_save()
                end

                local border_opacity_buf = { config.border_opacity or 1.0 }
                if imgui.SliderFloat("Border Opacity", border_opacity_buf, 0.0, 1.0, "%.2f") then
                    config.border_opacity = border_opacity_buf[1]
                    renderer.set_border_opacity(border_opacity_buf[1])
                    local bd_col = config.border_color or {1.0, 1.0, 1.0, 1.0}
                    bd_col[4] = border_opacity_buf[1]
                    config.border_color = bd_col
                    renderer.set_border_color(color_to_argb(bd_col))
                    request_save()
                end

                local pad_x_buf = { config.padding_x or 5 }
                if imgui.SliderInt("Window Padding X", pad_x_buf, 0, 30) then
                    config.padding_x = pad_x_buf[1]
                    renderer.set_chat_padding(get_effective_padding(config.padding_x), get_effective_padding(config.padding_y))
                    request_save()
                end

                local pad_y_buf = { config.padding_y or 5 }
                if imgui.SliderInt("Window Padding Y", pad_y_buf, 0, 30) then
                    config.padding_y = pad_y_buf[1]
                    renderer.set_chat_padding(get_effective_padding(config.padding_x), get_effective_padding(config.padding_y))
                    request_save()
                end

                imgui.Spacing()
                imgui.Text("Context Menu")

                local current_menu_theme = config.context_menu_theme or 'Plain'
                if imgui.BeginCombo("Context Menu Background", display_for(bg_items, current_menu_theme)) then
                    for _, it in ipairs(bg_items) do
                        local name = it.base
                        local selected = (current_menu_theme == name)
                        if imgui.Selectable(it.display_num or it.display, selected) then
                            config.context_menu_theme = name
                            renderer.set_context_menu_background_asset(name)
                            request_save()
                        end
                        if selected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end

                local lock_val = { config.lock_window }
                if imgui.Checkbox("Lock Window (Hide Resize Icon)", lock_val) then
                    config.lock_window = lock_val[1]
                    request_save()
                end

                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("Colors") then
                local color_flags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar)
                local bg_col = config.background_color or {1.0, 1.0, 1.0, 1.0}
                local bg_val = {bg_col[1], bg_col[2], bg_col[3], bg_col[4]}
                if imgui.ColorEdit4("Background Color", bg_val, color_flags) then
                    config.background_color = bg_val
                    renderer.set_background_color(color_to_argb(bg_val))
                    config.background_opacity = bg_val[4]
                    renderer.set_background_opacity(bg_val[4])
                    request_save()
                end

                local bd_col = config.border_color or {1.0, 1.0, 1.0, 1.0}
                local bd_val = {bd_col[1], bd_col[2], bd_col[3], bd_col[4]}
                if imgui.ColorEdit4("Border Color", bd_val, color_flags) then
                    config.border_color = bd_val
                    renderer.set_border_color(color_to_argb(bd_val))
                    config.border_opacity = bd_val[4]
                    renderer.set_border_opacity(bd_val[4])
                    request_save()
                end

                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end
    elseif config_visible and current_config_section == 'Fonts' then
        if imgui.BeginTabBar("ChatterFontsTabs") then
            if imgui.BeginTabItem("Fonts") then
                local current_font = config.font_family
                local found = false
                for _, name in ipairs(font_options) do
                    if name == current_font then
                        found = true
                        break
                    end
                end
                if not found then
                    current_font = 'Arial'
                    config.font_family = current_font
                    renderer.update_style(
                        config.font_family,
                        config.font_size,
                        config.font_bold,
                        config.font_italic,
                        config.outline_enabled,
                        color_to_argb(config.outline_color or {0.0, 0.0, 0.0, 1.0})
                    )
                    request_save()
                end
                
                if imgui.BeginCombo("Font Family", current_font) then
                    for _, name in ipairs(font_options) do
                        local selected = (config.font_family == name)
                        if imgui.Selectable(name, selected) then
                            config.font_family = name
                            renderer.update_style(
                                config.font_family,
                                config.font_size,
                                config.font_bold,
                                config.font_italic,
                                config.outline_enabled
                            )
                            request_save()
                        end
                        if selected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end
                
                local size_buf = { config.font_size }
                if imgui.SliderInt("Font Size", size_buf, 8, 32) then
                    config.font_size = size_buf[1]
                end
                if imgui.IsItemDeactivatedAfterEdit() then
                    renderer.update_style(
                        config.font_family,
                        config.font_size,
                        config.font_bold,
                        config.font_italic,
                        config.outline_enabled,
                        color_to_argb(config.outline_color or {0.0, 0.0, 0.0, 1.0})
                    )
                    request_save()
                end
                
                local style_options = { 'Bold', 'Italic', 'Bold Italic' }
                local current_style = config.font_style or 'Bold'
                if current_style ~= 'Bold' and current_style ~= 'Italic' and current_style ~= 'Bold Italic' then
                    if config.font_bold and config.font_italic then
                        current_style = 'Bold Italic'
                    elseif config.font_italic then
                        current_style = 'Italic'
                    else
                        current_style = 'Bold'
                    end
                    config.font_style = current_style
                end
                if imgui.BeginCombo("Font Style", current_style) then
                    for _, style in ipairs(style_options) do
                        local selected = (current_style == style)
                        if imgui.Selectable(style, selected) then
                            config.font_style = style
                            config.font_bold = (style == 'Bold' or style == 'Bold Italic')
                            config.font_italic = (style == 'Italic' or style == 'Bold Italic')
                            renderer.update_style(
                                config.font_family,
                                config.font_size,
                                config.font_bold,
                                config.font_italic,
                                config.outline_enabled,
                                color_to_argb(config.outline_color or {0.0, 0.0, 0.0, 1.0})
                            )
                            request_save()
                        end
                        if selected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end

                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("Colors") then
                local color_flags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar)
                local colors = config.colors
                if colors then
                    if imgui.CollapsingHeader("Chat") then
                        edit_color("Say (White)", colors.chat, 'say')
                        edit_color("Tell (Purple)", colors.chat, 'tell')
                        edit_color("Party (Cyan)", colors.chat, 'party')
                        edit_color("Linkshell (Light Green)", colors.chat, 'linkshell')
                        edit_color("Linkshell 2 (Light Green)", colors.chat, 'linkshell2')
                        edit_color("Unity (Faded Green)", colors.chat, 'unity')
                        edit_color("Emotes (Light Blue)", colors.chat, 'emotes')
                        edit_color("Messages (White)", colors.chat, 'messages')
                        edit_color("NPC (White)", colors.chat, 'npc')
                        edit_color("Shout (Yellow)", colors.chat, 'shout')
                        edit_color("Yell (Orange)", colors.chat, 'yell')

                        local outline_col = config.outline_color or {0.0, 0.0, 0.0, 1.0}
                        local outline_val = {outline_col[1], outline_col[2], outline_col[3], outline_col[4]}
                        if imgui.ColorEdit4("Outline Color", outline_val, color_flags) then
                            config.outline_color = outline_val
                            renderer.update_style(
                                config.font_family,
                                config.font_size,
                                config.font_bold,
                                config.font_italic,
                                config.outline_enabled,
                                color_to_argb(outline_val)
                            )
                            request_save()
                        end
                    end

                    if imgui.CollapsingHeader("For Self") then
                        edit_color("HP/MP Recovered (Light Green)", colors.self, 'hpmp_recovered')
                        edit_color("HP/MP Lost (Red)", colors.self, 'hpmp_lost')
                        edit_color("Beneficial Effects (Blue)", colors.self, 'beneficial_effects')
                        edit_color("Detrimental Effects (Purple)", colors.self, 'detrimental_effects')
                        edit_color("Resisted Effects (Light Orange)", colors.self, 'resisted_effects')
                        edit_color("Evaded Actions (Light Pink)", colors.self, 'evaded_actions')
                    end

                    if imgui.CollapsingHeader("For Others") then
                        edit_color("HP/MP Recovered (Light Green)", colors.others, 'hpmp_recovered')
                        edit_color("HP/MP Lost (Red)", colors.others, 'hpmp_lost')
                        edit_color("Beneficial Effects (Blue)", colors.others, 'beneficial_effects')
                        edit_color("Detrimental Effects (Purple)", colors.others, 'detrimental_effects')
                        edit_color("Resisted Effects (Light Orange)", colors.others, 'resisted_effects')
                        edit_color("Evaded Actions (Light Pink)", colors.others, 'evaded_actions')
                    end

                    if imgui.CollapsingHeader("System") then
                        edit_color("Standard Battle Messages (Light Blue)", colors.system, 'standard_battle')
                        edit_color("Calls For Help (Orange)", colors.system, 'calls_for_help')
                        edit_color("Basic System Messages (Light Yellow Brown)", colors.system, 'basic_system')
                    end
                end

                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end
    end

        imgui.EndChild()
        
        imgui.End()

        imgui.PopStyleVar(8)
        imgui.PopStyleColor(31)
    end
end)

ashita.events.register('unload', 'chatter_unload', function()
    chatmanager.save_history(addon.path .. 'chathistory.lua')
    renderer.dispose()
end)

ashita.events.register('command', 'chatter_command', function(e)
    local args = e.command:args()
    if #args == 0 or not args[1]:any('/chatter') then
        return
    end

    e.blocked = true
    show_config = not show_config
end)
