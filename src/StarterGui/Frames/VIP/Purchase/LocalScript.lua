local marketplaceService = game:GetService("MarketplaceService")

local player = game.Players.LocalPlayer

local uiModule = require(game.ReplicatedStorage.UiModule)
uiModule.Animate(script.Parent)

local function PromptGamepass(gamepassID, buyButton)
	local hasPass = false

	local success, errorMsg = pcall(function()
		hasPass = marketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassID)
	end)

	if not success then	return end

	if hasPass then
		buyButton.Text = "Already Own"
		wait(3)
		buyButton.Text = "Buy"
	else
		marketplaceService:PromptGamePassPurchase(player, gamepassID)
	end
end

script.Parent.MouseButton1Click:Connect(function()
	PromptGamepass(975187916, script.Parent)
end)