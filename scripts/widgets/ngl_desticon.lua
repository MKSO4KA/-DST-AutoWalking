local Text = require "widgets/text"
local Image = require "widgets/image"
local Widget = require "widgets/widget"

local updateFns = {
    MapWidget = function(self, dest)
        if dest == nil then
            return
        end
        local mapwidget = self.mapwidget
        local zoom = mapwidget.minimap:GetZoom()
        local screen_x, screen_y = mapwidget:WorldPosToScreenPos(dest.x, dest.z)
        self:SetPosition(screen_x, screen_y, 0)
        self:SetScale(self.default_scale / math.pow(zoom, 0.5))
    end,
    
    MiniMapWidget = function(self, dest)
        if dest == nil then
            return
        end
        
        local minimapwidget = self.mapwidget
        local img = minimapwidget.img
        local img_w, img_h = img:GetSize()

        local zoom = minimapwidget.minimap:GetZoom()
        local screen_x, screen_y = minimapwidget:WorldPosToScreenPos(dest.x, dest.z)
        self:SetPosition(screen_x, screen_y, 0)
        self:SetScale(self.default_scale / math.pow(zoom , 0.5) * minimapwidget.uvscale)
    end,
    
    SmallMap = function(self, dest)
        if dest == nil then
            return
        end
        
        local smallmap = self.mapwidget
        local img = smallmap.img
        local img_w, img_h = img:GetSize()

        local zoom = smallmap.minimap:GetZoom()
        local screen_x, screen_y = smallmap:WorldPosToScreenPos(dest.x, dest.z)
        self:SetPosition(screen_x, screen_y, 0)
        self:SetScale(self.default_scale / math.pow(zoom , 0.5) * smallmap.uvscale.x)
    end
}


local DestIcon = Class(Image, function(self, mapwidget, atlas, tex)
    Image._ctor(self, atlas, tex, tex)
    self.tint = {1,1,1,1}
    self.mapwidget = mapwidget
    self.default_scale = Vector3(1,1,1)
    self:SetVRegPoint(ANCHOR_MIDDLE)
    self:SetHRegPoint(ANCHOR_MIDDLE)
    self.UpdateIconPosition = mapwidget and updateFns[mapwidget.name] or nil
    
    if self.UpdateIconPosition then
        self:StartUpdating()
    end
end)

function DestIcon:SetDefaultScale(pos, y, z)
    if type(pos) == "number" then
        self.default_scale = Vector3(pos, y or pos, z or pos)
    else
        self.default_scale = Vector3(pos.x,pos.y,pos.z)
    end
    self:SetScale(self.default_scale)
end

function DestIcon:OnUpdate(dt)
    local pathfollower = ThePlayer and ThePlayer.components.ngl_pathfollower
    local dest = pathfollower and pathfollower.dest

    -- no dest
    if dest == nil then
        -- dont show if no dest
        if self:IsVisible() then
            self:Hide()
        end
        return
    end

    -- has dest
    -- update icon position if dest exists
    if not self:IsVisible() then
        self:Show()
    end
    self:UpdateIconPosition(dest)

    -- [MODIFIED] Colorize based on check status
    if pathfollower then
        if pathfollower.check_status == true then
            self:SetTint(0.3, 1, 0.3, 1) -- GREEN (Valid Path)
        elseif pathfollower.check_status == "ISOLATED" then
            self:SetTint(1, 0.8, 0, 1)   -- YELLOW (Land found, but isolated)
        elseif pathfollower.check_status == false then
            self:SetTint(1, 0.3, 0.3, 1) -- RED (No Path/Water)
        else
            self:SetTint(1, 1, 1, 1)     -- WHITE (Normal / Calculating)
        end
    end
end

return DestIcon