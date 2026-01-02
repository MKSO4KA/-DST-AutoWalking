local interrupt_controls = {}

--the keys to stop the autowalking 
for control = CONTROL_ATTACK, CONTROL_MOVE_RIGHT do
    interrupt_controls[control] = true	 
end

local function IsInGame()
	return ThePlayer and ThePlayer.HUD
end

local function IsInTyping()
	return  ThePlayer.HUD:HasInputFocus()
end

local function IsInMap()
	return ThePlayer.HUD:IsMapScreenOpen()

end

local function IsCursorOnHUD()
	local input = TheInput
	return input.hoverinst and input.hoverinst.Transform == nil
end

local function CanMouseActionLocomote(self, right) 
	if TheInput:GetWorldEntityUnderMouse() == ThePlayer then return false end 
	if right and self.placer ~= nil then return false end 

	local bufferedaction
	if right then
		bufferedaction = self:GetRightMouseAction() 
	else
		bufferedaction = self:GetLeftMouseAction() or BufferedAction(self.inst, nil, ACTIONS.WALKTO, nil, TheInput:GetWorldPosition())
	end
	
	if bufferedaction and
		(not (bufferedaction.action.instant or bufferedaction.action.do_not_locomote or bufferedaction.options.instant)	
		or bufferedaction.action == ACTIONS.WALKTO) then
		return true
	end

	return false
end

-- [NEW] Global Scanner Hotkeys
local function AddGlobalScannerKey(self)
    local key_toggle = GetModConfigData("KEY_TOGGLE_SCAN") or KEY_F9
    local key_rescan = GetModConfigData("KEY_FORCE_RESCAN") or KEY_F10
    
    local function HandleScannerInput(key)
        if not IsInGame() or IsInTyping() then return end
        if not (ThePlayer and ThePlayer.components.ngl_pathfollower) then return end
        
        if key == key_toggle then
            local pf = ThePlayer.components.ngl_pathfollower
            if pf.island_outlines == nil then
                -- No data, start scan
                pf.outlines_visible = true
                pf:ToggleIslandOutlines()
            else
                -- Has data, just toggle visibility
                pf.outlines_visible = not pf.outlines_visible
                if pf.outlines_visible then
                     -- Show
                     ThePlayer:PushEvent("ngl_outlines_toggle")
                     if ThePlayer.components.talker then ThePlayer.components.talker:Say("Biomes Shown") end
                else
                     -- Hide (Don't delete data!)
                     ThePlayer:PushEvent("ngl_outlines_cleared")
                     if ThePlayer.components.talker then ThePlayer.components.talker:Say("Biomes Hidden") end
                end
            end
            
        elseif key == key_rescan then
            local pf = ThePlayer.components.ngl_pathfollower
            pf.island_outlines = nil
            pf.outlines_visible = true
            pf:ToggleIslandOutlines() -- Rescan
        end
    end

    TheInput:AddKeyUpHandler(key_toggle, function() HandleScannerInput(key_toggle) end)
    TheInput:AddKeyUpHandler(key_rescan, function() HandleScannerInput(key_rescan) end)
end

AddComponentPostInit("playercontroller",function(self)
    -- Register Keys
    AddGlobalScannerKey(self)

	local OnControl_old = self.OnControl
	 self.OnControl = function(self, control, down)
	 
		local pathfollower = ThePlayer and ThePlayer.components.ngl_pathfollower
		local should_ignore_control = down and self._hack_ignore_held_controls or (not down and self._hack_ignore_ups_for and self._hack_ignore_ups_for[control])
		if not should_ignore_control and pathfollower and pathfollower:HasDest() and IsInGame() then		
			
			if not IsInMap() and not IsInTyping() and interrupt_controls[control] then
				pathfollower:ForceStop()
			elseif IsInMap() and control == CONTROL_ACTION then
				pathfollower:ForceStop()
			elseif not IsInMap() and not IsInTyping() and not IsCursorOnHUD() and (control == CONTROL_PRIMARY or control == CONTROL_SECONDARY)
				and CanMouseActionLocomote(self, control == CONTROL_SECONDARY) then
				pathfollower:ForceStop()
			end
		end
		return OnControl_old(self, control, down)
	end
	
	local OnMapAction_old = self.OnMapAction
	self.OnMapAction = function(self, actioncode, ...)
		local action = actioncode and ACTIONS_BY_ACTION_CODE[actioncode]
		if action and action.map_action then
			local pathfollower = ThePlayer and ThePlayer.components.ngl_pathfollower
			if pathfollower then
				pathfollower:ForceStop()
			end
		end
		return OnMapAction_old(self, actioncode, ...)
	end
end)