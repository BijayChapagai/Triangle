local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketPlaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local character = script.Parent
local humanoid : Humanoid = character:WaitForChild("Humanoid")
local DeathGUI = player.PlayerGui:WaitForChild("DeathGui")

humanoid.Died:Connect(function()
	DeathGUI.Enabled = true
	DeathGUI.DeathFrame.Content.Buttons.Row2.Revive.Details.Text = "+"..player:WaitForChild("leaderstats"):FindFirstChild("Size").Value.." Size"
	local killer = player:GetAttribute("Killer")
	if killer ~= nil then
		DeathGUI.DeathFrame.Content.Buttons.Row2.Revenge.Details.Text = "KILL: "..Players:GetPlayerByUserId(player:GetAttribute("Killer")).Name
		DeathGUI.DeathFrame.Content.DeathInfo.Text = `You died to <font color="rgb(255,0,0)">{Players:GetPlayerByUserId(player:GetAttribute("Killer")).Name}</font> and lost <font color="rgb(255,0,255)">{player:WaitForChild("leaderstats").Size.Value}</font> size!`
	else
		DeathGUI.DeathFrame.Content.Buttons.Row2.Revenge.Details.Text = "KILL: NoOne"
		DeathGUI.DeathFrame.Content.DeathInfo.Text = `You died to <font color="rgb(255,0,0)">Unknown</font> and lost <font color="rgb(255,0,255)">{player:WaitForChild("leaderstats").Size.Value}</font> size!`
	end
end)

DeathGUI.DeathFrame.Content.Buttons.Row1.Respawn.Activated:Connect(function()
	ReplicatedStorage.Events:WaitForChild("RespawnRequest"):FireServer()
	DeathGUI.Enabled = false
end)

DeathGUI.DeathFrame.Content.Buttons.Row2.Revive.Activated:Connect(function()
	MarketPlaceService:PromptProductPurchase(player, 2662841572)
end)

DeathGUI.DeathFrame.Content.Buttons.Row2.Revenge.Activated:Connect(function()
	MarketPlaceService:PromptProductPurchase(player, 2662841573)
end)

MarketPlaceService.PromptProductPurchaseFinished:Connect(function(userId, product, isPurchased)
	if not isPurchased then return end
	if product == 2662263658 then
		print("Remove frame")
		DeathGUI.Enabled = false
	end
end)