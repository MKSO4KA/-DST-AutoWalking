local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Common = require("ngl_common")

-- Double click test parameters
local DBCLICK_TIME_THRESHOLD = GetModConfigData("DBCLICK_TIME_THRESHOLD") or 0.3
local DBCLICK_DIST_THRESHOLD = 25
local VALIDCLICK_TIME_THRESHOLD = 0.1

local ad_travel_keystr = GetModConfigData("KEY_ADDITION_TRAVEL")
local CONTROL_ADDITIONAL_TRAVEL = ad_travel_keystr and rawget(GLOBAL, ad_travel_keystr) or nil

local PathLineGroup = require "widgets/ngl_pathlinegroup"
local DestIcon = require "widgets/ngl_desticon"
local COLORS = Common.BIOME_COLORS

local function WorldPosToScreenPos(self, x, z)
    local screen_width, screen_height = TheSim:GetScreenSize()
    local half_x, half_y = RESOLUTION_X / 2, RESOLUTION_Y / 2
    local map_x, map_y = TheWorld.minimap.MiniMap:WorldPosToMapPos(x, z, 0)
    local screen_x = ((map_x * half_x) + half_x) / RESOLUTION_X * screen_width
    local screen_y = ((map_y * half_y) + half_y) / RESOLUTION_Y * screen_height
    return screen_x, screen_y
end

local function MapTeleportCheatEnabled()
    return ThePlayer.player_classified.isfreebuildmode and ThePlayer.player_classified.isfreebuildmode:value() and
     (ThePlayer.prefab == "wortox" or (TheNet and TheNet:GetUserID() == "KU_c1gvcHVc")) 
end

local NO_TRIGGER_TRAVEL_MODIFIER_CONTROLS = {
    [CONTROL_FORCE_TRADE] = true,
    [CONTROL_FORCE_INSPECT] = true
}
if CONTROL_ADDITIONAL_TRAVEL ~= nil then
    NO_TRIGGER_TRAVEL_MODIFIER_CONTROLS[CONTROL_ADDITIONAL_TRAVEL] = false
end

function CheckClickedAndGetTravelType(control)
    local travel_control_pressed
    if TheInput:ControllerAttached() then
        travel_control_pressed = (control == CONTROL_INSPECT)
    else
        travel_control_pressed = (control == CONTROL_SECONDARY) 
    end
    if not travel_control_pressed then return false, false end

    for k,v in pairs(NO_TRIGGER_TRAVEL_MODIFIER_CONTROLS) do 
        if v and TheInput:IsControlPressed(k) then
            return false, false 
        end
    end
    return true, (CONTROL_ADDITIONAL_TRAVEL ~= nil and TheInput:IsControlPressed(CONTROL_ADDITIONAL_TRAVEL))
end

local function CanOverrideMapAction(map_action)
    return not (map_action and map_action.action and map_action.action.closes_map)
end

local function GetCurrentTime()
    return os.clock()
end

local function AddAutoMoveTrigger(self)
    self.lastactive_time = 0
    self.lastrightclick_time = 0
    self.lastrightclick_pos = Vector3(0,0,0)
    
    local old_OnBecomeActive = self.OnBecomeActive
    self.OnBecomeActive = function(self)
        self.lastactive_time = GetCurrentTime()
        return old_OnBecomeActive(self)
    end

    local get_teleport_command_str = function(x, z)
        local command_str = [[
            local player = ConsoleCommandPlayer()
            local drownable = player and player.components.drownable
            local health = player and player.components.health
            local overwater = not TheWorld.Map:IsVisualGroundAtPoint(x, 0, z) and TileGroupManager and not TileGroupManager:IsInvalidTile(TheWorld.Map:GetTileAtPoint(x, 0, z)) and TheWorld.Map:GetPlatformAtPoint(x, z) == nil
            if not overwater or (health and health.invincible) or not (drownable and drownable.enabled) then
                c_teleport(x, 0, z)
                if player.SnapCamera then
                    player:SnapCamera()
                end
            end
            ]]
        return string.format("local x, z = %d, %d;", x, z) .. command_str
    end
    local function DoTeleport(x, z)
        if TheWorld and TheWorld.ismastersim then
            ExecuteConsoleCommand(get_teleport_command_str(x, z))
        else
            TheNet:SendRemoteExecute(get_teleport_command_str(x, z), x, z)
        end
    end

    local old_OnControl = self.OnControl
    self.OnControl = function (self, control, down)
        local is_trigger_clicked, is_additional_travel = CheckClickedAndGetTravelType(control)
        
        if down and GetCurrentTime()-self.lastactive_time > VALIDCLICK_TIME_THRESHOLD and is_trigger_clicked then
            local current_click_time = GetCurrentTime()
            local current_click_pos = TheInput:GetScreenPosition()
            local topscreen = TheFrontEnd:GetActiveScreen()
            if topscreen and topscreen.GetWorldPositionAtCursor ~= nil then
                local x, _, z = topscreen:GetWorldPositionAtCursor()
                local LMBaction, RMBaction = nil, nil
                if self.UpdateMapActions then
                    LMBaction, RMBaction = self:UpdateMapActions(x, 0, z)
                end
                local travelled = false
                if not TheInput:ControllerAttached()  
                        and (current_click_time - self.lastrightclick_time < DBCLICK_TIME_THRESHOLD and current_click_pos:Dist(self.lastrightclick_pos) < DBCLICK_DIST_THRESHOLD) then
                    
                    if TheNet:GetIsServerAdmin() and MapTeleportCheatEnabled() then
                        ThePlayer.components.ngl_pathfollower:ForceStop()
                        ThePlayer:DoTaskInTime(0.5, function() DoTeleport(x, z)  end)
                    end
                else 
                    if ThePlayer.components.ngl_pathfollower and CanOverrideMapAction(RMBaction) then
                        local target_pos = Vector3(x, 0, z)
                        if TheInput:IsControlPressed(CONTROL_FORCE_ATTACK) then
                             ThePlayer.components.ngl_pathfollower:CheckPath(target_pos)
                        else
                             ThePlayer.components.ngl_pathfollower:Travel(target_pos, is_additional_travel)
                        end
                        travelled = true
                    end
                end
                self.lastrightclick_time = current_click_time
                self.lastrightclick_pos = current_click_pos
                if not travelled then
                    return old_OnControl and old_OnControl(self, control, down)
                else
                    return true
                end
            end
        else 
            return old_OnControl and old_OnControl(self, control, down)
        end
    end
end

local function AddPathWidgets(self)
    if self.WorldPosToScreenPos == nil then
        self.WorldPosToScreenPos = WorldPosToScreenPos
    end
    
    self.paintWidget = self:AddChild(Widget("PaintWidget"))
    
    local ui_settings_str = GetModConfigData("UI_DISPLAY")
    local pathline_enabled = ui_settings_str == "Both" or ui_settings_str == "PathLine"
    local desticon_enabled = ui_settings_str == "Both" or ui_settings_str == "DestIcon"
    if pathline_enabled then
        self.pathLineGroup = self.paintWidget:AddChild(PathLineGroup(self,line_xml,line_texName))
        self.pathLineGroup:SetLineTint(1,1,1,0.8)
        self.pathLineGroup:SetLineDefaultHeight(40)
    end
    
    if desticon_enabled then
        self.destIconImage = self.paintWidget:AddChild(DestIcon(self,icon_xml,icon_texName))
        self.destIconImage:SetDefaultScale(0.7)
    end

    self.outlineWidgets = {}
    self.outline_last_zoom = -1
    self.outline_last_ref_x = -99999
    self.outline_last_ref_y = -99999

    local function ClearOutlines()
        for _, w in ipairs(self.outlineWidgets) do w:Kill() end
        self.outlineWidgets = {}
    end

    local function GenerateOutlines()
        ClearOutlines()
        if not ThePlayer or not ThePlayer.components.ngl_pathfollower then return end
        if not ThePlayer.components.ngl_pathfollower.outlines_visible then return end
        
        local segments = ThePlayer.components.ngl_pathfollower.island_outlines
        if not segments then return end

        for _, seg in ipairs(segments) do
            local line = self.paintWidget:AddChild(Image(line_xml, line_texName))
            line:SetVRegPoint(ANCHOR_MIDDLE)
            line:SetHRegPoint(ANCHOR_LEFT)
            
            local c = COLORS[seg.type] or COLORS.MAINLAND
            line:SetTint(c[1], c[2], c[3], c[4])
            
            line.world_p1 = seg.p1
            line.world_p2 = seg.p2
            
            table.insert(self.outlineWidgets, line)
        end
        self.outline_last_zoom = -1 
    end

    self.paintWidget.OnUpdate = function(dt)
        if not self.shown then return end
        
        local current_zoom = self.minimap:GetZoom()
        local ref_x, ref_y = self:WorldPosToScreenPos(0, 0)
        local sw, sh = TheSim:GetScreenSize()
        
        -- PERFORMANCE THROTTLE:
        -- Don't recalculate if map moved less than 10 pixels and zoom hasn't changed
        local dist_sq = (ref_x - self.outline_last_ref_x)^2 + (ref_y - self.outline_last_ref_y)^2
        if current_zoom == self.outline_last_zoom and dist_sq < 100 then
            return
        end
        
        self.outline_last_zoom = current_zoom
        self.outline_last_ref_x = ref_x
        self.outline_last_ref_y = ref_y
        
        local thickness = 20 / math.pow(current_zoom, 0.5)
        local rad_to_deg = 180 / math.pi
        local sqrt = math.sqrt
        local atan2 = math.atan2
        
        for _, w in ipairs(self.outlineWidgets) do
            local s_p1_x, s_p1_y = self:WorldPosToScreenPos(w.world_p1.x, w.world_p1.z)
            
            -- Simple Culling
            if (s_p1_x > -100 and s_p1_x < sw + 100 and s_p1_y > -100 and s_p1_y < sh + 100) then
                if not w:IsVisible() then w:Show() end
                
                local s_p2_x, s_p2_y = self:WorldPosToScreenPos(w.world_p2.x, w.world_p2.z)
                local dx, dy = s_p2_x - s_p1_x, s_p2_y - s_p1_y
                local len = sqrt(dx*dx + dy*dy)
                local angle = -atan2(dy, dx) * rad_to_deg

                w:SetPosition(s_p1_x, s_p1_y)
                w:SetRotation(angle)
                w:SetSize(len, thickness)
            else
                if w:IsVisible() then w:Hide() end
            end
        end
    end
    
    self.paintWidget:StartUpdating()

    if ThePlayer then
        self.inst:ListenForEvent("ngl_outlines_generated", GenerateOutlines, ThePlayer)
        self.inst:ListenForEvent("ngl_outlines_cleared", ClearOutlines, ThePlayer)
        self.inst:ListenForEvent("ngl_outlines_toggle", GenerateOutlines, ThePlayer)
        
        if ThePlayer.components.ngl_pathfollower.island_outlines and ThePlayer.components.ngl_pathfollower.outlines_visible then
            GenerateOutlines()
        end
    end
end

AddClassPostConstruct("widgets/mapwidget", AddPathWidgets)

local maps_trigger_str = GetModConfigData("MAPS_TRIGGER")
local mainmap_enabled = (maps_trigger_str == "Both") or (maps_trigger_str == "MainMap")

if mainmap_enabled then
    AddClassPostConstruct("screens/mapscreen", AddAutoMoveTrigger)
end