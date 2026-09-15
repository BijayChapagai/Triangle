local ProductId = 2662841571

local Player = game.Players.LocalPlayer
local MarketplaceService = game:GetService("MarketplaceService")
script.Parent.KillAllButton.MouseButton1Click:Connect(function()
	MarketplaceService:PromptProductPurchase(Player, ProductId)
end)

local SizeLabel = script.Parent.SizeCounter.CurrentSize

local Formatter = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("FormatNumberAlt"))

SizeLabel.Text = Player:WaitForChild("leaderstats"):WaitForChild("Size").Value
Player:WaitForChild("leaderstats"):WaitForChild("Size").Changed:Connect(function()
	SizeLabel.Text = Formatter.FormatCompact(Player:WaitForChild("leaderstats"):WaitForChild("Size").Value)
end)

local AutoFarmBtn = script.Parent.AutoFarm

local autoEnabled = false

AutoFarmBtn.Activated:Connect(function()
	autoEnabled = not autoEnabled
	if not autoEnabled then
		AutoFarmBtn.Text = "Auto Farm: OFF"
		AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		game:GetService("ReplicatedStorage").Events:WaitForChild("AutoFarm"):FireServer(false)
	else
		AutoFarmBtn.Text = "Auto Farm: ON"
		AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		game:GetService("ReplicatedStorage").Events:WaitForChild("AutoFarm"):FireServer(true)
	end
end)