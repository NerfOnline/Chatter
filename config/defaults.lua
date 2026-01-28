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

local chatter_settings = T{
    theme = 'Plain',
    background_asset = 'Progressive-Blue',
    border_asset = 'Whispered-Veil',
    context_menu_theme = 'Progressive-Blue',
    font_family = 'Arial',
    font_size = 14,
    font_bold = true,
    font_italic = false,
    outline_enabled = false,
    window_x = 100,
    window_y = 100,
    window_w = 600,
    window_h = 400,
    lock_window = false,
    padding_x = 0,
    padding_y = 0,
    background_scale = 1.0,
    border_scale = 1.0,
    background_opacity = 0.7,
    border_opacity = 1.0,
    background_color = {0.8235, 0.7843, 1.0, 0.7020},
    border_color = {0.8235, 0.7843, 1.0, 1.0},
    outline_color = {0.0, 0.0, 0.0, 1.0},
    context_menu_config = T{
        items = T{
            { label = 'Copy Selected Text', enabled = true },
            { label = 'Send Tell', enabled = true },
            { label = 'Customize Context Menu', enabled = true },
            { label = 'Open Configuration', enabled = true },
        },
    },
    colors = T{
        chat = T{
            say = {1.0, 1.0, 1.0, 1.0},
            tell = {1.0, 0.0, 1.0, 1.0},
            party = {0.0, 1.0, 1.0, 1.0},
            linkshell = {0.0, 1.0, 0.0, 1.0},
            linkshell2 = {0.0, 1.0, 0.0, 1.0},
            assist_jp = {0.2510, 0.5020, 1.0, 1.0},
            assist_en = {0.2510, 0.5020, 1.0, 1.0},
            unity = {0.5020, 1.0, 0.5020, 1.0},
            emotes = {0.0, 0.7529, 1.0, 1.0},
            messages = {1.0, 1.0, 1.0, 1.0},
            npc = {1.0, 1.0, 1.0, 1.0},
            shout = {1.0, 1.0, 0.0, 1.0},
            yell = {1.0, 0.5020, 0.0, 1.0},
        },
        self = T{
            hpmp_recovered = {0.0, 1.0, 0.0, 1.0},
            hpmp_lost = {1.0, 0.0, 0.0, 1.0},
            beneficial_effects = {0.0, 0.0, 1.0, 1.0},
            detrimental_effects = {0.5020, 0.0157, 0.5020, 1.0},
            resisted_effects = {1.0, 0.7529, 0.0, 1.0},
            evaded_actions = {1.0, 0.5020, 0.7843, 1.0},
        },
        others = T{
            hpmp_recovered = {0.0, 1.0, 0.0, 1.0},
            hpmp_lost = {1.0, 0.0, 0.0, 1.0},
            beneficial_effects = {0.0, 0.0, 1.0, 1.0},
            detrimental_effects = {0.5020, 0.0157, 0.5020, 1.0},
            resisted_effects = {1.0, 0.7529, 0.0, 1.0},
            evaded_actions = {1.0, 0.5020, 0.7843, 1.0},
        },
        system = T{
            standard_battle = {0.2510, 0.5020, 1.0, 1.0},
            calls_for_help = {1.0, 0.5020, 0.0, 1.0},
            basic_system = {0.9490, 0.8510, 0.6000, 1.0},
        },
    },
}

local chat_colors = {
    say = {1.0, 1.0, 1.0, 1.0},
    tell = {1.0, 0.0, 1.0, 1.0},
    party = {0.0, 1.0, 1.0, 1.0},
    linkshell = {0.0, 1.0, 0.0, 1.0},
    linkshell2 = {0.0, 1.0, 0.0, 1.0},
    assist_jp = {0.2510, 0.5020, 1.0, 1.0},
    assist_en = {0.2510, 0.5020, 1.0, 1.0},
    unity = {0.5020, 1.0, 0.5020, 1.0},
    emotes = {0.0, 0.7529, 1.0, 1.0},
    messages = {1.0, 1.0, 1.0, 1.0},
    npc = {1.0, 1.0, 1.0, 1.0},
    shout = {1.0, 1.0, 0.0, 1.0},
    yell = {1.0, 0.5020, 0.0, 1.0},
}

local self_colors = {
    hpmp_recovered = {0.0, 1.0, 0.0, 1.0},
    hpmp_lost = {1.0, 0.0, 0.0, 1.0},
    beneficial_effects = {0.0, 0.0, 1.0, 1.0},
    detrimental_effects = {0.5020, 0.0157, 0.5020, 1.0},
    resisted_effects = {1.0, 0.7529, 0.0, 1.0},
    evaded_actions = {1.0, 0.5020, 0.7843, 1.0},
}

local system_colors = {
    standard_battle = {0.2510, 0.5020, 1.0, 1.0},
    calls_for_help = {1.0, 0.5020, 0.0, 1.0},
    basic_system = {0.9490, 0.8510, 0.6000, 1.0},
}

return {
    global_settings = global_settings,
    chatter_settings = chatter_settings,
    chat_colors = chat_colors,
    self_colors = self_colors,
    system_colors = system_colors,
}
