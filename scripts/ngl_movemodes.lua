-- 移动模式，具体在locomotor的Update里触发
-- 左键点击模式：RPC.LEFTCLICK，最后调用服务器端的locomotor:GoToPoint()，会触发官方的寻路，但当鼠标上附带物品时，由于左键动作变为Drop不再是WalkTo，无法移动
-- 直线行走模式：RPC.DirectWalk,在playercontroller:OnUpdate中调用服务器端的locomotor:MoveInDirection()，仅直走
-- 划船模式
-- 掌舵模式
local MOVEMODES = {
	-- WALKING
	DIRECTWALK = 	{name = "directwalk", 	priority = 0, check_offtrack = true, 	is_boat_movement = false}, 	-- via Remote Call locomotor:MoveInDirection()
	LEFTCLICK = 	{name = "leftclick",	priority = 1, check_offtrack = false, 	is_boat_movement = false},  -- via Remote Call locomotor:GoToPoint(), ACTONS.WALKTO actually
	-- SAILING
	ROWBOAT = 		{name = "rowboat", 		priority = 2, check_offtrack = false,	is_boat_movement = true},	-- via Do ACTIONS.ROW
	STEERBOAT = 	{name = "steerboat", 	priority = 3, check_offtrack = true,	is_boat_movement = true},	-- via Do ACTIONS.SteerBoat
}

local FORCESTOP_OFFSET = 2
local DASH_DIST = 7
local function Walter_CheckAndKeepSprint(self, target_pos)
	local inst = self.inst
	local my_pos = inst:GetPosition()
	if target_pos == my_pos then return end
	local dir, dist = (target_pos - my_pos):GetNormalizedAndLength()

	local dblclickact = inst.components.playeractionpicker and inst.components.playeractionpicker:GetDoubleClickActions(nil, dir, nil)[1]
	local skilltreeupdater = inst.components.skilltreeupdater
	if dist > DASH_DIST and -- do not dash when the dist to target below the dash dist
		dblclickact and dblclickact.action == ACTIONS.DASH and skilltreeupdater:IsActivated("walter_woby_lunar") and inst.woby_commands_classified:ShouldSprint() -- can lunar sprint
			and not (inst:HasTag("force_sprint_woby") or inst.AnimState:IsCurrentAnimation("sprint_woby_loop") or inst.AnimState:IsCurrentAnimation("sprint_woby_pst")) then -- not prepare to sprint / in sprinting
		self:SendAction(dblclickact, false, true)
		
		--- debug 
		-- local _, anim = inst.AnimState:GetHistoryData()
		-- print(anim)
	end
end

-- DIRECTWALK
MOVEMODES.DIRECTWALK.pick_movemode_fn = function(self)
	return true
end
MOVEMODES.DIRECTWALK.check_canmove_fn = function(self)
	local inst = self.inst
	local in_working = inst.components.playercontroller and inst.components.playercontroller:IsDoingOrWorking() or false
	local can_move = not (inst:HasTag("busy") or in_working)
	-- so directwalk will not be interrupted by other actions, we have to do it manually
	-- this helps to make player stop so that player can do their working (e.g. crafting)
	if self:GetLocomotor() == nil and MOVEMODES.DIRECTWALK.check_shouldresume_fn(self) then
		if not self.directwalk_interrupted then
			MOVEMODES.DIRECTWALK.on_stop_fn(self)
			self.directwalk_interrupted = true
			-- print("interrupted manually")
		end
	else
		self.directwalk_interrupted = false
	end
	return can_move
end
MOVEMODES.DIRECTWALK.check_shouldresume_fn = function(self)
	return not self.inst:HasTag("moving")
end
MOVEMODES.DIRECTWALK.on_move_fn = function(self, pos)
	local cur_pos = self:GetCurrentPos()
	cur_pos.y = 0
	pos.y = 0
	if cur_pos == pos then return end
	local normalized_dir = (pos - cur_pos):GetNormalized()
	local locomotor = self:GetLocomotor()
	if locomotor then	--lag compensation ON
		locomotor:RunInDirection(-math.atan2(normalized_dir.z, normalized_dir.x) / DEGREES)
	else	--lag compensation OFF
		SendRPCToServer(RPC.DirectWalking, normalized_dir.x, normalized_dir.z) -- actually it call locomotor:MoveInDirection in dedicated server
	end
	Walter_CheckAndKeepSprint(self, pos)
end
MOVEMODES.DIRECTWALK.on_stop_fn = function(self)
	local locomotor = self:GetLocomotor()
	if locomotor then
		locomotor:Stop()
		locomotor:Clear()
	else
		SendRPCToServer(RPC.StopWalking)
	end
end

-- LEFTCLICK
MOVEMODES.LEFTCLICK.pick_movemode_fn = function(self)
	-- if has locomotor
	if self:GetLocomotor() == nil then
		-- if we use RPC.LeftClick, we should guarantee the dest in range of RPC
		local dest_outofrange = self.path == nil and self.dest and self.inst:GetPosition():DistSq(self.dest) > 4096
		-- when Lag Compension OFF and we have active_item , the left action is DROP but not WALKTO,which cause fail to handle LEFTCLICK RPC
		-- so use DIRECTWALK rpc instead
		local active_item = self.inst.replica.inventory and self.inst.replica.inventory:GetActiveItem() or nil
		if dest_outofrange or active_item ~= nil then
			return false
		end
	end
	-- locomotor默认是 allowocean = false, ignorewalls = false,
	-- 如果我们通过Physics计算得到的pathcaps能跨海或者穿墙 和locomotor的默认pathcaps不一致时，在左键点击下的移动会触发locomotor的寻路导致不必要的绕道
	local pathcaps = self:GetPathCaps(true)
	local less_detour_pathcaps = pathcaps ~= nil and (pathcaps.allowocean or pathcaps.ignorewalls)
	if less_detour_pathcaps then
		return false
	end
	return true
end
MOVEMODES.LEFTCLICK.check_canmove_fn = function(self)
	local inst = self.inst
	local in_working = inst.components.playercontroller and inst.components.playercontroller:IsDoingOrWorking() or false
	local can_move = not (inst:HasTag("busy") or in_working)
	return can_move
end
MOVEMODES.LEFTCLICK.check_shouldresume_fn = function(self)
	-- it could be something wrong that we can't move, klei plz fix it so that no need handle bug manually
	-- e.g: https://forums.kleientertainment.com/klei-bug-tracker/dont-starve-together/clicking-previous-point-doesnt-work-after-you-get-knocked-back-in-autowalking-r44639/
	local is_moving = self.inst:HasTag("moving")
	if not is_moving and self:GetLocomotor() == nil then
		self:MoveTo(self.inst:GetPosition())
	end
	return not is_moving
end
MOVEMODES.LEFTCLICK.on_move_fn = function(self, pos)
	local locomotor = self:GetLocomotor()
	if locomotor then	--lag compensation ON
		local buffered_action = BufferedAction(self.inst, nil, ACTIONS.WALKTO)
		locomotor:GoToPoint(pos, buffered_action, true)
	else	--lag compensation OFF
		SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, pos.x, pos.z) -- actually it call locomotor:GoToPoint in dedicated server
	end
	Walter_CheckAndKeepSprint(self, pos)
end
MOVEMODES.LEFTCLICK.on_stop_fn = function(self)
	local locomotor = self:GetLocomotor()
	if locomotor then
		locomotor:Stop()
		locomotor:Clear()
	else
		-- stupid code to stop via leftclick the pos we front-facing
		local angle = self.inst:GetRotation() * DEGREES -- angle to target_pos or facing
		local offset_x, offset_z = math.cos(angle) * FORCESTOP_OFFSET, -math.sin(angle) * FORCESTOP_OFFSET
		local my_x, _, my_z = self.inst:GetPosition():Get()
		SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, my_x + offset_x, my_z + offset_z)
	end
end

--STEERBOAT
local MAGIC_NUMBER = 2.5
local STEER_CD = 5 * FRAMES
MOVEMODES.STEERBOAT.pick_movemode_fn = function(self)
	return self.inst:GetCurrentPlatform() ~= nil and self.inst:HasTag("steeringboat")
end
MOVEMODES.STEERBOAT.check_canmove_fn = function(self)
	local now_time = GetTime()
	if self.last_steer_time == nil or self.last_steer_time + STEER_CD < now_time then
		self.last_steer_time = now_time
		local cur_pos = self:GetCurrentPos()
		self.boat_vel = (cur_pos - (self.boat_pos or cur_pos)) / STEER_CD
		self.boat_pos = cur_pos
		return true
	end
	return false
end

MOVEMODES.STEERBOAT.on_move_fn = function(self, pos)
	local cur_pos = self:GetCurrentPos()
	cur_pos.y = 0
	pos.y = 0
	if cur_pos == pos then return end
	local vel = self.boat_vel or Vector3(0,0,0)
	local normalized_dir = (pos - cur_pos - vel*MAGIC_NUMBER):GetNormalized()
	local steeringwheeluser = self.inst.components.steeringwheeluser
	if steeringwheeluser ~= nil then
		steeringwheeluser:SteerInDir(normalized_dir.x, normalized_dir.z)
	else
		SendRPCToServer(RPC.SteerBoat, normalized_dir.x, normalized_dir.z)
	end
end
MOVEMODES.STEERBOAT.on_stop_fn = function(self)
	-- local buffered_action = BufferedAction(self.inst, nil, ACTIONS.STOP_STEERING_BOAT, nil, self.inst:GetPosition())
	-- self:SendAction(buffered_action)
end

-- ROWBOAT
local ROW_CD = 16 * FRAMES
MOVEMODES.ROWBOAT.pick_movemode_fn = function(self)
	local boat = self.inst:GetCurrentPlatform()
	if not (boat and boat:IsValid()) then return false end -- no boat
	
	local isriding =(self.inst.replica and self.inst.replica.rider and self.inst.replica.rider._isriding:value()) or
			(self.inst.components and self.inst.components.rider and self.inst.components.rider:IsRiding())
	if isriding then return false end -- can't row when riding
		
	local active_item = self.inst.replica.inventory and self.inst.replica.inventory:GetActiveItem() or nil
	if active_item ~= nil then return false end -- can't row when has active_item
	
	local hands_item = self.inst.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
	if not (hands_item and hands_item.HasActionComponent and hands_item:HasActionComponent("oar")) then return false end -- no oar
	-- or we can check row action by getrightclickactions ?
	
	return true
end
MOVEMODES.ROWBOAT.check_canmove_fn = function(self)
	local now_time = GetTime()
	if self.last_row_time == nil or self.last_row_time + ROW_CD < now_time then
		self.last_row_time = now_time
		local cur_pos = self:GetCurrentPos()
		self.boat_vel = (cur_pos - (self.boat_pos or cur_pos)) / ROW_CD
		self.boat_pos = cur_pos
		-- print(self.boat_vel)
		return MOVEMODES.LEFTCLICK.check_canmove_fn(self) or self.inst:HasTag("is_rowing")
	end
	return false
end
MOVEMODES.ROWBOAT.check_shouldresume_fn = function(self)
	return true
end
MOVEMODES.ROWBOAT.on_move_fn = function(self, pos)
	local cur_pos = self:GetCurrentPos()
	cur_pos.y = 0
	pos.y = 0
	if cur_pos == pos then return end
	local vel = self.boat_vel or Vector3(0,0,0)
	local normalized_dir = (pos - cur_pos - vel*MAGIC_NUMBER):GetNormalized() -- 马上靠近目标点时候减速
	local boat_radius = self.inst:GetCurrentPlatform() and self.inst:GetCurrentPlatform():GetPhysicsRadius() or 4
	local row_pos = cur_pos + normalized_dir * (boat_radius + 4)
	local oar = self.inst.replica.inventory and self.inst.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
	if oar and oar.HasActionComponent and oar:HasActionComponent("oar") then
		local buffered_action = BufferedAction(self.inst, nil, ACTIONS.ROW, oar, row_pos)
		self:SendAction(buffered_action, true) --rightclick
	end
end
MOVEMODES.ROWBOAT.on_stop_fn = function(self)
	self.boat_vel = nil
end


return MOVEMODES