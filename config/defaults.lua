require('common')

local function S(t)
    local s = {}
    if t then
        for _, v in pairs(t) do s[v] = true end
    end
    return s
end

local global_settings = T{
    log_length = 12,
    log_width = 500,
    log_dwidth = 0,
    log_dlength = 0,
    battle_all = true,
    battle_off = false,
    strict_width = true,
    strict_length = true,
    undocked_window = false,
    undocked_tab = 'General',
    undocked_hide = false,
    incoming_pause = false,
    drag_status = true,
    battle_flash = false,
    snapback = true,
    chat_input = false,
    chat_input_placement = 1,
    split_drops = false,
    drops_window = true,
    enh_whitespace = true,
    archive = false,
    vanilla_mode = false,
    time_format = '24h',
    flags = {
        draggable = false,
        bold = false,
    },
    mentions = {
        All = S{},
        Tell = S{},
        Linkshell = S{},
        Linkshell2 = S{},
        Party = S{},
        Battle = S{},
    },
    text = {
        font = 'Lucida Sans Typewriter',
        custom_font_name = '',
        fonts = {
            'Arial', 'Calibri', 'Cambria', 'Cambria Math', 'Candara',
            'Cascadia Code', 'Cascadia Mono', 'Comic Sans MS', 'Consolas',
            'Courier New', 'Georgia', 'Impact', 'Lucida Console',
            'Lucida Sans', 'Lucida Sans Typewriter', 'Tahoma',
            'Times New Roman', 'Trebuchet MS', 'Verdana', 'Other'
        },
        size = 10,
        outline = 1,
        line_spacing = 4,
        style = 'Regular',
        alpha = 255,
        red = 255,
        green = 255,
        blue = 255,
        stroke = {
            width = 1,
            alpha = 255,
            red = 0,
            green = 0,
            blue = 0,
        }
    },
    bg = {
        theme = 'Plain',
        alpha = 255,
        red = 0,
        green = 0,
        blue = 0,
    },
    window = {
        x = 100,
        y = 100,
        w = 600,
        h = 400,
    },
}

-- NOTE: Colors are stored as RGBA in the format:
--   { r, g, b, a }
-- Where r/g/b are 0-255 and a is 0.0-1.0.
local chatter_settings = T{
    theme = 'Plain',
    background_asset = 'Progressive-Blue',
    border_asset = 'Whispered-Veil',
    context_menu_theme = 'Progressive-Blue',

    -- Context menu configuration:
    -- `context_menu_items` is the ordered list of entries you want to appear.
    -- `context_menu_enabled` allows you to hide entries without losing their position/order.
    --
    -- Notes:
    -- - Labels are the display text shown in the in-game context menu.
    -- - These defaults match the requested new names and default insertion point.
    context_menu_items = T{
        'Copy Selected Text',
        'Send Tell',
        'Customize Context Menu',
        'Open Configuration',
    },
    context_menu_enabled = T{
        ['Copy Selected Text'] = true,
        ['Send Tell'] = true,
        ['Customize Context Menu'] = true,
        ['Open Configuration'] = true,
    },

    font_family = 'Arial',
    font_size = 14,
    font_bold = true,
    font_italic = false,
    outline_enabled = false,
    window_x = 20,
    window_y = 545,
    window_w = 645,
    window_h = 220,
    lock_window = false,
    padding_x = 0,
    padding_y = 0,
    background_scale = 1.0,
    border_scale = 1.0,
    background_opacity = 0.7,
    border_opacity = 1.0,

    -- Converted from {0.8235, 0.7843, 1.0, 0.7020}
    background_color = { 210, 200, 255, 0.7 },
    -- Converted from {0.8235, 0.7843, 1.0, 1.0}
    border_color = { 210, 200, 255, 1.0 },
    -- Converted from {0.0, 0.0, 0.0, 1.0}
    outline_color = { 0, 0, 0, 1.0 },

    colors = T{
        chat = T{
            say = { 255, 255, 255, 1.0 },
            tell = { 255, 0, 255, 1.0 },
            party = { 0, 255, 255, 1.0 },
            linkshell = { 0, 255, 0, 1.0 },
            linkshell2 = { 0, 255, 0, 1.0 },
            assist_jp = { 64, 128, 255, 1.0 },
            assist_en = { 64, 128, 255, 1.0 },
            unity = { 128, 255, 128, 1.0 },
            emotes = { 0, 192, 255, 1.0 },
            messages = { 255, 255, 255, 1.0 },
            npc = { 255, 255, 255, 1.0 },
            shout = { 255, 255, 0, 1.0 },
            yell = { 255, 128, 0, 1.0 },
        },
        self = T{
            hpmp_recovered = { 0, 255, 0, 1.0 },
            hpmp_lost = { 255, 0, 0, 1.0 },
            beneficial_effects = { 0, 0, 255, 1.0 },
            detrimental_effects = { 128, 4, 128, 1.0 },
            resisted_effects = { 255, 192, 0, 1.0 },
            evaded_actions = { 255, 128, 200, 1.0 },
        },
        others = T{
            hpmp_recovered = { 0, 255, 0, 1.0 },
            hpmp_lost = { 255, 0, 0, 1.0 },
            beneficial_effects = { 0, 0, 255, 1.0 },
            detrimental_effects = { 128, 4, 128, 1.0 },
            resisted_effects = { 255, 192, 0, 1.0 },
            evaded_actions = { 255, 128, 200, 1.0 },
        },
        system = T{
            standard_battle = { 64, 128, 255, 1.0 },
            calls_for_help = { 255, 128, 0, 1.0 },
            basic_system = { 242, 217, 153, 1.0 },
        },
    },
}

local chat_colors = {
    say = { 255, 255, 255, 1.0 },
    tell = { 255, 0, 255, 1.0 },
    party = { 0, 255, 255, 1.0 },
    linkshell = { 0, 255, 0, 1.0 },
    linkshell2 = { 0, 255, 0, 1.0 },
    assist_jp = { 64, 128, 255, 1.0 },
    assist_en = { 64, 128, 255, 1.0 },
    unity = { 128, 255, 128, 1.0 },
    emotes = { 0, 192, 255, 1.0 },
    messages = { 255, 255, 255, 1.0 },
    npc = { 255, 255, 255, 1.0 },
    shout = { 255, 255, 0, 1.0 },
    yell = { 255, 128, 0, 1.0 },
}

local self_colors = {
    hpmp_recovered = { 0, 255, 0, 1.0 },
    hpmp_lost = { 255, 0, 0, 1.0 },
    beneficial_effects = { 0, 0, 255, 1.0 },
    detrimental_effects = { 128, 4, 128, 1.0 },
    resisted_effects = { 255, 192, 0, 1.0 },
    evaded_actions = { 255, 128, 200, 1.0 },
}

local system_colors = {
    standard_battle = { 64, 128, 255, 1.0 },
    calls_for_help = { 255, 128, 0, 1.0 },
    basic_system = { 242, 217, 153, 1.0 },
}

return {
    global_settings = global_settings,
    chatter_settings = chatter_settings,
    chat_colors = chat_colors,
    self_colors = self_colors,
    system_colors = system_colors,
}
