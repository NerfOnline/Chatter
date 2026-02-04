addon.name    = 'Chatter'
addon.author  = 'NerfOnline'
addon.version = '0.1'

require('common')
local chatmanager = require('core.chatmanager')
local renderer = require('core.renderer')
local imgui = require('imgui')
local themestyle = require('core.themestyle')
local settings = require('settings')
local defaults = require('config.defaults')
local ffi = require('ffi')
local bit = require('bit')

-- Preallocated temporary tables to avoid per-frame allocations when calling ImGui APIs.
-- Reusing these avoids creating many short-lived Lua tables each frame.
local IMGUI_NEXT_WINDOW_SIZE = { 0, 0 } -- reused for SetNextWindowSize
local IMGUI_NEXT_WINDOW_POS = { 0, 0 } -- reused for SetNextWindowPos
local WINDOW_PADDING_ZERO = { 0, 0 }

local DEBUG = false
local function debug_log(msg)
    if DEBUG then
        print(msg)
    end
end

-- Default window geometry (kept as constants to avoid scattered magic numbers)
local CONFIG_WINDOW_DEFAULT = { x = 20, y = 55, w = 645, h = 480 }
local CUSTOMIZE_WINDOW_DEFAULT = { w = 350, h = 365 }
local CUSTOMIZE_WINDOW_OFFSET_X = 40
local CUSTOMIZE_WINDOW_DEFAULT_Y = 55
local CONFIG_WINDOW_CLAMP_PAD = 2

-- Padding constraints
local PADDING_DEFAULT = 5
local PADDING_MIN = 0
local PADDING_MAX = 30
local PADDING_EXTRA = 5

-- Resize handle visuals
local RESIZE_TRI_SIZE = 18
local RESIZE_TRI_INSET = 4
local RESIZE_TRI_STAGGER = 4
local RESIZE_TRI_COLORS = {
    dark = { 0.25, 0.25, 0.25, 1.0 },
    mid = { 0.5, 0.5, 0.5, 1.0 },
    light = { 0.75, 0.75, 0.75, 1.0 },
}
local resize_tri_colors_u32 = nil
local function get_resize_tri_colors()
    if not resize_tri_colors_u32 then
        resize_tri_colors_u32 = {
            dark = imgui.GetColorU32(RESIZE_TRI_COLORS.dark),
            mid = imgui.GetColorU32(RESIZE_TRI_COLORS.mid),
            light = imgui.GetColorU32(RESIZE_TRI_COLORS.light),
        }
    end
    return resize_tri_colors_u32.dark, resize_tri_colors_u32.mid, resize_tri_colors_u32.light
end

local SCROLL_MULTIPLIER = 3
local RESIZE_ZONE_PAD = 5

local contextmenu_ui = require('core.ui.contextmenu_ui')

local FONT_OPTIONS = {
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

-- Asset scan cache (avoid running filesystem scans every frame)
local _asset_cache = {
    backgrounds = nil,
    borders = nil,
    last_scan = 0,
}

local function file_exists_cached(path)
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

local function scan_assets_cached(force)
    if _asset_cache.backgrounds == nil or force then
        local root = addon.path .. 'assets\\backgrounds\\'
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
            if file_exists_cached(root .. base .. '-bg.png') then
                table.insert(backgrounds, { base = base, display = name })
            end
        end
        for _, name in ipairs(border_order) do
            local base = name:gsub('%s+', '-')
            if file_exists_cached(root .. base .. '-corners.png') and file_exists_cached(root .. base .. '-sides.png') then
                table.insert(borders, { base = base, display = name })
            end
        end
        for i, item in ipairs(backgrounds) do
            item.display_num = string.format('%d - %s', i, item.display)
        end
        for i, item in ipairs(borders) do
            item.display_num = string.format('%d - %s', i, item.display)
        end
        _asset_cache.backgrounds = backgrounds
        _asset_cache.borders = borders
        _asset_cache.last_scan = os.time()
    end
    return _asset_cache.backgrounds, _asset_cache.borders
end

-- Screen clamp helpers
--
-- Goal: never allow any ImGui-managed window (chat/config/customize/etc) to end up off-screen.
-- We clamp using ImGui's display size (safe and available every frame).
local clamp = renderer.clamp

local function clamp_window_to_screen(x, y, w, h, pad)
    -- `pad` is the outer margin between the window and the screen edge.
    -- For the chat window we want it flush to the screen edges.
    --
    -- Important note:
    -- In some setups, `io.DisplaySize` can behave like a slightly smaller "safe area" than the
    -- actual game viewport/backbuffer (multi-monitor / DPI / borderless quirks). That can create
    -- an unwanted gap even when `pad = 0`.
    --
    -- To make "flush to edges" actually flush, we clamp against the D3D viewport RECT (X/Y/Width/Height)
    -- when available, and only fall back to `io.DisplaySize` if needed.
    pad = pad or 0

    local screen_x = 0
    local screen_y = 0
    local screen_w = 0
    local screen_h = 0

    -- Use ImGui display size for clamping.
    -- The D3D viewport query was returning 0x0 in some setups, so we rely on ImGui's DisplaySize
    -- which correctly reflects the game window dimensions (1920x1080 in user's case).
    local io = imgui.GetIO()
    screen_x = 0
    screen_y = 0
    screen_w = (io and io.DisplaySize and io.DisplaySize.x) or 0
    screen_h = (io and io.DisplaySize and io.DisplaySize.y) or 0

    -- If we can't read screen size for some reason, don't touch values.
    if screen_w <= 0 or screen_h <= 0 then
        return x, y, w, h
    end

    -- Ensure sane sizes.
    w = math.max(1, w or 1)
    h = math.max(1, h or 1)

    -- Clamp size to viewport (so resizing can't push it beyond display).
    w = math.min(w, screen_w - (pad * 2))
    h = math.min(h, screen_h - (pad * 2))

    -- Clamp position so the window stays fully visible within the viewport rect.
    local min_x = screen_x + pad
    local min_y = screen_y + pad
    local max_x = (screen_x + screen_w - w) - pad
    local max_y = (screen_y + screen_h - h) - pad

    x = clamp(x or min_x, min_x, max_x)
    y = clamp(y or min_y, min_y, max_y)

    return x, y, w, h
end

-- Note on ImGui window movement:
-- The chat window stays on-screen because we do NOT let ImGui drive its position.
-- We drive it ourselves (stored rect + per-frame SetNextWindowPos/Size) and clamp during drag/resize.
--
-- For the config windows (main config + customize context menu), normal ImGui title-bar dragging was
-- producing snap-back / off-screen quirks. To match the chat window's reliable behavior, we implement
-- chat-style dragging for those windows too:
-- - We maintain our own persisted rect.
-- - We always feed ImGui that rect via SetNextWindowPos/Size before Begin().
-- - We implement our own drag handling (no Shift required).
--
-- This is intentionally simple and predictable (no ImGui timing surprises).
local function is_point_in_rect(px, py, x, y, w, h)
    return px >= x and px <= (x + w) and py >= y and py <= (y + h)
end

-- Persisted window rects for "snap-free" clamping.
-- Why: ImGui can update window position late during drag. If we only clamp after Begin(),
-- the drag can appear to go off-screen then "snap back" on mouse release.
-- By remembering the last known-good rect and feeding it via SetNextWindowPos/Size BEFORE Begin,
-- the window refuses to move off-screen while dragging (same feel as the chat window).
local config_window_rect = {
    x = CONFIG_WINDOW_DEFAULT.x,
    y = CONFIG_WINDOW_DEFAULT.y,
    w = CONFIG_WINDOW_DEFAULT.w,
    h = CONFIG_WINDOW_DEFAULT.h,
}
local customize_window_rect = {
    x = CONFIG_WINDOW_DEFAULT.w + CUSTOMIZE_WINDOW_OFFSET_X,
    y = CUSTOMIZE_WINDOW_DEFAULT_Y,
    w = CUSTOMIZE_WINDOW_DEFAULT.w,
    h = CUSTOMIZE_WINDOW_DEFAULT.h,
}

local function set_customize_window_default_pos()
    customize_window_rect.x = (config_window_rect.w or 0) + CUSTOMIZE_WINDOW_OFFSET_X
    customize_window_rect.y = CUSTOMIZE_WINDOW_DEFAULT_Y
end



local SAVE_DEBOUNCE_SEC = 0.5
local save_pending = false
local last_save_request = 0
local function request_save()
    save_pending = true
    last_save_request = os.clock()
end
local function get_effective_padding(value)
    if value == nil then
        value = PADDING_DEFAULT
    end
    if value < PADDING_MIN then
        value = PADDING_MIN
    elseif value > PADDING_MAX then
        value = PADDING_MAX
    end
    return value + PADDING_EXTRA
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




local function copy_to_clipboard(text)
    debug_log("[Chatter] Copying to clipboard...")
    local len = #text + 1
    local hMem = ffi.C.GlobalAlloc(GHND or GMEM_FIXED, len)
    if hMem == nil then
        debug_log("[Chatter] GlobalAlloc failed")
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
            debug_log("[Chatter] SetClipboardData failed")
            return false
        end
        ffi.C.CloseClipboard()
        debug_log("[Chatter] Copied successfully")
        return true
    else
        ffi.C.GlobalFree(hMem)
        debug_log("[Chatter] OpenClipboard failed")
        return false
    end
end

config = settings.load(defaults.chatter_settings)

local function apply_default_value(value, default)
    if value == nil then
        return default
    end
    if type(value) == 'string' and value == '' then
        return default
    end
    return value
end

local default_chat_colors = defaults.chat_colors
local default_self_colors = defaults.self_colors
local default_system_colors = defaults.system_colors

config.background_asset = apply_default_value(config.background_asset, defaults.chatter_settings.background_asset)
config.border_asset = apply_default_value(config.border_asset, defaults.chatter_settings.border_asset)
config.context_menu_theme = apply_default_value(config.context_menu_theme, config.background_asset)
config.background_scale = apply_default_value(config.background_scale, defaults.chatter_settings.background_scale)
config.border_scale = apply_default_value(config.border_scale, defaults.chatter_settings.border_scale)
config.background_opacity = apply_default_value(config.background_opacity, defaults.chatter_settings.background_opacity)
config.border_opacity = apply_default_value(config.border_opacity, defaults.chatter_settings.border_opacity)
config.padding_x = apply_default_value(config.padding_x, defaults.chatter_settings.padding_x)
config.padding_y = apply_default_value(config.padding_y, defaults.chatter_settings.padding_y)
config.background_color = apply_default_value(config.background_color, defaults.chatter_settings.background_color)
config.border_color = apply_default_value(config.border_color, defaults.chatter_settings.border_color)
config.font_family = apply_default_value(config.font_family, defaults.chatter_settings.font_family)
config.font_size = apply_default_value(config.font_size, defaults.chatter_settings.font_size)
config.font_bold = apply_default_value(config.font_bold, defaults.chatter_settings.font_bold)
config.font_italic = apply_default_value(config.font_italic, defaults.chatter_settings.font_italic)
config.outline_enabled = apply_default_value(config.outline_enabled, defaults.chatter_settings.outline_enabled)

-- Context menu config (ordered + enabled flags).
config.context_menu_items = apply_default_value(config.context_menu_items, defaults.chatter_settings.context_menu_items)
config.context_menu_enabled = apply_default_value(config.context_menu_enabled,
    defaults.chatter_settings.context_menu_enabled)

config.colors = apply_default_value(config.colors, T{})
config.colors.chat = apply_default_value(config.colors.chat, T{})
config.colors.self = apply_default_value(config.colors.self, T{})
config.colors.others = apply_default_value(config.colors.others, T{})
config.colors.system = apply_default_value(config.colors.system, T{})

for k, v in pairs(default_chat_colors) do
    if config.colors.chat[k] == nil then
        config.colors.chat[k] = { v[1], v[2], v[3], v[4] }
    end
end
for k, v in pairs(default_self_colors) do
    if config.colors.self[k] == nil then
        config.colors.self[k] = { v[1], v[2], v[3], v[4] }
    end
    if config.colors.others[k] == nil then
        config.colors.others[k] = { v[1], v[2], v[3], v[4] }
    end
end
for k, v in pairs(default_system_colors) do
    if config.colors.system[k] == nil then
        config.colors.system[k] = { v[1], v[2], v[3], v[4] }
    end
end

if config.outline_color == nil then
    config.outline_color = defaults.chatter_settings.outline_color
end
if config.font_style == nil or config.font_style == '' then
    if config.font_bold and config.font_italic then
        config.font_style = 'Bold Italic'
    elseif config.font_italic then
        config.font_style = 'Italic'
    elseif config.font_bold then
        config.font_style = 'Bold'
    else
        config.font_style = 'Normal'
        config.font_bold = false
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
elseif config.font_style == 'Normal' then
    config.font_bold = false
    config.font_italic = false
else
    config.font_style = 'Normal'
    config.font_bold = false
    config.font_italic = false
end

if config.colors and config.colors.self then
    if not config.colors.others or config.colors.others == config.colors.self then
        local copy = T{}
        for k, v in pairs(config.colors.self) do
            if type(v) == 'table' then
                copy[k] = { v[1], v[2], v[3], v[4] }
            else
                copy[k] = v
            end
        end
        config.colors.others = copy
        request_save()
    end
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

-- Color helpers
--
-- This addon stores colors as: { r, g, b, a }
-- where:
--   r,g,b are 0-255
--   a is 0.0-1.0
--
-- This matches the ergonomic `rgba(255,255,255,1.0)` mental model while keeping
-- alpha as a normalized float (what most UI sliders/pickers want).


local function normalize_rgba(color)
    -- Accept nil/malformed inputs safely.
    if type(color) ~= 'table' or #color < 4 then
        return { 255, 255, 255, 1.0 }
    end

    local r = color[1]
    local g = color[2]
    local b = color[3]
    local a = color[4]

    -- If we ever encounter legacy float RGB (0..1), convert to 0..255.
    -- This keeps the addon robust while you iterate during development.
    if type(r) == 'number' and type(g) == 'number' and type(b) == 'number' then
        if r <= 1.0 and g <= 1.0 and b <= 1.0 then
            r = math.floor(r * 255 + 0.5)
            g = math.floor(g * 255 + 0.5)
            b = math.floor(b * 255 + 0.5)
        end
    end

    -- Clamp into expected ranges.
    r = clamp(math.floor((r or 255) + 0.5), 0, 255)
    g = clamp(math.floor((g or 255) + 0.5), 0, 255)
    b = clamp(math.floor((b or 255) + 0.5), 0, 255)

    -- Alpha: support legacy 0..255 alpha or 0..1 alpha.
    if type(a) == 'number' and a > 1.0 then
        a = a / 255.0
    end
    a = clamp(a or 1.0, 0.0, 1.0)

    return { r, g, b, a }
end



local function imgui_float4_to_rgba(value)
    -- ImGui returns 0..1 floats for rgba.
    local r = clamp(math.floor((value[1] or 1.0) * 255 + 0.5), 0, 255)
    local g = clamp(math.floor((value[2] or 1.0) * 255 + 0.5), 0, 255)
    local b = clamp(math.floor((value[3] or 1.0) * 255 + 0.5), 0, 255)
    local a = clamp(value[4] or 1.0, 0.0, 1.0)
    return { r, g, b, a }
end

local function rgba_to_argb(color)
    local c = normalize_rgba(color)
    local r = c[1]
    local g = c[2]
    local b = c[3]
    local a = clamp(math.floor((c[4] * 255) + 0.5), 0, 255)
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
        return rgba_to_argb(colors.chat and colors.chat.say)
    elseif mid == CHAT_MODES.tell then
        return rgba_to_argb(colors.chat and colors.chat.tell)
    elseif mid == CHAT_MODES.party then
        return rgba_to_argb(colors.chat and colors.chat.party)
    elseif mid == CHAT_MODES.linkshell then
        return rgba_to_argb(colors.chat and colors.chat.linkshell)
    elseif mid == CHAT_MODES.linkshell2 then
        return rgba_to_argb(colors.chat and colors.chat.linkshell2)
    elseif mid == CHAT_MODES.unity then
        return rgba_to_argb(colors.chat and colors.chat.unity)
    elseif mid == CHAT_MODES.emote then
        return rgba_to_argb(colors.chat and colors.chat.emotes)
    elseif mid == CHAT_MODES.shout then
        return rgba_to_argb(colors.chat and colors.chat.shout)
    elseif mid == CHAT_MODES.yell then
        return rgba_to_argb(colors.chat and colors.chat.yell)
    elseif mid == CHAT_MODES.player
        or mid == CHAT_MODES.others
        or mid == CHAT_MODES.other_defeated
        or mid == CHAT_MODES.battle then
        return rgba_to_argb(colors.system and colors.system.standard_battle)
    elseif mid == CHAT_MODES.system then
        return rgba_to_argb(colors.system and colors.system.basic_system)
    elseif mid == CHAT_MODES.message
        or mid == CHAT_MODES.message2
        or mid == CHAT_MODES.misc_message
        or mid == CHAT_MODES.misc_message2
        or mid == CHAT_MODES.misc_message3 then
        return rgba_to_argb(colors.chat and colors.chat.messages)
    else
        return rgba_to_argb(colors.chat and colors.chat.messages)
    end
end

local function edit_color(label, tbl, key)
    if not tbl then
        return
    end

    -- Keep internal storage as { r, g, b, a } where:
    --   r,g,b are 0-255
    --   a is 0.0-1.0
    --
    -- But present the ORIGINAL compact ImGui picker UX:
    -- - A small color preview + label (no numeric inputs in the row)
    -- - Clicking opens the standard picker popup (square + hue bar + alpha bar)
    -- - Alpha is controlled via the alpha bar (no separate slider widget)
    local c = normalize_rgba(tbl[key] or { 255, 255, 255, 1.0 })
    local value = { c[1] / 255.0, c[2] / 255.0, c[3] / 255.0, c[4] }

    local flags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar)
    if imgui.ColorEdit4(label, value, flags) then
        tbl[key] = imgui_float4_to_rgba(value)
        request_save()
    end
end

local show_config = false
local show_context_menu_config = false
local current_config_section = 'General'
local is_dragging = false

-- Build the renderer-facing list of context menu items using the user's config:
-- - `context_menu_items` is the ordered list
-- - `context_menu_enabled[label]` determines visibility
local function build_enabled_context_menu_items(cfg)
    local items = {}
    if not cfg or type(cfg.context_menu_items) ~= 'table' then
        return items
    end

    local enabled = cfg.context_menu_enabled or T{}
    for i = 1, #cfg.context_menu_items do
        local label = cfg.context_menu_items[i]
        if label and label ~= '' and enabled[label] ~= false then
            table.insert(items, label)
        end
    end
    return items
end

-- Keep renderer's menu in sync with config.
local function apply_context_menu_to_renderer()
    if not config then
        return
    end
    renderer.set_context_menu_items(build_enabled_context_menu_items(config))
end
local is_resizing = false
local drag_offset_x = 0
local drag_offset_y = 0

-- Chat-style dragging state for ImGui config windows (no Shift required).
local config_is_dragging = false
local config_drag_offset_x = 0
local config_drag_offset_y = 0

-- Customize window drag state (mirror of main config dragging behavior).
local customize_is_dragging = false
local customize_drag_offset_x = 0
local customize_drag_offset_y = 0

-- Title-bar height approximation used for manual dragging regions.
-- (ImGui doesn't expose a direct "title bar rect" in this binding.)
local IMGUI_TITLEBAR_H = 22

-- Multi-monitor edge case:
-- If the mouse leaves the game viewport (e.g. moves to a second monitor) and the user releases
-- the mouse button outside of ImGui's area, `imgui.IsMouseDown(0)` may remain true for our frame loop.
-- This would cause the window to keep "dragging" when the cursor returns.
--
-- Fix: treat any mouse position outside the current ImGui display as "not dragging".
local function is_mouse_in_imgui_display(mx, my)
    local io = imgui.GetIO()
    local screen_w = (io and io.DisplaySize and io.DisplaySize.x) or 0
    local screen_h = (io and io.DisplaySize and io.DisplaySize.y) or 0
    if screen_w <= 0 or screen_h <= 0 then
        -- If we can't read the display size, don't force-cancel dragging.
        return true
    end
    return (mx >= 0) and (my >= 0) and (mx <= screen_w) and (my <= screen_h)
end
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

local anchor_start_abs = nil



-- Initialize
ashita.events.register('load', 'chatter_load', function()
    show_config = false
    show_context_menu_config = false
    renderer.initialize_minimal(addon.path)
    renderer.set_background_asset(config.background_asset or 'Plain')
    apply_context_menu_to_renderer()
    renderer.set_border_asset(config.border_asset)
    renderer.update_style(
        config.font_family,
        config.font_size,
        config.font_bold,
        config.font_italic,
        config.outline_enabled,
        rgba_to_argb(config.outline_color or { 0, 0, 0, 1.0 })
    )
    local bg_col = normalize_rgba(config.background_color or { 255, 255, 255, 1.0 })
    local bd_col = normalize_rgba(config.border_color or { 255, 255, 255, 1.0 })
    renderer.set_background_color(rgba_to_argb(bg_col))
    renderer.set_border_color(rgba_to_argb(bd_col))
    renderer.set_background_scale(config.background_scale or 1.0)
    renderer.set_border_scale(config.border_scale or 1.0)
    renderer.set_background_opacity(config.background_opacity or 1.0)
    renderer.set_border_opacity(config.border_opacity or 1.0)
    renderer.set_context_menu_opacity(1.0)
    renderer.set_chat_padding(get_effective_padding(config.padding_x), get_effective_padding(config.padding_y))



    -- Begin incremental background load (history, fonts, remaining objects).
    renderer.begin_background_load()
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
    -- Clamp chat window geometry to screen so it never ends up off-screen.
    do
        local cx, cy, cw, ch = clamp_window_to_screen(
            config.window_x,
            config.window_y,
            config.window_w,
            config.window_h,
            0
        )
        config.window_x = cx
        config.window_y = cy
        config.window_w = cw
        config.window_h = ch
    end

    IMGUI_NEXT_WINDOW_SIZE[1] = config.window_w
    IMGUI_NEXT_WINDOW_SIZE[2] = config.window_h
    IMGUI_NEXT_WINDOW_POS[1] = config.window_x
    IMGUI_NEXT_WINDOW_POS[2] = config.window_y
    imgui.SetNextWindowSize(IMGUI_NEXT_WINDOW_SIZE, ImGuiCond_Always)
    imgui.SetNextWindowPos(IMGUI_NEXT_WINDOW_POS, ImGuiCond_Always)

    -- Remove ImGui's default window padding so the chat window can be truly flush to screen edges.
    -- This affects GetCursorScreenPos() and GetContentRegionAvail() inside the window.
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, WINDOW_PADDING_ZERO)

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

    local chat_window_open = imgui.Begin("Chatter", true, windowFlags)

    -- Always pop the WindowPadding style we pushed, regardless of whether Begin succeeded.
    imgui.PopStyleVar(1)

    if chat_window_open then
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

        -- Resize handle: draw a small inset triangle in the top-right corner.
        --
        -- IMPORTANT: Position relative to the VISIBLE chat content area (render_x/y/w/h),
        -- not the ImGui window bounds (win_x/y/w/h). The visible chat background is drawn
        -- by the renderer at (render_x, render_y, render_w, render_h), so the triangle
        -- must be placed inside that rect.
        --
        -- Visual:
        -- - Triangle points into the top-right corner of the visible chat area.
        -- - Top and right legs are the same length.
        -- - Small inset gap from the edges.
        local draw_list = imgui.GetWindowDrawList()
        if not config.lock_window then
            -- Draw three staggered triangles pointing into the top-right corner.
            -- All same size, staggered diagonally by a fixed amount.
            -- Bottom layer = lightest, top layer = darkest.
            local tri_size = RESIZE_TRI_SIZE
            local inset = RESIZE_TRI_INSET
            local stagger = RESIZE_TRI_STAGGER

            -- Use the visible content rect (what the user sees as "the chat window").
            local content_right = render_x + render_w
            local content_top = render_y

            -- Colors (from darkest to lightest):
            -- Top layer (smallest visual, drawn last): #404040FF (dark)
            -- Mid layer: #808080FF (medium)
            -- Bottom layer (drawn first): #C0C0C0FF (light)
            local col_dark, col_mid, col_light = get_resize_tri_colors()

            -- Anchor point: top-right corner of content area, inset from edges.
            local anchor_x = content_right - inset
            local anchor_y = content_top + inset

            -- Bottom triangle (lightest, drawn first so it's behind).
            -- This one is at the anchor point.
            local b_ax, b_ay = anchor_x, anchor_y
            local b_bx, b_by = anchor_x - tri_size, anchor_y
            local b_cx, b_cy = anchor_x, anchor_y + tri_size
            draw_list:AddTriangleFilled({ b_ax, b_ay }, { b_bx, b_by }, { b_cx, b_cy }, col_light)

            -- Middle triangle (medium), staggered 4px inward diagonally.
            local m_ax, m_ay = anchor_x - stagger, anchor_y + stagger
            local m_bx, m_by = m_ax - tri_size, m_ay
            local m_cx, m_cy = m_ax, m_ay + tri_size
            draw_list:AddTriangleFilled({ m_ax, m_ay }, { m_bx, m_by }, { m_cx, m_cy }, col_mid)

            -- Top triangle (darkest, drawn last so it's on top), staggered 8px inward.
            local t_ax, t_ay = anchor_x - (stagger * 2), anchor_y + (stagger * 2)
            local t_bx, t_by = t_ax - tri_size, t_ay
            local t_cx, t_cy = t_ax, t_ay + tri_size
            draw_list:AddTriangleFilled({ t_ax, t_ay }, { t_bx, t_by }, { t_cx, t_cy }, col_dark)
        end

        if imgui.IsWindowHovered() or is_resizing or is_dragging or selecting then
            local wheel = imgui.GetIO().MouseWheel
            if wheel ~= 0 then
                renderer.update_scroll(wheel * SCROLL_MULTIPLIER)
            end

            local mouse_x, mouse_y = imgui.GetMousePos()
            local rel_x = mouse_x - content_x - get_effective_padding(config.padding_x)
            local rel_y = mouse_y - content_y - get_effective_padding(config.padding_y)

            local resize_zone_x1 = win_x + win_w - RESIZE_HANDLE_SIZE + RESIZE_ZONE_PAD
            local resize_zone_y1 = win_y
            local resize_zone_y2 = win_y + RESIZE_HANDLE_SIZE - RESIZE_ZONE_PAD
            local in_resize_zone = (not config.lock_window) and (mouse_x >= resize_zone_x1) and
                (mouse_y >= resize_zone_y1) and (mouse_y <= resize_zone_y2)

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
                -- Clamp resized window inside the screen.
                local cx, cy, cw, ch = clamp_window_to_screen(config.window_x, new_y, new_w, new_h, 0)
                config.window_x = cx
                config.window_y = cy
                config.window_w = cw
                config.window_h = ch
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
                -- Keep dragged window inside the screen.
                local cx, cy = clamp_window_to_screen(new_x, new_y, config.window_w, config.window_h, 0)
                config.window_x = cx
                config.window_y = cy
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
        end

        local mouse_x, mouse_y = imgui.GetMousePos()
        local is_mouse_over_chat = is_point_in_rect(mouse_x, mouse_y, render_x, render_y, render_w, render_h)
        local context_menu_opened_this_frame = false
        local context_menu_toggled_off = false
        if imgui.IsMouseClicked(1) then
            if renderer.is_context_menu_visible() then
                renderer.hide_context_menu()
                context_menu_toggled_off = true
            elseif is_mouse_over_chat then
                -- Ensure the renderer is drawing the user's configured menu before showing it.
                apply_context_menu_to_renderer()
                renderer.show_context_menu(mouse_x, mouse_y)
                context_menu_opened_this_frame = true
            end
        end
        if renderer.is_context_menu_visible() and (not context_menu_opened_this_frame) and (not context_menu_toggled_off) then
            if imgui.IsMouseClicked(0) or imgui.IsMouseClicked(1) or imgui.IsMouseClicked(2) then
                if imgui.IsMouseClicked(0) then
                    -- If the click is on a menu item, treat it like a selection.
                    local idx = renderer.get_context_menu_item_index(mouse_x, mouse_y)
                    if idx ~= nil then
                        local label = renderer.get_context_menu_item_label(idx)
                        if label == 'Copy Selected Text' then
                            local selected = renderer.get_selected_text and renderer.get_selected_text() or nil
                            if selected and selected ~= '' then
                                copy_to_clipboard(selected)
                            else
                                debug_log('[Chatter] No selected text to copy.')
                            end
                        elseif label == 'Send Tell' then
                            -- TODO: implement tell target / prefill behavior if desired.
                            debug_log('[Chatter] Send Tell is not implemented yet.')
                        elseif label == 'Customize Context Menu' then
                            local next_state = not show_context_menu_config
                            show_context_menu_config = next_state
                            if next_state then
                                set_customize_window_default_pos()
                            end
                        elseif label == 'Open Configuration' then
                            show_config = not show_config
                        end
                    end
                end
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
    -- Render config-related UI when either window is visible.
    -- This allows "Customize Context Menu" to open independently of the main config window.
    if not show_config and not show_context_menu_config then return end

    local font_options = FONT_OPTIONS

    -- Shared theme (used by both the main config window and the customize-context-menu window).
    local palette = themestyle.push()

    -- Main config window: chat-style dragging (no Shift) + always-on-screen clamping.
    local config_visible = false
    if show_config then
        -- Clamp our stored rect and feed it to ImGui BEFORE Begin() every frame (chat window behavior).
        do
            local cx, cy, cw, ch = clamp_window_to_screen(
                config_window_rect.x,
                config_window_rect.y,
                config_window_rect.w,
                config_window_rect.h,
                CONFIG_WINDOW_CLAMP_PAD
            )
            config_window_rect.x = cx
            config_window_rect.y = cy
            config_window_rect.w = cw
            config_window_rect.h = ch

            imgui.SetNextWindowSize({ cw, ch }, ImGuiCond_Always)
            imgui.SetNextWindowPos({ cx, cy }, ImGuiCond_Always)
        end

        local config_open = { show_config }
        config_visible = imgui.Begin("Chatter Config", config_open, 0)
        show_config = config_open[1]
        if not config_visible then
            imgui.End()
            -- Intentionally do not `return` here; the customize window may still be open.
            config_visible = false
        else
            -- Read ImGui internal rect (authoritative for sizing), store it, then handle manual dragging.
            local wx, wy = imgui.GetWindowPos()
            local ww, wh = imgui.GetWindowSize()
            wx = math.floor(wx + 0.5)
            wy = math.floor(wy + 0.5)
            ww = math.floor(ww + 0.5)
            wh = math.floor(wh + 0.5)

            config_window_rect.x = wx
            config_window_rect.y = wy
            config_window_rect.w = ww
            config_window_rect.h = wh

            -- Manual drag region: the title bar area at the top of the window.
            -- We DO NOT use ImGui's built-in moving; we move our stored rect.
            do
                local mx, my = imgui.GetMousePos()
                local title_hovered = is_point_in_rect(mx, my, wx, wy, ww, IMGUI_TITLEBAR_H)

                if imgui.IsMouseClicked(0) and title_hovered then
                    config_is_dragging = true
                    config_drag_offset_x = mx - wx
                    config_drag_offset_y = my - wy
                end

                -- If the mouse leaves the game viewport, immediately cancel dragging.
                -- This prevents "stuck dragging" when releasing on another monitor.
                if config_is_dragging and not is_mouse_in_imgui_display(mx, my) then
                    config_is_dragging = false
                    request_save()
                elseif config_is_dragging and imgui.IsMouseDown(0) then
                    local new_x = mx - config_drag_offset_x
                    local new_y = my - config_drag_offset_y
                    local cx, cy = clamp_window_to_screen(new_x, new_y, ww, wh, CONFIG_WINDOW_CLAMP_PAD)
                    config_window_rect.x = cx
                    config_window_rect.y = cy
                elseif config_is_dragging and not imgui.IsMouseDown(0) then
                    config_is_dragging = false
                    request_save()
                end
            end
        end
    end

    -- Pull commonly-used palette entries into locals for readability in the UI code below.
    local accent = palette.accent
    local accentDarker = palette.accentDarker
    local accentLight = palette.accentLight
    local bgLight = palette.bgLight
    local bgLighter = palette.bgLighter

    -- Customize Context Menu window (same theme as main config).
    -- This window intentionally has no left category list; it's one page.
    --
    -- UX goals:
    -- - Checkbox to enable/disable entries.
    -- - A "grip" handle (3 small vertical dots) to drag+drop reorder.
    -- - While dragging, the row follows the mouse, and other rows shift to make space.
    -- - Light row background for readability; stronger highlight on hover/active.
    if show_context_menu_config then
        -- Customize window: chat-style dragging (no Shift), fixed size, always on-screen.
        local w, h = CUSTOMIZE_WINDOW_DEFAULT.w, CUSTOMIZE_WINDOW_DEFAULT.h
        customize_window_rect.w = w
        customize_window_rect.h = h

        -- Clamp our stored rect and feed it to ImGui BEFORE Begin() every frame (chat window behavior).
        do
            local cx, cy, cw, ch = clamp_window_to_screen(
                customize_window_rect.x,
                customize_window_rect.y,
                customize_window_rect.w,
                customize_window_rect.h,
                CONFIG_WINDOW_CLAMP_PAD
            )
            customize_window_rect.x = cx
            customize_window_rect.y = cy
            customize_window_rect.w = cw
            customize_window_rect.h = ch

            imgui.SetNextWindowSize({ cw, ch }, ImGuiCond_Always)
            imgui.SetNextWindowPos({ cx, cy }, ImGuiCond_Always)
        end

        local cm_open = { show_context_menu_config }
        local cm_visible = imgui.Begin("Customize Context Menu", cm_open, ImGuiWindowFlags_NoResize)
        show_context_menu_config = cm_open[1]

        if cm_visible then
            local wx, wy = imgui.GetWindowPos()
            local ww, wh = imgui.GetWindowSize()
            wx = math.floor(wx + 0.5)
            wy = math.floor(wy + 0.5)
            ww = math.floor(ww + 0.5)
            wh = math.floor(wh + 0.5)

            customize_window_rect.x = wx
            customize_window_rect.y = wy
            customize_window_rect.w = ww
            customize_window_rect.h = wh

            -- Manual drag region for customize window (same approach as main config window).
            do
                local mx, my = imgui.GetMousePos()
                local title_hovered = is_point_in_rect(mx, my, wx, wy, ww, IMGUI_TITLEBAR_H)

                if imgui.IsMouseClicked(0) and title_hovered then
                    customize_is_dragging = true
                    customize_drag_offset_x = mx - wx
                    customize_drag_offset_y = my - wy
                end

                if customize_is_dragging and not is_mouse_in_imgui_display(mx, my) then
                    customize_is_dragging = false
                    request_save()
                elseif customize_is_dragging and imgui.IsMouseDown(0) then
                    local new_x = mx - customize_drag_offset_x
                    local new_y = my - customize_drag_offset_y
                    local cx, cy = clamp_window_to_screen(new_x, new_y, ww, wh, CONFIG_WINDOW_CLAMP_PAD)
                    customize_window_rect.x = cx
                    customize_window_rect.y = cy
                elseif customize_is_dragging and not imgui.IsMouseDown(0) then
                    customize_is_dragging = false
                    request_save()
                end
            end

            -- Delegate the customize-context-menu rendering to the extracted module.
            local changed = false
            if contextmenu_ui and contextmenu_ui.render then
                changed = contextmenu_ui.render(config, customize_window_rect, palette)
            end

            if changed then
                -- Apply and persist changes when module reports a mutation.
                apply_context_menu_to_renderer()
                request_save()
            end
        end

        imgui.End()
    end

    if show_config and config_visible then
        local sidebarWidth = 180

        imgui.BeginChild("ChatterConfigLeft", { sidebarWidth, 0 }, true)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 8, 6 })

        local general_selected = (current_config_section == 'General')
        if general_selected then
            imgui.PushStyleColor(ImGuiCol_Button, accent)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, accentLight)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, accentDarker)
        else
            imgui.PushStyleColor(ImGuiCol_Button, { 0, 0, 0, 0 })
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, { accent[1], accent[2], accent[3], 0.25 })
            imgui.PushStyleColor(ImGuiCol_ButtonActive, { accent[1], accent[2], accent[3], 0.35 })
        end
        if imgui.Button("General", { sidebarWidth - 24, 24 }) then
            current_config_section = 'General'
        end
        imgui.PopStyleColor(3)

        local fonts_selected = (current_config_section == 'Fonts')
        if fonts_selected then
            imgui.PushStyleColor(ImGuiCol_Button, accent)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, accentLight)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, accentDarker)
        else
            imgui.PushStyleColor(ImGuiCol_Button, { 0, 0, 0, 0 })
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, { accent[1], accent[2], accent[3], 0.25 })
            imgui.PushStyleColor(ImGuiCol_ButtonActive, { accent[1], accent[2], accent[3], 0.35 })
        end
        if imgui.Button("Fonts", { sidebarWidth - 24, 24 }) then
            current_config_section = 'Fonts'
        end
        imgui.PopStyleColor(3)

        imgui.PopStyleVar()
        imgui.EndChild()

        imgui.SameLine()

        imgui.BeginChild("ChatterConfigRight", { 0, 0 }, false)

        if config_visible and current_config_section == 'General' then
            if imgui.BeginTabBar("ChatterGeneralTabs") then
                if imgui.BeginTabItem("General") then
                    -- Asset scanning moved to cached helper `scan_assets_cached`.
                    -- Use `scan_assets_cached(true)` to force a refresh when needed.
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
                    imgui.Text("Chat Window Settings")
                    imgui.Separator()

                    local lock_val = { config.lock_window }
                    if imgui.Checkbox("Lock Window (Hide Resize Icon)", lock_val) then
                        config.lock_window = lock_val[1]
                        request_save()
                    end

                    local bg_items, border_items = scan_assets_cached()
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
                        local bg_col = normalize_rgba(config.background_color or { 255, 255, 255, 1.0 })
                        bg_col[4] = bg_opacity_buf[1]
                        config.background_color = bg_col
                        renderer.set_background_color(rgba_to_argb(bg_col))
                        request_save()
                    end

                    local border_opacity_buf = { config.border_opacity or 1.0 }
                    if imgui.SliderFloat("Border Opacity", border_opacity_buf, 0.0, 1.0, "%.2f") then
                        config.border_opacity = border_opacity_buf[1]
                        renderer.set_border_opacity(border_opacity_buf[1])
                        local bd_col = normalize_rgba(config.border_color or { 255, 255, 255, 1.0 })
                        bd_col[4] = border_opacity_buf[1]
                        config.border_color = bd_col
                        renderer.set_border_color(rgba_to_argb(bd_col))
                        request_save()
                    end

                    renderer.set_context_menu_opacity(1.0)

                    local pad_x_buf = { config.padding_x or PADDING_DEFAULT }
                    if imgui.SliderInt("Window Padding X", pad_x_buf, PADDING_MIN, PADDING_MAX) then
                        config.padding_x = pad_x_buf[1]
                        renderer.set_chat_padding(get_effective_padding(config.padding_x),
                            get_effective_padding(config.padding_y))
                        request_save()
                    end

                    local pad_y_buf = { config.padding_y or PADDING_DEFAULT }
                    if imgui.SliderInt("Window Padding Y", pad_y_buf, PADDING_MIN, PADDING_MAX) then
                        config.padding_y = pad_y_buf[1]
                        renderer.set_chat_padding(get_effective_padding(config.padding_x),
                            get_effective_padding(config.padding_y))
                        request_save()
                    end

                    imgui.Text("Context Menu Settings")
                    imgui.Separator()
                    if imgui.Button("Customize Context Menu", { 220, 24 }) then
                        local next_state = not show_context_menu_config
                        show_context_menu_config = next_state
                        if next_state then
                            set_customize_window_default_pos()
                        end
                    end

                    imgui.EndTabItem()
                end

                if imgui.BeginTabItem("Colors") then
                    -- Compact picker UX:
                    -- - Only show the label + small color square in the tab
                    -- - Clicking opens the standard popup (square + hue bar + alpha bar)
                    -- - Internally we still store { r, g, b, a } where r/g/b are 0-255 and a is 0.0-1.0
                    local flags = bit.bor(ImGuiColorEditFlags_NoInputs, ImGuiColorEditFlags_AlphaBar)

                    do
                        local c = normalize_rgba(config.background_color or { 255, 255, 255, 1.0 })
                        local value = { c[1] / 255.0, c[2] / 255.0, c[3] / 255.0, c[4] }
                        if imgui.ColorEdit4("Background Color", value, flags) then
                            local rgba = imgui_float4_to_rgba(value)
                            config.background_color = rgba
                            renderer.set_background_color(rgba_to_argb(rgba))
                            config.background_opacity = rgba[4]
                            renderer.set_background_opacity(rgba[4])
                            request_save()
                        end
                    end

                    do
                        local c = normalize_rgba(config.border_color or { 255, 255, 255, 1.0 })
                        local value = { c[1] / 255.0, c[2] / 255.0, c[3] / 255.0, c[4] }
                        if imgui.ColorEdit4("Border Color", value, flags) then
                            local rgba = imgui_float4_to_rgba(value)
                            config.border_color = rgba
                            renderer.set_border_color(rgba_to_argb(rgba))
                            config.border_opacity = rgba[4]
                            renderer.set_border_opacity(rgba[4])
                            request_save()
                        end
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
                            rgba_to_argb(config.outline_color or { 0, 0, 0, 1.0 })
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
                            rgba_to_argb(config.outline_color or { 0, 0, 0, 1.0 })
                        )
                        request_save()
                    end

                    local style_options = { 'Normal', 'Bold', 'Italic', 'Bold Italic' }
                    local current_style = config.font_style or 'Bold'
                    if current_style ~= 'Normal' and current_style ~= 'Bold' and current_style ~= 'Italic' and current_style ~= 'Bold Italic' then
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
                                    false,
                                    nil
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
                    local colors = config.colors
                    if colors then
                        if imgui.CollapsingHeader("Chat") then
                            edit_color("Say", colors.chat, 'say')
                            edit_color("Tell", colors.chat, 'tell')
                            edit_color("Party", colors.chat, 'party')
                            edit_color("Linkshell", colors.chat, 'linkshell')
                            edit_color("Linkshell 2", colors.chat, 'linkshell2')
                            edit_color("Assist JP", colors.chat, 'assist_jp')
                            edit_color("Assist EN", colors.chat, 'assist_en')
                            edit_color("Unity", colors.chat, 'unity')
                            edit_color("Emotes", colors.chat, 'emotes')
                            edit_color("Messages", colors.chat, 'messages')
                            edit_color("NPC", colors.chat, 'npc')
                            edit_color("Shout", colors.chat, 'shout')
                            edit_color("Yell", colors.chat, 'yell')
                        end

                        if imgui.CollapsingHeader("For Self") then
                            imgui.PushID("self_colors")
                            edit_color("HP/MP Recovered", colors.self, 'hpmp_recovered')
                            edit_color("HP/MP Lost", colors.self, 'hpmp_lost')
                            edit_color("Beneficial Effects", colors.self, 'beneficial_effects')
                            edit_color("Detrimental Effects", colors.self, 'detrimental_effects')
                            edit_color("Resisted Effects", colors.self, 'resisted_effects')
                            edit_color("Evaded Actions", colors.self, 'evaded_actions')
                            imgui.PopID()
                        end

                        if imgui.CollapsingHeader("For Others") then
                            imgui.PushID("others_colors")
                            edit_color("HP/MP Recovered", colors.others, 'hpmp_recovered')
                            edit_color("HP/MP Lost", colors.others, 'hpmp_lost')
                            edit_color("Beneficial Effects", colors.others, 'beneficial_effects')
                            edit_color("Detrimental Effects", colors.others, 'detrimental_effects')
                            edit_color("Resisted Effects", colors.others, 'resisted_effects')
                            edit_color("Evaded Actions", colors.others, 'evaded_actions')
                            imgui.PopID()
                        end

                        if imgui.CollapsingHeader("System") then
                            edit_color("Standard Battle Messages", colors.system, 'standard_battle')
                            edit_color("Calls For Help", colors.system, 'calls_for_help')
                            edit_color("Basic System Messages", colors.system, 'basic_system')
                        end
                    end

                    imgui.EndTabItem()
                end

                imgui.EndTabBar()
            end
        end

        imgui.EndChild()

        imgui.End()
    end

    themestyle.pop()
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
