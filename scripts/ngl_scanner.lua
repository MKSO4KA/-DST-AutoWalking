local Common = require("ngl_common")

local Scanner = {}

local insert = table.insert
local remove = table.remove
local floor = math.floor
local sort = table.sort
local SCAN_CFG = Common.SCAN

-- Tile Definitions
local TILES_ARCHIVE = WORLD_TILES.ARCHIVE
local TILES_ICE = WORLD_TILES.OCEAN_ICE
local TILES_HAZARDOUS = WORLD_TILES.OCEAN_HAZARDOUS
local TILES_WATERLOG = WORLD_TILES.OCEAN_WATERLOG

--------------------------------------------------------------------------------
-- OPTIMIZATION UTILS
--------------------------------------------------------------------------------

-- Compresses many small segments into fewer long segments.
-- This drastically reduces rendering load.
local function CompactSegments(raw_segments)
    if not raw_segments or #raw_segments == 0 then return {} end

    local horizontal = {} -- Key: z, Value: list of {min_x, max_x}
    local vertical = {}   -- Key: x, Value: list of {min_z, max_z}
    local optimized = {}

    -- 1. Sort raw segments into buckets
    for _, seg in ipairs(raw_segments) do
        local p1, p2 = seg.p1, seg.p2
        
        -- Check if horizontal (z matches)
        if math.abs(p1.z - p2.z) < 0.1 then 
            local z = p1.z
            if not horizontal[z] then horizontal[z] = {} end
            -- Ensure min < max
            local mn, mx = p1.x, p2.x
            if mn > mx then mn, mx = mx, mn end
            insert(horizontal[z], {min = mn, max = mx})
        
        -- Check if vertical (x matches)
        elseif math.abs(p1.x - p2.x) < 0.1 then
            local x = p1.x
            if not vertical[x] then vertical[x] = {} end
            local mn, mx = p1.z, p2.z
            if mn > mx then mn, mx = mx, mn end
            insert(vertical[x], {min = mn, max = mx})
        end
    end

    -- 2. Merge overlapping/touching intervals
    -- Helper function to merge intervals
    local function process_bucket(bucket, is_vert_mode)
        for key_coord, intervals in pairs(bucket) do
            if #intervals > 0 then
                -- Sort by start position
                sort(intervals, function(a,b) return a.min < b.min end)
                
                local current = intervals[1]
                for i = 2, #intervals do
                    local next_int = intervals[i]
                    -- If overlap or touch (within tiny margin due to float)
                    if next_int.min <= current.max + 0.1 then
                        -- Merge
                        if next_int.max > current.max then
                            current.max = next_int.max
                        end
                    else
                        -- Push current, start new
                        if is_vert_mode then
                            insert(optimized, {p1={x=key_coord, z=current.min}, p2={x=key_coord, z=current.max}})
                        else
                            insert(optimized, {p1={x=current.min, z=key_coord}, p2={x=current.max, z=key_coord}})
                        end
                        current = next_int
                    end
                end
                -- Push last
                if is_vert_mode then
                    insert(optimized, {p1={x=key_coord, z=current.min}, p2={x=key_coord, z=current.max}})
                else
                    insert(optimized, {p1={x=current.min, z=key_coord}, p2={x=current.max, z=key_coord}})
                end
            end
        end
    end

    process_bucket(horizontal, false)
    process_bucket(vertical, true)

    return optimized
end

--------------------------------------------------------------------------------
-- CAVE LOGIC
--------------------------------------------------------------------------------

local function GetCaveRegionType(map, x, z)
    local tile = map:GetTileAtPoint(x, 0, z)
    local is_ground = map:IsVisualGroundAtPoint(x, 0, z)
    if not is_ground then return nil end
    if tile == TILES_ARCHIVE then return "ARCHIVE" end
    return "MAINLAND"
end

local function TraceCaveRegion(map, start_x, start_z, target_type, visited_global)
    local stack = {{x = start_x, z = start_z}}
    local local_visited = {} 
    local segments = {}
    local checks = 0
    local edge_offset = SCAN_CFG.TILE_SIZE / 2
    local step = SCAN_CFG.STEP_FINE
    
    while #stack > 0 do
        local current = remove(stack)
        local key = Common.MakeKey(current.x, current.z)
        
        if not local_visited[key] then
            local_visited[key] = true
            visited_global[key] = true 
            
            local neighbors = {
                {x = current.x + step, z = current.z, dir="R"}, {x = current.x - step, z = current.z, dir="L"},
                {x = current.x, z = current.z + step, dir="U"}, {x = current.x, z = current.z - step, dir="D"}
            }

            for _, neighbor in ipairs(neighbors) do
                local neighbor_type = GetCaveRegionType(map, neighbor.x, neighbor.z)
                if neighbor_type == target_type then
                    if not local_visited[Common.MakeKey(neighbor.x, neighbor.z)] then
                        insert(stack, {x = neighbor.x, z = neighbor.z})
                    end
                else
                    -- Add Edge
                    local p1, p2
                    if neighbor.dir == "R" then p1={x=current.x+edge_offset, z=current.z-edge_offset}; p2={x=current.x+edge_offset, z=current.z+edge_offset}
                    elseif neighbor.dir == "L" then p1={x=current.x-edge_offset, z=current.z+edge_offset}; p2={x=current.x-edge_offset, z=current.z-edge_offset}
                    elseif neighbor.dir == "U" then p1={x=current.x+edge_offset, z=current.z+edge_offset}; p2={x=current.x-edge_offset, z=current.z+edge_offset}
                    elseif neighbor.dir == "D" then p1={x=current.x-edge_offset, z=current.z-edge_offset}; p2={x=current.x+edge_offset, z=current.z-edge_offset} end
                    insert(segments, {p1=p1, p2=p2})
                end
            end
            
            checks = checks + 1
            if checks > SCAN_CFG.YIELD_THRESHOLD then checks = 0; Sleep(0) end
        end
    end
    return segments
end

--------------------------------------------------------------------------------
-- SURFACE LOGIC
--------------------------------------------------------------------------------

local function GetSurfaceSpecialType(tile)
    if tile == WORLD_TILES.METEOR or tile == WORLD_TILES.PEBBLEBEACH then return "LUNAR" end
    if tile == WORLD_TILES.SHELLBEACH then return "HERMIT" end
    if tile == WORLD_TILES.MONKEY_DOCK or tile == WORLD_TILES.MONKEY_GROUND then return "MONKEY" end
    return nil
end

local function TraceSurfaceIsland(map, start_x, start_z, visited_global)
    local stack = {{x = start_x, z = start_z}}
    local local_visited = {} 
    local segments = {}
    local checks = 0
    local edge_offset = SCAN_CFG.TILE_SIZE / 2
    local step = SCAN_CFG.STEP_FINE
    local found_special_type = nil 

    while #stack > 0 do
        local current = remove(stack)
        local key = Common.MakeKey(current.x, current.z)
        
        if not local_visited[key] then
            local_visited[key] = true
            visited_global[key] = true 
            
            local t = map:GetTileAtPoint(current.x, 0, current.z)
            local spec = GetSurfaceSpecialType(t)
            if spec then found_special_type = spec end

            local neighbors = {
                {x = current.x + step, z = current.z, dir="R"}, {x = current.x - step, z = current.z, dir="L"},
                {x = current.x, z = current.z + step, dir="U"}, {x = current.x, z = current.z - step, dir="D"}
            }

            for _, neighbor in ipairs(neighbors) do
                local is_land = map:IsVisualGroundAtPoint(neighbor.x, 0, neighbor.z)
                if is_land then
                    if not local_visited[Common.MakeKey(neighbor.x, neighbor.z)] then
                        insert(stack, {x = neighbor.x, z = neighbor.z})
                    end
                else
                    -- Add Edge
                    local p1, p2
                    if neighbor.dir == "R" then p1={x=current.x+edge_offset, z=current.z-edge_offset}; p2={x=current.x+edge_offset, z=current.z+edge_offset}
                    elseif neighbor.dir == "L" then p1={x=current.x-edge_offset, z=current.z+edge_offset}; p2={x=current.x-edge_offset, z=current.z-edge_offset}
                    elseif neighbor.dir == "U" then p1={x=current.x+edge_offset, z=current.z+edge_offset}; p2={x=current.x-edge_offset, z=current.z+edge_offset}
                    elseif neighbor.dir == "D" then p1={x=current.x-edge_offset, z=current.z-edge_offset}; p2={x=current.x+edge_offset, z=current.z-edge_offset} end
                    insert(segments, {p1=p1, p2=p2})
                end
            end
            
            checks = checks + 1
            if checks > SCAN_CFG.YIELD_THRESHOLD then checks = 0; Sleep(0) end
        end
    end
    return segments, (found_special_type or "MAINLAND")
end

-- Trace simple ocean features
-- Returns {segments, area_size}
local function TraceOceanFeature(map, start_x, start_z, target_tile, visited_global)
    local stack = {{x = start_x, z = start_z}}
    local local_visited = {} 
    local segments = {}
    local checks = 0
    local edge_offset = SCAN_CFG.TILE_SIZE / 2
    local step = SCAN_CFG.STEP_FINE
    local area_size = 0 -- Count tiles to determine mass
    
    while #stack > 0 do
        local current = remove(stack)
        local key = Common.MakeKey(current.x, current.z)
        
        if not local_visited[key] then
            local_visited[key] = true
            visited_global[key] = true 
            area_size = area_size + 1
            
            local neighbors = {
                {x = current.x + step, z = current.z, dir="R"}, {x = current.x - step, z = current.z, dir="L"},
                {x = current.x, z = current.z + step, dir="U"}, {x = current.x, z = current.z - step, dir="D"}
            }

            for _, neighbor in ipairs(neighbors) do
                local t = map:GetTileAtPoint(neighbor.x, 0, neighbor.z)
                if t == target_tile then
                    if not local_visited[Common.MakeKey(neighbor.x, neighbor.z)] then
                        insert(stack, {x = neighbor.x, z = neighbor.z})
                    end
                else
                    -- Add Edge
                    local p1, p2
                    if neighbor.dir == "R" then p1={x=current.x+edge_offset, z=current.z-edge_offset}; p2={x=current.x+edge_offset, z=current.z+edge_offset}
                    elseif neighbor.dir == "L" then p1={x=current.x-edge_offset, z=current.z+edge_offset}; p2={x=current.x-edge_offset, z=current.z-edge_offset}
                    elseif neighbor.dir == "U" then p1={x=current.x+edge_offset, z=current.z+edge_offset}; p2={x=current.x-edge_offset, z=current.z+edge_offset}
                    elseif neighbor.dir == "D" then p1={x=current.x-edge_offset, z=current.z-edge_offset}; p2={x=current.x+edge_offset, z=current.z-edge_offset} end
                    insert(segments, {p1=p1, p2=p2})
                end
            end
            checks = checks + 1
            if checks > SCAN_CFG.YIELD_THRESHOLD then checks = 0; Sleep(0) end
        end
    end
    return segments, area_size
end

--------------------------------------------------------------------------------
-- MAIN EXECUTION
--------------------------------------------------------------------------------

function Scanner.Execute(inst, component)
    if not (TheWorld and TheWorld.Map) then return end
    
    local map = TheWorld.Map
    local width, height = map:GetSize()
    local half_w, half_h = width / 2, height / 2
    local visited = {} 
    local outlines = {} 
    local is_cave = Common.IsCave()
    
    local hazardous_candidates = {}

    -- Main Scanning Loop
    for ix = -half_w, half_w, SCAN_CFG.STEP_COARSE do
        for iz = -half_h, half_h, SCAN_CFG.STEP_COARSE do
            local world_x = floor((ix * SCAN_CFG.TILE_SIZE) / SCAN_CFG.STEP_FINE) * SCAN_CFG.STEP_FINE
            local world_z = floor((iz * SCAN_CFG.TILE_SIZE) / SCAN_CFG.STEP_FINE) * SCAN_CFG.STEP_FINE

            if not visited[Common.MakeKey(world_x, world_z)] then
                local segments = nil
                local label = nil

                if is_cave then
                    local c_type = GetCaveRegionType(map, world_x, world_z)
                    if c_type then
                        segments = TraceCaveRegion(map, world_x, world_z, c_type, visited)
                        label = c_type
                    end
                else
                    -- SURFACE
                    if map:IsVisualGroundAtPoint(world_x, 0, world_z) then
                        local land_segs, island_type = TraceSurfaceIsland(map, world_x, world_z, visited)
                        segments = land_segs
                        label = island_type
                    else
                        -- OCEAN
                        local tile = map:GetTileAtPoint(world_x, 0, world_z)
                        if tile == TILES_ICE then
                            segments = TraceOceanFeature(map, world_x, world_z, TILES_ICE, visited)
                            label = "ICE"
                        elseif tile == TILES_WATERLOG then
                            segments = TraceOceanFeature(map, world_x, world_z, TILES_WATERLOG, visited)
                            label = "WATERLOG"
                        elseif tile == TILES_HAZARDOUS then
                            -- Store for later comparison
                            local haz_segs, area = TraceOceanFeature(map, world_x, world_z, TILES_HAZARDOUS, visited)
                            -- Must be reasonably sized (e.g. at least 20 tiles) to be the real setpiece
                            if area > 20 then
                                insert(hazardous_candidates, {segs = haz_segs, area = area})
                            end
                        end
                    end
                end

                -- Compact segments immediately to save memory
                if segments and #segments > 0 and label then
                    local compact = CompactSegments(segments)
                    for _, seg in ipairs(compact) do
                        seg.type = label
                        insert(outlines, seg)
                    end
                    Sleep(0)
                end
            end
        end
        Sleep(0) -- Periodic yield during outer loop
    end

    -- Process Hazardous: Pick largest by Area
    if #hazardous_candidates > 0 then
        local best_cand = nil
        local max_area = -1
        
        for _, cand in ipairs(hazardous_candidates) do
            if cand.area > max_area then
                max_area = cand.area
                best_cand = cand.segs
            end
        end

        if best_cand then
            local compact = CompactSegments(best_cand)
            for _, seg in ipairs(compact) do
                seg.type = "HAZARDOUS"
                insert(outlines, seg)
            end
        end
    end

    component.island_outlines = outlines
    
    inst:DoTaskInTime(0, function()
        if inst.components.talker then
            local count = outlines and #outlines or 0
            inst.components.talker:Say("Scan complete. Objects: " .. tostring(count))
        end
        inst:PushEvent("ngl_outlines_generated")
    end)
end

return Scanner