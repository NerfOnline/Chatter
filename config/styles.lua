local style_templates = require('config.templates')

return function(settings)
    local player_name = (AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)) or 'Unknown'
    -- Escape special characters in player name
    player_name = string.gsub(player_name, "([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")

    local time_format = (settings and settings.time_format) or '24h'
    local ts_pat
    if time_format == '12h' then
         -- [01:30:00 PM]
         ts_pat = '%%[[0-9]+:[0-9]+:[0-9]+ %a+%%]'
    else
         -- [13:30:00]
         ts_pat = '%%[[0-9]+:[0-9]+:[0-9]+%%]'
    end
    
    -- Pattern with separator (space)
    local ts_sep = ts_pat .. ' '

    return {
        [0] = { -- Players Title / Zone Enter Message
            [1] = '^('..ts_sep..')(.+) title: (.+)',
            [2] = '\\cs('..style_templates['title_person']..')%1\\cr[%2 title] = \\cs('..style_templates['title_person']..')%3\\cr',
            [3] = '^('..ts_sep..')=== Area: (.*) ===',
            [4] = '\\cs('..style_templates['timestamp']..')%1\\cr=== Area -> \\cs('..style_templates['zone_name']..')%2\\cr ===',
        },
        [1] = { -- Say
            [1] = '^('..ts_sep..')(%a+)%s:(.*)',
            [2] = '\\cs('..style_templates['say_time']..')%1\\cr[\\cs('..style_templates['say_person']..')%2\\cr]\\cs('..style_templates['say_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['say_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['say_text']..')',
        },
        [2] = {
            [1] = '^('..ts_pat..')([^%[]+)%[([^%]]+)%](.*)',
            [2] = '\\cs('..style_templates['shout_time']..')%1\\cr%2[\\cs('..style_templates['shout_person']..')%3\\cr]\\cs('..style_templates['shout_text']..')%4\\cr',
    --		[3] = '(.+)\n(.+)\\cr',
    --		[4] = '%1\\cr\n\\cs('..style_templates['shout_text']..')%2\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['shout_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['shout_text']..')',
            },
        [3] = {
            [1] = '^('..ts_pat..')([^%[]+)%[([^%]]+)%](.*)',
            [2] = '\\cs('..style_templates['yell_time']..')%1\\cr%2[\\cs('..style_templates['yell_person']..')%3\\cr]\\cs('..style_templates['yell_text']..')%4\\cr',
    --		[3] = '(.+)\n(.+)\\cr',
    --		[4] = '%1\\cr\n\\cs('..style_templates['yell_text']..')%2\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['yell_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['yell_text']..')',
            },
        [4] = { -- Tell
            [1] = '^('..ts_pat..'):>>([^:]+):(.*)$', -- Note: Original had colon after timestamp. Now we use ts_pat and check if colon is needed? Original: ^([0-9]+:[0-9]+:[0-9]+):>>...
            -- Wait, if I output `[TS] >>...` (space), I should use ts_sep?
            -- Original: `HH:MM:SS:>>`
            -- My output: `[TS] >>`? Or `[TS] :>>`?
            -- If convert_text adds space: `[TS] >>`.
            -- So regex should be `^('..ts_sep..')>>`?
            -- But original had `:`, literal colon.
            -- If convert_text adds space, I should match space.
            -- So `^('..ts_sep..')>>` is correct.
            -- However, look at `[1] = '^('..ts_pat..'):>>([^:]+):(.*)$'`
            -- If I write `^('..ts_pat..'):>>`, it expects colon.
            -- I should use `^('..ts_sep..')>>`.
            -- But let's check Style 4 carefully.
            -- Original: `^([0-9]+:[0-9]+:[0-9]+):>>([^:]+):(.*)$`
            -- It matches timestamp, colon, `>>`, name, colon, msg.
            -- If I change to `[TS] >>Name: Msg`.
            -- Then pattern: `^('..ts_sep..')>>([^:]+):(.*)$`.
            
            [1] = '^('..ts_sep..')>>([^:]+):(.*)$',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr>>\\cs('..style_templates['outgoing_tell_name']..')%2\\cr:\\cs('..style_templates['outgoing_tell_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['outgoing_tell_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['outgoing_tell_text']..')',
            },
        [5] = {  -- party
            [1] = '^('..ts_pat..')[^%(]+%(([^%)]+)%)(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr<\\cs('..style_templates['party_name']..')%2\\cr>\\cs('..style_templates['party_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['party_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['party_text']..')',
            },
        [6] = { --ls1
            [1] = '^('..ts_pat..')[^<]+<([^>]+)>(.*)',
            [2] = '\\cs('..style_templates['linkshell1_time']..')%1\\cr<\\cs('..style_templates['linkshell1_name']..')%2\\cr>\\cs('..style_templates['linkshell1_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['linkshell1_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['linkshell1_text']..')',
            },
        [7] = { -- outgoing emote
            [1] = '^('..ts_sep..')(.+)( '..player_name..' )(.*)', --Someone Emoting you
            [2] = '\\cs('..style_templates['emote_time']..')%1\\cr * \\cs('..style_templates['emote_text']..')%2\\cr\\cs('..style_templates['emote_person']..')%3\\cr\\cs('..style_templates['emote_text']..')%4\\cr',
            [3] = '^('..ts_sep..')(.?'..player_name..')(.*)', --You Emoting
            [4] = '\\cs('..style_templates['emote_time']..')%1\\cr * \\cs('..style_templates['emote_person']..')%2\\cr\\cs('..style_templates['emote_text']..')%3\\cr',
            [5] = '^('..ts_sep..')(.+)', --Two assholes emoting solo/eachother.
            [6] = '\\cs('..style_templates['emote_time']..')%1\\cr * \\cs('..style_templates['emote_text']..')%2\\cr',
            },
        [8] = { -- Default settings for React use this ID
            [1] = '^('..ts_sep..')(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr\\cs('..style_templates['battle_dmg_1']..')%2\\cr',
        },
        [9] = { -- Say
            [1] = '^('..ts_sep..')(%a+)%s:(.*)', --Addon log message
            [2] = '\\cs('..style_templates['say_time']..')%1\\cr[\\cs('..style_templates['say_person']..')%2\\cr]\\cs('..style_templates['say_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['say_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['say_text']..')',
        },
        [10] = {  -- shout
            [1] = '^('..ts_pat..')([^%[]+)%[([^%]]+)%](.*)',
            [2] = '\\cs('..style_templates['shout_time']..')%1\\cr%2[\\cs('..style_templates['shout_person']..')%3\\cr]\\cs('..style_templates['shout_text']..')%4\\cr',
    --		[3] = '(.+)\n(.+)\\cr',
    --		[4] = '%1\\cr\n\\cs('..style_templates['shout_text']..')%2\\cr',
            [7] = '{(\n?):',
            [8] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['shout_text']..')',
            [9] = ':(\n?)}',
            [10] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['shout_text']..')',
            },
        [11] = { -- yell
            [1] = '^('..ts_pat..')([^%[]+)%[([^%]]+)%](.*)',
            [2] = '\\cs('..style_templates['yell_time']..')%1\\cr%2[\\cs('..style_templates['yell_person']..')%3\\cr]\\cs('..style_templates['yell_text']..')%4\\cr',
    --		[3] = '(.+)\n(.+)\\cr',
    --		[4] = '%1\\cr\n\\cs('..style_templates['yell_text']..')%2\\cr',
            [3] = '{(\n?):',
            [4] = '\\cs(0,255,0){\\cr\\cs('..style_templates['yell_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['yell_text']..')',
            },
        [12] = { -- tell
            [1] = '^('..ts_pat..')([^>]+)>>(.*)$',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr\\cs('..style_templates['incoming_tell_name']..')%2\\cr>>\\cs('..style_templates['incoming_tell_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['party_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['party_text']..')',
            },
        [13] = {  --party
            [1] = '^('..ts_pat..')[^%(]+%(([^%)]+)%)(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr<\\cs('..style_templates['party_name']..')%2\\cr>\\cs('..style_templates['party_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['party_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['party_text']..')',
            },
        [14] = { -- ls1
            [1] = '^('..ts_pat..')[^<]+<([^>]+)>(.*)',
            [2] = '\\cs('..style_templates['linkshell1_time']..')%1\\cr<\\cs('..style_templates['linkshell1_name']..')%2\\cr>\\cs('..style_templates['linkshell1_text']..')%3\\cr',
            [3] = '{(\n?):',
            [4] = '%1\\cs(0,255,0){\\cr\\cs('..style_templates['linkshell1_text']..')',
            [5] = ':(\n?)}',
            [6] = '\\cr\\cs(255,0,0)}\\cr%1\\cs('..style_templates['linkshell1_text']..')',
            },
        [15] = { -- incoming emote
            [1] = '^('..ts_sep..')(.+)( '..player_name..' )(.*)', --Someone Emoting you
            [2] = '\\cs('..style_templates['emote_time']..')%1\\cr * \\cs('..style_templates['emote_text']..')%2\\cr\\cs('..style_templates['emote_person']..')%3\\cr\\cs('..style_templates['emote_text']..')%4\\cr',
            [3] = '^('..ts_sep..')(.?'..player_name..')(.*)', --You Emoting
            [4] = '\\cs('..style_templates['emote_time']..')%1\\cr * \\cs('..style_templates['emote_person']..')%2\\cr\\cs('..style_templates['emote_text']..')%3\\cr',
            [5] = '^('..ts_sep..')(.+)', --Two assholes emoting solo/eachother.
            [6] = '\\cs('..style_templates['emote_time']..')%1\\cr * \\cs('..style_templates['emote_text']..')%2\\cr',
            },
        [20] = { -- battle     
            [1] = '^('..ts_sep..')(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr%2',
            [3] = '%[?('..player_name..'\'?s?)%]?',
            [4] = '[\\cs('..style_templates['battle_name_1']..')%1\\cr]',
            [5] = '(.-)( [0-9]+%s)(.*)',
            [6] = '%1\\cr\\cs('..style_templates['battle_dmg_1']..')%2\\cr%3',
            [7] = '^(.+'..ts_pat..'.+)%[([^%]]+)%](.+)',--
            [8] = '%1[\\cs('..style_templates['battle_name_2']..')%2\\cr]%3',--
            [9] = '(.*) %-> (.*)',
            [10] = '%1 ->\\cs('..style_templates['battle_name_2']..') %2\\cr',
        },
        [21] = { -- battle
            [1] = '^('..ts_sep..')(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr%2',
            [3] = '%[?('..player_name..'\'?s?)%]?',
            [4] = '[\\cs('..style_templates['battle_name_1']..')%1\\cr]',
            [5] = '^(.+'..ts_pat..'.+)%[([^%]]+)%] (.+)',
            [6] = '%1[\\cs('..style_templates['battle_name_2']..')%2\\cr] %3',
            [7] = '(.*) %-> (.*)',
            [8] = '%1 ->\\cs('..style_templates['battle_name_2']..') %2\\cr',
        },
        [22] = { --Party Members casting spell
            [1] = '^('..ts_sep..')(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr%2',
            [3] = '%[('..player_name..'\'?s?)%]',
            [4] = '[\\cs('..style_templates['battle_text_1']..')%1\\cr]',
            [5] = '(.-)( [0-9]+%s)(.*)',
            [6] = '%1\\cr\\cs('..style_templates['battle_dmg_1']..')%2\\cr%3',
            [7] = '(.*) %-> (.*)',
            [8] = '%1 ->\\cs('..style_templates['battle_name_2']..') %2\\cr',
        },
        [23] = { --casting spell on trust?
            [1] = '^('..ts_sep..')(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr%2',
            [3] = '^(.+'..ts_pat..'.+)('..player_name..'\'?s?)%]?(.+)',
            [4] = '%1[\\cs('..style_templates['battle_text_1']..')%2\\cr] %3',
            [5] = '^(.+'..ts_pat..'.+)%[?('..player_name..'\'?s?.-)([0-9]+)(.*)',
            [6] = '%1%2\\cs('..style_templates['battle_dmg_1']..')%3\\cr%4',
            [7] = '^(.+'..ts_pat..'.+)%[([^%]]+)%] (.-[0-9]+)(.*)',
            [8] = '%1[\\cs('..style_templates['battle_text_1']..')%2\\cr]\\cs('..style_templates['battle_dmg_1']..')%3\\cr%4',
            [9] = '^(.+'..ts_pat..'.+)%[([^%]]+)%](.+)',
            [10] = '%1[\\cs('..style_templates['battle_text_1']..')%2\\cr] %3',
            [11] = '(.*) %-> (.*)',
            [12] = '%1 ->\\cs('..style_templates['battle_name_2']..') %2\\cr',
        },
        [25] = { -- battle     
            [1] = '^('..ts_sep..')(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr%2',
            [3] = '%[?('..player_name..'\'?s?)%]?',
            [4] = '[\\cs('..style_templates['battle_name_1']..')%1\\cr]',
            [5] = '(.-)( [0-9]+%s)(.*)',
            [6] = '%1\\cr\\cs('..style_templates['battle_dmg_1']..')%2\\cr%3',
            [7] = '^(.+'..ts_pat..'.+)%[([^%]]+)%](.+)',--
            [8] = '%1[\\cs('..style_templates['battle_name_2']..')%2\\cr]%3',--
            [9] = '(.*) %-> (.*)',
            [10] = '%1 ->\\cs('..style_templates['battle_name_2']..') %2\\cr',
        },
        [26] = { -- battle     
            [1] = '^('..ts_sep..')(.*)',
            [2] = '\\cs('..style_templates['timestamp']..')%1\\cr%2',
            [3] = '%[?('..player_name..'\'?s?)%]?',
            [4] = '[\\cs('..style_templates['battle_name_1']..')%1\\cr]',
            [5] = '(.-)( [0-9]+%s)(.*)',
            [6] = '%1\\cr\\cs('..style_templates['battle_dmg_1']..')%2\\cr%3',
            [7] = '^(.+'..ts_pat..'.+)%[([^%]]+)%](.+)',--
            [8] = '%1[\\cs('..style_templates['battle_name_2']..')%2\\cr]%3',--
            [9] = '(.*) %-> (.*)',
            [10] = '%1 ->\\cs('..style_templates['battle_name_2']..') %2\\cr',
        }
    }
end