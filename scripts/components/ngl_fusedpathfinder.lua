-- the status of pathsearch
local STATUS_CALCULATING = 0
local STATUS_FOUNDPATH = 1
local STATUS_NOPATH = 2

local Pathfinder = Class(function(self, inst)
	self.inst = inst

    self.cpp_pathfinder = self.inst.components.ngl_pathfinder
    self.lua_pathfinder = self.inst.components.ngl_astarpathfinder
    self.cpp_pathfinder_enabled = true
    self.lua_pathfinder_enabled = true
end)
    
function Pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps, boatRadius)
    self:KillSearch()
    -- 内部优化一下
    -- cpp pathfinder is not able to keep a dist from shore which may cause the boat collision
    self.cpp_pathfinder_enabled = boatRadius == nil and not (self.cpp_pathfinder.process_maxtime and self.cpp_pathfinder.process_maxtime <= 0)
    self.lua_pathfinder_enabled = not (self.lua_pathfinder.process_maxtime and self.lua_pathfinder.process_maxtime < 0)
    if self.cpp_pathfinder_enabled then 
        self.cpp_pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps, boatRadius)
    end
    if self.lua_pathfinder_enabled then 
        self.lua_pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps, boatRadius)
    end

    self.pathcaps = pathcaps
    self.groundcaps = groundcaps
end


function Pathfinder:GetSearchStatus()
    local cpp_pathfinder_status = self.cpp_pathfinder_enabled and self.cpp_pathfinder:GetSearchStatus() or nil
    local lua_pathfinder_status = self.lua_pathfinder_enabled and self.lua_pathfinder:GetSearchStatus() or nil
    if lua_pathfinder_status == STATUS_NOPATH then
        return cpp_pathfinder_status
    else
        return lua_pathfinder_status
    end
end

function Pathfinder:GetSearchResult()
	if self:GetSearchStatus() == STATUS_FOUNDPATH then
        local cpp_pathfinder_result, lua_pathfinder_result
        if self.cpp_pathfinder:GetSearchStatus() == STATUS_FOUNDPATH then
            cpp_pathfinder_result= self.cpp_pathfinder:GetSearchResult()
        end
        if self.lua_pathfinder:GetSearchStatus() == STATUS_FOUNDPATH then
            lua_pathfinder_result = self.lua_pathfinder:GetSearchResult()
        end

        return lua_pathfinder_result or cpp_pathfinder_result
    end
end

function Pathfinder:KillSearch()
    self.cpp_pathfinder:KillSearch()
    self.lua_pathfinder:KillSearch()
end

function Pathfinder:SetPeriod(time)
	self.lua_pathfinder:SetPeriod(time)
end

--function Pathfinder:SetPerRound(amount)
--	self.lua_pathfinder:SetPerRound(amount)
--end
--
--function Pathfinder:SetMaxWork(amount)
--	self.lua_pathfinder:SetMaxWork(amount)
--end

function Pathfinder:SetTimePerRound(lua_time)
    self.lua_pathfinder:SetTimePerRound(lua_time)
end

function Pathfinder:SetMaxTime(lua_time)
    self.lua_pathfinder:SetMaxTime(lua_time)
end

function Pathfinder:IsClear(p1, p2, pathcaps, boatRadius)
    return self.lua_pathfinder:IsClear(p1, p2, pathcaps, boatRadius)
end

function Pathfinder:TestClear(pathcaps, boatRadius)
    return self.lua_pathfinder:TestClear(pathcaps, boatRadius)
end

function Pathfinder:IsFasterAtPoint(point, groundcaps)
	return self.lua_pathfinder:IsFasterAtPoint(point, groundcaps)
end

function Pathfinder:IsPassableAtPoint(point, pathcaps)
	return self.lua_pathfinder:IsPassableAtPoint(point, pathcaps)
end

function Pathfinder:TestPassable(pathcaps)
    return self.lua_pathfinder:TestPassable(pathcaps)
end

return Pathfinder