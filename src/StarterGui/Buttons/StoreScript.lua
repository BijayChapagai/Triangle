local MarketplaceService = game:GetService('MarketplaceService')
local Player = game:GetService('Players').LocalPlayer
	
local function Init()
	local StoreButtons = script.Parent.Store:GetChildren()
	
	for i, Button in StoreButtons do
		if not Button:IsA('GuiButton') then continue end
		
		Button.Activated:Connect(function()
			MarketplaceService:PromptProductPurchase(Player, Button:GetAttribute('ProductId'))
		end)
	end
end
Init()