-- Chatter/core/ui/contextmenu_ui.lua
-- Clean, self-contained implementation of the "Customize Context Menu" UI.
--
-- API:
--   local contextmenu_ui = require('core.ui.contextmenu_ui')
--   local changed = contextmenu_ui.render(config, customize_window_rect, palette)
--
-- Notes:
-- - `config` should be the user's settings table (must expose `context_menu_items` and
--   `context_menu_enabled`).
-- - `rect` is a table with numeric fields `x`, `y`, `w`, `h` (the caller retains ownership).
--   The function will ensure `rect.w`/`rect.h` match the window defaults and will update
--   `rect.x`/`rect.y` after clamping performed by the caller (if any).
-- - `palette` is optional and expected to be `themestyle.palette` or similar; safe fallbacks
--   are used when not provided.
-- - The function returns `true` when something changed (order or enabled flags); caller is
--   responsible for applying/persisting the changes (e.g., call apply_context_menu_to_renderer()
--   and request_save()).
--
-- Implementation goals:
-- - Small, readable, and robust.
-- - Keep runtime-only drag state local to the module.
-- - Avoid any persistence side-effects; this function only mutates `config` when the user
--   explicitly changes something in the UI.

local imgui = require('imgui')

local M = {}

-- Window defaults (module-level constants).
local WIN_W = 350
local WIN_H = 365

-- Layout constants
local ROW_H = 26
local ROW_PAD_X = 8
local GRIP_W = 18
local CHECKBOX_W = 18
local CHECKBOX_TEXT_GAP = 10
local ROW_GAP = 6
local ROW_CORNER_RADIUS = 4.0
local GRIP_DOT_RADIUS = 1.25
local GRIP_DOT_SPACING = 5

-- Runtime-only drag state (does not live in persisted config).
local drag_state = {
    active = false,
    from_index = nil,
    to_index = nil,
    mouse_y = 0,
}

-- Utility: safe accessor for a table-as-array (handles nil)
local function safe_len(t)
    if not t then return 0 end
    return #t
end

-- Utility: move item inside an array-like table. Returns true if moved.
local function move_item_inplace(items, from_idx, to_idx)
    if not items or from_idx == to_idx then return false end
    if from_idx < 1 or from_idx > #items then return false end
    if to_idx < 1 or to_idx > #items then return false end
    local v = table.remove(items, from_idx)
    table.insert(items, to_idx, v)
    return true
end

-- Render the customize-context-menu UI.
-- Parameters:
--   cfg   - user config table (must contain `context_menu_items`, `context_menu_enabled`)
--   rect  - window rect table { x, y, w, h } (caller is expected to clamp / persist)
--   palette - optional palette from themestyle.push()
-- Returns:
--   changed (bool) - true if config was mutated (items or enabled map)
function M.render(cfg, rect, palette)
    if not cfg then
        return false
    end

    -- Ensure the window uses our intended fixed size.
    rect.w = WIN_W
    rect.h = WIN_H

    -- Palette fallbacks
    local bgLight = (palette and palette.bgLight) or { 0.095, 0.105, 0.130, 1.0 }
    local bgLighter = (palette and palette.bgLighter) or { 0.120, 0.135, 0.165, 1.0 }
    local accent = (palette and palette.accent) or { 0.30, 0.55, 0.95, 1.0 }

    local changed = false

    -- Header
    imgui.Text("Enable, disable, or sort menu items.")
    imgui.Separator()

    -- Begin scrollable area for list
    imgui.BeginChild("ContextMenuSettingsList", { 0, 0 }, true)

    local items = cfg.context_menu_items or {}
    local enabled = cfg.context_menu_enabled or {}

    -- Drawlist and region info
    local child_x, child_y = imgui.GetCursorScreenPos()
    local child_w = imgui.GetContentRegionAvail()
    local child_draw = imgui.GetWindowDrawList()

    -- Update drag target if active
    if drag_state.active then
        local mx, my = imgui.GetMousePos()
        drag_state.mouse_y = my
        local rel_y = my - child_y
        local idx = math.floor(rel_y / (ROW_H + ROW_GAP)) + 1
        if idx < 1 then idx = 1 end
        if idx > safe_len(items) then idx = safe_len(items) end
        drag_state.to_index = idx
    end

    -- Row visual colors (constructed once per frame; cheap)
    local row_bg = { bgLight[1], bgLight[2], bgLight[3], 0.90 }
    local row_hover = { bgLighter[1], bgLighter[2], bgLighter[3], 0.95 }
    local row_active = { bgLighter[1], bgLighter[2], bgLighter[3], 0.95 }

    local function row_bg_color(is_hovered, is_active)
        if is_active then return imgui.GetColorU32(row_active) end
        if is_hovered then return imgui.GetColorU32(row_hover) end
        return imgui.GetColorU32(row_bg)
    end

    -- Small helper to render the 3-dot grip
    local function draw_grip(x, y, h)
        local dot_r = GRIP_DOT_RADIUS
        local cx = x + (GRIP_W / 2)
        local cy = y + (h / 2)
        local spacing = GRIP_DOT_SPACING
        local col_u32 = imgui.GetColorU32(accent)
        child_draw:AddCircleFilled({ cx, cy - spacing }, dot_r, col_u32)
        child_draw:AddCircleFilled({ cx, cy }, dot_r, col_u32)
        child_draw:AddCircleFilled({ cx, cy + spacing }, dot_r, col_u32)
    end

    -- Render rows with placeholder insertion while dragging.
    -- When dragging we leave the dragged-from item out of the main flow and draw
    -- a ghost following the mouse; to present a stable drop target we render a
    -- placeholder slot at `drag_state.to_index` so other rows shift correctly.
    local total = safe_len(items)
    local display_pos = 1
    local mx, my = imgui.GetMousePos()

    for orig_i = 1, total do
        -- If dragging and the placeholder should be before the current display pos, render it.
        if drag_state.active and drag_state.to_index == display_pos and drag_state.from_index ~= display_pos then
            local y_ph = child_y + (display_pos - 1) * (ROW_H + ROW_GAP)
            imgui.SetCursorScreenPos({ child_x, y_ph })
            imgui.Dummy({ child_w, ROW_H })
            local x0 = child_x
            local y0 = y_ph
            local x1 = child_x + child_w
            local y1 = y0 + ROW_H
            child_draw:AddRectFilled({ x0, y0 }, { x1, y1 }, imgui.GetColorU32(row_bg), ROW_CORNER_RADIUS)
            display_pos = display_pos + 1
        end

        -- Skip rendering the original row that is being dragged; the ghost will be rendered later.
        if drag_state.active and drag_state.from_index == orig_i then
            -- do not increment display_pos for the removed item
        else
            local y = child_y + (display_pos - 1) * (ROW_H + ROW_GAP)
            imgui.SetCursorScreenPos({ child_x, y })
            imgui.Dummy({ child_w, ROW_H })

            local x0 = child_x
            local y0 = y
            local x1 = child_x + child_w
            local y1 = y0 + ROW_H
            local hover = mx >= x0 and mx <= x1 and my >= y0 and my <= y1
            local active = (drag_state.active and drag_state.from_index == orig_i)

            local bg_col = row_bg_color(hover, active)
            child_draw:AddRectFilled({ x0, y0 }, { x1, y1 }, bg_col, ROW_CORNER_RADIUS)

            -- Grip
            draw_grip(x0 + ROW_PAD_X, y0, ROW_H)

            -- Grip hitbox: handle drag start (only when not already dragging)
            local grip_x0 = x0 + ROW_PAD_X
            local grip_x1 = grip_x0 + GRIP_W
            local grip_y0 = y0
            local grip_y1 = y1
            local grip_hover = (mx >= grip_x0 and mx <= grip_x1 and my >= grip_y0 and my <= grip_y1)

            if (not drag_state.active) and grip_hover then
                imgui.SetCursorScreenPos({ grip_x0, grip_y0 })
                imgui.InvisibleButton("##cm_grip_" .. tostring(orig_i), { GRIP_W, ROW_H })
                if imgui.IsItemHovered() then
                    imgui.SetMouseCursor(ImGuiMouseCursor_Hand)
                end
                if imgui.IsItemActivated() then
                    drag_state.active = true
                    drag_state.from_index = orig_i
                    drag_state.to_index = orig_i
                    drag_state.mouse_y = my
                end
            end

            -- Checkbox + Label
            local cb_x = x0 + ROW_PAD_X + GRIP_W + 6
            local frame_h = imgui.GetFrameHeight()
            local row_center_y = y0 + (ROW_H * 0.5)
            local cb_y = math.floor((row_center_y - (frame_h * 0.5)) + 0.5)
            imgui.SetCursorScreenPos({ cb_x, cb_y })

            local label = items[orig_i] or ""
            local is_enabled = (enabled[label] ~= false)
            local buf = { is_enabled }
            if imgui.Checkbox("##cm_enabled_" .. tostring(orig_i), buf) then
                enabled[label] = buf[1]
                cfg.context_menu_enabled = enabled
                changed = true
            end

            -- Label text (center vertically)
            local font_h = imgui.GetFontSize()
            imgui.SetCursorScreenPos({ cb_x + CHECKBOX_W + CHECKBOX_TEXT_GAP, y0 + math.floor((ROW_H - font_h) / 2) })
            imgui.Text(label)

            display_pos = display_pos + 1
        end
    end

    -- If dragging and the placeholder is positioned at the end (after all rows), render it now.
    if drag_state.active and drag_state.to_index == display_pos and drag_state.from_index ~= drag_state.to_index then
        local y_ph = child_y + (display_pos - 1) * (ROW_H + ROW_GAP)
        imgui.SetCursorScreenPos({ child_x, y_ph })
        imgui.Dummy({ child_w, ROW_H })
        local x0 = child_x
        local y0 = y_ph
        local x1 = child_x + child_w
        local y1 = y0 + ROW_H
        child_draw:AddRectFilled({ x0, y0 }, { x1, y1 }, imgui.GetColorU32(row_bg), ROW_CORNER_RADIUS)
    end

    -- Ghost row when dragging (render on top)
    if drag_state.active and drag_state.from_index and drag_state.to_index then
        local ghost_y = drag_state.mouse_y - (ROW_H / 2)
        local min_y = child_y
        local max_y = child_y + (safe_len(items) - 1) * (ROW_H + ROW_GAP)
        if ghost_y < min_y then ghost_y = min_y end
        if ghost_y > max_y then ghost_y = max_y end

        local i = drag_state.from_index
        local x0 = child_x
        local y0 = ghost_y
        imgui.SetCursorScreenPos({ child_x, y0 })
        imgui.Dummy({ child_w, ROW_H })
        local child_draw2 = imgui.GetWindowDrawList()
        child_draw2:AddRectFilled({ x0, y0 }, { x0 + child_w, y0 + ROW_H }, imgui.GetColorU32(row_active), ROW_CORNER_RADIUS)
        draw_grip(x0 + ROW_PAD_X, y0, ROW_H)
        imgui.SetCursorScreenPos({ x0 + ROW_PAD_X + GRIP_W + 6, y0 + 2 })
        imgui.Text(items[i] or "")
    end

    -- Commit reorder when mouse released
    if drag_state.active and imgui.IsMouseReleased(0) then
        if drag_state.from_index and drag_state.to_index and drag_state.from_index ~= drag_state.to_index then
            if move_item_inplace(items, drag_state.from_index, drag_state.to_index) then
                cfg.context_menu_items = items
                changed = true
            end
        end

        -- reset state
        drag_state.active = false
        drag_state.from_index = nil
        drag_state.to_index = nil
        drag_state.mouse_y = 0
    end

    imgui.EndChild()

    return changed
end

return M
