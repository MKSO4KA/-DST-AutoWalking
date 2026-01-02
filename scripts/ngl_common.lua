local Common = {}

--------------------------------------------------------------------------
-- [CONSTANTS]
--------------------------------------------------------------------------
Common.SERVER_LEFTCLICK_DIST_SQ = 4096 
Common.CLIENT_ENTITY_LOADING_RANGE = 64
Common.MAX_STEP_DIST = 40
Common.MAX_STEP_DIST_SQ = 1600 

Common.STATUS = {
    CALCULATING = 0,
    FOUNDPATH = 1,
    NOPATH = 2
}

-- Movement Prediction
Common.PREDICT_ENABLED = .5
local PREDICT_DISABLED = 1.25

-- Scan Settings
Common.SCAN = {
    STEP_COARSE = 3,  
    STEP_FINE   = 2,  
    TILE_SIZE   = 4,  
    YIELD_THRESHOLD = 2000 
}

-- [NEW] Biome Colors (R, G, B, A)
Common.BIOME_COLORS = {
    -- Surface Land
    LUNAR     = {0.2, 0.8, 1,   0.9}, -- Лунный остров (Голубой)
    HERMIT    = {1,   0.4, 0.8, 0.9}, -- Остров отшельницы (Розовый)
    MONKEY    = {0.6, 0.4, 0.2, 0.9}, -- Остров обезьян (Коричневый)
    MAINLAND  = {1,   1,   1,   0.4}, -- Обычная суша (Белый полупрозрачный)
    
    -- Ocean
    ICE       = {0.4, 0.9, 1,   0.7}, -- Лед (Ярко-голубой)
    HAZARDOUS = {0.8, 0,   0,   0.8}, -- Воронки (Красный)
    WATERLOG  = {0.2, 0.7, 0.2, 0.8}, -- Водный лес (Зеленый)
    
    -- Cave
    ARCHIVE   = {0.9, 0.9, 0.2, 0.8}, -- Архивы (Желтый)
    
    UNKNOWN   = {1,   1,   1,   0.5}
}

--------------------------------------------------------------------------
-- [UTILITIES]
--------------------------------------------------------------------------
local floor = math.floor

function Common.MakeKey(x, z) 
    return (floor(x) * 100000) + floor(z)
end

function Common.StepToVector3(step)
    return Vector3(step.x, step.y, step.z)
end

function Common.Vector3ToStep(point)
    return {y = point.y, x = point.x, z = point.z}
end

function Common.IsValidPath(path)
    return path ~= nil and path.steps and #path.steps >= 2
end

function Common.BitAND(a, b)
    local p, c = 1, 0
    while a > 0 and b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb > 1 then c = c + p end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return c
end

function Common.IsSailingMoveMode(movemode)
    return movemode and movemode.is_boat_movement
end

function Common.GetArriveStep(locomotor)
    if locomotor then return Common.PREDICT_ENABLED end
    return PREDICT_DISABLED
end

function Common.GetDistFromPointToLine(point, linePoint1, linePoint2)
    local x0,y0 = point.x, point.z
    local x1,y1 = linePoint1.x, linePoint1.z
    local x2,y2 = linePoint2.x, linePoint2.z
    return math.abs( (x2-x1)*(y0-y1) - (y2-y1)*(x0-x1) ) / math.sqrt((x2-x1)*(x2-x1) + (y2-y1)*(y2-y1))
end

function Common.IsCave()
    return TheWorld and TheWorld:HasTag("cave")
end

-- [FIXED] Added GetTileName to prevent crash
function Common.GetTileName(x, z)
    if TheWorld and TheWorld.Map then
        local tile_id = TheWorld.Map:GetTileAtPoint(x, 0, z)
        if tile_id and WORLD_TILES then
            for name, id in pairs(WORLD_TILES) do
                if id == tile_id then return name end
            end
            return "ID:"..tostring(tile_id)
        end
    end
    return "Unknown"
end

return Common