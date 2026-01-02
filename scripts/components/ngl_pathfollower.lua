--------------------------------------------------------------------------
-- [IMPORTS]
--------------------------------------------------------------------------
local Common = require("ngl_common")
local Scanner = require("ngl_scanner")
local MOVEMODES = require("ngl_movemodes")

--------------------------------------------------------------------------
-- [SETUP & LOCAL ALIASES]
--------------------------------------------------------------------------
local BitAND = Common.BitAND
local StepToVector3 = Common.StepToVector3
local Vector3ToStep = Common.Vector3ToStep
local IsValidPath = Common.IsValidPath
local GetTileName = Common.GetTileName or function() return "Unknown" end -- [FIXED] Fallback to prevent crash
local IsSailingMoveMode = Common.IsSailingMoveMode
local GetArriveStep = Common.GetArriveStep
local GetDistFromPointToLine = Common.GetDistFromPointToLine

local insert = table.insert
local remove = table.remove

-- Prepare MoveModes Array
local MOVEMODES_ARRAY = {}
for k,v in pairs(MOVEMODES) do 
    table.insert(MOVEMODES_ARRAY, {mode = k, fn = v.pick_movemode_fn, priority = v.priority}) 
end
table.sort(MOVEMODES_ARRAY, function(a,b) return a.priority > b.priority end)

-- Helpers for SetPathfinder
local function is_implemented_required_interfaces(pathfinder_cmp)
    return (pathfinder_cmp.SubmitSearch and pathfinder_cmp.GetSearchStatus and pathfinder_cmp.GetSearchResult and pathfinder_cmp.KillSearch and pathfinder_cmp.SetMaxTime) ~= nil
end

local function get_pathfinder_component(pathfinder, inst)
    local pathfinder_cmp = nil
    if type(pathfinder) == "string" and inst.components[pathfinder] then
        pathfinder_cmp = inst.components[pathfinder]
    elseif type(pathfinder) == "table" then
        pathfinder_cmp = pathfinder
    end
    return pathfinder_cmp
end

--------------------------------------------------------------------------
-- [CLASS DEFINITION]
--------------------------------------------------------------------------
local PathFollower = Class(function(self, inst)
    self.inst = inst
    
    self.dest = nil
    self.path = nil
    self.pathfinder = self.inst.components.fusedpathfinder
    
    -- Subsearch (Dynamic adjustment)
    -- Note: We assume ngl_pathfinder is added to player in modmain
    self.subsearch_pathfinder = self.inst.components.ngl_pathfinder 
    self.subsearch_enabled = true
    self.subsearch_info = {startstep = nil, endstep = nil} 
    self.allow_pathfinding_fog_of_war = false
    
    -- Check mode
    self.is_checking_only = false
    self.check_status = nil 

    -- Scanner
    self.island_outlines = nil 
    self.outlines_visible = false
    self.scan_task = nil
    
    self.pathcaps = {}
    self.groundcaps = {speed_on_road = 0}
end)

--------------------------------------------------------------------------
-- [PERSISTENCE]
--------------------------------------------------------------------------
function PathFollower:OnSave()
    return {
        island_outlines = self.island_outlines,
        outlines_visible = self.outlines_visible
    }
end

function PathFollower:OnLoad(data)
    if data then
        self.island_outlines = data.island_outlines
        self.outlines_visible = data.outlines_visible
    end
end

--------------------------------------------------------------------------
-- [SCANNER INTERFACE]
--------------------------------------------------------------------------
function PathFollower:ToggleIslandOutlines()
    -- If outlines exist, logic in playercontroller handles visibility toggling.
    -- If this function is called, it triggers a new scan process.

    if self.scan_task then 
        if self.inst.components.talker then
            self.inst.components.talker:Say("Scanning in progress...")
        end
        return 
    end

    if self.inst.components.talker then
        self.inst.components.talker:Say("Scanning map biomes...")
    end

    self.scan_task = self.inst:StartThread(function()
        Scanner.Execute(self.inst, self)
        self.scan_task = nil
    end)
end

--------------------------------------------------------------------------
-- [PATHFINDING HELPERS]
--------------------------------------------------------------------------
local function SplitPathInRange(self, path, range, start_index, end_index)
    local start_idx = math.max(1, start_index or 1)
    local end_idx = math.min(#(path.steps), end_index or #(path.steps))
    local idx = start_idx + 1
    
    while(idx <= math.min(end_idx, #(path.steps))) do
        local pre = StepToVector3(path.steps[idx-1])
        local cur = StepToVector3(path.steps[idx])
        if pre:DistSq(cur) > range*range + 4 then
            local inrange_pos = (cur - pre):GetNormalized() * range + pre
            insert(path.steps, idx, Vector3ToStep(inrange_pos))
            end_idx = end_idx + 1
        else
            idx = idx + 1
        end
    end
    return path
end

local function CheckAndGetSearchResult(self, is_subsearch)
    local pathfinder = is_subsearch and self.subsearch_pathfinder or self.pathfinder
    local search_over, validpath = false, nil
    
    if not pathfinder then return true, nil end -- Error case

    local status = pathfinder:GetSearchStatus()
    
    if status ~= Common.STATUS.CALCULATING then
        search_over = true
        if status == Common.STATUS.FOUNDPATH then
            local foundpath = pathfinder:GetSearchResult()
            if IsValidPath(foundpath) then
                validpath = SplitPathInRange(self, foundpath, Common.MAX_STEP_DIST)
            end
        end
    end
    return search_over, validpath
end

local function PathSetNewFirstStep(self, path)
    if #path.steps > 0 then
        table.remove(path.steps, 1)
    end
    table.insert(path.steps, 1, Vector3ToStep(self:GetCurrentPos()))
    return SplitPathInRange(self, path, Common.MAX_STEP_DIST, 1, 2)
end

local function InsertSubPathToMainPath(self, path, subpath, start_index, end_index)
    local sub_maxsteps = #(subpath.steps)
    if sub_maxsteps > 2 then
        local steps = deepcopy(path.steps)
        if (end_index - start_index) > 1 then
            for i = end_index - 1, start_index + 1, -1 do
                remove(steps, i)
                end_index = end_index - 1
            end
        end
        for i = 2, sub_maxsteps - 1 do
            local step = subpath.steps[i]
            insert(steps, start_index + i - 1, step)
            end_index = end_index + 1
        end
        path.steps = steps
    end
    return path
end

--------------------------------------------------------------------------
-- [MOVEMENT & LOGIC]
--------------------------------------------------------------------------
function PathFollower:OnUpdate()
    self:TryToDoPathSearch()

    -- 1. SEARCHING PHASE
    if self.in_mainpathsearching then
        local search_over, foundpath = CheckAndGetSearchResult(self, false)
        
        if not search_over then 
            return 
        else 
            self:KillMainpathSearch() 
        end

        -- [MODE: CHECK ONLY]
        if self.is_checking_only then
            self.is_checking_only = false
            self.in_updating = false
            self.inst:StopUpdatingComponent(self)

            local dest = self.dest
            local tile_name = dest and GetTileName(dest.x, dest.z) or "Unknown"

            if foundpath and IsValidPath(foundpath) then
                self.check_status = true 
                foundpath = PathSetNewFirstStep(self, foundpath) 
                self.path = {steps = foundpath.steps, currentstep = 2} -- Fake path for visual

                if self.inst.components.talker then
                    local steps = #foundpath.steps
                    self.inst.components.talker:Say(string.format("Path found! (%d steps) [%s]", steps, tile_name))
                end
            else
                local is_land = dest and (TheWorld.Map:IsVisualGroundAtPoint(dest.x, 0, dest.z) or TheWorld.Map:GetTileAtPoint(dest.x, 0, dest.z) == WORLD_TILES.OCEAN_ICE)
                
                if is_land then
                    self.check_status = "ISOLATED" 
                    self.path = nil 
                    if self.inst.components.talker then
                        self.inst.components.talker:Say(string.format("Land detected! (Isolated) [%s]", tile_name))
                    end
                else
                    self.check_status = false
                    self.path = nil 
                    if self.inst.components.talker then
                        self.inst.components.talker:Say(string.format("No path. (Water/Void) [%s]", tile_name))
                    end
                end
            end
            return 
        end

        -- [MODE: TRAVEL]
        local final_path = foundpath
        local prev_path_not_existed = self.path == nil
        
        if final_path then
            if prev_path_not_existed then
                final_path = PathSetNewFirstStep(self, final_path)
                self.path = {steps = final_path.steps, currentstep = 2}
            else 
                -- Concatenate logic
                local existed_steps = deepcopy(self.path.steps)
                local currrentstep = self.path.currentstep
                remove(existed_steps) 
                for _, step in pairs(final_path.steps) do
                    insert(existed_steps, step)
                end
                self.path.steps = existed_steps
                self:MoveTo(StepToVector3(self.path.steps[currrentstep]))
            end
        else 
            -- No path found, direct walk
            self.path = nil
            self.search_queue = {}
            if self.dest then
                self:UpdateMoveMode()
                self:MoveTo(self.dest)
                self.inst:PushEvent("ngl_startdirectwalkwithnopath", {dest = self.dest})
            end
        end

        if prev_path_not_existed and self.path then 
            if self.debugmode then self:VisualizePath() end
            
            self:UpdateMoveMode()
            self:MoveTo(StepToVector3(self.path.steps[self.path.currentstep]))
            self.inst:PushEvent("ngl_startpathfollow", {path = self.path})
            
            -- Subsearch triggers could be added here
        end
    end 

    -- 2. FOLLOWING PHASE
    if self.path then
        self:FollowPath()
    else 
        self:DirectWalkWithNoPath()
    end
end

function PathFollower:FollowPath()
    if not self.path then return end
    self:UpdateMoveMode()

    local cur_pos = self:GetCurrentPos()
    cur_pos.y = 0
    local currentstep_pos = StepToVector3(self.path.steps[self.path.currentstep]) 
    
    local step_distsq = cur_pos:DistSq(currentstep_pos)
    local boat = self.inst:GetCurrentPlatform()
    local physdiameter = IsSailingMoveMode(self:GetMoveMode(true)) and boat
                            and boat:GetPhysicsRadius(0)*2
                            or self.inst:GetPhysicsRadius(0)*2
    step_distsq = step_distsq - physdiameter * physdiameter

    local arrive = GetArriveStep(self:GetLocomotor())
    
    if step_distsq <= arrive*arrive then 
        local maxsteps = #self.path.steps
        if self.path.currentstep < maxsteps then
            self.path.currentstep = self.path.currentstep + 1
            self.inst:PushEvent("ngl_startnextstep", {currentstep = self.path.currentstep})
            self:MoveTo(StepToVector3(self.path.steps[self.path.currentstep]))
        else
            self.inst:PushEvent("ngl_onreachdestination", {pos = self.dest})
            if self.atdestfn then self.atdestfn(self.inst) end
            self:ForceStop()
        end
    else 
        if self:ShouldResumeMoving() or self:IsOffTrack() then
            self:MoveTo(StepToVector3(self.path.steps[self.path.currentstep]))
        end
    end
end

function PathFollower:DirectWalkWithNoPath()
    local cur_pos = self:GetCurrentPos()
    cur_pos.y = 0
    local dest_distsq = cur_pos:DistSq(self.dest)
    self:UpdateMoveMode()
    
    if dest_distsq <= 4 then 
        self.inst:PushEvent("ngl_onreachdestination", {pos = self.dest})
        if self.atdestfn then self.atdestfn(self.inst) end
        self:ForceStop()
    elseif self:ShouldResumeMoving() then
        self:MoveTo(self.dest)
    end
end

--------------------------------------------------------------------------
-- [CORE INTERFACE]
--------------------------------------------------------------------------

function PathFollower:SetPathfinder(pathfinder)
    if pathfinder then
        local pathfinder_cmp = get_pathfinder_component(pathfinder, self.inst)
        if pathfinder_cmp and is_implemented_required_interfaces(pathfinder_cmp) then
            self.pathfinder = pathfinder_cmp
        else
            print("Pathfinder component not found or invalid interface")
        end
    end
end

function PathFollower:CheckPath(destPos)
    if not destPos then return end
    self:Clear()

    if destPos.IsVector3 and destPos:IsVector3() then
        if self.pathfinder then
            self.dest = destPos
            self.is_checking_only = true
            
            self:UpdatePathCaps()
            self:UpdateGroundCaps()
            self:AddToPathSearchQueue(self:GetCurrentPos(), destPos, self.pathcaps, self.groundcaps, false)
            
            self.inst:StartUpdatingComponent(self)
            self.in_updating = true
            
            if self.inst.components.talker then
                self.inst.components.talker:Say("Checking path...")
            end
        end
    end
end

function PathFollower:Travel(destPos, additional)
    if not destPos then return end
    
    if not additional then
        self:Clear()
        if self.inst.detect_interrupt_task then 
             self.inst.detect_interrupt_task:Cancel()
             self.inst.detect_interrupt_task = nil
        end
    end

    self.is_checking_only = false
    self.check_status = nil

    if destPos.IsVector3 and destPos:IsVector3() then 
        if self.pathfinder then
            local prev_dest = self.dest
            self.dest = destPos
            
            self:UpdatePathCaps()
            self:UpdateGroundCaps()
            
            self.inst:PushEvent("ngl_newdest", {dest = self.dest})
            if not additional then 
                TheWorld:PushEvent("ngl_pathfinding_change", {enabled = false}) 
            end
            
            local start_pos = (not self:DirectWalkingWithNoPath()) and prev_dest or self:GetCurrentPos()
            self:AddToPathSearchQueue(start_pos, destPos, self.pathcaps, self.groundcaps, false)
        else
            self.dest = destPos
            self.path = nil
            self:MoveTo(self.dest)
            self.inst:PushEvent("ngl_startdirectwalkwithnopath", {dest = self.dest})
        end
    end

    self.inst:StartUpdatingComponent(self)
    self.in_updating = true
end

-- Necessary Utils
function PathFollower:AddToPathSearchQueue(start, endp, pcaps, gcaps, sub)
    if not self.search_queue then self.search_queue = {} end
    insert(self.search_queue, {startpos = start, endpos = endp, pathcaps = pcaps, groundcaps = gcaps, is_subsearch = sub})
end

function PathFollower:TryToDoPathSearch()
    if not self.in_mainpathsearching and self.search_queue and #self.search_queue > 0 then
        local p = remove(self.search_queue, 1)
        self:FindPath(p.startpos, p.endpos, p.pathcaps, p.groundcaps, p.is_subsearch)
    end
end

function PathFollower:FindPath(startpos, endpos, pathcaps, groundcaps, is_subsearch)
    local pf = is_subsearch and self.subsearch_pathfinder or self.pathfinder
    if not pf then return end
    
    local boat = self.inst:GetCurrentPlatform()
    local rad = boat and boat:GetPhysicsRadius() + 2
    
    pf:SubmitSearch(startpos, endpos, pathcaps, groundcaps, rad)
    
    if is_subsearch then self.in_subpathsearching = true
    else self.in_mainpathsearching = true end
end

function PathFollower:KillMainpathSearch()
    self.in_mainpathsearching = false
    if self.pathfinder then self.pathfinder:KillSearch() end
end

function PathFollower:KillSubpathSearch()
    self.in_subpathsearching = false
    if self.subsearch_pathfinder then self.subsearch_pathfinder:KillSearch() end
end

function PathFollower:KillAllSearches()
    self:KillMainpathSearch()
    self:KillSubpathSearch()
end

function PathFollower:KillPendingSubpathSearches()
    if not self.search_queue then return end
    for i = #self.search_queue, 1, -1 do
        if self.search_queue[i].is_subsearch then
            remove(self.search_queue, i)
        end
    end
end

function PathFollower:GetCurrentPos()
    if IsSailingMoveMode(self:GetMoveMode(true)) and self.inst:GetCurrentPlatform() then
        return self.inst:GetCurrentPlatform():GetPosition()
    else
        return self.inst:GetPosition()
    end
end

function PathFollower:HasDest() return self.dest ~= nil end
function PathFollower:GetLocomotor() return self.inst.components.locomotor end
function PathFollower:WaitingForPathSearch() return self.in_updating and self.path == nil and (self.in_mainpathsearching or (self.search_queue and #self.search_queue > 0)) end
function PathFollower:FollowingPath() return self.in_updating and self.path ~= nil end
function PathFollower:DirectWalkingWithNoPath() return self.in_updating and self.path == nil end


function PathFollower:SetMoveModeOverrideInternal(m) self._movemode_override = m end
function PathFollower:SetMoveModeOverride(m) self.movemode_override = m end

function PathFollower:UpdateMoveMode()
    local prev = self.movemode
    for _,v in ipairs(MOVEMODES_ARRAY) do
        if v.fn(self) then
            self.movemode = MOVEMODES[v.mode]
            break
        end
    end
    if prev == MOVEMODES.DIRECTWALK and self.movemode ~= MOVEMODES.DIRECTWALK and not self:GetLocomotor() then
        SendRPCToServer(RPC.StopWalking)
    end
end

function PathFollower:GetMoveMode(no_update)
    if not no_update then self:UpdateMoveMode() end
    return self.movemode_override or self._movemode_override or self.movemode
end

function PathFollower:CanCollideWith(COLLISION_TYPE)
    local mask = self.inst.Physics:GetCollisionMask()
    return BitAND(mask, COLLISION_TYPE) == COLLISION_TYPE
end

function PathFollower:UpdatePathCaps()
    local is_land = self.inst:IsOnValidGround()
    local no_limits = not self:CanCollideWith(COLLISION.LAND_OCEAN_LIMITS)
    local no_obs = not self:CanCollideWith(COLLISION.OBSTACLES)
    
    self.pathcaps = {
        player = self.inst:HasTag("player"),
        ignorecreep = true,
        ignorewalls = no_obs,
        allowocean = not is_land or no_limits,
        ignoreLand = not is_land and not no_limits
    }
end

function PathFollower:GetPathCaps(no_update)
    if not no_update then self:UpdatePathCaps() end
    return self.pathcaps_override or self._pathcaps_override or self.pathcaps
end

function PathFollower:SetPathCapsOverride(p) self.pathcaps_override = p end
function PathFollower:SetGroundCapsOverride(g) self.groundcaps_override = g end

function PathFollower:UpdateGroundCaps()
    self.groundcaps = {speed_on_road = 0, speed_on_creep = 0, faster_on_tiles = nil}
end

function PathFollower:GetGroundCaps(no_update)
    if not no_update then self:UpdateGroundCaps() end
    return self.groundcaps_override or self._groundcaps_override or self.groundcaps
end

function PathFollower:ForceStop()
    self.inst:StopUpdatingComponent(self)
    self.in_updating = false
    self:Clear()
    local movemode = self:GetMoveMode(true)
    if movemode and movemode.on_stop_fn then
        movemode.on_stop_fn(self)
    end
    self.inst:PushEvent("ngl_stoppathfollow")
    TheWorld.ngl_pathfinding_settings = {enabled = false}
    TheWorld:PushEvent("ngl_pathfinding_change", {enabled = false})
end

function PathFollower:Clear()
    self:KillAllSearches()
    self.path = nil
    self.dest = nil
    self.search_queue = {}
    self.is_checking_only = false
    self.check_status = nil
    if self.debug_signs then
        for _, s in pairs(self.debug_signs) do s:Remove() end
        self.debug_signs = nil
    end
end

function PathFollower:CanMove()
    local m = self:GetMoveMode(true)
    return m and m.check_canmove_fn and m.check_canmove_fn(self)
end

function PathFollower:ShouldResumeMoving()
    local movemode = self:GetMoveMode(true)
    return movemode and movemode.check_shouldresume_fn and movemode.check_shouldresume_fn(self)
end

function PathFollower:MoveTo(pos)
    if not self:CanMove() then return end
    local m = self:GetMoveMode()
    if m and m.on_move_fn then m.on_move_fn(self, pos) end
end

function PathFollower:IsOffTrack()
    if self.path == nil or not self:FollowingPath() then return false end
    local movemode = self:GetMoveMode(true)
    if movemode and movemode.check_offtrack then
        local path = self.path
        local cur_pos = self:GetCurrentPos()
        cur_pos.y = 0
        local curstep_pos = StepToVector3(path.steps[path.currentstep])
        local prestep_pos = StepToVector3(path.steps[path.currentstep - 1])
        if curstep_pos == prestep_pos then return end 

        local dist = GetDistFromPointToLine(cur_pos, prestep_pos, curstep_pos)
        return dist > 1
    end
    return false
end

function PathFollower:VisualizePath()
    if not IsValidPath(self.path) then return end
    self.debug_signs = {}
    for _,step in pairs (self.path.steps) do
        local sign = SpawnPrefab("minisign")
        sign.Transform:SetPosition(step.x, step.y, step.z)
        insert(self.debug_signs, sign)
    end
end

function PathFollower:SetDebugMode(enabled)
    self.debugmode = (enabled == true)
    if self:FollowingPath() then
        self:VisualizePath()
    end
end

function PathFollower:SendAction(act, rightclick, doubleclick)
    local function sendrpc(act, rightclick, doubleclick)
        local pos = act:GetActionPoint()
        local controlmods = act.controlmods or 10 --force stack and force attack
        if doubleclick then
            SendRPCToServer(RPC.DoubleTapAction, act.action.code, pos.x, pos.z, act.action.canforce, act.action.mod_name)
        elseif rightclick then
            SendRPCToServer(RPC.RightClick, act.action.code, pos.x, pos.z, act.target, act.rotation, true, nil, act.action.canforce, act.action.mod_name)
        else
            SendRPCToServer(RPC.LeftClick, act.action.code, pos.x, pos.z, act.target, true, controlmods, act.action.canforce, act.action.mod_name)
        end
    end

    local playercontroller = self.inst.components.playercontroller
    if playercontroller == nil or act == nil then return end
    if playercontroller.locomotor == nil then
        if act.action and act.action.pre_action_cb then
            act.action.pre_action_cb(act)
        end
        sendrpc(act, rightclick, doubleclick)
    elseif playercontroller:CanLocomote() then
        act.preview_cb = function()
            sendrpc(act, rightclick, doubleclick)
        end
        playercontroller:DoAction(act)
    end
end

return PathFollower