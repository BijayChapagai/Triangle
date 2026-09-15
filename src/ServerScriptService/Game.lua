--// Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Main = require(script.Main)
local Manager = require(script.Parent.Data.Manager)
local CodeManager = require(script.Parent.CodeManager)
local Progression = require(script.Parent.Progression)
local RewardList = require(ReplicatedStorage.Modules.RewardList)

-- Initialize the modular progression systems (all logic lives in ModuleScripts)
require(script.Parent.FoodSpawner).Init()
require(script.Parent.ProgressionServer).Init()
require(script.Parent.AdminServer).Init()

for _, plr in Players:GetPlayers() do
	task.spawn(Main.PlayerSetup, plr)
end

Players.PlayerAdded:Connect(Main.PlayerSetup)

ReplicatedStorage.Events.AutoFarm.OnServerEvent:Connect(function(player, enabled: boolean)
	Main.AutoFarm(player, enabled)
end)

ReplicatedStorage.Events.PlayTimeReward.OnServerEvent:Connect(function(player, gift: number)
	local playertime = player:GetAttribute("PlayerTime")
	local CurrentGift = player:GetAttribute("CurrentGift")
	local index = RewardList[gift]
	if index == nil then return end
	if playertime < index.RequiredTime then return end
	if CurrentGift >= gift then return end
	local rewardAmount = index.Reward
	local typeOfReward = index.Type
	player:SetAttribute("CurrentGift", CurrentGift + 1)

	if typeOfReward == "Cash" then
		local profile = Manager.Profiles[player]
		profile.Data.Cash += rewardAmount
		player.leaderstats.Cash.Value = profile.Data.Cash
	else
		local Size = player.leaderstats.Size
		Size.Value += rewardAmount
		Progression.setCubeSize(player.Character, require(ReplicatedStorage.Modules.ProgressionConfig).visualSize(Size.Value))
	end
end)

ReplicatedStorage.Events.AttemptCode.OnServerEvent:Connect(function(player, request: string)
	CodeManager.AttemptRedeem(player, request)
end)

--// Food pickup (rarity-based, dynamic). Uses CollectionService tag signals so
--// cubes spawned at runtime by FoodSpawner also work.
local function handleFood(food)
	food.Touched:Connect(function(otherPart)
		local player = Players:GetPlayerFromCharacter(otherPart.Parent)
		if not player then return end
		if food.CanTouch == false then return end
		food.CanTouch = false

		local val = food:GetAttribute("Value") or 5
		Main.IncreaseSize(player, val / 50)
		Progression.AddProgress(player, "eat", 1)

		-- smooth shrink-out then remove; the spawner refills the map
		local t = TweenService:Create(food, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
		local ok, err = pcall(function() t.Completed:Connect(function() food:Destroy() end) end)
		if ok then t:Play() else food:Destroy() end
	end)
end

CollectionService:GetInstanceAddedSignal("Food"):Connect(function(inst)
	if inst:IsA("BasePart") and inst.Name == "Food" then
		handleFood(inst)
	end
end)

for _, food in CollectionService:GetTagged("Food") do
	if food:IsA("BasePart") then
		handleFood(food)
	end
end
