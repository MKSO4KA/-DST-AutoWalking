local all_clients_require_mod = env.modinfo and env.modinfo.all_clients_require_mod -- 老登俱乐部可能会改成服务器版本
-- print("all_clients_require_mod: ", all_clients_require_mod)

local function IsAprilFoolsDay()
    local date = os.date("*t")
    return date.month == 4 and date.day == 1
end

local function get_deathcause_override_command_str()
    return [[
        local player = ConsoleCommandPlayer()
        if player then
            local locale = LOC and LOC.GetLocaleCode()
            local CH = locale == "zh" or locale == "zhr"
            player.deathpkname = CH and "自动寻路" or "Auto Walking"
        end
    ]]
end

local function DoDeathCauseOverride(x, z)
    if TheWorld and TheWorld.ismastersim then -- Client Host（no cave or Dont Starve Alone mod）
        ExecuteConsoleCommand(get_deathcause_override_command_str(x, z))
    elseif TheNet:GetIsServerAdmin() then -- you are the admin of the server
        TheNet:SendRemoteExecute(get_deathcause_override_command_str(x, z), x, z)
    elseif MOD_RPC[modname]["OverrideDeathCause"] ~= nil then -- has registered mod RPC
        SendModRPCToServer(MOD_RPC[modname]["OverrideDeathCause"], ThePlayer)
    else
        print("DoDeathCauseOverride: not a server admin or mod RPC not available")
    end
end


if all_clients_require_mod then
    AddModRPCHandler(modname, "OverrideDeathCause", function(player)
        if player then
            local locale = LOC and LOC.GetLocaleCode()
            local CH = locale == "zh" or locale == "zhr"
            player.deathpkname = CH and "自动寻路" or "Auto Walking"
        end
    end)
end
if not TheNet:IsDedicated() then --client side
    AddComponentPostInit("playercontroller", function(self, player)
        if ThePlayer and ThePlayer == player then
            player:ListenForEvent("healthdelta", function(inst, data)
                if data and data.oldpercent > 0 and data.newpercent <= 0 and --death
                    player.components.ngl_pathfollower and player.components.ngl_pathfollower:FollowingPath() and -- path following
                    IsAprilFoolsDay() then -- should override
                        -- 发送指令改变player.deathpkname
                        DoDeathCauseOverride()
                end
            end)
        end
    end)
end

