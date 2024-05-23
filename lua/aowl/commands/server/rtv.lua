RTV = RTV or {}
RTV.TotalVotes = 0
RTV.Wait = 60 -- The wait time in seconds. This is how long a player has to wait before voting when the map changes.
RTV._ActualWait = CurTime() + RTV.Wait
RTV.PlayerCount = MapVote.Config.RTVPlayerCount or 3

function RTV.ShouldChange()
    return RTV.TotalVotes >= math.Round(#player.GetAll() * 0.66)
end

function RTV.RemoveVote()
    RTV.TotalVotes = math.Clamp(RTV.TotalVotes - 1, 0, math.huge)
end

function RTV.Start()
    if GAMEMODE_NAME == "terrortown" then
        net.Start("RTV_Delay")
        net.Broadcast()

        hook.Add("TTTEndRound", "MapvoteDelayed", function()
            MapVote.Start(nil, nil, nil, nil)
        end)
    elseif GAMEMODE_NAME == "deathrun" then
        net.Start("RTV_Delay")
        net.Broadcast()

        hook.Add("RoundEnd", "MapvoteDelayed", function()
            MapVote.Start(nil, nil, nil, nil)
        end)
    else
        PrintMessage(HUD_PRINTTALK, "The vote has been rocked, map vote imminent")

        timer.Simple(4, function()
            MapVote.Start(nil, nil, nil, nil)
        end)
    end
end

function RTV.AddVote(pl)
    if not RTV.CanVote(pl) then return end

    RTV.TotalVotes = RTV.TotalVotes + 1
    pl.RTVoted = true

    local players = player.GetAll()
    local requiredAmount = math.Round(#players * 0.66)
    local sndPitch = 90 + math.ceil((RTV.TotalVotes / requiredAmount) * 40)

    local msg = string.format("%s has RTV'd! (%s / %s)", pl:Nick(), RTV.TotalVotes, requiredAmount)
    MsgN(msg)

    for k, v in ipairs(players) do
        v:ChatPrint(msg)
    end

    local filter = RecipientFilter()
    filter:AddAllPlayers()

    EmitSound("friends/friend_join.wav", vector_origin, -2, CHAN_AUTO, 0.8, 0, 0, sndPitch, 0, filter)

    if RTV.ShouldChange() then
        RTV.Start()
    end
end

hook.Add("PlayerDisconnected", "Remove RTV", function(pl)
    if pl.RTVoted then
        RTV.RemoveVote()
    end

    timer.Simple(0.1, function()
        if RTV.ShouldChange() then
            RTV.Start()
        end
    end)
end)

function RTV.CanVote(pl)
    local plCount = table.Count(player.GetAll())
    if RTV._ActualWait >= CurTime() then return false, "You must wait a bit before voting!" end
    if GetGlobalBool("In_Voting") then return false, "There is currently a vote in progress!" end
    if pl.RTVoted then return false, "You have already voted to Rock the Vote!" end
    if RTV.ChangingMaps then return false, "There has already been a vote, the map is going to change!" end
    if plCount < RTV.PlayerCount then return false, "You need more players before you can rock the vote!" end

    return true
end

function RTV.StartVote(pl)
    local can, err = RTV.CanVote(pl)

    if not can then
        pl:PrintMessage(HUD_PRINTTALK, err)

        return
    end

    RTV.AddVote(pl)
end

concommand.Add("rtv_start", RTV.StartVote)

aowl.AddCommand("rtv", "Rock to vote (vote for next map!)", function(pl)
    RTV.StartVote(pl)
end, "players", true)