local MarketPlaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manager = require(script.Parent.Data.Manager)

local MAX_SIZE = 40

local products = {
	[2662840537] = function(player: Player)
		local Size = player:FindFirstChild("leaderstats"):FindFirstChild("Size")
		Size.Value += 5000
		local character = player.Character
		if character.PrimaryPart.Size.Y >= MAX_SIZE then
			print("Max Size Reached")
			return true
		else
			character.PrimaryPart.Size += Vector3.new(Size.Value / 10000, Size.Value / 10000, Size.Value / 10000)
		end

		return true
	end,
	[2662840538] = function(player)
		local Size = player:FindFirstChild("leaderstats"):FindFirstChild("Size")
		Size.Value += 25000
		local character = player.Character
		if character.PrimaryPart.Size.Y >= MAX_SIZE then
			print("Max Size Reached")
			return true
		else
			character.PrimaryPart.Size += Vector3.new(Size.Value / 10000, Size.Value / 10000, Size.Value / 10000)
		end

		return true
	end,
	[2660172572] = function(player)
		local Size = player:FindFirstChild("leaderstats"):FindFirstChild("Size")
		Size.Value += 80000
		local character = player.Character
		if character.PrimaryPart.Size.Y >= MAX_SIZE then
			print("Max Size Reached")
			return true
		else
			character.PrimaryPart.Size += Vector3.new(Size.Value / 10000, Size.Value / 10000, Size.Value / 10000)
		end

		return true
	end,
	[2662841571] = function(player)
		for _, v in Players:GetPlayers() do
			v.Character.Humanoid.Health = 0
		end
		return true
	end,
	[2662841572] = function(player : Player) -- revive
		local OriginalSize = player:FindFirstChild("leaderstats"):FindFirstChild("Size")
		
		local newCharacter = ServerStorage.Character
		local oldModel = player.Character

		local newModel = newCharacter:Clone()
		newModel.Name = player.Name
		player.Character = newModel
		newModel.Parent = workspace
		newModel.PrimaryPart.Size = oldModel.PrimaryPart.Size
		local Spawns = workspace.Spawns:GetChildren()
		local randomSpawn = Spawns[math.random(1, #Spawns)]

		newModel:PivotTo(randomSpawn:GetPivot())

		for _, object in game.StarterPlayer.StarterCharacterScripts:GetChildren() do
			local newObject = object:Clone()
			newObject.Parent = newModel
		end
		oldModel:Destroy()
		return true
	end,
	[2662841573] = function(player : Player)
		local Killer = player:GetAttribute("Killer")
		if Killer ~= nil then
			local otherPlayer = Players:GetPlayerByUserId(Killer)
			if otherPlayer then
				local otherplayerCharacter = otherPlayer.Character
				otherplayerCharacter.Humanoid.Health = 0
				otherPlayer.leaderstats.Size.Value = 0
			end
		end
		
		return true
	end,
}

MarketPlaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local success, result = pcall(products[info.ProductId], player)
	if not success or not result then warn("Error for product "..result) return Enum.ProductPurchaseDecision.NotProcessedYet end
	
	return Enum.ProductPurchaseDecision.PurchaseGranted
end