
GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})
modimport("scripts/misc/foolsday_joke.lua")
if TheNet:IsDedicated()  then  return end

-------------------ASSETS----------------------------
local is_newicon = GetModConfigData("ICON_STYLE") > 0

-- path line
line_xml = "images/line.xml"
line_tex = "images/line.tex"
line_texName = string.sub(line_tex, string.find(line_tex, "[^/]*$")) -- "line.tex"
-- dest icon
icon_xml = is_newicon and "images/mappin.xml" or "images/mappin_old.xml"
icon_tex = is_newicon and "images/mappin.tex" or "images/mappin_old.tex"
icon_texName = string.sub(icon_tex, string.find(icon_tex, "[^/]*$")) -- "mappin.tex"

Assets = {
    Asset("ATLAS", line_xml),
	Asset("IMAGE", line_tex),
	
    Asset("ATLAS", icon_xml),
	Asset("IMAGE", icon_tex)
}


------------------COMPONENTS REGISTER-----------------
local PATHFINDER = GetModConfigData("PATHFINDER")
local pathfinder = nil

local ALLOW_PATHFIND_FOGOFWAR = GetModConfigData("ALLOW_FOGOFWAR")

local function SetTimeScale_ClientAndServer(multi)
	TheSim:SetTimeScale(multi)
	if not TheWorld.ismastersim then
		local x, y, z = TheSim:ProjectScreenPos(TheSim:GetPosition())
		TheNet:SendRemoteExecute("TheSim:SetTimeScale("..multi..")", x, z)
	end
end
-- increase the sim timescale during the autowalking
local TIMESCALE_TWEAK_MULTI = GetModConfigData("TIMESCALE_TWEAK_MULTI")
local ori_simtimescale, in_tweaking
local function GetPlayerNum()
	local client_objs = TheNet:GetClientTable() or {}
	return not TheNet:GetServerIsClientHosted() and #client_objs - 1 or #client_objs
end
local function SetSimTimeScaleTweakEnabled(enabled)
	if enabled then
		if TheNet:GetIsServerAdmin() and GetPlayerNum() == 1 and not in_tweaking then
			ori_simtimescale = TheSim:GetTimeScale()
			SetTimeScale_ClientAndServer(ori_simtimescale * TIMESCALE_TWEAK_MULTI)
			in_tweaking = true
		end
	else
		if in_tweaking and ori_simtimescale then
			SetTimeScale_ClientAndServer(ori_simtimescale)
			in_tweaking = false
		end
	end
end

AddComponentPostInit("playercontroller", function(self, player)
	if ThePlayer ~= nil and player == ThePlayer then
		-- add lua pathfinder
		if player.components.ngl_astarpathfinder == nil then
			player:AddComponent("ngl_astarpathfinder")
		end

		-- add official pathfinder
		if player.components.ngl_pathfinder == nil then
			player:AddComponent("ngl_pathfinder")
		end

		-- add a pathfinder that fuse lua and cpp pathfinder result
		if player.components.ngl_fusedpathfinder == nil then
			player:AddComponent("ngl_fusedpathfinder")
		end

		-- add pathfollower component to do pathfollow work
		if player.components.ngl_pathfollower == nil then
			player:AddComponent("ngl_pathfollower")
		end

		pathfinder = PATHFINDER == "klei's" and player.components.ngl_pathfinder or player.components.ngl_fusedpathfinder

		-- override for island adventure mod
		if TheWorld and TheWorld:HasTag("island") then --or if TheWorld and (TheWorld:HasTag("island") or TheWorld:HasTag("volcano"))
			pathfinder = player.components.ngl_pathfinder
		end

		-- pathfinder for main path search
		player.components.ngl_pathfollower:SetPathfinder(pathfinder)
		-- pathfinder for sub path search (dymanic path adjustment to handle the obstacles out of the loading range)
		-- player.components.ngl_pathfollower.subsearch_pathfinder = pathfinder
		-- there's some problems to use LUA pathfinder in subpath searching when the tiles of startpos and endpos is adjacent(see FindNearbyWalkableCenterPoint)

		player.components.ngl_pathfollower.allow_pathfinding_fog_of_war = ALLOW_PATHFIND_FOGOFWAR
		
		-- for SimTimeScale Tweak:
		if type(TIMESCALE_TWEAK_MULTI) == "number" then
			player:ListenForEvent("ngl_startpathfollow", function() SetSimTimeScaleTweakEnabled(true) end)
			player:ListenForEvent("ngl_stoppathfollow", function() SetSimTimeScaleTweakEnabled(false) end)
		end
	end
end)

----------------TRIGGER AND HALT----------------------
-- including the tweak of mapscreen, minimapwidget, smallmap, playercontroller

-- TRIGGER
modimport("scripts/postInits/mapscreenPostInit.lua")

AddSimPostInit(function ()
	local is_minimap_enable = false
	local is_smallmap_enable = false
	--On Error Resume Next
	pcall(function() is_minimap_enable = (require("widgets/minimapwidget") ~= nil) end)
	pcall(function() is_smallmap_enable = (require("widgets/smallmap") ~= nil) end)

	if is_minimap_enable then
		modimport("scripts/postInits/minimapwidgetPostInit.lua")
	end

	if is_smallmap_enable then 
		modimport("scripts/postInits/smallmapPostInit.lua")
	end
end)

-- HALT
modimport("scripts/postInits/playercontrollerPostInit.lua")

-------------------------MISC-----------------------
--it may cause many problems
--i just want to see how is it if all the creatures can detour
--and now you can get this feature in "Don't Blocked Together" mod
local bypass_enabled = GetModConfigData("TWEAK_DETOUR_ENABLE")
-- 2023.8.9:
--always enabled, i have fixed it and it seems work well these days
--if it's broken someday , please found this and changed to false
-- FORGIVE ME , I JUST WANT MY EFFORT PUT TO USE
bypass_enabled = true
if not TheNet:GetIsServer() and bypass_enabled then
	modimport("scripts/misc/pathfinding_bypass.lua")
end