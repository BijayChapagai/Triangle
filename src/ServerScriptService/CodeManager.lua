local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Manager = require(ServerScriptService.Data.Manager)

local CodeManager = {}

local CodeList = {
	["RELEASE"] = function(player)
		local profile = Manager.Profiles[player]
		profile.Data.Cash += 200 -- change to value for redeeming
		player.leaderstats.Cash.Value = profile.Data.Cash
	end,
	["FREEMONEY"] = function(player)
		local profile = Manager.Profiles[player]
		profile.Data.Cash += 350 -- change to value for redeeming
		player.leaderstats.Cash.Value = profile.Data.Cash
	end,
	["CUBES"] = function(player)
		local profile = Manager.Profiles[player]
		profile.Data.Cash += 400 -- change to value for redeeming
		player.leaderstats.Cash.Value = profile.Data.Cash
	end,
}

CodeManager.AttemptRedeem = function(player : Player, code: string)
	if not player:IsInGroup(34195654) then
		--ReplicatedStorage.Remotes.Notification:FireClient(player, "Can't Redeem [Not In Group!]", Color3.fromRGB(255, 35, 35), "Error")
		return
	end

	local profile = Manager.Profiles[player]
	if CodeList[code] then
		if table.find(profile.Data.RedeemedCodes, code) then return end
		CodeList[code](player)
		table.insert(profile.Data.RedeemedCodes, code)
	else
		--print("This isn't a valid code")
	end
end

return CodeManager