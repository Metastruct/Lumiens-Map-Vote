MapVote = {}
MapVote.Config = {}

-- Default Config
MapVoteConfigDefault = {
    MapLimit = 24,
    TimeLimit = 28,
    AllowCurrentMap = false,
    EnableCooldown = true,
    MapsBeforeRevote = 3,
    RTVPlayerCount = 3,
    MapPrefixes = {"ttt_"},
    AutoGamemode = false
}

-- Default Config
hook.Add("Initialize", "MapVoteConfigSetup", function()
    if not file.Exists("mapvote", "DATA") then
        file.CreateDir("mapvote")
    end

    if not file.Exists("mapvote/config.txt", "DATA") then
        file.Write("mapvote/config.txt", util.TableToJSON(MapVoteConfigDefault))
    end
end)

MapVote.CurrentMaps = {}
MapVote.Votes = {}
MapVote.Allow = false
MapVote.UPDATE_VOTE = 1
MapVote.UPDATE_WIN = 3

if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("mapvote/cl_mapvote.lua")

    include("mapvote/sv_mapvote.lua")
    include("mapvote/rtv.lua")

    hook.Add("Initialize", "AutoTTTMapVote", function()
        if GAMEMODE_NAME == "terrortown" then
            function CheckForMapSwitch()
                -- Check for mapswitch
                local rounds_left = math.max(0, GetGlobalInt("ttt_rounds_left", 6) - 1)
                SetGlobalInt("ttt_rounds_left", rounds_left)
                local time_left = math.max(0, (GetConVar("ttt_time_limit_minutes"):GetInt() * 60) - CurTime())
                local switchmap = false
                local nextmap = string.upper(game.GetMapNext())

                if rounds_left <= 0 then
                    LANG.Msg("limit_round", {
                        mapname = nextmap
                    })

                    switchmap = true
                elseif time_left <= 0 then
                    LANG.Msg("limit_time", {
                        mapname = nextmap
                    })

                    switchmap = true
                end

                if switchmap then
                    timer.Stop("end2prep")
                    MapVote.Start(nil, nil, nil, nil)
                end
            end
        end

        if GAMEMODE_NAME == "deathrun" then
            function RTV.Start()
                MapVote.Start(nil, nil, nil, nil)
            end
        end

        if GAMEMODE_NAME == "zombiesurvival" then
            hook.Add("LoadNextMap", "MAPVOTEZS_LOADMAP", function()
                MapVote.Start(nil, nil, nil, nil)

                return true
            end)
        end
    end)
end

if CLIENT then
    include("mapvote/cl_mapvote.lua")
end