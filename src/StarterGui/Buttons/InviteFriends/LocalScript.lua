local button = script.Parent
local SocialService = game:GetService("SocialService")
local player = game.Players.LocalPlayer

function onButtonPressed()
	local success, resoult = pcall (
		function()
			return SocialService:CanSendGameInviteAsync(player)
		end
	)

	if resoult == true then
		SocialService:PromptGameInvite(player)
	end
end

button.MouseButton1Click:Connect(onButtonPressed)
button.TouchTap:Connect(onButtonPressed)