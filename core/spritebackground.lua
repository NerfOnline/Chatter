local M = {}
require('common')
local d3d = require('d3d8')
local ffi = require('ffi')
local bit = require('bit')

local math_floor = math.floor
local math_ceil = math.ceil
local math_min = math.min
local string_format = string.format
local bit_band = bit.band
local bit_bor = bit.bor
local bit_lshift = bit.lshift
local bit_rshift = bit.rshift

local DEFAULT_PADDING = 8
local DEFAULT_BORDER_SIZE = 16
local DEFAULT_BG_OFFSET = 1
local DEFAULT_BG_SCALE = 1.0
local DEFAULT_BORDER_SCALE = 1.0

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

local function apply_opacity(color, opacity)
    if opacity == nil then
        return color
    end
    if opacity < 0 then
        opacity = 0
    elseif opacity > 1 then
        opacity = 1
    end
    local new_alpha = math_floor((opacity * 255) + 0.5)
    if new_alpha < 0 then
        new_alpha = 0
    elseif new_alpha > 255 then
        new_alpha = 255
    end
    return bit_bor(bit_lshift(new_alpha, 24), bit_band(color, 0x00FFFFFF))
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
    local rect = ffi.new('RECT', { 0, 0, info[0].Width, info[0].Height })
    return {
        texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', tex_ptr[0])),
        width = info[0].Width,
        height = info[0].Height,
        rect = rect,
    }
end

local function normalize_color(color)
    if color < 0 then
        return color + 0x100000000
    end
    return color
end

local function draw_texture(sprite, texture_info, x, y, w, h, color, vec_pos, vec_scale)
    if not sprite or not texture_info or not texture_info.texture then
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
    vec_pos.x = x
    vec_pos.y = y
    vec_scale.x = w / tex_w
    vec_scale.y = h / tex_h
    local draw_color = normalize_color(color or 0xFFFFFFFF)
    sprite:Draw(texture_info.texture, texture_info.rect, vec_scale, nil, 0.0, vec_pos, draw_color)
end

local function draw_texture_scaled(sprite, texture_info, x, y, scale, src_w, src_h, color, vec_pos, vec_scale)
    if not sprite or not texture_info or not texture_info.texture then
        return
    end
    if scale <= 0 then
        return
    end
    local tex_w = texture_info.width
    local tex_h = texture_info.height
    if tex_w <= 0 or tex_h <= 0 then
        return
    end
    src_w = src_w or tex_w
    src_h = src_h or tex_h
    if src_w <= 0 or src_h <= 0 then
        return
    end
    if src_w > tex_w then
        src_w = tex_w
    end
    if src_h > tex_h then
        src_h = tex_h
    end
    vec_pos.x = x
    vec_pos.y = y
    vec_scale.x = scale
    vec_scale.y = scale
    local rect = ffi.new('RECT', { 0, 0, src_w, src_h })
    local draw_color = normalize_color(color or 0xFFFFFFFF)
    sprite:Draw(texture_info.texture, rect, vec_scale, nil, 0.0, vec_pos, draw_color)
end

local function draw_texture_region(sprite, texture_info, x, y, w, h, src_x, src_y, src_w, src_h, color, vec_pos, vec_scale)
    if not sprite or not texture_info or not texture_info.texture then
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
    if src_w <= 0 or src_h <= 0 then
        return
    end
    vec_pos.x = x
    vec_pos.y = y
    vec_scale.x = w / src_w
    vec_scale.y = h / src_h
    local rect = ffi.new('RECT', { src_x, src_y, src_x + src_w, src_y + src_h })
    local draw_color = normalize_color(color or 0xFFFFFFFF)
    sprite:Draw(texture_info.texture, rect, vec_scale, nil, 0.0, vec_pos, draw_color)
end

local function get_xiui_addon_path(addon_path)
    if not addon_path then
        return ''
    end
    local lower = addon_path:lower()
    local idx = lower:find('\\chatter\\', 1, true) or lower:find('/chatter/', 1, true)
    if idx then
        return addon_path:sub(1, idx) .. 'XIUI\\'
    end
    return addon_path
end

local function load_theme_texture(addon_path, theme_name, suffix)
    local path = string_format('%sassets\\backgrounds\\%s-%s.png', addon_path, theme_name, suffix)
    local texture = load_texture(path)
    if texture then
        return texture
    end
    local xiui_path = get_xiui_addon_path(addon_path)
    if xiui_path ~= addon_path then
        local alt_path = string_format('%sassets\\backgrounds\\%s-%s.png', xiui_path, theme_name, suffix)
        texture = load_texture(alt_path)
    end
    return texture
end

local function refresh_background_base_size(handle, width, height)
    if handle.bg_texture then
        handle.background_base_w = handle.bg_texture.width or width
        handle.background_base_h = handle.bg_texture.height or height
        return
    end
    handle.background_base_w = width
    handle.background_base_h = height
end

function M.new(addon_path)
    local self = {
        addon_path = addon_path or '',
        sprite = nil,
        vec_pos = ffi.new('D3DXVECTOR2', { 0, 0 }),
        vec_scale = ffi.new('D3DXVECTOR2', { 1.0, 1.0 }),
    }
    return setmetatable(self, { __index = M })
end

function M:ensure_sprite()
    if self.sprite then
        return self.sprite
    end
    local sprite_ptr = ffi.new('ID3DXSprite*[1]')
    if ffi.C.D3DXCreateSprite(d3d.get_device(), sprite_ptr) == ffi.C.S_OK then
        self.sprite = d3d.gc_safe_release(ffi.cast('ID3DXSprite*', sprite_ptr[0]))
    end
    return self.sprite
end

function M:begin(sprite)
    local use_sprite = sprite or self:ensure_sprite()
    if use_sprite then
        use_sprite:Begin()
    end
    return use_sprite
end

function M:finish(sprite)
    local use_sprite = sprite or self.sprite
    if use_sprite then
        use_sprite:End()
    end
end

function M:create_handle(bg_asset, border_asset, bg_scale, border_scale)
    local handle = {
        bg_asset = bg_asset or 'Plain',
        border_asset = border_asset or nil,
        bg_scale = bg_scale or DEFAULT_BG_SCALE,
        border_scale = border_scale or DEFAULT_BORDER_SCALE,
        background_opacity = 1.0,
        border_opacity = 1.0,
        background_color = 0xFFFFFFFF,
        border_color = 0xFFFFFFFF,
        bg_texture = nil,
        border_textures = { corners = nil, sides = nil },
        background_base_w = 0,
        background_base_h = 0,
        background_draw = { x = 0, y = 0, w = 0, h = 0 },
        border_padding = DEFAULT_PADDING,
        border_size = DEFAULT_BORDER_SIZE,
        border_offset = DEFAULT_BG_OFFSET,
    }
    self:set_background_asset(handle, handle.bg_asset)
    self:set_border_asset(handle, handle.border_asset)
    return handle
end

function M:set_background_asset(handle, bg_asset)
    if not handle then
        return
    end
    handle.bg_asset = bg_asset or 'Plain'
    if handle.bg_asset == '-None-' then
        handle.bg_texture = nil
        return
    end
    handle.bg_texture = load_theme_texture(self.addon_path, handle.bg_asset, 'bg')
end

function M:set_border_asset(handle, border_asset)
    if not handle then
        return
    end
    handle.border_asset = border_asset
    handle.border_textures.corners = nil
    handle.border_textures.sides = nil
    if not border_asset or border_asset == '-None-' then
        return
    end
    handle.border_textures.corners = load_theme_texture(self.addon_path, border_asset, 'corners')
    handle.border_textures.sides = load_theme_texture(self.addon_path, border_asset, 'sides')
end

function M:set_scale(handle, bg_scale, border_scale)
    if not handle then
        return
    end
    if bg_scale then
        handle.bg_scale = bg_scale
    end
    if border_scale then
        handle.border_scale = border_scale
    end
end

function M:set_background_opacity(handle, opacity)
    if not handle then
        return
    end
    handle.background_opacity = opacity
end

function M:set_border_opacity(handle, opacity)
    if not handle then
        return
    end
    handle.border_opacity = opacity
end

function M:set_background_color(handle, color)
    if not handle then
        return
    end
    handle.background_color = color
end

function M:set_border_color(handle, color)
    if not handle then
        return
    end
    handle.border_color = color
end

function M:update_geometry(handle, x, y, width, height, options)
    if not handle then
        return
    end
    options = options or {}
    if options.bg_asset and options.bg_asset ~= handle.bg_asset then
        self:set_background_asset(handle, options.bg_asset)
    end
    if options.border_asset and options.border_asset ~= handle.border_asset then
        self:set_border_asset(handle, options.border_asset)
    end
    local bg_scale = options.bg_scale or handle.bg_scale or DEFAULT_BG_SCALE
    local border_scale = options.border_scale or handle.border_scale or DEFAULT_BORDER_SCALE
    handle.bg_scale = bg_scale
    handle.border_scale = border_scale
    local padding = options.padding or DEFAULT_PADDING
    local border_size = options.border_size or DEFAULT_BORDER_SIZE
    local border_offset = options.border_offset or DEFAULT_BG_OFFSET
    handle.background_base_w = width
    handle.background_base_h = height
    local base_w = handle.background_base_w
    local base_h = handle.background_base_h
    if base_w <= 0 or base_h <= 0 then
        base_w = width
        base_h = height
    end
    local w = base_w + (padding * 2)
    local h = base_h + (padding * 2)
    if bg_scale > 0 then
        w = math_ceil(w / bg_scale) * bg_scale
        h = math_ceil(h / bg_scale) * bg_scale
    end
    handle.background_draw.x = x - padding
    handle.background_draw.y = y - padding
    handle.background_draw.w = w
    handle.background_draw.h = h
    handle.border_padding = padding
    handle.border_size = border_size
    handle.border_offset = border_offset
end

function M:draw_background(handle, sprite)
    if not handle or handle.bg_asset == '-None-' then
        return
    end
    local use_sprite = sprite or self.sprite or self:ensure_sprite()
    if not use_sprite then
        return
    end
    local bg_tint = apply_opacity(handle.background_color, handle.background_opacity)
    if handle.bg_texture then
        local draw = handle.background_draw
        local scale = handle.bg_scale or 1.0
        local tex = handle.bg_texture
        local tex_w = tex.width or 0
        local tex_h = tex.height or 0
        if tex_w > 0 and tex_h > 0 and scale > 0 then
            local tile_w = tex_w * scale
            local tile_h = tex_h * scale
            if tile_w > 0 and tile_h > 0 then
                local end_x = draw.x + draw.w
                local end_y = draw.y + draw.h
                local y = draw.y
                while y < end_y do
                    local remaining_h = end_y - y
                    local src_h = math_min(tex_h, remaining_h / scale)
                    local draw_h = src_h * scale
                    local x = draw.x
                    while x < end_x do
                        local remaining_w = end_x - x
                        local src_w = math_min(tex_w, remaining_w / scale)
                        local draw_w = src_w * scale
                        draw_texture_scaled(use_sprite, tex, x, y, scale, src_w, src_h, bg_tint, self.vec_pos, self.vec_scale)
                        x = x + draw_w
                    end
                    y = y + draw_h
                end
            end
        end
    end
end

function M:draw_borders(handle, sprite)
    if not handle then
        return
    end
    local use_sprite = sprite or self.sprite or self:ensure_sprite()
    if not use_sprite then
        return
    end
    local corners = handle.border_textures.corners
    local sides = handle.border_textures.sides
    if not corners or not sides then
        return
    end
    local border_tint = apply_opacity(handle.border_color, handle.border_opacity)
    local border_size = handle.border_size or DEFAULT_BORDER_SIZE
    local border_scale = handle.border_scale or DEFAULT_BORDER_SCALE
    if border_scale <= 0 then
        return
    end
    local offset = (handle.border_offset or DEFAULT_BG_OFFSET) * border_scale
    local corner_draw = border_size * border_scale
    local bg = handle.background_draw
    local bg_x = bg.x
    local bg_y = bg.y
    local bg_w = bg.w
    local bg_h = bg.h
    local tl_x = bg_x - offset
    local tl_y = bg_y - offset
    local tr_x = bg_x + bg_w - corner_draw + offset
    local tr_y = tl_y
    local bl_x = tl_x
    local bl_y = bg_y + bg_h - corner_draw + offset
    local br_x = tr_x
    local br_y = bl_y
    draw_texture_region(use_sprite, corners, tl_x, tl_y, corner_draw, corner_draw, 0, 0, border_size, border_size, border_tint, self.vec_pos, self.vec_scale)
    draw_texture_region(use_sprite, corners, tr_x, tr_y, corner_draw, corner_draw, border_size, 0, border_size, border_size, border_tint, self.vec_pos, self.vec_scale)
    draw_texture_region(use_sprite, corners, bl_x, bl_y, corner_draw, corner_draw, 0, border_size, border_size, border_size, border_tint, self.vec_pos, self.vec_scale)
    draw_texture_region(use_sprite, corners, br_x, br_y, corner_draw, corner_draw, border_size, border_size, border_size, border_size, border_tint, self.vec_pos, self.vec_scale)
    local top_start_x = tl_x + corner_draw
    local top_end_x = tr_x
    local top_y = tl_y
    local bottom_y = br_y
    local left_x = tl_x
    local right_x = tr_x
    local left_start_y = tl_y + corner_draw
    local left_end_y = bl_y
    local right_start_y = tr_y + corner_draw
    local right_end_y = br_y
    local tile_draw = corner_draw
    local tile_src = border_size
    local x = top_start_x
    while x < top_end_x do
        local remaining = top_end_x - x
        local draw_w = math_min(tile_draw, remaining)
        local src_w = math_min(tile_src, draw_w / border_scale)
        draw_texture_region(use_sprite, sides, x, top_y, draw_w, corner_draw, 0, 0, src_w, tile_src, border_tint, self.vec_pos, self.vec_scale)
        x = x + draw_w
    end
    x = bl_x + corner_draw
    while x < br_x do
        local remaining = br_x - x
        local draw_w = math_min(tile_draw, remaining)
        local src_w = math_min(tile_src, draw_w / border_scale)
        draw_texture_region(use_sprite, sides, x, bottom_y, draw_w, corner_draw, 0, tile_src, src_w, tile_src, border_tint, self.vec_pos, self.vec_scale)
        x = x + draw_w
    end
    local y = left_start_y
    while y < left_end_y do
        local remaining = left_end_y - y
        local draw_h = math_min(tile_draw, remaining)
        local src_h = math_min(tile_src, draw_h / border_scale)
        draw_texture_region(use_sprite, sides, left_x, y, corner_draw, draw_h, tile_src, 0, tile_src, src_h, border_tint, self.vec_pos, self.vec_scale)
        y = y + draw_h
    end
    y = right_start_y
    while y < right_end_y do
        local remaining = right_end_y - y
        local draw_h = math_min(tile_draw, remaining)
        local src_h = math_min(tile_src, draw_h / border_scale)
        draw_texture_region(use_sprite, sides, right_x, y, corner_draw, draw_h, tile_src, tile_src, tile_src, src_h, border_tint, self.vec_pos, self.vec_scale)
        y = y + draw_h
    end
end

function M:draw(handle, sprite)
    if not handle or handle.theme == '-None-' then
        return
    end
    self:draw_background(handle, sprite)
    self:draw_borders(handle, sprite)
end

function M:destroy(handle)
    if not handle then
        return
    end
    handle.bg_texture = nil
    for key in pairs(handle.border_textures) do
        handle.border_textures[key] = nil
    end
end

return M
