local id = 975187916
local MarketPlaceService = game:GetService("MarketplaceService")

script.Parent.MouseClick:Connect(function(player)
	MarketPlaceService:PromptGamePassPurchase(player,id)
end)