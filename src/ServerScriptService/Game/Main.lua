local Main = {}

--// Services
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketPlaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Manager = require(script.Parent.Parent.Data.Manager)
local Progression = require(script.Parent.Parent.Progression)
local Config = require(ReplicatedStorage.Modules.ProgressionConfig)

local function applyRankText(player)
	local size = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Size")
	if not size then return end
	local rebirths = (Manager.Profiles[player] and Manager.Profiles[player].Data.Rebirths) or 0
	local _, rankName = Config.getRank(size.Value, rebirths)
	if player.Character and player.Character:FindFirstChild("PlayerDisplay") then
		player.Character.PlayerDisplay.PlayerSize.Text = `Size: {math.floor(size.Value)}  [{rankName}]`
	end
end

local function setupVisuals(player)
	Progression.applySkin(player)
	applyRankText(player)
	if player.Character and player.Character.PrimaryPart then
		Progression.setCubeSize(player.Character, Config.visualSize(player.leaderstats.Size.Value))
	end
end

local function Respawn(player)
	local Size = player:FindFirstChild("leaderstats"):FindFirstChild("Size")
	local oldModel = player.Character
	local newModel = ServerStorage.Character:Clone()
	newModel.PrimaryPart.Color = Color3.fromRGB(math.random(1, 255), math.random(1, 255), math.random(1, 255))
	newModel.Name = player.Name
	player.Character = newModel
	newModel.Parent = workspace

	local Spawns = workspace.Spawns:GetChildren()
	local randomSpawn = Spawns[math.random(1, #Spawns)]
	newModel:PivotTo(randomSpawn:GetPivot())

	player.Character.PlayerDisplay.PlayerName.Text = `@{player.Name}`
	player.Character.PlayerDisplay.PlayerSize.Text = `Size: {Size.Value}`

	Size.Changed:Connect(function()
		applyRankText(player)
		Progression.CheckSize(player)
	end)

	newModel.PrimaryPart.Touched:Connect(function(other)
		local otherPlayer = Players:GetPlayerFromCharacter(other.Parent)
		if not otherPlayer then return end
		local otherPlayerSize = otherPlayer.leaderstats.Size
		if otherPlayerSize.Value > player.leaderstats.Size.Value then
			newModel.Humanoid.Health = 0
			player:SetAttribute("Killer", otherPlayer.UserId)
		else
			local otherPlayerCharacter = otherPlayer.Character
			otherPlayerCharacter.Humanoid.Health = 0
			otherPlayer:SetAttribute("Killer", player.UserId)
			Progression.AddProgress(player, "kill", 1)
		end
	end)

	for _, object in game.StarterPlayer.StarterCharacterScripts:GetChildren() do
		local newObject = object:Clone()
		newObject.Parent = newModel
	end

	setupVisuals(player)
	oldModel:Destroy()
end

ReplicatedStorage.Events.RespawnRequest.OnServerEvent:Connect(function(player)
	Respawn(player)
	player.leaderstats.Size.Value = 0
end)

Main.PlayerSetup = function(player: Player)
	local profile
	player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		profile = Manager.Profiles[player]
	end)

	local CharacterClone = ServerStorage.Character:Clone()
	CharacterClone.Parent = workspace
	CharacterClone.Name = player.Name
	CharacterClone.PrimaryPart.Color = Color3.fromRGB(math.random(1, 255), math.random(1, 255), math.random(1, 255))
	player.Character = CharacterClone

	for _, object in game.StarterPlayer.StarterCharacterScripts:GetChildren() do
		local newObject = object:Clone()
		newObject.Parent = CharacterClone
	end

	local Spawns = workspace.Spawns:GetChildren()
	local randomSpawn = Spawns[math.random(1, #Spawns)]
	CharacterClone:PivotTo(randomSpawn:GetPivot())

	CharacterClone.Humanoid.Died:Connect(function()
		CharacterClone.PrimaryPart.Transparency = 1
		CharacterClone.PrimaryPart.CanCollide = false
		CharacterClone.PrimaryPart.Anchored = true
	end)

	if MarketPlaceService:UserOwnsGamePassAsync(player.UserId, 976477890) then
		CharacterClone.Humanoid.WalkSpeed = CharacterClone.Humanoid.WalkSpeed * 2
	end
	if MarketPlaceService:UserOwnsGamePassAsync(player.UserId, 976285751) then
		player:SetAttribute("2xMoney", true)
	end

	player:SetAttribute("PlayerTime", 0)
	player:SetAttribute("CurrentGift", 0)
	coroutine.wrap(function()
		while task.wait(1) do
			player:SetAttribute("PlayerTime", player:GetAttribute("PlayerTime") + 1)
		end
	end)()

	CharacterClone.PrimaryPart.Touched:Connect(function(other)
		local otherPlayer = Players:GetPlayerFromCharacter(other.Parent)
		if not otherPlayer then return end
		local otherPlayerSize = otherPlayer.leaderstats.Size
		if otherPlayerSize.Value > player.leaderstats.Size.Value then
			CharacterClone.Humanoid.Health = 0
			player:SetAttribute("Killer", otherPlayer.UserId)
		else
			local otherPlayerCharacter = otherPlayer.Character
			otherPlayerCharacter.Humanoid.Health = 0
			otherPlayer:SetAttribute("Killer", player.UserId)
			Progression.AddProgress(player, "kill", 1)
		end
	end)

	local ls = player:WaitForChild("leaderstats")
	local Size = ls:WaitForChild("Size")
	Size.Changed:Connect(function()
		applyRankText(player)
		Progression.CheckSize(player)
	end)

	task.wait(0.1)
	setupVisuals(player)
end

MarketPlaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, wasPurchased)
	if not wasPurchased then return end
	if id == 976477890 then
		if player.Character then player.Character.Humanoid.WalkSpeed = player.Character.Humanoid.WalkSpeed * 2 end
	elseif id == 976285751 then
		player:SetAttribute("2xMoney", true)
	end
end)

local playerStates = {}

-- Automatically move character to closest food
Main.AutoFarm = function(player: Player, enabled: boolean)
	playerStates[player.UserId] = enabled
	if enabled then
		coroutine.wrap(function()
			while playerStates[player.UserId] do
				if not player.Character then task.wait(0.5) continue end
				local character = player.Character
				local rootpart = character.HumanoidRootPart
				local closestFood
				local closestDistance = math.huge
				for _, food in workspace.FoodParts:GetChildren() do
					if food:IsA("BasePart") and food.CanTouch == false then continue end
					local distance = (rootpart.Position - food.Position).Magnitude
					if distance < closestDistance then
						closestDistance = distance
						closestFood = food
					end
				end
				if closestFood then
					character.Humanoid:MoveTo(closestFood.Position)
				end
				task.wait(0.5)
			end
		end)()
	else
		playerStates[player.UserId] = false
	end
end

-- Eat a cube -> grow with soft diminishing returns + rebirth multiplier
Main.IncreaseSize = function(player, amount: number)
	local profile = Manager.Profiles[player]
	if not profile then return end
	if player:GetAttribute("2xMoney") then
		profile.Data.Cash += 2
	else
		profile.Data.Cash += 1
	end
	player.leaderstats.Cash.Value = profile.Data.Cash

	local Size = player:FindFirstChild("leaderstats"):FindFirstChild("Size")
	local mult = profile.Data.RebirthMult or 1
	Size.Value = Size.Value + (1 + amount * 50) * mult

	Progression.setCubeSize(player.Character, Config.visualSize(Size.Value))
	applyRankText(player)
	Progression.CheckSize(player)
end

return Main
