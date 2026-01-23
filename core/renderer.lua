local renderer = {}
require('common')
local d3d = require('d3d8')
local chat_manager = require('chat_manager')
local gdi = require('submodules.gdifonts.include')
local bit = require('bit')

local measurement_cache = {}

local CachedFont = {}
CachedFont.__index = CachedFont

function CachedFont.new(font_obj)
    local self = setmetatable({}, CachedFont)
    self.font = font_obj
    self.cache = {
        text = nil,
        color = nil,
        pos_x = nil,
        pos_y = nil,
        visible = nil,
        height = nil,
        family = nil,
        flags = nil,
        outline_color = nil,
        outline_width = nil,
    }
    return self
end

function CachedFont:set_text(text)
    if self.cache.text ~= text then
        self.font:set_text(text)
        self.cache.text = text
    end
end

function CachedFont:set_font_color(color)
    if self.cache.color ~= color then
        self.font:set_font_color(color)
        self.cache.color = color
    end
end

function CachedFont:set_position_x(x)
    if self.cache.pos_x ~= x then
        self.font:set_position_x(x)
        self.cache.pos_x = x
    end
end

function CachedFont:set_position_y(y)
    if self.cache.pos_y ~= y then
        self.font:set_position_y(y)
        self.cache.pos_y = y
    end
end

function CachedFont:set_visible(visible)
    if self.cache.visible ~= visible then
        self.font:set_visible(visible)
        self.cache.visible = visible
    end
end

function CachedFont:set_font_height(height)
    if self.cache.height ~= height then
        self.font:set_font_height(height)
        self.cache.height = height
    end
end

function CachedFont:set_font_family(family)
    if self.cache.family ~= family then
        self.font:set_font_family(family)
        self.cache.family = family
    end
end

function CachedFont:set_font_flags(flags)
    if self.cache.flags ~= flags then
        self.font:set_font_flags(flags)
        self.cache.flags = flags
    end
end

function CachedFont:set_outline_color(color)
    if self.cache.outline_color ~= color then
        self.font:set_outline_color(color)
        self.cache.outline_color = color
    end
end

function CachedFont:set_outline_width(width)
    if self.cache.outline_width ~= width then
        self.font:set_outline_width(width)
        self.cache.outline_width = width
    end
end

function CachedFont:get_text_size()
    return self.font:get_text_size()
end

function CachedFont:get_font_height()
    return self.cache.height or self.font:get_font_height()
end

local font_pool = {}
local pool_size = 50
local font_height = 14
local layout_lines = {}
local total_visual_lines = 0
local window_rect = { x = 100, y = 100, w = 600, h = 400 }
local scroll_offset = 0
local is_resizing = false
local is_layout_dirty = true
local is_render_dirty = true
local selection_start_abs = nil
local selection_end_abs = nil
local measure_font = nil

local selection_prims = {}
local addon_path_cache = ''

local bg_primitive = nil
local bg_tex_primitive = nil
local border_prims = { tl = nil, tr = nil, bl = nil, br = nil }
local current_theme = 'Plain'
local background_color = 0xC0000000
local border_color = 0xFFFFFFFF

local PADDING = 0
local LINE_SPACING = 2
local outline_colors = {
    off = 0x00000000,
    on = 0xFF000000,
}

local BORDER_PADDING = 8
local BORDER_SIZE = 21
local BORDER_OFFSET = 1
local BORDER_SCALE = 1.0

local function is_window_theme(name)
    if not name then
        return false
    end
    return name:match('^Window%d+$') ~= nil
end

local function update_background_geometry()
    local padding = BORDER_PADDING
    local x = window_rect.x - padding
    local y = window_rect.y - padding
    local w = window_rect.w + (padding * 2)
    local h = window_rect.h + (padding * 2)

    if bg_primitive then
        bg_primitive:SetColor(background_color)
        bg_primitive:SetPositionX(x)
        bg_primitive:SetPositionY(y)
        bg_primitive:SetWidth(w)
        bg_primitive:SetHeight(h)
    end

    if bg_tex_primitive then
        bg_tex_primitive:SetPositionX(x)
        bg_tex_primitive:SetPositionY(y)
        bg_tex_primitive:SetWidth(w)
        bg_tex_primitive:SetHeight(h)
    end

    if border_prims.br then
        local use_borders = is_window_theme(current_theme)
        if not use_borders then
            for _, prim in pairs(border_prims) do
                if prim then
                    prim:SetVisible(false)
                end
            end
            return
        end

        local bg_width = window_rect.w + (padding * 2)
        local bg_height = window_rect.h + (padding * 2)
        local bg_x = window_rect.x - padding
        local bg_y = window_rect.y - padding

        local border_size = BORDER_SIZE
        local bg_offset = BORDER_OFFSET
        local border_scale = BORDER_SCALE
        local final_color = border_color

        local br = border_prims.br
        if br then
            br:SetVisible(true)
            local br_x = bg_x + bg_width - math.floor((border_size * border_scale) - (bg_offset * border_scale))
            local br_y = bg_y + bg_height - math.floor((border_size * border_scale) - (bg_offset * border_scale))
            br:SetPositionX(br_x)
            br:SetPositionY(br_y)
            br:SetWidth(border_size)
            br:SetHeight(border_size)
            br:SetScaleX(border_scale)
            br:SetScaleY(border_scale)
            br:SetColor(final_color)
        end

        local tr = border_prims.tr
        if tr and br then
            tr:SetVisible(true)
            local tr_x = br:GetPositionX()
            local tr_y = bg_y - (bg_offset * border_scale)
            tr:SetPositionX(tr_x)
            tr:SetPositionY(tr_y)
            tr:SetWidth(border_size)
            local tr_height = math.ceil((br:GetPositionY() - tr_y) / border_scale)
            tr:SetHeight(tr_height)
            tr:SetScaleX(border_scale)
            tr:SetScaleY(border_scale)
            tr:SetColor(final_color)
        elseif tr then
            tr:SetVisible(false)
        end

        local tl = border_prims.tl
        if tl and tr then
            tl:SetVisible(true)
            local tl_x = bg_x - (bg_offset * border_scale)
            local tl_y = bg_y - (bg_offset * border_scale)
            tl:SetPositionX(tl_x)
            tl:SetPositionY(tl_y)
            local tl_width = math.ceil((tr:GetPositionX() - tl_x) / border_scale)
            tl:SetWidth(tl_width)
            tl:SetHeight(tr:GetHeight())
            tl:SetScaleX(border_scale)
            tl:SetScaleY(border_scale)
            tl:SetColor(final_color)
        elseif tl then
            tl:SetVisible(false)
        end

        local bl = border_prims.bl
        if bl and tl and br then
            bl:SetVisible(true)
            bl:SetPositionX(tl:GetPositionX())
            bl:SetPositionY(br:GetPositionY())
            bl:SetWidth(tl:GetWidth())
            bl:SetHeight(br:GetHeight())
            bl:SetScaleX(border_scale)
            bl:SetScaleY(border_scale)
            bl:SetColor(final_color)
        elseif bl then
            bl:SetVisible(false)
        end
    end
end

local function get_xiui_addon_path()
    local lower = addon_path_cache:lower()
    local idx = lower:find('\\chatter\\', 1, true) or lower:find('/chatter/', 1, true)
    if idx then
        return addon_path_cache:sub(1, idx) .. 'XIUI\\'
    end
    return addon_path_cache
end

function renderer.initialize(addon_path)
    addon_path_cache = addon_path
    
    -- Force cleanup of potential stale objects from previous crashes
    local pm = AshitaCore:GetPrimitiveManager()
    if pm then
        pm:Delete('chatter_bg_rect')
        pm:Delete('chatter_bg_tex')
        pm:Delete('chatter_border_tl')
        pm:Delete('chatter_border_tr')
        pm:Delete('chatter_border_bl')
        pm:Delete('chatter_border_br')
    end
    
    local fm = AshitaCore:GetFontManager()
    if fm then
        for i = 1, pool_size do
            fm:Delete('chatter_font_' .. i)
        end
        fm:Delete('chatter_font_measure')
    end

    local pm2 = AshitaCore:GetPrimitiveManager()
    if pm2 then
        bg_primitive = pm2:Create('chatter_bg_rect')
        if bg_primitive then
            bg_primitive:SetColor(background_color)
            bg_primitive:SetPositionX(window_rect.x)
            bg_primitive:SetPositionY(window_rect.y)
            bg_primitive:SetWidth(window_rect.w)
            bg_primitive:SetHeight(window_rect.h)
            bg_primitive:SetLocked(true)
            bg_primitive:SetCanFocus(false)
            bg_primitive:SetVisible(true)
        end

        bg_tex_primitive = pm2:Create('chatter_bg_tex')
        if bg_tex_primitive then
            bg_tex_primitive:SetColor(0xFFFFFFFF)
            bg_tex_primitive:SetPositionX(window_rect.x)
            bg_tex_primitive:SetPositionY(window_rect.y)
            bg_tex_primitive:SetWidth(window_rect.w)
            bg_tex_primitive:SetHeight(window_rect.h)
            bg_tex_primitive:SetLocked(true)
            bg_tex_primitive:SetCanFocus(false)
            bg_tex_primitive:SetVisible(false)
        end

        border_prims.tl = pm2:Create('chatter_border_tl')
        if border_prims.tl then
            border_prims.tl:SetColor(border_color)
            border_prims.tl:SetPositionX(window_rect.x)
            border_prims.tl:SetPositionY(window_rect.y)
            border_prims.tl:SetWidth(BORDER_SIZE)
            border_prims.tl:SetHeight(BORDER_SIZE)
            border_prims.tl:SetLocked(true)
            border_prims.tl:SetCanFocus(false)
            border_prims.tl:SetVisible(false)
        end

        border_prims.tr = pm2:Create('chatter_border_tr')
        if border_prims.tr then
            border_prims.tr:SetColor(border_color)
            border_prims.tr:SetPositionX(window_rect.x)
            border_prims.tr:SetPositionY(window_rect.y)
            border_prims.tr:SetWidth(BORDER_SIZE)
            border_prims.tr:SetHeight(BORDER_SIZE)
            border_prims.tr:SetLocked(true)
            border_prims.tr:SetCanFocus(false)
            border_prims.tr:SetVisible(false)
        end

        border_prims.bl = pm2:Create('chatter_border_bl')
        if border_prims.bl then
            border_prims.bl:SetColor(border_color)
            border_prims.bl:SetPositionX(window_rect.x)
            border_prims.bl:SetPositionY(window_rect.y)
            border_prims.bl:SetWidth(BORDER_SIZE)
            border_prims.bl:SetHeight(BORDER_SIZE)
            border_prims.bl:SetLocked(true)
            border_prims.bl:SetCanFocus(false)
            border_prims.bl:SetVisible(false)
        end

        border_prims.br = pm2:Create('chatter_border_br')
        if border_prims.br then
            border_prims.br:SetColor(border_color)
            border_prims.br:SetPositionX(window_rect.x)
            border_prims.br:SetPositionY(window_rect.y)
            border_prims.br:SetWidth(BORDER_SIZE)
            border_prims.br:SetHeight(BORDER_SIZE)
            border_prims.br:SetLocked(true)
            border_prims.br:SetCanFocus(false)
            border_prims.br:SetVisible(false)
        end
    end
    
    -- 2. Create Selection Background Primitives (Pool)
    for i = 1, pool_size do
        local sel_name = 'chatter_sel_bg_' .. i
        local prim = AshitaCore:GetPrimitiveManager():Create(sel_name)
        prim:SetColor(0x800078D7) -- Semi-transparent Blue
        prim:SetPositionX(0)
        prim:SetPositionY(0)
        prim:SetWidth(0)
        prim:SetHeight(0)
        prim:SetLocked(true)
        prim:SetCanFocus(false)
        prim:SetVisible(false)
        -- Ensure selection is above background but below text (if possible, though font manager usually renders last)
        -- Ashita's PrimitiveManager usually renders in creation order unless z-ordering is manually managed?
        -- Actually, Font objects are managed by FontManager which renders separately.
        -- Primitives are rendered by PrimitiveManager.
        -- Usually Primitives are rendered before Fonts.
        -- If selection background is not showing, it might be behind the main background window?
        -- Let's ensure Z-order by recreating if needed or just assuming order.
        -- Actually, the issue might be that we created the BG *before* the selection, so BG is drawn first (bottom), then Selection (top).
        -- Wait, if BG is drawn first, then Selection is drawn on top of BG. That is correct.
        -- However, if the user says "not seeing the background", maybe the alpha blending is wrong or it's being culled?
        -- Or maybe the text is drawing OVER it (which is good) but the color is too faint?
        -- Let's try to increase opacity slightly or check if it's being drawn at all.
        -- Another possibility: Texture BG might be drawing over selection if we re-set texture?
        -- No, we created bg_tex_primitive BEFORE selection_prims. So selection_prims should be ON TOP of bg_tex_primitive.
        
        -- Let's try setting a higher alpha to be sure.
        prim:SetColor(0xC00078D7) -- More opaque Blue
        
        table.insert(selection_prims, prim)
    end
    
    for i = 1, pool_size do
        local font_settings = {
            box_height = 0,
            box_width = 0,
            font_alignment = gdi.Alignment.Left,
            font_color = 0xFFFFFFFF,
            font_family = 'Arial',
            font_flags = gdi.FontFlags.Bold,
            font_height = font_height,
            gradient_color = 0x00000000,
            gradient_style = 0,
            opacity = 1,
            outline_color = outline_colors.on,
            outline_width = 1,
            position_x = 0,
            position_y = 0,
            text = '',
            visible = false,
            z_order = 0,
        }
        local font = gdi:create_object(font_settings, false)
        table.insert(font_pool, CachedFont.new(font))
    end
    
    local measure_settings = {
        box_height = 0,
        box_width = 0,
        font_alignment = gdi.Alignment.Left,
        font_color = 0xFFFFFFFF,
        font_family = 'Arial',
        font_flags = gdi.FontFlags.Bold,
        font_height = font_height,
        gradient_color = 0x00000000,
        gradient_style = 0,
        opacity = 1,
        outline_color = outline_colors.on,
        outline_width = 1,
        position_x = 0,
        position_y = 0,
        text = '',
        visible = false,
        z_order = 0,
    }
    measure_font = CachedFont.new(gdi:create_object(measure_settings, false))
    
    -- 4. Register Render Loop (Only for textured background & logic updates)
    ashita.events.register('d3d_present', 'chatter_renderer_present', renderer.on_present)
    
    print('[Chatter] Renderer initialized with gdifonts.')
end

function renderer.set_theme(theme_name)
    current_theme = theme_name or 'Plain'

    if current_theme == '-None-' then
        if bg_primitive then bg_primitive:SetVisible(false) end
        if bg_tex_primitive then bg_tex_primitive:SetVisible(false) end
        for _, prim in pairs(border_prims) do
            if prim then
                prim:SetVisible(false)
            end
        end
        return
    end

    if current_theme == 'Plain' then
        if bg_primitive then
            bg_primitive:SetColor(background_color)
            bg_primitive:SetVisible(true)
        end
        if bg_tex_primitive then
            bg_tex_primitive:SetVisible(false)
        end
        for _, prim in pairs(border_prims) do
            if prim then
                prim:SetVisible(false)
            end
        end
    else
        -- local xiui_path = get_xiui_addon_path() -- Deprecated
        local tex_path = string.format('%sassets\\backgrounds\\%s-bg.png', addon_path_cache, current_theme)
        if bg_tex_primitive then
            bg_tex_primitive:SetTextureFromFile(tex_path)
            bg_tex_primitive:SetColor(0xFFFFFFFF)
            bg_tex_primitive:SetVisible(true)
        end
        if bg_primitive then
            bg_primitive:SetVisible(false)
        end

        local keys = { tl = 'tl', tr = 'tr', bl = 'bl', br = 'br' }
        for key, suffix in pairs(keys) do
            local prim = border_prims[key]
            if prim then
                local border_path = string.format('%sassets\\backgrounds\\%s-%s.png', addon_path_cache, current_theme, suffix)
                prim:SetTextureFromFile(border_path)
            end
        end
    end

    update_background_geometry()
end

function renderer.update_geometry(x, y, w, h)
    local width_changed = (math.abs(window_rect.w - w) > 1)
    local height_changed = (math.abs(window_rect.h - h) > 1)
    local pos_changed =
        (math.abs(window_rect.x - x) > 0.5) or
        (math.abs(window_rect.y - y) > 0.5)

    if width_changed then
        window_rect.w = w
        window_rect.h = h
        is_layout_dirty = true
    end

    if pos_changed or height_changed then
        window_rect.x = x
        window_rect.y = y
        window_rect.h = h
        is_render_dirty = true
    end

    update_background_geometry()
end

function renderer.set_resizing(flag)
    if flag then
        is_resizing = true
    else
        is_resizing = false
        is_layout_dirty = true
    end
end

function renderer.set_background_color(color)
    if not color then
        return
    end
    background_color = color
    if bg_primitive then
        bg_primitive:SetColor(background_color)
    end
end

function renderer.set_border_color(color)
    if not color then
        return
    end
    border_color = color
    for _, prim in pairs(border_prims) do
        if prim then
            prim:SetColor(border_color)
        end
    end
end

function renderer.get_content_height()
    return math.max(1, total_visual_lines * (font_height + LINE_SPACING))
end

function renderer.get_window_rect()
    return window_rect.x, window_rect.y, window_rect.w, window_rect.h
end

function renderer.get_page_size()
    return math.floor((window_rect.h - (PADDING * 2)) / (font_height + LINE_SPACING))
end

function renderer.get_visible_line_count()
    local page_size = renderer.get_page_size()
    return math.min(pool_size, page_size)
end

function renderer.get_view_line(view_index)
    local page_size = renderer.get_page_size()
    local visible_count = math.min(pool_size, page_size)
    if total_visual_lines == 0 then
        return nil
    end
    if view_index < 1 or view_index > visible_count then
        return nil
    end
    local end_index = total_visual_lines - scroll_offset
    if end_index < 1 then
        end_index = 1
    end
    local start_index = end_index - visible_count + 1
    if start_index < 1 then
        start_index = 1
    end
    local visual_index = start_index + view_index - 1
    local layout = layout_lines[visual_index]
    if not layout then
        return nil
    end
    return layout.line_index, layout.start_char, layout.end_char
end

function renderer.set_selection(start_abs, end_abs)
    selection_start_abs = start_abs
    selection_end_abs = end_abs
    is_render_dirty = true
end

function renderer.update_scroll(delta)
    scroll_offset = scroll_offset + delta
    if scroll_offset < 0 then scroll_offset = 0 end
    
    local page_size = renderer.get_page_size()
    local max_scroll = 0
    if total_visual_lines > page_size then
        max_scroll = total_visual_lines - page_size
    end
    if scroll_offset > max_scroll then scroll_offset = max_scroll end
    
    is_render_dirty = true
end

local function measure_text(text)
    if not text or text == "" then
        return 0
    end
    if measurement_cache[text] then
        return measurement_cache[text]
    end
    if not measure_font then
        return 0
    end
    measure_font:set_text(text)
    local w, h = measure_font:get_text_size()
    if not w then
        return 0
    end
    measurement_cache[text] = w
    return w
end

local function compute_wrap_length(text, max_width)
    if not text or text == "" then
        return 0
    end
    if max_width <= 0 then
        return #text
    end
    local len = #text
    local low = 1
    local high = len
    local best = len
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local chunk = text:sub(1, mid)
        local w = measure_text(chunk)
        if w > max_width then
            best = mid - 1
            high = mid - 1
        else
            low = mid + 1
        end
    end
    if best < 1 then
        best = 1
    end
    if best >= len then
        return len
    end
    local last_space = 0
    for i = 1, best do
        local c = text:sub(i, i)
        if c == ' ' or c == '\t' then
            last_space = i
        end
    end
    if last_space > 0 then
        return last_space
    end
    return best
end

local MAX_PAGE_MULTIPLIER = 4
local max_source_lines = 50

function renderer.set_layout_history_lines(n)
    if type(n) ~= 'number' then
        return
    end
    if n < 10 then
        n = 10
    end
    if n > chat_manager.max_lines then
        n = chat_manager.max_lines
    end
    max_source_lines = math.floor(n + 0.5)
    is_layout_dirty = true
end

local function append_layout_for_range(start_idx, end_idx)
    local lines = chat_manager.lines
    local max_text_width = window_rect.w - (PADDING * 2)
    if max_text_width <= 0 then
        max_text_width = 1
    end

    for idx = start_idx, end_idx do
        local line = lines[idx]
        local text = line and line.text or ""
        local len = #text
        if len == 0 then
            table.insert(layout_lines, {
                line_index = idx,
                start_char = 1,
                end_char = 0,
            })
        else
            local pos = 1
            while pos <= len do
                local remaining = text:sub(pos)
                local slice_len = compute_wrap_length(remaining, max_text_width)
                if slice_len <= 0 then
                    slice_len = len - pos + 1
                end
                local start_char = pos
                local end_char = pos + slice_len - 1
                table.insert(layout_lines, {
                    line_index = idx,
                    start_char = start_char,
                    end_char = end_char,
                })
                pos = end_char + 1
            end
        end
    end
    total_visual_lines = #layout_lines
end

local function rebuild_layout()
    layout_lines = {}
    local count = #chat_manager.lines
    if count > 0 then
        local max_source = max_source_lines
        if max_source > count then
            max_source = count
        end
        local start_idx = count - max_source + 1
        if start_idx < 1 then
            start_idx = 1
        end
        append_layout_for_range(start_idx, count)
    else
        total_visual_lines = 0
    end
end

function renderer.update_style(family, size, bold, italic, outline_enabled, outline_argb)
    measurement_cache = {}
    font_height = size
    if bold == nil then bold = true end
    if italic == nil then italic = false end
    if outline_argb ~= nil then
        outline_colors.on = outline_argb
    end
    local outline_color = outline_colors.off
    if outline_enabled then
        outline_color = outline_colors.on
    end
    local flags = gdi.FontFlags.None
    if bold then
        flags = bit.bor(flags, gdi.FontFlags.Bold)
    end
    if italic then
        flags = bit.bor(flags, gdi.FontFlags.Italic)
    end
    
    for _, font in ipairs(font_pool) do
        if font then
            font:set_font_family(family)
            font:set_font_height(size)
            font:set_font_flags(flags)
            font:set_outline_color(outline_color)
        end
    end
    if measure_font then
        measure_font:set_font_family(family)
        measure_font:set_font_height(size)
        measure_font:set_font_flags(flags)
        measure_font:set_outline_color(outline_color)
    end
    -- calibrate_measurement(family, size, bold, italic) -- Deprecated

    is_layout_dirty = true
end

function renderer.set_window_size(w, h)
    -- Deprecated: use update_geometry
end

function renderer.update_fonts()
    local page_size = renderer.get_page_size()
    local visible_count = math.min(pool_size, page_size)
    -- rebuild_layout called separately
    if total_visual_lines == 0 then
        for i = 1, pool_size do
            local font = font_pool[i]
            local sel_prim = selection_prims[i]
            font:set_visible(false)
            if sel_prim then
                sel_prim:SetVisible(false)
            end
        end
        return
    end

    local end_index = total_visual_lines - scroll_offset
    if end_index < 1 then
        end_index = 1
    end
    local start_index = end_index - visible_count + 1
    if start_index < 1 then
        start_index = 1
    end

    local start_x = window_rect.x + PADDING
    local start_y = window_rect.y + PADDING
    local max_text_width = window_rect.w - (PADDING * 2)
    local sel_start_line = nil
    local sel_start_char = nil
    local sel_end_line = nil
    local sel_end_char = nil
    if selection_start_abs and selection_end_abs then
        if selection_start_abs.line > selection_end_abs.line then
            sel_start_line = selection_end_abs.line
            sel_start_char = selection_end_abs.char
            sel_end_line = selection_start_abs.line
            sel_end_char = selection_start_abs.char
        elseif selection_start_abs.line < selection_end_abs.line then
            sel_start_line = selection_start_abs.line
            sel_start_char = selection_start_abs.char
            sel_end_line = selection_end_abs.line
            sel_end_char = selection_end_abs.char
        else
            sel_start_line = selection_start_abs.line
            sel_end_line = selection_start_abs.line
            if selection_start_abs.char > selection_end_abs.char then
                sel_start_char = selection_end_abs.char
                sel_end_char = selection_start_abs.char
            else
                sel_start_char = selection_start_abs.char
                sel_end_char = selection_end_abs.char
            end
        end
    end
    
    for i = 1, pool_size do
        local font = font_pool[i]
        local sel_prim = selection_prims[i]
        if i <= visible_count then
            local visual_index = start_index + i - 1
            local layout = layout_lines[visual_index]
            if layout then
                local line = chat_manager.lines[layout.line_index]
                local full_text = line and line.text or ""
                local segment_text = ""
                if full_text ~= "" and layout.start_char <= #full_text then
                    local seg_end = math.min(layout.end_char, #full_text)
                    segment_text = full_text:sub(layout.start_char, seg_end)
                end
                local color = line and line.color or 0xFFFFFFFF
                local is_selected = false
                local sel_x_start = 0
                local sel_x_width = 0

                if sel_start_line and sel_end_line and segment_text ~= "" then
                    local line_index = layout.line_index
                    local seg_start = layout.start_char
                    local seg_end = layout.end_char
                    if seg_end > #full_text then
                        seg_end = #full_text
                    end
                    if seg_start <= seg_end then
                        if line_index >= sel_start_line and line_index <= sel_end_line then
                            local sel_seg_start = seg_start
                            local sel_seg_end = seg_end
                            if line_index == sel_start_line then
                                if sel_start_char > sel_seg_start then
                                    sel_seg_start = sel_start_char
                                end
                            end
                            if line_index == sel_end_line then
                                if sel_end_char < sel_seg_end then
                                    sel_seg_end = sel_end_char
                                end
                            end
                            if line_index > sel_start_line and line_index < sel_end_line then
                                sel_seg_start = seg_start
                                sel_seg_end = seg_end
                            end
                            if sel_seg_start <= sel_seg_end then
                                local rel_start = sel_seg_start - seg_start + 1
                                local rel_end = sel_seg_end - seg_start + 1
                                if rel_start < 1 then
                                    rel_start = 1
                                end
                                if rel_end > #segment_text then
                                    rel_end = #segment_text
                                end
                                if rel_start <= rel_end then
                                    local text_before = segment_text:sub(1, rel_start - 1)
                                    local text_incl = segment_text:sub(1, rel_end)
                                    sel_x_start = measure_text(text_before)
                                    sel_x_width = measure_text(text_incl) - sel_x_start
                                    if sel_x_width <= 0 then
                                        sel_x_width = measure_text(segment_text)
                                    end
                                    is_selected = true
                                end
                            end
                        end
                    end
                end

                if is_selected then
                    color = 0xFFFFFFFF
                    if sel_prim then
                        sel_prim:SetPositionX(start_x + sel_x_start)
                        sel_prim:SetPositionY(start_y + (i-1) * (font_height + LINE_SPACING) + 2)
                        sel_prim:SetWidth(sel_x_width)
                        sel_prim:SetHeight(font_height + 1)
                        sel_prim:SetVisible(true)
                    end
                else
                    if sel_prim then
                        sel_prim:SetVisible(false)
                    end
                end

                font:set_text(segment_text)
                font:set_font_color(color)
                font:set_position_x(start_x)
                font:set_position_y(start_y + (i-1) * (font_height + LINE_SPACING))
                font:set_visible(true)
            else
                font:set_visible(false)
                if sel_prim then sel_prim:SetVisible(false) end
            end
        else
            font:set_visible(false)
            if sel_prim then sel_prim:SetVisible(false) end
        end
    end
    
    -- is_dirty handled by caller
end

function renderer.get_char_index_from_x(text, rel_x)
    if not text or text == "" then return 1 end
    
    local len = #text
    if rel_x <= 0 then
        return 1
    end
    local total_w = measure_text(text)
    if rel_x >= total_w then
        return len
    end

    local low = 1
    local high = len
    local best = len
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local w = measure_text(text:sub(1, mid))
        if rel_x < w then
            best = mid
            high = mid - 1
        else
            low = mid + 1
        end
    end
    return best
end

function renderer.get_word_boundaries(text, char_index)
    if not text or text == "" then return 1, 1 end
    local len = #text
    if char_index < 1 then char_index = 1 end
    if char_index > len then char_index = len end
    
    -- Check if we are on a separator
    local function is_separator(c)
        return c:match("[%s%p]") -- whitespace or punctuation
    end
    
    local start_idx = char_index
    local end_idx = char_index
    
    -- If we clicked on a separator, just select that separator (or word before/after?)
    -- User wants word highlighting. Usually selecting a space selects just the space or the word before.
    -- Let's try to expand to the word.
    
    local char_at = text:sub(char_index, char_index)
    if is_separator(char_at) then
        -- If on separator, maybe just select the separator? 
        -- Or try to find the word if it's close?
        -- Let's stick to: expand until separator.
        -- If we are on a separator, the "word" is that sequence of separators.
        while start_idx > 1 and is_separator(text:sub(start_idx - 1, start_idx - 1)) do
            start_idx = start_idx - 1
        end
        while end_idx < len and is_separator(text:sub(end_idx + 1, end_idx + 1)) do
            end_idx = end_idx + 1
        end
    else
        -- Expand alphanumeric
        while start_idx > 1 and not is_separator(text:sub(start_idx - 1, start_idx - 1)) do
            start_idx = start_idx - 1
        end
        while end_idx < len and not is_separator(text:sub(end_idx + 1, end_idx + 1)) do
            end_idx = end_idx + 1
        end
    end
    
    return start_idx, end_idx
end

local last_line_count = 0

function renderer.on_present()
    local current_count = chat_manager.get_line_count()
    if current_count ~= last_line_count then
        local previous_count = last_line_count
        last_line_count = current_count

        if current_count == 0 then
            layout_lines = {}
            total_visual_lines = 0
            scroll_offset = 0
            is_render_dirty = true
        elseif current_count > previous_count and previous_count > 0 and (not is_layout_dirty) and (current_count <= (chat_manager.max_lines or current_count)) then
            append_layout_for_range(previous_count + 1, current_count)
            is_render_dirty = true
        else
            is_layout_dirty = true
        end
    end

    if is_layout_dirty then
        rebuild_layout()
        is_render_dirty = true
        is_layout_dirty = false
    end

    if is_render_dirty then
        renderer.update_fonts()
        is_render_dirty = false
    end
end

function renderer.dispose()
    for i, font in ipairs(font_pool) do
        if font ~= nil then
            font:set_visible(false)
            if font.font then
                gdi:destroy_object(font.font)
            end
            font_pool[i] = nil
        end
    end
    if measure_font then
        if measure_font.font then
            gdi:destroy_object(measure_font.font)
        end
        measure_font = nil
    end

    local pm = AshitaCore:GetPrimitiveManager()
    if pm then
        if bg_primitive then
            pm:Delete('chatter_bg_rect')
            bg_primitive = nil
        end

        if bg_tex_primitive then
            pm:Delete('chatter_bg_tex')
            bg_tex_primitive = nil
        end

        for key, prim in pairs(border_prims) do
            if prim then
                pm:Delete('chatter_border_' .. key)
                border_prims[key] = nil
            end
        end

        if selection_prims then
            for i, prim in ipairs(selection_prims) do
                if prim then
                    pm:Delete('chatter_sel_bg_' .. i)
                    selection_prims[i] = nil
                end
            end
        end
    end

    gdi:destroy_interface()
end

return renderer
