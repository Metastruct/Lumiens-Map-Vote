util.AddNetworkString("RAM_MapVoteStart")
util.AddNetworkString("RAM_MapVoteUpdate")
util.AddNetworkString("RAM_MapVoteCancel")
util.AddNetworkString("RAM_WorkshopInfo")
util.AddNetworkString("RTV_Delay")

MapVote.Continued = false

net.Receive("RAM_MapVoteUpdate", function(len, ply)
    if not MapVote.Allow then return end
    if not IsValid(ply) then return end

    local update_type = net.ReadUInt(3)
    if update_type == MapVote.UPDATE_VOTE then
        local map_id = net.ReadUInt(32)
        if MapVote.CurrentMaps[map_id] then
            MapVote.Votes[ply:SteamID()] = map_id

            net.Start("RAM_MapVoteUpdate")
            net.WriteUInt(MapVote.UPDATE_VOTE, 3)
            net.WriteEntity(ply)
            net.WriteUInt(map_id, 32)
            net.Broadcast()
        end
    end
end)

if file.Exists("mapvote/recentmaps.txt", "DATA") then
    recentmaps = util.JSONToTable(file.Read("mapvote/recentmaps.txt", "DATA"))
else
    recentmaps = {}
end

if file.Exists("mapvote/playcount.txt", "DATA") then
    playCount = util.JSONToTable(file.Read("mapvote/playcount.txt", "DATA"))
else
    playCount = {}
end

if file.Exists("mapvote/config.txt", "DATA") then
    MapVote.Config = util.JSONToTable(file.Read("mapvote/config.txt", "DATA"))
else
    MapVote.Config = {}
end

function CoolDownDoStuff()
    local cooldownnum = MapVote.Config.MapsBeforeRevote or 3

    if #recentmaps == cooldownnum then
        table.remove(recentmaps)
    end

    local curmap = game.GetMap():lower() .. ".bsp"

    if not table.HasValue(recentmaps, curmap) then
        table.insert(recentmaps, 1, curmap)
    end

    if playCount[curmap] == nil then
        playCount[curmap] = 1
    else
        playCount[curmap] = playCount[curmap] + 1
    end

    file.Write("mapvote/recentmaps.txt", util.TableToJSON(recentmaps))
    file.Write("mapvote/playcount.txt", util.TableToJSON(playCount))
end

function MapVote.Start(length, current, limit, expressions, callback)
    current = current or MapVote.Config.AllowCurrentMap or false
    length = length or MapVote.Config.TimeLimit or 28
    limit = limit or MapVote.Config.MapLimit or 24
    expressions = expressions or MapVote.Config.MapExpressions

    local cooldown = MapVote.Config.EnableCooldown or MapVote.Config.EnableCooldown == nil and true
    local autoGamemode = autoGamemode or MapVote.Config.AutoGamemode or MapVote.Config.AutoGamemode == nil and true

    if not expressions then
        local info = file.Read(GAMEMODE.Folder .. "/" .. GAMEMODE.FolderName .. ".txt", "GAME")
        if info then
            info = util.KeyValuesToTable(info)
            expressions = info.maps
        else
            error("MapVote Expressions can not be loaded from gamemode")
        end
    end

    if type(expressions) ~= "table" then
        expressions = {expressions}
    end

    local maps = file.Find("maps/*.bsp", "GAME")
    local vote_maps = {}
    local play_counts = {}
    local amt = 0

    local curmap = game.GetMap():lower() .. ".bsp"

    for _, map in RandomPairs(maps) do
        local plays = playCount[map]

        if (plays == nil) then
            plays = 0
        end

        if (not ((not current and curmap == map) or (cooldown and table.HasValue(recentmaps, map)))) then
            for _, v in ipairs(expressions) do
                local mapname = map:sub(1, -5)

                if string.find(mapname, v) then
                    vote_maps[#vote_maps + 1] = mapname
                    play_counts[#play_counts + 1] = plays
                    amt = amt + 1

                    break
                end
            end

            if (limit and amt >= limit) then break end
        end
    end

    net.Start("RAM_MapVoteStart")
    net.WriteUInt(#vote_maps, 32)

    for i = 1, #vote_maps do
        net.WriteString(vote_maps[i])
        net.WriteUInt(play_counts[i], 32)
    end

    net.WriteUInt(length, 32)
    net.Broadcast()

    MapVote.Allow = true
    MapVote.CurrentMaps = vote_maps
    MapVote.Votes = {}

    timer.Create("RAM_MapVote", length, 1, function()
        MapVote.Allow = false
        local map_results = {}

        for k, v in pairs(MapVote.Votes) do
            if (not map_results[v]) then
                map_results[v] = 0
            end

            for k2, v2 in ipairs(player.GetAll()) do
                if (v2:SteamID() == k) then
                    map_results[v] = map_results[v] + 1
                end
            end
        end

        CoolDownDoStuff()

        local winner = table.GetWinningKey(map_results) or 1

        net.Start("RAM_MapVoteUpdate")
        net.WriteUInt(MapVote.UPDATE_WIN, 3)
        net.WriteUInt(winner, 32)
        net.Broadcast()

        local map = MapVote.CurrentMaps[winner]
        local gamemode = nil

        if (autoGamemode) then
            -- check if map matches a gamemode's map pattern
            for k, gm in ipairs(engine.GetGamemodes()) do
                -- ignore empty patterns
                if (gm.maps and gm.maps ~= "") then
                    -- patterns are separated by "|"
                    for k2, pattern in ipairs(string.Split(gm.maps, "|")) do
                        if (string.match(map, pattern)) then
                            gamemode = gm.name
                            break
                        end
                    end
                end
            end
        else
            print("not enabled")
        end

        timer.Simple(4, function()
            if (hook.Run("MapVoteChange", map) ~= false) then
                if (callback) then
                    callback(map)
                else
                    -- if map requires another gamemode then switch to it
                    if (gamemode and gamemode ~= engine.ActiveGamemode()) then
                        RunConsoleCommand("gamemode", gamemode)
                    end

                    RunConsoleCommand("changelevel", map)
                end
            end
        end)
    end)
end

hook.Add("Shutdown", "RemoveRecentMaps", function()
    if file.Exists("mapvote/recentmaps.txt", "DATA") then
        file.Delete("mapvote/recentmaps.txt")
    end
end)

function MapVote.Cancel()
    if MapVote.Allow then
        MapVote.Allow = false

        net.Start("RAM_MapVoteCancel")
        net.Broadcast()
        timer.Remove("RAM_MapVote")
    end
end

hook.Add("PlayerFullyConnected", "NetworkMapWsids", function(ply)
    local lookup = {}
    local wsid_files, _ = file.Find("maps/*.wsid", "GAME")

    for _, wsid_file in ipairs(wsid_files) do
        local wsid = file.Read("maps/" .. wsid_file, "GAME")
        local name = string.StripExtension(string.StripExtension(wsid_file)) -- twice, because .bsp.wsid

        wsid = string.Explode("[\\/]", wsid)[1]
        lookup[name] = wsid
    end

    local data = util.Compress(util.TableToJSON(lookup))
    local bytes = #data

    net.Start("RAM_WorkshopInfo")
    net.WriteUInt(bytes, 16)
    net.WriteData(data, bytes)
    net.Send(ply)
end)