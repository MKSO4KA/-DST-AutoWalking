local PathLineGroup = require "widgets/ngl_pathlinegroup"
local DestIcon = require "widgets/ngl_desticon"
local Widget = require "widgets/widget"

local ROT_REPEAT = .25

local function DoRotate(right)
    local rotamount = right and 45 or -45
    if not IsPaused() then
        TheCamera:SetHeadingTarget(TheCamera:GetHeadingTarget() + rotamount)
    end
end

local function AddRotForMinimap(self)
    local old_OnControl = self.OnControl
    self.OnControl = 
        function (self, control, down)
            local isenabled, ishudblocking = ThePlayer.components.playercontroller:IsEnabled()
            if not isenabled and not ishudblocking then
                return
            end
            
            local time = os.clock() 
            local invert_rotation = Profile:GetInvertCameraRotation()
            if  self.lastrottime == nil or time - self.lastrottime > ROT_REPEAT then    
                if control == CONTROL_ROTATE_LEFT or control == CONTROL_ROTATE_RIGHT then
                    DoRotate(control == (invert_rotation and CONTROL_ROTATE_LEFT or CONTROL_ROTATE_RIGHT))
                    self.lastrottime = time
                end
            end
            if old_OnControl then
                return old_OnControl(self, control, down)
            end
        end

end

local function AddResetKeyForMinimap(self)
    local old_OnMouseButton = self.OnMouseButton
    self.OnMouseButton = 
        function (self, button, down, x, y)
            if button == MOUSEBUTTON_MIDDLE and down and self.minimap then
                self.minimap:ResetOffset()
            end
            
            if old_OnMouseButton ~= nil then
                return old_OnMouseButton(self, button, down, x, y)
            end
            return true
        end
end

local function MiniMapWidget_GetMapPosition(self)
    if not self.img then return 0, 0 end
    
    local x_cursor, y_cursor = TheSim:GetPosition()
    local x_widgetcenter, y_widgetcenter = self.img:GetWorldPosition():Get()
    local w, h = self.img:GetSize()
    local scale = self.img:GetScale()
    
    if scale.x == 0 or scale.y == 0 then return 0, 0 end

    local uvscale = self.uvscale or 1 
    local x = (x_cursor - x_widgetcenter)*(2-uvscale)/scale.x + w/2
    local y = (y_cursor - y_widgetcenter)*(2-uvscale)/scale.y + h/2

    x = 2 * x / w - 1
    y = 2 * y / h - 1
    return x, y
end

local function MiniMapWidget_GetWorldPositionAtCursor(self)
    if not self.minimap then return 0,0,0 end
    local x, y = self:GetCursorPosition()
    x, y = self.minimap:MapPosToWorldPos(x, y, 0)
    return x, 0, y 
end

local function MiniMapWidget_WorldPosToScreenPos(self, x, z)
    if not self.minimap or not self.img then return 0, 0 end

    local map_x, map_y = self.minimap:WorldPosToMapPos(x, z, 0)
    
    local w, h = self.img:GetSize()
    local scale = self.img:GetScale()
    local uvscale = self.uvscale or 1

    local map_x = map_x * w * scale.x /(2 - uvscale)/ 2
    local map_y = map_y * h * scale.y /(2 - uvscale)/ 2
    
    if scale.x == 0 or scale.y == 0 then return 0, 0 end

    local screen_x = map_x /scale.x
    local screen_y = map_y /scale.y 
    
    return screen_x, screen_y
end

local function MiniMapWidget_OnShow(self)
    if self:IsOpen() then
        self:EnableMinimapUpdating()
    end
    if self.mapscreenzoom and self.minimap then
        self.minimap:Zoom(self.mapscreenzoom + 0.75 - self.minimap:GetZoom())
        self.minimapzoom = self.mapscreenzoom + 0.75
        self.minimap:ResetOffset()
    end
end

local MINIMAP_TEMP_IGNORE_RESET = false
local function AddOnShowPatch(self)
    local minimap = self.minimap and getmetatable(self.minimap).__index  
    if minimap then
        local old_Zoom = minimap.Zoom
        minimap.Zoom = function(self, ...)
            if MINIMAP_TEMP_IGNORE_RESET then
                return 
            end
            return old_Zoom and old_Zoom(self, ...)
        end
        local old_ResetOffset = minimap.ResetOffset
        minimap.ResetOffset = function(self, ...)
            if MINIMAP_TEMP_IGNORE_RESET then
                return 
            end
            return old_ResetOffset and old_ResetOffset(self, ...)
        end
    end
    local old_OnShow = self.OnShow
    self.OnShow = function (self, was_hidden, ...)
        MINIMAP_TEMP_IGNORE_RESET = was_hidden
        local ret = old_OnShow(self, was_hidden, ...)
        MINIMAP_TEMP_IGNORE_RESET = false
        return ret
    end
end

local function AddAutoMoveTriggerForMiniMap(self)
    local old_OnControl = self.OnControl
    self.OnControl = function (self, control, down)
        if CheckClickedAndGetTravelType then
            local is_trigger_clicked, is_additional_travel = CheckClickedAndGetTravelType(control)
            if is_trigger_clicked and down then     
                local topscreen = TheFrontEnd:GetActiveScreen()
                if topscreen == ThePlayer.HUD then
                    if self.minimap ~= nil then
                        local x, _, z = self:GetWorldPositionAtCursor()
                        local target_pos = Vector3(x, 0, z)
                        if ThePlayer.components.ngl_pathfollower then
                            if TheInput:IsControlPressed(CONTROL_FORCE_ATTACK) then
                                ThePlayer.components.ngl_pathfollower:CheckPath(target_pos)
                            else
                                ThePlayer.components.ngl_pathfollower:Travel(target_pos, is_additional_travel)
                            end
                        end
                    end
                end
                return true 
            end
        end
        
        return old_OnControl and old_OnControl(self, control, down)
    end
end
    
local function AddPathWidgetsForMiniMap(self, pathline_enabled, desticon_enabled)
    if not self.img then return end

    self.paintWidget = self.img:AddChild(Widget("PaintWidget"))
    
    -- [CRITICAL FIX] Use self.img:GetSize() instead of non-existent self.mapsize
    local w, h = self.img:GetSize()
    self.paintWidget:SetScissor(-w/2, -h/2, w, h)
    
    ------------------------SHOW PATH LINES-----------------------------
    -- Only show standard path lines (for auto-walking), NO island outlines here
    if pathline_enabled then
        self.pathLineGroup = self.paintWidget:AddChild(PathLineGroup(self,line_xml,line_texName))
        self.pathLineGroup:SetLineTint(1,1,1,0.8)
        self.pathLineGroup:SetLineDefaultHeight(15)
    end
        
    -----------------------SHOW DEST ICON------------------------------
    if desticon_enabled then
        self.destIconImage = self.paintWidget:AddChild(DestIcon(self,icon_xml,icon_texName))
        self.destIconImage:SetDefaultScale(0.2)
    end
end

------------------------------APPLY-------------------------------
local maps_trigger_str = GetModConfigData("MAPS_TRIGGER")
local patch_enabled = GetModConfigData("PATCH_MINIMAP")
local minimap_trigger_enabled = (maps_trigger_str == "Both") or (maps_trigger_str == "MiniMap")

local ui_settings_str = GetModConfigData("UI_DISPLAY")
local pathline_enabled = ui_settings_str == "Both" or ui_settings_str == "PathLine"
local desticon_enabled = ui_settings_str == "Both" or ui_settings_str == "DestIcon"

AddClassPostConstruct("widgets/minimapwidget",
    function(self)
        self.GetCursorPosition = MiniMapWidget_GetMapPosition
        self.GetWorldPositionAtCursor = MiniMapWidget_GetWorldPositionAtCursor
        self.WorldPosToScreenPos = MiniMapWidget_WorldPosToScreenPos
        
        if minimap_trigger_enabled then
            AddAutoMoveTriggerForMiniMap(self)
        end
        
        AddPathWidgetsForMiniMap(self, pathline_enabled, desticon_enabled)
        
        AddRotForMinimap(self)
        AddResetKeyForMinimap(self)
        
        if patch_enabled then 
            AddOnShowPatch(self)
        end
end)