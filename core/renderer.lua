local renderer = {}
require('common')
local d3d = require('d3d8')
local ffi = require('ffi')
local chatmanager = require('core.chatmanager')
local gdi = require('submodules.gdifonts.include')
local spritebackground = require('core.spritebackground')
local bit = require('bit')

-- Localize global functions for performance
local math_floor = math.floor
local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local string_sub = string.sub
local string_format = string.format
local string_byte = string.byte
local table_insert = table.insert
local table_remove = table.remove
local bit_band = bit.band
local bit_bor = bit.bor
local bit_lshift = bit.lshift
local bit_rshift = bit.rshift

local measurement_cache = {}

local CachedFont = {}
CachedFont.__index = CachedFont

function CachedFont.new(font_obj)
    local self = setmetatable({}, CachedFont)
    self.font = font_obj
    self.current_key = nil
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

function CachedFont:set_z_order(z_order)
    self.font:set_z_order(z_order)
end

function CachedFont:get_text_size()
    return self.font:get_text_size()
end

function CachedFont:get_font_height()
    return self.cache.height or self.font:get_font_height()
end

local font_pool = {}
local font_cache = {}
local pool_size = 50
local font_height = 14

-- Layout Store (SoA)
local layout_store = {
    line_index = {},
    start_char = {},
    end_char = {},
    key = {},
    segment_text = {}
}

-- Reusable buffers to avoid GC
local layout_buffer = {
    line_index = {},
    start_char = {},
    end_char = {},
    key = {},
    segment_text = {}
}
local line_segments_buffer = {
    start_char = {},
    end_char = {}
}

local assignments = {}
local available_fonts = {}
local visible_slot_line = {}
local visible_slot_start = {}
local visible_slot_end = {}
local visible_slot_key = {}
local free_list = {}
local last_visible_count = 0
local background_dirty = true
local assets_loaded = false
local layout_task = nil
local layout_rebuild_mode = 'immediate'
local layout_lines_per_frame = 8
local last_layout_time = 0
local LAYOUT_THROTTLE_DELAY = 0.05
local layout_use_task = false
local begin_layout_task
local MAX_LINES_PER_FRAME = 64
local MIN_LINES_PER_FRAME = 4
local TARGET_LAYOUT_BUDGET_SEC = 0.004
local STYLE_UPDATES_PER_FRAME = 8
local style_updates_pending = false
local fonts_to_style = {}
local pending_style = { family = nil, size = nil, flags = nil, outline_color = nil }

local total_visual_lines = 0
local window_rect = { x = 100, y = 100, w = 600, h = 400 }
local geometry_ready = false
local scroll_offset = 0
local is_resizing = false
local is_layout_dirty = true
local is_render_dirty = true
local selection_start_abs = nil
local selection_end_abs = nil
local measure_font = nil
local loading_font = nil

local selection_rects = {}
local addon_path_cache = ''

local bg_sprite = nil
local bg_texture = nil
local spritebg = nil
local main_bg_handle = nil
local context_bg_handle = nil
local current_background_asset = 'Progressive-Blue'
local current_border_asset = 'Whispered-Veil'
local background_color = 0xC0000000
local border_color = 0xFFFFFFFF
local background_scale = 1.0
local border_scale = 1.0
local background_opacity = 1.0
local border_opacity = 1.0
local background_base_w = 0
local background_base_h = 0
local background_draw = { x = 0, y = 0, w = 0, h = 0 }
local background_theme = nil
local context_menu_visible = false
local context_menu_x = 0
local context_menu_y = 0
local context_menu_w = 0
local context_menu_h = 0
local context_menu_padding = 8
local context_menu_item_spacing = 4
local context_menu_items = { 'Copy Text', 'Send Tell', 'Configuration' }
local context_menu_fonts = {}
local context_menu_bg_rect = nil
local context_menu_bg_texture = nil
local context_menu_background_draw = { x = 0, y = 0, w = 0, h = 0 }
local context_menu_background_asset = 'Progressive-Blue'
local context_menu_border_asset = 'Whispered-Veil'
local context_menu_theme_cache = nil
local update_context_menu_layout

local PADDING_X = 0
local PADDING_Y = 0
local LINE_SPACING = 2
local outline_colors = {
    off = 0x00000000,
    on = 0xFF000000,
}

local BORDER_PADDING = 8
local BORDER_SIZE = 16
local BORDER_OFFSET = 1
local BORDER_SCALE = 1.0

pcall(function()
    ffi.cdef[[
        typedef long HRESULT;
        typedef struct IDirect3DDevice8 IDirect3DDevice8;
        typedef struct IDirect3DTexture8 IDirect3DTexture8;
        typedef struct _D3DXIMAGE_INFO {
            uint32_t Width;
            uint32_t Height;
            uint32_t Depth;
            uint32_t MipLevels;
            uint32_t Format;
            uint32_t ResourceType;
            uint32_t ImageFileFormat;
        } D3DXIMAGE_INFO;
        HRESULT D3DXCreateTextureFromFileExA(
            IDirect3DDevice8* pDevice,
            const char* pSrcFile,
            uint32_t Width,
            uint32_t Height,
            uint32_t MipLevels,
            uint32_t Usage,
            uint32_t Format,
            uint32_t Pool,
            uint32_t Filter,
            uint32_t MipFilter,
            uint32_t ColorKey,
            D3DXIMAGE_INFO* pSrcInfo,
            void* pPalette,
            IDirect3DTexture8** ppTexture
        );
    ]]
end)

local D3DX_DEFAULT = 0xFFFFFFFF
local D3DPOOL_MANAGED = 1
local D3DXSPRITE_ALPHABLEND = 0x00000002
local texture_cache = {}
local bg_vec_position = ffi.new('D3DXVECTOR2', { 0, 0 })
local bg_vec_scale = ffi.new('D3DXVECTOR2', { 1.0, 1.0 })

local function ensure_bg_sprite()
    if bg_sprite then
        return
    end
    local sprite_ptr = ffi.new('ID3DXSprite*[1]')
    if ffi.C.D3DXCreateSprite(d3d.get_device(), sprite_ptr) == ffi.C.S_OK then
        bg_sprite = d3d.gc_safe_release(ffi.cast('ID3DXSprite*', sprite_ptr[0]))
    end
end

local function load_texture(path)
    if not path or path == '' then
        return nil
    end
    local device = d3d.get_device()
    if not device then
        return nil
    end
    local info = ffi.new('D3DXIMAGE_INFO[1]')
    local tex_ptr = ffi.new('IDirect3DTexture8*[1]')
    local hr = ffi.C.D3DXCreateTextureFromFileExA(
        device,
        path,
        D3DX_DEFAULT,
        D3DX_DEFAULT,
        1,
        0,
        0,
        D3DPOOL_MANAGED,
        D3DX_DEFAULT,
        D3DX_DEFAULT,
        0,
        info,
        nil,
        tex_ptr
    )
    if hr ~= 0 or tex_ptr[0] == nil then
        return nil
    end
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', tex_ptr[0]))
    local tex_id = tonumber(ffi.cast('uintptr_t', texture)) or 0
    local rect = ffi.new('RECT', { 0, 0, info[0].Width, info[0].Height })
    return {
        texture = texture,
        tex_id = tex_id,
        width = info[0].Width,
        height = info[0].Height,
        rect = rect,
    }
end

local function draw_texture(texture_info, x, y, w, h, color)
    if not texture_info or not texture_info.texture then
        return
    end
    if w <= 0 or h <= 0 then
        return
    end
    local tex_w = texture_info.width
    local tex_h = texture_info.height
    if tex_w <= 0 or tex_h <= 0 then
        return
    end
    bg_vec_position.x = x
    bg_vec_position.y = y
    bg_vec_scale.x = w / tex_w
    bg_vec_scale.y = h / tex_h
    bg_sprite:Draw(texture_info.texture, texture_info.rect, bg_vec_scale, nil, 0.0, bg_vec_position, color or 0xFFFFFFFF)
end

function renderer.get_texture(path)
    if not path or path == '' then
        return nil
    end
    local cached = texture_cache[path]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    local tex = load_texture(path)
    if tex == nil then
        texture_cache[path] = false
        return nil
    end
    texture_cache[path] = tex
    return tex
end

local function apply_opacity(color, opacity)
    if opacity == nil then
        return color
    end
    if opacity < 0 then
        opacity = 0
    elseif opacity > 1 then
        opacity = 1
    end
    local alpha = bit_rshift(color, 24)
    local new_alpha = math_floor((alpha * opacity) + 0.5)
    return bit_bor(bit_lshift(new_alpha, 24), bit_band(color, 0x00FFFFFF))
end

local function refresh_background_base_size()
    if spritebg and main_bg_handle and main_bg_handle.bg_texture then
        background_base_w = main_bg_handle.bg_texture.width or window_rect.w
        background_base_h = main_bg_handle.bg_texture.height or window_rect.h
        return
    end
    background_base_w = window_rect.w
    background_base_h = window_rect.h
end

local function update_background_geometry()
    if not spritebg or not main_bg_handle then
        return
    end
    spritebg:set_scale(main_bg_handle, background_scale, border_scale)
    spritebg:set_background_color(main_bg_handle, background_color)
    spritebg:set_border_color(main_bg_handle, border_color)
    spritebg:set_background_opacity(main_bg_handle, background_opacity)
    spritebg:set_border_opacity(main_bg_handle, border_opacity)
    spritebg:update_geometry(
        main_bg_handle,
        window_rect.x,
        window_rect.y,
        window_rect.w,
        window_rect.h,
        {
            bg_asset = current_background_asset,
            border_asset = current_border_asset,
            padding = 0,
            border_size = BORDER_SIZE,
            border_offset = BORDER_OFFSET,
            bg_scale = background_scale,
            border_scale = border_scale,
        }
    )
end

local function update_context_menu_background_geometry()
    if not spritebg or not context_bg_handle then
        return
    end
    spritebg:set_scale(context_bg_handle, background_scale, border_scale)
    spritebg:set_background_color(context_bg_handle, background_color)
    spritebg:set_border_color(context_bg_handle, border_color)
    spritebg:set_background_opacity(context_bg_handle, background_opacity)
    spritebg:set_border_opacity(context_bg_handle, border_opacity)
    spritebg:update_geometry(
        context_bg_handle,
        context_menu_x,
        context_menu_y,
        context_menu_w,
        context_menu_h,
        {
            bg_asset = context_menu_background_asset,
            border_asset = context_menu_border_asset,
            padding = 0,
            border_size = BORDER_SIZE,
            border_offset = BORDER_OFFSET,
            bg_scale = background_scale,
            border_scale = border_scale,
        }
    )
end

local function get_xiui_addon_path()
    local lower = addon_path_cache:lower()
    local idx = lower:find('\\chatter\\', 1, true) or lower:find('/chatter/', 1, true)
    if idx then
        return addon_path_cache:sub(1, idx) .. 'XIUI\\'
    end
    return addon_path_cache
end

local function load_theme_texture(theme_name, suffix)
    local path = string_format('%sassets\\backgrounds\\%s-%s.png', addon_path_cache, theme_name, suffix)
    local texture = load_texture(path)
    if texture then
        return texture
    end
    local xiui_path = get_xiui_addon_path()
    if xiui_path ~= addon_path_cache then
        local alt_path = string_format('%sassets\\backgrounds\\%s-%s.png', xiui_path, theme_name, suffix)
        texture = load_texture(alt_path)
    end
    return texture
end

function renderer.initialize(addon_path)
    addon_path_cache = addon_path
    assets_loaded = false
    
    -- Force cleanup of potential stale objects from previous crashes
    local pm = AshitaCore:GetPrimitiveManager()
    if pm then
        pm:Delete('chatter_bg_rect')
        pm:Delete('chatter_border_tl')
        pm:Delete('chatter_border_tr')
        pm:Delete('chatter_border_bl')
        pm:Delete('chatter_border_br')
        for i = 1, pool_size do
            pm:Delete('chatter_sel_bg_' .. i)
        end
    end
    
    local fm = AshitaCore:GetFontManager()
    if fm then
        for i = 1, pool_size do
            fm:Delete('chatter_font_' .. i)
        end
        fm:Delete('chatter_font_measure')
    end

    ensure_bg_sprite()
    gdi:set_auto_render(false)

    spritebg = spritebackground.new(addon_path_cache)
    main_bg_handle = spritebg:create_handle(current_background_asset, current_border_asset, background_scale, border_scale)
    context_bg_handle = spritebg:create_handle(context_menu_background_asset, context_menu_border_asset, background_scale, border_scale)
    
    for i = 1, pool_size do
        local sel_settings = {
            width = 0,
            height = 0,
            outline_width = 0,
            fill_color = 0xC00078D7,
            position_x = 0,
            position_y = 0,
            visible = false,
            z_order = 1,
        }
        local rect = gdi:create_rect(sel_settings, false)
        table.insert(selection_rects, rect)
    end

    update_background_geometry()
    background_dirty = false
    
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
            z_order = 2,
        }
        local font = gdi:create_object(font_settings, false)
        table.insert(font_pool, CachedFont.new(font))
    end

    for i = 1, #context_menu_items do
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
            z_order = 6,
        }
        local font = gdi:create_object(font_settings, false)
        context_menu_fonts[i] = CachedFont.new(font)
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

    local loading_settings = {
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
        z_order = 3,
    }
    loading_font = CachedFont.new(gdi:create_object(loading_settings, false))
    
    -- 4. Register Render Loop (Only for textured background & logic updates)
    ashita.events.register('d3d_present', 'chatter_renderer_present', renderer.on_present)
    
    print('[Chatter] Renderer initialized with gdifonts.')
end

function renderer.set_background_asset(asset_name)
    current_background_asset = asset_name or 'Plain'
    background_dirty = true
    assets_loaded = false
    context_menu_background_asset = current_background_asset

    if spritebg and main_bg_handle then
        spritebg:set_background_asset(main_bg_handle, current_background_asset)
    end
    if spritebg and context_bg_handle then
        spritebg:set_background_asset(context_bg_handle, context_menu_background_asset)
    end
    update_context_menu_layout()

    if background_dirty then
        update_background_geometry()
        background_dirty = false
    end
end

function renderer.set_border_asset(asset_name)
    current_border_asset = asset_name
    background_dirty = true
    assets_loaded = false
    context_menu_border_asset = current_border_asset

    if spritebg and main_bg_handle then
        spritebg:set_border_asset(main_bg_handle, current_border_asset)
    end
    if spritebg and context_bg_handle then
        spritebg:set_border_asset(context_bg_handle, context_menu_border_asset)
    end
    update_context_menu_layout()

    if background_dirty then
        update_background_geometry()
        background_dirty = false
    end
end

function renderer.set_context_menu_background_asset(asset_name)
    context_menu_background_asset = asset_name or 'Plain'
    if spritebg and context_bg_handle then
        spritebg:set_background_asset(context_bg_handle, context_menu_background_asset)
    end
    update_context_menu_layout()
end

function renderer.set_context_menu_border_asset(asset_name)
    context_menu_border_asset = asset_name
    if spritebg and context_bg_handle then
        spritebg:set_border_asset(context_bg_handle, context_menu_border_asset)
    end
    update_context_menu_layout()
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

    if width_changed or height_changed or pos_changed then
        background_dirty = true
    end
    if background_dirty then
        update_background_geometry()
        background_dirty = false
    end
    if context_menu_visible then
        update_context_menu_layout()
    end
    if is_resizing and width_changed then
        layout_task = nil
        layout_use_task = false
        is_layout_dirty = true
        is_render_dirty = true
    end
end

function renderer.set_resizing(flag)
    if flag then
        is_resizing = true
        layout_task = nil
        layout_use_task = false
        is_layout_dirty = true
    else
        is_resizing = false
        layout_task = nil
        is_layout_dirty = true
    end
end

function renderer.set_background_color(color)
    if not color then
        return
    end
    background_color = color
    if spritebg then
        if main_bg_handle then
            spritebg:set_background_color(main_bg_handle, background_color)
        end
        if context_bg_handle then
            spritebg:set_background_color(context_bg_handle, background_color)
        end
    end
end

function renderer.set_border_color(color)
    if not color then
        return
    end
    border_color = color
    if spritebg then
        if main_bg_handle then
            spritebg:set_border_color(main_bg_handle, border_color)
        end
        if context_bg_handle then
            spritebg:set_border_color(context_bg_handle, border_color)
        end
    end
end

function renderer.set_background_scale(scale)
    if not scale then
        return
    end
    background_scale = scale
    background_dirty = true
    if spritebg and main_bg_handle then
        spritebg:set_scale(main_bg_handle, background_scale, border_scale)
    end
    if spritebg and context_bg_handle then
        spritebg:set_scale(context_bg_handle, background_scale, border_scale)
    end
    update_background_geometry()
end

function renderer.set_border_scale(scale)
    if not scale then
        return
    end
    border_scale = scale
    background_dirty = true
    if spritebg and main_bg_handle then
        spritebg:set_scale(main_bg_handle, background_scale, border_scale)
    end
    if spritebg and context_bg_handle then
        spritebg:set_scale(context_bg_handle, background_scale, border_scale)
    end
    update_background_geometry()
end

function renderer.set_background_opacity(opacity)
    if opacity == nil then
        return
    end
    background_opacity = opacity
    if spritebg then
        if main_bg_handle then
            spritebg:set_background_opacity(main_bg_handle, background_opacity)
        end
        if context_bg_handle then
            spritebg:set_background_opacity(context_bg_handle, background_opacity)
        end
    end
end

function renderer.set_border_opacity(opacity)
    if opacity == nil then
        return
    end
    border_opacity = opacity
    if spritebg then
        if main_bg_handle then
            spritebg:set_border_opacity(main_bg_handle, border_opacity)
        end
        if context_bg_handle then
            spritebg:set_border_opacity(context_bg_handle, border_opacity)
        end
    end
end

function renderer.set_chat_padding(pad_x, pad_y)
    if pad_x ~= nil then
        if pad_x < 0 then pad_x = 0 end
        PADDING_X = pad_x
    end
    if pad_y ~= nil then
        if pad_y < 0 then pad_y = 0 end
        PADDING_Y = pad_y
    end
    is_layout_dirty = true
    is_render_dirty = true
end

function renderer.mark_geometry_ready()
    geometry_ready = true
end

function renderer.is_geometry_ready()
    return geometry_ready
end

local function assets_ready()
    if not spritebg or not main_bg_handle then
        return false
    end
    local bg_ready = true
    if current_background_asset ~= '-None-' then
        bg_ready = (main_bg_handle.bg_texture ~= nil)
    end
    local border_ready = true
    if current_border_asset and current_border_asset ~= '-None-' then
        local borders = main_bg_handle.border_textures
        border_ready = borders and borders.corners and borders.sides
    end
    local fonts_ready = (#font_pool > 0)
    return bg_ready and border_ready and fonts_ready
end

function renderer.is_assets_loaded()
    if not assets_loaded then
        assets_loaded = assets_ready()
    end
    return assets_loaded
end

function renderer.is_render_ready()
    if not renderer.is_assets_loaded() then
        return false
    end
    if style_updates_pending or is_layout_dirty or layout_task ~= nil or layout_use_task then
        return false
    end
    local current_count = chatmanager.get_line_count()
    if current_count > 0 and total_visual_lines == 0 then
        return false
    end
    return true
end

function renderer.show_context_menu(x, y)
    context_menu_visible = true
    context_menu_x = x
    context_menu_y = y
    for i = 1, #context_menu_fonts do
        local font = context_menu_fonts[i]
        if font then
            font:set_z_order(10 + i)
        end
    end
    update_context_menu_layout()
    local max_x = window_rect.x + window_rect.w - context_menu_w
    local max_y = window_rect.y + window_rect.h - context_menu_h
    if context_menu_x > max_x then
        context_menu_x = max_x
    end
    if context_menu_y > max_y then
        context_menu_y = max_y
    end
    if context_menu_x < window_rect.x then
        context_menu_x = window_rect.x
    end
    if context_menu_y < window_rect.y then
        context_menu_y = window_rect.y
    end
    update_context_menu_layout()
end

function renderer.hide_context_menu()
    context_menu_visible = false
    if context_menu_bg_rect then
        context_menu_bg_rect:set_visible(false)
    end
    for i = 1, #context_menu_fonts do
        local font = context_menu_fonts[i]
        if font then
            font:set_visible(false)
        end
    end
end

function renderer.is_context_menu_visible()
    return context_menu_visible
end

function renderer.get_context_menu_item_index(mouse_x, mouse_y)
    if not context_menu_visible then
        return nil
    end
    if mouse_x < context_menu_x or mouse_x > (context_menu_x + context_menu_w) then
        return nil
    end
    if mouse_y < context_menu_y or mouse_y > (context_menu_y + context_menu_h) then
        return nil
    end
    local item_height = font_height + context_menu_item_spacing
    local total_items_height = (#context_menu_items * item_height) - context_menu_item_spacing
    local rel_y = mouse_y - context_menu_y
    if rel_y < context_menu_padding or rel_y > (context_menu_padding + total_items_height) then
        return nil
    end
    local idx = math.floor((rel_y - context_menu_padding) / item_height) + 1
    if idx < 1 or idx > #context_menu_items then
        return nil
    end
    return idx
end

function renderer.get_content_height()
    -- Estimate content height for scrollbar
    return math.max(1, chatmanager.count * (font_height + LINE_SPACING))
end

function renderer.get_window_rect()
    return window_rect.x, window_rect.y, window_rect.w, window_rect.h
end

function renderer.get_page_size()
    return math.floor((window_rect.h - (PADDING_Y * 2)) / (font_height + LINE_SPACING))
end

function renderer.get_visible_line_count()
    local page_size = renderer.get_page_size()
    return math.min(pool_size, page_size)
end

function renderer.get_view_line(view_index)
    if view_index < 1 or view_index > #layout_store.line_index then
        return nil
    end
    return layout_store.line_index[view_index], layout_store.start_char[view_index], layout_store.end_char[view_index]
end

function renderer.set_selection(start_abs, end_abs)
    selection_start_abs = start_abs
    selection_end_abs = end_abs
    is_render_dirty = true
end

function renderer.update_scroll(delta)
    scroll_offset = scroll_offset + delta
    if scroll_offset < 0 then scroll_offset = 0 end
    
    local max_scroll = chatmanager.count
    if max_scroll < 0 then max_scroll = 0 end
    
    if scroll_offset > max_scroll then scroll_offset = max_scroll end
    
    is_layout_dirty = true
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

update_context_menu_layout = function()
    if not context_menu_visible then
        return
    end
    local max_width = 0
    for i = 1, #context_menu_items do
        local w = measure_text(context_menu_items[i])
        if w > max_width then
            max_width = w
        end
    end
    context_menu_w = max_width + (context_menu_padding * 2)
    context_menu_h = (#context_menu_items * (font_height + context_menu_item_spacing)) + (context_menu_padding * 2) - context_menu_item_spacing
    update_context_menu_background_geometry()
    local start_x = context_menu_x + context_menu_padding
    local start_y = context_menu_y + context_menu_padding
    for i = 1, #context_menu_items do
        local font = context_menu_fonts[i]
        if font then
            font:set_text(context_menu_items[i])
            font:set_position_x(start_x)
            font:set_position_y(start_y + (i - 1) * (font_height + context_menu_item_spacing))
            font:set_visible(context_menu_visible)
        end
    end
end

local function compute_wrap_length(text, start_pos, max_width)
    if not text or text == "" then
        return 0
    end
    
    local len = #text
    if start_pos > len then
        return 0
    end
    
    local available = len - start_pos + 1
    if max_width <= 0 then
        return available
    end

    -- Optimization: Check if the rest of the string fits (up to a reasonable limit)
    -- This avoids binary search for short lines (common case) and massive allocs for huge lines.
    local limit = 1000
    local check_len = math_min(available, limit)
    
    -- We must measure the chunk to know if it fits.
    local check_chunk = string_sub(text, start_pos, start_pos + check_len - 1)
    local check_w = measure_text(check_chunk)
    
    if check_w <= max_width then
        -- If the checked chunk fits, and it was the whole available text, return it.
        if available <= limit then
            return available
        end
        -- If we have more text than the limit, but the limit chunk fits, 
        -- we can safely return 'limit'. The next iteration will handle the rest.
        return limit
    end

    -- Binary search for the split point within [1, check_len]
    local low = 1
    local high = check_len
    local best = 1
    
    while low <= high do
        local mid = math_floor((low + high) / 2)
        local chunk = string_sub(text, start_pos, start_pos + mid - 1)
        local w = measure_text(chunk)
        if w > max_width then
            high = mid - 1
        else
            best = mid
            low = mid + 1
        end
    end
    
    -- Word wrap logic: Backtrack to last space if we are splitting the line
    if best < available then
        for i = best, 1, -1 do
            local b = string.byte(text, start_pos + i - 1)
            if b == 32 or b == 9 then -- space or tab
                return i
            end
        end
    end
    
    return best
end

local MAX_PAGE_MULTIPLIER = 4

local function append_layout_for_range(start_idx, end_idx)
    -- Deprecated in favor of lazy layout
end

local function update_visible_layout()
    local lb_idx = 0
    
    local max_text_width = window_rect.w - (PADDING_X * 2)
    if max_text_width <= 0 then max_text_width = 1 end
    
    local page_size = renderer.get_page_size()
    local visible_count = math.min(pool_size, page_size)
    local layout_limit = math.max(100, page_size * 2)
    if is_resizing then
        layout_limit = math_max(visible_count, page_size)
    end
    
    local anchor_idx = chatmanager.count - math.floor(scroll_offset)
    if anchor_idx > chatmanager.count then anchor_idx = chatmanager.count end
    if anchor_idx < 1 then 
        total_visual_lines = 0
        render_start_index = 1
        for i = 1, #layout_store.line_index do
            layout_store.line_index[i] = nil
            layout_store.start_char[i] = nil
            layout_store.end_char[i] = nil
            layout_store.key[i] = nil
            layout_store.segment_text[i] = nil
        end
        return 
    end
    
    local visual_lines_generated = 0
    local current_idx = anchor_idx
    
    -- Safety limit
    local loop_limit = 200 
    if is_resizing then
        loop_limit = math_max(visible_count, page_size)
    end
    local loops = 0
    
    while current_idx >= 1 and visual_lines_generated < layout_limit and loops < loop_limit do
        local text = chatmanager.get_line_text(current_idx) or ""
        local len = #text
        local line_id = chatmanager.get_line_id(current_idx)
        
        -- Reuse line_segments_buffer
        local seg_count = 0
        
        if len == 0 then
            seg_count = 1
            line_segments_buffer.start_char[1] = 1
            line_segments_buffer.end_char[1] = 0
        else
            local pos = 1
                while pos <= len do
                    local slice_len = compute_wrap_length(text, pos, max_text_width)
                    if slice_len <= 0 then slice_len = len - pos + 1 end
                    
                    seg_count = seg_count + 1
                    line_segments_buffer.start_char[seg_count] = pos
                    line_segments_buffer.end_char[seg_count] = pos + slice_len - 1
                    
                    pos = pos + slice_len
                end
        end
        
        for i = seg_count, 1, -1 do
            lb_idx = lb_idx + 1
            layout_buffer.line_index[lb_idx] = current_idx
            layout_buffer.start_char[lb_idx] = line_segments_buffer.start_char[i]
            layout_buffer.end_char[lb_idx] = line_segments_buffer.end_char[i]
            local s = layout_buffer.start_char[lb_idx]
            local e = layout_buffer.end_char[lb_idx]
            if line_id then
                layout_buffer.key[lb_idx] = line_id .. ':' .. s .. ':' .. e
            else
                layout_buffer.key[lb_idx] = nil
            end
            if text ~= "" and s <= len then
                local ee = math_min(e, len)
                layout_buffer.segment_text[lb_idx] = string_sub(text, s, ee)
            else
                layout_buffer.segment_text[lb_idx] = ""
            end
            visual_lines_generated = visual_lines_generated + 1
        end
        
        current_idx = current_idx - 1
        loops = loops + 1
    end
    
    local store_idx = 0
    for i = lb_idx, 1, -1 do
        store_idx = store_idx + 1
        layout_store.line_index[store_idx] = layout_buffer.line_index[i]
        layout_store.start_char[store_idx] = layout_buffer.start_char[i]
        layout_store.end_char[store_idx] = layout_buffer.end_char[i]
        layout_store.key[store_idx] = layout_buffer.key[i]
        layout_store.segment_text[store_idx] = layout_buffer.segment_text[i]
    end
    
    for i = store_idx + 1, #layout_store.line_index do
        layout_store.line_index[i] = nil
        layout_store.start_char[i] = nil
        layout_store.end_char[i] = nil
        layout_store.key[i] = nil
        layout_store.segment_text[i] = nil
    end
    
    total_visual_lines = store_idx
    
    local visible_count = math.min(pool_size, page_size)
    if total_visual_lines > visible_count then
        render_start_index = total_visual_lines - visible_count + 1
    else
        render_start_index = 1
    end
    background_dirty = true
end

local function rebuild_layout()
    local now = os.clock()
    if not is_resizing and (now - last_layout_time) < LAYOUT_THROTTLE_DELAY then
        return
    end
    update_visible_layout()
    last_layout_time = now
end

function begin_layout_task()
    local max_text_width = window_rect.w - (PADDING_X * 2)
    if max_text_width <= 0 then max_text_width = 1 end
    local page_size = renderer.get_page_size()
    local layout_limit = math.max(100, page_size * 2)
    local anchor_idx = chatmanager.count - math.floor(scroll_offset)
    if anchor_idx > chatmanager.count then anchor_idx = chatmanager.count end
    layout_task = {
        max_text_width = max_text_width,
        layout_limit = layout_limit,
        current_idx = anchor_idx,
        lb_idx = 0,
        visual_lines_generated = 0,
        loops = 0,
        loop_limit = 200
    }
end

local function step_layout_task()
    local task = layout_task
    if not task then return true end
    local lines_processed = 0
    task.max_text_width = math_max(1, window_rect.w - (PADDING_X * 2))
    if task.current_idx < 1 then
        total_visual_lines = 0
        render_start_index = 1
        for i = 1, #layout_store.line_index do
            layout_store.line_index[i] = nil
            layout_store.start_char[i] = nil
            layout_store.end_char[i] = nil
            layout_store.key[i] = nil
            layout_store.segment_text[i] = nil
        end
        layout_task = nil
        is_layout_dirty = false
        background_dirty = true
        return true
    end

    while task.current_idx >= 1
        and task.visual_lines_generated < task.layout_limit
        and task.loops < task.loop_limit
        and lines_processed < layout_lines_per_frame do
        local text = chatmanager.get_line_text(task.current_idx) or ""
        local len = #text
        local line_id = chatmanager.get_line_id(task.current_idx)
        local seg_count = 0

        if len == 0 then
            seg_count = 1
            line_segments_buffer.start_char[1] = 1
            line_segments_buffer.end_char[1] = 0
        else
            local pos = 1
            while pos <= len do
                local slice_len = compute_wrap_length(text, pos, task.max_text_width)
                if slice_len <= 0 then slice_len = len - pos + 1 end
                seg_count = seg_count + 1
                line_segments_buffer.start_char[seg_count] = pos
                line_segments_buffer.end_char[seg_count] = pos + slice_len - 1
                pos = pos + slice_len
            end
        end

        for i = seg_count, 1, -1 do
            task.lb_idx = task.lb_idx + 1
            layout_buffer.line_index[task.lb_idx] = task.current_idx
            layout_buffer.start_char[task.lb_idx] = line_segments_buffer.start_char[i]
            layout_buffer.end_char[task.lb_idx] = line_segments_buffer.end_char[i]
            local s = layout_buffer.start_char[task.lb_idx]
            local e = layout_buffer.end_char[task.lb_idx]
            if line_id then
                layout_buffer.key[task.lb_idx] = line_id .. ':' .. s .. ':' .. e
            else
                layout_buffer.key[task.lb_idx] = nil
            end
            if text ~= "" and s <= len then
                local ee = math_min(e, len)
                layout_buffer.segment_text[task.lb_idx] = string_sub(text, s, ee)
            else
                layout_buffer.segment_text[task.lb_idx] = ""
            end
            task.visual_lines_generated = task.visual_lines_generated + 1
        end

        task.current_idx = task.current_idx - 1
        task.loops = task.loops + 1
        lines_processed = lines_processed + 1
    end

    if task.current_idx < 1
        or task.visual_lines_generated >= task.layout_limit
        or task.loops >= task.loop_limit then
        local store_idx = 0
        for i = task.lb_idx, 1, -1 do
            store_idx = store_idx + 1
            layout_store.line_index[store_idx] = layout_buffer.line_index[i]
            layout_store.start_char[store_idx] = layout_buffer.start_char[i]
            layout_store.end_char[store_idx] = layout_buffer.end_char[i]
            layout_store.key[store_idx] = layout_buffer.key[i]
            layout_store.segment_text[store_idx] = layout_buffer.segment_text[i]
        end
        for i = store_idx + 1, #layout_store.line_index do
            layout_store.line_index[i] = nil
            layout_store.start_char[i] = nil
            layout_store.end_char[i] = nil
            layout_store.key[i] = nil
            layout_store.segment_text[i] = nil
        end
        total_visual_lines = store_idx
        local visible_count = math.min(pool_size, renderer.get_page_size())
        if total_visual_lines > visible_count then
            render_start_index = total_visual_lines - visible_count + 1
        else
            render_start_index = 1
        end
        layout_task = nil
        is_layout_dirty = false
        background_dirty = true
        return true
    end

    return false
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
    pending_style.family = family
    pending_style.size = size
    pending_style.flags = flags
    pending_style.outline_color = outline_color
    local q = 0
    for i = 1, #font_pool do
        local f = font_pool[i]
        if f then
            q = q + 1
            fonts_to_style[q] = f
        end
    end
    for i = 1, #context_menu_fonts do
        local f = context_menu_fonts[i]
        if f then
            q = q + 1
            fonts_to_style[q] = f
        end
    end
    for i = q + 1, #fonts_to_style do
        fonts_to_style[i] = nil
    end
    style_updates_pending = true
    if measure_font then
        measure_font:set_font_family(family)
        measure_font:set_font_height(size)
        measure_font:set_font_flags(flags)
        measure_font:set_outline_color(outline_color)
    end
    if loading_font then
        loading_font:set_font_family(family)
        loading_font:set_font_height(size)
        loading_font:set_font_flags(flags)
        loading_font:set_outline_color(outline_color)
    end
    -- calibrate_measurement(family, size, bold, italic) -- Deprecated

    layout_task = nil
    layout_use_task = true
    is_layout_dirty = true
    if context_menu_visible then
        update_context_menu_layout()
    end
end

function renderer.set_window_size(w, h)
    -- Deprecated: use update_geometry
end

function renderer.update_fonts()
    local page_size = renderer.get_page_size()
    local visible_count = math.min(pool_size, page_size)
    -- rebuild_layout called separately
    if is_layout_dirty and layout_task == nil and not layout_use_task then
        update_visible_layout()
        is_layout_dirty = false
    end
    
    if total_visual_lines == 0 then
        for i = 1, pool_size do
            local font = font_pool[i]
            local sel_rect = selection_rects[i]
            font:set_visible(false)
            if sel_rect then
                sel_rect:set_visible(false)
            end
        end
        return
    end

    -- With virtual layout, we just render everything in layout_store from start
    -- because layout_store ONLY contains what fits on screen (or slightly more)
    
    local start_index = render_start_index
    -- local end_index = math.min(total_visual_lines, visible_count) -- Unused
    
    -- If we have fewer lines than page_size, we might need to adjust start_y 
    -- to stick to bottom?
    -- Standard terminal behavior: if few lines, start from top.
    -- If we want to stick to bottom when < page_size, we add padding.
    -- But our loop generated lines bottom-up.
    -- If we generated 5 lines but page_size is 20:
    -- Buffer has 5 lines. They are lines N-4, N-3, N-2, N-1, N.
    -- We render them at top of screen?
    -- Usually chat starts at bottom.
    -- Let's stick to top for now as it's standard for scrolling up.
    -- Actually, if we are at bottom of history, we usually want them at bottom of screen?
    -- Let's stick to top-down rendering of the buffer.
    
    local start_x = window_rect.x + PADDING_X
    local start_y = window_rect.y + PADDING_Y
    local max_text_width = window_rect.w - (PADDING_X * 2)
    local line_height = font_height + LINE_SPACING
    local visible_lines = math.min(total_visual_lines, visible_count)
    if visible_lines < visible_count then
        start_y = start_y + ((visible_count - visible_lines) * line_height)
    end
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
    
    for k in pairs(available_fonts) do
        available_fonts[k] = nil
    end
    for i = 1, visible_count do
        assignments[i] = nil
        visible_slot_line[i] = nil
        visible_slot_start[i] = nil
        visible_slot_end[i] = nil
        visible_slot_key[i] = nil
    end
    for i = visible_count + 1, last_visible_count do
        assignments[i] = nil
        visible_slot_line[i] = nil
        visible_slot_start[i] = nil
        visible_slot_end[i] = nil
        visible_slot_key[i] = nil
    end
    last_visible_count = visible_count
    
    for i = 1, #font_pool do
        available_fonts[font_pool[i]] = true
    end
    
    -- Pass 1: Identify visible slots and try to match with cache
    -- Note: chatmanager data is a ring buffer, so we must use accessor functions
    -- instead of direct array access.
    
    for i = 1, visible_count do
        local visual_index = start_index + i - 1
        
        -- Bounds check
        if visual_index <= #layout_store.line_index then
            local line_idx = layout_store.line_index[visual_index]
            local start_c = layout_store.start_char[visual_index]
            local end_c = layout_store.end_char[visual_index]
            
            if line_idx then
                local key = layout_store.key[visual_index]
                if not key then
                    local line_id = chatmanager.get_line_id(line_idx)
                    if line_id then
                        key = line_id .. ':' .. start_c .. ':' .. end_c
                    end
                end
                visible_slot_line[i] = line_idx
                visible_slot_start[i] = start_c
                visible_slot_end[i] = end_c
                visible_slot_key[i] = key
                
                if key then
                    local cached = font_cache[key]
                    if cached and available_fonts[cached] then
                        assignments[i] = cached
                        available_fonts[cached] = nil
                    end
                end
            end
        end
    end
    
    -- Pass 2: Assign remaining slots from free pool
    local free_count = 0
    for f, _ in pairs(available_fonts) do
        free_count = free_count + 1
        free_list[free_count] = f
    end
    for i = free_count + 1, #free_list do
        free_list[i] = nil
    end
    local free_idx = 1
    
    for i = 1, visible_count do
        if not assignments[i] and visible_slot_line[i] then
            local font = free_list[free_idx]
            free_idx = free_idx + 1
            if font then
                assignments[i] = font
                
                -- Update cache mapping
                local key = visible_slot_key[i]
                if font.current_key and font.current_key ~= key then
                    font_cache[font.current_key] = nil
                end
                font.current_key = key
                if key then
                    font_cache[key] = font
                end
            end
        end
    end

    -- Pass 3: Render and Selection
    for i = 1, pool_size do
        local font = assignments[i]
        local sel_rect = selection_rects[i]
        
        if i <= visible_count and font and visible_slot_line[i] then
            local line_idx = visible_slot_line[i]
            local start_c = visible_slot_start[i]
            local end_c = visible_slot_end[i]
            local segment_text = layout_store.segment_text[start_index + i - 1] or ""
            local full_text = chatmanager.get_line_text(line_idx) or ""
            local color = chatmanager.get_line_color(line_idx) or 0xFFFFFFFF
            local is_selected = false
            local sel_x_start = 0
            local sel_x_width = 0

            if sel_start_line and sel_end_line and segment_text ~= "" then
                local seg_start = start_c
                local seg_end = end_c
                if seg_end > #full_text then
                    seg_end = #full_text
                end
                if seg_start <= seg_end then
                    if line_idx >= sel_start_line and line_idx <= sel_end_line then
                        local sel_seg_start = seg_start
                        local sel_seg_end = seg_end
                        if line_idx == sel_start_line then
                            if sel_start_char > sel_seg_start then
                                sel_seg_start = sel_start_char
                            end
                        end
                        if line_idx == sel_end_line then
                            if sel_end_char < sel_seg_end then
                                sel_seg_end = sel_end_char
                            end
                        end
                        if line_idx > sel_start_line and line_idx < sel_end_line then
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
                if sel_rect then
                    sel_rect:set_position_x(start_x + sel_x_start)
                    sel_rect:set_position_y(start_y + (i-1) * line_height)
                    sel_rect:set_width(sel_x_width)
                    sel_rect:set_height(line_height)
                    sel_rect:set_visible(true)
                end
            else
                if sel_rect then
                    sel_rect:set_visible(false)
                end
            end

            font:set_text(segment_text)
            font:set_font_color(color)
            font:set_position_x(start_x)
            font:set_position_y(start_y + (i-1) * line_height)
            font:set_visible(true)
        else
            if sel_rect then sel_rect:set_visible(false) end
        end
    end
    
    -- Pass 4: Hide unused fonts
    for k = free_idx, free_count do
        free_list[k]:set_visible(false)
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
    if not geometry_ready then
        return
    end
    local current_count = chatmanager.get_line_count()
    if current_count ~= last_line_count then
        last_line_count = current_count

        if current_count == 0 then
            layout_store.line_index = {}
            layout_store.start_char = {}
            layout_store.end_char = {}
            total_visual_lines = 0
            scroll_offset = 0
            is_render_dirty = true
        else
            is_layout_dirty = true
        end
    end

    if style_updates_pending and pending_style.family ~= nil then
        local applied = 0
        local i = 1
        while i <= #fonts_to_style and applied < STYLE_UPDATES_PER_FRAME do
            local f = fonts_to_style[i]
            if f then
                f:set_font_family(pending_style.family)
                f:set_font_height(pending_style.size)
                f:set_font_flags(pending_style.flags)
                f:set_outline_color(pending_style.outline_color)
            end
            table_remove(fonts_to_style, i)
            applied = applied + 1
        end
        if #fonts_to_style == 0 then
            style_updates_pending = false
        end
        is_render_dirty = true
    end

    if is_resizing then
        if is_layout_dirty then
            rebuild_layout()
            is_render_dirty = true
            is_layout_dirty = false
        end
    else
        if layout_task ~= nil then
            local t0 = os.clock()
            step_layout_task()
            local dt = os.clock() - t0
            if dt > (TARGET_LAYOUT_BUDGET_SEC * 1.5) then
                layout_lines_per_frame = math_max(MIN_LINES_PER_FRAME, math_floor(layout_lines_per_frame * 0.7))
            elseif dt < (TARGET_LAYOUT_BUDGET_SEC * 0.5) then
                layout_lines_per_frame = math_min(MAX_LINES_PER_FRAME, layout_lines_per_frame + 1)
            end
            is_render_dirty = true
        elseif is_layout_dirty then
            if layout_use_task then
                begin_layout_task()
                layout_use_task = false
                is_render_dirty = true
            else
                rebuild_layout()
                is_render_dirty = true
                is_layout_dirty = false
            end
        end
    end

    if is_render_dirty then
        renderer.update_fonts()
        is_render_dirty = false
    end

    if not renderer.is_assets_loaded() then
        return
    end

    if bg_sprite then
        bg_sprite:Begin(D3DXSPRITE_ALPHABLEND)
        if spritebg and main_bg_handle then
            spritebg:draw_background(main_bg_handle, bg_sprite)
        end

        if renderer.is_render_ready() then
            if loading_font then
                loading_font:set_visible(false)
            end

            for i = 1, #selection_rects do
                local rect = selection_rects[i]
                if rect then
                    rect:render(bg_sprite)
                end
            end

            for i = 1, #font_pool do
                local font = font_pool[i]
                if font and font.font then
                    font.font:render(bg_sprite)
                end
            end
            if spritebg and main_bg_handle then
                spritebg:draw_borders(main_bg_handle, bg_sprite)
            end

            if context_menu_visible then
                if spritebg and context_bg_handle then
                    spritebg:draw_background(context_bg_handle, bg_sprite)
                end
                for i = 1, #context_menu_fonts do
                    local font = context_menu_fonts[i]
                    if font and font.font then
                        font.font:render(bg_sprite)
                    end
                end
                if spritebg and context_bg_handle then
                    spritebg:draw_borders(context_bg_handle, bg_sprite)
                end
            end
        else
            if loading_font then
                loading_font:set_text('Loading...')
                loading_font:set_font_color(0xFFFFFFFF)
                local text_w, text_h = loading_font:get_text_size()
                local x = window_rect.x + ((window_rect.w - text_w) * 0.5)
                local y = window_rect.y + ((window_rect.h - text_h) * 0.5)
                loading_font:set_position_x(x)
                loading_font:set_position_y(y)
                loading_font:set_visible(true)
                if loading_font.font then
                    loading_font.font:render(bg_sprite)
                end
            end
            if spritebg and main_bg_handle then
                spritebg:draw_borders(main_bg_handle, bg_sprite)
            end
        end

        bg_sprite:End()
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
    if loading_font then
        loading_font:set_visible(false)
        if loading_font.font then
            gdi:destroy_object(loading_font.font)
        end
        loading_font = nil
    end

    bg_texture = nil
    bg_sprite = nil

    if selection_rects then
        for i, rect in ipairs(selection_rects) do
            if rect then
                gdi:destroy_object(rect)
                selection_rects[i] = nil
            end
        end
    end

    if bg_rect then
        gdi:destroy_object(bg_rect)
        bg_rect = nil
    end
    if context_menu_bg_rect then
        gdi:destroy_object(context_menu_bg_rect)
        context_menu_bg_rect = nil
    end
    for i = 1, #context_menu_fonts do
        local font = context_menu_fonts[i]
        if font and font.font then
            gdi:destroy_object(font.font)
        end
        context_menu_fonts[i] = nil
    end
    context_menu_bg_texture = nil

    gdi:destroy_interface()
end

return renderer
