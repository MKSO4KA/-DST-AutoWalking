name = "Auto Walking"
version = "4.1.2"
description = version .. [[
 Auto-pathfinding and Biome Scanner.

Features:
1. Right-click on Map/MiniMap to auto-walk.
2. Biome Scanner (F9/F10) to outline specific areas.
3. Intelligent obstacle avoidance.
]]

author = "Original Author & You"
forumthread = ""
api_version = 10
dst_compatible = true
client_only_mod = true
all_clients_require_mod = false
icon_atlas = "modicon.xml"
icon = "modicon.tex"
priority = -1001

local function Breaker(title) 
	return {name = title, options = {{description = "", data = false}}, default = false}
end

configuration_options = {
	Breaker("UI Settings"), 
	{
		name = "UI_DISPLAY",
		label = "UI Display",
		hover = "Configure the display of the icon and path line", 
		options = {
            {description = "Icon & PathLine", data = "Both"},
            {description = "Icon Only", data = "DestIcon"}, 
            {description = "PathLine Only", data = "PathLine"}, 
            {description = "None", data = false}
        },
		default = "Both",
	}, 
	{
		name = "ICON_STYLE",
		label = "Icon Style",
		options = {{description = "New", data = 1}, {description = "Classical", data = 0}},
		default = 1,
	},

	Breaker("Operation Settings"), 
	{
		name = "MAPS_TRIGGER",
		label = "Maps Trigger Settings",
		hover = "Configure whether the MainMapScreen and MiniMapHUD/SmallMap Mod can trigger auto-pathing",
		options = {
            {description = "Map & MiniMap", data = "Both"},
            {description = "MainMap Only", data = "MainMap"}, 
            {description = "MiniMap Only", data = "MiniMap"}
        },
		default = "Both",
	},
	{	
		name = "DBCLICK_TIME_THRESHOLD",
		label = "DoubleClick Interval",
		hover = "DoubleClick to trigger the original map action. Set the time interval.",
		options = {
            {description = "0.2s", data = 0.2},
            {description = "0.3s", data = 0.3},
            {description = "0.4s", data = 0.4},
            {description = "0.5s", data = 0.5}
        },
		default = 0.3,
	},
	{
		name = "KEY_ADDITION_TRAVEL",
		label = "Additional Travel Key",
		hover = "Key modifier to append a waypoint to the current path.",
		options = {
            {description = "Disabled", data = false},
            {description = "Shift+RMB", data = "CONTROL_FORCE_TRADE"},
            {description = "Ctrl+RMB", data = "CONTROL_FORCE_ATTACK"},
            {description = "Alt+RMB", data = "CONTROL_FORCE_INSPECT"}
        },
		default = false,
	},

	Breaker("Pathfinding Settings"),
	{
		name = "ALLOW_FOGOFWAR",
		label = "Allow Fog Of War",
		hover = "Allow Pathfinding in Fog Of War",
		options = {{description = "Yes", data = true}, {description = "No", data = false}},
		default = true,
	},
	{
		name = "TWEAK_DETOUR_ENABLE",
		label = "Bypass Obstacles",
		hover = "Automatically avoid obstacles (Best with Caves enabled).",
		options = {{description = "Enabled", data = true}, {description = "Disabled", data = false}},
		default = true,
	},
	{
		name = "PATHFINDER",
		label = "Pathfinder",
		hover = "A Star: Long distance, follows roads.\nKlei's: Short distance, faster calculation.",
		options = {{description = "A star", data = "A star"}, {description = "klei's", data = "klei's"}},
		default = "A star",
	},

	Breaker("Other Settings"), 
	{
		name = "TIMESCALE_TWEAK_MULTI",
		label = "Auto Speedup (Solo)",
		hover = "Auto increase game speed during autowalking (Solo only).",
		options = {
            {description = "Disabled", data = false},
            {description = "1.25x", data = 1.25},
            {description = "1.5x", data = 1.5},
            {description = "2x", data = 2},
            {description = "3x", data = 3},
            {description = "4x", data = 4}
        },
		default = false,
	},
	{
		name = "PATCH_MINIMAP",
		label = "Patch For MiniMap HUD",
		hover = "Fixes MiniMap HUD zoom reset issue.",
		options = {{description = "Disabled", data = false}, {description = "Enabled", data = true}},
		default = false,
	},

    -- SCANNER SETTINGS
    Breaker("Scanner Settings"),
    {
        name = "KEY_TOGGLE_SCAN",
        label = "Toggle Scan/Display",
        hover = "Show/Hide outlines. Starts a new scan if no data exists.",
        options = {
            {description = "F9", data = KEY_F9},
            {description = "F10", data = KEY_F10},
            {description = "F11", data = KEY_F11},
            {description = "F12", data = KEY_F12},
            {description = "J", data = KEY_J},
            {description = "K", data = KEY_K},
        },
        default = KEY_F9,
    },
    {
        name = "KEY_FORCE_RESCAN",
        label = "Force Rescan",
        hover = "Deletes current data and forces a new scan.",
        options = {
            {description = "F9", data = KEY_F9},
            {description = "F10", data = KEY_F10},
            {description = "F11", data = KEY_F11},
            {description = "F12", data = KEY_F12},
            {description = "L", data = KEY_L},
        },
        default = KEY_F10,
    }
}