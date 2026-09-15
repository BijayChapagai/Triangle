local Manager = {}
Manager.Profiles = {}

local Players = game:GetService("Players")
local ProfileService = require(script.ProfileService)

local Template = {
	Cash = 0,
	RedeemedCodes = {},
	Rebirths = 0,
	RebirthMult = 1,
	Skin = "Default",
	OwnedSkins = { "Default" },
	Quests = {},
	ClaimedQuests = {},
	QuestDay = 0,
}
local ProfileStore = ProfileService.GetProfileStore("Yeah", Template)

Manager.PlayerAdded = function(player: Player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		profile:ListenToRelease(function()
			Manager.Profiles[player] = nil
			player:Kick()
		end)

		if player:IsDescendantOf(Players) == true then
			Manager.Profiles[player] = profile

			local leaderstats = Instance.new("Folder")
			leaderstats.Name = "leaderstats"
			leaderstats.Parent = player

			local Cash = Instance.new("NumberValue")
			Cash.Name = "Cash"
			Cash.Value = profile.Data.Cash
			Cash.Parent = leaderstats

			local Size = Instance.new("NumberValue")
			Size.Name = "Size"
			Size.Value = 0
			Size.Parent = leaderstats

			-- Ensure progression fields exist for older saves
			local d = profile.Data
			d.Rebirths = d.Rebirths or 0
			d.RebirthMult = d.RebirthMult or 1
			d.Skin = d.Skin or "Default"
			if not d.OwnedSkins then d.OwnedSkins = { "Default" } end
			if not d.Quests then d.Quests = {} end
			if not d.ClaimedQuests then d.ClaimedQuests = {} end

			player:SetAttribute("DataLoaded", true)
		else
			profile:Release()
		end
	else
		player:Kick()
	end
end

Manager.PlayerRemoving = function(player: Player)
	local profile = Manager.Profiles[player]
	if profile ~= nil then
		profile:Release()
	end
end

return Manager
