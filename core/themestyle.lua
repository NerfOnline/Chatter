-- Shared ImGui theme helper for config-like windows.
--
-- Purpose:
-- - Provide a single place to define Chatter's "config window" theme.
-- - Avoid duplicating PushStyleColor/PushStyleVar blocks across multiple windows.
-- - Keep theme values accessible (accent/background tones) for custom draw code.
--
-- Usage:
--   local themestyle = require('core.themestyle')
--
--   themestyle.push()
--   -- ... imgui.Begin(...) ... your UI ... imgui.End()
--   themestyle.pop()
--
-- Notes:
-- - ImGui expects colors as { r, g, b, a } floats in 0..1.
-- - This file intentionally keeps them as the original float format, because they
--   are not persisted and they map directly to ImGui APIs.
-- - Keep Push/Pop counts in sync. Only call `pop()` if `push()` succeeded.
--
-- This module does not require any addon globals; it only requires `imgui`.

local imgui = require('imgui')

local themestyle = {}

-- Expose the current palette so other UI code can reuse the same tones
-- (e.g., custom drawlist UI like the context menu reorder list).
--
-- WARNING:
-- - Treat this as read-only. If you need a modified alpha, make a copy.
themestyle.palette = {
    accent =        { 0.30, 0.55, 0.95, 1.0 },
    accentDark =    { 0.20, 0.40, 0.75, 1.0 },
    accentDarker =  { 0.12, 0.28, 0.55, 1.0 },
    accentLight =   { 0.40, 0.65, 0.98, 1.0 },

    bgDark =        { 0.050, 0.055, 0.070, 0.95 },
    bgMedium =      { 0.070, 0.080, 0.100, 1.0 },
    bgLight =       { 0.095, 0.105, 0.130, 1.0 },
    bgLighter =     { 0.120, 0.135, 0.165, 1.0 },

    textLight =     { 0.900, 0.920, 0.950, 1.0 },
    borderDark =    { 0.16,  0.24,  0.40,  1.0 },
}

-- How many PushStyleColor calls we do in `push()`.
-- Keep this in sync if you add/remove colors.
local STYLE_COLOR_COUNT = 31

-- How many PushStyleVar calls we do in `push()`.
local STYLE_VAR_COUNT = 8

-- Push the shared "config window" theme.
-- Returns the palette for convenience.
function themestyle.push()
    local p = themestyle.palette

    -- Base colors the original config used
    local bgColor = p.bgDark
    local buttonColor = p.bgMedium
    local buttonHoverColor = p.bgLight
    local buttonActiveColor = p.bgLighter

    imgui.PushStyleColor(ImGuiCol_WindowBg, bgColor)
    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0, 0, 0, 0 })
    imgui.PushStyleColor(ImGuiCol_TitleBg, p.bgMedium)
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, p.bgLight)
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, p.bgDark)

    imgui.PushStyleColor(ImGuiCol_FrameBg, p.bgMedium)
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, p.bgLight)
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, p.bgLighter)

    imgui.PushStyleColor(ImGuiCol_Header, p.bgLight)
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, p.bgLighter)
    imgui.PushStyleColor(ImGuiCol_HeaderActive, { p.accent[1], p.accent[2], p.accent[3], 0.35 })

    imgui.PushStyleColor(ImGuiCol_Border, p.borderDark)
    imgui.PushStyleColor(ImGuiCol_Text, p.textLight)
    imgui.PushStyleColor(ImGuiCol_TextDisabled, { 0.55, 0.62, 0.78, 1.0 })

    imgui.PushStyleColor(ImGuiCol_Button, buttonColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, buttonHoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, buttonActiveColor)

    imgui.PushStyleColor(ImGuiCol_CheckMark, p.accent)
    imgui.PushStyleColor(ImGuiCol_SliderGrab, p.accentDark)
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, p.accent)

    imgui.PushStyleColor(ImGuiCol_Tab, p.bgMedium)
    imgui.PushStyleColor(ImGuiCol_TabHovered, p.bgLight)
    imgui.PushStyleColor(ImGuiCol_TabActive, { p.accent[1], p.accent[2], p.accent[3], 0.35 })
    imgui.PushStyleColor(ImGuiCol_TabUnfocused, p.bgDark)
    imgui.PushStyleColor(ImGuiCol_TabUnfocusedActive, p.bgMedium)

    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, p.bgMedium)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, p.accentDarker)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, p.accentDark)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, p.accent)

    imgui.PushStyleColor(ImGuiCol_ResizeGrip, { p.accent[1], p.accent[2], p.accent[3], 0.35 })
    imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, p.accentLight)
    imgui.PushStyleColor(ImGuiCol_ResizeGripActive, p.accent)

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 12, 12 })
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 6, 4 })
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 6 })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0)

    return p
end

-- Pop the shared theme. Safe to call only if `push()` was called.
function themestyle.pop()
    imgui.PopStyleVar(STYLE_VAR_COUNT)
    imgui.PopStyleColor(STYLE_COLOR_COUNT)
end

return themestyle
