-- Global Helper Functions
require('common')
local ashita_settings = require('settings')
local defaults = require('config.defaults')

function S(t)
    local s = {}
    if t then
        for _,v in pairs(t) do s[v] = true end
    end
    return s
end

-- Global Variables
save_delay = 5000
rupt_savefile = ''
rupt_db = nil -- Will be table or file handle
tab_styles = nil
style_templates = nil
battlemod_loaded = false
debug_mode = false
chat_debug = false
drops_timer = os.clock()
undocked_timer = os.clock()+30

-- rupt_db initialization will happen in load event

rupt_table_length = 1000  --How many lines before we throw out lines from all_tabname table
rupt_subtable_length = 500 --How many lines before we throw out lines from sub tables (Tell,Linkshell,etc..)

chat_log_env = {
	['scrolling'] = false,
	['scroll_num'] = {},
	['finding'] = false,
	['last_seen'] = os.time(),
	['mention_found'] = false,
	['mention_count'] = 0,
	['last_mention_tab'] = false,
	['last_text_line'] = false,
	['monospace'] = false,
}

battle_ids = { [20]=true,[21]=true,[22]=true,[23]=true,[24]=true,[25]=true,[26]=true,[27]=true,[28]=true,[29]=true,[30]=true,[31]=true,[32]=true,[33]=true,[35]=true,[36]=true,[40]=true,[50]=true,[56]=true,[57]=true,[59]=true,[63]=true,[64]=true,[81]=true,[101]=true,[102]=true,[107]=true,[109]=true,[110]=true,[111]=true,[112]=true,[114]=true,[122]=true,[157]=true,[191]=true,[209]=true,[210]=true }
duplidoc_ids = { [121]=true, [190]=true, [662]=true, [66200]=true }
filter_ids = { [23]=true,[24]=true,[31]=true,[151]=true,[152]=true }

pause_ids = { [0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[38]=true,[59]=true,[64]=true,[90]=true,[91]=true,[121]=true,[123]=true,[127]=true,[131]=true,[144]=true,[146]=true,[148]=true,[160]=true,[161]=true,[190]=true,[204]=true,[207]=true,[208]=true,[210]=true,[212]=true,[213]=true,[214]=true,[221]=true,[245]=true }
chat_tables = {}
battle_table = {}
archive_table = {}

assist_flags = { 
	labels = {'bronze','silver','gold' },
	bronze = {
	[1] = string.char(0x2F),
	[2] = string.char(0x30),
	[3] = string.char(0x31),
	[4] = string.char(0x32),
	[5] = string.char(0x33),
	[6] = string.char(0x34),
	[7] = string.char(0x35),
	},
	silver = {
	[1] = string.char(0x39),
	[2] = string.char(0x3A),
	[3] = string.char(0x3B),
	[4] = string.char(0x3C),
	[5] = string.char(0x3D),
	[6] = string.char(0x3E),
	[7] = string.char(0x3F),
	},
	gold = {
	[1] = string.char(0x43),
	[2] = string.char(0x44),
	[3] = string.char(0x45),
	[4] = string.char(0x46),
	[5] = string.char(0x47),
	[6] = string.char(0x48),
	[7] = string.char(0x49),
	},
}
find_table = {
	['last_find'] = false,
	['last_index'] = 1,
}

default_settings = defaults.global_settings

tab_ids = {}
all_tabs = {}

calibrate_text = ""
calibrate_width  = "WIBIWIBIWIBIWIBIWIBI\nWIBIWIBIWIBIWIBIWIBI"
calibrate_width2 = "WIIIWIIIWIIIWIIIWIII\nWIIIWIIIWIIIWIIIWIiI"
calibrate_count = 0

setup_window_toggles = { 'battle_all','battle_off','strict_width','strict_length',
'incoming_pause','drag_status','battle_flash','chat_input','snapback','split_drops','drops_window','enh_whitespace','archive','vanilla_mode'}
setup_window_commands = { 'battle_all','battle_off','strict_width','strict_length',
'incoming_pause','drag','battle_flash','chatinput','snapback','splitdrops','dropswindow','enhancedwhitespace','archive','vanilla_mode'}

-- Export everything as a table
local loaded_settings = ashita_settings.load(default_settings)

-- Ensure critical sections exist (Fix for missing fields in old config files)
if not loaded_settings.bg then loaded_settings.bg = default_settings.bg end
if not loaded_settings.window then loaded_settings.window = default_settings.window end
if not loaded_settings.text then loaded_settings.text = default_settings.text end

return {
    S = S,
    save_settings = function() ashita_settings.save() end,
    save_delay = save_delay,
    rupt_savefile = rupt_savefile,
    rupt_db = rupt_db,
    tab_styles = tab_styles,
    style_templates = style_templates,
    battlemod_loaded = battlemod_loaded,
    chat_debug = chat_debug,
    drops_timer = drops_timer,
    undocked_timer = undocked_timer,
    rupt_table_length = rupt_table_length,
    rupt_subtable_length = rupt_subtable_length,
    chat_log_env = chat_log_env,
    battle_ids = battle_ids,
    duplidoc_ids = duplidoc_ids,
    filter_ids = filter_ids,
    pause_ids = pause_ids,
    chat_tables = chat_tables,
    battle_table = battle_table,
    archive_table = archive_table,
    assist_flags = assist_flags,
    find_table = find_table,
    default_settings = loaded_settings,
    tab_ids = tab_ids,
    all_tabs = all_tabs,
    all_tabname = 'General',
    battle_tabname = 'Battle',
    current_tab = 'General',
    calibrate_text = calibrate_text,
    calibrate_width = calibrate_width,
    calibrate_width2 = calibrate_width2,
    calibrate_count = calibrate_count,
    setup_window_toggles = setup_window_toggles,
    setup_window_commands = setup_window_commands,
    vanilla_color_codes = {}, -- Placeholder, will be populated if needed
}
