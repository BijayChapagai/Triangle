-- Wires progression RemoteEvents to the Progression module and keeps the global
-- leaderboards fresh. (ModuleScript; call ProgressionServer.Init() from Game.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = require(script.Parent.Progression)
local Events = ReplicatedStorage.Events

local function onPlayer(player)
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if player:GetAttribute("DataLoaded") then
			Progression.InitPlayer(player)
		end
	end)
	if player:GetAttribute("DataLoaded") then
		Progression.InitPlayer(player)
	end
end

function ProgressionServer.Init()
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		Progression.PlayerRemoving(p)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end

	Events.Rebirth.OnServerEvent:Connect(function(p) Progression.TryRebirth(p) end)
	Events.EquipSkin.OnServerEvent:Connect(function(p, skinId) Progression.EquipSkin(p, skinId) end)
	Events.QuestFetch.OnServerEvent:Connect(function(p) Progression.sendQuests(p) end)
	Events.QuestClaim.OnServerEvent:Connect(function(p, qid) Progression.ClaimQuest(p, qid) end)
	Events.Leaderboard.OnServerEvent:Connect(function(p) Progression.sendLeaderboard(p) end)
	Events.ZoneTeleport.OnServerEvent:Connect(function(p, zoneId) Progression.TryZoneTeleport(p, zoneId) end)

	-- Throttled leaderboard writes (avoids DataStore rate limits)
	task.spawn(function()
		while task.wait(30) do
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(function() Progression.updateLeaderboard(p) end)
			end
		end
	end)
end

return ProgressionServer
