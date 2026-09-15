local VIPDOOR = workspace:WaitForChild("VIPDoor")

if game:GetService("MarketplaceService"):UserOwnsGamePassAsync(game.Players.LocalPlayer.UserId, 975187916) then
	VIPDOOR.CanCollide = false
end

game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player, id, wasPurchased)
	if not wasPurchased then return end
	if id == 975187916 then
		VIPDOOR.CanCollide = false
	end
end)